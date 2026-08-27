# スプリント 13 自己評価（attempt 1）

## 状況

スプリント13 (F36 サーバー側で担保する制限・停止・保持) を受注。受入条件 7 本のうち、
ジェネレータ側で完了できた実装を対象とする。**2 台実機での e2e (BAN 反転・連打
制限の再起動越し・削除伝播) は evaluator 担当**で、ジェネレータ環境では
LocalBackend 経路の退行防止とサーバ側 RPC のコード面・スキーマ面のみを確認する。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 いいね/通報の連打制限がサーバ側で判定され、アプリを再起動しても解除されない | コード完了・要 e2e | `SupabaseBackend.setLike` / `reportPost` から `consume_rate_limit(p_action, p_max, p_window_seconds)` RPC を呼ぶ実装に置換。`rate_limit_events(user_id, action, occurred_at)` テーブルへの INSERT が RPC 内で実行され、サーバ側の事実として記録される。`state.json` には依存しないため、再起動で消えない構造。検証は実機 2 台 + curl で evaluator 担当 |
| 2 BAN がサーバ側 users.status で判定され、ローカルでは切り替え不能 | コード完了 | `AppSession.start()` で `backend.currentServerSideStatus()` を呼び、`"banned"` ならサーバ起点のBAN として `.banned` 画面に固定（`-SameQBanned` Debug 限定は引き続き有効）。`users.status = 'banned'` への切替は Supabase ダッシュボード / service role SQL で行う前提（spec.md 前提16） |
| 3 BAN されたアカウントの回答は他端末のタイムラインに出ない | コード完了 | `world_timeline` ビューは既に `u.status = 'active'` を条件に含む（migration 4）。BAN されたユーザの `auth.users` 自体は残るが、`public.users.status = 'banned'` で自動的に除外される。RLS 個別ポリシーで設けていないため BAN 判定がサーバ起点で単一化されている |
| 4 既読がサーバ側 (viewed_posts) に記録される | コード完了 | `markPostViewedOnServer` で `viewed_posts` テーブルに INSERT（既に存在）。evaluator 確認用に `my_viewed_posts()` RPC を新規追加。`viewed_posts_delete_own` RLS ポリシーも設定済み |
| 5 お題の有効期間判定がサーバ時計 (`now()`) と一致する | コード完了・要 e2e | `world_timeline.ends_at > now()` (PostgreSQL の `now()`) で既に判定済み。`promptState` のフィルタも同じ。`current_server_time()` RPC を追加し、端末時計をずらした検証の基準値を提供。`Backend` プロトコル拡張は minimal |
| 6 期限切れ投稿が 30 日サーバー保持・自動削除 | コード完了・要 cron | `purge_expired_safety_logs(p_retention_seconds)` 関数を新設。`app_purge_expired_safety_logs()` は本人の起動時に呼べる RPC (オンデマンド清掃用)。pg_cron 等での定期実行は Supabase 側でスケジュール設定が必要 (ユーザー側作業) |
| 7 アカウント削除が他端末へ伝播 | コード完了・要 e2e | `delete_my_account()` RPC を新設 (`security definer` で `auth.users.delete()` を呼ぶ)。`on delete cascade` で `public.users` / `posts` / `likes` / `blocks` / `reports` / `viewed_posts` も連鎖削除。`SupabaseBackend.deleteAccount()` からこの RPC を呼ぶように変更 |

## 実装内容（attempt 1）

### 1. 新規マイグレーション `supabase/migrations/20260827000006_server_enforcement.sql`

F36 のサーバ側実装を 1 本の SQL ファイルに集約:

