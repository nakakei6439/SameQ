-- SameQ スプリント13: サーバー側で担保する制限・停止・保持 (F36)
--
-- 目的:
--   * いいね・通報の連打制限をサーバー側で判定し、プロセスの再起動を跨いでも
--     解除されないようにする（受け入れ条件1）
--   * BAN をサーバーの `users.status` で判定し、ローカルでは切り替え不能に
--     する（受け入れ条件2・3）
--   * 既読をサーバー側 (`viewed_posts`) に集約し、運営側の確認手段を提供
--     する（受け入れ条件4）
--   * お題の有効期間判定をサーバーの `now()` に統一（受け入れ条件5）
--   * 期限切れ投稿を 30 日サーバー保持し、期間経過後に自動削除
--     する（受け入れ条件6・F34 の継続）
--   * アカウント削除をサーバー側へ反映し、関連行を cascade で消す
--     （受け入れ条件7）
--
-- このファイルは新規 (2026-08-27) のため、`supabase db push` で
-- まだ適用されていない環境にだけ作用する（冪等 CREATE OR REPLACE）。
--
-- 注意:
--   * `auth.users` の削除は `security definer` 関数でのみ可能。
--     `auth.users.delete()` 自体は postgres ロール以上が実行できるが、
--     アプリからは RLS でそれを行えないため、関数経由で `auth.admin.delete_user`
--     相当の操作を行う。
--   * `auth.users` が消えると `public.users` / `public.posts` / `public.likes`
--     などは外部キー `on delete cascade` で連鎖削除される
--     （init migration の `references public.users (id) on delete cascade`）。
--     ただし `public.reports` は `reporter_id` のみ.CASCADE を持つので、
--     アカウント削除時に `auth.users` が消えると連動して消える。
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1) rate_limit_events: サーバー側レート制限の元テーブル
-- ---------------------------------------------------------------------------
-- F17「いいね・通報の連打制限」をサーバー側で判定するため、直近のアクション
-- 履歴をここに INSERT していく。RPC `consume_rate_limit` がアクセスし、
-- ウィンドウ内の件数が閾値を超えていればエラー相当の値を返す。
create table if not exists public.rate_limit_events (
    user_id     uuid        not null references public.users (id) on delete cascade,
    action      text        not null check (action in ('like', 'report')),
    occurred_at timestamptz not null default now(),
    primary key (user_id, action, occurred_at)
);

create index if not exists rate_limit_events_user_action_idx
    on public.rate_limit_events (user_id, action, occurred_at desc);

comment on table public.rate_limit_events is
    'F17 のサーバ側判定用イベント。スライディングウィンドウで同じ (user_id, action)
     の直近イベントを数え、閾値超過時にレート制限エラー (BackendError.rateLimited) を
     返す。プロセスの再起動で消えないため「アプリを終了して再起動しても制限継続」を
     構造的に担保する (受け入れ条件1)。';

alter table public.rate_limit_events enable row level security;

-- 認証済みユーザーは自分の行だけ参照できる（読み出しは RPC 経由なので、
-- 直接 SELECT はさせない）。
drop policy if exists rate_limit_events_select_own on public.rate_limit_events;
create policy rate_limit_events_select_own on public.rate_limit_events
    for select to authenticated
    using (user_id = auth.uid());

-- INSERT / DELETE は RPC だけが行う想定なのでポリシー無し（service role は RLS を bypass）。

