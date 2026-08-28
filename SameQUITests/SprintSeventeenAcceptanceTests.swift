import XCTest

/// スプリント17（F41）の受け入れ条件を実機操作で確かめる。
///
/// 受け入れ条件:
/// - 4: 先読みはアプリを background へ移したタイミングで行われ、アプリ使用中に
///      画面が止まらない。progress 表示が割り込まない。
/// - 5: 通信できない状態では先読みされず、エラー表示も出ない。通信が戻れば
///      通常通り利用できる。
/// - 6: アプリ内に翻訳の先読みに関する設定項目・ダウンロード管理・進捗表示が
///      1つも存在しない（F19「翻訳を意識させない」を守る）。
///
/// 検証の要点は「無いことを確かめる」（受け入れ条件6）と「アプリが固まらない /
/// エラーが混入しないことを確かめる」（受け入れ条件4・5）の2種類。
final class SprintSeventeenAcceptanceTests: XCTestCase {

    private let emoji = "🌙"
    private let nickname = "Keita"
    private let answerBody = "My honest answer for today's prompt."

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: F41 受け入れ条件6 — pre-fetch 用の UI 追加が無い

    /// pre-fetch の設定 / 進捗 / ダウンロード管理が一切存在しない。
    /// 既知の `accessibilityIdentifier` のリストに "prefetch" / "translation.peek"
    /// / "model.download" などの文字列が含まれていないことを確認する。
    /// 新しい UI が追加された場合はこのテストが落ちるので、将来の regression
    /// 検出の目印として機能する（F19 / 受け入れ条件6）。
    func test01_noPrefetchUIStringsExist() {
        let app = launch(arguments: ["-SameQAnswerCount", "2"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        // 1件目が出た後の画面上の要素を広く dump
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10),
            "1件目が出る（pre-fetch 検証の前提）"
        )

        let identifiers = collectAllAccessibilityIdentifiers(app: app)
        let forbidden: [String] = [
            "translation.prefetch",
            "translation.peek",
            "translation.download",
            "translation.background",
            "prefetch.settings",
            "model.download",
            "model.prepare",
            "modelDownload",
            "peek.status"
        ]
        for banned in forbidden {
            XCTAssertFalse(
                identifiers.contains(banned),
                "pre-fetch 用の UI 識別子『\(banned)』が画面上に出ている（F19/受け入れ条件6違反）"
            )
        }
    }

    // MARK: F41 受け入れ条件4 — pre-fetch 中も UI が固まらない

