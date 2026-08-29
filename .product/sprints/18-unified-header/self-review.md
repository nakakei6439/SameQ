# スプリント 18 自己評価（attempt 2）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| F42: 今日/お題待ちの上部に「メニュー/SameQ/通知ベル/Plus/絵文字」が1行で並ぶ。歯車・ヘッダー上のニックネーム文字列は無い | 達成 | `SameQUITests/SprintEighteenAcceptanceTests.test01_todayScreenHasUnifiedHeader` PASS（`menu.open` / `notifications.open` / `plus.open` / `header.appName` の存在と `settings.open`・`today.identity.nickname` の不在を検証） |
| F43: メニューから通知・Plus・設定へ到達でき、設定の中身はスプリント11と同じ | 達成 | `test02_menuHasAllThreeRows`・`test03_menuOpensAllSubscreens` ともに PASS。設定画面の項目（`settings.profile.emoji` / `settings.notification.status` / `settings.plus.status`）は Sprint11 と同一 |
| F43: メニュー下部にアプリのバージョンが "vX.Y (Z)" 形式で表示される | 達成 | `test04_menuShowsVersionString` が正規表現 `^v\d+(?:\.\d+)+\s*\(\d+\)$` で PASS |
| F44: ベルからもメニュー「通知」からも同じお知らせ画面が開き、「アプリ通知」と「運営お知らせ」を切り替えられる。「アプリ通知」は常に空状態で履歴を残さないことが分かる説明文が出る | 達成 | `test05_notificationsScreenHasTwoTabsWithEmptyStateExplanation` PASS（両タブの存在と「アプリ通知」タブで `notifications.app.empty` の説明文が表示） |
| F44: サーバー側のお知らせ追加がアプリ再インストール不要で反映され、新しい順で見出し・本文・公開日時が読める | 達成（attempt 2 で `publishedAt` 表示を追加） | **attempt 2**: `NotificationsView` の行ビューに `Text(item.publishedAt, format: .dateTime.year().month().day())` を追加し、`publishedAt` 識別子 `notifications.operator.publishedAt` を露出。`supabase/migrations/20260829000011_announcements.sql` は本番適用済み、announcements テーブル RLS は select のみ許可 |
| F45: Plus 画面に「1ヶ月無料」相当の案内が出て、購入ボタンが「無料で試す」相当になる。提供されない状態では旧表示に戻る | 達成（attempt 2 で trial の ON/OFF を分離） | **attempt 2**: `-SameQFakePlusTrial` フラグを追加。既定（フラグ無し）は `introductoryOfferDescription: nil` で Sprint10/14 と同じ「Plus に登録」購入表示に落ちる。`test06_plusScreenShowsFreeTrialBadgeAndButton`（trial 有り）と **新規** `test10_plusScreenWithoutTrialFlagShowsLegacyPurchaseButton`（trial 無し・`label CONTAINS 'Plus に登録'` を assert）の両方で確認 |
| F43: バージョン表示を8回連続タップ＋8桁数字で隠し開発者モードが解錠 | 達成（UI ジェスチャは評価者実機検証、ロジックはユニットで担保） | `test07` / `test08` は `XCTSkip`（SwiftUI `Text.onTapGesture` の連続タップが不安定なため evaluator も skip と認めていた）。`SameQTests/DeveloperModeTests` の 4 本で永続化されないこと（`debugPlusOverride` は `AppSession` 再生成時に `nil`）と 3 値トグルを担保 |
| F15: en 端末で主要文言がすべて英語 | 達成 | `test09_englishLocaleShowsEnglishStrings` PASS（`-AppleLanguages (en)`、`menu.close` / `notifications.close` が "Close"、ヘッダーベルが "Notifications"、Plus 画面の purchase ボタンが "Start free trial"） |

**達成数: 8/8（受け入れ条件）**

## eval-1.md [1]〜[4] の修正内容

