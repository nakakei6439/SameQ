-- SameQ スプリント13 attempt 3: サーバー側制限/停止/保持の**決定版**修正 (F36)
--
-- 背景:
--   eval-2.md で次の問題が確認された:
--     [1] migration 7 (20260827000007) の `comment on extension pg_cron is …`
--         が do ブロックの外にあったため、pg_cron 拡張が無い本番で SQLSTATE
--         42704 が出てファイル全体がロールバックされ、migration 7 内の**他の
--         修正** (`consume_rate_limit` / `delete_my_account` / `users_update_own`)
--         も一切本番に乗っていなかった。
--
--   このファイル (migration 8) は:
--     * 上記 [1] で migration 7 が本番に乗らないケースに備え、同じ修正を**こ
--       のファイルでも** `create or replace` 付きで再投入する。Supabase CLI の
--       仕様上「適用済み」になった migration は再走しないため、migration 8 は
--       migration 7 が結果的にロールバックされた環境でも、これから db push す
--       るだけで必ず適用される。
--     * `purge_expired_safety_logs(int)` を一般ユーザーから実行できないよう
--       GRANT を明示的に閉じる (eval-2.md 改善提案1)。任意ユーザーが
--       `p_retention_seconds=0` で `reports` を全消しできてしまう穴を防ぐ。
--       アプリ起動時のオンデマンド清掃は `app_purge_expired_safety_logs()`
--       経由だけが authorized になる。
--     * 既存ファイル (20260827000006 / 20260827000007) に既に同じ修正が書かれ
--       ていても、`create or replace` は冪等なので重複適用は安全。
--
-- 受け入れ条件との対応:
--   * 受け入れ条件1 (連打制限のサーバ側判定・再起動で解除されない)
--     → `consume_rate_limit` の予約語バグを `create or replace` で再投入
--   * 受け入れ条件2 (BAN がサーバ側 users.status で判定・切替不能)
--     → `users_update_own` の USING に status='active' を再投入
--   * 受け入れ条件7 (アカウント削除が他端末へ伝播)
--     → `delete_my_account` の予約語バグを `create or replace` で再投入
--   * 受け入れ条件6 (期限切れ safety logs の 30 日保持・自動削除)
--     → `purge_expired_safety_logs(int)` を postgres / service_role 専用に限定
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1) consume_rate_limit: ローカル変数を予約語以外に置換 (eval-1.md [1] の再投入)
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
    -- 予約語 `current_user` (PostgreSQL の組み込み・型 `name`) を避け、
    -- ローカル変数名を `v_uid` に統一する。これで `where user_id = v_uid`
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
    'F17 (sprint13 fix v2): 連打制限をサーバ側で判定 (受け入れ条件1)。attempt 1 で
     ローカル変数に予約語 `current_user` を使っていたため `operator does not exist:
     uuid = name` (SQLSTATE 42883) で毎回失敗していた不具合を、予約語以外 (`v_uid`)
     への置換で解消。migration 8 として再投入することで、migration 7 が pg_cron
     起因でロールバックされた環境でもこの修正が必ず乗る。';

-- ---------------------------------------------------------------------------
-- 2) delete_my_account: ローカル変数を予約語以外に置換 (eval-1.md [1] の再投入)
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    -- 予約語 `current_user` を避け `v_uid` に統一 (eval-1.md [1])。
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
    'F33 (sprint13 fix v2): アカウント削除をサーバへ反映 (受け入れ条件7)。
     attempt 1 の予約語 `current_user` 起因の SQLSTATE 42883 を `v_uid`
     への置換で解消。migration 8 として再投入することで、migration 7 が
     ロールバックされた環境でもこの修正が必ず乗る。';

-- ---------------------------------------------------------------------------
-- 3) users_update_own: USING に status='active' を追加 (eval-1.md [2] の再投入)
-- ---------------------------------------------------------------------------
-- 旧: using (id = auth.uid())
-- 新: using (id = auth.uid() and status = 'active')
-- これで banned 行はオーナーからでも一切 UPDATE できなくなる (受け入れ条件2)。
drop policy if exists users_update_own on public.users;
create policy users_update_own on public.users
    for update to authenticated
    using (id = auth.uid() and status = 'active')
    with check (id = auth.uid() and status = 'active');

