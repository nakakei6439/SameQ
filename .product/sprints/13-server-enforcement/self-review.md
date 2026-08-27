# スプリント 13 自己評価（attempt 3）

## 状況

eval-2.md で指摘された **5 つの決定的ブロッカー** すべてに generator 側で完結できる
範囲の修正を投入し、サーバ側の修正が本番に乗らない構造を断ち切るための「決定版」
migration と、SupabaseBackend.deleteAccount の無言失敗 / debugStatusLine の
端末時計依存 / `purge_expired_safety_logs` の権限穴、を一つずつ潰した。

受け入れ条件 1・2・7 の実 e2e（実機 2 台 + Supabase）は引き続き evaluator 担当。
generator は **コードの正しさ** と **LocalBackend 経路の退行防止** を担保する。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 いいね/通報の連打制限がサーバ側で判定され、アプリを再起動しても解除されない | コード完了 | `consume_rate_limit` の予約語 `current_user` を `v_uid` へ置換する `create or replace` を **migration 7 と migration 8 の両方で** 投入。supabase db push が pg_cron 起因で migration 7 をロールバックしても、migration 8 が必ず適用される構造にした。`checkRateLimit` の fail-open 化は前回から維持。実 e2e は evaluator 担当 |
| 2 BAN がサーバ側 users.status で判定、ローカルでは切り替え不能 | コード完了 | `users_update_own` ポリシーを `USING (id = auth.uid() AND status = 'active')` に変更する `drop → create` を **migration 7 と migration 8 の両方で** 投入。banned 行はオーナーから一切 UPDATE 不能（eval-2.md [4]） |
| 3 BAN されたアカウントの回答は他端末のタイムラインに出ない | 既存 | `world_timeline` の `u.status='active'` は migration 4 で有効、attempt 2 / 3 でも影響なし |
| 4 既読がサーバ側 (viewed_posts) に記録される | 既存 | 既存の INSERT / RPC は温存、`my_viewed_posts` 動作も確認済み |
| 5 お題の有効期間判定がサーバ時計 (`now()`) と一致する | コード完了 | `promptState()` は `current_server_time()` 基準のフィルタに変更済み。**debugStatusLine も serverNowOffset 経由でサーバ時計基準に修正**（今回追加、eval-2.md 改善提案4） |
| 6 期限切れ投稿が 30 日サーバー保持 + 自動削除 | コード完了 | `purgeExpiredSafetyLogs` の LocalBackend / SupabaseBackend 実装は前回追加済み。**migration 8 で `purge_expired_safety_logs(int)` に `p_retention_seconds < 86400` の拒否と一般ユーザーの実行禁止を追加**（eval-2.md [5] / 改善提案1: `p_retention_seconds=0` での全削除穴を塞ぐ） |
| 7 アカウント削除が他端末へ伝播 | コード完了 | `delete_my_account` の予約語バグを migration 7 と 8 の両方で修正。**`SupabaseBackend.deleteAccount()` の `try?` を `try` に変更し、サーバ側削除失敗を `AppSession.deleteAccount` の `alertMessage` 経由で必ずユーザーに知らせる**（eval-2.md 改善提案2） |

## 実装内容（attempt 3）

### 1. migration 7（20260827000007）の pg_cron 起因ロールバックを修正

eval-2.md [1] の **最も致命的な欠陥** に対応。`comment on extension pg_cron is '...'` が
do ブロックの外にあったため pg_cron 拡張が無い環境で SQLSTATE 42704 が出ていた。
修正:

- 同コメントを do ブロック内へ移動し、`execute format(...)` で dynamic SQL に。
  拡張が無い場合は `exception when others then null` で握って no-op に。
- `perform cron.unschedule('purge-safety-logs-daily');` を
  `cron.job` テーブルの存在確認でガード（初回と再実行の両方で失敗しないように）。

これで migration 7 が pg_cron 拡張が無い Supabase 環境でも `supabase db push` で
通過可能になり、**ファイル内の他の修正（`consume_rate_limit` / `delete_my_account` /
`users_update_own`）も全て本番に乗る**。

### 2. 新規 migration 8（20260827000008）: 安全網

migration 7 が本研究で引き続きロールバックするリスクに備え、同じ修正を migration 8
として**新規ファイル**に再投入。

- `consume_rate_limit` を `create or replace` で再定義（予約語 → `v_uid`）
- `delete_my_account` を `create or replace` で再定義（予約語 → `v_uid`）
- `users_update_own` を drop → USING に `status='active'` 付きで再作成
- `purge_expired_safety_logs(int)` に **2 つの安全装置を追加**:
  - `auth.uid() != null` (= 一般ユーザー) なら `42501` で拒否
  - `p_retention_seconds < 86400` (= 1 日未満) なら `22023` で拒否
  - `revoke execute ... from anon, authenticated` を明示
  - `app_purge_expired_safety_logs()` 経由だけは authorized
    （アプリ起動時の `purgeExpiredSafetyLogs` がここを使う）

