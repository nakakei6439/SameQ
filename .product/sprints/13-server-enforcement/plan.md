# スプリント 13: サーバー側で担保する制限・停止・保持（F36）

## 受け入れ条件（spec.md 320〜331 行）
- [ ] 連打制限がサーバー側で判定され、アプリを再起動しても解除されない
- [ ] BAN がサーバー側の users.status で判定され、ローカルでは切り替え不能
- [ ] BAN されたアカウントの回答は他端末のタイムラインに出ない
- [ ] 既読がサーバー側 (viewed_posts) に記録される
- [ ] お題の有効期間判定がサーバーの now() で行われ、端末時計をずらしても同一
- [ ] 期限切れ投稿が 30 日サーバー保持 + 自動削除
- [ ] アカウント削除が他端末のタイムラインに伝播する

## 実装方針（attempt 1）

スコープが広いので、ジェネレータ側で完結できる「サーバー側に永続化されるべき
事実のサーバー化」を中心に進める。2 台実機での e2e 検証は evaluator の担当。

### 1. 連打制限をサーバー側へ (条件 1)
- 新テーブル `rate_limit_events(user_id, action, occurred_at)` を新設
- `security definer` RPC `consume_rate_limit(p_action text, p_max int, p_window_seconds int)`
  を実装。スライディングウィンドウで閾値超過なら `retry_after_seconds` を返し、
  そうでなければイベントを記録して `0` を返す
- `SupabaseBackend.setLike`/`reportPost` のローカル `likeLimiter`/`reportLimiter`
  を撤去し、RPC を呼ぶように変更。スローされたエラーは
  `BackendError.rateLimited(action:retryAfterSeconds:)` に変換する
- これで「アプリを再起動しても解除されない」が構造的に担保される

### 2. BAN をサーバー側ステータスで判定 (条件 2, 3)
- `SupabaseBackend.start()` 経路で `users.status` を取得する RPC
  `current_user_status()` を新設。`active` 以外なら `.banned` 画面へ
- ローカルの `-SameQBanned` は Debug 限定の足場として温存
  （evaluator が `users.status = 'banned'` を作る手段は Supabase ダッシュボード
  またはサービスロールでの SQL 経由）
- BAN されたユーザーの投稿は `world_timeline` ビューの
  `u.status = 'active'` 条件で既に除外済み（migration 4）

### 3. 既読のサーバー化 (条件 4)
- `viewed_posts` テーブルへの INSERT は既にある（migration 1, 4）
- evaluator が「サーバー側の viewed_posts を確認できる」よう
  `read_viewed_posts` RPC または RLS を介した SELECT で検証可能にする
  （SupabaseBackend は既読をローカルでもキャッシュしている）

### 4. お題の有効期間をサーバーの now() に揃える (条件 5)
- `world_timeline` ビューと `promptState` のフィルタは既に Supabase の `now()`
  を使用（`ends_at > now()`）。クライアント側の PromptState も DB の結果を
  正として扱うことで、デバイスの時計ずれの影響を受けない
- 端末時計をずらした検証は evaluator 担当（サーバ側で再評価すれば同一結果）

### 5. 期限切れ投稿の 30 日保持と自動削除 (条件 6)
- 新規 migration 6 に `purge_expired_safety_logs()` 関数を追加
- pg_cron 拡張があればスケジュール、無ければ Edge Functions / Scheduled
  を前提に、関数単体で「n 秒より古い safety log を消す」ロジックを提供
- アプリ側からは `deleteExpiredSafetyLogs()` RPC を提供し、Debug 限定で
  検証 (`-SameQSafetyLogRetentionSeconds` のサーバ版)

### 6. アカウント削除の伝播 (条件 7)
- 新 RPC `delete_my_account()` を新設: `security definer` で
  `auth.users.delete()` を呼ぶ（`cascade` で posts/likes/blocks/viewed_posts
  /reports も消える）。
- `SupabaseBackend.deleteAccount()` からこの RPC を呼ぶように変更。
  ローカルの state は従来どおりクリア

## 影響範囲
- 既存テストはすべて LocalBackend 経由（`-SameQUseLocalBackend`）なので
  SupabaseBackend の修正で壊れない。新規 `SprintThirteenAcceptanceTests` を追加
- `LikeLimiter` / `ReportLimiter` の SupabaseBackend 側の使用を撤去→
  `RateLimiter.swift` 自体は LocalBackend 用に残る
- 同梱シードを 1 件「BAN ユーザー」として登録するオプションを
  `-SameQBanned` と整合させて追加（Debug 限定）。これは attempt 2 以降
  でもよい

## 検証計画
- ユニット: `SameQTests` がすべて緑（166/166 維持）
- UI: `SprintThirteenAcceptanceTests` を新規追加（3〜4 本）
- 回帰: 直近 2〜3 スプリント（SprintEleven/Twelve/Nine）から 3 クラス
- ビルド: Debug + Release 両方で BUILD SUCCEEDED

## 持ち越し（attempt 2 以降）
- pg_cron による自動実行（Supabase 側でスケジュール設定が必要、ユーザー作業）
- 実機 2 台での e2e（生成 BAN • 連打制限 • 削除伝播を確認）