### [1] メニュー → 子画面 → 閉じる → ホームの動線（`MenuView.openChildSheet`）
- `MenuView.openChildSheet(_:)` を新設。`menuRow` の `Button { action() }` を `Button { openChildSheet(action) }` に置換。
- `openChildSheet` は `dismiss()`（メニュー自身を閉じる）で先にメニューを閉じ、`DispatchQueue.main.asyncAfter(deadline: .now() + 0.4)` で dismissal アニメーションが落ち着いてから `action()` を実行。SwiftUI のシート同時スタックを回避。
- `SprintFourAcceptanceTests.test03` の `app.buttons["menu.close"].tap()` を撤去（メニューは子画面を開く前に既に閉じているため不要）。これで「設定→ブロック解除→『閉じる』→お題待ち」の動線が復活。

### [2] アカウント削除のフレーク（[1] の派生で解消）
- `AppSession.resetToOnboarding()` は従来どおり `isMenuPresented` / `isSettingsPresented` を一括 false 化。openChildSheet 化でスタックが浅くなり、三重シート同時 dismiss の不安定さが解消する見込み。`SprintElevenAcceptanceTests.test03_accountDeletionShowsConfirmationAndResetsToOnboarding` を**単独**でもフルランでも通ることを確認（要 eval-2 再評価）。

### [3] FakePlus の trial ON/OFF を分離
- `LaunchOptions.fakePlusWithIntroductoryOffer: Bool = false` を追加（`-SameQFakePlusTrial` 起動引数）。
- `FakePlusService.init(withIntroductoryOffer: Bool = false)` を追加。**既定は `false`** で、`availableProducts()` が `introductoryOfferDescription: nil` を返し、Sprint10 / Sprint14 と同じ「Plus に登録」購入表示に落ちる。
- `AppSession.start()` の `LaunchOptions.current.fakePlus` 分岐で `withIntroductoryOffer: LaunchOptions.current.fakePlusWithIntroductoryOffer` を渡す。
- `PlusIntroductoryOfferTests.test04_fakePlusServiceExposesIntroductoryOfferWhenEnabled` を更新（既定で `nil`・`withIntroductoryOffer: true` で `notNil`）。
- **新規** `SprintEighteenAcceptanceTests.test10_plusScreenWithoutTrialFlagShowsLegacyPurchaseButton` を追加し、フラグ無しで「Plus に登録」ボタンが現れることを assert。
- `test06` / `test09` は `launchFresh(fakePlus: true, fakePlusTrial: true, ...)` に更新。

### [4] お知らせ行に `publishedAt` を表示
- `NotificationsView.operatorAnnouncementsList` の行ビューに `Text(item.publishedAt, format: .dateTime.year().month().day())` を追加（タイトルと本文の間）。端末ロケールの短い日付書式（日本語: 2026/08/29 / 英語: 8/29/2026）。
- アクセシビリティ識別子 `notifications.operator.publishedAt` を付与。

## 動かし方（evaluator 向け）

### ビルド・テスト
```bash
# プロジェクトルートで
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  build

# ユニットテスト（Sprint18 追加分）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SameQTests/AnnouncementTests \
  -only-testing:SameQTests/DeveloperModeTests \
  -only-testing:SameQTests/PlusIntroductoryOfferTests test

# UI テスト（Sprint18 追加分 9件 + 2 skip）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:SameQUITests/SprintEighteenAcceptanceTests test
```

### 起動引数
- 既定（trial 無し）: `-SameQUseLocalBackend -SameQResetState -SameQFakePlus` → Plus 画面の購入ボタンは「Plus に登録」
- Trial 有り: 上記に加えて `-SameQFakePlusTrial` → バッジ「1ヶ月無料」+ 購入ボタン「無料で試す」

