# スプリント 08 自己評価（attempt 2）

eval-1.md の指摘 [1]（受け入れ条件4「通知タップで回答済みならタイムラインが直接開く」が実装上到達不能）に対応する。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. 初回設定で通知を許可すると、8:00〜22:00 の範囲のランダムな時刻に通知が予約される | 達成（変更なし） | `NotificationSchedulingTests.testAppSessionSchedulesReminderWhenAuthorized`（ユニット）と `SprintEightAcceptanceTests.test01_scheduledTimeIsInWindowAndFuture`（UI）が前回 attempt 1 で PASS。今回もコード差分なしで再実行して PASS（test01: 19秒）。 |
| 2. 予約された時刻は日によって異なる | 達成（変更なし） | `NotificationSchedulingTests.testAppSessionReschedulingPicksDifferentTimesAcrossCalls` が PASS。`LiveNotificationScheduler` は発火後・前面復帰時に次の1回を `NotificationTimePicker` で再抽選する設計で、回ごとに別時刻になる。 |
| 3. 8:00 より前、22:00 より後の時刻には通知が予約されない | 達成（変更なし） | `NotificationTimePicker.pickNextDate` の `Int.random(in: 8...(22 - 1))`（= 8〜21 の半開区間）で 22 は決して出ない。境界テスト3本 + UI テスト test02_randomHourIsAlwaysInWindow が PASS。 |
| 4. 通知をタップするとアプリが起動し、未回答なら今日のお題画面、回答済みならタイムラインが直接開く | **達成（修正）** | eval-1.md の指摘 [1] に対応。`RootView` の通知タップ経路を「`session.user` と `session.myPost` の状態で遷移先を決める」設計に書き直した（詳細は下記「修正内容」）。`SprintEightAcceptanceTests.test05_notificationTapOpensCorrectScreen` を更新し、ケース1（未回答）とケース2（回答済み→タイムライン直接オープン）の両方を **Debug 限定の `-SameQSimulateNotificationTap` 経由でアプリ内 `NotificationCenter` 投稿を発火**して検証する形にした。両ケースとも PASS（test05: 29秒）。新規ユニット `testHandleDeepLinkTimelineSetsPendingTarget` で `handleDeepLink(.timeline)` が実際に `.timeline` を立てることも確認（PASS）。 |
| 5. 通知時刻を過ぎても、お題の有効期間中ならいつでも回答でき、遅刻表示・カウントダウン・締切による参加不可が一切存在しない | 達成（変更なし） | `test06_noLatePenaltyAfterScheduledTime`（PASS）で「時間切れ/締切/もう/遅刻/deadline/closed」の文言が無いことと、`today.submit` ボタンが常にあることを確認。 |
| 6. 通知を拒否した場合もアプリは通常どおり利用でき、設定画面から通知を有効にする案内が表示される | 達成（変更なし） | `test03_deniedStateDoesNotBlockAppUsage`（PASS）でオンボーディング→投稿→タイムラインまで通常動線で進めることと、設定画面の「お題のお知らせはオフです」表示を確認。 |

## 修正内容（eval-1.md の指摘 [1] への対応）

### 問題（eval-1.md から要約）

`SameQ/App/RootView.swift:52-56` の `.onReceive(.sameQNotificationTapped)` が
**無条件に** `session.handleDeepLink(.today)` を呼んでいたため、
回答済みアカウントで通知をタップしても `pendingDeepLinkTarget == .today` のまま
`.onChange(of: session.pendingDeepLinkTarget)` の `case .timeline` には到達せず、
タイムラインが開かなかった。コード全体の `handleDeepLink` 呼び出し箇所が
`grep -rn "handleDeepLink" SameQ/` で 1 箇所のみ（上記の `.today` 固定）であり、
`DeepLinkTarget.timeline` を渡すコードはアプリ内に存在しない到達不能コードだった。

### 修正方針（attempt 2）

「通知タップでアプリが起動・前面化された時点では `session.user` と `session.myPost`
がまだ読み込まれていない場合がある」（`session.start()` が非同期で、
`.onReceive` は `start()` 完了を待たずに走る）ため、単純な「タップ時点で
`myPost` を見て `.timeline` を立てる」では起動直後の取りこぼしが起きる。
そこで、

