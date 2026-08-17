# スプリント05: BAN・投稿頻度制限・スパム対策

## 受け入れ条件（spec.md 177〜183行から転記）
- [ ] 1つのお題に投稿できるのは1回だけで、投稿後にお題画面へ戻っても入力欄は再表示されず、自分の回答が表示される
- [ ] 直近の自分の投稿と同一の本文を別のお題に投稿しようとすると、拒否メッセージが出て投稿されない
- [ ] 空白・改行のみの投稿、および同一文字の過剰な繰り返しは拒否メッセージが出て投稿されない
- [ ] 短時間にいいねまたは通報を規定回数以上繰り返すと一時的に制限され、その旨が画面に表示される
- [ ] BAN状態のアカウントで起動すると、利用できない旨の画面が表示され、お題画面にもタイムラインにも入れない
- [ ] BANされたユーザーの回答は、他ユーザーのタイムラインに1件も表示されない

## 実装方針
1. **1お題1投稿**: 既存の `alreadyAnswered` チェックを確認するだけ（壊れていない）。
2. **同一文面連投拒否**: `PersistedState` に `lastPostBody`（お題をまたいで残る・pruneで消えない）を追加し、`submitPost` で直近投稿と完全一致なら `BackendError.duplicateBody`。
3. **無意味な文字列拒否**: `PostValidator.isMeaninglessRepetition` を新設（空白除去後、最頻出1文字の占有率が閾値以上なら拒否）。空白・改行のみは既存の `emptyBody` チェックで担保済み。
4. **いいね・通報の連打制限**: `RateLimiter`（スライディングウィンドウ、`Date` を受け取る純粋構造体）を新設し、`LocalBackend` に like 用・report 用を1つずつ持たせる。閾値は `LaunchOptions`（Debug限定 `-SameQRateLimitTestMode` で短縮可）。
5. **BAN（自分のアカウント）**: 運営用UIは作らない。Debug限定の起動引数 `-SameQBanned` で `AppSession.screen = .banned` に強制し、`BannedView` を表示。今日のお題・タイムラインへの経路は `RootView` の `switch` から外れるので到達不可。
6. **BANされた投稿者の非表示**: `SeedData.json` に `bannedAuthorIDs` を追加し、`PromptSchedule` が保持。`LocalBackend.visibleOthers` でこの集合を除外（`candidates` はここを経由するので自動的に効く）。既存の `-SameQAnswerCount` の件数系テストを壊さないよう、BAN対象の投稿は既存22件の**後ろ**に追加する新規1件のみとする。
7. **メッセージの日英対応**: 今回追加・変更する `BackendError`（duplicateBody / meaninglessBody / emptyBody / bodyTooLong / rateLimited）と `BannedView` の文言は、日本語行＋英語行を1つの文字列にまとめて両方常時表示する（既存の Localizable 基盤が無いため、範囲を絞った対応とする）。
8. **タイムラインのアラート未配線を解消**: `TimelineView` に `session.alertMessage` を出す `.alert` が無いため、いいね・通報の制限メッセージが表示できない。今回のスケジュール上不可欠なので追加する（スプリント04の改善提案[4]の一部を解消するが、範囲はこの受け入れ条件に必要な分のみ）。

## 影響範囲
- `PersistedState`（schemaVersion 4 へ）: 追加フィールドはデコード時デフォルト値で吸収、既存の移行テストは壊さない。
- `PromptSchedule` に `bannedAuthorIDs` を追加するが、デフォルト引数 `= []` を付けるので既存のテストコードでの直接生成箇所は変更不要。
- `BackendError` に新規ケース追加のみ（既存ケースの意味は変えない）。
- `-SameQAnswerCount` を使う既存テスト（スプリント03・04）の件数アサーションに影響しないことを、BAN対象を「既存シードの後ろに足す新規1件」にすることで担保する。
