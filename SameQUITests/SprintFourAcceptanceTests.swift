import XCTest

/// スプリント04の受け入れ条件（.product/spec.md 160〜166行）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
final class SprintFourAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "A cat looked at me like it knew something."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 1・2・6（通報→理由選択→送信→完了表示→次へ進む／再起動しても戻らない）

    func test01_reportRemovesAnswerAndAdvances() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        let card = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let reportedBody = card.label

        app.buttons["timeline.more"].tap()
        XCTAssertTrue(app.buttons["safety.report"].waitForExistence(timeout: 5), "通報の導線がある")
        app.buttons["safety.report"].tap()

        // 理由を選ぶまで送信できない
        let submit = app.buttons["safety.reportSubmit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "理由の選択画面が出る")
        XCTAssertFalse(submit.isEnabled, "理由を選ばずに送信できてはいけない")
        app.buttons["safety.reason.discrimination"].tap()
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        // 完了表示
        XCTAssertTrue(app.staticTexts["safety.reportDone"].waitForExistence(timeout: 5), "完了表示が出る")
        app.buttons["safety.close"].tap()

        // 閉じたときには次の回答へ進んでいる（操作前の位置で固まらない）
        XCTAssertTrue(card.waitForExistence(timeout: 8), "次の回答が出ない")
        XCTAssertNotEqual(card.label, reportedBody, "通報した回答が残っている")

        // 再起動しても通報した回答は戻らない
        app.terminate()
        app.launchArguments = ["-SameQAnswerCount", "10", "-SameQResetViewed", "-SameQUseLocalBackend"]
        app.launch()
        for _ in 1...9 {
            guard card.waitForExistence(timeout: 8) else { break }
            XCTAssertNotEqual(card.label, reportedBody, "再起動後に通報した回答が出た")
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8),
            "通報したぶんを除いて読み切りになる"
        )
    }

    // MARK: 受け入れ条件 3・6（ブロックした人の回答は以後出てこない）

    func test02_blockRemovesAuthorAndAdvances() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        let card = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let blockedBody = card.label

        app.buttons["timeline.more"].tap()
        XCTAssertTrue(app.buttons["safety.block"].waitForExistence(timeout: 5), "ブロックの導線がある")
        app.buttons["safety.block"].tap()
        XCTAssertTrue(app.buttons["safety.blockConfirm"].waitForExistence(timeout: 5), "確認が挟まる")
        app.buttons["safety.blockConfirm"].tap()
        XCTAssertTrue(app.staticTexts["safety.blockDone"].waitForExistence(timeout: 5), "完了表示が出る")
        app.buttons["safety.close"].tap()

        XCTAssertTrue(card.waitForExistence(timeout: 8), "次の回答が出ない")
        XCTAssertNotEqual(card.label, blockedBody, "ブロックした回答が残っている")

        // 同じお題でスワイプを続けても出てこない
        for _ in 1...9 {
            guard card.waitForExistence(timeout: 6) else { break }
            XCTAssertNotEqual(card.label, blockedBody, "ブロックした人の回答が出た")
            app.swipeLeft()
        }
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8))
    }

    // MARK: 受け入れ条件 4（設定のブロック一覧と解除）

    func test03_blockListShowsOnlyEmojiAndNicknameAndUnblockRestores() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        let card = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let blockedBody = card.label
        block(app)
        app.buttons["timeline.close"].tap()

        // ハンバーガーメニュー → 設定 → ブロック一覧（新機能）
        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5), "メニューへの導線がある")
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5), "設定への導線がある")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.otherElements["settings.blocked.row"].waitForExistence(timeout: 5), "一覧に1件出る")
        XCTAssertEqual(app.otherElements.matching(identifier: "settings.blocked.row").count, 1)

        // 相手を特定できる情報（本文・言語・国）が漏れていない
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(texts.contains(blockedBody), "ブロック一覧に回答本文が出ている")
        for word in ["日本", "英語", "Japan", "ja", "en", "ko", "言語", "国"] {
            XCTAssertFalse(texts.contains(word), "ブロック一覧に『\(word)』が出ている")
        }

        // 解除すると一覧から消える
        app.buttons["settings.unblock"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["settings.blocked.empty"].waitForExistence(timeout: 5), "一覧が空になる")
        app.buttons["settings.close"].tap()

        // 解除した人の回答は再び表示対象に戻る（読み切りにならず、また出てくる）
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
        app.buttons["today.openTimeline"].tap()
        var restored = false
        for _ in 1...10 {
            guard card.waitForExistence(timeout: 6) else { break }
            if card.label == blockedBody { restored = true; break }
            app.swipeLeft()
        }
        XCTAssertTrue(restored, "解除した人の回答が戻ってこない")
    }

    // MARK: 受け入れ条件（評価者注記）最後の1件をブロックしたときの落ち方

    func test04_blockingTheLastAnswerFallsBackToEndState() {
        let app = launch(arguments: ["-SameQAnswerCount", "1"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        block(app)

        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8),
            "最後の1件をブロックしたら読み切り表示に落ちる"
        )
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists)
        // 空振りのスワイプでも壊れない
        for _ in 0..<3 { app.swipeLeft() }
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].exists)
        XCTAssertTrue(app.buttons["timeline.close"].isHittable)

        // 閉じて開き直しても壊れない
        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
        app.buttons["today.openTimeline"].tap()
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8))
    }

    // MARK: 受け入れ条件 5（相手に伝わる表示や通知が無い）

    func test05_noSignalIsShownToTheOtherPerson() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))

        // 通報・ブロックの説明に「相手に伝わらない」ことが明記されている
        app.buttons["timeline.more"].tap()
        XCTAssertTrue(app.buttons["safety.report"].waitForExistence(timeout: 5))
        let sheetTexts = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " / ")
        XCTAssertTrue(sheetTexts.contains("相手に伝わる"), "相手に伝わらないことの説明が無い: \(sheetTexts)")
        app.buttons["safety.cancel"].tap()

        // カードにも一覧にも「通報された／ブロックされた」を相手に見せる表示は無い
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5))
        let forbidden = ["通報されました", "ブロックされました", "報告されました", "警告"]
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
            + app.buttons.allElementsBoundByIndex.map(\.label)
        for label in labels {
            for word in forbidden {
                XCTAssertFalse(label.contains(word), "相手に伝わる表示らしきものがある: 『\(label)』")
            }
        }
    }

    // MARK: 回帰（いいね・次へ・閉じるが今までどおり動く）

    func test06_existingTimelineActionsStillWork() {
        let app = launch(arguments: ["-SameQAnswerCount", "10"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        let card = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let first = card.label
        app.buttons["timeline.like"].tap()
        XCTAssertTrue(app.buttons["timeline.like"].isSelected, "いいねの押下状態にならない")
        app.swipeLeft()
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertNotEqual(card.label, first)
        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
    }

    // MARK: 受け入れ条件 4（お題待ちのあいだも設定からブロック一覧を見られる）

    func test07_settingsReachableFromWaitingScreen() {
        let app = launch(arguments: ["-SameQScenario", "expired"], reset: true)
        completeOnboarding(app)
        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 10), "お題待ち画面")

        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5), "メニューへの導線がある")
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5), "設定への導線がある")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["settings.blocked.empty"].waitForExistence(timeout: 5), "ブロック一覧（空）")
        app.buttons["settings.close"].tap()
        app.buttons["menu.close"].tap()
        XCTAssertTrue(app.otherElements["waiting.root"].waitForExistence(timeout: 5), "閉じるとお題待ちへ戻る")
    }

    // MARK: ヘルパー

    private func launch(arguments: [String], reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = arguments
        launchArguments.append("-SameQUseLocalBackend")
        if reset { launchArguments.append("-SameQResetState") }
        app.launchArguments = launchArguments
        app.launch()
        // 2回目以降の起動でリセットが効かないよう、引数からリセットだけ外しておく
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

    /// いま出ている回答の投稿者をブロックして、完了表示を閉じるまで。
    private func block(_ app: XCUIApplication) {
        app.buttons["timeline.more"].tap()
        XCTAssertTrue(app.buttons["safety.block"].waitForExistence(timeout: 5))
        app.buttons["safety.block"].tap()
        XCTAssertTrue(app.buttons["safety.blockConfirm"].waitForExistence(timeout: 5))
        app.buttons["safety.blockConfirm"].tap()
        XCTAssertTrue(app.staticTexts["safety.blockDone"].waitForExistence(timeout: 5))
        app.buttons["safety.close"].tap()
    }
}
