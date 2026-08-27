import XCTest

/// スプリント15（F38 アプリUIの多言語表示）の受け入れ条件の自動検証。
///
/// evaluator の手作業を置き換えるものではないが、
/// - 端末言語 ja / en で起動したときの見出しの切替
/// - en 端末で ja の見出しが出ないこと
/// - fr 端末（en / ja 以外の端末言語）で en にフォールバックすること
/// を、起動引数 `-AppleLanguages (ja|en|fr)` で確認する。
final class SprintFifteenAcceptanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件1: ja 端末でコンセプト見出しが日本語

    /// 端末言語 ja で起動した直後のオンボーディング画面に、コンセプト見出しが
    /// 日本語で表示されていることを確認する（受け入れ条件3「日本語で表示」の逆）。
    func test01_jaTerminalShowsJapaneseConceptTitle() {
        let app = launch(languages: ["ja"])
        // コンセプト画面の見出しは `stepTitle("同じ問いに、\n答えるだけ。")` で
        // 改行を含む。`staticTexts` の `label` に直接ヒットさせにくいので、
        // 「同じ」「答える」片方の単語で見出しの存在を確認する。
        XCTAssertTrue(
            app.staticTexts["同じ問いに、\n答えるだけ。"].waitForExistence(timeout: 8),
            "ja 端末のコンセプト画面に日本語見出しが出ていない"
        )
    }

    // MARK: 受け入れ条件1: en 端末でコンセプト見出しが英語

    /// 端末言語 en で起動したとき、見出しが英文 "One question.\nOne answer." になり、
    /// 日本語の "同じ" "問い" "答える" が一切画面に出ていないことを確認する
    /// （受け入れ条件1 / 2）。
    func test02_enTerminalShowsEnglishConceptTitleAndNoJapanese() {
        let app = launch(languages: ["en"])

        XCTAssertTrue(
            app.staticTexts["One question.\nOne answer."].waitForExistence(timeout: 8),
            "en 端末のコンセプト画面に英語見出しが出ていない"
        )

        // 英語見出しが出ても、別の場所に日本語が残っていないことを確認する。
        // オンボーディング画面の「はじめる前に」「あなたの印を」「呼び名を」「お題が届いたら」
        // といった ja 専用のラベルが **en 端末では画面に出ていない** ことを確認する。
        let jaLabelsThatMustBeAbsent = [
            "はじめる前に",
            "あなたの印を",
            "呼び名を",
            "お題が届いたら",
            "同じ問いに、"
        ]
        for label in jaLabelsThatMustBeAbsent {
            XCTAssertFalse(
                app.staticTexts[label].exists,
                "en 端末の画面に日本語ラベル「\(label)」が残っている"
            )
        }
    }

    // MARK: 受け入れ条件2: en 端末でオンボーディングを進めると ja 文字列が残らない

    /// en 端末でオンボーディングを「あとで設定する」まで進め、今日のお題画面に到達。
    /// 画面にある主要ラベル（ロック表示・ボタン）がすべて英語であり、日本語が
    /// 一切残らないことを確認する（受け入れ条件2）。
    func test03_enTerminalOnboardingFlowHasNoJapanese() {
        let app = launch(languages: ["en"])

        // コンセプト
        XCTAssertTrue(app.staticTexts["One question.\nOne answer."].waitForExistence(timeout: 8))
        app.buttons["onboarding.next"].tap()

        // 規約 → agree → next
        XCTAssertTrue(app.staticTexts["I agree to the Terms of Use and Privacy Policy"].waitForExistence(timeout: 5))
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()

        // 絵文字
        XCTAssertTrue(app.staticTexts["Pick one mark\nthat's yours"].waitForExistence(timeout: 5))
        app.buttons["onboarding.emoji.🌙"].tap()
        app.buttons["onboarding.next"].tap()

        // ニックネーム
        XCTAssertTrue(app.staticTexts["Want a name\nto go with it?"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)

        // 通知
        XCTAssertTrue(app.staticTexts["We'll let you know\nwhen the prompt arrives"].waitForExistence(timeout: 5))
        app.buttons["onboarding.notification.later"].tap()

        // 今日のお題画面に到達し、ロック表示が英語になっていることを確認する。
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["The world is still hidden"].waitForExistence(timeout: 5),
            "en 端末のロック表示が英語になっていない"
        )

        // 日本語のラベルが残っていないこと（投稿ボタン・送信中・お題見出しも確認）。
        let jaLabelsThatMustBeAbsent = [
            "世界の回答はまだ見られません",
            "投稿する",
            "送信中…",
            "今日のお題",
            "同じ問いに、",
        ]
        for label in jaLabelsThatMustBeAbsent {
            XCTAssertFalse(
                app.staticTexts[label].exists,
                "en 端末の画面に日本語ラベル「\(label)」が残っている"
            )
        }
    }

    // MARK: 受け入れ条件4: fr 端末で英語にフォールバックする

    /// 端末言語 fr（日本語でも英語でもない）で起動したとき、
    /// アプリは英語 UI を出して、フランス語も英語も読めない内部記号も出さない
    /// ことを確認する（受け入れ条件4）。
    func test04_frTerminalFallsBackToEnglish() {
        let app = launch(languages: ["fr"])

        // 英語見出しが出る（＝fr では日本語UIにフォールバックしない）ことを確認。
        XCTAssertTrue(
            app.staticTexts["One question.\nOne answer."].waitForExistence(timeout: 8),
            "fr 端末のコンセプト画面に英語見出しが出ていない（=日本語へ誤フォールバック）"
        )

        // 同じ画面の ja 見出しは出ない。
        XCTAssertFalse(
            app.staticTexts["同じ問いに、\n答えるだけ。"].exists,
            "fr 端末で日本語見出しが出ている"
        )
    }

    // MARK: 受け入れ条件2: en 端末で設定画面の全ラベルが英語

    /// en 端末で設定画面を開き、すべての主要ラベルが英語になっていることを確認する
    /// （受け入れ条件2「設定画面までアプリの案内を一度も日本語に出会わずに使い切れる」）。
    func test05_enTerminalSettingsScreenAllLabelsAreEnglish() {
        let app = launch(languages: ["en"])

        // オンボーディング完了まで進める
        completeOnboarding(app)

        // 設定を開く
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 8))
        app.buttons["settings.open"].tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "en 端末で設定のナビゲーションタイトルが英語になっていない"
        )
        XCTAssertTrue(
            app.staticTexts["NOTIFICATIONS"].waitForExistence(timeout: 5),
            "en 端末で通知セクション見出しが英語になっていない"
        )
        XCTAssertTrue(
            app.staticTexts["BLOCKED PEOPLE"].waitForExistence(timeout: 5),
            "en 端末でブロックセクション見出しが英語になっていない"
        )
        XCTAssertTrue(
            app.staticTexts["You haven't blocked anyone"].waitForExistence(timeout: 5),
            "en 端末でブロック空状態の見出しが英語になっていない"
        )
        // 日本語の見出しが出ていないこと
        for label in ["通知", "ブロック中の人", "ブロックしている人はいません", "設定"] {
            XCTAssertFalse(
                app.staticTexts[label].exists,
                "en 端末の設定画面に日本語ラベル「\(label)」が残っている"
            )
        }
    }

    // MARK: 受け入れ条件2: en 端末でタイムライン画面が英語

    /// en 端末で投稿してからタイムラインを開き、上部見出し・空状態がすべて英語であることを確認。
    func test06_enTerminalTimelineLabelsAreEnglish() {
        let app = launch(languages: ["en"])

        completeOnboarding(app)
        submitAnswer(app, body: "Hello world")

        // 投稿直後に `AppSession` が自動でタイムラインを開く（attempt 6 の `pendingOpenTimelineTask`）
        // ため、ユーザーが明示的に `today.openTimeline` をタップする必要は無い。
        // ただし自動オープンが遅延する可能性も考慮し、最大10秒はボタンの出現を待つ。
        _ = app.buttons["today.openTimeline"].waitForExistence(timeout: 10)

        // タイムライン上部の見出し（"THE WORLD'S ANSWERS"）が英語であることを確認。
        // fullScreenCover が立ち上がるまで少し余裕を持たせる。
        XCTAssertTrue(
            app.staticTexts["THE WORLD'S ANSWERS"].waitForExistence(timeout: 15),
            "en 端末のタイムライン上部見出しが英語になっていない"
        )
        // スワイプで空状態 or 読み切りへ到達。
        var reachedEnd = false
        for _ in 0..<30 {
            if app.staticTexts["timeline.exhausted"].exists
                || app.staticTexts["timeline.empty"].exists
                || app.staticTexts["No new answers right now"].exists
                || app.staticTexts["No one has answered yet"].exists {
                reachedEnd = true
                break
            }
            app.swipeLeft()
        }
        XCTAssertTrue(reachedEnd, "タイムラインの終端状態（exhausted / empty）に到達できない")

        // 終端状態の文言が英語。
        let onScreen = app.staticTexts.allElementsBoundByIndex.map { $0.label }
        let hasEnglishEnd = onScreen.contains("No new answers right now")
            || onScreen.contains("No one has answered yet")
        XCTAssertTrue(hasEnglishEnd, "タイムライン終端の英語文言が見つからない: \(onScreen)")

        // 日本語の文言が出ていないこと。
        let jaLabelsThatMustBeAbsent = [
            "世界の回答",
            "世界の回答はまだ見られません",
            "スワイプすると、次の知らない誰かへ",
            "いいね",
            "今日は新しい回答がありません",
        ]
        for label in jaLabelsThatMustBeAbsent {
            XCTAssertFalse(
                app.staticTexts[label].exists,
                "en 端末のタイムラインに日本語ラベル「\(label)」が残っている"
            )
        }
    }

    // MARK: 受け入れ条件4: fr 端末で設定画面が英語

    /// fr 端末で設定画面を開いても、英語 UI が出ることを確認する
    /// （受け入れ条件4の補強）。
    func test07_frTerminalSettingsScreenIsEnglish() {
        let app = launch(languages: ["fr"])

        completeOnboarding(app)
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 8))
        app.buttons["settings.open"].tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 5),
            "fr 端末で設定のナビゲーションタイトルが英語になっていない"
        )
    }

    // MARK: 受け入れ条件2: ja 端末でオンボーディングが日本語

    /// ja 端末でオンボーディング画面のラベルが日本語のまま表示されることを確認
    /// （受け入れ条件3「日本語に戻すと、同じ画面がすべて日本語で表示される」）。
    func test08_jaTerminalOnboardingLabelsAreJapanese() {
        let app = launch(languages: ["ja"])

        // コンセプト
        XCTAssertTrue(app.staticTexts["同じ問いに、\n答えるだけ。"].waitForExistence(timeout: 8))
        app.buttons["onboarding.next"].tap()

        // 規約
        XCTAssertTrue(app.staticTexts["はじめる前に"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["利用規約とプライバシーポリシーに同意します"].waitForExistence(timeout: 5))
    }

    // MARK: ヘルパー

    /// `-AppleLanguages (<コード>)` を渡してアプリを起動する。
    private func launch(languages: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments: [String] = ["-SameQResetState", "-SameQUseLocalBackend"]
        for code in languages {
            launchArguments.append("-AppleLanguages")
            launchArguments.append("(\(code))")
        }
        app.launchArguments = launchArguments
        app.launch()
        return app
    }

    /// en / ja / fr いずれでも動くよう、表示文字列ではなく accessibilityIdentifier だけを使うオンボーディング。
    private func completeOnboarding(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
        app.buttons["onboarding.next"].tap()                    // コンセプト
        app.buttons["onboarding.terms.agree"].tap()
        app.buttons["onboarding.next"].tap()                    // 規約
        app.buttons["onboarding.emoji.🌙"].tap()
        app.buttons["onboarding.next"].tap()                    // 絵文字
        app.buttons["onboarding.next"].tap()                    // ニックネーム
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
        app.buttons["onboarding.notification.later"].tap()
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
        // 送信完了 → 自分の回答画面に切り替わる（`today.myAnswer` 識別子が立つ）
        XCTAssertTrue(app.staticTexts["today.myAnswer"].waitForExistence(timeout: 10))
    }
}
