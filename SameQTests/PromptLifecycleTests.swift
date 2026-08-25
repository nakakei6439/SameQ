import XCTest
@testable import SameQ

/// スプリント02（F08 / F09 / F10）のうち、画面操作では確かめにくい部分をここで押さえる。
/// 特に「期限切れ直前に投稿した回答が、終了時刻を過ぎると他ユーザーから見えなくなる」は
/// UI 操作では別アカウントを用意できないため、データ層で検証する。
final class PromptLifecycleTests: XCTestCase {

    private let storeFileName = "unit-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    /// お題2つと、それぞれの回答1件ずつを持つ日程を作る。
    private func makeSchedule(reference: Date) -> (PromptSchedule, Prompt, Prompt) {
        let first = Prompt(
            id: "p1",
            text: "1つ目のお題",
            startsAt: reference.addingTimeInterval(-Prompt.defaultDuration + 60),   // 60秒後に終了
            endsAt: reference.addingTimeInterval(60)
        )
        let second = Prompt(
            id: "p2",
            text: "2つ目のお題",
            startsAt: reference.addingTimeInterval(120),                            // 60秒の空白のあと開始
            endsAt: reference.addingTimeInterval(120 + Prompt.defaultDuration)
        )
        let posts = [
            makePost(promptID: first.id, body: "誰かの回答（1つ目）", expiresAt: first.endsAt),
            makePost(promptID: second.id, body: "誰かの回答（2つ目）", expiresAt: second.endsAt)
        ]
        return (PromptSchedule(prompts: [first, second], posts: posts), first, second)
    }

    private func makePost(promptID: String, body: String, expiresAt: Date) -> Post {
        Post(
            id: UUID(),
            promptID: promptID,
            authorID: UUID(),
            authorEmoji: "🐢",
            authorNickname: nil,
            body: body,
            bodyLanguage: "ja",
            createdAt: expiresAt.addingTimeInterval(-3600),
            expiresAt: expiresAt
        )
    }

    private func makeBackend(store: LocalStore, schedule: PromptSchedule, offset: TimeInterval) -> LocalBackend {
        LocalBackend(
            store: store,
            clock: AppClock(offset: offset),
            schedule: schedule,
            options: LaunchOptions()
        )
    }

    // MARK: 有効期間（F09）