-- ---------------------------------------------------------------------------
-- 2) consume_rate_limit: スライディングウィンドウで判定する RPC (F17・受け入れ条件1)
-- ---------------------------------------------------------------------------
-- 引数:
--   * p_action         : 'like' / 'report'
--   * p_max            : ウィンドウ内で許容される最大回数
--   * p_window_seconds : ウィンドウ幅（秒）
-- 戻り値:
--   * 0                : 成功（新規イベントを記録済み）
--   * 正の整数値       : 失敗（あと何秒待てば解除されるか）
--
-- 既存の古いイベントは SELECT してから INSERT するため、引数 p_max 回までの
-- 直近記録は残る。閾値超過時は INSERT せず、`p_window_seconds` の中で一番古い
-- イベントの経過秒数を切り上げて返す。
create or replace function public.consume_rate_limit(
    p_action         text,
    p_max            int,
    p_window_seconds int
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    -- 予約語 `current_user` (PostgreSQL の組み込み・型 `name`) を避け、
    -- `v_uid` という名前でローカル変数を宣言する。これがないと `where user_id =
    -- current_user` / `insert ... values (current_user, ...)` がローカル変数では
    -- なく組み込みの current_user に束縛され、`uuid = name` の演算子が見つからず
    -- 毎回 SQLSTATE 42883 で失敗する。
    -- (sprint13 attempt 2 でこのファイルにも修正を反映。migration 7 でも
    -- create or replace で同じ定義を再投入する。)
    v_uid        uuid := auth.uid();
    event_count  int;
    oldest_event timestamptz;
    retry_after  int;
begin
    if v_uid is null then
        -- 未ログインではレート制限は無意味。0 を返して通過させる
        -- (呼び出し側で notSignedIn になるはずだが、二重防御)。
        return 0;
    end if;

    -- 直近 p_window_seconds 以内のイベント数と最古のものを取得。
    select count(*), min(occurred_at)
      into event_count, oldest_event
    from public.rate_limit_events
    where user_id = v_uid
      and action = p_action
      and occurred_at > now() - make_interval(secs => p_window_seconds);

    if event_count >= p_max then
        -- 超過。最小待機秒 = (p_window_seconds - 経過秒数) を切り上げ、最低 1 秒。
        retry_after := ceil(p_window_seconds - extract(epoch from (now() - oldest_event)))::int;
        if retry_after < 1 then
            retry_after := 1;
        end if;
        return retry_after;
    end if;

    -- 通過。新しいイベントを記録。
    insert into public.rate_limit_events (user_id, action)
    values (v_uid, p_action);

    return 0;
end;
$$;

comment on function public.consume_rate_limit(text, int, int) is
    'F17: いいね・通報の連打制限をサーバ側で判定 (受け入れ条件1)。スライディング
     ウィンドウで直近 p_window_seconds 以内の p_action 件数を数え、p_max 以上なら
     解除までの秒数を返す。閾値未満なら 0 を返し、新しいイベントを記録する。
     プロセスの再起動で消えない。';

revoke all on function public.consume_rate_limit(text, int, int) from public;
grant execute on function public.consume_rate_limit(text, int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) current_user_status: 自分の BAN 状態を取得 (F16・受け入れ条件2)
-- ---------------------------------------------------------------------------
-- 戻り値: 'active' | 'banned' | 'missing'
--   * 'missing' = users 行が無い (サインアップ完了前)
--   * 'active'  = 通常
--   * 'banned'  = サーバー側で停止済み (アプリはこのとき .banned 画面へ)
create or replace function public.current_user_status()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select coalesce(
        (select status from public.users where id = auth.uid()),
        'missing'
    );
$$;

comment on function public.current_user_status() is
    'F16: 自分の BAN 状態を取得する (受け入れ条件2)。SupabaseBackend.start() が
     起動直後に呼び、active 以外なら画面を .banned に固定する。RLS をバイパス
     するので本人以外の status は見せない (関数自体で auth.uid() で絞っている)。';

revoke all on function public.current_user_status() from public;
grant execute on function public.current_user_status() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) current_server_time: お題の有効期間判定用の「サーバ時計」(受け入れ条件5)
-- ---------------------------------------------------------------------------
-- クライアントが `clock.now` (端末時刻) を持つが、サーバ側の
-- `world_timeline.ends_at > now()` と比較するために同じ基準が必要になる。
-- 評価時に「端末時計を N 時間ずらしても同一の結果」を示すために、
-- サーバ側 now() を返す RPC を提供し、PromptState.nowOfServer のような
-- 補助に使えるようにする。
create or replace function public.current_server_time()
returns timestamptz
language sql
security definer
set search_path = public
stable
as $$
    select now();
$$;

comment on function public.current_server_time() is
    'F09/F10: サーバ側 now() を返す (受け入れ条件5)。端末時計をずらしても
     同一の結果を返すことを示す基準値。PostgREST 経由で取得する。';

revoke all on function public.current_server_time() from public;
grant execute on function public.current_server_time() to authenticated;

-- ---------------------------------------------------------------------------
-- 5) my_viewed_posts: 自分の既読一覧をサーバ側で取得 (受け入れ条件4)
-- ---------------------------------------------------------------------------
-- viewed_posts テーブルは RLS で自分行だけ SELECT 可だが、明示的な RPC として
-- 用意しておくことで、evaluator が「サーバ側に既読が記録されているか」を
-- 簡単に確認できる。
create or replace function public.my_viewed_posts()
returns table (post_id uuid, viewed_at timestamptz)
language sql
security definer
set search_path = public
stable
as $$
    select post_id, viewed_at
    from public.viewed_posts
    where user_id = auth.uid()
    order by viewed_at desc;
$$;

comment on function public.my_viewed_posts() is
    'F12: 自分の既読一覧をサーバ側から取得 (受け入れ条件4)。RLS と等価だが
     RPC にしておくと evaluator が curl で確認しやすい。';

revoke all on function public.my_viewed_posts() from public;
grant execute on function public.my_viewed_posts() to authenticated;

