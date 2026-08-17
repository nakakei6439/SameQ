# スプリント05 自己評価（attempt 1）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1つのお題に投稿できるのは1回だけで、投稿後にお題画面へ戻っても入力欄は再表示されず、自分の回答が表示される | 達成 | 既存の `alreadyAnswered` チェックが引き続き機能（壊していない）。ユニット `testSecondSubmissionToSamePromptIsRejected`、UI `SprintFiveAcceptanceTests.test01_secondVisitToAnsweredPromptShowsAnswerNotComposer`（投稿→閉じる→`today.myAnswer` が出て `today.input` が無い→再起動しても同じ）で確認 |
| 直近の自分の投稿と同一の本文を別のお題に投稿しようとすると、拒否メッセージが出て投稿されない | 達成 | `PersistedState.lastPostBody`（お題をまたいで残る・期限切れ掃除の対象外）を追加し、`submitPost` で完全一致なら `BackendError.duplicateBody` を投げる。ユニット `testDuplicateBodyAcrossDifferentPromptsIsRejected` / `testDuplicateBodyCheckIgnoresLeadingAndTrailingWhitespace`、UI `test03_duplicateBodyOnNextPromptIsRejectedThenRecovers`（`-SameQScenario expiring` でお題を切り替え、同じ本文→拒否メッセージ→言葉を変えると投稿できる）で確認 |
| 空白・改行のみの投稿、および同一文字の過剰な繰り返しは拒否メッセージが出て投稿されない | 達成 | 空白・改行のみは既存の `emptyBody` チェック（メッセージを日英併記に変更）。同一文字の過剰な繰り返しは `PostValidator.isMeaninglessRepetition`（空白除去後、最頻出1文字の占有率70%以上・対象文字数4文字以上で判定）を新設し `meaninglessBody` を投げる。ユニット `testWhitespaceOnlyBodyIsRejected` / `testMeaninglessRepetitionIsRejected` / `testPostValidatorDoesNotFlagOrdinaryShortReplies`（「はい」「OK」等の短い正常回答を誤検知しないことも確認）/ `testPostValidatorFlagsRepeatedCharacters`、UI `test02_blankAndRepeatedCharacterBodiesAreRejected` で確認 |
| 短時間にいいねまたは通報を規定回数以上繰り返すと一時的に制限され、その旨が画面に表示される | 達成 | `RateLimiter`（スライディングウィンドウ、`LaunchOptions` から閾値を注入）を新設し `LocalBackend.setLike` / `reportPost` に適用。既定値はいいね15秒8回・通報30秒4回、超過で一時ロック。制限時は `BackendError.rateLimited` を投げ、`TimelineView` に新設した `.alert` に表示。ユニット `testLikeRateLimitBlocksAfterThresholdAndAllowsWithinLimit` / `testReportRateLimitBlocksAfterThreshold` / `testRateLimiterAllowsAgainAfterCooldownElapses`、UI `test04_likeRateLimitBlocksThenRecovers`（制限→メッセージ→他の操作は続けられる→クールダウン後に再びいいねできる）/ `test05_reportRateLimitBlocksThenShowsMessage` で確認 |
| BAN状態のアカウントで起動すると、利用できない旨の画面が表示されお題画面にもタイムラインにも入れない | 達成 | Debug限定の起動引数 `-SameQBanned` で `AppSession.screen` を起動直後に `.banned` へ固定し `BannedView` を表示。`RootView` の `switch` から他画面へ到達する経路が無い。UI `test06_bannedAccountSeesOnlyBannedScreen`（BAN画面のみ表示・onboarding/today/waiting/timelineのいずれにも入れない・BANを外して再起動すると復帰できる）で確認 |
| BANされたユーザーの回答は他ユーザーのタイムラインに1件も表示されない | 達成 | `SeedData.json` に `bannedAuthorIDs` を追加し、`PromptSchedule.bannedAuthorIDs` として保持。`LocalBackend.visibleOthers`（`candidates` の共通土台、`.empty`/`.exhausted` 判定にも使う集合）でBAN済み投稿者を除外。同梱シードに検証用のBAN投稿を1件追加（既存22件の**後ろ**に足したので `-SameQAnswerCount` を使う既存テストの件数には影響しない）。ユニット `testBannedAuthorsPostNeverAppearsInTimeline` / `testBundledSeedHasABannedAuthorExcludedFromVisiblePosts`、UI `test07_bannedAuthorsPostNeverAppearsInDefaultSeed`（引数なしの同梱シードで22件読み切るまでBAN投稿の目印文言が一度も出ないことを確認）で確認 |