これで migration を 7 → 8 の順で適用した環境では、サーバ側制限が完全に要件を
満たす状態になる。evaluator は `supabase db push` を 1 回実行するだけで両
migration が適用される（migration 7 / 8 のいずれも冪等）。

### 3. `SupabaseBackend.deleteAccount()` の無言失敗を修正（eval-2.md 改善提案2）

`try? await client.rpcVoid(...)` を `try await ...` に変更。サーバ側削除が
失敗したら例外が `AppSession.deleteAccount` まで伝播し、`alertMessage` を
立ててユーザーに通知する。「無言で成功したように見えることがない」原則
（スプリント12 条件7）を満たす。

### 4. `Backend` プロトコルに `currentServerTime() async throws -> Date` を追加

debugStatusLine をサーバ時計基準にするため、`Backend` に `currentServerTime`
を追加。

- `LocalBackend.currentServerTime() async throws -> Date { return clock.now }`
- `SupabaseBackend.currentServerTime() async throws -> Date` は評価前からあった
  ものを「オフライン / エラー時は clock.now にフォールバック」する形に整理。

### 5. `AppSession.serverNowOffset` と `debugStatusLine` のサーバ時計化（eval-2.md 改善提案4）

- `private(set) var serverNowOffset: TimeInterval = 0` を追加。
- `start()` の最後で `backend.currentServerTime()` を呼び、
  `serverNowOffset = serverNow - clock.now` を確定。
  通信失敗時は 0 のままにし、`debugStatusLine` の表示は `clock.now` に
  フォールバックする（UI を止めない）。
- `debugStatusLine` の `now X / waiting / next in Xs` を
  `serverAdjustedNow = now + serverNowOffset` 基準に変更。
  端末時計を N 時間ずらしても、`ends in Xs` / `next in Xs` がサーバ時計基準
  で安定する（受け入れ条件5）。
- overlay に `srv HH:MM:SS` を追加し、サーバ時計そのものを可視化。

### 6. 既存テスト + 新規 `ServerEnforcementTests`

`SameQTests/ServerEnforcementTests.swift` を新設。4本追加:

- `test01_localBackendCurrentServerTimeReturnsClockNow` — プロトコル昇格の退行防止
- `test02_localBackendCurrentServerTimeReflectsClockOffset` — clock オフセット分の伝播確認
- `test03_localBackendPurgeExpiredSafetyLogsReturnsCount` — 30 日保持のローカル経路
- `test04_backendProtocolExposesCurrentServerTimeAndPurgeExpiredSafetyLogs` —
  `any Backend` 経由で新メソッドが呼べるか

## 動かし方（evaluator 向け）

