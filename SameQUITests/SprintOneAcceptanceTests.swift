import XCTest

/// スプリント01の受け入れ条件（.product/spec.md 107〜115行）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
final class SprintOneAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "The bus driver waved at a dog today."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 1・2（順序と、同意・絵文字が無いと進めないこと）

    func test01_onboardingOrderAndGuards() {
        let app = launchFresh()

        // コンセプト説明
        XCTAssertTrue(app.staticTexts["同じ問いに、\n答えるだけ。"].waitForExistence(timeout: 5))
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.isEnabled, "コンセプト説明では次へ進める")
        next.tap()

        // 利用規約：同意するまで進めない
        XCTAssertTrue(app.staticTexts["はじめる前に"].waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled, "同意前は次へ進めない")
        app.buttons["onboarding.terms.agree"].tap()
        XCTAssertTrue(next.isEnabled, "同意後は次へ進める")
        next.tap()

        // 絵文字：1つ選ぶまで進めない
        XCTAssertTrue(app.staticTexts["あなたの印を\n1つ選んでください"].waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled, "絵文字未選択では次へ進めない")
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        XCTAssertTrue(next.isEnabled, "絵文字を選ぶと次へ進める")
        next.tap()

        // ニックネーム：空のままでも進める
        XCTAssertTrue(app.staticTexts["呼び名を\n決めますか？"].waitForExistence(timeout: 3))
        XCTAssertTrue(next.isEnabled, "ニックネームが空でも次へ進める")
        next.tap()

        // 通知許可
        XCTAssertTrue(app.buttons["onboarding.notification.allow"].waitForExistence(timeout: 3))
        app.buttons["onboarding.notification.allow"].tap()
        allowSystemNotificationAlertIfNeeded()

        // 今日のお題画面に到達する
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))
    }

    // MARK: 受け入れ条件 4・5・6・7（ロック → 投稿 → タイムライン → 自分は出ない）

    func test02_lockedUntilAnsweredThenTimeline() {
        let app = launchFresh()
        completeOnboarding(app, nickname: nickname, allowNotifications: false)

        // 未回答のあいだはタイムラインへの導線が無く、ロック表示だけがある
        XCTAssertTrue(app.otherElements["today.locked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.openTimeline"].exists, "未回答でタイムラインへの導線があってはいけない")
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists, "未回答で他人の回答が見えてはいけない")

        submitAnswer(app, body: answerBody)

        // 投稿完了後に世界タイムラインが開き、自分以外の回答が1件表示される
        let card = app.staticTexts["timeline.card.body"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "投稿後にタイムラインが開く")
        let firstBody = card.label
        XCTAssertFalse(firstBody.isEmpty)
        XCTAssertNotEqual(firstBody, answerBody, "自分の回答が他人の回答として出てはいけない")
        XCTAssertTrue(app.staticTexts["timeline.card.emoji"].exists, "投稿者の絵文字が表示される")

        // スワイプすると別の回答へ切り替わる
        app.swipeLeft()
        XCTAssertTrue(waitForBodyToChange(app, from: firstBody), "スワイプで別の回答に切り替わる")

        // 最後まで送っても自分の回答は一度も出ない
        var seen = 0
        while app.staticTexts["timeline.card.body"].exists, seen < 30 {
            XCTAssertNotEqual(app.staticTexts["timeline.card.body"].label, answerBody, "自分の投稿がタイムラインに出た")
            seen += 1
            app.buttons["timeline.next"].tap()
        }
        XCTAssertTrue(app.otherElements["timeline.end"].waitForExistence(timeout: 5), "読み切ったら終端表示になる")
        XCTAssertGreaterThanOrEqual(seen, 10, "検証には自分以外の回答が10件以上必要")
    }

    // MARK: 受け入れ条件 8（いいねの押下状態が開き直しても残る）

    /// スプリント03（F12 既読管理）以降、一度出した回答は既読になり二度と出てこない。
    /// そのため「開き直して同じ回答を探す」手順は、既読だけを消す `-SameQResetViewed` を挟んで行う。
    /// いいねが保存されていること自体は `TimelineSelectionTests` でも確認している。
    func test03_likePersistsAcrossReopeningTimeline() {
        let app = launchFresh()
        completeOnboarding(app, nickname: nickname, allowNotifications: false)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        let likedBody = app.staticTexts["timeline.card.body"].label

        let like = app.buttons["timeline.like"]
        XCTAssertFalse(like.isSelected, "最初は未押下")
        like.tap()
        XCTAssertTrue(like.isSelected, "押すと押下状態になる")

        // 別の投稿へ進んでから、タイムラインを閉じる
        app.buttons["timeline.next"].tap()
        XCTAssertTrue(waitForBodyToChange(app, from: likedBody))
        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))

        // 既読だけを消して起動し直し、いいねした回答をもう一度出せる状態にする
        app.terminate()
        app.launchArguments = ["-SameQResetViewed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 12))

        // 並び順は毎回変わるので、いいねした回答が出てくるまで送る
        var found = false
        for _ in 0..<40 {
            guard app.staticTexts["timeline.card.body"].exists else { break }
            if app.staticTexts["timeline.card.body"].label == likedBody {
                found = true
                break
            }
            app.buttons["timeline.next"].tap()
            _ = app.staticTexts["timeline.card.body"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(found, "いいねした回答が見つからなかった")
        XCTAssertTrue(app.buttons["timeline.like"].isSelected, "開き直しても押下状態が保たれる")
    }

    // MARK: 受け入れ条件 3（再起動しても初回設定が出ず、絵文字とニックネームが残る）

    func test04_accountSurvivesRelaunch() {
        let app = launchFresh()
        completeOnboarding(app, nickname: nickname, allowNotifications: false)
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 5))

        // 未回答のまま再起動 → 初回設定は出ず、今日のお題画面が開く
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["onboarding.next"].exists, "初回設定が再表示されてはいけない")
        XCTAssertTrue(app.staticTexts[emoji].exists, "選んだ絵文字が残っている")
        XCTAssertTrue(app.staticTexts[nickname].exists, "入力したニックネームが残っている")

        // 回答してから再起動 → タイムラインが開く
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10), "回答済みで起動するとタイムラインが開く")
    }

    // MARK: オンボーディング途中で落としても中途半端なアカウントが残らない

    func test05_abortedOnboardingLeavesNoAccount() {
        let app = launchFresh()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()

        // ニックネーム入力の途中で終了する
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.staticTexts["同じ問いに、\n答えるだけ。"].waitForExistence(timeout: 8), "初回設定の最初からやり直しになる")
        XCTAssertFalse(app.staticTexts["today.promptText"].exists)
    }

    // MARK: ヘルパー

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SameQResetState"]
        app.launch()
        return app
    }

    private func completeOnboarding(_ app: XCUIApplication, nickname: String?, allowNotifications: Bool) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        app.buttons["onboarding.next"].tap()                    // コンセプト
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()                    // 規約
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()                    // 絵文字
        if let nickname {
            let field = app.textFields["onboarding.nickname"]
            field.tap()
            field.typeText(nickname)
        }
        app.buttons["onboarding.next"].tap()                    // ニックネーム
        // キーボードが下がりきる前にタップすると、下のボタンではなくキーボードに当たる
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        if allowNotifications {
            app.buttons["onboarding.notification.allow"].tap()
            allowSystemNotificationAlertIfNeeded()
        } else {
            app.buttons["onboarding.notification.later"].tap()
        }
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))
    }

    private func submitAnswer(_ app: XCUIApplication, body: String) {
        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(body)
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["today.submit"].tap()
    }

    private func waitForBodyToChange(_ app: XCUIApplication, from previous: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let card = app.staticTexts["timeline.card.body"]
            if !card.exists { return true }          // 終端表示に移った場合も「変わった」とみなす
            if card.label != previous { return true }
            usleep(200_000)
        }
        return false
    }

    private func allowSystemNotificationAlertIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["許可", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }
}
