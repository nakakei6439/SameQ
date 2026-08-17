import XCTest

/// スプリント02の受け入れ条件（.product/spec.md 126〜132行）を実機操作で確かめる。
/// 実時間で28時間待てないので、起動引数でお題の日程シナリオを差し替えて検証する。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
final class SprintTwoAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "A cat looked at me like it knew something."

    /// 期限切れ検証で使う秒数。オンボーディングと投稿の操作時間を見込んで長めに取る。
    private let expirySeconds = 75
    private let gapSeconds = 30

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 1（有効なお題が無い時間帯はお題待ち画面）

    func test01_waitingScreenWhenPromptAlreadyEnded() {
        let app = launch(scenario: "expired", reset: true)
        completeOnboarding(app)

        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 8), "お題待ち画面が出る")
        assertNoAnsweringOrTimelineAffordance(app)

        // 再起動してもお題待ちのまま（回答済みの状態が復活したりしない）
        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 10))
        assertNoAnsweringOrTimelineAffordance(app)
    }

    func test02_waitingScreenBeforeFirstPromptStarts() {
        let app = launch(scenario: "upcoming", reset: true)
        completeOnboarding(app)

        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 8), "未開始でもお題待ち画面")
        assertNoAnsweringOrTimelineAffordance(app)
    }

    // MARK: 受け入れ条件 2（有効期間中: 未回答なら今日のお題、回答済みならタイムライン）

    func test03_activePromptOpensTodayThenTimelineAfterRelaunch() {
        let app = launch(scenario: "live", reset: true)
        completeOnboarding(app)

        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8), "未回答なら今日のお題画面")
        XCTAssertTrue(app.textViews["today.input"].exists, "回答入力欄がある")
        XCTAssertFalse(app.otherElements["waiting.root"].exists)

        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))

        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 12),
            "回答済みで起動するとタイムラインが開く"
        )
    }

    // MARK: 受け入れ条件 3・4・6（期限をまたぐ切り替え）

    func test04_timelineClosesAtExpiryAndNextPromptReopensAnswering() {
        let app = launch(scenario: "expiring", reset: true)
        completeOnboarding(app)

        let firstPromptText = app.staticTexts["today.promptText"].label
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "投稿後にタイムラインが開く")

        // タイムラインを開いたまま終了時刻をまたぐ → お題待ちへ切り替わり、回答は1件も残らない
        XCTAssertTrue(
            app.otherElements["waiting.root"].waitForExistence(timeout: Double(expirySeconds) + 60),
            "終了時刻を過ぎるとお題待ち画面へ切り替わる"
        )
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists, "期限切れの回答が残ってはいけない")
        XCTAssertFalse(app.staticTexts["today.myAnswer"].exists, "自分の回答も消える")
        assertNoAnsweringOrTimelineAffordance(app)

        // 次のお題が始まる → 回答済みだったアカウントでも未回答状態に戻る
        XCTAssertTrue(
            app.staticTexts["today.promptText"].waitForExistence(timeout: Double(gapSeconds) + 60),
            "次のお題が始まると今日のお題画面になる"
        )
        XCTAssertNotEqual(app.staticTexts["today.promptText"].label, firstPromptText, "新しいお題に変わっている")
        XCTAssertTrue(app.textViews["today.input"].waitForExistence(timeout: 5), "再び回答できる")
        XCTAssertFalse(app.buttons["today.openTimeline"].exists, "未回答なのでタイムライン導線は無い")
        XCTAssertTrue(app.otherElements["today.locked"].exists, "未回答のロック表示に戻る")
    }

    // MARK: 受け入れ条件 5（履歴の導線が存在しない）

    func test05_noHistoryAffordancesAnywhere() {
        let app = launch(scenario: "live", reset: true)
        completeOnboarding(app)
        assertNoHistoryAffordance(app, screen: "今日のお題（未回答）")

        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        assertNoHistoryAffordance(app, screen: "世界タイムライン")

        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
        assertNoHistoryAffordance(app, screen: "今日のお題（回答済み）")
    }

    // MARK: ヘルパー

    private func launch(scenario: String, reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-SameQScenario", scenario,
                         "-SameQExpirySeconds", String(expirySeconds),
                         "-SameQGapSeconds", String(gapSeconds)]
        if reset { arguments.append("-SameQResetState") }
        app.launchArguments = arguments
        app.launch()
        // 2回目以降の起動でリセットが効かないよう、引数からリセットだけ外しておく
        app.launchArguments = arguments.filter { $0 != "-SameQResetState" }
        return app
    }

    /// 回答も閲覧もできない状態であることの確認（お題待ち画面）。
    private func assertNoAnsweringOrTimelineAffordance(_ app: XCUIApplication) {
        XCTAssertFalse(app.textViews["today.input"].exists, "お題待ちに回答入力欄があってはいけない")
        XCTAssertFalse(app.buttons["today.submit"].exists, "お題待ちに投稿ボタンがあってはいけない")
        XCTAssertFalse(app.buttons["today.openTimeline"].exists, "お題待ちにタイムライン導線があってはいけない")
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists, "お題待ちで他人の回答が見えてはいけない")
        XCTAssertFalse(app.staticTexts["today.promptText"].exists, "お題待ちでお題本文が出てはいけない")
    }

    /// 履歴・過去のお題・いいね一覧への入口が無いこと。
    private func assertNoHistoryAffordance(_ app: XCUIApplication, screen: String) {
        let forbidden = ["履歴", "過去", "アーカイブ", "一覧", "いいねした", "マイページ", "プロフィール",
                         "History", "Archive", "Liked", "Past"]
        let labels = app.buttons.allElementsBoundByIndex.map(\.label)
            + app.staticTexts.allElementsBoundByIndex.map(\.label)
        for label in labels {
            for word in forbidden {
                XCTAssertFalse(
                    label.contains(word),
                    "\(screen) に履歴らしき導線がある: 『\(label)』"
                )
            }
        }
        XCTAssertEqual(app.tabBars.count, 0, "\(screen) にタブバーがある")
    }

    private func completeOnboarding(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()                    // コンセプト
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()                    // 規約
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()                    // 絵文字
        let field = app.textFields["onboarding.nickname"]
        field.tap()
        field.typeText(nickname)
        app.buttons["onboarding.next"].tap()                    // ニックネーム
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["onboarding.notification.later"].tap()
    }

    private func submitAnswer(_ app: XCUIApplication, body: String) {
        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.tap()
        editor.typeText(body)
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["today.submit"].tap()
    }
}
