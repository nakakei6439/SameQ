import XCTest

/// スプリント05の受け入れ条件（.product/spec.md 177〜183行）を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
final class SprintFiveAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "A cat looked at me like it knew something."

    /// 同梱シードに埋め込んだ、BANされた投稿者の回答に含まれる目印の文字列。
    /// これが画面に一度でも出たら不合格（F16）。
    private let bannedMarker = "BANされた投稿者のテスト投稿"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件1（1つのお題に投稿できるのは1回だけ）

    func test01_secondVisitToAnsweredPromptShowsAnswerNotComposer() {
        let app = launch(arguments: ["-SameQAnswerCount", "5"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        app.buttons["timeline.close"].tap()

        // お題画面へ戻っても入力欄は出ず、自分の回答が表示される
        XCTAssertTrue(app.staticTexts["today.myAnswer"].waitForExistence(timeout: 5), "自分の回答が表示されない")
        XCTAssertEqual(app.staticTexts["today.myAnswer"].label, answerBody)
        XCTAssertFalse(app.textViews["today.input"].exists, "投稿済みなのに入力欄が再表示された")
        XCTAssertTrue(app.buttons["today.openTimeline"].exists)

        // 再起動しても同じ
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["today.myAnswer"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textViews["today.input"].exists)
    }

    // MARK: 受け入れ条件2（空白・改行のみ、同一文字の過剰な繰り返しは拒否）

    /// 空白・改行のみと、同一文字の過剰な繰り返しを別々の入力として確かめる
    /// （書きかけを持ち越さないよう、シナリオの切れ目でアプリを開き直す）。
    func test02_blankAndRepeatedCharacterBodiesAreRejected() {
        let app = launch(arguments: ["-SameQAnswerCount", "5"], reset: true)
        completeOnboarding(app)

        // 空白・改行のみ：何か入力されている以上、送信ボタン自体は押せる
        // （ここで無効化すると拒否メッセージまで届かない。attempt 1 の evaluator 指摘）。
        // 拒否は `submitPost` 側の判定で行い、日英併記のメッセージを画面に出す。
        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("   \n\n  ")
        if app.buttons["today.doneEditing"].exists { app.buttons["today.doneEditing"].tap() }
        XCTAssertTrue(app.buttons["today.submit"].isEnabled, "何か入力されていれば送信ボタンは押せる（拒否はメッセージ側で行う）")
        app.buttons["today.submit"].tap()

        XCTAssertTrue(
            alertMessageContains(app, "空白や改行だけの回答は投稿できません"),
            "空白・改行のみを拒否する日本語メッセージが出ない"
        )
        XCTAssertTrue(
            alertMessageContains(app, "only blank space or line breaks"),
            "空白・改行のみを拒否する英語メッセージが出ない"
        )
        dismissAlert(app)
        // 拒否されているので投稿は進んでいない（入力欄がまだお題画面にある）
        XCTAssertTrue(app.textViews["today.input"].exists, "拒否されたのに投稿が進んでしまった")

        // 同一文字の過剰な繰り返し（新しい入力として確かめるため開き直す）
        app.terminate()
        app.launch()
        let freshEditor = app.textViews["today.input"]
        XCTAssertTrue(freshEditor.waitForExistence(timeout: 10))
        freshEditor.tap()
        for _ in 0..<15 {
            freshEditor.typeText("あ")
        }
        if app.buttons["today.doneEditing"].exists { app.buttons["today.doneEditing"].tap() }
        app.buttons["today.submit"].tap()

        XCTAssertTrue(
            alertMessageContains(app, "同じ文字を並べただけ"),
            "同一文字の繰り返しを拒否する日本語メッセージが出ない"
        )
        XCTAssertTrue(
            alertMessageContains(app, "same character repeated"),
            "同一文字の繰り返しを拒否する英語メッセージが出ない"
        )
        dismissAlert(app)

        // 制限メッセージのあとも操作を続けられる（操作不能にならない）。開き直して確かめる。
        app.terminate()
        app.launch()
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "制限のあと通常の投稿ができない")
    }

    // MARK: 受け入れ条件3（直近の自分の投稿と同一の本文を別のお題に投稿すると拒否）

    func test03_duplicateBodyOnNextPromptIsRejectedThenRecovers() {
        let expirySeconds = 20
        let gapSeconds = 15
        let app = launch(
            arguments: ["-SameQScenario", "expiring", "-SameQExpirySeconds", "\(expirySeconds)", "-SameQGapSeconds", "\(gapSeconds)"],
            reset: true
        )
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))

        // 終了時刻をまたいでお題待ちへ
        XCTAssertTrue(
            app.otherElements["waiting.root"].waitForExistence(timeout: Double(expirySeconds) + 30),
            "終了時刻を過ぎてもお題待ちにならない"
        )
        // 次のお題が始まる
        XCTAssertTrue(
            app.staticTexts["today.promptText"].waitForExistence(timeout: Double(gapSeconds) + 30),
            "次のお題が始まらない"
        )

        let editor = app.textViews["today.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(answerBody)
        if app.buttons["today.doneEditing"].exists { app.buttons["today.doneEditing"].tap() }
        app.buttons["today.submit"].tap()

        XCTAssertTrue(
            alertMessageContains(app, "直前の自分の投稿と同じ内容です"),
            "同一本文を拒否する日本語メッセージが出ない"
        )
        XCTAssertTrue(
            alertMessageContains(app, "identical to your previous post"),
            "同一本文を拒否する英語メッセージが出ない"
        )
        dismissAlert(app)

        // 制限のあとも操作可能（言葉を変えれば投稿できる＝操作不能にならない）
        editor.tap()
        editor.typeText(" changed")
        if app.buttons["today.doneEditing"].exists { app.buttons["today.doneEditing"].tap() }
        app.buttons["today.submit"].tap()
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "言葉を変えても投稿できない")
    }

    // MARK: 受け入れ条件4（いいねの連打制限）

    func test04_likeRateLimitBlocksThenRecovers() {
        let app = launch(
            arguments: ["-SameQAnswerCount", "5", "-SameQRateLimitTestMode"],
            reset: true
        )
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        let likeButton = app.buttons["timeline.like"]
        XCTAssertTrue(likeButton.waitForExistence(timeout: 8))

        // テストモードでは3回まで許可（RateLimitSettings(maxActions: 3, window: 30, cooldown: 8)）
        for _ in 1...3 { likeButton.tap() }
        let selectedBeforeLimit = likeButton.isSelected
        likeButton.tap() // 4回目は制限される

        XCTAssertTrue(alertMessageContains(app, "いいねが短時間に多すぎます"), "いいねの制限メッセージ（日本語）が出ない")
        XCTAssertTrue(alertMessageContains(app, "Likes too fast"), "いいねの制限メッセージ（英語）が出ない")
        dismissAlert(app)
        XCTAssertEqual(likeButton.isSelected, selectedBeforeLimit, "制限された操作の見た目が反映されてしまった")

        // 操作不能にならない：他の操作は普通に使える
        XCTAssertTrue(app.buttons["timeline.next"].isEnabled)
        app.buttons["timeline.next"].tap()
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8), "制限のあと操作を続けられない")

        // クールダウンが明けると再びいいねできる（復帰できることの確認）
        Thread.sleep(forTimeInterval: 9)
        app.buttons["timeline.like"].tap()
        XCTAssertTrue(app.buttons["timeline.like"].isSelected, "クールダウン後にいいねできない")
    }

    // MARK: 受け入れ条件4（通報の連打制限）

    func test05_reportRateLimitBlocksThenShowsMessage() {
        let app = launch(
            arguments: ["-SameQAnswerCount", "10", "-SameQRateLimitTestMode"],
            reset: true
        )
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))

        // テストモードでは2回まで許可（RateLimitSettings(maxActions: 2, window: 40, cooldown: 8)）
        XCTAssertTrue(report(app), "1回目の通報が成功しない")
        XCTAssertTrue(report(app), "2回目の通報が成功しない")
        XCTAssertFalse(report(app), "3回目の通報が制限されない")

        XCTAssertTrue(alertMessageContains(app, "通報が短時間に多すぎます"), "通報の制限メッセージ（日本語）が出ない")
        XCTAssertTrue(alertMessageContains(app, "Reports too fast"), "通報の制限メッセージ（英語）が出ない")
        dismissAlert(app)

        // 操作不能にならない：タイムラインの操作は続けられる
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["timeline.next"].isEnabled)
    }

    // MARK: 受け入れ条件5（BAN状態のアカウントは今日のお題にもタイムラインにも入れない）

    func test06_bannedAccountSeesOnlyBannedScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-SameQBanned", "-SameQResetState"]
        app.launch()

        XCTAssertTrue(app.otherElements["banned.root"].waitForExistence(timeout: 8), "BAN画面が出ない")
        XCTAssertTrue(app.staticTexts["banned.title"].exists, "日本語の文言が無い")
        XCTAssertTrue(app.staticTexts["banned.titleEnglish"].exists, "英語の文言が無い")
        XCTAssertFalse(app.buttons["onboarding.next"].exists, "初回設定に入れてしまう")
        XCTAssertFalse(app.staticTexts["today.promptText"].exists, "今日のお題に入れてしまう")
        XCTAssertFalse(app.otherElements["waiting.root"].exists, "お題待ちに入れてしまう")
        XCTAssertFalse(app.staticTexts["timeline.card.body"].exists, "タイムラインに入れてしまう")

        // BAN状態を外して起動し直すと通常どおり使える（運営の解除に相当する模擬操作）
        app.terminate()
        let recovered = XCUIApplication()
        recovered.launchArguments = ["-SameQScenario", "live"]
        recovered.launch()
        XCTAssertTrue(recovered.buttons["onboarding.next"].waitForExistence(timeout: 8), "BANを外しても復帰できない")
    }

    // MARK: 受け入れ条件6（BANされたユーザーの回答は他ユーザーのタイムラインに表示されない）

    func test07_bannedAuthorsPostNeverAppearsInDefaultSeed() {
        // 引数なし（同梱シードそのまま）。SeedData.json に混ぜたBAN済み投稿者の回答が
        // 22件を読み切るまで一度も出ないことを確かめる。
        let app = launch(arguments: [], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        for step in 1...22 {
            let card = app.staticTexts["timeline.card.body"]
            XCTAssertTrue(card.waitForExistence(timeout: 8), "\(step)件目が出ない")
            XCTAssertFalse(card.label.contains(bannedMarker), "BANされた投稿者の回答が表示された: \(card.label)")
            app.buttons["timeline.next"].tap()
        }
        XCTAssertTrue(app.staticTexts["timeline.exhausted"].waitForExistence(timeout: 8), "読み切りに到達しない")
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

    /// いま出ている回答を1件通報する。成功したら完了表示を閉じて `true`。
    /// 連打制限で拒否された場合はシートが自動的に閉じるので `false` を返す。
    /// シートが完全に閉じきるまで待ってから返すので、連続で呼んでも前回の名残を拾わない。
    @discardableResult
    private func report(_ app: XCUIApplication, reason: String = "discrimination") -> Bool {
        XCTAssertTrue(app.buttons["timeline.more"].waitForExistence(timeout: 5))
        app.buttons["timeline.more"].tap()
        guard app.buttons["safety.report"].waitForExistence(timeout: 5) else { return false }
        app.buttons["safety.report"].tap()
        guard app.buttons["safety.reason.\(reason)"].waitForExistence(timeout: 5) else { return false }
        app.buttons["safety.reason.\(reason)"].tap()
        app.buttons["safety.reportSubmit"].tap()
        if app.staticTexts["safety.reportDone"].waitForExistence(timeout: 5) {
            app.buttons["safety.close"].tap()
            _ = app.staticTexts["safety.reportDone"].waitForNonExistence(timeout: 5)
            return true
        }
        // 制限された場合はシートが自動的に閉じる。完全に閉じきるまで待つ。
        _ = app.buttons["safety.reportSubmit"].waitForNonExistence(timeout: 5)
        return false
    }

    /// 表示中のアラートに、指定した部分文字列を含む文言があるかを見る
    /// （日本語行・英語行のどちらも同じ文字列に入っているので、部分一致で拾える）。
    private func alertMessageContains(_ app: XCUIApplication, _ substring: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", substring)
        return app.staticTexts.element(matching: predicate).waitForExistence(timeout: 5)
    }

    private func dismissAlert(_ app: XCUIApplication) {
        let ok = app.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: 5) {
            ok.tap()
        }
    }
}
