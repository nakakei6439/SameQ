-- SameQ スプリント13 attempt 2: サーバー側制限/停止/保持の修正 (F36)
--
-- 背景:
--   evaluator attempt 1 で発見された致命的欠陥を修正する。
--   * `consume_rate_limit` と `delete_my_account` がローカル変数名に
--     PostgreSQL の予約語 `current_user` を使っていたため、関数実行時に
--     毎回 SQLSTATE 42883 "operator does not exist: uuid = name" で
--     失敗していた（eval-1.md [1]）。
--     連打制限・アカウント削除が一切機能せず、その副作用で Supabase 経由の
--     いいね・通報 (`setLike` / `reportPost`) が `checkRateLimit` の
--     throw を伝播して完全停止していた（スプリント12 の条件3 を回帰）。
--   * `users_update_own` ポリシーが USING 句で `status='active'` を
--     絞っていなかったため、BAN されたアカウントが REST 1 発で自分の
--     BAN を解除できていた（eval-1.md [2]）。
--
-- 方針:
--   * 関数名・RPC 名は変えず、ローカル変数だけ予約語でない名前に全置換する。
--   * `create or replace` を使い、定義だけを差し替える（GRANT 等は温存）。
--   * `users_update_own` ポリシーを drop して status 条件付き USING で
--     再作成する。banned 行はオーナーからも一切 UPDATE 不能になる
--     （emoji/nickname 変更も停止中は不可になるが、これは条件2 を満たす
--     ための素直な選択）。
--   * pg_cron 拡張が有効なら safety_logs 自動削除スケジュールを登録する。
--     拡張が無効の環境ではコメントでスケジュール SQL を残し、Supabase
--     ダッシュボードからの有効化と 1 回の手動 SQL を申し送る。
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1) consume_rate_limit: ローカル変数を予約語以外に置換 (eval-1.md [1])
-- ---------------------------------------------------------------------------
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
    -- 予約語 `current_user` (PostgreSQL の組み込み。型 `name`) を避け、
    -- ローカル変数名を `v_uid` に変更する。これで `where user_id = v_uid`
    -- / `insert into ... values (v_uid, ...)` が uuid 比較に戻る。
    v_uid         uuid := auth.uid();
    event_count   int;
    oldest_event  timestamptz;
    retry_after   int;
begin
    if v_uid is null then
        return 0;
    end if;

    select count(*), min(occurred_at)
      into event_count, oldest_event
    from public.rate_limit_events
    where user_id = v_uid
      and action = p_action
      and occurred_at > now() - make_interval(secs => p_window_seconds);

    if event_count >= p_max then
        retry_after := ceil(p_window_seconds - extract(epoch from (now() - oldest_event)))::int;
        if retry_after < 1 then
            retry_after := 1;
        end if;
        return retry_after;
    end if;

    insert into public.rate_limit_events (user_id, action)
    values (v_uid, p_action);

    return 0;
end;
$$;

comment on function public.consume_rate_limit(text, int, int) is
    'F17 (sprint13 fix): いいね・通報の連打制限をサーバ側で判定。スライディング
     ウィンドウで直近 p_window_seconds 以内の p_action 件数を数え、p_max 以上なら
     解除までの秒数を返す。閾値未満なら 0 を返し、新しいイベントを記録する。
     attempt 1 でローカル変数に予約語 `current_user` を使っていたため
     `operator does not exist: uuid = name` (SQLSTATE 42883) で毎回失敗していた
     不具合を、予約語以外 (`v_uid`) への置換で解消。';

-- GRANT は migration 6 で既に付与済みなので再付与は不要。

-- ---------------------------------------------------------------------------
-- 2) delete_my_account: ローカル変数を予約語以外に置換 (eval-1.md [1])
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    -- `current_user` (PostgreSQL の組み込み・予約語・型 `name`) を避け、
    -- ローカル変数名を `v_uid` に変更する。
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'not signed in' using errcode = '28000';
    end if;

    delete from public.users where id = v_uid;
    delete from auth.users where id = v_uid;
end;
$$;

comment on function public.delete_my_account() is
    'F33 (sprint13 fix): アカウント削除をサーバへ反映。public.users と
     auth.users を消すことで、関連行 (posts/likes/blocks/reports/viewed_posts) は
     すべて cascade で連動削除される。attempt 1 の予約語 `current_user`
     起因の SQLSTATE 42883 を `v_uid` への置換で解消。';

-- ---------------------------------------------------------------------------
-- 3) users_update_own: USING に status='active' を追加 (eval-1.md [2])
-- ---------------------------------------------------------------------------
-- 旧: using (id = auth.uid())
-- 新: using (id = auth.uid() and status = 'active')
-- これで banned 行はオーナーからでも一切 UPDATE できなくなる
-- （emoji/nickname の編集も停止中は不可になるが、条件2 「ローカルでは
-- 切り替え不能」を素直に満たす形）。
drop policy if exists users_update_own on public.users;
create policy users_update_own on public.users
    for update to authenticated
    using (id = auth.uid() and status = 'active')
    with check (id = auth.uid() and status = 'active');

-- ---------------------------------------------------------------------------
-- 4) pg_cron による safety logs 自動削除スケジュール (eval-1.md [4])
-- ---------------------------------------------------------------------------
-- pg_cron 拡張が有効なら、毎日 03:00 UTC に `purge_expired_safety_logs(30日)` を
-- 実行するジョブを登録する。拡張が無効の環境（既定の Supabase プロジェクト
-- ではダッシュボードから Extensions → pg_cron を ON にする必要あり）では
-- このブロックは無視され、コメントで残した SQL を 1 回手動で流す必要がある。
do $$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        -- 同じ名前の既存スケジュールを消してから再作成（冪等）。
        perform cron.unschedule('purge-safety-logs-daily');
        perform cron.schedule(
            'purge-safety-logs-daily',
            '0 3 * * *',
            $sql$select public.purge_expired_safety_logs(30 * 24 * 60 * 60);$sql$
        );
    end if;
end;
$$;

comment on extension pg_cron is
    'sprint13 fix: pg_cron が有効なら、毎日 03:00 UTC に期限切れ safety logs を
     自動削除するスケジュール `purge-safety-logs-daily` を登録する。';

-- pg_cron が**無い**環境で手動スケジュールしたい場合の SQL (コメント):
--   select cron.schedule(
--       'purge-safety-logs-daily',
--       '0 3 * * *',
--       $$select public.purge_expired_safety_logs(30 * 24 * 60 * 60);$$
--   );
-- 拡張を有効化する場所は Supabase ダッシュボードの Database → Extensions。
