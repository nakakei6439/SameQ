import XCTest

/// スプリント03の受け入れ条件（.product/spec.md 143〜149行）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
final class SprintThreeAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "A cat looked at me like it knew something."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 2（20回スワイプする間に同じ回答が2回出ない）

    func test01_twentySwipesWithoutRepeat() {
        let app = launch(arguments: ["-SameQAnswerCount", "20"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        var seen: [String] = []
        for step in 1...20 {
            let card = app.staticTexts["timeline.card.body"]
            XCTAssertTrue(card.waitForExistence(timeout: 8), "\(step)件目が出ない")
            let body = card.label
            XCTAssertFalse(seen.contains(body), "\(step)件目に既読の回答が再び出た: 『\(body)』")
            XCTAssertNotEqual(body, answerBody, "自分の回答が他人として出た")
            seen.append(body)
            app.swipeLeft()
        }
        XCTAssertEqual(Set(seen).count, 20)

        // 受け入れ条件 3: 読み切ったら明示された状態表示になる
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8), "読み切りの表示が出る")
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists)
        // 空振りのスワイプを繰り返しても壊れない
        for _ in 0..<3 { app.swipeLeft() }
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].exists, "スワイプしても表示が壊れない")
        XCTAssertTrue(app.buttons["timeline.close"].isHittable, "閉じる操作は生きている")
    }

    // MARK: 受け入れ条件（評価者注記）アプリを再起動しても既読が残る

    func test02_viewedAnswersDoNotReturnAfterRelaunch() {
        let app = launch(arguments: ["-SameQAnswerCount", "20"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        var seen: [String] = []
        for _ in 1...8 {
            let card = app.staticTexts["timeline.card.body"]
            XCTAssertTrue(card.waitForExistence(timeout: 8))
            seen.append(card.label)
            app.swipeLeft()
        }
        // 8回送った結果、画面に出ている9件目も「見た」ことになる
        let onScreen = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(onScreen.waitForExistence(timeout: 8))
        seen.append(onScreen.label)

        app.terminate()
        app.launch()

        for step in 1...11 {
            let card = app.staticTexts["timeline.card.body"]
            XCTAssertTrue(card.waitForExistence(timeout: 12), "再起動後の\(step)件目が出ない")
            XCTAssertFalse(seen.contains(card.label), "再起動後に既読の回答が出た: 『\(card.label)』")
            seen.append(card.label)
            app.swipeLeft()
        }
        XCTAssertEqual(Set(seen).count, 20)
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8))
    }

    // MARK: 受け入れ条件 5（自分の回答しか無い場合は空状態）

    func test03_emptyStateWhenOnlyMyOwnAnswerExists() {
        let app = launch(arguments: ["-SameQAnswerCount", "0"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.empty"].waitForExistence(timeout: 10), "空状態の説明が出る")
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists, "自分の回答が他人として出てはいけない")
        XCTAssertFalse(app.staticTexts["timeline.exhausted"].exists, "0件は『読み切り』ではない")
        // 閉じて開き直しても空状態のまま壊れない
        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
        app.buttons["today.openTimeline"].tap()
        XCTAssertTrue(app.staticTexts["timeline.empty"].waitForExistence(timeout: 8))
    }

    // MARK: 受け入れ条件 3（他人の回答が1件だけのケース）

    func test04_singleAnswerThenExhausted() {
        let app = launch(arguments: ["-SameQAnswerCount", "1"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10), "1件だけ出る")
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8))

        // 再起動しても、その1件はもう出ない
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 12), "再起動しても既読のまま")
    }

    // MARK: 受け入れ条件 4（1件目が毎回同一とは限らない）

    func test05_firstAnswerIsNotAlwaysTheSame() {
        var firstBodies: Set<String> = []
        for _ in 0..<6 {
            let app = launch(arguments: ["-SameQAnswerCount", "20"], reset: true)
            completeOnboarding(app)
            submitAnswer(app, body: answerBody)
            let card = app.staticTexts["timeline.card.body"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            firstBodies.insert(card.label)
            app.terminate()
            if firstBodies.count > 1 { break }
        }
        XCTAssertGreaterThan(firstBodies.count, 1, "1件目が毎回同じ回答になっている")
    }

    // MARK: 受け入れ条件 6（前へ戻る操作が存在しない）

    func test06_noBackAffordanceInTimeline() {
        let app = launch(arguments: ["-SameQAnswerCount", "20"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))

        let forbidden = ["戻る", "前へ", "ひとつ前", "Back", "Previous", "Undo", "取り消"]
        let labels = app.buttons.allElementsBoundByIndex.map(\.label)
        for label in labels {
            for word in forbidden {
                XCTAssertFalse(label.contains(word), "タイムラインに戻る操作らしきボタンがある: 『\(label)』")
            }
        }
        XCTAssertEqual(app.buttons.matching(identifier: "timeline.previous").count, 0)

        // 右スワイプ（戻る方向）でも前の回答には戻らず、次の未読へ進む
        let first = app.staticTexts["timeline.card.body"].label
        app.swipeLeft()
        XCTAssertTrue(waitForBodyToChange(app, from: first))
        let second = app.staticTexts["timeline.card.body"].label
        app.swipeRight()
        XCTAssertTrue(waitForBodyToChange(app, from: second))
        let third = app.staticTexts["timeline.card.body"].label
        XCTAssertNotEqual(third, first, "右スワイプで前の回答に戻ってはいけない")
        XCTAssertNotEqual(third, second)
    }

    // MARK: 受け入れ条件 1（別のお題の回答が混ざらない）

    func test07_onlyTodaysPromptAnswersAppear() {
        // 1つ目のお題が45秒で終わり、15秒後に2つ目が始まる
        let app = launch(
            arguments: ["-SameQScenario", "expiring",
                        "-SameQExpirySeconds", "45",
                        "-SameQGapSeconds", "15",
                        "-SameQAnswerCount", "6"],
            reset: true
        )
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        var firstPromptBodies: [String] = []
        for _ in 0..<3 {
            let card = app.staticTexts["timeline.card.body"]
            guard card.waitForExistence(timeout: 8) else { break }
            firstPromptBodies.append(card.label)
            app.swipeLeft()
        }
        XCTAssertFalse(firstPromptBodies.isEmpty)

        // 1つ目のお題が終わり、2つ目が始まるまで待つ
        // （タイムラインの裏に今日のお題画面が残るので、先にお題待ち画面を待つ）
        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 120), "1つ目のお題が終わる")
        XCTAssertTrue(app.textViews["today.input"].waitForExistence(timeout: 120), "次のお題では再び回答できる")
        submitAnswer(app, body: "Second prompt answer from me.")

        for _ in 0..<6 {
            let card = app.staticTexts["timeline.card.body"]
            guard card.waitForExistence(timeout: 8) else { break }
            XCTAssertFalse(
                firstPromptBodies.contains(card.label),
                "前のお題への回答が今日のタイムラインに出た: 『\(card.label)』"
            )
            app.swipeLeft()
        }
    }

    // MARK: ヘルパー

    private func launch(arguments: [String], reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = arguments
        if reset { launchArguments.append("-SameQResetState") }
        app.launchArguments = launchArguments
        app.launch()
        // 2回目以降の起動でリセットが効かないよう、引数からリセットだけ外しておく
        app.launchArguments = arguments
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

    private func waitForBodyToChange(_ app: XCUIApplication, from previous: String) -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            let card = app.staticTexts["timeline.card.body"]
            if !card.exists { return true }          // 終端表示に移った場合も「変わった」とみなす
            if card.label != previous { return true }
            usleep(200_000)
        }
        return false
    }
}