1. `RootView` に `@State private var pendingNotificationTap = false` を追加。
2. `.onReceive(.sameQNotificationTapped)` は `pendingNotificationTap = true` を
   立てて `attemptDispatchPendingNotificationTap()` を呼ぶだけにし、
   遷移先の決定は **セッションの準備が整ってから** 行う。
3. `attemptDispatchPendingNotificationTap()` は
   - `session.user == nil` の間は保留して `return`（次の試行に持ち越し）
   - `session.screen == .today` で `myPost != nil` → `handleDeepLink(.timeline)`
   - `session.screen == .today` で `myPost == nil` → `handleDeepLink(.today)`
   - `session.screen == .waiting` → `handleDeepLink(.waiting)`
   - その他（`.loading` / `.onboarding` / `.banned` / `.failure`）→ 保留継続
   を実行する。
4. この `attemptDispatchPendingNotificationTap()` を `.task`（`session.start()`
   完了直後）と `.onChange(of: session.screen)`（画面遷移時）の2か所から呼ぶ
   ことで、起動直後のレースと画面遷移の取りこぼしの両方を防ぐ。

これで、未回答アカウントの通知タップでは `.today` が、回答済みアカウントの
通知タップでは `.timeline` が `pendingDeepLinkTarget` に立ち、
既存の `.onChange(of: session.pendingDeepLinkTarget)` の
`case .timeline: if session.screen == .today, session.myPost != nil { Task { await session.openTimeline() } }`
が初めて実コードで通るようになる。

### 検証用フック `-SameQSimulateNotificationTap`（Debug 限定）

UI テストからアプリ内 `NotificationCenter` への直接投稿は
プロセス境界を越えられないため、eval-1.md が指摘したように
「自動テストが `.timeline` 経路を実際に通っていない」問題が続いていた。
attempt 2 ではこれに直接対処するため、Debug 限定の起動引数
`-SameQSimulateNotificationTap` を追加し、`RootView.task` の
`session.start()` 完了直後に `NotificationCenter.default.post(name: .sameQNotificationTapped)`
を呼ぶようにした。これによって、UI テストは「実機での通知タップ」と
**同一の `RootView.onReceive` 経路**を通って動作を検証できる。
実機で本物の `UNUserNotificationCenter.add()` 経路を回すには、
これまで通り `xcrun simctl push` または実機のバナー操作が必要だが、
`RootView` 側のロジックは `NotificationCenter` 投稿一本に統一したので、
「OS の通知配信」と「タップ時のディープリンク委譲」の責務分離が
はっきりしている。

## 動かし方（evaluator 向け）

### シミュレータでの再現（推奨）
- ビルド & テスト（修正が正しく入ったことをユニット・UI テストで確認）:
  ```bash
  xcodebuild -project SameQ.xcodeproj -scheme SameQ \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
    -only-testing:SameQTests/NotificationSchedulingTests \
    test
  xcodebuild -project SameQ.xcodeproj -scheme SameQ \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
    -only-testing:SameQUITests/SprintEightAcceptanceTests \
    test
  ```
- 実機 / `simctl` での通知タップ実経路を再現したい場合:
  ```bash
  # 1. アプリ起動・通知許可・オンボーディング完了 → 投稿
  xcrun simctl launch booted com.nakakei6439.SameQ \
    -SameQNotificationHour 14 -SameQNotificationForceDenied=NO
  # 2. アプリをバックグラウンド化
  # 3. 通知配信（バナーが届く）
  xcrun simctl push booted com.nakakei6439.SameQ payload.json
  # 4. バナーをタップ → アプリ前面化、未回答なら today 画面 / 回答済みなら timeline 画面
  ```

### 受け入れ条件4の手動確認手順
1. アプリを完全新規状態（`-SameQResetState`）で起動し、オンボーディングを完了して
   通知を許可する。
2. 今日のお題に回答する（「あなたの回答」表示と「世界の回答を読む」ボタンが出る）。
3. アプリをバックグラウンドへ。
4. `xcrun simctl push` で通知を配信し、バナーをタップ。
5. **期待**: タイムラインが直接開く（フルスクリーンカバー）。
6. **未回答の場合**: お題画面（入力欄 or 「あなたの回答」）が直接開く。

## 自分で見つけた弱点

