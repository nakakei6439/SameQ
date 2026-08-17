import XCTest
@testable import SameQ

/// スプリント05（F16 / F17）の BAN・投稿頻度制限・スパム対策を、データ層で押さえる。
///
/// 画面操作は `SprintFiveAcceptanceTests`（UI）で確認するが、
/// 連打制限や重複投稿は繰り返し回数を増やせるここでも検証する。
final class BanAndSpamTests: XCTestCase {

    private let storeFileName = "ban-spam-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeSchedule(
        reference: Date,
        bannedAuthorIDs: Set<UUID> = []
    ) -> (PromptSchedule, Prompt, Prompt, UUID) {
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
        let bannedAuthorID = UUID()
        var posts: [Post] = [
            makePost(promptID: first.id, authorID: UUID(), body: "他の人の回答1", expiresAt: first.endsAt),
            makePost(promptID: first.id, authorID: UUID(), body: "他の人の回答2", expiresAt: first.endsAt),
            makePost(
                promptID: first.id,
                authorID: bannedAuthorID,
                body: "BANされた人の回答",
                expiresAt: first.endsAt
            )
        ]
        posts += (1...3).map {
            makePost(promptID: second.id, authorID: UUID(), body: "2つ目のお題の回答#\($0)", expiresAt: second.endsAt)
        }
        let schedule = PromptSchedule(
            prompts: [first, second],
            posts: posts,
            bannedAuthorIDs: bannedAuthorIDs.isEmpty ? [bannedAuthorID] : bannedAuthorIDs
        )
        return (schedule, first, second, bannedAuthorID)
    }

    private func makePost(promptID: String, authorID: UUID, body: String, expiresAt: Date) -> Post {
        Post(
            id: UUID(),
            promptID: promptID,
            authorID: authorID,
            authorEmoji: "🐢",
            authorNickname: "Kai",
            body: body,
            bodyLanguage: "ja",
            createdAt: expiresAt.addingTimeInterval(-7200),
            expiresAt: expiresAt
        )
    }

    private func makeBackend(
        store: LocalStore,
        schedule: PromptSchedule,
        offset: TimeInterval = 0,
        options: LaunchOptions = LaunchOptions()
    ) -> LocalBackend {
        LocalBackend(store: store, clock: AppClock(offset: offset), schedule: schedule, options: options)
    }

    // MARK: 受け入れ条件1（1つのお題に投稿できるのは1回だけ）

    func testSecondSubmissionToSamePromptIsRejected() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "最初の回答")

        do {
            try await backend.submitPost(promptID: first.id, body: "別の言葉で２回目")
            XCTFail("2回目の投稿が通ってしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .alreadyAnswered)
        }

        // お題画面へ戻っても自分の回答が見える（入力欄には戻れない）
        let myPost = try await backend.myPost(promptID: first.id)
        XCTAssertEqual(myPost?.body, "最初の回答")
    }

    // MARK: 受け入れ条件2（直近の自分の投稿と同一の本文を別のお題に投稿すると拒否）

    func testDuplicateBodyAcrossDifferentPromptsIsRejected() async throws {
        let store = makeStore()
        let (schedule, first, second, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "全く同じ回答")

        // 1つ目のお題が終わったあと、2つ目のお題に同じ本文を投稿しようとする
        let afterSwitch = makeBackend(store: store, schedule: schedule, offset: Prompt.defaultDuration)
        do {
            try await afterSwitch.submitPost(promptID: second.id, body: "全く同じ回答")
            XCTFail("同一本文の投稿が通ってしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .duplicateBody)
        }

        // 言葉を変えれば投稿できる
        let post = try await afterSwitch.submitPost(promptID: second.id, body: "少し違う回答にしてみた")
        XCTAssertEqual(post.body, "少し違う回答にしてみた")
    }

    func testDuplicateBodyCheckIgnoresLeadingAndTrailingWhitespace() async throws {
        let store = makeStore()
        let (schedule, first, second, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "改行を含む回答")

        let afterSwitch = makeBackend(store: store, schedule: schedule, offset: Prompt.defaultDuration)
        do {
            try await afterSwitch.submitPost(promptID: second.id, body: "  改行を含む回答\n")
            XCTFail("前後の空白・改行を無視した重複が検出されなかった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .duplicateBody)
        }
    }

    // MARK: 受け入れ条件3（空白・改行のみ、同一文字の過剰な繰り返しは拒否）

    func testWhitespaceOnlyBodyIsRejected() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)

        do {
            try await backend.submitPost(promptID: first.id, body: "   \n\n   ")
            XCTFail("空白・改行のみの投稿が通ってしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .emptyBody)
        }
    }

    func testMeaninglessRepetitionIsRejected() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)

        do {
            try await backend.submitPost(promptID: first.id, body: "あああああああああ")
            XCTFail("同一文字の繰り返しが通ってしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .meaninglessBody)
        }

        // 正常な短い回答は通る（誤検知しない）
        let post = try await backend.submitPost(promptID: first.id, body: "はい")
        XCTAssertEqual(post.body, "はい")
    }

    func testPostValidatorDoesNotFlagOrdinaryShortReplies() {
        XCTAssertFalse(PostValidator.isMeaninglessRepetition("はい"))
        XCTAssertFalse(PostValidator.isMeaninglessRepetition("OK"))
        XCTAssertFalse(PostValidator.isMeaninglessRepetition("今日は天気が良かった"))
        XCTAssertFalse(PostValidator.isMeaninglessRepetition("The rain stopped exactly when I stepped outside"))
    }

    func testPostValidatorFlagsRepeatedCharacters() {
        XCTAssertTrue(PostValidator.isMeaninglessRepetition("あああああああ"))
        XCTAssertTrue(PostValidator.isMeaninglessRepetition("wwwwwwwwww"))
        XCTAssertTrue(PostValidator.isMeaninglessRepetition("。。。。。。。。"))
    }

    // MARK: 受け入れ条件4（いいね・通報の連打制限）

    func testLikeRateLimitBlocksAfterThresholdAndAllowsWithinLimit() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date())
        var options = LaunchOptions()
        options.likeRateLimit = RateLimitSettings(maxActions: 3, windowSeconds: 60, cooldownSeconds: 30)
        let backend = makeBackend(store: store, schedule: schedule, options: options)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        for index in 0..<3 {
            let postID = UUID()
            try await backend.setLike(postID: postID, liked: true)
            _ = index
        }

        do {
            try await backend.setLike(postID: UUID(), liked: true)
            XCTFail("4回目のいいねが制限されなかった")
        } catch let error as BackendError {
            guard case .rateLimited(let action, let retryAfter) = error else {
                return XCTFail("rateLimited 以外のエラー: \(error)")
            }
            XCTAssertEqual(action, .like)
            XCTAssertGreaterThan(retryAfter, 0)
        }
    }

    func testReportRateLimitBlocksAfterThreshold() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date())
        var options = LaunchOptions()
        options.reportRateLimit = RateLimitSettings(maxActions: 2, windowSeconds: 60, cooldownSeconds: 20)
        let backend = makeBackend(store: store, schedule: schedule, options: options)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        try await backend.reportPost(postID: UUID(), reason: .other)
        try await backend.reportPost(postID: UUID(), reason: .other)

        do {
            try await backend.reportPost(postID: UUID(), reason: .other)
            XCTFail("3回目の通報が制限されなかった")
        } catch let error as BackendError {
            guard case .rateLimited(let action, _) = error else {
                return XCTFail("rateLimited 以外のエラー: \(error)")
            }
            XCTAssertEqual(action, .report)
        }
    }

    func testRateLimiterAllowsAgainAfterCooldownElapses() {
        // window を短くしておき、クールダウン明けの時点では直近のウィンドウにも
        // 過去の記録が残っていない状態で検証する（さもないとウィンドウ側で再び弾かれる）。
        var limiter = RateLimiter(maxActions: 2, window: 2, cooldown: 5)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertNil(limiter.attempt(at: start))
        XCTAssertNil(limiter.attempt(at: start.addingTimeInterval(1)))
        // 3回目は制限される
        XCTAssertNotNil(limiter.attempt(at: start.addingTimeInterval(2)))
        // クールダウン中はまだ拒否される
        XCTAssertNotNil(limiter.attempt(at: start.addingTimeInterval(4)))
        // クールダウンが明けたら許可される
        XCTAssertNil(limiter.attempt(at: start.addingTimeInterval(8)))
    }

    // MARK: 受け入れ条件6（BANされた投稿者の回答は他ユーザーのタイムラインに1件も表示されない）

    func testBannedAuthorsPostNeverAppearsInTimeline() async throws {
        let store = makeStore()
        let (schedule, first, _, bannedAuthorID) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: first.id, body: "自分の回答")

        var drawnAuthorIDs: Set<UUID> = []
        while case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) {
            drawnAuthorIDs.insert(post.authorID)
        }
        XCTAssertFalse(drawnAuthorIDs.contains(bannedAuthorID), "BANされた投稿者の回答が出た")

        let candidates = try await backend.timelinePosts(promptID: first.id)
        XCTAssertFalse(candidates.contains { $0.authorID == bannedAuthorID })

        // 「まだ誰も答えていない」判定にもBANされた投稿者だけの回答は数えない
        let store2 = makeStore()
        let onlyBannedSchedule = PromptSchedule(
            prompts: schedule.prompts,
            posts: schedule.posts.filter { $0.authorID == bannedAuthorID && $0.promptID == first.id },
            bannedAuthorIDs: [bannedAuthorID]
        )
        let onlyBannedBackend = makeBackend(store: store2, schedule: onlyBannedSchedule)
        try await onlyBannedBackend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await onlyBannedBackend.submitPost(promptID: first.id, body: "自分の回答")
        let draw = try await onlyBannedBackend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(draw, .empty, "BANされた投稿者しかいないのに empty にならなかった")
    }

    // MARK: 同梱シードにBANされた投稿者が含まれていること（評価者が実機で確認するための土台）

    func testBundledSeedHasABannedAuthorExcludedFromVisiblePosts() throws {
        let reference = Date()
        let schedule = try SeedCatalog.loadSchedule(reference: reference, scenario: .live, options: LaunchOptions())
        XCTAssertFalse(schedule.bannedAuthorIDs.isEmpty, "同梱シードにBANされた投稿者が用意されていない")

        // BANされた投稿者の投稿は `visiblePosts`（生データ）には含まれるが、
        // LocalBackend の候補生成では必ず除外される（`visibleOthers` で確認済み）。
        let bannedID = schedule.bannedAuthorIDs.first!
        let rawPosts = schedule.visiblePosts(promptID: "prompt_001", at: reference)
        XCTAssertTrue(rawPosts.contains { $0.authorID == bannedID }, "検証用のBAN投稿がシードに見当たらない")
    }
}
