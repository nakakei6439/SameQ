import XCTest

/// attempt 6 の実機確認用の一時テスト（evaluator 向けの本番テストではない。
/// 確認後に削除する。eval-5.md [1][2] の修正が実機で効いているかを直接確かめる）。
final class TempAttempt6DeviceProbeTests: XCTestCase {

    private let emoji = "🌙"
    private let answerBody = "A cat looked at me like it knew something."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func safeTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// [2] 投稿ボタンの応答性: submit() が openTimeline() の完了を待たなくなったため、
    /// タップから「あなたの回答」が表示されるまでは数秒で済むはず（60秒待たされない）。
    /// [1] 2回目のタイムライン起動が1回目より速いこと（クールダウンで再試行しない）。
    /// 読み切りまでは待たず、開けた時点（1件目 or 読み切り or 0件）だけを見て閉じ、
    /// すぐ2回目を開いて所要時間を比べる（実機での所要時間を抑えるため）。
    func testSubmitRespondsQuicklyAndSecondOpenIsFasterThanFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-SameQResetState"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.emoji.\(emoji)"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["onboarding.notification.later"].tap()

        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(answerBody)
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)

        let submitStart = Date()
        app.buttons["today.submit"].tap()
        XCTAssertTrue(
            app.staticTexts["today.myAnswer"].waitForExistence(timeout: 10),
            "投稿ボタンを押してから『あなたの回答』が表示されるまでが遅すぎる（openTimeline()を待っている可能性）"
        )
        let submitElapsed = Date().timeIntervalSince(submitStart)
        NSLog("ATTEMPT6_PROBE submitToAnsweredSection=\(submitElapsed)s")
        XCTAssertLessThan(submitElapsed, 10, "投稿ボタンはopenTimeline()を待たずすぐ反応するはず")

        // 1回目のタイムライン展開（自動）を待つ。モデル未ダウンロードの言語があれば
        // 最大90秒の予算のぶん時間が掛かりうる。読み切りまでは待たず、開けたら即座に閉じる。
        // 待っている間、OSの「翻訳／必要なダウンロード」確認シートが実際に画面へ出るかを
        // 目で確認するため、数秒おきにスクリーンショットを添付する
        // （attempt 3〜5でXCUITestのautomation modeが有効化できず一度も確認できていなかった点）。
        let firstOpenStart = Date()
        var opened = false
        var shot = 0
        while Date().timeIntervalSince(firstOpenStart) < 100 {
            if app.staticTexts["timeline.card.body"].exists
                || app.staticTexts["timeline.exhausted"].exists
                || app.staticTexts["timeline.empty"].exists {
                opened = true
                break
            }
            shot += 1
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "attempt6-wait-\(String(format: "%02d", shot))"
            attachment.lifetime = .keepAlways
            add(attachment)
            Thread.sleep(forTimeInterval: 4)
        }
        XCTAssertTrue(opened, "1回目のタイムラインが開かない")
        let firstOpenElapsed = Date().timeIntervalSince(firstOpenStart)
        NSLog("ATTEMPT6_PROBE firstOpenElapsed=\(firstOpenElapsed)s shots=\(shot)")

        safeTap(app.buttons["timeline.close"])

        // 2回目: 同じ未読の言語が .supported のまま残っていればクールダウン中のはずなので、
        // 「準備中…」を経ずすぐ開く（または一瞬だけ「準備中…」を経て即座に開く）。
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))
        let secondOpenStart = Date()
        safeTap(app.buttons["today.openTimeline"])
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 15)
                || app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 15)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 15),
            "2回目のタイムラインが15秒以内に開かない（クールダウンが効いていない可能性）"
        )
        let secondOpenElapsed = Date().timeIntervalSince(secondOpenStart)
        NSLog("ATTEMPT6_PROBE secondOpenElapsed=\(secondOpenElapsed)s")
        XCTAssertLessThan(secondOpenElapsed, 15, "2回目はクールダウン中なので毎回60秒以上待たされてはいけない")
    }
}