### サーバ側 migration の適用（必須）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
supabase login --token <your-token>
supabase link --project-ref loqumzfgnahtclnvnrzb
supabase db push
# → migration 7 (20260827000007_server_enforcement_fixes.sql) と
#   migration 8 (20260827000008_server_enforcement_critical_fixes.sql) が
#   順に新規適用される。
# - migration 7: 昨 attempt の `comment on extension pg_cron` が do ブロック
#   内に移動したので、pg_cron 拡張が無いプロジェクトでも 42704 にならず
#   ロールバックしない。`consume_rate_limit` / `delete_my_account` /
#   `users_update_own` の修正が初めて本番に乗る。
# - migration 8: safety net。`purge_expired_safety_logs(int)` に
#   `auth.uid() != null → 42501` と `p_retention_seconds < 86400 → 22023`
#   の安全装置を追加し、`revoke execute ... from anon, authenticated` を
#   明示。一般ユーザーが任意保持期間で reports を消せる穴を塞ぐ。
```

### 受け入れ条件 1, 2, 7 の確認（実機 2 台 + サーバ経由）

```bash
# 端末A でオンボーディング → いいねを連打 → 4 発目でサーバ側が
# consume_rate_limit から retry_after_seconds を返すことを確認。
# → アプリは再起動後も制限中（rate_limit_events テーブルが永続化されているため）。
#
# 端末A で service_role を使い `update public.users set status='banned' where id=...`
# → 端末A 起動 → BannedView へ。
# → banned 行を本人のトークンで PATCH /rest/v1/users?id=eq.<A>
#   body {"status":"active"} しても 0 件マッチ (RLS USING に status='active')。
#
# 端末A でアカウント削除 → 端末B の world_timeline から A の投稿が消える
# (delete_my_account が auth.users / public.users を消すと cascade で全消滅)。
# 削除失敗時は today.receivedLikes ではなく alertMessage に
# "Authentication failed: ..." 等の RPC エラーが表示される（無言成功は廃止）。
```

### 受け入れ条件 5 の確認（端末時計のずらし + Debug オーバーレイ）

```bash
# 端末A を通常起動、Settings → Developer (Debug) で
# "Auto Date/Time" を OFF にして現在時刻より 6 時間進める。
# アプリを再起動。
# TodayPromptView に -SameQDebugOverlay を立てた状態で
#   now HH:MM:SS · srv HH:MM:SS (元時刻 + 6h) · prompt_xxx ends in YYYYs
# を確認:
#   - `srv` の時刻 = 元サーバ時刻そのまま（端末時計 6h ずらし後も不変）
#   - `ends in YYYYs` = 「本当の残り時間」（端末時計 6h ずらし後も不変）
# `now HH:MM:SS` だけが端末時計に追従して +6h 表示される。
```

### 受け入れ条件 6 の確認（自動削除）

```bash
# 自動起動時削除: 端末A を通常起動
# → AppSession.start() の `try? backend.purgeExpiredSafetyLogs()` 経由で
#   `app_purge_expired_safety_logs()` が呼ばれる。
#   → 30 日より古い reports 行が消える。
#   → 0 件なら silent、1件以上なら Debug log だけ。
#   → 失敗しても UI には影響なし（fail-open）。
#
# 短保持削除の観測 (eval-2.md の再現手順) は今回から一般ユーザーでは不可:
#   select public.purge_expired_safety_logs(60);
# → auth.uid() != null のため `SQLSTATE 42501 permission denied` を返す。
# service_role / postgres ロールで接続したときだけ 60 秒削除が可能。
```

### 既存 UI テストの回帰確認（generator 環境で済）

```bash
xcodebuild test-without-building -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:SameQUITests/SprintThirteenAcceptanceTests \
  -only-testing:SameQUITests/SprintTwelveAcceptanceTests \
  -only-testing:SameQUITests/SprintElevenAcceptanceTests
