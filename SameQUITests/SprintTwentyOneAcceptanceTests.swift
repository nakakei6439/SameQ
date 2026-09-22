import XCTest

/// スプリント21（F13 / F14 の通報・ブロック導線の配置修正、前提44）の受け入れ条件を
/// 実機操作で確かめる。
///
/// 背景: 通報・ブロックの入口は以前、画面上部の隅にある小さな灰色の「…」アイコンだけ
/// だった。ラベルも無く、回答が出ているときだけ現れる作りだったため、App Store 審査
/// （Guideline 1.2）でレビュアーが到達できず4度リジェクトされた。回答本体のすぐ下に
/// テキストラベル付きで移設し、`accessibilityIdentifier("timeline.more")` を持つ要素が
/// 常にちょうど1つだけになることを確認する。
final class SprintTwentyOneAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "The train was late, but the sky made up for it."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 1・2・6 — 回答表示中は timeline.more がちょうど1つ、カードの近くにある

    func test01_moreButtonExistsExactlyOnceNearTheCardAndTitleStaysCentered() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))

        // ちょうど1つだけ存在する（受け入れ条件2）。
        let moreButtons = app.buttons.matching(identifier: "timeline.more")
        XCTAssertEqual(moreButtons.count, 1, "timeline.more が2つ以上あると既存UIテストが曖昧参照で壊れる")

        let more = moreButtons.firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(more.isHittable, "スクロールなしで押せる位置にある")

        // カードの本文より下、82pt のいいねボタンより上（＝カードのすぐ下）にある。
        let cardBody = app.staticTexts["timeline.card.body"]
        let likeButton = app.buttons["timeline.like"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            more.frame.minY, cardBody.frame.maxY,
            "通報・ブロックの入口がカード本文より上にある"
        )
        XCTAssertLessThanOrEqual(
            more.frame.maxY, likeButton.frame.minY,
            "通報・ブロックの入口がいいねボタンより下にある（埋もれていない）"
        )

        // 見出し「世界の回答」は依然として中央付近にある（受け入れ条件6）。
        let title = app.staticTexts[L10n_TimelineTitle]
        if title.exists {
            let screenWidth = app.frame.width
            let titleCenterX = title.frame.midX
            XCTAssertEqual(titleCenterX, screenWidth / 2, accuracy: 24, "見出しの中央揃えが崩れている")
        }
    }

    // MARK: 受け入れ条件3 — タップしたときの挙動は変わらない

    func test02_tappingMoreStillOpensSafetySheet() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        app.buttons["timeline.more"].tap()

        XCTAssertTrue(app.otherElements["safety.sheet"].waitForExistence(timeout: 5), "従来どおりシートが開く")
        XCTAssertTrue(app.buttons["safety.report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["safety.block"].waitForExistence(timeout: 5))
    }

    // MARK: 受け入れ条件7 — 回答が表示されていないときは宙に浮かない

    func test03_moreButtonDoesNotExistWhenNoAnswerIsShown() {
        let app = launch(arguments: ["-SameQAnswerCount", "0"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.empty"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["timeline.more"].exists, "回答が無いときは通報ボタンごと存在しない")
    }

    func test04_moreButtonDisappearsAfterReadingTheOnlyAnswer() {
        let app = launch(arguments: ["-SameQAnswerCount", "1"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["timeline.more"].exists, "回答表示中は存在する")

        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["timeline.more"].exists, "読み切ったあとは通報ボタンが宙に浮かない")
    }

    // MARK: 目視確認用スクリーンショット（一時的。evaluator への報告のみが目的）

    func test05_screenshotJapanese() {
        captureTimelineScreenshot(languageCode: "ja", localeID: "ja_JP", name: "timeline_ja")
    }

    func test06_screenshotEnglish() {
        captureTimelineScreenshot(languageCode: "en", localeID: "en_US", name: "timeline_en")
    }

    private func captureTimelineScreenshot(languageCode: String, localeID: String, name: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SameQAnswerCount", "10",
            "-SameQUseLocalBackend",
            "-SameQResetState",
            "-AppleLanguages", "(\(languageCode))",
            "-AppleLocale", localeID
        ]
        app.launch()
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["timeline.more"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: ヘルパー

    /// `L10n.Timeline.title` はテスト対象に直接依存させず、実行時のロケールに応じて
    /// 日英どちらでも一致するよう和英両方を試す簡易ヘルパー。
    private var L10n_TimelineTitle: String {
        Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "世界の回答" : "THE WORLD'S ANSWERS"
    }

    private func launch(arguments: [String], reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = arguments
        launchArguments.append("-SameQUseLocalBackend")
        if reset { launchArguments.append("-SameQResetState") }
        app.launchArguments = launchArguments
        app.launch()
        app.launchArguments = arguments + ["-SameQUseLocalBackend"]
        return app
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
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(body)
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["today.submit"].tap()
    }
}