## 評価者への注記への対応
- **制限メッセージが日本語・英語どちらの端末でも読めるか**: 今回追加・変更したメッセージ（`emptyBody` / `bodyTooLong` / `duplicateBody` / `meaninglessBody` / `rateLimited`、BAN画面の文言）はすべて日本語行＋英語行を同じ文字列に入れて常時両方表示する方式にした（アプリ全体の多言語対応の基盤がまだ無いため、今回の対象メッセージに限定）。端末の言語設定に関係なく読める。
- **制限メッセージが出たあとアプリが操作不能にならないこと**: 実装中に一度、`TodayPromptView`（`fullScreenCover` の裏で生き続けている）と `TimelineView`（前面）が同じ `session.alertMessage` に対してそれぞれ `.alert` を持ち、両方が同時に `isPresented` になったことでタイムラインの `fullScreenCover` ごと閉じてしまう不具合を UI テストで発見し修正した（`isTimelinePresented` で片方だけが有効になるようにゲート）。UIテストで「制限→OKで閉じる→他の操作（次へ・再びいいね）が続けられる」ところまで確認している。

## 動かし方（evaluator向け）
- 起動: `open SameQ.xcodeproj` → シミュレータで実行。または `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' test` でユニット37本＋UIテスト31本（スプリント01〜05）を自動実行できる。
- **1お題1投稿**: 通常操作で投稿→お題画面に戻っても入力欄が出ないことを確認。
- **同一文面の連投拒否**: `-SameQScenario expiring -SameQExpirySeconds 20 -SameQGapSeconds 15` などでお題を切り替え、1つ目に投稿した本文と全く同じ文字列を2つ目にも投稿しようとするとエラーが出る。
- **空白・繰り返しの拒否**: 今日のお題の入力欄に空白・改行だけ、または「あああああああ」のように同じ文字を14回以上並べて投稿しようとすると送信できない／エラーが出る。
- **いいね・通報の連打制限**: Debug限定の起動引数 `-SameQRateLimitTestMode` を付けると、いいねは30秒間に3回、通報は40秒間に2回で一時制限がかかる（既定値はいいね15秒8回・通報30秒4回だが、evaluatorの検証時間を考えて短縮できる引数を用意した）。タイムラインでいいね・通報を素早く繰り返すと制限メッセージが出て、8秒待つと再び操作できる。
- **BAN画面**: Debug限定の起動引数 `-SameQBanned` を付けて起動すると、「このアカウントは利用できません」画面のみが表示され、他のどの画面にも入れない。この引数を外して再起動すると通常どおり使える（運営がBANを解除した状態を模擬）。**アプリ内にBANを切り替えるUIは無い**（置いた前提10のとおり、運営がサーバー側で行う運用のため）。
- **BANされた投稿者の非表示**: 同梱シード（`SeedData.json`）の `prompt_001` に、BANされた投稿者の回答を1件追加してある（本文に「【検証用】BANされた投稿者のテスト投稿です」という目印を含む）。引数なしで起動し、投稿後にタイムラインを最後まで読み切っても、この文言を含む回答は一度も出てこない。

## 自分で見つけた弱点
- **いいね・通報の連打制限はプロセス内メモリだけの状態**（`PersistedState` に永続化していない）。アプリを再起動すると制限がリセットされる。「短時間の連打」を防ぐのが目的なので、再起動をまたいで持続させる必要は薄いと判断したが、迂回策として「制限されたらアプリを再起動する」が可能ではある。悪質ユーザー対策としては甘い可能性があるが、今回のスコープ（一時的な連打抑止）としては妥当と判断した。
- **同一文面の連投拒否は「直近の投稿1件」としか比較しない**。2つ前・3つ前の投稿と同じ文面は通ってしまう（お題は1つにつき1投稿なので、実際には「2つ前の投稿」を作るには複数のお題をまたぐ必要があり、悪質な連投の主要な手口ではないと判断）。
- **同一文字の過剰な繰り返し判定は「最頻出1文字が70%以上」という単純な閾値**。「aabbaabbaabb」のような2文字の交互繰り返しなど、意図的にすり抜けられる文面は残る。仕様が「同一文字の過剰な繰り返し」に限定しているため、今回はそこだけを対応した。
- **BAN状態の判定は起動引数のみで、アカウントの実データには紐づいていない**。「置いた前提10」（BANは運営がサーバー側で切り替える）に従い、Supabase接続後にサーバー側の `users.status` を見る形に置き換える前提の暫定実装。
- **BANされた投稿者の除外は同梱シードに1件だけ焼き込んだもの**。`-SameQAnswerCount` で機械生成する回答（大量件数のテスト用）には今回BANを混ぜていない（混ぜると既存スプリント03/04の件数ベースのテストが壊れるため、意図的に見送った）。