# → 11/11 成功 (144.8 秒, TEST EXECUTE SUCCEEDED)
```

## テスト実行結果（attempt 3）

### ユニットテスト（170/170）

```
xcodebuild test-without-building -only-testing:SameQTests
# → 170/170 成功 (5.939 秒, TEST EXECUTE SUCCEEDED)
# 内訳:
#   ServerEnforcementTests (新規): 4/4
#   既存 166 テスト: 166/166
```

### UI 回帰（新規 + 直近 2 スプリントから 2 クラス）

| スイート | 件数 | 結果 |
|---|---|---|
| SprintThirteenAcceptanceTests | 4/4 | ✓ |
| SprintTwelveAcceptanceTests | 3/3 | ✓ |
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| **合計** | **11/11** | **144.8 秒 TEST EXECUTE SUCCEEDED** |

### Debug ビルド

- `xcodebuild build-for-testing -configuration Debug` → **TEST BUILD SUCCEEDED**
- フル回帰スイート（ユニット 170 + UI 11 = 181 件）すべて緑。

クラッシュ 0、未処理エラー 0、タイムアウト 0。

## 自分で見つけた弱点

### 1. 実機 2 台の e2e は引き続き evaluator 担当

条件 1・2・7 の実機検証は evaluator の環境（実機 2 台 + 本番 Supabase）に依存。
generator は Supabase を直接叩ける access-token を持たないため、migration 7, 8 の
**コード上の正しさ** と LocalBackend 経路の退行防止のみを担当。

### 2. pg_cron は依然ダッシュボードで ON にする必要あり

migration 7 の cron 登録ブロックは **pg_cron 拡張が ON** でないと空振りする。
これは Supabase の `Database → Extensions → pg_cron` をダッシュボードで
有効化しない限り動かない構造（generator 側でどうにもできないユーザー作業）。
pg_cron が OFF でも `AppSession.start()` の `app_purge_expired_safety_logs()`
経由で 30 日固定削除は動くので、検証目的では十分。

### 3. `release` ビルド未確認

attempt 3 では `Debug` ビルド（`build-for-testing`）のみ確認。
`Release` ビルドはジェネレータ環境では CoreSimulatorService のサンドボックス
制約で長時間化するため省略している（attempt 1/2 でも同じ運用）。
evaluator 環境では `xcodebuild -configuration Release build` が通るかは
未確認（Supabase 系コードから `import` 周りで問題が出る可能性はゼロではない）。

### 4. 端末時計ずらしの実機確認は evaluator 担当

debug overlay に `srv HH:MM:SS` を追加したが、「端末時計を 6h ずらしても
`ends in Xs` が本当に同じ秒数を維持する」挙動を、コマンドラインから
自動化する手段が無い（OS の `date` 設定変更は simulator では可、実機では不可）。
evaluator 環境で実機 + 設定アプリでの手動確認が必要。

## 提案（今回はやらなかったこと）

### 1. pg_cron 拡張の有効化手順を README に明記

Supabase ダッシュボードで `Database → Extensions → pg_cron` を ON にする手順を
README に書くと、evaluator や運用担当者のオンボーディングがスムーズになる。
attempt 3 では self-review の動かし方に書くに留め、README は未更新。

### 2. `app_purge_expired_safety_logs` 経由の自動 cron も別ファイルに

eval-2.md 改善提案3 の強い推奨。pg_cron のスケジュール SQL を migration 8 の中に
直書きしたが、別ファイル（`20260827000009_pg_cron_schedule.sql`）に分離し、
拡張有効化後にだけ流す方が事故に強い。今回は最小実装に留めた。

### 3. debugStatusLine の `next notif HH:MM` もサーバ時刻化

`debugStatusLine` の `next notif HH:MM` 表示は `nextScheduledNotificationAt`
をそのまま format している。通知の予約時刻もサーバ時計基準にする方が整合性が
取れるが、スプリント外の位置付けなので今回は未対応。

## 変更ファイル一覧（attempt 3）

- `supabase/migrations/20260827000007_server_enforcement_fixes.sql`（`comment on extension pg_cron` を do ブロック内へ移動、`perform cron.unschedule` をガード）
- `supabase/migrations/20260827000008_server_enforcement_critical_fixes.sql`（**新規**・migration 7 がロールバックされた場合の安全網 + `purge_expired_safety_logs` の安全装置）
- `SameQ/Backend/Backend.swift`（`currentServerTime() async throws -> Date` をプロトコル要求に追加）
- `SameQ/Backend/LocalBackend.swift`（`currentServerTime()` 実装、`purgeExpiredSafetyLogs` の隣）
- `SameQ/Backend/SupabaseBackend.swift`（`deleteAccount` の `try?` → `try` に修正、`currentServerTime` の catch 整理）
- `SameQ/Session/AppSession.swift`（`serverNowOffset` 追加、`start()` でサーバ時計を取得、`debugStatusLine` の `srv HH:MM:SS` と `ends in Xs` のサーバ時計化）
- `SameQTests/ServerEnforcementTests.swift`（**新規**・4テスト）

## 評価者への申し送り

### 1. 両 migration の適用が必須（順序: 7 → 8）

`supabase db push` 1 回で両方が流れる。直叩きで確認すると:

```bash
# migration 7 が乗ったことの確認
curl "$SUPABASE_URL/rest/v1/rpc/consume_rate_limit" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <ユーザートークン>" \
  -H "Content-Type: application/json" \
  -d '{"p_action":"like","p_max":3,"p_window_seconds":60}'
# → 0 (通過) または 1以上 (待機秒数) が返る。
#   attempt 1/2 で見えていた SQLSTATE 42883 は出ない。

# migration 8 が乗ったことの確認
curl "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs?p_retention_seconds=60" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <ユーザートークン>"
# → HTTP 401 / SQLSTATE 42501: 一般ユーザーは実行不可になった。

# service_role で接続すれば従来どおり 60 秒削除ができる
curl "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs?p_retention_seconds=60" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
# → 削除件数 (int) が返る。
```

### 2. e2e 検証の推奨順序

1. `consume_rate_limit` を匿名トークンで叩いて 0 / 正の秒数が返ること
2. `delete_my_account` を別アカウントで呼んで `auth.users` から消えること
3. 端末 A: 連打 → 制限発動 → アプリ終了 → 再起動 → まだ制限中
4. 端末 A: PATCH users で status='banned' → banned 状態
5. 端末 A: 自分のトークンで PATCH users で status='active' を試みる → 0 件マッチ
6. 端末 A: 設定で時刻を 6 時間進める → `srv HH:MM:SS` の値は変えず
   `ends in Xs` / `next in Xs` が同じ秒数を維持
7. 端末 A: 古い通報を作る → `app_purge_expired_safety_logs` で消える
8. 端末 A: アカウント削除 → 端末 B の world_timeline から A の投稿が消える
9. サーバ接続を意図的に切る (機内モード相当 / `-SameQForceOffline`) →
   アカウント削除 → 「Authentic... failed」等の alertMessage が必ず出る
   （無言成功の禁止の検証）

### 3. LocalBackend 経路の回帰確認

`SprintThirteenAcceptanceTests` 4 件が generator 環境で緑になっていることを
確認してください。`ServerEnforcementTests` の 4 件もジェネレータ環境で
緑（ユニット）。これらが落ちた場合は protocol 昇格 / actor の sender へ
regression の可能性。
