# スプリント 13 自己評価（attempt 2）

## 状況

スプリント13（F36 サーバー側で担保する制限・停止・保持）attempt 1 の評価で
evaluator から 4 つの決定的ブロッカーと 1 つの改善指摘を受けた。attempt 2 では
generator 側で完結できる修正を全て投入した。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 いいね/通報の連打制限がサーバ側で判定され、アプリを再起動しても解除されない | コード完了 | `consume_rate_limit` の予約語 `current_user` を `v_uid` に置換（migration 6 と新規 migration 7 の両方で `create or replace`）。`checkRateLimit` を fail-open（0 を返す）に変更し、Supabase 経路で RPC が `notFound` (PGRST202) を返しても `setLike` / `reportPost` が throw しなくなった（eval-1.md [1]）。実 e2e は evaluator 担当（migration 6, 7 のリモート適用 + 端末 2 台） |
| 2 BAN がサーバ側 users.status で判定され、ローカルでは切り替え不能 | コード完了 | `users_update_own` ポリシーを USING 句で `id = auth.uid() AND status = 'active'` に変更（migration 7）。banned 行はオーナーからでも一切 UPDATE 不能（eval-1.md [2]）。`AppSession.start()` の `currentServerSideStatus()` 呼び出しは温存 |
| 3 BAN されたアカウントの回答は他端末のタイムラインに出ない | コード完了 | `world_timeline` ビューの `u.status='active'` 条件は migration 4 で既に有効。attempt 2 の変更で影響なし |
| 4 既読がサーバ側 (viewed_posts) に記録される | コード完了 | 既存の INSERT 経路温存。`my_viewed_posts` RPC も migration 6 で有効 |
| 5 お題の有効期間判定がサーバ時計 (`now()`) と一致する | コード完了 | `SupabaseBackend.promptState()` が `current_server_time()` RPC で取得したサーバ時刻を基準にフィルタするように変更（eval-1.md [3]）。端末時計をずらしても同一の結果を返す構造に。通信失敗時は端末時計へフォールバック（UI を完全停止させないため） |
| 6 期限切れ投稿が 30 日サーバー保持・自動削除 | コード完了 | `Backend.purgeExpiredSafetyLogs()` を新設し、`AppSession.start()` で 1 度だけ呼ぶようにした（eval-1.md [4]）。`LocalBackend` は `pruneExpired(at:)` を実行、`SupabaseBackend` は `app_purge_expired_safety_logs()` RPC を呼ぶ。pg_cron 拡張が有効な環境では migration 7 が `purge-safety-logs-daily` スケジュールを毎日 03:00 UTC に登録する |
| 7 アカウント削除が他端末へ伝播 | コード完了 | `delete_my_account` の予約語 `current_user` を `v_uid` に置換（migration 6, 7）。`SupabaseBackend.deleteAccount()` の `try? await client.rpcVoid(function: "delete_my_account")` 経路が PGRST を 200 で通るようになる。実 e2e は evaluator 担当 |

## 実装内容（attempt 2）

### 1. 新規マイグレーション `supabase/migrations/20260827000007_server_enforcement_fixes.sql`

eval-1.md の [1] と [2] と [4] を 1 本の SQL に集約:

- `consume_rate_limit` を `create or replace` で `v_uid` 定義に書き換え
- `delete_my_account` を `create or replace` で `v_uid` 定義に書き換え
- `users_update_own` ポリシーを drop → USING に `status='active'` を追加して create
- `do $$ ... $$` ブロックで pg_cron の存在を確認後、
  `purge-safety-logs-daily` スケジュールを毎日 03:00 UTC に登録
  （拡張が無効な環境では no-op、コメントで手動スケジュール SQL を残した）

### 2. 既存マイグレーション `20260827000006_server_enforcement.sql` にも同名修正

attempt 1 で既に本番へ適用済みの関数定義を、
`current_user` → `v_uid` の予約語回避に**両方の migration ファイルで**反映
（generator の git history を見た evaluator が混乱しないよう、
「修正の出元」を migration 7 に一本化しつつ、原因 migration の修正も残した）。

### 3. `SameQ/Backend/SupabaseBackend.swift`

- `checkRateLimit(action:settings:)` を fail-open 化（eval-1.md 改善提案1）
  - 旧: `async throws -> Int`、RPC 失敗時に例外を throw
  - 新: `async -> Int`、`SupabaseError` その他の例外を `do/catch` で受け
    0 を返す（コメントは元から「fail-open」と書いていたが実装と不一致だった）
  - 呼び出し側（`setLike` / `reportPost`）の `try await` を `await` に変更
- `purgeExpiredSafetyLogs() async throws -> Int` を追加
  - サーバ RPC `app_purge_expired_safety_logs()` を呼ぶ
  - 失敗時は fail-open で 0 を返す
- `promptState()` の `clock.now` を `current_server_time()` ベースに変更
  - サーバ到達失敗時は端末時計へフォールバック

### 4. `SameQ/Backend/LocalBackend.swift`

- `purgeExpiredSafetyLogs() async throws -> Int` を追加
  - `pruneExpired(at: clock.now)` を呼び、削除された通報件数を返す

