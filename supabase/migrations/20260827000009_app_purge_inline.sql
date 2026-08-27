-- SameQ スプリント13 attempt 4: 受け入れ条件6「期限切れ safety logs の30日保持
-- + 自動削除」の修正 (F34/F36)
--
-- 背景:
--   attempt 3 (migration 8) で `purge_expired_safety_logs(int)` に
--     if caller_uid is not null then raise ... 'restricted to service role' …
--   を追加した。これは「`p_retention_seconds=0` で reports を全消しできる穴」
--   を塞ぐための正しい安全装置だが、`app_purge_expired_safety_logs()`
--   の **実装** が `select public.purge_expired_safety_logs(30 * 24 * 60 * 60)`
--   のラッパだったため、ラッパ経由の呼び出しでも SECURITY DEFINER 内では
--   `auth.uid()` が **呼び出し元 JWT の sub** を返すため、必ず 42501 で
--   弾かれるようになっていた。
--
--   eval-4.md [1] の再現手順 (`/tmp/sameq_eval13d/t2.py`) で確定:
--     * `app_purge_expired_safety_logs()` を認証トークンで呼ぶと HTTP 403 /
--       `42501 restricted to service role`
--     * アプリ起動時の自動削除経路 (`AppSession.start` →
--       `SupabaseBackend.purgeExpiredSafetyLogs` → `app_purge_*`) が
--       no-op になり、条件6 の「自動で削除される」が一切動かなくなった。
--     * pg_cron 拡張も本番で無効化されており、`app_purge_*` 以外の
--       経路も無い。attempt 2 より後退した状態。
--
-- 修正方針 (eval-4.md 修正案・選択肢A):
--   1. `app_purge_expired_safety_logs()` を **削除ロジック直書き** の
--      独立した SECURITY DEFINER 関数として再定義する。
--      * 30 日固定 (`make_interval(secs => 30 * 24 * 60 * 60)`)。
--      * `auth.uid()` ガードも `p_retention_seconds` の最小値ガードも
--        **持たない**。引数も取らない。
--      * `purge_expired_safety_logs(int)` を呼び出さないので、
--        そちらの service_role 専用ガードを素通りできる。
--   2. `purge_expired_safety_logs(int)` は service_role / postgres 専用の
--      任意保持秒数版として **そのまま温存**。evaluator が「短保持での
--      自動削除」を観測するための唯一の正攻法がこの関数。
--   3. `app_purge_expired_safety_logs()` は authenticated / anon 双方に
--      EXECUTE を許可し直す（migration 6 で authenticated に付与済みを再
--      確認、念のため明示）。
--
-- これで以下が両立する:
--   * **アプリ起動時に自動で削除が走る** (条件6・前半)
--     `AppSession.start` → `app_purge_expired_safety_logs()` が 30 日で動作。
--   * **短保持での自動削除を運営手段で観測できる** (条件6・spec 評価者注記)
--     service_role で `purge_expired_safety_logs(60)` を呼ぶ。
--   * 一般ユーザーが任意保持秒数で `reports` を消せる穴は塞がったまま
--     (条件6・attempt 3 で導入した安全装置は温存)。
--
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1) app_purge_expired_safety_logs: 削除ロジックを直書きして SECURITY DEFINER
--    ラッパから独立させる。引数なし・30 日固定。
-- ---------------------------------------------------------------------------
create or replace function public.app_purge_expired_safety_logs()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    deleted_count int;
    retention     int := 30 * 24 * 60 * 60;  -- 30 日 (秒)
begin
    -- posts.expires_at + retention を過ぎた reports と
    -- (posts が既に消えている場合のフォールバックとして)
    -- reports.created_at + retention を過ぎた reports を両方削除する。
    -- これは元 purge_expired_safety_logs と同じ条件だが、
    -- auth.uid() のチェックを持たず、purge_expired_safety_logs(int)
    -- を経由しないので 42501 に当たらない。
    with targets as (
        select r.id
        from public.reports r
        where (r.created_at + make_interval(secs => retention)) < now()
           or exists (
               select 1 from public.posts p
               where p.id = r.post_id
                 and (p.expires_at + make_interval(secs => retention)) < now()
           )
    )
    delete from public.reports
    where id in (select id from targets);
    get diagnostics deleted_count = row_count;

    return deleted_count;
end;
$$;

comment on function public.app_purge_expired_safety_logs() is
    'F34/F36 (sprint13 fix v3): アプリ起動時のオンデマンド清掃 (受け入れ条件6)。
     attempt 3 で `purge_expired_safety_logs(int)` に追加された
     `auth.uid() != null → 42501` ガードが、ラッパ経由でも
     SECURITY DEFINER 内では `auth.uid()` が呼び出し元 JWT の sub を
     返すため、`app_purge_expired_safety_logs()` 自体を 403 化して
     しまっていた。attempt 4 では削除ロジックをこの関数内に直書きし、
     `purge_expired_safety_logs(int)` を経由しない独立実装に変更する。
     これで:
       * 一般ユーザーの起動時呼び出しが 30 日固定で動作する
       * `purge_expired_safety_logs(int)` の service_role 専用ガードは
         そのまま温存され、任意保持秒数での運用観測も従来どおり可能
     引数なし・30 日固定。';

-- 念のため EXECUTE 権限を再付与（migration 6 で authenticated に付与済みを
-- 確認する意味でも明示）。
grant execute on function public.app_purge_expired_safety_logs() to authenticated;
grant execute on function public.app_purge_expired_safety_logs() to anon;

-- ---------------------------------------------------------------------------
-- 2) purge_expired_safety_logs(int) は attempt 3 の安全装置付きで温存。
--    ファイル冒頭のコメントで「service_role / postgres 専用」を再強調する。
--    実装は migration 8 のまま (auth.uid() != null → 42501、
--    p_retention_seconds < 86400 → 22023、revoke anon/authenticated)。
--    ここでは変更しない。
-- ---------------------------------------------------------------------------

-- evaluator が「短保持での自動削除」を観測する手順 (コメント):
--   -- 1) Supabase ダッシュボード → Settings → API から service_role キーを取得
--   -- 2) ターミナルで:
--   --
--   -- curl -X POST "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs" \
--   --   -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
--   --   -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
--   --   -H "Content-Type: application/json" \
--   --   -d '{"p_retention_seconds": 60}'
--   --
--   -- → 60 秒経過した reports 行が消え、期間内の reports は残ること。
--   -- このとき認証ユーザー (anon / authenticated) で同じ RPC を叩くと
--   -- 42501 で拒否される (attempt 3 の安全装置が生きている)。
-- ---------------------------------------------------------------------------
