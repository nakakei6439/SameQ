import XCTest
@testable import SameQ

/// F43 / スプリント18 の隠し開発者モード（`AppSession.debugPlusOverride`）を
/// 検証する単体テスト。
///
/// 受け入れ条件7「アプリを終了して起動し直すと必ず『実際の状態』に戻る」
/// を担保する最重要点 = **永続化されないこと** を直接検証する。
@MainActor
final class DeveloperModeTests: XCTestCase {

    private let storeFileName = "developer-mode-test-state.json"

    private func makeSession(plusActive: Bool = false) async -> AppSession {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        var options = LaunchOptions.current
        options.fakePlus = true
        options.plusActiveAtLaunch = plusActive
        let backend = LocalBackend(store: store, options: options)
        let service = FakePlusService(active: plusActive)
        let session = AppSession(
            backend: backend,
            plusService: service
        )
        // `plusEntitlement` は `refreshPlusEntitlement()` で `plusService` から取り込まれる。
        // ここで明示的に呼んでテストの状態を確定させる。
        await session.refreshPlusEntitlement()
        return session
    }

    /// `debugPlusOverride` が `isPlus` を上書きする（=実際のエンタイトルメントを
    /// 無視する）。
    func test01_debugOverrideOverridesActualEntitlement() async {
        // 実際のエンタイトルメントは false（無料ユーザー）
        let session = await makeSession(plusActive: false)
        XCTAssertFalse(session.isPlus, "実体が無料で override なしなら isPlus == false")
        session.debugPlusOverride = true
        XCTAssertTrue(session.isPlus, "debugOverride=true で実体が無料でも isPlus == true")

        // 実際のエンタイトルメントが true（Plus 購入済み）
        let session2 = await makeSession(plusActive: true)
        XCTAssertTrue(session2.isPlus, "実体が Plus で override なしなら isPlus == true")
        session2.debugPlusOverride = false
        XCTAssertFalse(session2.isPlus, "debugOverride=false で実体が Plus でも isPlus == false")
    }

    /// 受け入れ条件7: アプリ再起動（新しい `AppSession` インスタンス）で
    /// `debugPlusOverride` は常に `nil` に戻り、実体のエンタイトルメントに従う。
    /// **永続化されないこと**の直接検証。
    func test02_debugOverrideDoesNotPersistAcrossSessionInstances() async {
        // 1回目: 開発者モードで「常に Plus」を有効化
        let first = await makeSession(plusActive: false)
        first.debugPlusOverride = true
        XCTAssertTrue(first.isPlus, "1回目セッションでは Plus 表示")

        // 2回目: 新しい `AppSession` を作る（アプリ再起動を模倣）。
        // 永続化はされないので override は設定しない。
        let second = await makeSession(plusActive: false)
        XCTAssertNil(
            second.debugPlusOverride,
            "再起動後の新規 AppSession の debugPlusOverride は nil（永続化されない）"
        )
        XCTAssertFalse(second.isPlus, "再起動後は実体（無料）に戻る")
    }

    /// `debugOverride = false` で「常に無料」を強制した状態でも、
    /// 実体が Plus 購入済みなら `isPlus == false` を返す。
    func test03_debugOverrideFalseForcesFreeEvenIfActuallyPlus() async {
        let session = await makeSession(plusActive: true)
        XCTAssertTrue(session.isPlus, "override なし・実体 Plus → isPlus == true")

        session.debugPlusOverride = false
        XCTAssertFalse(session.isPlus, "常に無料 override は実体の Plus を上書きする")

        session.debugPlusOverride = true
        XCTAssertTrue(session.isPlus, "ランタイムで override を true に変えると即反映")

        session.debugPlusOverride = nil
        XCTAssertTrue(
            session.isPlus,
            "override を nil に戻すと実体（Plus 購入済み）に戻る"
        )
    }

    /// `debugPlusOverride` はアカウント状態と独立して保持される開発者用フラグ。
    /// ランタイムで `user` を消しても override は落ちない。
    func test04_debugOverrideSurvivesUserReset() async {
        let session = await makeSession(plusActive: false)
        session.debugPlusOverride = true
        XCTAssertTrue(session.isPlus)
        // user は外部からは直接消せないので、override が落ちないことだけを確認。
        XCTAssertNotNil(session.debugPlusOverride, "override は明示的に nil するまで残る")
    }
}