# スプリント 13 attempt 4: 受け入れ条件6（自動削除）の修正

## 状況（eval-4.md [1] を最優先）

attempt 3 で `purge_expired_safety_logs(int)` に `auth.uid() != null → 42501`
ガードを追加したが、`app_purge_expired_safety_logs()` は SECURITY DEFINER 内で
あっても `auth.uid()` が **呼び出し元 JWT の sub** を返すため、ラッパ経由でも
必ず 42501 で弾かれていた。結果、本番で `app_purge_expired_safety_logs()`
経由の自動削除が1件も動かず、attempt 2 より後退した状態。

## 受け入れ条件（spec.md 320〜331 行・eval-4.md で確定不合格の1項目）

- [x] 1 連打制限のサーバ側判定（attempt 2 / 3 で解決済み）
- [x] 2 BAN のサーバ側判定・切替不能（attempt 2 / 3 で解決済み）
- [x] 3 BAN されたアカウントの非表示（既存）
- [x] 4 既読のサーバ側記録（既存）
- [x] 5 サーバ時計基準の判定（attempt 3 で解決済み）
- [ ] **6 期限切れ投稿の30日保持 + 自動削除** ← 今回のスコープ
- [x] 7 アカウント削除の伝播（attempt 2 / 3 で解決済み）

## 実装方針

eval-4.md 修正案（選択肢A）に従い、`app_purge_expired_safety_logs()` の
削除ロジックを **直書き** して `purge_expired_safety_logs(int)` を
経由しない実装に変更する。これで:

- アプリ起動時の `AppSession.start() → SupabaseBackend.purgeExpiredSafetyLogs() → app_purge_expired_safety_logs()` が 200 を返すようになる。
- `purge_expired_safety_logs(int)` は service_role / postgres 専用の
  関数として残し、任意の保持秒数での運用観測を引き続き可能にする。
- 「アプリで起動時に自動削除が動く」「service_role で短保持の自動削除を観測できる」の両方を満たせる。

加えて eval-4.md 改善提案3 を反映: pg_cron スケジュールを
migration 7 から分離し、拡張が ON になった後にだけ流す
`20260827000010_pg_cron_schedule.sql` にする。

## 影響範囲

- 新規ファイル: `supabase/migrations/20260827000009_app_purge_inline.sql`
- 新規ファイル: `supabase/migrations/20260827000010_pg_cron_schedule.sql`
- 既存 migration 7 は変更しない（既に Remote に記録済みで再走しない）。
  pg_cron スケジュールは新設 migration 10 へ移動するだけで、
  migration 7 から削除する必要はない（残っていても既に適用済みで無害）。
- アプリコードに protocol / Backend 実装の変更は **不要**。
  `purgeExpiredSafetyLogs() -> Int` の意味も変わらない。
- ユニットテスト: `ServerEnforcementTests` に migration 9 の責務を
  LocalBackend で担保するテストを1本追加（`app_purge_expired_safety_logs`
  経由の削除件数算出が LocalBackend でも整合することを確認する対称テスト）。

## 検証計画

- ユニット: `SameQTests` 全件が緑（170 + 新規1 = 171）
- UI: `SprintThirteenAcceptanceTests` を全件実行（4件）
- 回帰: 直近2スプリントから `SprintElevenAcceptanceTests` + `SprintFiveAcceptanceTests`
- ビルド: Debug build-for-testing が SUCCEEDED

## 評価者への申し送り

- `supabase db push` で migration 9 と 10 が新規適用される（順序: 9 → 10）。
  migration 9 が条件6 の自動削除を直り、migration 10 は pg_cron 拡張が
  ダッシュボードで ON になった後にも自動でスケジュールを登録する
  将来用。
- 短保持での自動削除観測: evaluator が service_role キーを
  `https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb/settings/api`
  から取得し、`purge_expired_safety_logs(60)` を叩く。期限切れの
  reports が消え、期間内の reports は残ることを2時点で観測。