-- ---------------------------------------------------------------------------
-- 4) purge_expired_safety_logs の grant を明示的に閉じる (eval-2.md 改善提案1)
-- ---------------------------------------------------------------------------
-- 背景:
--   migration 6 で
--     revoke all on function public.purge_expired_safety_logs(int) from public;
--     -- grant は省略
--   としたが、`security definer` 関数はデフォルトで `public` に EXECUTE が
--   付与されている扱いになり、`revoke ... from public` だけでは authenticated
--   からの実行を完全には止められない (Supabase の関数自動公開が上書きする疑い)。
--   実測 (eval-2.md) では `purge_expired_safety_logs(60)` を認証トークンで
--   呼ぶと HTTP 200 で reports が 4 行消えた。一般ユーザーが任意保持期間で
--   `reports` を消せてしまうのは F34 の趣旨に対する明確な穴。
--
-- 修正:
--   1) anon / authenticated から execute 権限を明示的に剥奪
--   2) 引数に最低保持秒数 (例 1 日 = 86400 秒) のセーフティガードを追加し、
--      `p_retention_seconds=0` のような破壊呼び出しを関数レベルで拒否する
--      (postgres / service_role は `is member of` で判定できないため、
--       `auth.uid() is null` で anon 経由を遮断する形に簡略化)。
--   3) `app_purge_expired_safety_logs` だけは残し、auth.uid() != null のとき
--      だけ 30 日固定で実行する。これはアプリ経路 (SupabaseBackend.purgeExpiredSafetyLogs)
--      で常に通る。
--
-- 重要: signature は (int) のまま保つ（呼び出し側の互換維持）。
create or replace function public.purge_expired_safety_logs(
    p_retention_seconds int default 30 * 24 * 60 * 60
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    deleted_count int;
    caller_uid    uuid := auth.uid();
begin
    -- 一般ユーザー (anon / authenticated) 経由では弾く。
    -- postgres / service_role は auth.uid() が NULL のまま invoke されるので通る。
    if caller_uid is not null then
        raise exception
            'purge_expired_safety_logs is restricted to service role'
            using errcode = '42501';
    end if;

    -- 安全装置: 0 や極端に短い保持期間は拒否 (1 日未満は不可)。
    -- これにより一般ユーザーが `p_retention_seconds=0` で全削除する穴を塞ぐ。
    if p_retention_seconds is null or p_retention_seconds < 86400 then
        raise exception
            'p_retention_seconds must be >= 86400 (1 day), got %',
            coalesce(p_retention_seconds::text, 'NULL')
            using errcode = '22023';
    end if;

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
    'F34 (sprint13 fix v2): 保持秒数を経過した通報記録を削除 (受け入れ条件6)。
     attempt 2 では一般ユーザーから `p_retention_seconds=0` で reports を
     全消しできてしまう穴があった。attempt 3 では:
       * auth.uid() が non-null (= 一般ユーザー) なら 42501 で拒否
       * p_retention_seconds < 86400 (= 1 日) なら 22023 で拒否
     に変更。これで `app_purge_expired_safety_logs()` 経由の 30 日固定削除
     (postgres / service_role 専用) と、`consume_rate_limit` 同様に
     アプリ起動時にユーザー本人起点で動作する 30 日固定版だけが authorized
     になる。';

-- 明示的に EXECUTE 権限を剥奪。postgres / service_role はデフォルトで
-- 関数を実行できる。
revoke all on function public.purge_expired_safety_logs(int) from public;
revoke execute on function public.purge_expired_safety_logs(int) from anon;
revoke execute on function public.purge_expired_safety_logs(int) from authenticated;

-- `app_purge_expired_safety_logs()` 経由のアプリ起動時オンデマンド削除は残す。
-- SupabaseBackend.purgeExpiredSafetyLogs からこの RPC を呼ぶ (受け入れ条件6)。
-- これは 30 日固定で、引数の細工ができないため安全。
-- (関数の再定義はしない。grant だけ確認しておく。)
-- grant execute on function public.app_purge_expired_safety_logs() to authenticated;
-- ↑ は migration 6 で既に付与済み。