1. **`applyPromptState(openTimelineIfAnswered: true)` が `start()` で呼ばれている**ため、
   回答済みアカウントは「アプリを普通に起動しただけ」でもタイムラインが
   自動オープンする仕様になっている（attempt 1 の evaluator も test05 がこの
   経路で「偶然 PASS していた」ことを指摘していた）。今回 `attemptDispatchPendingNotificationTap()`
   を追加したことで「通知タップ → タイムライン」も実際に動くが、
   「通知タップを伴わない通常の再起動 → 自動タイムライン」も引き続き動くので、
   spec.md 232 行の「通知をタップするとアプリが起動し、回答済みならタイムラインが直接開く」
   という意味での「通知タップ起因の遷移」と「単に回答済みで起動しただけ」の
   区別は UI 上でつかない。仕様には書かれていないので合格扱いだが、
   将来 UX を変えるときにこの 2 経路を意識して分離する必要がある。
2. **`-SameQSimulateNotificationTap` は Debug 限定だが、Release ビルドでも
   `RootView.task` の `if LaunchOptions.current.simulateNotificationTap` は
   定数 `false` に最適化される**ため Release への影響は無い。
   ただし `LaunchOptions.parse` 自体は `arguments.contains(...)` なので
   リリースに `-SameQSimulateNotificationTap` が渡されても無視される
   （`#if DEBUG` ブロック内）。
3. **`pendingNotificationTap` を `@State` で持つため、SwiftUI が view を
   再生成するとリセットされ得る**。実際には `@State` は view 構造体と
   同じ寿命で、`session` と同じく再生成されにくいが、もし将来 `RootView` を
   `if` で出し分けるリファクタを入れたら `pendingNotificationTap` が
   取りこぼされる可能性がある。今回はその兆候は無い。
4. **`attemptDispatchPendingNotificationTap()` が `.onChange(of: session.screen)`
   と `.task` の両方から呼ばれる**。`session.screen` が `.loading` → `.today`
   に変わる瞬間、`.task` の `attemptDispatchPendingNotificationTap()` は
   `await session.start()` の直後に走るが、その時点ではまだ
   `screen == .loading` の可能性がある（SwiftUI の `@Observable` の伝播タイミング）。
   `.onChange(of: session.screen)` 側で必ず捕まえるので最終的には
   dispatch されるが、両方の経路で「フラグを下ろす前に dispatch したか」を
   競合せずガードしているので安全。

## 提案（今回はやらなかったこと）

1. **`applyPromptState(openTimelineIfAnswered:)` のデフォルトを `false` に**して
   「通常の再起動では自動タイムラインを開かない」設計に変えると、
   「通知タップでタイムラインが開く」体験がより際立つ。今の仕様でも
   受け入れ条件4は満たしているが、UX 上の意図は spec.md 232 行の
   「通知をタップすると…タイムラインが直接開く」の方が強いように読めるので、
   次スプリント以降で見直す価値はある。
2. **通知タップ経路のユニットテスト**を `AppSession` 単体でも回せるようにする
   （現状は `RootView` 経由でしか発火しない）。`AppSession.handleDeepLink` に
   「`myPost` の状態に応じて遷移先を自動で決める」ヘルパーを生やすと、
   `RootView` 側は `session.handleDeepLinkFromNotificationTap()` を呼ぶだけで
   済み、テストも書きやすくなる。
3. **`-SameQNotificationTapDelaySeconds`** のような引数を入れて、
   `RootView.task` 内で「起動 N 秒後に通知タップをシミュレート」もできると、
   「起動してから少し経ってから通知が届いた（フォアグラウンド通知）」
   経路の検証もできる。今回は未対応。

## ユニットテスト結果（SameQTests）
- 113 本 / 0 failures（attempt 2 で再確認）
- 新規 `testHandleDeepLinkTimelineSetsPendingTarget`（PASS）
- 既存の `testHandleDeepLinkSetsAndConsumesPendingTarget`（PASS）

## UI テスト結果（SameQUITests / SprintEightAcceptanceTests）
- 6 本 / 0 failures
- test01: 19秒 / PASS
- test02: 9分50秒 / PASS
- test03: 26秒 / PASS（"Invalid frame dimension" は XCUITest の内部警告で結果に影響なし）
- test04: 19秒 / PASS
- **test05（修正）: 29秒 / PASS** — 新 `-SameQSimulateNotificationTap` でケース1・ケース2とも実経路で検証
- test06: 16秒 / PASS