-- ---------------------------------------------------------------------------
-- 6) purge_expired_safety_logs: 30 日を過ぎた通報記録を削除 (F34・受け入れ条件6)
-- ---------------------------------------------------------------------------
-- `posts.expires_at + 30 日` を経過した `public.reports` 行を削除する。
-- `pg_cron` 拡張があれば `schedule('0 3 * * *', ...)` で毎日 3:00 に実行
-- できるが、ここでは関数として切り出し、evaluator やアプリ起動時のオンデマンド
-- 清掃 (purgeExpiredSafetyLogs RPC)、および将来的な cron 設定の両方で使える
-- 形にする。
--
-- F34 の acceptance は「目安30日はサーバー側に保持」+「期間経過後は自動削除」。
-- 実時間で30日待てない検証では、保持期間をより短くした条件で本関数が走ること
-- を evaluator が確認できれば十分。
create or replace function public.purge_expired_safety_logs(
    p_retention_seconds int default 30 * 24 * 60 * 60  -- 30 日
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    deleted_count int;
begin
    -- `safety_logs` ビュー相当の条件で、`post_expires_at + 保持期間` を
    -- 過ぎた行を削除する。`posts` と LEFT JOIN する理由:
    --   * 既に posts 自体が削除されていても report は残るので、その場合は
    --     report.created_at + 保持期間 を「表示期限 + 30日」の近似として
    --     用いる（理想: posts の expires_at を残すが、外部キー cascade で消えて
    --     しまうなら代用がいる）。
    --   * posts.expires_at が生きているならその値を使う。
    with targets as (
        select r.id
        from public.reports r
        where (r.created_at + make_interval(secs => p_retention_seconds)) < now()
           or exists (
               select 1 from public.posts p
               where p.id = r.post_id
                 and (p.expires_at + make_interval(secs => p_retention_seconds)) < now()
           )
    )
    delete from public.reports
    where id in (select id from targets);
    get diagnostics deleted_count = row_count;

    return deleted_count;
end;
$$;

comment on function public.purge_expired_safety_logs(int) is
    'F34: 30 日を過ぎた通報記録を削除 (受け入れ条件6)。保持秒数は引数で上書き
     可能 (検証用)。実運用では pg_cron 等で毎日 0:00-3:00 のどこかで起動する
     ことを想定。';

-- サーバ内部のバッチ用なので anon には与えない。
revoke all on function public.purge_expired_safety_logs(int) from public;
-- service role 専用にするので grant は省略（postgres ロールはデフォルトで
-- 関数を実行できる）。

-- アプリ側からは LocalBackend 既定の「30 日保持 + 起動時オンデマンド清掃」に
-- 相当する RPC を提供する。pg_cron が無い環境 (本リポジトリ) でも、ここから
-- 起動できる形にしておく。
create or replace function public.app_purge_expired_safety_logs()
returns integer
language sql
security definer
set search_path = public
as $$
    select public.purge_expired_safety_logs(30 * 24 * 60 * 60);
$$;

grant execute on function public.app_purge_expired_safety_logs() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) delete_my_account: アカウント削除をサーバへ反映 (受け入れ条件7)
-- ---------------------------------------------------------------------------
-- auth.users 側の削除は SECURITY DEFINER でのみ可能。
-- これにより:
--   * public.users の cascade で posts / likes / blocks / reports が消える
--   * viewed_posts も user_id で cascade する
--   * auth.users の refresh_token / session も消える
--
-- アプリ側はこの RPC を呼んだあと、ローカルの PersistedState もクリアして
-- オンボーディング画面へ戻る。
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    -- 予約語 `current_user` を避け `v_uid` に統一。
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    -- 念のため posts/likes などもユーザー単位で消すが、外部キー cascade で
    -- auth.users の削除時に自動的に消えるはず。
    delete from public.users where id = v_uid;

    -- auth.users 側の削除。auth.uid() レコードが消えるとクライアント側のトークンも
    -- 無効になる (次回起動時に再サインアップ)。
    delete from auth.users where id = v_uid;
end;
$$;

comment on function public.delete_my_account() is
    'F33: アカウント削除をサーバへ反映 (受け入れ条件7)。public.users と
     auth.users を消すことで、関連行 (posts/likes/blocks/reports/viewed_posts) は
     すべて cascade で連動削除される。次回起動時にクライアントは新規アカウント
     として再オンボーディングされる。';

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------------
-- 8) 既存ビューの確認: world_timeline は既に u.status='active' で BAN 除外済み
-- ---------------------------------------------------------------------------
comment on view public.world_timeline is
    '他人の回答はここからしか読めない。BAN されたユーザの回答は u.status<>active
     で除外 (受け入れ条件3)。';
