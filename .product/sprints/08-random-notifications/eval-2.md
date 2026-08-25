# スプリント 08 評価（attempt 2） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/6 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / アプリ由来の未処理エラー0 | 0 | ✓ |
| 3 データ整合性 | 問題なし | 100% | ✓ |
| 4 回帰 | 18/18（3スプリント抜き取り）＋ ユニット113/113 | 100% | ✓ |
| 5 使用性 | 4 | 3以上 | ✓ |

## 検証環境
- 新規作成した2台のiPhone 17シミュレータ（iOS 26.5）: `Eval08`（自動テスト専用, UDID `98CE5B0F-...`）と `Eval08-Manual`（手動の実通知タップ検証専用, UDID `9F934266-...`）。既存の他シミュレータには触れていない。評価終了後に両方とも削除済み。
- ビルド: `xcodebuild -project SameQ.xcodeproj -scheme SameQ` BUILD SUCCEEDED。
- 検証時刻: 2026-08-25 10:37〜11:06 JST
- 実施した自動テスト（自分で実行、他プロセス非併走）:
  - `SameQUITests/SprintEightAcceptanceTests`（test01〜06）: 6/6 成功
  - `SameQTests/NotificationSchedulingTests`: 10/10 成功
  - `SameQUITests/SprintOneAcceptanceTests` + `SprintThreeAcceptanceTests` + `SprintSevenAcceptanceTests`（回帰）: 18/18 成功
  - `SameQTests`（ユニット全件）: 113/113 成功
- 実施した手動検証（`Eval08-Manual` で、`cliclick` によるウィンドウ内座標クリック＋`xcrun simctl push` による本物のプッシュ通知配信＋通知バナーへの実タップ）:
  - オンボーディング完了→通知許可→投稿→タイムライン閉じる→Simulatorのツールバーの Home アイコンでバックグラウンド化（プロセス終了せず）→`xcrun simctl push` で通知配信→バナーをタップ（実座標）→**タイムラインが直接開いた**ことをスクリーンショットで確認
  - 新規アカウントを作り直し、同じ手順で未回答のまま通知をバックグラウンドタップ→**今日のお題画面（入力欄あり）が直接開いた**ことをスクリーンショットで確認

## 受け入れ条件ごとの結果
1. 初回設定で通知を許可すると8:00〜22:00の範囲のランダムな時刻に通知が予約される → ✓（test01/test04を自分で再実行し確認。設定画面の「次のお知らせ」表示）
2. 予約された時刻は日によって異なる → ✓（`NotificationSchedulingTests.testAppSessionReschedulingPicksDifferentTimesAcrossCalls`を自分で再実行し確認）
3. 8:00より前、22:00より後の時刻には通知が予約されない → ✓（test02、および境界値ユニットテスト3本を自分で再実行し確認）
4. 通知をタップするとアプリが起動し、未回答なら今日のお題画面、回答済みならタイムラインが直接開く → **✓ 解消を確認**（詳細は下記）
5. 通知時刻を過ぎても、お題の有効期間中ならいつでも回答でき、遅刻表示・カウントダウン・締切による参加不可が一切存在しない → ✓（test06を自分で再実行し確認）
6. 通知を拒否した場合もアプリは通常どおり利用でき、設定画面から通知を有効にする案内が表示される → ✓（test03を自分で再実行し確認。`SettingsView.swift`のコードも確認し、拒否状態では「通知をオンにすると…iOSの『設定 › 通知 › SameQ』からオンにできます」という案内文が出る実装であることを確認）

## 条件4の解消の根拠（attempt 1で不合格だった箇所）

attempt 1（eval-1.md）の不合格理由は「通知タップの実経路（`UNUserNotificationCenterDelegate` → `NotificationCenter.post` → `RootView.onReceive`）が常に `.today` を固定で呼んでおり、`.timeline` ケースが到達不能なコードだった」というものだった。

今回、**generatorの自己申告テスト（`-SameQSimulateNotificationTap`によるアプリ内シミュレート）だけでなく、それとは独立に、本物のOS通知配信・実タップで直接検証した**。理由は、自己申告テストのケース2（回答済みアカウント）が `app.terminate()` → 新規 `launch()` という「コールドスタート」を経由しており、`AppSession.start()` 自体が「回答済みなら自動でタイムラインを開く」という既存動作（`applyPromptState(openTimelineIfAnswered: true)`、self-review.mdの「自分で見つけた弱点1」に記載あり）を持つため、**通知タップの修正が無くても偶然パスしうる**構造になっていたため。

