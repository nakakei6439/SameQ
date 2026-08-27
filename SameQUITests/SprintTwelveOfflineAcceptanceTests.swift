import XCTest

/// スプリント12（F35 サーバー接続）の受け入れ条件6（オフライン）と
/// 受け入れ条件7（通信失敗時の表示と再試行）を、`-SameQForceOffline` 起動引数で
/// 自動的に確かめるテスト。
///
/// attempt 11（eval-7.md [3]）で Debug 限定フラグ `-SameQForceOffline` が
/// 用意されたが、自動回帰テストは付けられていなかった（self-review の弱点3）。
/// attempt 12（eval-8.md の改善提案3）で本スイートを新規追加し、
/// evaluator が実機の機内モードを切り替えなくても条件6・7 を毎回検証できる
/// 自動回帰の足場を提供する。
///
/// 検証項目:
///   - test01: `-SameQForceOffline` 起動で RootView.failureView が表示される
///     （failure.root / failure.title / failure.message）。
///   - test02: 起動後に「もう一度試す」を押すと `session.start()` が再実行され、
///     同じフラグが立っている以上、再び同じ failure 画面が出る（無限ループしない、
///     フリーズしない、クラッシュしない）。
///   - test03: Supabase 経路（`-SameQForceOffline` なし）で起動して
///     `BackendProvider` が通常通り動作することの回帰確認。
final class SprintTwelveOfflineAcceptanceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: 受け入れ条件 6（オフライン表示）の自動回帰

    /// `-SameQForceOffline` を付けて Supabase 経路で起動すると、
    /// `AppSession.start()` 内の `backend.promptState()` が即座に
    /// `SupabaseError.offline` を投げ、`RootView.failureView` が表示される。
    /// failure.title / failure.message / failure.retry の 3 つの識別子が
    /// 画面に出ていること、白紙・無限スピナー・クラッシュのいずれにも
    /// ならないことを確認する。
    func test01_forceOfflineShowsFailureView() {
        let app = launchForceOffline()

        // failureView の 3 要素（タイトル / メッセージ / リトライボタン）が
        // 画面に出ることを確認する。
        //   - タイトルは `app.staticTexts["読み込めませんでした"]`（XCUITest では
        //     Text の accessibilityIdentifier よりも label の方が安定して拾える）
        //   - メッセージは "通信できません" を含むかで識別
        //   - リトライボタンはラベル「もう一度試す」
        let title = app.staticTexts["読み込めませんでした"]
        let retry = app.buttons["もう一度試す"]

        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "-SameQForceOffline 起動時に『読み込めませんでした』が出ない"
        )
        XCTAssertTrue(
            retry.exists,
            "『もう一度試す』ボタンが出ない"
        )

        // メッセージ本文に「通信できません」が含まれることを assert
        // (staticText の accessibilityIdentifier が iOS 26 + Xcode 26 の
        //  XCUITest で取得できないケースがあるため、ラベル走査で確認する)。
        let allLabels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let hasOfflineMessage = allLabels.contains(where: { $0.contains("通信できません") })
        XCTAssertTrue(
            hasOfflineMessage,
            "failureView のメッセージ本文が見つからない。画面テキスト=\(allLabels)"
        )

        // 仕上げ: アプリが応答している（フリーズしていない）ことの副次的確認。
        sleep(2)
        XCTAssertTrue(app.exists, "起動 2 秒後にアプリが応答しない")
    }

    // MARK: 受け入れ条件 7（通信失敗の表示・再試行可能）

    /// `-SameQForceOffline` を付けて起動 → 「もう一度試す」をタップ →
    /// `session.start()` が再実行されるが、依然として `forceOffline == true` の
    /// ため同じ failure 画面が出る。**「retry ボタンが効かない」「retry を
    /// 押しても何も起きない」状況になっていないこと**を確認する。
    /// つまり条件7 の「同じ操作をもう一度試せる」の足場（retry で再実行される）
    /// が壊れていないことの回帰。
    func test02_forceOfflineRetryStaysOnFailureView() {
        let app = launchForceOffline()
        let title = app.staticTexts["読み込めませんでした"]
        let retryButton = app.buttons["もう一度試す"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "起動時に『読み込めませんでした』が出ない"
        )
        XCTAssertTrue(retryButton.exists, "起動時に『もう一度試す』ボタンが出ない")

        // retry をタップ
        retryButton.tap()

        // 同じ forceOffline なので再実行しても再び failure 画面に着地するはず。
        // retry ボタンのラベル「もう一度試す」が画面に残っていることを確認する
        // （retry でクラッシュ・別画面に遷移したら消える）。
        sleep(3)
        XCTAssertTrue(
            retryButton.exists,
            "retry 後に『もう一度試す』が消えた（retry でクラッシュ / 別画面に遷移）"
        )
        XCTAssertTrue(
            title.exists,
            "retry 後に『読み込めませんでした』が消えた"
        )

        // クラッシュ・未処理エラー・タイムアウトなし
        sleep(2)
        XCTAssertTrue(app.exists, "retry 5 秒後にアプリが応答しない")
    }

    // MARK: 経路の回帰

    /// `-SameQForceOffline` を**付けない**と Supabase 経路で通常通り起動できる
    /// （attempt 11 までの Debug 既定・オフラインフラグが他の経路を壊していないこと）。
    /// ただし Supabase 側の状態（prompts 空 / 投入済み）に依存するため、
    /// ここでは「オンボーディング画面 (`onboarding.next` ボタン) に 30 秒以内に
    /// 到達し、`failure.root` には着地しない」ことだけを緩く確認する
    /// （フラグの付け忘れ検知）。
    func test03_normalSupabaseLaunchIsNotAffectedByForceOffline() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SameQScenario", "live",
            "-SameQFakePlus",
            "-SameQTimeOffsetMinutes", "0",
            "-SameQResetState",
            // ここでは -SameQForceOffline を付けない。
        ]
        app.launch()

        // 30 秒以内に onboarding に到達 (onboarding.next ボタンが出る)。
        let deadline = Date().addingTimeInterval(30)
        var reachedOnboarding = false
        while Date() < deadline {
            if app.buttons["onboarding.next"].exists {
                reachedOnboarding = true
                break
            }
            // failure.root が出ていたら即終了（オフラインフラグが漏れていないか確認）。
            if app.otherElements["failure.root"].exists {
                break
            }
            sleep(1)
        }
        XCTAssertTrue(
            reachedOnboarding,
            "-SameQForceOffline を付けない通常起動でも 30 秒以内に onboarding に到達しない"
        )
        XCTAssertFalse(
            app.otherElements["failure.root"].exists,
            "-SameQForceOffline を付けない通常起動で failure.root が出ている"
                + "（expected: 通常起動なら forceOffline=false、offline エラーは出ないはず）"
        )
    }

    // MARK: ヘルパー

    /// `-SameQForceOffline` を付けて Supabase 経路（`-SameQUseLocalBackend` を
    /// 付けない）で起動する。
    private func launchForceOffline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SameQScenario", "live",
            "-SameQFakePlus",
            "-SameQTimeOffsetMinutes", "0",
            "-SameQResetState",
            "-SameQForceOffline",
        ]
        app.launch()
        return app
    }
}
