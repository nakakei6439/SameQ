# スプリント 08: ランダム通知 (F24, F25)

## 受け入れ条件（spec.md 228〜234行）
- [ ] 初回設定で通知を許可すると、8:00〜22:00 の範囲のランダムな時刻に通知が予約される
- [ ] 予約された時刻は日によって異なる（複数日分の予約を確認すると同じ時刻が並ばない）
- [ ] 8:00 より前、22:00 より後の時刻には通知が予約されない
- [ ] 通知をタップするとアプリが起動し、未回答なら今日のお題画面、回答済みならタイムラインが直接開く
- [ ] 通知時刻を過ぎても、お題の有効期間中ならいつでも回答でき、遅刻表示・カウントダウン・締切による参加不可が一切存在しない
- [ ] 通知を拒否した場合もアプリは通常どおり利用でき、設定画面から通知を有効にする案内が表示される

## 実装方針

### 1. `NotificationScheduler.swift`（新規・Backend 配下）
ローカル通知の予約・取り消し・状態取得を抽象化する薄い層。プロトコル
`NotificationScheduling` を切り、ユニットテストでは偽実装に差し替えられるようにする。
実機検証は `UNUserNotificationCenter` 経由。

- 1日1回の `UNCalendarNotificationTrigger`（non-repeating）で「次の1回」を予約する。
  予約のたびにランダムな時刻を `NotificationTimePicker`（純粋関数）で選ぶので、
  「日によって違う時刻」になる。発火後、または前面復帰時に次の1回を予約し直す。
- 時刻は端末のローカルタイムで 8:00〜22:00 の範囲。現在時刻が範囲外なら翌日、
  範囲内ならその日中の、まだ来ていない時刻から選ぶ。`dateComponents: DateComponents`
  を `UNCalendarNotificationTrigger(dateMatching:repeats:)` に渡す。
- 通知本文は「新しいお題が届きました」（端末言語を区別しない・固定文字列）。

### 2. `NotificationPermission.swift`（既存・拡張）
`request()` に加えて `currentStatus()` を追加し、設定画面が現在の許可状態を
判定できるようにする。許可が得られなかったときにアプリが落ちないよう、
エラーを握りつぶして `false` を返す形はそのまま。

### 3. `AppSession` の拡張
- `init` で `NotificationScheduling?`（既定は `LiveNotificationScheduler()`）
  を受け取り、`AppSession` 内に保持。テストからは偽実装を渡せる。
- `start()` 完了後、`promptState` に応じて「次の1回」の通知を予約し直す。
- `applyPromptState` の中でも通知の予約を更新する（有効なお題が切り替わるたびに
  「次のお題開始まで」に合わせて予約し直す）。
- `pendingDeepLinkTarget: DeepLinkTarget?` を追加し、`handleDeepLink(_:)` で
  タップ時の遷移先（today / timeline / waiting）を指示する。
- 通知の許可状態が「拒否」のときは予約せず、設定画面から案内を出すだけに留める。

### 4. `RootView` の拡張
- `SameQApp` 側で `UNUserNotificationCenterDelegate` を設定し、フォアグラウンド／バックグラウンド
  どちらからのタップでも `AppSession.handleDeepLink(_:)` へ通知する。
- `RootView.body` で `pendingDeepLinkTarget` の変化に応じて、
  `session.screen == .today && myPost != nil` のときはタイムラインを自動で開く
  （F25「回答済みならタイムラインが直接開く」）。

### 5. `SettingsView` の拡張
- 上部に「通知」セクションを追加。現状の許可状態を表示し、拒否されている場合は
  「このアプリの通知はオフです。設定アプリからオンにできます」という案内を出す。
  アプリ内から直接許可を再要求する導線は作らない（iOS の仕様上、一旦拒否した
  後は設定アプリでしか戻せないため）。

### 6. `LaunchOptions` の拡張（Debug 限定）
検証用の追加フラグ：
- `-SameQNotificationHour <0〜23>`: `NotificationTimePicker` へ渡す「強制時」。
- `-SameQNotificationForceDenied`: 許可状態を常に `.denied` として扱う（拒否経路の検証用）。
- `-SameQNotificationForceHourOnly`: 強制時のみを使い分のランダム化を止める
  （境界値確認用）。

### 7. `PersistedState` のスキーマ変更
- `notificationAuthorizationAsked: Bool` を追加（schemaVersion 5→6）。
  一度許可状態を聞いたかを覚え、未回答のままアプリが落ちても次回起動時に
  再要求ダイアログを出さない。ただし `UNAuthorizationStatus` を毎回確認するので
  永続化は補助目的のみで、メインの判定は OS のステータスを使う。

## 影響範囲
- `AppSession.start()` のあとに「通知の予約」が入る。既存ユニットテストは
  `NotificationScheduling` を偽実装（`nil` 予約）に差し替えるか、または
  `AppSession(backend:clock:translator:notificationScheduler:)` の新引数で
  完全にバイパスできる形にする。`scheduler == nil` のときは何もしない。
- `RootView` に `UNUserNotificationCenterDelegate` の橋渡し（`NSObject` の
  薄いホルダークラス）を追加する。スプリント06 の `TranslationHostView` と
  同様の「画面を横断する常駐コンポーネント」だが、これは UI を持たない
  （`UIViewControllerRepresentable` ではない）。`@MainActor` の `AppSession`
  にタップを届ける。
- `SettingsView` に新しいセクションを足すだけ。既存テストへの影響は最小限。
- `PersistedState` のキーが増えるため、`schemaVersion` を 5→6 へ上げる。
  既存ファイルは `decodeIfPresent` で欠落を吸収できる形に揃える。

## テスト戦略
- **ユニット**: `NotificationTimePicker` の純粋関数性を網羅（境界 7:59/8:00/21:59/22:00、
  既に過ぎている時刻の除外、翌日への繰り越し、強制フラグ）。`FakeNotificationScheduler`
  で `AppSession.start()` が予約を呼ぶこと、`applyPromptState` がプロンプト切替で
  予約を更新すること、`handleDeepLink(.today)` / `.timeline` がそれぞれ正しい
  画面に遷移することを検証。
- **UI**: `SprintEightAcceptanceTests` で「通知予約時刻が範囲内」「許可拒否でも
  アプリは普通に使えて設定画面に案内が出る」「タップで該当画面が開く」を検証。
  実際の通知発火は実時間待ちになるので、`UNUserNotificationCenter` の `pendingNotificationRequests`
  を直接読んで確認する形にする。
