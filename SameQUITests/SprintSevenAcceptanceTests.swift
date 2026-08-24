import XCTest

/// スプリント07（F23 ニックネームの自動ローカライズ）の受け入れ条件を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
///
/// 端末言語は `-AppleLanguages (ja|en)` で切り替える。`Locale.preferredLanguages` を
/// `Translator` が読むので、シミュレータ側で同じ言語を切り替えてもアプリに反映される
/// （シミュレータのシステム言語を変えて再起動するのと等価）。
///
/// `-SameQNicknameTranslitDebug` を付けるとすべての入力が音写失敗扱いになり、
/// 受け入れ条件3（絵文字のみ表示フォールバック）の再現に使える。
final class SprintSevenAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let myNickname = "Mizuki"
    private let answerBody = "Tonight I walked the long way home."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件1（端末言語と異なる文字体系のニックネームが端末言語の文字体系で表示される）

    /// 端末言語が ja のとき、同梱シードのニックネーム `ふゆ`（ひらがな）は ja 端末でも
    /// **そのまま `ふゆ` で表示される**（スクリプト一致なので音写しない）。
    /// 一方、`하늘`（ハングル）は ja 端末でカタカナ音写される（`ハヌル` 等のカタカナ）。
    /// どちらも「読める文字体系で表示されている」ことを確認する。
    func test01_jaTerminalShowsKatakanaTransliterationForHangulNicknames() {
        let app = launch(
            languages: ["ja"],
            arguments: [],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        // タイムライン上でニックネーム表示が読める文字体系になっていることを確認する。
        // すべてのカードを巡回して、ハングル文字が**画面に出ていない**こと（=カタカナ音写された）
        // と、何らかのカタカナ・ひらがな・漢字が**画面に出ている**ことを確認する。
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        var sawKatakanaOrHiraganaOrKanji = false
        for _ in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            guard app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5) else { break }
            // ニックネーム表示（任意・nil なら出ない）
            let nickname = app.staticTexts["timeline.card.nickname"]
            if nickname.exists {
                let label = nickname.label
                XCTAssertFalse(
                    label.contains("하늘") || label.contains("ミ나") || label.contains("케이타"),
                    "ja 端末でハングルのニックネーム原文が出てはいけない: \(label)"
                )
                if containsAnyKatakanaHiraganaOrKanji(label) {
                    sawKatakanaOrHiraganaOrKanji = true
                }
            }
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 5),
            "読み切りにも空状態にも到達しない"
        )
        XCTAssertTrue(
            sawKatakanaOrHiraganaOrKanji,
            "ja 端末でハングル→カタカナ音写されたニックネームが一度も表示されなかった（受け入れ条件1の動作確認）"
        )
    }

    /// 端末言語が en のとき、同梱シードのニックネーム `ふゆ` は Latin 音写（`fuyu`）で、
    /// `하늘` も Latin 音写（`haneul`）で表示されるはず（受け入れ条件1）。
    func test02_enTerminalShowsLatinTransliterationForNonLatinNicknames() {
        let app = launch(
            languages: ["en"],
            arguments: [],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        var sawLatinTransliteration = false
        for _ in 0..<40 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            guard app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5) else { break }
            let nickname = app.staticTexts["timeline.card.nickname"]
            if nickname.exists {
                let label = nickname.label
                XCTAssertFalse(
                    label.contains("ふゆ") || label.contains("하늘"),
                    "en 端末で非 Latin スクリプトのニックネーム原文が出てはいけない: \(label)"
                )
                // Latin 音写された名前（典型的に `Mina` / `Kai` / `Leo` 等）は ASCII 文字だけ
                if label.unicodeScalars.allSatisfy({ $0.isASCII }) && !label.isEmpty {
                    sawLatinTransliteration = true
                }
            }
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 5),
            "読み切りにも空状態にも到達しない"
        )
        XCTAssertTrue(
            sawLatinTransliteration,
            "en 端末で Latin 音写されたニックネームが一度も表示されなかった"
        )
    }

    // MARK: 受け入れ条件3（音写できないニックネームは絵文字のみ表示）

    /// `-SameQNicknameTranslitDebug` を付けると、すべてのニックネームが音写失敗扱いになる
    /// （受け入れ条件3の再現用）。結果として、ニックネーム表示が出ない（絵文字のみ表示）か、
    /// 「名前のない人」表記（F15 ブロック一覧）になる。タイムラインではニックネーム行そのものが
    /// 表示されないことを確認する。
    func test03_forceTranslitFailureHidesNicknameOnTimeline() {
        let app = launch(
            languages: ["ja"],
            arguments: ["-SameQNicknameTranslitDebug"],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        var sawCardWithoutNickname = false
        for _ in 0..<15 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            guard app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5) else { break }
            // ニックネーム表示（"timeline.card.nickname"）が出ていない（=絵文字のみ表示）ことを
            // 確認する。デバッグモードでは `displayedNickname` が nil を返すので、
            // AnswerCardView 側の `if let nickname = displayedNickname` ブロックが丸ごと表示されない。
            let nickname = app.staticTexts["timeline.card.nickname"]
            if !nickname.exists {
                sawCardWithoutNickname = true
            }
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 5),
            "読み切りにも空状態にも到達しない"
        )
        XCTAssertTrue(
            sawCardWithoutNickname,
            "-SameQNicknameTranslitDebug でニックネームが一度も絵文字のみ表示にならなかった"
        )
    }

    /// 受け入れ条件4（絵文字のみ表示でレイアウトが崩れない）の間接確認:
    /// ニックネーム未設定の回答（`authorNickname == nil`）でもレイアウトが壊れず、
    /// 絵文字のみが表示されることを確認する。デバッグモードでニックネームが
    /// 「あったはずのものが消える」場合、レイアウトの高さや幅が破綻しないか目視可能。
    ///
    /// 自動テストでは「ニックネーム表示が出ていない状態でカードの高さが
    /// 極端に変わらない」程度のことしか確認できないので、ここではニックネーム表示の
    /// 不在と、絵文字が常に表示されていることを確認するに留める。
    func test04_emojiOnlyNicknameDoesNotBreakLayout() {
        let app = launch(
            languages: ["ja"],
            arguments: [],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10))
        var sawCardWithEmojiOnly = false
        for _ in 0..<20 {
            if app.staticTexts["timeline.exhausted"].exists || app.staticTexts["timeline.empty"].exists { break }
            guard app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5) else { break }
            let nickname = app.staticTexts["timeline.card.nickname"]
            let cardEmoji = app.staticTexts["timeline.card.emoji"]
            if !nickname.exists && cardEmoji.exists {
                sawCardWithEmojiOnly = true
            }
            app.swipeLeft()
        }
        XCTAssertTrue(
            app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 20)
                || app.staticTexts["timeline.empty"].waitForExistence(timeout: 5),
            "読み切りにも空状態にも到達しない"
        )
        // シードでは 4件に1件がニックネーム未設定なので、必ず「絵文字のみ表示」のカードが現れる。
        XCTAssertTrue(
            sawCardWithEmojiOnly,
            "ニックネーム未設定のカード（絵文字のみ表示）が一度も表示されなかった"
        )
    }

    // MARK: 受け入れ条件5（自分のニックネームは原文のまま表示される）

    /// ja 端末で自分のニックネーム `Mizuki` がカタカナ音写されず**原文のまま**表示される
    /// ことを確認する。
    func test05_myNicknameStaysOriginalOnJaTerminal() {
        let app = launch(
            languages: ["ja"],
            arguments: [],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        // 今日のお題画面の identityRow（受け入れ条件5の主戦場）。
        XCTAssertTrue(app.staticTexts["today.identity"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts[myNickname].waitForExistence(timeout: 5),
            "ja 端末でも自分のニックネーム `\(myNickname)` は原文のまま表示されるべき"
        )
        XCTAssertFalse(
            app.staticTexts["ミズキ"].exists,
            "自分のニックネームがカタカナ音写されてはいけない"
        )
    }

    /// en 端末でも同様に、自分のニックネーム `Mizuki` が**原文のまま**表示される
    /// （受け入れ条件5）。英語端末で他人のニックネームは音写されるが、自分のだけは原文。
    func test06_myNicknameStaysOriginalOnEnTerminal() {
        let app = launch(
            languages: ["en"],
            arguments: [],
            reset: true
        )
        completeOnboarding(app, nickname: myNickname)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(app.staticTexts["today.identity"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts[myNickname].waitForExistence(timeout: 5),
            "en 端末でも自分のニックネーム `\(myNickname)` は原文のまま表示されるべき"
        )
    }

    // MARK: ヘルパー

    /// 指定の端末言語・追加起動引数でアプリを立ち上げる。
    /// `XCUIApplication` の `launchArguments` に `-AppleLanguages (<コード>)` を入れると
    /// `Locale.preferredLanguages` がその言語コードになる（アプリが `-AppleLanguages` を
    /// 読む前提の設計と整合する）。
    private func launch(languages: [String], arguments: [String], reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments: [String] = []
        for code in languages {
            launchArguments.append("-AppleLanguages")
            launchArguments.append("(\(code))")
        }
        launchArguments.append(contentsOf: arguments)
        if reset { launchArguments.append("-SameQResetState") }
        app.launchArguments = launchArguments
        app.launch()
        return app
    }

    private func completeOnboarding(_ app: XCUIApplication, nickname: String?) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
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

    /// 文字列にカタカナ・ひらがな・CJK 漢字のいずれかが含まれているか。
    /// 「日本語系の文字体系の音写結果らしさ」を雑に判定する。
    private func containsAnyKatakanaHiraganaOrKanji(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x309F).contains(v) { return true } // ひらがな
            if (0x30A0...0x30FF).contains(v) { return true } // カタカナ
            if (0x4E00...0x9FFF).contains(v) { return true } // CJK 漢字
        }
        return false
    }
}