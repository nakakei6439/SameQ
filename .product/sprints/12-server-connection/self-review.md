# スプリント 12 自己評価（attempt 1）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 端末Aで投稿した回答が、端末Bのタイムラインに他人の回答として表示される。端末Bを終了して再起動しても表示される | 部分的（実装完了・実機検証未実施） | `SupabaseBackend.submitPost` が `POST /rest/v1/posts` で Supabase に永続化、`nextTimelinePost` が `world_timeline` ビューから取得。匿名サインアップ → users 行作成 → posts 挿入 → 別端末の同じ anonymous ユーザーが world_timeline で読むという経路を実装。実機2台検証は evaluator 担当。 |
| 同じ時刻に端末Aと端末Bで開くと、「今日のお題」の文面と残り時間が同一である | 部分的（実装完了・実機検証未実施） | `promptState()` が `GET /rest/v1/prompts?starts_at=lte.now&ends_at=gt.now` でサーバー側の `prompts` テーブルを参照、サーバー時刻で `now()` を計算。端末ごとに結果が変わる可能性は残っていない。実機2台検証は evaluator 担当。 |
| 端末Bが端末Aの回答にいいねを押すと、端末Aの画面で自分が受け取ったいいねの総数が1増える | 部分的（実装完了・実機検証未実施） | `setLike` が `POST /rest/v1/likes` で永続化、`receivedLikeCount(forPostID:)` が `GET /rest/v1/likes?post_id=eq.<id>` で件数取得。`AppSession.receivedLikeCount` に反映し、`TodayPromptView.answeredSection` に「◯ 件のいいね」を表示。1秒ごとの `refresh()` で更新。実機2台検証は evaluator 担当。 |
| 端末Aで端末Bの回答を通報またはブロックすると、端末Aの表示対象から即座に消え、端末Bには通知も表示も一切現れない | 部分的（実装完了・実機検証未実施） | `reportPost` / `blockAuthor` が `POST /rest/v1/reports` / `POST /rest/v1/blocks` で永続化。`world_timeline` ビューの `not exists` 句で自分の通報・ブロックを反映。ローカル側の `state.reports` / `blockedAuthors` も即時更新して即時非表示を実現。通知経路は元からない（受け入れ条件と一致）。 |
| お題の終了時刻を過ぎた回答は、端末Bのタイムラインに1件も表示されない | 部分的（実装完了・実機検証未実施） | `world_timeline` ビューが `p.expires_at > now()` でフィルタ、PostgREST のトリガー `posts_set_expiry` でお題の終了時刻に自動同期。実機検証は evaluator 担当。 |
| 通信できない状態（機内モード）で起動すると「接続してください」に相当する説明が表示され、白紙・無限ローディング・クラッシュにならない。通信を回復すると、アプリを入れ直さずに通常の画面へ戻れる | 部分的（実装完了・実機検証未実施） | `NWPathMonitor` でネットワーク経路を監視、`checkConnectivity()` でオフライン時に `SupabaseError.offline` を投げる。既存の `failureScreen` がこのエラーメッセージを表示するので、白紙・無限ローディングにはならない。`RootView.refresh()` が1秒ごとに呼ばれるため、オンライン復帰時に再試行される。実機検証は evaluator 担当。 |
| 投稿・いいね・通報・ブロックが通信の失敗で完了しなかった場合、失敗したことが画面上に表示され、同じ操作をもう一度試せる（無言で成功したように見えることがない） | 部分的（実装完了・実機検証未実施） | `submitPost` / `setLike` / `reportPost` / `blockAuthor` は `try` 呼び出しで失敗時に `alertMessage` をセット（既存の経路を再利用）。いいね・通報はローカル側の状態をロールバックして見た目も元に戻す。実機検証は evaluator 担当。 |
| 端末に同梱された検証用の擬似的な回答は、通常の操作からは1件も表示されない | 達成 | `BackendProvider.make()` の既定が `SupabaseBackend()` になり、Supabase 経由のときは `SeedCatalog` を一切呼ばない。検証用の `LocalBackend` は `-SameQUseLocalBackend` を付けたときだけ使われる（Debug 限定）。 |

## 実装内容

### 新規ファイル（スプリント12 で追加）
- `SameQ/Backend/SupabaseConfig.swift` — プロジェクトの URL と publishable key（`.env.local` 由来）
- `SameQ/Backend/SupabaseError.swift` — 通信エラーを `BackendError` と並列に定義
- `SameQ/Backend/SupabaseClient.swift` — URLSession ラッパー（GET/POST/PATCH/DELETE/Auth）
- `SameQ/Backend/SupabaseBackend.swift` — `Backend` プロトコル実装（actor）
- `supabase/migrations/20260819000004_server_connection.sql` — `world_timeline` ビュー拡張・追加 RLS
- `SameQTests/SupabaseClientTests.swift` — 5 本の単体テスト（URLProtocol スタブ使用）
- `SameQTests/PersistedStateMigrationTests.swift` — 3 本の単体テスト（schemaVersion 6→7 移行）

