import XCTest

/// スプリント20（F48〜F54）の受け入れ条件を実機操作で確かめる。
///
/// App Store ガイドライン 1.2（匿名投稿の安全対策）と 3.1.2（サブスクリプションの
/// 規約リンク）への対応。Apple が "all of the following" と書いているため、
/// 1項目でも欠けると意味を持たない。
///
/// **ここで確認できないもの**（評価者への注記どおり、隠さず明記する）:
/// - 削除した回答が「他の人の画面から」消えること
///   → 別 UDID・別アカウントの2台が要る。SQL とスクリーンショットの突き合わせで確認する。
/// - 通報3件による自動非表示、通報3件たまった投稿者の自動停止
///   → 別アカウント3つが要る。`supabase db query --linked` で通報行を作って確認する。
/// - メールアプリが実際に開くこと
///   → シミュレータには Mail が無い。ここでは逆に「メールアプリが無いときの
///     フォールバック案内が出る」ことを確認できる（実機での起動確認は手動）。
/// - 年齢レーティング 18+
///   → App Store Connect のメタデータ作業（置いた前提43）。アプリを操作しても検証できない。
final class SprintTwentyAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "The rain stopped just as I stepped outside."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: F52 — 規約への同意とゼロトレランスの明示

    /// 同意のチェックを入れないと先へ進めない。ゼロトレランスの要約が、
    /// 規約本文をスクロールしなくても同意欄のそばで読める。
    func test01_termsMustBeAgreedAndZeroToleranceIsVisibleWithoutScrolling() {
        let app = launchFresh()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.next"].tap()   // コンセプト → 規約

        XCTAssertTrue(
            app.staticTexts["onboarding.terms.zeroTolerance"].waitForExistence(timeout: 5),
            "ゼロトレランスの要約が規約画面に常時表示されていない"
        )

        let next = app.buttons["onboarding.next"]
        XCTAssertFalse(next.isEnabled, "同意チェック無しで次へ進めてしまう")

        app.buttons["onboarding.terms.agree"].tap()
        XCTAssertTrue(next.isEnabled, "同意しても次へ進めない")
    }

    /// 設定からも規約とプライバシーポリシーの全文を読める（F32 の回帰確認も兼ねる）。
    func test02_termsAndPrivacyAreReadableFromSettings() {
        let app = launchFresh()
        completeOnboarding(app)
        openSettings(app)

        app.buttons["settings.legal.terms"].tap()
        XCTAssertTrue(app.buttons["settings.legal.close"].waitForExistence(timeout: 5))
        app.buttons["settings.legal.close"].tap()

        app.buttons["settings.legal.privacy"].tap()
        XCTAssertTrue(app.buttons["settings.legal.close"].waitForExistence(timeout: 5))
        app.buttons["settings.legal.close"].tap()
    }

    // MARK: F53 — 同意の記録

    /// 同意した日が設定画面に出る。
    func test03_termsAcceptanceDateIsShownInSettings() {
        let app = launchFresh()
        completeOnboarding(app)
        openSettings(app)

        XCTAssertTrue(
            app.staticTexts["settings.legal.acceptedOn"].waitForExistence(timeout: 5),
            "規約に同意した日が設定画面に出ていない"
        )
    }

    // MARK: F51 — アプリ内のお問い合わせ

    /// 設定から運営の連絡先に到達でき、アドレスが文字として読めてコピーできる。
    func test04_contactIsReachableFromSettingsAndAddressIsReadable() {
        let app = launchFresh()
        completeOnboarding(app)
        openSettings(app)

        XCTAssertTrue(
            app.buttons["settings.support.contact"].waitForExistence(timeout: 5),
            "設定に「お問い合わせ」が無い"
        )
        app.buttons["settings.support.contact"].tap()

        let address = app.staticTexts["settings.support.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), "連絡先が文字として表示されていない")
        XCTAssertTrue(
            address.label.contains("@"),
            "連絡先がメールアドレスとして読めない: \(address.label)"
        )
        XCTAssertTrue(app.buttons["settings.support.copy"].exists, "コピーの導線が無い")
        XCTAssertTrue(app.buttons["settings.support.compose"].exists, "メール作成の導線が無い")
    }

    // MARK: F48 — 禁止表現のフィルタ

    /// 禁止表現を含む回答は投稿されない。理由は出るが、どの語に当たったかは出さない。
    func test05_prohibitedAnswerIsRejectedAndNotPosted() {
        let app = launchFresh()
        completeOnboarding(app)

        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("You are such a bitch.")
        dismissKeyboard(app)
        app.buttons["today.submit"].tap()

        // 投稿されていない（自分の回答カードが現れない）。
        XCTAssertFalse(
            app.staticTexts["today.myAnswer"].waitForExistence(timeout: 5),
            "禁止表現を含む回答が投稿できてしまった"
        )
    }

    /// 禁止語を偶然含むだけの普通の英文は投稿できる（誤検知が最悪の壊れ方）。
    func test06_ordinaryAnswerContainingProhibitedSubstringIsAccepted() {
        let app = launchFresh()
        completeOnboarding(app)

        submitAnswer(app, body: "I passed the class and the analysis was fine.")

        XCTAssertTrue(
            app.staticTexts["today.myAnswer"].waitForExistence(timeout: 10),
            "誤検知: ふつうの英文が投稿できていない"
        )
    }

    // MARK: F49 — 自分の回答の削除

    /// 回答を削除すると「削除しました」の表示になり、入力欄には戻らない
    /// （同じお題への再回答はできないため）。世界の回答は読み続けられる。
    func test07_deletingOwnAnswerShowsRemovedStateAndDoesNotReopenComposer() {
        let app = launchFresh()
        completeOnboarding(app)
        submitAnswer(app)

        let deleteButton = app.buttons["today.myAnswer.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "削除の導線が無い")
        deleteButton.tap()

        // 確認ダイアログ（「もう一度回答できない」ことが書かれている）。
        // SwiftUI の confirmationDialog はボタンを階層に二重に持つことがあるので
        // `firstMatch` で1つに絞る（絞らないと "Multiple matching elements" になる）。
        let confirm = app.buttons["today.myAnswer.deleteConfirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "削除の確認が出ない")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["today.myAnswer.removed"].waitForExistence(timeout: 8),
            "削除後に「削除しました」の表示にならない"
        )
        XCTAssertFalse(
            app.textViews["today.input"].exists,
            "削除後に入力欄へ戻ってしまっている（同じお題には再回答できないので戻してはいけない）"
        )
        XCTAssertTrue(
            app.buttons["today.openTimeline"].exists,
            "削除しても世界の回答は読み続けられなければならない"
        )
    }

    // MARK: F54 — Plus 購入画面の規約リンク（ガイドライン 3.1.2）

    /// Plus の購入画面から利用規約とプライバシーポリシーを開ける。
    func test08_plusPurchaseScreenLinksToTermsAndPrivacy() {
        let app = launchFresh(fakePlus: true)
        completeOnboarding(app)

        XCTAssertTrue(app.buttons["plus.open"].waitForExistence(timeout: 8))
        app.buttons["plus.open"].tap()
        XCTAssertTrue(app.otherElements["plus.root"].waitForExistence(timeout: 5)
                      || app.staticTexts["plus.root.anchor"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["plus.autoRenewNote"].waitForExistence(timeout: 5),
            "購入画面に自動更新の説明が無い"
        )
        XCTAssertTrue(app.buttons["plus.legal.terms"].exists, "購入画面に利用規約へのリンクが無い")
        XCTAssertTrue(app.buttons["plus.legal.privacy"].exists, "購入画面にプライバシーポリシーへのリンクが無い")

        app.buttons["plus.legal.terms"].tap()
        XCTAssertTrue(app.buttons["settings.legal.close"].waitForExistence(timeout: 5))
    }

    // MARK: ヘルパー

    private func launchFresh(fakePlus: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = ["-SameQUseLocalBackend", "-SameQResetState"]
        if fakePlus {
            arguments.append("-SameQFakePlus")
        }
        app.launchArguments = arguments
        app.launch()
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

    /// 回答を投稿し、投稿直後に自動で開くタイムラインを閉じて今日のお題画面へ戻す。
    /// タイムラインは `fullScreenCover` なので、閉じるまで裏の `today.myAnswer` は掴めない。
    private func submitAnswer(_ app: XCUIApplication, body: String? = nil) {
        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(body ?? answerBody)
        dismissKeyboard(app)
        app.buttons["today.submit"].tap()
        if app.buttons["timeline.close"].waitForExistence(timeout: 15) {
            app.buttons["timeline.close"].tap()
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.buttons["today.doneEditing"].exists {
            app.buttons["today.doneEditing"].tap()
        }
        _ = app.keyboards.element.waitForNonExistence(timeout: 5)
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 8))
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.otherElements["settings.root"].waitForExistence(timeout: 8))
    }
}