    func testPromptStateSwitchesAtStartAndEnd() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, second) = makeSchedule(reference: reference)

        // いまは1つ目のお題が有効
        let now = makeBackend(store: store, schedule: schedule, offset: 0)
        let stateNow = try await now.promptState()
        XCTAssertEqual(stateNow, .active(first))

        // 終了直後は「お題待ち」で、次の開始時刻を持つ
        let afterEnd = makeBackend(store: store, schedule: schedule, offset: 61)
        let stateAfterEnd = try await afterEnd.promptState()
        XCTAssertEqual(stateAfterEnd, .waiting(nextStartsAt: second.startsAt))

        // 2つ目が始まると、そちらが有効になる
        let afterNextStart = makeBackend(store: store, schedule: schedule, offset: 121)
        let stateAfterNextStart = try await afterNextStart.promptState()
        XCTAssertEqual(stateAfterNextStart, .active(second))
    }

    /// 受け入れ条件: 期限切れ直前に投稿した回答も、終了時刻を過ぎれば見えなくなる。
    func testPostSubmittedJustBeforeExpiryDisappearsForOthers() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference)

        let backend = makeBackend(store: store, schedule: schedule, offset: 0)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: "tester")
        let mine = try await backend.submitPost(promptID: first.id, body: "終了30秒前の回答")

        // 表示期限はお題の終了時刻に揃う（置いた前提2）
        XCTAssertEqual(mine.expiresAt, first.endsAt)
        XCTAssertTrue(mine.isVisible(at: reference))
        XCTAssertFalse(mine.isVisible(at: first.endsAt))

        // 他ユーザー視点: 終了後はその投稿が世界タイムラインの対象に入らない
        let afterEnd = makeBackend(store: store, schedule: schedule, offset: 61)
        let others = schedule.visiblePosts(promptID: first.id, at: reference.addingTimeInterval(61))
        XCTAssertTrue(others.isEmpty, "終了後は誰の回答も表示対象に残らない")
        let timeline = try await afterEnd.timelinePosts(promptID: first.id)
        XCTAssertTrue(timeline.isEmpty, "終了したお題のタイムラインは0件")
    }

    /// 受け入れ条件: 新しいお題が始まると、前のお題に回答済みでも再び未回答になる。
    func testNewPromptResetsAnsweredState() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, second) = makeSchedule(reference: reference)

        let backend = makeBackend(store: store, schedule: schedule, offset: 0)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "1つ目への回答")
        let answered = try await backend.myPost(promptID: first.id)
        XCTAssertNotNil(answered)

        // 2つ目のお題が始まった時点では未回答
        let afterNextStart = makeBackend(store: store, schedule: schedule, offset: 121)
        let stateAfterNextStart = try await afterNextStart.promptState()
        XCTAssertEqual(stateAfterNextStart, .active(second))
        let myPostForSecond = try await afterNextStart.myPost(promptID: second.id)
        XCTAssertNil(myPostForSecond, "新しいお題では未回答に戻る")
        // 前のお題の回答は保存からも落ちている（履歴を持たない）
        let myPostForFirst = try await afterNextStart.myPost(promptID: first.id)
        XCTAssertNil(myPostForFirst, "期限切れの自分の回答は残さない")
    }

    /// 期限切れのお題・未開始のお題には投稿できない。
    func testSubmitRejectedOutsidePromptPeriod() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, second) = makeSchedule(reference: reference)

        let afterEnd = makeBackend(store: store, schedule: schedule, offset: 61)
        try await afterEnd.createAnonymousUser(emoji: "🌙", nickname: nil)
        do {
            try await afterEnd.submitPost(promptID: first.id, body: "終了後の投稿")
            XCTFail("終了したお題には投稿できてはいけない")
        } catch {
            XCTAssertEqual(error as? BackendError, .promptNotActive)
        }
        do {
            try await afterEnd.submitPost(promptID: second.id, body: "開始前の投稿")
            XCTFail("開始前のお題には投稿できてはいけない")
        } catch {
            XCTAssertEqual(error as? BackendError, .promptNotActive)
        }
    }

    // MARK: 検証用シナリオ（評価者が使う起動引数の裏付け）

    func testScenariosProduceExpectedPromptState() throws {
        // スプリント09 attempt 2: `.live` の reference は anchor 直近 (anchor + 12h) を使い、
        // seed prompt が active な状態で検証する（coverage 内）。
        let reference = SeedCatalog.debugLiveAnchor.addingTimeInterval(12 * 60 * 60)
        var options = LaunchOptions()
        options.expirySeconds = 120
        options.gapSeconds = 60

        let live = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: options)
        XCTAssertNotNil(live.activePrompt(at: reference), "live: いまお題が有効")
        XCTAssertGreaterThanOrEqual(live.visiblePosts(promptID: "prompt_001", at: reference).count, 10)

        let expiring = try SeedCatalog.loadSchedule(reference: reference, scenario: .expiring, options: options)
        XCTAssertEqual(expiring.activePrompt(at: reference)?.id, "prompt_001")
        XCTAssertNil(expiring.activePrompt(at: reference.addingTimeInterval(121)), "終了直後はお題待ち")
        XCTAssertEqual(
            expiring.activePrompt(at: reference.addingTimeInterval(181))?.id,
            "prompt_002",
            "空白のあと次のお題が始まる"
        )

        let expired = try SeedCatalog.loadSchedule(reference: reference, scenario: .expired, options: options)
        XCTAssertNil(expired.activePrompt(at: reference), "expired: 有効なお題が無い")
        XCTAssertTrue(expired.visiblePosts(promptID: "prompt_001", at: reference).isEmpty, "期限切れの回答は0件")

        let upcoming = try SeedCatalog.loadSchedule(reference: reference, scenario: .upcoming, options: options)
        XCTAssertNil(upcoming.activePrompt(at: reference), "upcoming: まだ始まっていない")
        XCTAssertNotNil(upcoming.nextStart(after: reference))
    }

    /// 同時に有効なお題は常に1つだけ（置いた前提3）。
    func testPromptPeriodsNeverOverlap() throws {
        let reference = Date()
        for scenario in PromptScenario.allCases {
            let schedule = try SeedCatalog.loadSchedule(reference: reference, scenario: scenario, options: LaunchOptions())
            let sorted = schedule.prompts.sorted { $0.startsAt < $1.startsAt }
            XCTAssertEqual(sorted.map(\.id), schedule.prompts.map(\.id), "\(scenario): 開始時刻順に並んでいる")
            for (previous, next) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(previous.endsAt, next.startsAt, "\(scenario): 有効期間が重なっている")
            }
            for prompt in schedule.prompts {
                XCTAssertEqual(
                    prompt.endsAt.timeIntervalSince(prompt.startsAt),
                    Prompt.defaultDuration,
                    accuracy: 1,
                    "\(scenario): 有効期間は28時間"
                )
            }
        }
    }
}
