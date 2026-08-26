# スプリント 12: サーバー接続（1つの世界を共有する）

## 受け入れ条件（spec.md から転記）
- [ ] 端末Aで投稿した回答が、端末Bのタイムラインに他人の回答として表示される。端末Bを終了して再起動しても表示される
- [ ] 同じ時刻に端末Aと端末Bで開くと、「今日のお題」の文面と残り時間が同一である
- [ ] 端末Bが端末Aの回答にいいねを押すと、端末Aの画面で自分が受け取ったいいねの総数が1増える
- [ ] 端末Aで端末Bの回答を通報またはブロックすると、端末Aの表示対象から即座に消え、端末Bには通知も表示も一切現れない
- [ ] お題の終了時刻を過ぎた回答は、端末Bのタイムラインに1件も表示されない
- [ ] 通信できない状態（機内モード）で起動すると「接続してください」に相当する説明が表示され、白紙・無限ローディング・クラッシュにならない。通信を回復すると、アプリを入れ直さずに通常の画面へ戻れる
- [ ] 投稿・いいね・通報・ブロックが通信の失敗で完了しなかった場合、失敗したことが画面上に表示され、同じ操作をもう一度試せる（無言で成功したように見えることがない）
- [ ] 端末に同梱された検証用の擬似的な回答は、通常の操作からは1件も表示されない

## 実装方針

### 1. SupabaseBackend（新規ファイル）
`Backend` プロトコルを実装する `actor`。URLSession 経由で Supabase の REST API（PostgREST + GoTrue Auth）を直接呼ぶ。外部 SDK は使わず、純粋な Foundation のみで構成する（「外部パッケージ依存はゼロ」方針の維持）。

- `SameQ/Backend/SupabaseBackend.swift` — `Backend` 実装本体
- `SameQ/Backend/SupabaseClient.swift` — HTTP クライアント（URLSession をラップ、JSON デコード、エラー型を定義）
- `SameQ/Backend/SupabaseConfig.swift` — プロジェクト URL と publishable key の定数（`.env.local` から）
- `SameQ/Backend/SupabaseError.swift` — `BackendError` を拡張する Supabase 固有エラー

### 2. 認証（Anonymous Auth）
- `POST /auth/v1/signup` で匿名ユーザー作成
- アクセストークンを `state.json` に永続化（`PersistedState.supabaseAuth` を追加、schemaVersion 6→7）
- `Authorization: Bearer <token>` を全リクエストに付与
- 401 応答時はトークンクリア → 起動時フローで再認証

### 3. PostgREST CRUD
すべてのテーブルを `actor` 内の `SupabaseClient` 経由で読み書き：
- `GET /rest/v1/prompts?starts_at=lte.now&ends_at=gt.now&limit=1` → 現在のお題
- `GET /rest/v1/users?id=eq.<uid>` → 自分のプロフィール
- `POST /rest/v1/users` → 初回設定時のアカウント作成（`id = auth.uid()`）
- `PATCH /rest/v1/users?id=eq.<uid>` → プロフィール更新
- `GET /rest/v1/posts?prompt_id=eq.<pid>&author_id=eq.<uid>&limit=1` → 自分の回答
- `POST /rest/v1/posts` → 回答投稿（DB トリガーで `expires_at` 自動設定）
- `GET /rest/v1/world_timeline?prompt_id=eq.<pid>` → 他人の回答
- `POST /rest/v1/likes` / `DELETE /rest/v1/likes` → いいね
- `POST /rest/v1/reports` → 通報
- `POST /rest/v1/blocks` / `DELETE /rest/v1/blocks` → ブロック
- `GET /rest/v1/viewed_posts?user_id=eq.<uid>` / `POST` / `DELETE` → 既読
- `GET /rest/v1/posts?author_id=eq.<uid>&select=id,likes(count)` → 自分の投稿への受信いいね数

### 4. オフライン対応（受け入れ条件6）
- `NWPathMonitor` でネットワーク到達性を監視
- `start()` / `refresh()` でオフライン検出時は `.waiting(message: "接続してください")` を画面に出す
- オンライン復帰を監視し、画面状態を自動復旧（再起動不要）

### 5. 失敗表示（受け入れ条件7）
- `submitPost` / `setLike` / `reportPost` / `blockAuthor` で `URLError` 等が投げられた場合、`alertMessage` にユーザー向けメッセージを設定
- 既存の `alertMessage` 経路をそのまま使う

### 6. 受信いいね数（受け入れ条件3）
- `Backend.receivedLikeCount(forMyPostID:) async throws -> Int` を追加（プロトコル拡張）
- `TodayPromptView.answeredSection` の末尾に「◯ 件のいいね」を追加
- 起動時 + 1秒ごとの `refresh()` で最新値を取り直す（Realtime は使わない）

### 7. バックエンド切替
- `BackendProvider.make()` を `SupabaseBackend` を返すように変更
- Debug 限定の `-SameQUseLocalBackend` で `LocalBackend` にフォールバック可能に（テスト用）
- 接続切り替え時に端末内データを読み込まない（初回設定からやり直し）

### 8. 同梱シードの扱い（受け入れ条件8）
- `BackendProvider.make() == SupabaseBackend()` のときは `SeedCatalog.loadScheduleWithAutoGeneration` を呼ばない
- `LocalBackend` 経路は今までどおり（テスト用）
- Supabase 接続時は `prompts` / `posts` テーブルから直接取得するのでシードは到達不能

## 影響範囲
- 既存の `LocalBackend` テストは引き続き動く（バックエンド切替で `LocalBackend` を直接注入できる）
- 既存テストのうち `Backend` プロトコルの呼び出しに依存するものは影響なし
- `TodayPromptView` / `RootView` にUI追加（小さい範囲）
- `PersistedState.schemaVersion` を 6 → 7 にバンプ（後方互換のため `init(from:)` で `supabaseAuth` を `decodeIfPresent`）
- 新しい Supabase 用マイグレーション `20260819000004_server_connection.sql` が必要（RLS の微調整、`posts.likes_count` ビュー等）

## 検証方針
- 既存ユニットテスト（77件）すべて引き続き通過
- 新規ユニットテスト 6本（SupabaseClient の URLSession モックで認証・CRUD・401再認証）
- 新規 UI テスト 4本（オフライン表示・失敗メッセージ・通常起動の3台シナリオ）
- ビルド成功（xcodebuild Debug + simulator）
- 実機検証は次回 evaluator（2台以上）

## 申し送り
- 本実装は「外部パッケージ依存ゼロ」を維持するため、Supabase Swift SDK は使わず URLSession で REST を直叩きする
- `.env.local` のキーは機密扱いなので、Swift の定数として直接書く（gitignore 対象ではない `SameQ/Backend/SupabaseConfig.swift` に集約）
- 2台検証は evaluator の責任範囲。generator は自前でシミュレータ2台起動してスモーク確認する