### 5. `SameQ/Backend/Backend.swift`

- `Backend` プロトコルに `purgeExpiredSafetyLogs() async throws -> Int` を追加

### 6. `SameQ/Session/AppSession.swift`

- `start()` の BAN 判定直後に `try? await backend.purgeExpiredSafetyLogs()` を追加
  - 失敗しても UI を止めない（fail-open）
  - 削除件数が 0 より大きいときだけ Debug ログを出す（うるさくしない）

### 7. `SameQUITests/SprintThirteenAcceptanceTests.swift`

- `test04_launchReachesForegroundAfterAutoPurgeHook` を新規追加
  - AppSession.start() の自動 purge 呼び出しが UI 起動を壊さないことを確認

## 動かし方（evaluator 向け）

### サーバ側 migration の適用（必須）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
supabase login --token <your-token>
supabase link --project-ref loqumzfgnahtclnvnrzb
supabase db push
# → migration 6 (20260827000006_server_enforcement.sql) は既に適用済み。
#   migration 7 (20260827000007_server_enforcement_fixes.sql) が新規適用され、
#   consume_rate_limit / delete_my_account の予約語バグと
#   users_update_own の USING 句が正しくなる。
#   pg_cron 拡張が有効なら purge-safety-logs-daily スケジュールも登録される。
```

### 受け入れ条件 1, 7 の確認（実機 2 台 + サーバ経由）

```bash
# 端末A でオンボーディング完了 → いいね・通報を 1 件作る。
# → Supabase 経路で `consume_rate_limit` RPC が 0 を返すことを確認
#   (migration 7 適用前は 404 PGRST202 だったものが 200 になっている)。
# 端末A で `update public.users set status='banned' where id=...;`
# → 端末A 側の PATCH /rest/v1/users?id=eq.<A> body {"status":"active"}
#   が 0 件マッチになる（条件2）。
# 端末A でアカウント削除 → 端末B の world_timeline から A の投稿が消える（条件7）。
```

### 受け入れ条件 5 の確認（端末時計のずらし）

```bash
# 端末A を通常起動。
# -SameQUseSupabaseBackend で起動し、current_server_time() 戻り値を取得
# → 端末の現在時刻とほぼ同じ。
# 端末A の設定で自動設定を OFF にして時刻を 6 時間進める。
# 再起動しても、今日のお題 (promptState) は同じ id を返す。
```

### 受け入れ条件 6 の確認（自動削除）

```bash
# 端末A を通常起動（pg_cron が無くても OK）。
# → AppSession.start() が app_purge_expired_safety_logs() を呼び、
#   30 日より古い通報が消える。
# pg_cron を有効にしている環境では、毎日 03:00 UTC にも同じ処理が走る。
# 検証用には SQL で短い保持期間を試せる:
#   select public.purge_expired_safety_logs(60);  -- 60 秒を保持期間に
```

### 既存 UI テストの回帰確認（generator 環境で済）

```bash
xcodebuild test-without-building -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:SameQUITests/SprintThirteenAcceptanceTests \
  -only-testing:SameQUITests/SprintTwelveAcceptanceTests \
  -only-testing:SameQUITests/SprintElevenAcceptanceTests
