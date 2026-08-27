import XCTest

/// スプリント16（F39 / F40）の受け入れ条件を実機操作で確かめる。
/// - F39: 世界タイムライン上部のお題表示帯が、明るい表示・暗い表示のどちらでも
///        はっきり読める（`Theme.promptStripSurface` で白背景・ink 文字）。
/// - F40: 未読の回答が3件未満のとき、前向きな案内が出る／出ないの境界と、
///        既定の空／読み切り表示との二重が出ないこと。
final class SprintSixteenAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Keita"
    private let answerBody = "My honest answer for today's prompt."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: F40 - 未読が0件のとき

    /// 0件（=他人の回答が無い）ときは「前向きな案内」は出さず、既存の `.empty`
    /// 表示だけが「いま何が起きているか分かる文言」として出る（二重に出ない）。
    /// 受け入れ条件6。
    func test01_emptyStateDoesNotShowFewAnswersHint() {
        let app = launch(arguments: ["-SameQAnswerCount", "0"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.empty"].waitForExistence(timeout: 10),
            "0件のときは .empty の終端表示が出る"
        )
        XCTAssertFalse(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "0件のときは前向き案内（F40）が重なってはいけない"
        )
    }

    // MARK: F40 - 未読が1件のとき

    /// 1件のときは `timeline.fewAnswersHint` が出て、1件読んだら exhausted になり
    /// 同時に案内は消える（=終端表示と二重に出ない）。
    func test02_singleAnswerShowsHintThenDisappearsAtExhausted() {
        let app = launch(arguments: ["-SameQAnswerCount", "1"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        // 1件目：未読=1 → ヒントが出る
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10),
            "1件目が出る"
        )
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].waitForExistence(timeout: 5),
            "未読1件のときは前向き案内が出る"
        )

        // ヒントに数値が含まれていないこと（受け入れ条件4）
        let hintText = app.staticTexts["timeline.fewAnswersHint"].label
        for digit in "0123456789" {
            XCTAssertFalse(
                hintText.contains(digit),
                "前向き案内に数値が入っている: 『\(hintText)』"
            )
        }

        // 1件スワイプ → 読み切り → 案内は消える
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8),
            "1件読んだら exhausted が出る"
        )
        XCTAssertFalse(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "exhausted になったとき案内は消える（二重に出ない）"
        )
    }

    // MARK: F40 - 未読が2件のとき

    /// 未読2件のときはヒントが出る。1件読んだ状態（未読1）でもヒントは出続ける。
    func test03_twoAnswersShowHintWhileReading() {
        let app = launch(arguments: ["-SameQAnswerCount", "2"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].waitForExistence(timeout: 5),
            "未読2 → 1 のあいだずっとヒントが出る"
        )

        app.swipeLeft()
        // 2件目：未読1 → まだヒント対象
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "未読1のときもヒントは残る"
        )

        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8),
            "2件読み切ったら exhausted"
        )
        XCTAssertFalse(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "未読0で案内は消える"
        )
    }

    // MARK: F40 - 未読が3件以上のとき

    /// 未読が3件以上あるときはヒントが出ない（=閾値の上側）。0まで読み切ったら
    /// exhausted が出て、そこでもヒントは出ない。
    func test04_threeAnswersDoNotShowHint() {
        let app = launch(arguments: ["-SameQAnswerCount", "5"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "未読5のときは前向き案内が出ない（閾値の上側）"
        )

        // スワイプで読み進めて、最後の2枚（残り 2 / 1）まで持っていく。
        // - 5件 → 1件目描画 → 既読1
        // - スワイプ → 2件目描画 → 既読2（残3 = +1で4、ヒント対象外）
        // - スワイプ → 3件目描画 → 既読3（残2 = +1で3、ヒント対象外）
        // - スワイプ → 4件目描画 → 既読4（残1 = +1で2、ヒント対象）
        for _ in 0..<3 {
            app.swipeLeft()
            XCTAssertTrue(
                app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8)
            )
        }
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].waitForExistence(timeout: 8),
            "最後の2枚に入ったとき初めてヒントが出る"
        )

        // 5件目を読み切る（ヒントは出続ける = 残1 = +1で1、ヒント対象）
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8),
            "5件目が描画される"
        )
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "最後の1枚でもヒントは残る"
        )

        // 最後のスワイプで exhausted（=ヒントが消える）
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "0件（exhausted）で案内は消える"
        )
    }

    // MARK: F40 - いいね/スワイプ/ブロックが効く

    /// ヒントが出ているあいだも、通常操作（スワイプ・いいね・⋯のボタン）が
    /// そのまま機能すること。受け入れ条件7。
    func test05_swipeAndLikeStillWorkWhileHintIsVisible() {
        let app = launch(arguments: ["-SameQAnswerCount", "1"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].waitForExistence(timeout: 10),
            "未読1でヒントが出る"
        )

        // いいねボタンを押せる（ヒントの存在でヒット領域が消えていない）。
        // 押下状態の判定は既存の他スプリント同様 `buttons[...].isSelected` で行う
        // （「いいねしました」のテキストには accessibilityIdentifier を付けていない
        //  ＝ iOS 26 + Xcode 26 の Text 識別子落とし問題を踏まえてボタン側で判定する）。
        let likeButton = app.buttons["timeline.like"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 5), "いいねボタンが押せる")
        XCTAssertTrue(likeButton.isHittable, "いいねボタンのヒット領域が生きている")
        XCTAssertFalse(likeButton.isSelected, "初期状態は未選択")
        likeButton.tap()
        XCTAssertTrue(
            waitForLikeButtonSelected(likeButton, timeout: 5),
            "いいねしたらボタンの選択状態になる"
        )

        // ⋯ボタン（通報・ブロック）も生きている
        XCTAssertTrue(
            app.buttons["timeline.more"].isHittable,
            "⋯ボタンのヒット領域が生きている"
        )

        // スワイプも従来どおり次の1件へ進める
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8),
            "スワイプで読み切りまで進める"
        )
    }

    // MARK: F39 - お題本文が常設表示のまま読める

    /// ヒントが出る／出ないどちらのときも、お題本文（`timeline.promptText`）は
    /// タイムライン上部に表示されており、既読の本文カードと違ってヒット領域は無いが
    /// アクセシビリティラベルとして存在し続ける。
    func test06_promptStripStaysReadableWhileHintFlips() {
        let app = launch(arguments: ["-SameQAnswerCount", "2"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.promptText"].waitForExistence(timeout: 10),
            "お題本文がタイムライン上部に常設表示されている"
        )
        let promptText = app.staticTexts["timeline.promptText"].label
        XCTAssertFalse(promptText.isEmpty, "お題本文が空ではない")

        // 未読2 → 1 に減らすとヒントが出続ける（お題本文もそのまま）
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8)
        )
        XCTAssertEqual(
            app.staticTexts["timeline.promptText"].label, promptText,
            "スワイプでお題本文が変わっていない"
        )
        XCTAssertTrue(
            app.staticTexts["timeline.fewAnswersHint"].exists,
            "未読1になってもヒントが残る"
        )
    }

    // MARK: ヘルパ

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

    /// いいねボタンの選択状態になるまで短時間ポーリングする（XCUIElement に
    /// `waitFor(_:)` が無いため、自前で 0.2s 刻みに確認する）。
    /// `toggleLike` は async なので、タップ直後の `isSelected` 反映に数百ms
    /// かかることがある（SprintFourAcceptanceTests も同じ理由で待ちを挟む）。
    private func waitForLikeButtonSelected(_ button: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.isSelected { return true }
            usleep(200_000)
        }
        return button.isSelected
    }
}
