import XCTest
@testable import SameQ

/// スプリント16（F40）の `AppSession.unreadTimelineCount` を、データ層から押さえる。
///
/// `unreadTimelineCount` は「候補数 − 既読数」を 0 で床打ちした純粋な計算プロパティで、
/// それを `TimelineView.shouldShowFewAnswersHint` が `timelineContent == .post` の
/// ときだけ `+1`（いま見ているカードを足し戻す）で解釈する。
///
/// このテストはその **データ層** の境界値だけを担保する:
/// - 候補 0・既読 0 → 未読 0（`.empty` / `.exhausted` で使用、ヒント対象外）
/// - 候補 N・既読 0 → 未読 N（候補の母数そのもの）
/// - 候補 N・既読 N → 未読 0（全部読んだ）
/// - 候補 N・既読 M (M > N) → 未読 0（異常系のクランプ、UI に「-1」を出さない）
///
/// UI 側の分岐（+1 と .post の組合せ）は `SprintSixteenAcceptanceTests` の XCUITest で
/// 1件／2件／3件以上のシナリオを実際に開いて確認する。
@MainActor
final class TimelineUnreadCountTests: XCTestCase {

    private let storeFileName = "timeline-unread-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeSchedule(reference: Date, otherCount: Int) -> PromptSchedule {
        let first = Prompt(
            id: "p1",
            text: "テスト用のお題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600)
        )
        let posts = (1...max(otherCount, 0)).prefix(otherCount).map { i in
            Post(
                id: UUID(),
                promptID: first.id,
                authorID: UUID(),
                authorEmoji: "🐢",
                authorNickname: nil,
                body: "p1の回答#\(i)",
                bodyLanguage: "ja",
                createdAt: first.endsAt.addingTimeInterval(-7200),
                expiresAt: first.endsAt
            )
        }
        return PromptSchedule(prompts: [first], posts: posts)
    }

    private func makeBackend(
        store: LocalStore,
        schedule: PromptSchedule,
        offset: TimeInterval = 0
    ) -> LocalBackend {
        LocalBackend(
            store: store,
            clock: AppClock(offset: offset),
            schedule: schedule,
            options: LaunchOptions()
        )
    }

    private func makeSession(backend: Backend, clock: AppClock = AppClock()) -> AppSession {
        AppSession(backend: backend, clock: clock)
    }

    // MARK: 受け入れ条件 (F40) — データ層の境界値

    /// 候補3件・既読0件（= 起動直後の典型状態）: 未読は 3。
    /// UI 側では「+1 した現在表示中カード = 4」で閾値（>= 3）を超えるためヒント対象外。
    func testFreshOpenWithThreeCandidatesYieldsUnreadThree() async throws {
        let reference = Date()
        let store = makeStore()
        let schedule = makeSchedule(reference: reference, otherCount: 3)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: "p1", body: "自分の回答")
        let session = makeSession(backend: backend)

        session.replaceTimelineCountsForTest(
            candidate: try await backend.timelinePosts(promptID: "p1").count,
            viewed: try await backend.viewedPostIDs().count
        )
        XCTAssertEqual(session.unreadTimelineCount, 3)
    }

    /// 候補2件・既読0件 → 未読 2。UI 側では +1 で 3 → ちょうど閾値で**ヒント対象外**。
    /// （3件ぴったりは「まだ読めるカードが3枚ある＝少なさ」ではないので出さない）
    func testTwoCandidatesAtFreshOpenYieldsUnreadTwo() async throws {
        let reference = Date()
        let store = makeStore()
        let schedule = makeSchedule(reference: reference, otherCount: 2)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: "p1", body: "自分の回答")
        let session = makeSession(backend: backend)

        session.replaceTimelineCountsForTest(candidate: 2, viewed: 0)
        XCTAssertEqual(session.unreadTimelineCount, 2)
    }

    /// 候補1件・既読0件 → 未読 1。UI 側では +1 で 2 → ヒント対象。
    func testOneCandidateAtFreshOpenYieldsUnreadOne() async throws {
        let reference = Date()
        let store = makeStore()
        let schedule = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: "p1", body: "自分の回答")
        let session = makeSession(backend: backend)

        session.replaceTimelineCountsForTest(candidate: 1, viewed: 0)
        XCTAssertEqual(session.unreadTimelineCount, 1)
    }

    /// 候補0件・既読0件（=他人の回答が無い）→ 未読 0。`.empty` 表示側で扱うので
    /// ヒント表示は `.empty` 終端表示に任せる（受け入れ条件6: 二重に出ない）。
    func testZeroCandidatesYieldsUnreadZero() async throws {
        let session = makeSession(backend: BackendProvider.make())
        session.replaceTimelineCountsForTest(candidate: 0, viewed: 0)
        XCTAssertEqual(session.unreadTimelineCount, 0)
    }

    /// 候補1件・既読1件（=1件読み切った直後）→ 未読 0。`.exhausted` に遷移する。
    func testAllReadYieldsUnreadZero() async throws {
        let session = makeSession(backend: BackendProvider.make())
        session.replaceTimelineCountsForTest(candidate: 1, viewed: 1)
        XCTAssertEqual(session.unreadTimelineCount, 0)
    }

    /// 候補5件・既読2件（=タイムラインで2件読んだところ）→ 未読 3。
    /// UI 側では +1 で 4 → まだ「多め」と判断されてヒント対象外（境界の安定性確認）。
    func testPartiallyReadFiveCandidatesYieldsUnreadThree() async throws {
        let session = makeSession(backend: BackendProvider.make())
        session.replaceTimelineCountsForTest(candidate: 5, viewed: 2)
        XCTAssertEqual(session.unreadTimelineCount, 3)
    }

    /// 異常系: 候補より既読のほうが多く（古い `viewedPostIDs` が残っている等）、
    /// 差分が負になっても UI には 0 として返す（受け入れ条件4「数値が出ない」を守るため、
    /// ヒントの文字列にも「マイナス」が現れないことを担保）。
    func testUnreadClampsAtZeroWhenViewedExceedsCandidates() async throws {
        let session = makeSession(backend: BackendProvider.make())
        session.replaceTimelineCountsForTest(candidate: 2, viewed: 5)
        XCTAssertEqual(session.unreadTimelineCount, 0)
    }
}