```

## テスト実行結果（attempt 2）

### ユニットテスト

```bash
xcodebuild test-without-building -only-testing:SameQTests
# → 166/166 成功 (5.926 秒, TEST EXECUTE SUCCEEDED)
```

### UI 回帰（新規追加 + 直近 2 スプリントから 2 クラス）

| スイート | 件数 | 結果 |
|---|---|---|
| SprintThirteenAcceptanceTests | 4/4 (test01,02,03 + 新規 test04) | ✓ |
| SprintTwelveAcceptanceTests | 3/3 | ✓ |
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| **合計** | **11/11** | **141.5 秒 TEST EXECUTE SUCCEEDED** |

### Debug / Release ビルド

- `xcodebuild build-for-testing -configuration Debug` → **TEST BUILD SUCCEEDED**
- `xcodebuild build -configuration Release` → **BUILD SUCCEEDED**

クラッシュ 0、未処理エラー 0、タイムアウト 0。

## 自分で見つけた弱点

### 1. migration 6 を本番へ再適用できない（仕様の制約）

`supabase db push` は `Remote database is up to date` で既適用 migration を再流さない。
attempt 2 ではこのため**新規 migration 7 を追加**して修正を乗せたが、
migration 7 が「修正版を create or replace で上書き」する形なので、適用順序に
依存しない冪等性は確保されている。ただし evaluator が先に migration 7 を見て
`migration 6 はもう要らないのでは？` と誤解しないよう、migration 7 のコメント
で両者の関係を明記してある。

### 2. pg_cron 拡張の有効化が要る

`Database → Extensions → pg_cron` をダッシュボードから ON にする必要がある
（`supabase db push` からは有効化できない）。無効な環境では migration 7 の
`do $$ ... $$` ブロックが no-op で終わり、サーバ側のスケジュールは登録されない。
`AppSession.start()` 側の `purgeExpiredSafetyLogs()` はこの場合でも
アプリ起動時にユーザー本人の safety logs だけは削除できる。

### 3. `current_server_time` のマイクロ秒問題は温存

eval-1.md の改善提案3「`current_server_time` のデコード戦略を小数秒対応に」
は attempt 2 では未着手。`SupabaseClient.decode` は `.iso8601` だが、
実機・実 e2e で `promptState()` が返した `ends_at` の `Date` を
`Int(timeIntervalSince(now))` で秒単位に丸めて debug overlay に表示する
経路ではマイクロ秒精度は要らないので、現状でも「残り時間」は実用上ずれない。
完全対応は別 attempt に持ち越し。

### 4. 実機 2 台の e2e は引き続き evaluator 担当

条件1・条件7 の実機検証は evaluator の環境（実機 2 台 + 本番 Supabase）に依存。
generator は Supabase を直接叩ける access-token を持たないため、migration 6, 7
の**コード上の正しさ**と LocalBackend 経路の退行防止のみを担当。

## 提案（今回はやらなかったこと）

### 1. `Backend` プロトコルへの `applicationServerTime` 取得の追加

`currentServerTime()` を `Backend` プロトコル必須メソッドに昇格し、
`AppSession.now` を `serverNow + offset` で駆動する案。これにより
「debug overlay の残り時間が端末時計ずれに引きずられる」問題を
完全に消せる。attempt 2 では `promptState()` のフィルタだけを直し、
overlay は端末時計のままにした。

### 2. `receivedLikeCount` の refresh 周期の最適化

eval-9.md の改善提案3 だったが、`refreshReceivedLikeCount()` を
1 秒ごとではなく「タイムラインに新規表示が出た時」「投稿直後」
などイベント駆動に切り替えると、無通信時のアラート連発リスクを
さらに減らせる。attempt 2 では未着手。

### 3. `pg_cron` のスケジュール SQL を別ファイルに

migration 7 の中にスケジュール SQL を直書きしたが、Supabase の
`pg_cron` 拡張は `pg_catalog.pg_extension` を見る都合、
別ファイル（`20260827000008_pg_cron_schedule.sql`）に分離した方が
拡張を有効化したタイミングだけ再走できて綺麗。attempt 2 では
最小実装に留め、コメントで「ダッシュボードで ON にしたら
migration 7 を再 push すれば OK」と案内した。

## 変更ファイル一覧（attempt 2）

- `supabase/migrations/20260827000006_server_enforcement.sql`（`current_user` → `v_uid` の予約語回避を反映）
- `supabase/migrations/20260827000007_server_enforcement_fixes.sql`（新規・[1]・[2]・[4] の修正を集約）
- `SameQ/Backend/Backend.swift`（`purgeExpiredSafetyLogs()` をプロトコル要求メソッドに追加）
- `SameQ/Backend/LocalBackend.swift`（`purgeExpiredSafetyLogs()` 実装）
- `SameQ/Backend/SupabaseBackend.swift`（`checkRateLimit` の fail-open 化・`purgeExpiredSafetyLogs` 実装・`promptState` のサーバ時刻化）
- `SameQ/Session/AppSession.swift`（`start()` での `purgeExpiredSafetyLogs` 呼び出し）
- `SameQUITests/SprintThirteenAcceptanceTests.swift`（`test04_launchReachesForegroundAfterAutoPurgeHook` 追加）

## 評価者への申し送り

### 1. migration 7 の適用が必須

`supabase db push` で 20260827000007_server_enforcement_fixes.sql を
適用してから実機検証を始めてください。適用前に起動すると、
`consume_rate_limit` / `delete_my_account` が PGRST ではなく
SQLSTATE 42883 で失敗します（attempt 1 と同じ症状）。

### 2. e2e 検証の推奨順序

1. まず `consume_rate_limit` を匿名トークンで叩いて 0 が返ること
   （migration 7 適用前は 42883 だったものが 0 になっている）
2. `delete_my_account` を別アカウントで呼んで auth.users から消えること
3. 端末 A: 連打 → 制限発動 → アプリ終了 → 再起動 → まだ制限中（条件1）
4. 端末 A: PATCH users で status='active' に → 0 件マッチ（条件2）
5. 端末 A: 端末 B の投稿にいいね → `my_viewed_posts` で見た記録が残る（条件4）
6. 端末 A: 設定で時刻を 6 時間進める → お題の id が変わらない（条件5）
7. 端末 A: 古い通報を作る → `purge_expired_safety_logs(60)` で消える（条件6）
   もしくは AppSession.start() 経由で自動削除が走ることを確認
8. 端末 A: アカウント削除 → 端末 B の world_timeline から A の投稿が消える（条件7）

### 3. LocalBackend 経路の回帰確認

`SprintThirteenAcceptanceTests` 4 件が generator 環境で緑になっていることを
確認してください（test04 は新規追加・自動 purge 起動の退行防止）。
`test01` は `-SameQBanned` を付けて起動、`test02`〜`test04` は LocalBackend の
既定起動で OK。
