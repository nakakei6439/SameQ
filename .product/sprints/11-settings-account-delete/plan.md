# スプリント 11: 設定・アカウント削除・安全ログ

## 受け入れ条件（spec.md 281〜286行）
- [ ] 設定画面から利用規約とプライバシーポリシーが開いて読める
- [ ] 絵文字とニックネームを後から変更でき、変更後にタイムラインへ流れる自分の情報が新しい内容になる
- [ ] アカウント削除は確認ダイアログを挟み、実行後はアプリが初回設定からやり直しになる
- [ ] アカウント削除後、そのユーザーの回答は他ユーザーのタイムラインに表示されない
- [ ] 設定画面から購入復元が実行できる（**スプリント10 で実装済み・既存テストで再確認**）
- [ ] ユーザーの表示期限が切れた投稿も、安全対策のためのログとして目安30日はサーバー側に保持され、期間経過後は自動で削除される（運営側の確認手段で検証できる）

## 実装方針

**Backend プロトコル拡張** (`SameQ/Backend/Backend.swift`)
- `updateProfile(emoji:nickname:)` を追加（既存ユーザー情報の書き換え）
- `deleteAccount()` を追加（ユーザー本体と関連データ全削除）
- `Report` に `postExpiresAt: Date` を追加し、`safetyLogRetentionSeconds`（既定 30 日）を超えたら `pruneExpired` が自動削除する

**`LocalBackend` 実装** (`SameQ/Backend/LocalBackend.swift`)
- 上記 2 メソッドを実装。`updateProfile` はユーザー本体だけでなく `myPosts` の `authorEmoji` / `authorNickname` も遡って書き換える（受け入れ条件2「自分の情報が新しい内容になる」を満たすため）
- `deleteAccount` は `user` / `myPosts` / `likedPostIDs` / `viewedPostIDs` / `reports` / `blockedAuthors` / `lastPostBody` / `lastPrepareAttemptAt` を全て消去し、`discardedCandidatesCount` は積算なので残す（リセットしない）
- `pruneExpired` の `liveReports` を「`postExpiresAt + 30日` を過ぎていない報告」に変更。`Report` に `postExpiresAt` を保持し、後方互換は `decodeIfPresent` で `createdAt + 28h` をフォールバック（受け入れ条件6）

**`PersistedState`** (`SameQ/Backend/LocalStore.swift`)
- schemaVersion を 5 → 6 にバンプ
- `Report` フィールド追加のみ・既存値の破壊的変更はしない

**`AppSession`** (`SameQ/Session/AppSession.swift`)
- `updateProfile(emoji:nickname:)` を追加し `user` を更新
- `deleteAccount()` を追加し、Backend 削除後に `screen = .onboarding` に戻す（`myPost` / `likedPostIDs` / `blockedAuthors` 等もクリア）
- 削除直後に `discardedCandidatesCount` を除く全状態を空にする（再作成後のリーク防止）

**`SettingsView` 拡張** (`SameQ/Feature/Settings/SettingsView.swift`)
- 新セクション:
  - **プロフィール**: 現在の絵文字＋ニックネーム、「編集」ボタン → `ProfileEditView` を sheet
  - **規約・プライバシー**: 利用規約 / プライバシーポリシー を開くボタン → `LegalView` を sheet
  - **アカウント削除**: 赤いテキストのボタン、確認ダイアログ → 削除 → オンボーディングへ
- ブロック管理・通知・Plus は既存セクションをそのまま温存

**新規ファイル**:
- `SameQ/Feature/Settings/ProfileEditView.swift` — 絵文字ピッカー＋ニックネーム入力（既存 `EmojiCatalog` を流用）
- `SameQ/Feature/Settings/LegalView.swift` — 利用規約 / プライバシーポリシーの本文表示（既存 `LegalText` を流用）
- `SameQTests/ProfileAndAccountTests.swift` — updateProfile / deleteAccount の検証
- `SameQTests/SafetyLogRetentionTests.swift` — 30日保持と自動削除の検証（`clock` の offset で検証可能）
- `SameQUITests/SprintElevenAcceptanceTests.swift` — 受け入れ条件1〜4のUI検証

**変更ファイル**:
- `SameQ/Model/Safety.swift` — `Report.postExpiresAt` を追加
- `SameQ/Backend/Backend.swift` — プロトコル拡張
- `SameQ/Backend/LocalBackend.swift` — 新メソッド実装・pruneExpired 修正
- `SameQ/Backend/LocalStore.swift` — schemaVersion バンプ
- `SameQ/Session/AppSession.swift` — 新API・画面遷移
- `SameQ/Feature/Settings/SettingsView.swift` — 新セクション3つ

## 影響範囲

- **`myPosts` の絵文字/ニックネーム遡及更新**: 既存ユーザーが絵文字/ニックネームを変更したとき、自分の過去の投稿（期限内）が新しい情報で表示される。タイムラインの候補に既に出ている `Post`（シード由来）にも影響するので、`submitPost` 経由で `Post` を組み立てる箇所は全て `user.emoji` / `user.displayNickname` を読むため自然に新しくなる（既存実装でも `user` から値を取得しているはずだが、`myPosts` 内の古い `Post` 値を更新しないと過去の投稿に古い情報が出る）。
- **`Report.postExpiresAt` 後方互換**: schemaVersion 5 のファイルには `postExpiresAt` キーが無いので、`init(from:)` で `decodeIfPresent` し、無ければ `createdAt + 28h`（お題の標準有効期間）にフォールバック。新規の通報は正しい `postExpiresAt` を保存する。
- **既存テストへの影響**: `ReportBlockTests` の `Report` 構築は `postExpiresAt` の初期化が必要。新ヘルパー（`makeReport(post:reason:)`）に置き換える。

## 検証方針

- **ユニットテスト**:
  - `ProfileAndAccountTests`: 絵文字/ニックネーム変更が `user` と `myPosts` に反映される / アカウント削除後に再作成してもリーク無し
  - `SafetyLogRetentionTests`: 期限切れ後 29日では残存、31日経過で自動削除。`AppClock` の offset で検証可能
- **UIテスト**: `SprintElevenAcceptanceTests`（受け入れ条件1〜4を実操作）
- **回帰**: `SameQTests` + `SameQUITests`（既存スプリント01〜10）を全て実行し、脱落がないこと