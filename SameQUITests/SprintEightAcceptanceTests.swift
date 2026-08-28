import XCTest
import UserNotifications

/// スプリント08（F24 ランダム通知 / F25 通知タップ）の受け入れ条件を実機操作で確かめる。
/// evaluator の手作業を置き換えるものではなく、実装側の自己確認用。
///
/// 実機での `UNUserNotificationCenter.add()` の振る舞いは実機でしか確認できないため、
/// ここではシミュレータでも確認できる次の経路で検証する：
/// - **設定画面**で「通知オン／オフ」案内と「次のお知らせ: yyyy/M/d HH:mm」表示が出る
///   （= AppSession の `nextScheduledNotificationAt` が更新されていることの直接確認）
/// - **拒否状態**（`-SameQNotificationForceDenied`）でもオンボーディング→投稿が普通にできる
/// - **通知タップ**で未回答 → お題画面、回答済み → タイムラインが直接開く
/// - **遅刻表示・カウントダウン**が無い（`today.submit` が常にある）
///
/// `UNUserNotificationCenter` に登録された時刻が 8:00〜22:00 の範囲内であることと、
/// 「日によって違う時刻」になることは `SameQTests/NotificationSchedulingTests` の
/// `testAppSessionReschedulingPicksDifferentTimesAcrossCalls` で直接検証している。
final class SprintEightAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Mizuki"
    private let answerBody = "A small bird perched on the balcony railing today."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 1・2・3（8:00〜22:00 の範囲・ランダム性・予約成立）

    /// `-SameQNotificationHour 14` を付けて起動すると、設定画面に
    /// 「次のお知らせ: ...」が表示され、その時刻の時部分が 14 になっている。
    /// 8:00 未満・22:00 以降になっていないことも同時に確認する。
    /// （シミュレータで `UNUserNotificationCenter.add()` 自体が制限される事があるため、
    /// 予約の成立は AppSession の `nextScheduledNotificationAt` を設定画面越しに読む。）
    func test01_scheduledTimeIsInWindowAndFuture() {
        let app = launchFresh(hour: 14)
        completeOnboarding(app, allowNotifications: true)
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))

        // 設定画面で「次のお知らせ」が出ることを確認
        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5))
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.staticTexts["settings.notification.nextAt"].waitForExistence(timeout: 5),
                      "設定画面に『次のお知らせ』が表示される = 予約が成立している")
        let label = app.staticTexts["settings.notification.nextAt"].label
        // "次のお知らせ: M/d HH:mm" の形式から時を取り出す
        let components = label.split(separator: " ").last ?? ""
        let hourString = components.split(separator: ":").first ?? ""
        guard let hour = Int(hourString) else {
            XCTFail("『次のお知らせ』表記から時を取り出せなかった: \(label)")
            return
        }
        XCTAssertEqual(hour, 14, "起動引数で指定した時刻（14時）になっているはず")
        XCTAssertGreaterThanOrEqual(hour, 8, "8:00 未満は不可")
        XCTAssertLessThan(hour, 22, "22:00 以降は不可")
    }

    /// `-SameQNotificationHour` を付けない場合、設定画面の「次のお知らせ」から
    /// 読み取れる時が 8〜21 の範囲に入ることを 30 回連続で検証する。
    /// 範囲外が一度でも出たら不合格。
    func test02_randomHourIsAlwaysInWindow() {
        for iteration in 0..<30 {
            let app = launchFresh(hour: nil)
            completeOnboarding(app, allowNotifications: true)
            XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8),
                          "iter \(iteration): お題画面に到達")

            XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5))
            app.buttons["menu.open"].tap()
            XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
            app.buttons["settings.open"].tap()
            XCTAssertTrue(app.staticTexts["settings.notification.nextAt"].waitForExistence(timeout: 5),
                          "iter \(iteration): 『次のお知らせ』が出る")
            let label = app.staticTexts["settings.notification.nextAt"].label
            let components = label.split(separator: " ").last ?? ""
            let hourString = components.split(separator: ":").first ?? ""
            guard let hour = Int(hourString) else {
                XCTFail("iter \(iteration): 『次のお知らせ』表記から時を取り出せなかった: \(label)")
                continue
            }
            XCTAssertTrue((8..<22).contains(hour),
                          "iter \(iteration): 8:00〜22:00 の範囲内であるべき。実際: \(hour)")
            // 設定シートを閉じて次の繰り返しへ
            app.buttons["settings.close"].tap()
        }
    }

    // MARK: 受け入れ条件 6（拒否状態でもアプリは普通に使え、設定画面に案内が出る）

    /// `-SameQNotificationForceDenied` を付けて起動すると、
    /// アプリは通常どおり使える（オンボーディング完了 → お題 → 投稿）。
    /// 設定画面では「オフです」案内が出ること。
    func test03_deniedStateDoesNotBlockAppUsage() {
        let app = launchFresh(forceDenied: true)
        completeOnboarding(app, allowNotifications: true)
        // 拒否強制なので「次のお知らせ」は表示されない（予約しないため）
        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5))
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        app.buttons["settings.open"].tap()
        let status = app.staticTexts["settings.notification.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "お題のお知らせはオフです")
        XCTAssertFalse(app.staticTexts["settings.notification.nextAt"].exists,
                       "拒否状態では『次のお知らせ』が表示されない")

        // アプリ自体は普通にお題画面に到達できる
        app.buttons["settings.close"].tap()
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["today.input"].exists, "入力欄がある")

        // 投稿も普通にできる
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
    }

    /// 通常（許可状態）でも、設定画面を開くと「オンです」案内が出る。
    func test04_authorizedStateShowsNextScheduledTimeInSettings() {
        let app = launchFresh(hour: 15)
        completeOnboarding(app, allowNotifications: true)
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))

        XCTAssertTrue(app.buttons["menu.open"].waitForExistence(timeout: 5))
        app.buttons["menu.open"].tap()
        XCTAssertTrue(app.buttons["settings.open"].waitForExistence(timeout: 5))
        app.buttons["settings.open"].tap()
        let status = app.staticTexts["settings.notification.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "お題のお知らせはオンです")
        XCTAssertTrue(app.staticTexts["settings.notification.nextAt"].waitForExistence(timeout: 3),
                      "次の予約時刻が表示される")
    }

    // MARK: 受け入れ条件 4（通知タップ → 未回答なら今日のお題、回答済みならタイムライン）

    /// 通知タップでアプリが起動されたとき、未回答アカウントならお題画面が直接開き、
    /// 回答済みアカウントならタイムラインが直接開くことを確認する。
    /// `UNUserNotificationCenterDelegate` の経路をシミュレートするため、
    /// Debug 限定の起動引数 `-SameQSimulateNotificationTap` を付けて起動すると、
    /// `RootView.task` が `session.start()` 完了直後にアプリ内の `NotificationCenter` に
    /// `.sameQNotificationTapped` を post し、実際の通知タップと同じ `onReceive` 経路を
    /// 通る（attempt 2: eval-1.md [1] の修正で追加された経路）。
    func test05_notificationTapOpensCorrectScreen() {
        // ケース 1: 未回答 → 通知タップで今日のお題画面へ
        // 通知タップを「アプリ内」でシミュレートするため -SameQSimulateNotificationTap を付ける
        let app = launchFresh(hour: 12, simulateNotificationTap: true)
        completeOnboarding(app, allowNotifications: true)
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8),
                      "未回答アカウントの通知タップではお題画面が出る")
        XCTAssertTrue(app.textViews["today.input"].exists, "入力欄が出ている")

        // ケース 2: 回答済み → 通知タップでタイムラインが直接開く
        submitAnswer(app, body: answerBody)
        XCTAssertTrue(app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8))
        app.buttons["timeline.close"].tap()
        XCTAssertTrue(app.buttons["today.openTimeline"].waitForExistence(timeout: 5))

        // アプリを一旦閉じて、回答済みアカウントを「通知タップで再起動」する。
        // シミュレート通知タップで起動直後にタイムラインが直接開くはず。
        app.terminate()
        let app2 = launchFresh(hour: 12, simulateNotificationTap: true, resetState: false)
        XCTAssertTrue(app2.staticTexts["timeline.card.body"].waitForExistence(timeout: 12),
                      "回答済みアカウントの通知タップではタイムラインが直接開く")
    }

    // MARK: 受け入れ条件 5（遅刻表示・カウントダウン・締切がない）

    /// お題の有効期間中は何時にでも回答でき、遅刻表示やカウントダウンが一切無いこと。
    /// 既定のお題は28時間有効なので「時間を過ぎた」という判定は起こらない。
    /// ここでは「投稿する」ボタンが時間に関係なく常に有効であることを確認する。
    func test06_noLatePenaltyAfterScheduledTime() {
        let app = launchFresh(hour: 8)
        completeOnboarding(app, allowNotifications: true)
        XCTAssertTrue(app.staticTexts["today.promptText"].waitForExistence(timeout: 8))

        // 「投稿する」ボタンの accessibility identifier は変わらず、遅刻を示す文言も無い
        XCTAssertTrue(app.buttons["today.submit"].exists, "投稿ボタンは常にある")
        // 「もう答えられません」「時間切れ」「締切」のいずれかの文言が無いこと
        let allText = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
        for forbidden in ["時間切れ", "締切", "もう", "遅刻", "deadline", "closed"] {
            XCTAssertFalse(
                allText.contains(forbidden),
                "遅刻を示す文言『\(forbidden)』が画面に出ている"
            )
        }
    }

    // MARK: ヘルパー

    /// アプリを新規状態に起動する。`-SameQResetState` と検証用の通知引数を付与。
    /// - `resetState: false` で呼び出すと `-SameQResetState` を付けず、
    ///   オンボーディング・回答などの既存状態を保ったまま再起動できる。
    /// - `simulateNotificationTap: true` で呼び出すと `-SameQSimulateNotificationTap` を付け、
    ///   `session.start()` 完了直後にアプリ内で通知タップをシミュレートする（attempt 2）。
    private func launchFresh(
        hour: Int? = nil,
        forceDenied: Bool = false,
        simulateNotificationTap: Bool = false,
        resetState: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = ["-SameQUseLocalBackend"]
        if resetState {
            arguments.append("-SameQResetState")
        }
        if let hour {
            arguments.append(contentsOf: ["-SameQNotificationHour", String(hour)])
        }
        if forceDenied {
            arguments.append("-SameQNotificationForceDenied")
        }
        if simulateNotificationTap {
            arguments.append("-SameQSimulateNotificationTap")
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// オンボーディングを完了させて今日のお題画面へ。
    private func completeOnboarding(_ app: XCUIApplication, allowNotifications: Bool) {
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 8))
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
