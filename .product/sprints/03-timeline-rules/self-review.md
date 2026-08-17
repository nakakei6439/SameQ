# スプリント 03 自己評価（attempt 1）

対象: F11（タイムライン取得ルール）/ F12（既読管理）
受け入れ条件: `.product/spec.md` 143〜149行

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 表示されるのは今日のお題への回答だけで、別のお題への回答は1件も出ない | 達成 | `LocalBackend.candidates(promptID:at:)` が「同一お題／自分以外／表示期限内」で絞る。UIテスト `SprintThreeAcceptanceTests.test07`（1つ目のお題で読んだ本文が、2つ目のお題のタイムラインに出ないことを確認）とユニットテスト `testOtherPromptAnswersNeverAppear` |
| 20件の回答があるとき、20回スワイプする間に同じ回答が2回出ない | 達成 | UIテスト `test01_twentySwipesWithoutRepeat`（`-SameQAnswerCount 20` で20回タップし、本文の重複が無いことを確認、20件すべて別物）。ユニットテスト `testUnreadFirstNeverRepeatsWithinOnePrompt` |
| 未読を全て読み切った後もスワイプ操作が壊れず、明示された状態表示になる | 達成 | 読み切ると「今は新しい回答がありません／このお題の回答はすべて読みました。」を表示（`timeline.exhausted`）。空振りスワイプ3回のあとも表示が残り、閉じるボタンが押せることを `test01` の末尾で確認。シミュレータでの実画面も確認済み |
| 同じ条件でタイムラインを2回開くと、1件目に出る回答が毎回同一とは限らない | 達成 | 引くたびに未読集合から `randomElement()`。UIテスト `test05_firstAnswerIsNotAlwaysTheSame`（状態をリセットして開き直し、1件目が2種類以上になるまで確認）。ユニットテスト `testFirstDrawIsNotAlwaysTheSamePost`（30回試行） |
| 回答が自分の1件しか無い場合、空状態の説明文が表示され、自分の投稿が他人の回答として出ることはない | 達成 | `-SameQAnswerCount 0` で「まだ誰も答えていません／世界の誰かが答えると、ここに1件ずつ出てきます。」（`timeline.empty`）。UIテスト `test03_emptyStateWhenOnlyMyOwnAnswerExists`、ユニットテスト `testOnlyMyOwnAnswerYieldsEmpty` |
| スワイプは次へ進むのみで、前の回答へ戻る操作は提供されない | 達成 | `AppSession` は回答を1件しか保持せず、過去の回答を持たない（戻る実装が原理的に作れない）。UIテスト `test06_noBackAffordanceInTimeline`（「戻る/前へ/Back/Previous/Undo」を含むボタンが無いこと、右スワイプでも前の回答に戻らないこと） |
| （評価者注記）アプリを再起動しても既読が残る | 達成 | 既読は `state.json` の `viewedPostIDs` に即時保存。UIテスト `test02_viewedAnswersDoNotReturnAfterRelaunch`（9件見て強制終了 → 再起動後の11件が全部新しい → 20件で読み切り）。ユニットテスト `testViewedRecordsSurviveRelaunch` |
| （評価者注記）0件・1件・大量（100件以上）の3ケース | 達成 | `-SameQAnswerCount 0 / 1 / 120` で再現できる。0件=`test03`、1件=`test04_singleAnswerThenExhausted`、120件=シミュレータで目視確認（Debug オーバーレイに `answers 120 · viewed 1`） |

自動テストは **ユニット16本 ＋ UIテスト17本**（スプリント01の5本・02の5本・03の7本）。
スプリント01・02の受け入れ条件をなぞる UI テストも全て通っている。

## 動かし方（evaluator 向け）

```bash
open SameQ.xcodeproj      # 外部パッケージ依存なし
# または
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

初回設定 → 今日のお題に回答 → 世界タイムラインが開く、が基本の動線。
ログイン情報は無い（匿名アカウント）。

### 検証用の起動引数（すべて Debug ビルド限定 / Release では無効）

スプリント02から引き継いだもの:

| 引数 | 意味 |
|---|---|
| `-SameQResetState` | 保存を全部捨てて初回設定からやり直す |
| `-SameQScenario live\|expiring\|expired\|upcoming` | お題の日程シナリオ |
| `-SameQExpirySeconds <秒>` / `-SameQGapSeconds <秒>` | `expiring` の秒数 |
| `-SameQTimeOffsetMinutes <分>` | アプリが認識する「今」をずらす |
| `-SameQDebugOverlay` | 画面下端の状態表示 |

今回追加したもの:

| 引数 | 意味 |
|---|---|
| `-SameQAnswerCount <件数>` | 各お題の「自分以外の回答」を指定件数ちょうどにする。`0` / `1` / `120` で3ケースを再現できる |
| `-SameQResetViewed` | **既読の記録だけ**を消す。アカウント・自分の回答・いいねは残るので、同じ回答をもう一度出せる |

`-SameQDebugOverlay` の表示は
`now HH:mm:ss · scenario live · prompt_001 ends in Ns · answered · answers 120 · viewed 7 · liked 1`
の形式。`answers` が候補の総数、`viewed` が既読、`liked` がいいねの件数。
アクセシビリティ識別子は `debug.status`。**今回オーバーレイの位置を `overlay` から
`safeAreaInset` に変えた**（スプリント02の評価で「画面最下部のテキストに重なる」と指摘があり、
今回そのオーバーレイが検証の主要な手段になるため）。

### 3ケースの再現手順

```bash
# 0件（自分の回答しか無い）→ 空状態
xcrun simctl launch <UDID> com.nakakei6439.SameQ -SameQResetState -SameQAnswerCount 0 -SameQDebugOverlay
# 1件
xcrun simctl launch <UDID> com.nakakei6439.SameQ -SameQResetState -SameQAnswerCount 1 -SameQDebugOverlay
# 120件（大量）
xcrun simctl launch <UDID> com.nakakei6439.SameQ -SameQResetState -SameQAnswerCount 120 -SameQDebugOverlay
# 既読の永続を見る: 上のあと引数から -SameQResetState を外して起動し直す
xcrun simctl launch <UDID> com.nakakei6439.SameQ -SameQAnswerCount 120 -SameQDebugOverlay
```

引数なしでも `prompt_001` に22件の回答が同梱されているので、
「20回スワイプして重複しない」はそのままでも確認できる。
`-SameQAnswerCount` で機械生成される回答は本文末尾に `（#1-76）` のような通し番号が入るので、
重複の有無を目で追える（`#1-` は1つ目のお題、`#2-` は2つ目のお題）。