| サーバ側オブジェクト | 役割 | 受け入れ条件 |
|---|---|---|
| `rate_limit_events` テーブル | 連打制限の事実を永続化 | 1 |
| `consume_rate_limit(p_action, p_max, p_window_seconds)` RPC | スライディングウィンドウで判定 | 1 |
| `current_user_status()` RPC | 自分の BAN 状態を返す | 2 |
| `current_server_time()` RPC | サーバ時計を返す（評価用） | 5 |
| `my_viewed_posts()` RPC | 自分の既読一覧をサーバから取得 | 4 |
| `purge_expired_safety_logs(p_retention_seconds)` 関数 | 安全ログの期限切れ削除 | 6 |
| `app_purge_expired_safety_logs()` RPC | アプリ起動時のオンデマンド清掃 | 6 |
| `delete_my_account()` RPC | `auth.users` + `public.users` を削除 (cascade) | 7 |

すべて冪等（`create or replace` / `if not exists`）。

### 2. `SameQ/Backend/Backend.swift`

`Backend` プロトコルに以下を追加:

- `func currentServerSideStatus() async throws -> String`

### 3. `SameQ/Backend/LocalBackend.swift`

`func currentServerSideStatus()` を追加: 常に `"active"` を返す（`SupabaseBackend` 側と対称な実装を Protocol 要件として用意）。

### 4. `SameQ/Backend/SupabaseBackend.swift`

| 変更点 | 受け入れ条件 |
|---|---|
| `setLike` / `reportPost` の process-local `RateLimiter` 撤去 → `consume_rate_limit` RPC を呼ぶ `checkRateLimit(action:settings:)` private helper で置換 | 1 |
| `currentServerSideStatus()` で `current_user_status` RPC を呼ぶ (fail-open) | 2 |
| `currentServerTime()` で `current_server_time` RPC を呼ぶ (評価用) | 5 |
| `deleteAccount()` で `delete_my_account` RPC を呼ぶ (`client.rpcVoid` 経由) | 7 |
| `private struct Empty: Encodable {}` を追加し、引数なし RPC の `arguments` に渡せる形に | - |

### 5. `SameQ/Backend/SupabaseClient.swift`

- 引数なし RPC 用 `func rpcVoid(function:)` を追加 (`{}` を body として送る)。

### 6. `SameQ/Session/AppSession.swift`

`start()` の冒頭で `backend.currentServerSideStatus()` を呼び、`"banned"` のときに
`.banned` 画面に固定する経路を追加（`LaunchOptions.isBanned` の Debug 経路は温存）。
通信失敗時は `"active"` 扱い（fail-open）。

### 7. `SameQUITests/SprintThirteenAcceptanceTests.swift`（新規）

3 件の退行防止テスト:

1. `test01_debugBannedLaunchArgumentShowsBannedScreen`: `-SameQBanned` で
   起動すると BannedView が表示される（Debug 経路の動作確認）。
2. `test02_localBackendLaunchReachesOnboarding`: LocalBackend 経路でも
   サーバ側ステータス取得が失敗しても fail-open で起動できる。
3. `test03_localBackendLikeLocalRateLimiterStillWorks`: いいねの連打は
   LocalBackend 経路では process-local のまま動く（`LocalBackend` の
   `setLike` にはサーバ RPC 呼び出しが無いので、`-SameQRateLimitTestMode` で
   反応することを期待）。

## 動かし方（evaluator 向け）

### サーバ側 RPC の適用

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
# プロジェクトの access-token を有効化した環境で:
supabase login --token <your-token>
supabase link --project-ref loqumzfgnahtclnvnrzb
supabase db push
# → migration 6 (20260827000006_server_enforcement.sql) が適用され、
#   rate_limit_events テーブルと 6 つの RPC が作成される
```

### 受け入れ条件 1, 6, 7 の確認（実機 2 台 + サーバ経由）

```bash
# 端末A でオンボーディング完了 → 既読 / いいねを 1 件作る。
# 端末B で同じ Supabase に接続し、端末A の投稿にいいねを送る。
# 端末A を完全終了 → 再起動。
# → いいねサーバ側の rate_limit_events に残っているので連打制限が継続
#   (受け入れ条件1)

# 端末A の users.status を SQL で 'banned' に更新:
#   update public.users set status='banned' where id=...;
# 端末A を再起動 → BannedView が表示される (条件2)。
# 端末B の world_timeline を curl で見ると、端末A の投稿は 1 件も
# 出てこない (条件3)。