そこで、eval-1.mdの実際の再現手順（「アプリをバックグラウンドへ。プロセスは終了しない」）に忠実に、
1. オンボーディング完了→通知許可→投稿（回答済みにする）
2. Simulatorのツールバー内Homeアイコンでバックグラウンド化（`app.terminate()`は使わない。プロセスは生きたまま）
3. `xcrun simctl push <UDID> com.nakakei6439.SameQ payload.json` で本物の通知を配信
4. 表示された通知バナーをウィンドウ内座標で実際にタップ

を行い、**タイムラインが直接開くことをスクリーンショットで確認した**（`/tmp/eval08_after_tap_banner2.png` 相当、下記「証跡」参照）。この経路では `.task`（`session.start()`を含む）は再実行されないため、`applyPromptState(openTimelineIfAnswered: true)`の影響を受けず、`RootView.onReceive` → `attemptDispatchPendingNotificationTap()` という修正コードだけが実際に働いた結果であると判断できる。

同じ手順を未回答アカウントでも実施し、今日のお題画面（入力欄あり）が直接開くことも確認した。

## 安定性・データ整合性
- 手動検証中の `log show`（`messageType == 16 OR 17` でfault/error抽出）で、SameQ由来の異常は見つからなかった。出現したエラーは全て既知のシミュレータ環境ノイズ（`CoreHaptics`のhapticpatternlibrary.plist不在、`libCoreFSCache`のfopen失敗、`Invalid frame dimension`というSwiftUIのキーボード関連の内部警告）で、過去のスプリントの評価でも同様に無害と判断されているもの。
- `state.json`を直接確認（`schemaVersion: 5`、リセット後のアカウントで`myPosts`が空、`lastPrepareAttemptAt`等のフィールドも正しい形）。壊れたJSONや不整合は無し。

## 回帰
- `SprintOneAcceptanceTests` + `SprintThreeAcceptanceTests` + `SprintSevenAcceptanceTests` を自分で実行し18/18成功（eval-1.mdの回帰確認と同じ3スプリントを抜き取り）。
- ユニットテスト全件（113本）も0 failures。

## 使用性（4/5）
主要動線（オンボーディング→お題→投稿→通知タップでの遷移）は迷わず完走できる。attempt 1で評価者が指摘していた「通知タップ後にもう一手動タップが必要になる場面がある」という摩擦は、条件4の修正によって解消された（実タップで直接目的の画面が開く）。空状態（「世界の回答はまだ見られません」＋鍵アイコン）も意図を持って設計されている。4点に留めた理由は、通知タップ経路の一部（`.loading`/`.onboarding`/`.banned`/`.failure`中にタップが来た場合の保留挙動）はコードレビューでのみ確認しており、実機・実タップでは網羅していないため。

## 改善提案（合否には影響しない）
1. self-review.md「自分で見つけた弱点1」が指摘するとおり、回答済みアカウントは通知タップに関係なく通常再起動でも自動でタイムラインが開く。仕様上は問題ないが、「通知タップ起因の遷移」と「単なる再起動」の体験上の区別が無い。UXを重視するなら次回以降で意図的に分離を検討してもよい。
2. `RootView`の通知タップ経路の自動テストが、実際のOS通知配信・実タップではなく`-SameQSimulateNotificationTap`（コールドスタート限定）にしか対応していない。今回evaluatorが行った「バックグラウンド維持＋実タップ」のシナリオを、`XCUIApplication(bundleIdentifier: "com.apple.springboard")`経由でXCUITest化できると、次回以降のevaluatorが同じ手動作業を繰り返さずに済む。

## 評価できなかったもの
- 「端末のタイムゾーンを変更した場合に範囲外の時刻へずれないか」「日付をまたいだときに二重で通知されないか」（spec.md 236行の評価者への注記）は、実機での長時間・複数日の運用確認が必要なため今回も未検証（eval-1.mdから持ち越し）。