### 主な画面の識別子

| 識別子 | 意味 |
|---|---|
| `timeline.card.body` / `timeline.card.emoji` / `timeline.card.nickname` | 表示中の回答 |
| `timeline.next` / `timeline.like` / `timeline.close` | 次へ／いいね／閉じる |
| `timeline.end` | 読み切り・空状態の入れ物（どちらも同じ） |
| `timeline.exhausted` | 「今は新しい回答がありません」 |
| `timeline.empty` | 「まだ誰も答えていません」 |
| `timeline.loading` | 引いている最中（端末内処理なので通常は一瞬） |

## 実装したこと（要点）

- `Backend.nextTimelinePost(promptID:)` を追加。返り値は `TimelineDraw`（`.post` / `.empty` / `.exhausted`）。
  `LocalBackend` は候補（同一お題・自分以外・期限内）のうち**未読だけ**から `randomElement()` で1件選び、
  返す時点で `viewedPostIDs` に追記して `state.json` へ保存する。
- `PersistedState` に `viewedPostIDs` を追加（schemaVersion 2）。旧ファイルは欠損キーを空として読むので、
  既存アカウントは消えない。
- `AppSession` はタイムラインの回答を配列で持たなくなった（`timelineContent` に1件だけ）。
  そのため「前へ戻る」は実装しようがない。
- `TimelineView` は `timelineContent` を描画するだけ。空状態と読み切り状態を別の文言で出す。
- `pruneExpired` が既読も掃除する（期限切れと確認できた投稿だけ）。
- 同梱シードの `prompt_001` を14件→22件に増やし、`supabase/seed.sql` も同じ内容に合わせた。

## 自分で見つけた弱点

1. **スプリント01の受け入れ条件8（いいねの押下状態が開き直しても残る）の検証手順を変えた。**
   F12 を入れると、一度出した回答は既読になり二度と出てこないので、
   「開き直して同じ回答を探して押下状態を見る」という元の手順が成立しない。
   いいねの永続そのもの（`likedPostIDs` が `state.json` に残り、既読とは独立して復元される）は維持していて、
   - UIテスト `SprintOneAcceptanceTests.test03` は `-SameQResetViewed` を挟んで同じ回答を出し直す手順に変更
   - ユニットテスト `testLikesSurviveRelaunchIndependentlyOfViewedRecords` でも二重に確認
   としている。**この仕様の解釈（既読の回答は再表示しない）が誤りなら、ここが影響範囲。**
2. **「既読にする」タイミングは「画面に出した瞬間」にした。** 送った先の1件は、
   ユーザーが読む前にアプリを終了しても既読になる。
   「読み終えたら既読」にすると、閉じて開き直したときに同じ回答が再び出るため、
   受け入れ条件4（1件目が毎回同一とは限らない）と噛み合わないと判断した。
3. **既読の掃除は「期限切れと確認できた投稿」に限っている。**
   `-SameQAnswerCount` を付けたり外したりして回答の顔ぶれが変わると、
   もう存在しない投稿の既読 ID が保存に残り続ける（実害は無いが件数は増える）。
   Supabase 接続時はサーバー側の `viewed_posts` に移すので、そこで解消する想定。
4. **`LocalBackend`（単一端末）なので、「他人から見て自分の投稿が出ない」ことは自分の端末からしか確認できない。**
   自分の投稿が候補から外れることはユニットテストで確認済み。
5. スプリント01・02の評価で挙がった改善提案のうち、Debug オーバーレイの重なり（[C]）だけ今回直した。
   残り（キーボードが「投稿する」を隠す／投稿ボタンが押せない理由が出ない／`state.json` 破損時に
   アカウントが黙って消える／期限切れの瞬間にタイムラインが無言で閉じる／入力中に期限切れで書きかけが消える）は
   **今回も未対応**。合否には影響しない範囲と判断した。

## 提案（今回はやらなかったこと）

- 読み切り状態から「もう一度最初から読む」導線。仕様が「読み切ったら明示状態」としか言っていないので作らなかったが、
  実運用では回答が増えたときに引き直したくなる（＝プル更新の導線）はず。
- 既読の記録をサーバー（`viewed_posts`）へ移す。端末を替えると既読が引き継がれない。B01 の続き。
- スプリント04（通報・ブロック）で `candidates()` に「ブロック外」「通報済み以外」の条件を足す。
  今回そのための切れ目（`candidates(promptID:at:)`）だけ作ってある。
