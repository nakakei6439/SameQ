import XCTest

/// スプリント06（.product/spec.md 194〜201行）の修正（attempt 2）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
///
/// このシミュレータでは Apple Translation Framework 自体が使えない（evaluator が
/// `unsupportedLanguagePairing` を実測・確認済み）ため、Debug限定の疑似翻訳モード
/// （`-SameQFakeTranslate`）を使う。これは実際の `TranslationSession` を使わず
/// `[<言語コード>] <原文>` という決定的な変換を返すので、シミュレータでも
/// 「翻訳結果が画面へ反映される」「非対応言語は一度も現れない」「同じ言語ペアが連続しても
/// 途中で止まらない」ことを確定的に確認できる。
final class SprintSixAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let answerBody = "A cat looked at me like it knew something."

    /// 検証用に仕込まれた、翻訳できない言語コード（`zxx`）の回答に含まれる目印。
    private let untranslatableMarker = "sameQ_untranslatable_test_marker"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件1・4・6（翻訳結果の反映・待ちの発生・エラーダイアログなし）
    //       ＋ バグ1の再発防止（同じ原文言語が連続しても途中で止まらない）

    /// 疑似翻訳モードで同梱シード（多言語）をそのまま読み切るまでスワイプする。
    /// 途中で止まらず（＝待ち行列が固着せず）、翻訳された本文（`[<言語コード>] `接頭辞）が
    /// 少なくとも1件は表示され、非対応言語（`zxx`）は一度も現れないことを確認する。
    func test01_fakeTranslateAppliesAcrossTimelineWithoutStalling() {
        let app = launch(arguments: ["-SameQFakeTranslate"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "1件目が出ない")

        var seenCount = 0
        var sawTranslatedPrefix = false
        for _ in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            let card = app.staticTexts["timeline.card.body"]
            // バグ1（同じ言語ペアの2件目で永久固着）が再発していれば、ここで確実にタイムアウトする。
            guard card.waitForExistence(timeout: 10)
                || app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 1) else {
                XCTFail("\(seenCount + 1)件目も読み切りも出ない（翻訳キューが固着した可能性）")
                break
            }
            guard card.exists else { break }
            XCTAssertFalse(card.label.contains(untranslatableMarker), "非対応言語の回答が表示された: \(card.label)")
            if card.label.hasPrefix("[") && card.label.contains("] ") {
                sawTranslatedPrefix = true
            }
            seenCount += 1
            app.buttons["timeline.next"].tap()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20),
            "読み切りに到達しない（固着した可能性）"
        )
        XCTAssertGreaterThan(seenCount, 0, "1件も表示されなかった")
        XCTAssertTrue(sawTranslatedPrefix, "疑似翻訳の接頭辞（[<言語コード>] ）を持つ回答が1件も無かった")
    }

    // MARK: 受け入れ条件5（お題も端末言語で表示される）＋ バグ3の確認

    /// 同梱シードのお題は日本語原文（`promptLanguage: "ja"`）。疑似翻訳モードでは
    /// 「準備中…」を経て、`promptDisplayText` が確定した表示になる
    /// （このシミュレータの言語設定次第で、原文のままか `[<言語コード>] ` 付きかは変わるが、
    /// いずれにせよ「準備中…」のまま固まらないことを確認する）。
    func test02_promptTranslationResolvesWithoutStalling() {
        let app = launch(arguments: ["-SameQFakeTranslate"], reset: true)
        completeOnboarding(app)

        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 10), "お題の表示が確定しない（準備中のまま固まった可能性）")
        XCTAssertFalse(app.otherElements["today.promptLoading"].exists, "確定後も準備中の表示が残っている")
        XCTAssertFalse(app.staticTexts["today.promptText"].label.isEmpty)
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
        app.buttons["onboarding.next"].tap()                    // ニックネーム（未入力のまま進む）
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