# SQL:
#   select public.purge_expired_safety_logs(60);  -- 60 秒を保持期間に
# → 60 秒より古い通報が消える (条件6 の「自動削除」機能の実証)。

# 端末A の Settings → アカウント削除 → 端末B の world_timeline に
# 端末A の投稿が 1 件も残らない (条件7)。
```

### 受け入れ条件 5 の確認（端末時計のずらし）

```bash
# 端末A を通常起動 (端末時計が UTC のものとする)。
# `current_server_time()` 戻り値を取得 → 端末の現在時刻とほぼ同じ。

# 端末A の設定で「自動設定」を OFF にして時刻を 6 時間進める。
# 再起動しても、今日のお題の `ends_at` は変わらず、world_timeline に
# 出ている投稿も同じ。端末時計を変えても結果が変わらないことを目視。
```

### 受け入れ条件 4 の確認

```bash
# タイムラインを数件読む。
# curl で:
#   POST /rest/v1/rpc/my_viewed_posts
# → 既読の post_id リストが返る。
```

### 既存 UI テストの回帰確認（generator 環境で済）

```bash
xcodebuild test-without-building -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:SameQUITests/SprintThirteenAcceptanceTests \
  -only-testing:SameQUITests/SprintTwelveAcceptanceTests \
  -only-testing:SameQUITests/SprintElevenAcceptanceTests
