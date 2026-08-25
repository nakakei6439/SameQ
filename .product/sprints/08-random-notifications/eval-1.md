# スプリント 08 評価（attempt 1） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 5/6（条件4が部分的に未達） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 | 0 | ✓ |
| 3 データ整合性 | 問題なし | 100% | ✓ |
| 4 回帰 | 18/18（3スプリント抜き取り） | 100% | ✓ |
| 5 使用性 | 3 | 3以上 | ✓ |

## 検証環境
- iPhone 17 Pro Max シミュレータ（UDID `E33C6F86-0484-4209-8609-9624DC34C710`, iOS 26.3）を新規boot
- `xcodebuild -project SameQ.xcodeproj -scheme SameQ` でビルド（BUILD SUCCEEDED）
- 検証時刻: 2026-08-25 09:29〜09:53 JST
- self-review.md に記載の `SprintEightAcceptanceTests`（test01〜test06）を自分で実行、`NotificationSchedulingTests` を自分で実行、回帰用に `SprintOneAcceptanceTests` / `SprintThreeAcceptanceTests` / `SprintSevenAcceptanceTests`（計18件）を自分で実行。加えて、通知タップの実経路を検証するため一時UIテスト（`TempEvalNotificationTapTest.swift`、確認後に削除・`git status`で復元確認済み）を作成し、`xcrun simctl push` で実際にプッシュ通知をシミュレータへ配信して通知バナーが表示されることを画面キャプチャで確認、その後の遷移を検証した。

## 受け入れ条件ごとの結果
1. 初回設定で通知を許可すると8:00〜22:00の範囲のランダムな時刻に通知が予約される → ✓（test01, test04で確認。設定画面の「次のお知らせ」表示を実際に読み取り）
2. 予約された時刻は日によって異なる → ✓（`NotificationSchedulingTests.testAppSessionReschedulingPicksDifferentTimesAcrossCalls`を自分で実行し確認。実装は`start()`・`refresh()`のたびに`scheduleDailyReminderIfPossible()`を呼び直しランダムな時を再抽選する設計）
3. 8:00より前、22:00より後の時刻には通知が予約されない → ✓（test02で30回連続起動しすべて8〜21時であることを確認）
4. 通知をタップするとアプリが起動し、未回答なら今日のお題画面、回答済みならタイムラインが直接開く → **✗ 部分的に未達**（詳細は下記「不合格の原因」）
5. 通知時刻を過ぎても、お題の有効期間中ならいつでも回答でき、遅刻表示・カウントダウン・締切による参加不可が一切存在しない → ✓（test06で「時間切れ」「締切」「もう」「遅刻」「deadline」「closed」の文言が無いことを確認）
6. 通知を拒否した場合もアプリは通常どおり利用でき、設定画面から通知を有効にする案内が表示される → ✓（test03で拒否状態からオンボーディング→投稿→タイムライン到達を確認）

## 不合格の原因（これを直せば通る）

### [1] 通知タップで回答済みアカウントがタイムラインへ直接開かない（実際の通知タップ経路が未接続）

- **再現手順**:
  1. オンボーディングを完了し、通知を許可する
  2. 今日のお題に投稿する（回答済み状態になる）
  3. アプリをバックグラウンドへ（ホームボタン相当）。プロセスは終了しない
  4. `xcrun simctl push <UDID> com.nakakei6439.SameQ payload.json` で通知を配信する（実機でも同様に、通知バナーが届く）
  5. 通知バナーをタップする
- **期待**: spec.md 232行「通知をタップするとアプリが起動し、…回答済みならタイムラインが直接開く」。回答済みなのでタイムラインが自動で開くべき。
- **実際**: アプリは前面に戻るが、タイムラインは開かず「今日の画面（投稿済み・"世界の回答を読む"ボタンがある状態）」のまま。ユーザーはもう一度手動でボタンをタップしないとタイムラインに入れない。
- **根拠（コード）**:
  - `SameQ/App/RootView.swift:52-56` — 通知タップの実経路（`UNUserNotificationCenterDelegate.didReceive` → `NotificationCenter.post(.sameQNotificationTapped)` → `RootView.onReceive`）は、**常に** `session.handleDeepLink(.today)` を呼ぶ（引数は無条件に `.today` 固定）。
  - `SameQ/App/RootView.swift:70-86` — `onChange(of: session.pendingDeepLinkTarget)` は `case .timeline:` のときだけ `openTimeline()` を呼ぶが、`case .today, .waiting: break` は何もしない。
  - `grep -rn "handleDeepLink" SameQ/` の結果、`handleDeepLink(_:)` の呼び出し箇所はコード全体で1箇所のみ（上記の`.today`固定呼び出し）。`DeepLinkTarget.timeline` を渡すコードはアプリ内に存在しない。つまり `case .timeline: openTimeline()` は**到達不能なコード**であり、実際の通知タップでタイムラインが開くことは仕組み上ありえない。
  - ユニットテスト`testHandleDeepLinkSetsAndConsumesPendingTarget`（`SameQTests/NotificationSchedulingTests.swift:205`）も`.today`しか渡しておらず、`.timeline`経路をテストしているコードはユニット・UIテストのどちらにも存在しない。
  - self-review.md「自分で見つけた弱点 2」でgenerator自身がこの懸念（`pendingDeepLinkTarget`がプロセスkill後は初期フォールバックに頼っている）を記載しており、今回の検証でその懸念が実際の欠陥であることを確認した形。
- **根拠（実機能検証）**: `xcrun simctl push`で実際に通知バナーをシミュレータへ配信し、画面キャプチャでバナー表示を確認（`/tmp/notif_banner.png`等）。通知タップ後、SameQアプリの`timeline.card.body`が表示されないことをXCUITestのアサーションで2回連続確認（`timelineOpened=false`）。バナーの正確なタップ座標特定はシミュレータの座標変換問題で完全な再現には至らなかったが、コード上「到達不能」であることは確定しており、動作結果（タイムラインが一度も開かなかったこと）もこれと矛盾しない。
- **補足**: 「未回答なら今日のお題画面」の方は、`start()`時に`.today`画面がデフォルトで表示される設計により結果的に満たされている（が、これも通知タップ固有のロジックではなく、たまたま一致しているだけ）。

## 改善提案（合否には影響しない）
1. `NotificationDelegateViewController.didReceive`で、通知タップ時点の`AppSession`の状態（`myPost != nil`かどうか）を見て`handleDeepLink(.today)`と`handleDeepLink(.timeline)`を出し分けるか、あるいは`onChange`側で「`.today`ターゲットでも回答済みなら`openTimeline()`を呼ぶ」ようにすれば、実際の通知タップ経路でも仕様どおりの遷移になる。
2. 上記修正後は、`.timeline`ケース（またはそれに相当する分岐）を実際に通す自動テストを1本追加すること（現状ユニット・UIどちらにも存在しない）。

## 評価できなかったもの
- 実機での本物の通知タップ操作（OS本体の通知バナーへの正確な指タップ）。シミュレータの座標系キャリブレーションが不安定で、`xcrun simctl push`によるバナー配信の再現はできたが、正確な座標タップの往復確認までは至らなかった。ただし上記の通りコード上の到達可能性で判断は確定できている。
- 「端末のタイムゾーンを変更した場合に範囲外の時刻へずれないか」「日付をまたいだときに二重で通知されないか」（spec.md 236行の評価者への注記）は、実機での長時間・複数日の運用確認が必要なため未検証。