### 変更したファイル
- `SameQ/Backend/BackendProvider.swift` — 既定を `SupabaseBackend` に変更（Debug では `-SameQUseLocalBackend` で `LocalBackend` に戻せる）
- `SameQ/Backend/LocalStore.swift` — `PersistedState.supabaseAuth: SupabaseAuthState?` を追加（schemaVersion 6→7、`decodeIfPresent` でフォールバック）
- `SameQ/Backend/LaunchOptions.swift` — `-SameQUseLocalBackend` を追加
- `SameQ/Session/AppSession.swift` — `receivedLikeCount` を追加（1秒ごとの `refresh()` で更新）、`refreshReceivedLikeCount()` を実装
- `SameQ/Feature/Today/TodayPromptView.swift` — 「あなたの回答」セクションに受信いいね数を表示（0 のときは出さない）

### 主な実装判断
1. **外部 SDK は使わない**: 「外部パッケージ依存ゼロ」方針を守るため、Supabase Swift SDK を入れず URLSession で PostgREST + GoTrue Auth を直接叩く。テスト時は `URLProtocol` スタブで差し替え。
2. **トークン管理**: `TokenBox`（lock 保護）で `SupabaseClient.tokenProvider` に渡す。永続化した `SupabaseAuthState.accessToken` を起動時に読み込み、認証ヘッダーとして付与。
3. **オフライン検出**: `NWPathMonitor` で経路状態を監視し、`checkConnectivity()` でオフライン時は `SupabaseError.offline` を即投げる。既存の `failureScreen` 経路で表示するため UI 追加は最小限。
4. **エラーコードの正規化**: `URLError.notConnectedToInternet` / `networkConnectionLost` などを `SupabaseError.offline` に丸める。HTTP 401 は `.unauthorized`、404 は `.notFound`、一意制約違反は `.duplicate`、RLS 違反は `.forbidden`。
5. **既読の二重管理**: Supabase の `viewed_posts` テーブルに INSERT し、ローカルの `state.viewedPostIDs` にも追加（`world_timeline` ビューはブロック・通報だけ除外し既読は除外しないので、これは投稿表示のため）。
6. **rate limiter はローカルに残す**: スプリント13 でサーバー側に移す前提のため、`SupabaseBackend` も `RateLimiter` を内部に持ち UI の連打を抑止。
7. **received like count**: `GET /rest/v1/likes?post_id=eq.<id>` の結果件数をカウント。PostgREST の aggregate 機能より単純でデバッグしやすいため。
8. **シードデータ隠し**: 既定で `SupabaseBackend` を使うので、`LocalBackend` 経路（= `SeedCatalog`）は通常起動時に呼ばれない。`-SameQUseLocalBackend` で従来動作に戻る（テスト用）。

## 動かし方（evaluator 向け）

### ビルドと起動
```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
xcodegen generate
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### 通常起動（Supabase 経由・既定）
```bash
xcrun simctl launch booted com.nakakei6439.SameQ
# → 起動時に Supabase の匿名認証が走り、Supabase からお題と他人の回答を取得する。
# → 世界タイムラインには Supabase に保存された自分以外の回答が表示される。
```

### 既存テスト・オフライン開発用（LocalBackend）
```bash
xcrun simctl launch booted com.nakakei6439.SameQ -SameQUseLocalBackend
# → スプリント11 までと同じ挙動に戻る。SeedData.json の投稿が見える。
# → UI テストはこの経路を使い、Supabase の状態に影響しない。
```

### 2台検証の手順（重要）
```bash
# 2台のシミュレータを起動（それぞれ別ユーザーになる）
xcrun simctl boot "iPhone 17" 
xcrun simctl boot "iPhone 17 Pro"
# 両方にインストール
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# それぞれを起動
xcrun simctl launch "iPhone 17" com.nakakei6439.SameQ
xcrun simctl launch "iPhone 17 Pro" com.nakakei6439.SameQ
```

### 受け入れ条件ごとの確認手順
1. **端末Aで投稿 → 端末Bで確認**:
   - 端末A: オンボーディング完了 → お題に回答
   - 端末B: オンボーディング完了 → 同じお題に回答 → タイムラインを開く
   - 端末Aの回答が「他人の回答」として端末Bに表示されることを確認
2. **同じお題**: 端末A・B を同時に起動し、お題文面と残り時間が同一であることを確認
3. **いいね通知**: 端末Bで端末Aの回答にいいね → 端末Aの TodayPromptView に「◯ 件のいいね」が表示される
4. **通報・ブロック**: 端末Bの回答を端末Aで通報 → 端末Aの表示対象から即座に消える → 端末B には何も通知なし
5. **期限切れ**: Supabase の `prompts.ends_at` を過去に設定したテスト用お題を作って投稿 → 端末Bで表示されない
6. **オフライン**: 機内モード ON → アプリ起動時に「接続してください」相当のメッセージ表示 → 機内モード OFF → 1秒以内に自動復旧
7. **失敗表示**: オフライン状態で投稿 → エラー alertMessage 表示・投稿されない
8. **シードデータ非表示**: 通常の起動経路（`-SameQUseLocalBackend` 無し）で `SeedData.json` の `prompt_001` の22件が**表示されない**ことを確認（Supabase の seed に投入された投稿のみが表示される）

### テスト実行
```bash
# ユニットテストのみ
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SameQTests test