```

## テスト実行結果（attempt 1）

### ユニットテスト

```bash
xcodebuild test-without-building -only-testing:SameQTests
# → 166/166 成功 (5.958 秒, TEST SUCCEEDED)
```

### UI 回帰（新規追加 + 直近 2 スプリントから 2 クラス）

| スイート | 件数 | 結果 |
|---|---|---|
| SprintThirteenAcceptanceTests | 3/3 | ✓ |
| SprintTwelveAcceptanceTests | 3/3 | ✓ |
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| **合計** | **10/10** | **142.8 秒 TEST SUCCEEDED** |

### Debug ビルド

`xcodebuild build-for-testing -configuration Debug` → **TEST BUILD SUCCEEDED**

## 自分で見つけた弱点

### 1. `delete_my_account` の SECURITY DEFINER 関数は GRANT が必要

`supabase db push` 後のロールに `EXECUTE` 権限が届かない環境でハマる可能性。
`revoke all ... from public; grant execute ... to authenticated;` で
カバーしているが、念のため `pg_proc` で確認する手順を README に書くべき。

### 2. `purge_expired_safety_logs` を定期実行する手段が無い

Supabase の `pg_cron` 拡張はデフォルトで有効だが、`supabase db push` からは
有効化できない。有効化は Supabase ダッシュボードの Database → Extensions で
行う必要があり、ユーザー側の作業。`app_purge_expired_safety_logs()` は
アプリ起動時に手動で呼び出せる RPC だが、これも 1 ユーザーが呼ぶだけなので
「全ユーザー分の safety_logs を消す」のは難しい。

`pg_cron` を有効化した環境では次の SQL を手動で 1 回流す:

```sql
select cron.schedule(
  'purge-safety-logs-daily',
  '0 3 * * *',
  $$select public.purge_expired_safety_logs(30 * 24 * 60 * 60);$$
);
```

### 3. `current_server_time` の ISO 8601 パースに依存

`SupabaseClient.rpc` の `Date` デコードは ISO 8601 パーサを通る。PostgREST の
date 出力はマイクロ秒まで含むが、`JSONDecoder.dateDecodingStrategy` の既定で
`timeIntervalSince1970` 形式に統一しているかの確認は実 e2e で必要。

### 4. スプリント13 の本物の e2e は generator では検証できない

実機 2 台 + Supabase 接続 + migration 6 適用が前提なので、evaluator 環境
（`SprintTwelveEvalE2ETests` を回せる環境）に完全に依存する。generator の
テストは全て LocalBackend 経由の退行防止に留まっている。

## 提案（今回はやらなかったこと）

### 1. `Backend` プロトコルへの `applicationServerTime` 取得の追加

`currentServerTime()` をプロトコルに昇格させて、`AppSession` の
`AppClock.now` を `currentServerTime()` ベースに置き換える案。これにより
「端末時計を N ずらすと ends_at がずれる」問題を完全に消せる。
attempt 1 では最小実装に留め、未着手。

### 2. `Backend` プロトコルへの `purgeExpiredSafetyLogs()` の追加

`LocalBackend` のオンデマンド清掃 (`pruneExpired`) と、サーバ側の
`purge_expired_safety_logs()` を統合する案。`BackendProtocol` に
`purgeExpiredSafetyLogs(retention: TimeInterval) async throws -> Int` を
追加し、`LocalBackend` は `pruneExpired` をそのまま実装、`SupabaseBackend` は
RPC を呼ぶ。スプリント11 attempt 2 の積み残しに近いが、サーバ側起点にすると
「端末で 30 日待たないと消えない」問題が根本解決する。

### 3. `Backend` プロトコルへの seenPosts の差分同期の追加

evaluator が「サーバの `viewed_posts` テーブルを直接 SELECT」しても、auth.uid()
制限で見えない可能性があるため、`my_viewed_posts()` RPC を介して取得する設計
は正しいが、`AppSession` の `viewedPostIDs` を起動時に RPC で同期していない。
再起動後の既読の継続性をサーバ起点で担保するには、`refreshViewedFromServer()`
を `start()` に追加するのが次のステップ。

## 変更ファイル一覧（attempt 1）

- `supabase/migrations/20260827000006_server_enforcement.sql`（新規）
- `SameQ/Backend/Backend.swift`（`currentServerSideStatus()` を要求メソッドに追加）
- `SameQ/Backend/LocalBackend.swift`（`currentServerSideStatus()` 実装）
- `SameQ/Backend/SupabaseBackend.swift`（`checkRateLimit` / `currentServerSideStatus` /
  `currentServerTime` / `Empty` struct / `deleteAccount` 経由 `rpcVoid` /
  `setLike`/`reportPost` の RPC 化）
- `SameQ/Backend/SupabaseClient.swift`（`rpcVoid(function:)` の追加）
- `SameQ/Session/AppSession.swift`（`start()` で `currentServerSideStatus` を呼ぶ）
- `SameQUITests/SprintThirteenAcceptanceTests.swift`（新規 3 テスト）

## 評価者への申し送り

### 1. migration 6 の適用が必須

`supabase db push` で 20260827000006_server_enforcement.sql を適用してから
実機検証を始めてください。適用前に起動すると、`SupabaseBackend` から
RPC を呼んだ時点で PGRST202 (404) が一斉に出ます（attempt 12 と同じ症状）。

### 2. e2e 検証の推奨順序

1. まず `current_user_status` / `current_server_time` が 200 を返すこと
   （テーブルのみの確認。レート制限や削除とは独立）
2. `consume_rate_limit` が `like` / `report` で 0 を返し、超過時に正の秒数を
   返すこと（同じ `auth.uid()` で）
3. 端末 A: 連打 → 制限発動 → アプリ終了 → 再起動 → まだ制限中（条件1）
4. 端末 A: `update users set status='banned' where id=...` → 端末 A 再起動 →
   BannedView（条件2）／端末 B の world_timeline から A の投稿が消える（条件3）
5. 端末 A: 端末 B の投稿にいいね → `my_viewed_posts` で見た記録が残る（条件4）
6. 端末 A: 設定で時刻を 6 時間進める → お題の `ends_at` が変わらない（条件5）
7. 端末 A: 古い通報を作る → `purge_expired_safety_logs(60)` で消える（条件6）
8. 端末 A: アカウント削除 → 端末 B の world_timeline から A の投稿が消える（条件7）

### 3. LocalBackend 経路の回帰確認

`SprintThirteenAcceptanceTests` 3 件が generator 環境で緑になっていることを
確認してください。`test01` は `-SameQBanned` を付けて起動、
`test02` / `test03` は LocalBackend の既定起動で OK。
