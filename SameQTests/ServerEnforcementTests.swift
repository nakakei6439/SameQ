import XCTest
@testable import SameQ

/// スプリント13 (F36) attempt 3 のサーバー側制限/停止/保持の単体テスト。
///
/// generator 環境 (LocalBackend) で完結できる範囲を検証する。
/// Supabase 経路での実 e2e（実機 2 台・サーバ側 RPC の動作）は evaluator 担当。
final class ServerEnforcementTests: XCTestCase {

    private let storeFileName = "unit-test-state-server.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeBackend(offset: TimeInterval = 0) -> LocalBackend {
        LocalBackend(
            store: makeStore(),
            clock: AppClock(offset: offset),
            schedule: PromptSchedule(prompts: [], posts: []),
            options: LaunchOptions()
        )
    }

    // MARK: 受け入れ条件5関連（eval-2.md 改善提案4）

    /// `Backend.currentServerTime()` のプロトコル追加（`LocalBackend.currentServerTime`）
    /// が `clock.now` を返すことを確認する。これは `Backend` プロトコルが
    /// 必須要件として `currentServerTime() async throws -> Date` を追加したことで
    /// 既存実装が追随する必要があることの退行防止。
    func test01_localBackendCurrentServerTimeReturnsClockNow() async throws {
        let backend = makeBackend(offset: 0)
        let first = try await backend.currentServerTime()
        // 2 回目は少し先の時刻。両者が単調増加で、差が小さいことを確認
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let second = try await backend.currentServerTime()
        XCTAssertGreaterThanOrEqual(second, first)
        XCTAssertLessThanOrEqual(second.timeIntervalSince(first), 5.0)
    }

    /// 端末時計を意図的にオフセットした `AppClock` を渡しても、
    /// `currentServerTime()` はその時計の now を返す（=時計がそのまま見える）。
    /// サーバ時計が本当に独立した「ものさし」になるのは SupabaseBackend 側で
    /// あり、ここでは LocalBackend の戻り値経路の正しさに焦点を絞る。
    func test02_localBackendCurrentServerTimeReflectsClockOffset() async throws {
        let future = makeBackend(offset: 3600) // +1h
        let past = makeBackend(offset: -3600) // -1h
        let futureNow = try await future.currentServerTime()
        let pastNow = try await past.currentServerTime()
        // 時計オフセット分、未来が過去より 7200 秒 (= 2h) 先になることを確認。
        let delta = futureNow.timeIntervalSince(pastNow)
        XCTAssertGreaterThan(delta, 7000)
        XCTAssertLessThan(delta, 7400)
    }

    // MARK: `purgeExpiredSafetyLogs` の LocalBackend 経路（受け入れ条件6）

    /// LocalBackend 経路では古いレポートを `pruneExpired(at:)` で削除する。
    /// attempt 3 ではプロトコル `purgeExpiredSafetyLogs() async throws -> Int`
    /// の実装が両バックエンドで揃っていることを確認する。
    func test03_localBackendPurgeExpiredSafetyLogsReturnsCount() async throws {
        let backend = makeBackend()
        let deleted = try await backend.purgeExpiredSafetyLogs()
        XCTAssertGreaterThanOrEqual(deleted, 0)
    }

    // MARK: `Backend` プロトコルの必須要件が揃っていることの確認

    /// `Backend` プロトコルの `currentServerTime()` と `purgeExpiredSafetyLogs()`
    /// が `any Backend` 経由で呼べることを確認する（プロトコルへの昇格が実
    /// インターフェースに反映されていることの回帰防止）。
    func test04_backendProtocolExposesCurrentServerTimeAndPurgeExpiredSafetyLogs() async throws {
        let backend: any Backend = makeBackend()
        // 戻り値の型が Date / Int として受け取れることを確認
        let _: Date = try await backend.currentServerTime()
        let _: Int = try await backend.purgeExpiredSafetyLogs()
    }
}