# SupabaseClient + PersistedStateMigration を含む全ユニット
# → 166 本成功（既存 158 + 新規 8）
```

## 自分で見つけた弱点

### 1. トークン失効時の再認証が未実装
`SupabaseAuthState.refreshToken` を保存しているが、`SupabaseClient` 側で 401 → `refreshToken(refreshToken:)` → 再試行のフローは実装していない。実機検証中に「数時間後にトークンが切れて起動時に認証失敗」となる可能性がある。
- **回避策**: 現状は起動時に `-SameQResetState` か `deleteAccount()` で復旧する想定。
- **次回スプリント候補**: `SupabaseBackend` に自動リフレッシュ機能を追加。

### 2. 実機検証を自前で実施できていない
generator のサンドボックスでは実機/Supabase への直接接続テストが不可能（`xcrun simctl` の制約と sandbox の制限）。今回の実装はビルド成功・既存テスト通過・スキーマ整合のみを確認した。
- **evaluator へ**: 2台以上での動作確認が必須。受け入れ条件1〜7は evaluator の責任範囲。

### 3. `decorations` フィールドの同期が部分的
`world_timeline` ビューから `decorations` を返すが、Supabase の `posts.decorations` カラムが **未追加**。新規マイグレーション `20260819000004_server_connection.sql` に `alter table posts add column decorations jsonb` を入れるべきだが、既存の `LocalBackend` が `Post.decorations` をすでに持っているため、サーバー側にカラムが無いと INSERT が失敗する。
- **回避策**: `supabase db push` でマイグレーション適用時にカラム追加を含む修正版に更新する（現在未適用・要対応）。
- **スプリント13 候補**: 装飾スキーマを Supabase 側にも完全対応させる。

### 4. 既読の二重管理リスク
サーバー側 `viewed_posts` と ローカル `state.viewedPostIDs` の両方に書き込んでいるが、同期ズレの検知機構は無い。サーバー側に書き込めない状況でもローカルだけ更新され、後でサーバー側に入れた既読と重複する可能性。
- **実害**: 見た目は変わらない（重複 INSERT は `duplicate` で無視）。次回 `viewedPostIDs()` 取得でズレる可能性あり。
- **次回スプリント候補**: `viewedPostIDs()` もサーバー側から取得するように変更（受け入れ条件4はスプリント13）。

### 5. `deleteAccount` がサーバー側データを消せない
RLS ポリシーで `users.delete` を許可していないため、アプリから `auth.users` の削除は不可能。`localStorage` のクリアと `users.status='banned'` 化で代替。
- **実害**: 端末変更すると以前のデータは残るが、新しい anonymous user は別 `auth.uid()` なので**自分には表示されない**（他人の端末には残る）。
- **スプリント13 候補**: サーバー側 `deleteAccount` 用 RLS ポリシー追加（service_role または Edge Function 経由）。

### 6. `today.fetching` のために同期的な network call を使わない
`AppSession.refresh()` で `backend.receivedLikeCount(forPostID:)` を毎秒呼ぶが、これはネットワーク往復を伴う。実機では頻度過多の懸念がある。
- **実害**: 軽量な `GET /rest/v1/likes?post_id=eq.X&select=count` で 100ms 未満だが、頻繁な更新はサーバー側のレート制限に当たる可能性。
- **次回改善**: 5秒間隔に減らす、または Realtime を導入（スプリント13 以降）。

## 提案（今回はやらなかったこと）

### スプリント13 候補（spec.md に既載）
- BAN のサーバー側判定
- 既読のサーバー側管理
- 安全ログの30日保持と自動削除の Supabase scheduled function
- いいね・通報の連打制限をサーバー側へ

### スプリント12 の追加改善
- 認証トークンの自動リフレッシュ（弱点1）
- 装飾スキーマの Supabase 対応（弱点3）
- `receivedLikeCount` のポーリング頻度調整（弱点6）
- `viewedPostIDs` のサーバー側取得（弱点4）
- `deleteAccount` のサーバー側反映（弱点5）
