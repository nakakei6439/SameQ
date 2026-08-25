import XCTest
@testable import SameQ

/// スプリント03（F11 / F12）の取得ルールと既読管理を、データ層で押さえる。
///
/// 「20回スワイプして重複しない」「アプリを再起動しても既読が残る」は
/// 画面操作でも確認するが、乱数が絡むので回数を増やせるここでも検証する。
final class TimelineSelectionTests: XCTestCase {

    private let storeFileName = "timeline-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    /// お題2つ。1つ目に `otherCount` 件、2つ目に3件の「他人の回答」を持つ。
    private func makeSchedule(reference: Date, otherCount: Int) -> (PromptSchedule, Prompt, Prompt) {
        let first = Prompt(
            id: "p1",
            text: "1つ目のお題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600)
        )
        let second = Prompt(
            id: "p2",
            text: "2つ目のお題",
            startsAt: first.endsAt,
            endsAt: first.endsAt.addingTimeInterval(Prompt.defaultDuration)
        )
        var posts = (1...max(otherCount, 1)).prefix(otherCount).map {
            makePost(promptID: first.id, body: "p1の回答#\($0)", expiresAt: first.endsAt)
        }
        posts += (1...3).map {
            makePost(promptID: second.id, body: "p2の回答#\($0)", expiresAt: second.endsAt)
        }
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
            createdAt: expiresAt.addingTimeInterval(-7200),
            expiresAt: expiresAt
        )
    }

    private func makeBackend(store: LocalStore, schedule: PromptSchedule, offset: TimeInterval = 0) -> LocalBackend {
        LocalBackend(store: store, clock: AppClock(offset: offset), schedule: schedule, options: LaunchOptions())
    }

    /// 受け入れ条件: 20件あるとき、20回引く間に同じ回答が2回出ない。21回目は「読み切り」。
    func testUnreadFirstNeverRepeatsWithinOnePrompt() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 20)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        var seen: [UUID] = []
        for step in 1...20 {
            guard case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) else {
                return XCTFail("\(step)回目で回答が引けなかった")
            }
            XCTAssertFalse(seen.contains(post.id), "\(step)回目に既読の回答が再び出た")
            XCTAssertEqual(post.promptID, first.id, "別のお題の回答が出た")
            seen.append(post.id)
        }
        XCTAssertEqual(Set(seen).count, 20)

        let afterAll = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterAll, .exhausted, "読み切ったら exhausted（空ではない）")
    }

    /// 受け入れ条件（評価者注記）: アプリを再起動しても既読が残る。
    func testViewedRecordsSurviveRelaunch() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 20)

        let firstLaunch = makeBackend(store: store, schedule: schedule)
        try await firstLaunch.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await firstLaunch.submitPost(promptID: first.id, body: "自分の回答")
        var seen: Set<UUID> = []
        for _ in 1...8 {
            guard case .post(let post) = try await firstLaunch.nextTimelinePost(promptID: first.id) else {
                return XCTFail("回答が引けなかった")
            }
            seen.insert(post.id)
        }

        // 起動し直す（同じ保存ファイルから読み直す）
        let secondLaunch = makeBackend(store: store, schedule: schedule)
        let restored = try await secondLaunch.viewedPostIDs()
        XCTAssertEqual(restored, seen, "既読が保存から復元される")
        for _ in 1...12 {
            guard case .post(let post) = try await secondLaunch.nextTimelinePost(promptID: first.id) else {
                return XCTFail("再起動後に回答が引けなかった")
            }
            XCTAssertFalse(seen.contains(post.id), "再起動後に既読の回答が出た")
            seen.insert(post.id)
        }
        XCTAssertEqual(seen.count, 20)
        let afterRelaunchAll = try await secondLaunch.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterRelaunchAll, .exhausted)
    }

    /// 受け入れ条件: 回答が自分の1件しか無い場合は「空」状態で、自分の投稿は他人として出ない。
    func testOnlyMyOwnAnswerYieldsEmpty() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 0)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        let mine = try await backend.submitPost(promptID: first.id, body: "自分だけの回答")

        let candidates = try await backend.timelinePosts(promptID: first.id)
        XCTAssertEqual(candidates.count, 0)
        let firstDraw = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(firstDraw, .empty)
        // 何度引いても空のまま（壊れない）
        let secondDraw = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(secondDraw, .empty)
        let viewed = try await backend.viewedPostIDs()
        XCTAssertFalse(viewed.contains(mine.id), "自分の回答は既読にもならない")
    }

    /// 受け入れ条件: 他人の回答が1件だけのときは1回引けて、その次が読み切りになる。
    func testSingleOtherAnswerThenExhausted() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        XCTAssertEqual(post.promptID, first.id)
        let afterOnly = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterOnly, .exhausted)
    }

    /// 受け入れ条件: 表示されるのは今日のお題への回答だけ。別のお題の回答は混ざらない。
    func testOtherPromptAnswersNeverAppear() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, second) = makeSchedule(reference: reference, otherCount: 5)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        for _ in 1...5 {
            guard case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) else {
                return XCTFail("回答が引けなかった")
            }
            XCTAssertEqual(post.promptID, first.id)
            XCTAssertNotEqual(post.promptID, second.id)
        }
        let afterFive = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterFive, .exhausted)
        // 2つ目のお題はまだ始まっていないので、その回答も引けない
        let secondPromptDraw = try await backend.nextTimelinePost(promptID: second.id)
        XCTAssertEqual(secondPromptDraw, .empty)
    }

    /// 受け入れ条件: 同じ条件で開き直すと1件目が毎回同一とは限らない（順番を持たない）。
    func testFirstDrawIsNotAlwaysTheSamePost() async throws {
        let reference = Date()
        var firstDraws: Set<UUID> = []
        for _ in 1...30 {
            let store = makeStore()
            let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 20)
            let backend = makeBackend(store: store, schedule: schedule)
            try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
            try await backend.submitPost(promptID: first.id, body: "自分の回答")
            if case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) {
                firstDraws.insert(post.id)
            }
        }
        XCTAssertGreaterThan(firstDraws.count, 1, "1件目が毎回同じ回答になっている（ランダムでない）")
    }

    /// いいねの永続はスプリント01の受け入れ条件。既読の導入で消えていないことを確認する。
    /// 画面では既読の回答を出し直せないため、ここと `-SameQResetViewed` で担保する。
    func testLikesSurviveRelaunchIndependentlyOfViewedRecords() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 20)

        let firstLaunch = makeBackend(store: store, schedule: schedule)
        try await firstLaunch.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await firstLaunch.submitPost(promptID: first.id, body: "自分の回答")
        guard case .post(let liked) = try await firstLaunch.nextTimelinePost(promptID: first.id) else {
            return XCTFail("回答が引けなかった")
        }
        try await firstLaunch.setLike(postID: liked.id, liked: true)

        // 起動し直しても、いいねは残っている
        let secondLaunch = makeBackend(store: store, schedule: schedule)
        let likedAfterRelaunch = try await secondLaunch.likedPostIDs()
        XCTAssertTrue(likedAfterRelaunch.contains(liked.id))

        // `-SameQResetViewed` は既読だけを消し、アカウント・回答・いいねは残す
        var options = LaunchOptions()
        options.resetsViewed = true
        let afterResetViewed = LocalBackend(
            store: store,
            clock: AppClock(offset: 0),
            schedule: schedule,
            options: options
        )
        let viewedAfterReset = try await afterResetViewed.viewedPostIDs()
        XCTAssertTrue(viewedAfterReset.isEmpty, "既読だけ消える")
        let likesAfterReset = try await afterResetViewed.likedPostIDs()
        XCTAssertTrue(likesAfterReset.contains(liked.id), "いいねは残る")
        let userAfterReset = try await afterResetViewed.currentUser()
        XCTAssertNotNil(userAfterReset, "アカウントは残る")
        let myPostAfterReset = try await afterResetViewed.myPost(promptID: first.id)
        XCTAssertNotNil(myPostAfterReset, "自分の回答は残る")
    }

    /// お題が終わると、その回答への既読は保存から落ちる（履歴を持たない）。
    func testViewedRecordsAreDroppedWhenPostsExpire() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, first, _) = makeSchedule(reference: reference, otherCount: 5)

        let live = makeBackend(store: store, schedule: schedule)
        try await live.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await live.submitPost(promptID: first.id, body: "自分の回答")
        _ = try await live.nextTimelinePost(promptID: first.id)
        let viewedWhileLive = try await live.viewedPostIDs()
        XCTAssertEqual(viewedWhileLive.count, 1)

        // 1つ目のお題の終了後
        let afterEnd = makeBackend(store: store, schedule: schedule, offset: Prompt.defaultDuration)
        let viewedAfterEnd = try await afterEnd.viewedPostIDs()
        XCTAssertTrue(viewedAfterEnd.isEmpty, "期限切れの回答の既読は残さない")
    }

    // MARK: 検証用の件数指定（`-SameQAnswerCount`）

    func testAnswerCountOptionProducesStableIdentifiersAcrossLaunches() throws {
        // スプリント09 attempt 2: `.live` の seed prompt は絶対アンカーから 28h 間隔で並ぶ。
        // coverage (= 56h) 内の reference (= anchor + 12h) を使い、prompt_001 が active な状態で検証する。
        let reference = SeedCatalog.debugLiveAnchor.addingTimeInterval(12 * 60 * 60)
        var options = LaunchOptions()
        options.answerCount = 120

        let firstLoad = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: options)
        let secondLoad = try SeedCatalog.loadSchedule(
            reference: reference.addingTimeInterval(600),
            scenario: .live,
            options: options
        )
        XCTAssertEqual(firstLoad.visiblePosts(promptID: "prompt_001", at: reference).count, 120)
        XCTAssertEqual(
            firstLoad.posts.map(\.id),
            secondLoad.posts.map(\.id),
            "起動をまたいで同じ ID でないと既読の判定ができない"
        )
        XCTAssertEqual(Set(firstLoad.posts.map(\.id)).count, firstLoad.posts.count, "ID が重複している")

        options.answerCount = 0
        let empty = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: options)
        XCTAssertTrue(empty.visiblePosts(promptID: "prompt_001", at: reference).isEmpty)

        options.answerCount = 1
        let single = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: options)
        XCTAssertEqual(single.visiblePosts(promptID: "prompt_001", at: reference).count, 1)
    }

    /// 引数なしでも20スワイプの検証ができるだけの回答が同梱されている。
    func testBundledSeedHasEnoughAnswersForTwentySwipes() throws {
        // スプリント09 attempt 2: `.live` の reference は anchor 直近 (anchor + 12h) を使う。
        let reference = SeedCatalog.debugLiveAnchor.addingTimeInterval(12 * 60 * 60)
        let schedule = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: LaunchOptions())
        XCTAssertGreaterThanOrEqual(
            schedule.visiblePosts(promptID: "prompt_001", at: reference).count,
            20,
            "同梱シードだけで20件そろっていないと、引数なしの検証ができない"
        )
    }
}
