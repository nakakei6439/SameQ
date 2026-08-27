-- SameQ スプリント13 attempt 4: pg_cron スケジュールの分離 (eval-4.md 改善提案3)
--
-- 背景:
--   attempt 2 (migration 7) で pg_cron 拡張が有効な場合に毎日 03:00 UTC に
--   `purge_expired_safety_logs(30日)` を実行するスケジュールを登録する
--   ブロックを追加した。attempt 3 で pg_cron 起因のロールバック問題は
--   解消済みだが、cron スケジュール SQL が条件6 の他の修正と同じ
--   ファイルに同居しているのが事故リスクとして残っていた:
--     * 拡張が後から有効化された場合、migration 7 を再走させる術が無い
--     * cron 関連のエラーが他の修正のロールバックを引き起こす可能性を
--       ゼロにはできない
--
-- 修正方針:
--   pg_cron スケジュールの登録ブロックをこの独立ファイルへ移し、
--   拡張が ON になった後に `supabase db push` するだけでスケジュールが
--   登録される形にする。`migration 7` 自体は既に Remote に記録済みの
--   ファイルであり、後から中身を編集しても Supabase CLI は再走しない。
--   このファイルは新規適用なので、有効化直後の 1 回 `db push` で
--   スケジュールが登録される。
--
-- 注意:
--   * このファイルは pg_cron 拡張が**無い**環境でもロールバックしない
--     よう、`do $...$ ... $...$` ブロックの中で
--     `if exists (select 1 from pg_extension where extname='pg_cron') then`
--     でガードする。
--   * cron ジョブ名 `purge-safety-logs-daily` は冪等:
--     既に存在する場合は `cron.unschedule` で消してから再作成する。
-- ---------------------------------------------------------------------------

do $outer$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        -- 同じ名前の既存スケジュールを消してから再作成（冪等・初回は no-op）。
        if exists (
            select 1 from cron.job where jobname = 'purge-safety-logs-daily'
        ) then
            perform cron.unschedule('purge-safety-logs-daily');
        end if;
        perform cron.schedule(
            'purge-safety-logs-daily',
            '0 3 * * *',
            $sql$select public.purge_expired_safety_logs(30 * 24 * 60 * 60);$sql$
        );
        -- 拡張自身へのコメント。do ブロックの中で dynamic SQL 経由で当てるので、
        -- 拡張が無くてもここで SQLSTATE 42704 にならない。
        begin
            execute format(
                'comment on extension pg_cron is %L',
                'sprint13 fix v3: 毎日 03:00 UTC に期限切れ safety logs を自動削除するスケジュール purge-safety-logs-daily を登録する'
            );
        exception when others then
            -- 拡張はあるが comment 権限が無い等の稀ケース。fatal ではないため握る。
            null;
        end;
    end if;
end;
$outer$;

-- 手順 (eval-4.md 改善提案4 と整合):
--   1) Supabase ダッシュボード → Database → Extensions で `pg_cron` を ON
--   2) `supabase db push` を実行 → このファイルが新規適用され、
--      スケジュール `purge-safety-logs-daily` が登録される
--   3) 確認:
--        select * from cron.job where jobname = 'purge-safety-logs-daily';
--      → 1 行返れば OK。
-- ---------------------------------------------------------------------------
