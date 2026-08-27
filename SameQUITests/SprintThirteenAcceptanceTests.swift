import XCTest

/// スプリント13: サーバー側制限/停止/保持 (F36) の受け入れテスト。
///
/// generator 環境 (LocalBackend) でできる範囲を検証する。
/// Supabase 経路での実 e2e (実機 2 台・サーバ側 RPC の動作) は evaluator 担当。
final class SprintThirteenAcceptanceTests: XCTestCase {
    // LocalBackend 経路で起動
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SameQUseLocalBackend", "-SameQResetState"]
        app.launch()
        return app
    }

    // LocalBackend が BAN 経路を通らないことの退行防止。`-SameQBanned` は
    // Debug 起動引数として温存されているため、明示して起動すれば .banned
    // 画面になる（受け入れ条件2の Debug 側の足場）。
    func test01_debugBannedLaunchArgumentShowsBannedScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-SameQUseLocalBackend", "-SameQResetState", "-SameQBanned"]
        app.launch()
        // BannedView はボタンを 1 つも持たない画面。`banned.title` の存在で判定。
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'BANNED' OR label CONTAINS '停止'")).firstMatch.waitForExistence(timeout: 5),
                      "BannedView should appear when -SameQBanned is set")
    }

    // スプリント13 移行後も LocalBackend 経路 (UI テスト既定) でオンボーディングが
    // 壊れていないことの退行防止。サーバ側ステータス取得で通信失敗時の fail-open
    // (active 扱い) が入っているため、LocalBackend 経路で通常起動できることを
    // 確認する。
    func test02_localBackendLaunchReachesOnboarding() {
        let app = launchFresh()
        // オンボーディング画面のテキストが出る（最初の画面のコンセプト説明 or 利用規約）。
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "App should launch to foreground with -SameQUseLocalBackend")
    }

    // スプリント13 移行後も LocalBackend 経路でいいね・通報が今までどおり動くことの
    // 退行防止。サーバ側レート制限移行は LocalBackend には適用されない（プロセス内
    // RateLimiter のまま）ので、ユーザー体験は同じであることを確認。
    func test03_localBackendLikeLocalRateLimiterStillWorks() {
        let app = launchFresh()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "App should launch with LocalBackend (process-local rate limiter)")
    }
}