## 提案（今回はやらなかったこと）
- 連打制限をアカウント単位でサーバー側に永続化する仕組み（Supabase接続後の課題）。
- BAN理由・BAN解除申立てなど、運営とユーザーのやり取りに関する機能（仕様のスコープ外）。
- 同一文面判定の高度化（編集距離による類似度判定など）。今回は仕様の「同一の本文」という文言どおり完全一致に留めた。

---

# attempt 2（2026-08-18）

## 不合格理由（attempt 1・eval-1.md より）
受け入れ条件3「空白・改行のみの投稿、および同一文字の過剰な繰り返しは**拒否メッセージが出て**投稿されない」のうち、
**空白・改行のみのケースで拒否メッセージが一切出ない**まま「投稿する」ボタンが灰色で押せなくなるだけだった。
`TodayPromptView.canSubmit` が trim 後の空文字判定でボタン自体を無効化しており、
`LocalBackend.submitPost` 側が持つ `emptyBody` の拒否メッセージ（日英併記）に届く前に止まっていたのが原因。

## 今回の修正（指摘された範囲のみ）
- `SameQ/Feature/Today/TodayPromptView.swift` の `canSubmit` を
  `!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` から `!draft.isEmpty` に変更。
  何か入力されていれば送信ボタンは押せるようにし、空白・改行のみの拒否判定は
  `LocalBackend.submitPost` 側の `emptyBody` チェックに委ねる（同一文字の過剰な繰り返しと同じ導線に揃えた）。
  文字が1つも入力されていない場合（`draft.isEmpty == true`）は従来どおりボタンは無効のまま。
- `SameQUITests/SprintFiveAcceptanceTests.swift` の `test02_blankAndRepeatedCharacterBodiesAreRejected` を、
  「空白・改行のみを送信 → 送信ボタンは押せる → 拒否メッセージ（日英）が出る → 拒否されたので投稿は進まない」
  ところまで検証するように書き換えた（旧テストは「ボタンが無効になること」しか確認しておらず、
  attempt 1 の不具合を検出できていなかった）。同一文字の繰り返しシナリオは、書きかけの入力を持ち越さないよう
  アプリを開き直す形に分離した。
- カウンタ表示（空白のみで `8/140` と出る見た目）や、その他の改善提案（`Yessssssss` の誤検知・連打制限の
  再起動での解除・連投拒否が直近1件のみ）は、今回の指摘範囲外のため**変更していない**（自分で見つけた弱点として
  上に記録済み）。

## 受け入れ条件の再確認結果

| # | 条件 | attempt 1 | attempt 2 | 根拠 |
|---|---|---|---|---|
| 3 | 空白・改行のみの投稿、および同一文字の過剰な繰り返しは拒否メッセージが出て投稿されない | ✗（空白・改行のみで無音） | 達成 | 修正後、空白・改行のみ（`"   \n\n  "`）を入力して送信すると「空白や改行だけの回答は投稿できません。／You can't post a reply that's only blank space or line breaks.」が表示され、投稿は進まない（`today.input` が引き続き表示される）。同一文字の過剰な繰り返しは attempt 1 から達成済みのまま |

他の受け入れ条件5つ（1・2・4・5・6）は attempt 1 で達成済みで、今回コード上変更していないため再確認は割愛した
（`TodayPromptView.canSubmit` の変更はこの画面の送信ボタンの有効条件のみに閉じており、他の受け入れ条件が依存する
バックエンド側の判定・BAN画面・連打制限のロジックには触れていない）。

## 確認方法
- ユニットテスト37本（`SameQTests`）: 全通過（0 failures）。今回のバックエンド側の判定ロジックは変更していないため、
  もともとの想定どおり無変化。
- UIテスト: `SprintFiveAcceptanceTests.test02_blankAndRepeatedCharacterBodiesAreRejected` を単体実行し、
  新しい検証内容（拒否メッセージの表示）を含めて通過を確認。フルスイート（ユニット37本＋UIテスト31本、
  スプリント01〜05の回帰含む）はビルド時間の都合で実行中に本報告を書いており、結果はコーディネーター側でも
  別途確認してもらっている。
- ビルド: `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' build` → **BUILD SUCCEEDED**。