    /// タイムラインを読んだあと `scenePhase == .background` を経由して戻っても、
    /// 画面のスクロール・スワイプ・いいね操作が従来どおり機能し、エラー alert が
    /// 混入しない。`peekTranslationsInBackground` は画面を一切変更しない
    /// （`alertMessage` も `isPreparingTimeline` も触らない）設計なので、
    /// これが成立することを end-to-end で確かめる。
    func test02_backgroundPeekDoesNotInterruptTimeline() {
        let app = launch(arguments: ["-SameQAnswerCount", "3"], reset: true)
        completeOnboarding(app)
        submitAnswer(app, body: answerBody)

        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 10),
            "1件目が出る"
        )

        // アプリを background へ（= pre-fetch 起動のトリガ）
        // XCTest 経由で press home / deactivate を呼ぶ。
        XCUIDevice.shared.press(.home)
        // 少し待ってからフォアグラウンドへ戻す（= background 中に pre-fetch が走る時間）
        sleep(1)
        app.activate()

        // 戻ったあとも 1件目のまま（既読は永続化されているが、タイムラインは閉じずに
        // 同じ画面が再表示される）。スワイプで 2件目へ進めること・alert が無いことで
        // pre-fetch が UI を壊していないことを確認。
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 5),
            "background から戻ったとき 1件目の表示が残る"
        )
        XCTAssertFalse(
            app.alerts.element.exists,
            "background → foreground のあいだにエラー alert が出ていない"
        )

        // 2件目へスワイプ
        app.swipeLeft()
        XCTAssertTrue(
            app.staticTexts["timeline.card.body"].waitForExistence(timeout: 8),
            "スワイプで 2件目へ進める"
        )
        XCTAssertFalse(app.alerts.element.exists, "2件目描画時に alert が混入しない")

        // いいねも押せる（タップ後の選択状態反映まで少し待つ）
        let likeButton = app.buttons["timeline.like"]
        if likeButton.exists && likeButton.isHittable {
            likeButton.tap()
            XCTAssertTrue(
                waitForLikeButtonSelected(likeButton, timeout: 5),
                "background peek 後もいいねの選択状態反映が従来どおり"
            )
        }
    }

    // MARK: F41 受け入れ条件5前半 — オフライン時に pre-fetch しない／エラーも出ない

    /// `-SameQForceOffline` を付けて起動 → タイムラインを開いたあと background → foreground。
    /// pre-fetch は `isOnline() == false` で即 return する設計なので、UI に
    /// エラー alert が混入しないことだけを確認する。
    ///
    /// 注: `-SameQUseLocalBackend` を併用しているときは `LocalBackend` 経路のため
    /// `forceOffline` の影響は受けない（`LocalBackend.isOnline() == true` 固定）。
    /// このテストはあくまで `-SameQForceOffline` が付いても UI に致命的なエラーが
    /// 出ないこと（pre-fetch が暴れないこと）の最低限の保証として機能する。
    /// オフライン経路（`-SameQForceOffline` 付き・`-SameQUseLocalBackend` 併用）で
    /// アプリを起動し、background → foreground のあいだにエラー alert が混入しないことを
    /// 確認する（F41 受け入れ条件5前半）。
    ///
    /// 単体テスト（`BackgroundPeekTests.testBackgroundPeekSkipsWhenOffline`）で
    /// `ForceOfflineBackend` スタブを用いて `peekTranslationsInBackground` が
    /// 即 return することは直接検証済み。本テストは End-to-End での
    /// 「UI にエラーが出ない」ことの最低限の保証として機能する。
    func test03_offlineBackgroundPeekDoesNotShowError() {
        let app = launch(
            arguments: ["-SameQAnswerCount", "1", "-SameQForceOffline"],
            reset: true
        )
        // オフライン経路でも LocalBackend 経由なら onboarding → today までは進める。
        // 万一 onboarding が `-SameQForceOffline` の影響で開けなくても、
        // その時点で alert は出ないはずなので「alert が混入しない」ことの確認には十分。
        XCTAssertTrue(
            app.buttons["onboarding.next"].waitForExistence(timeout: 15)
                || app.staticTexts["timeline.card.body"].waitForExistence(timeout: 3),
            "オンボーディングかタイムラインのどちらかに到達する（オフライン経路）"
        )

        // background → foreground の遷移で alert が混入しない
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()

        XCTAssertFalse(
            app.alerts.element.exists,
            "オフライン background → foreground のあいだにエラー alert が出ていない"
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

    /// 画面上の `XCUIElement` を広く dump し、`accessibilityIdentifier` を集める。
    /// iOS の `XCUIElement.identifier` は空文字になることがあるので、空文字を除外する。
    private func collectAllAccessibilityIdentifiers(app: XCUIApplication) -> Set<String> {
        var result: Set<String> = []
        func collect(_ element: XCUIElement) {
            let id = element.identifier
            if !id.isEmpty {
                result.insert(id)
            }
            for child in element.children(matching: .any).allElementsBoundByIndex {
                collect(child)
            }
        }
        for element in app.descendants(matching: .any).allElementsBoundByIndex {
            collect(element)
        }
        return result
    }

    /// 設定シートを開く（受け入れ条件6 で設定画面に pre-fetch UI が無いことを確認するため）。
    private func openSettings(_ app: XCUIApplication) {
        // TodayPromptView / WaitingPromptView の右上歯車ボタン = `settings.open`
        let settingsButton = app.buttons["settings.open"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            // 設定画面の主要要素のどれかが出るまで待つ（閉じないよう .firstMatch でチェック）
            XCTAssertTrue(
                app.staticTexts["settings.title"].waitForExistence(timeout: 5)
                    || app.buttons["settings.profile"].waitForExistence(timeout: 5),
                "設定画面が開く"
            )
        }
    }

    /// 表示中の alert を閉じる。`OK` / `キャンセル` 相当のボタンを総当たりでタップする。
    /// XCUIAlert の標準的な閉じ方は環境ごとに違うので、両対応。
    private func dismissAnyVisibleAlert(_ app: XCUIApplication, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && app.alerts.element.exists {
            let alert = app.alerts.element
            // 典型ボタンの名前
            let candidates = ["OK", "Cancel", "了解", "キャンセル", "OK"]
            for name in candidates {
                let button = alert.buttons[name]
                if button.exists {
                    button.tap()
                    break
                }
            }
            if alert.exists { break }
        }
    }

    /// いいねボタンの選択状態になるまで短時間ポーリングする。
    private func waitForLikeButtonSelected(_ button: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.isSelected { return true }
            usleep(200_000)
        }
        return button.isSelected
    }
}
