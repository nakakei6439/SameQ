import XCTest
@testable import SameQ

/// スプリント04（F13 / F14 / F15）の通報とブロックを、データ層で押さえる。
///
/// 画面操作は `SprintFourAcceptanceTests`（UI）で確認するが、
/// 「以後1件も出てこない」「解除すると戻る」は繰り返し回数を増やせるここでも検証する。
final class ReportBlockTests: XCTestCase {

    private let storeFileName = "report-block-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    /// お題2つ。`authors` 人の投稿者が**それぞれのお題に1件ずつ**答えている
    /// （1お題1投稿は守りつつ、同じ人が次のお題にも出てくる状態）。
    private func makeSchedule(
        reference: Date,
        authors: Int
    ) -> (PromptSchedule, Prompt, Prompt, [UUID]) {
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
        let authorIDs = (0..<authors).map { _ in UUID() }
        var posts: [Post] = []
        for (index, authorID) in authorIDs.enumerated() {
            posts.append(
                makePost(promptID: first.id, authorID: authorID, body: "p1の回答#\(index)", expiresAt: first.endsAt)
            )
            posts.append(
                makePost(promptID: second.id, authorID: authorID, body: "p2の回答#\(index)", expiresAt: second.endsAt)
            )
        }
        return (PromptSchedule(prompts: [first, second], posts: posts), first, second, authorIDs)
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

    private func makeBackend(store: LocalStore, schedule: PromptSchedule, offset: TimeInterval = 0) -> LocalBackend {
        LocalBackend(store: store, clock: AppClock(offset: offset), schedule: schedule, options: LaunchOptions())
    }

    /// アカウントを作って1つ目のお題に回答するところまで。
    private func prepared(
        store: LocalStore,
        schedule: PromptSchedule,
        prompt: Prompt
    ) async throws -> LocalBackend {
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")
        return backend
    }

    // MARK: 受け入れ条件 1・2（通報した回答は即座に消え、再起動しても戻らない）

    func testReportedPostLeavesTimelineAndStaysGoneAfterRelaunch() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 5)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let reported) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.reportPost(postID: reported.id, reason: .discrimination)

        let candidates = try await backend.timelinePosts(promptID: first.id)
        XCTAssertFalse(candidates.contains(reported), "通報した回答が候補に残っている")
        let reportedIDs = try await backend.reportedPostIDs()
        XCTAssertEqual(reportedIDs, [reported.id])

        // 起動し直しても戻らない（既読とは別に、通報の記録で外れている）
        var options = LaunchOptions()
        options.resetsViewed = true          // 既読を消しても再表示されないことを確かめる
        let relaunched = LocalBackend(
            store: store,
            clock: AppClock(offset: 0),
            schedule: schedule,
            options: options
        )
        for _ in 1...4 {
            guard case .post(let post) = try await relaunched.nextTimelinePost(promptID: first.id) else {
                return XCTFail("再起動後に回答が引けなかった")
            }
            XCTAssertNotEqual(post.id, reported.id, "通報した回答が再び出た")
        }
        let afterAll = try await relaunched.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterAll, .exhausted)
    }

    /// 同じ回答を二重に通報しても記録は増えない（連打しても壊れない）。
    func testReportingTwiceKeepsSingleRecord() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 3)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.reportPost(postID: post.id, reason: .sexual)
        try await backend.reportPost(postID: post.id, reason: .crime)
        let reportedIDs = try await backend.reportedPostIDs()
        XCTAssertEqual(reportedIDs.count, 1)
    }

    // MARK: 受け入れ条件 3（ブロックした人の回答は以後1件も出ない）

    func testBlockedAuthorNeverAppearsAgainIncludingNextPrompt() async throws {
        let store = makeStore()
        let (schedule, first, second, _) = makeSchedule(reference: Date(), authors: 6)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let target) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.blockAuthor(of: target)

        // 同じお題で最後まで引いても出てこない
        while case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) {
            XCTAssertNotEqual(post.authorID, target.authorID, "ブロックした人の回答が出た")
        }
        let remaining = try await backend.timelinePosts(promptID: first.id)
        XCTAssertFalse(remaining.contains { $0.authorID == target.authorID })

        // 次のお題（同じ人が別の回答を書いている）でも出てこない
        let afterSwitch = makeBackend(store: store, schedule: schedule, offset: Prompt.defaultDuration)
        try await afterSwitch.submitPost(promptID: second.id, body: "2つ目のお題への自分の回答")
        while case .post(let post) = try await afterSwitch.nextTimelinePost(promptID: second.id) {
            XCTAssertNotEqual(post.authorID, target.authorID, "次のお題でブロックした人の回答が出た")
        }
        let stillBlocked = try await afterSwitch.blockedAuthors()
        XCTAssertEqual(stillBlocked.count, 1, "お題が変わってもブロックは残る")
    }

    // MARK: 受け入れ条件 4（解除すると再び表示対象に戻る）

    func testUnblockRestoresTheAuthorsAnswer() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 4)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let target) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.blockAuthor(of: target)
        let whileBlocked = try await backend.timelinePosts(promptID: first.id)
        XCTAssertFalse(whileBlocked.contains(target))

        try await backend.unblockAuthor(id: target.authorID)
        let afterUnblock = try await backend.timelinePosts(promptID: first.id)
        XCTAssertTrue(afterUnblock.contains(target), "解除しても候補に戻っていない")
        let blockedList = try await backend.blockedAuthors()
        XCTAssertTrue(blockedList.isEmpty)

        // 「表示対象に戻る」＝実際にもう一度引ける（ブロックした回答は既読にしない）
        var drawn: Set<UUID> = []
        while case .post(let post) = try await backend.nextTimelinePost(promptID: first.id) {
            drawn.insert(post.id)
        }
        XCTAssertTrue(drawn.contains(target.id), "解除した人の回答が引けない")
    }

    // MARK: 受け入れ条件（評価者注記）最後の1件をブロックしたときの落ち方

    func testBlockingTheLastRemainingAnswerFallsBackToEndState() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 1)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let only) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.blockAuthor(of: only)
        // 誰も答えていないわけではないので `.empty` ではなく `.exhausted`（読み切り表示）に落とす
        let afterBlock = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterBlock, .exhausted)
        let candidates = try await backend.timelinePosts(promptID: first.id)
        XCTAssertEqual(candidates.count, 0)

        // 通報でも同じ（クラッシュも無限ループもしない）
        try await backend.unblockAuthor(id: only.authorID)
        try await backend.reportPost(postID: only.id, reason: .other)
        let afterReport = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(afterReport, .exhausted)
    }

    /// 自分以外の回答が最初から0件なら、これまでどおり `.empty`（まだ誰も答えていない）。
    func testEmptyStateIsUnchangedWhenNobodyElseAnswered() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 0)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)
        let draw = try await backend.nextTimelinePost(promptID: first.id)
        XCTAssertEqual(draw, .empty)
    }

    // MARK: 受け入れ条件 5（相手を特定できる情報を持たない）

    func testBlockedAuthorRecordHoldsOnlyEmojiAndNickname() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 3)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let target) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.blockAuthor(of: target)
        guard let entry = try await backend.blockedAuthors().first else {
            return XCTFail("ブロック一覧が空")
        }
        XCTAssertEqual(entry.emoji, target.authorEmoji)
        XCTAssertEqual(entry.nickname, target.displayNickname)

        // 国・言語・本文・投稿時刻を持ち込んでいないこと（一覧から属性を推測させない）
        let fields = Mirror(reflecting: entry).children.compactMap(\.label)
        XCTAssertEqual(Set(fields), ["id", "emoji", "nickname", "blockedAt"])
    }

    // MARK: 永続と掃除

    func testBlocksSurviveRelaunchAndReportsAreDroppedWhenPostsExpire() async throws {
        let store = makeStore()
        let (schedule, first, _, _) = makeSchedule(reference: Date(), authors: 4)
        let backend = try await prepared(store: store, schedule: schedule, prompt: first)

        guard case .post(let blocked) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("1件目が引けなかった")
        }
        guard case .post(let reported) = try await backend.nextTimelinePost(promptID: first.id) else {
            return XCTFail("2件目が引けなかった")
        }
        try await backend.blockAuthor(of: blocked)
        try await backend.reportPost(postID: reported.id, reason: .politics)

        let relaunched = makeBackend(store: store, schedule: schedule)
        let restoredBlocks = try await relaunched.blockedAuthors()
        XCTAssertEqual(restoredBlocks.map(\.id), [blocked.authorID])
        let restoredReports = try await relaunched.reportedPostIDs()
        XCTAssertEqual(restoredReports, [reported.id])

        // お題が終われば、その回答への通報の記録は端末から落ちる（履歴を持たない）。
        // ブロックは相手に対するものなので残る。
        let afterEnd = makeBackend(store: store, schedule: schedule, offset: Prompt.defaultDuration)
        let reportsAfterEnd = try await afterEnd.reportedPostIDs()
        XCTAssertTrue(reportsAfterEnd.isEmpty)
        let blocksAfterEnd = try await afterEnd.blockedAuthors()
        XCTAssertEqual(blocksAfterEnd.map(\.id), [blocked.authorID])
    }

    /// 旧バージョン（schemaVersion 2）の保存ファイルからでも、アカウントを消さずに読める。
    func testMigratesFromSchemaVersionTwo() throws {
        let store = LocalStore(fileName: storeFileName)
        let user = AppUser(id: UUID(), emoji: "🌙", nickname: "Mizuki", createdAt: Date())
        let legacy = """
        {
          "schemaVersion": 2,
          "user": {
            "id": "\(user.id.uuidString)",
            "emoji": "🌙",
            "nickname": "Mizuki",
            "createdAt": "\(ISO8601DateFormatter().string(from: user.createdAt))"
          },
          "myPosts": [],
          "likedPostIDs": [],
          "viewedPostIDs": []
        }
        """
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let url = base.appendingPathComponent("SameQ", isDirectory: true)
            .appendingPathComponent(storeFileName)
        try legacy.data(using: .utf8)?.write(to: url)

        let loaded = store.load()
        XCTAssertEqual(loaded.user?.id, user.id, "移行でアカウントが消えてはいけない")
        XCTAssertTrue(loaded.reports.isEmpty)
        XCTAssertTrue(loaded.blockedAuthors.isEmpty)

        // 書き戻すと現在のバージョンに揃う
        try store.save(loaded)
        XCTAssertEqual(store.load().schemaVersion, PersistedState.currentSchemaVersion)
    }
}