### 実機での隠し開発者モード検証手順
1. ホーム → ヘッダー左上「≡」→ メニュー
2. 下部の `vX.Y (Z)` を **8回連続でタップ**
3. アラート → パスコード欄に **19820427**（8桁）→ "Unlock"
4. メニュー最下部に「DEVELOPER MODE」セクションが現れ、Plus 状態を **Actual / Always Plus / Always Free** で切り替えられる
5. アプリを完全終了 → 再起動 → 隠し開発者モードが消え Actual に戻る（永続化されない）

## 検証結果

| テスト対象 | 件数 | 結果 |
|---|---|---|
| `SameQTests/AnnouncementTests` | 3 | 全件 PASS |
| `SameQTests/DeveloperModeTests` | 4 | 全件 PASS |
| `SameQTests/PlusIntroductoryOfferTests` | 5 | 全件 PASS |
| `SameQUITests/SprintEighteenAcceptanceTests` | 10（うち 2 skip） | 8 件 PASS・2 件 XCTSkip（test07/test08: SwiftUI Text.onTapGesture の 8 回連続タップが XCUITest 不安定のため generator / evaluator 双方が skip と合意済み） |
| `SameQUITests/SprintFourAcceptanceTests/test03`（[1] 回帰） | 1 | PASS |
| `SameQUITests/SprintTenAcceptanceTests/test02/test07`（[3] 回帰） | 2 | PASS |
| `SameQUITests/SprintElevenAcceptanceTests/test03`（[2] 回帰） | 1 | PASS |
| `SameQUITests/SprintSevenAcceptanceTests`（直近 2〜3 スプリントの固定サンプル） | 6 | 全件 PASS |

ビルド: `BUILD SUCCEEDED`、クラッシュ 0、未処理例外 0。

## 自分で見つけた弱点

- **XCUITest で `Text.onTapGesture` を 8 回叩くのが不安定**（attempt 1 と同じ）: test07 / test08 は XCTSkip。`DeveloperModeTests`（ユニット 4 本）で永続化なし・3 値トグルを担保しているが、UI ジェスチャ経由の動線は実機でしか検証していない。evaluator 側での実機手動検証が必要（パスコード 19820427）。
- **`openChildSheet` の 0.4 秒遅延**は SwiftUI のシート dismissal アニメーションが完了するのを待つためのマジックナンバー。iOS のバージョンやアニメーション設定によって前後する可能性があり、最悪「メニューが完全に閉じる前に次のシートを立てて二重スタック」が再発しうる。実機で 0.4 秒が不足する／過剰な事象があれば eval で報告してほしい。
- **`NotificationsView` の `publishedAt` 表示は端末ロケールの短い日付書式**（例: 2026/08/29）。時刻（HH:MM）は出していない。spec は「公開日時」とだけ書いており時刻まで要求していないが、必要なら追加可能（`format: .dateTime.year().month().day().hour().minute()` に変更）。
- **`-SameQFakePlusTrial` フラグを `-SameQFakePlus` と組み合わせる必要がある**ことに注意。`-SameQFakePlusTrial` だけ付けても `fakePlus == false` なら `RevenueCatPlusService` が使われて trial 経路は踏まない。README かテストヘルパへの注記が必要かもしれない。

## 提案（今回はやらなかったこと）

- **お知らせ本文のロケール対応**（en 端末でも日本語の本文のまま）: spec 受け入れ条件3「無料トライアルの案内 … すべて英語」の範囲外なので未着手。別スプリント想定。
- **`PlusTrialPeriodUnit.year` / `.week` の fake ケース**: FakePlusService は `.month` の 1 ヶ月無料のみ返す。年間無料トライアルを追加したときに同じ UI パスが動くかは未確認。
- **お知らせの "既読" 機能**: DB の `read_at` カラム追加＋既読管理は仕様にないため未実装。
- **`debugPlusOverride` のキー名や Passcode を Keychain 経由にする**: 現状はソースにハードコード（バイナリ/ソースから自明）。
- **`openChildSheet` の遅延時間を SwiftUI の dismissal 完了コールバックで受け取る**ようにすればマジックナンバー 0.4 を消せる（が、dispatch async の方が実装は単純）。