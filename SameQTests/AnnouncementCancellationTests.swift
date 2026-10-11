import XCTest
@testable import SameQ

/// メニュー → 通知 で開いたとき、読み込みがキャンセルされても「空」と確定せず、
/// 再読み込みで一覧が埋まることを確かめる。
final class AnnouncementCancellationTests: XCTestCase {

    @MainActor
    func test01_cancelledOnceThenSucceeds_returnsNilThenItems() async throws {
        let backend = CancellingOnceBackend(underlying: LocalBackend(), failure: URLError(.cancelled))
        let session = AppSession(backend: backend, clock: AppClock(offset: 0),
                                 translator: Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja"))

        let first = await session.loadAnnouncementsOrNilIfCancelled()
        XCTAssertNil(first, "キャンセルは空と確定させず nil を返す")
        let second = await session.loadAnnouncementsOrNilIfCancelled()
        XCTAssertEqual(second?.isEmpty, false, "再読み込みでは一覧が埋まる")
    }

    @MainActor
    func test02_cancellationError_isAlsoNil() async throws {
        let backend = CancellingOnceBackend(underlying: LocalBackend(), failure: CancellationError())
        let session = AppSession(backend: backend, clock: AppClock(offset: 0),
                                 translator: Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja"))
        let first = await session.loadAnnouncementsOrNilIfCancelled()
        XCTAssertNil(first)
    }

    @MainActor
    func test03_realFailure_stillEmpty() async throws {
        let backend = CancellingOnceBackend(underlying: LocalBackend(), failure: URLError(.notConnectedToInternet))
        let session = AppSession(backend: backend, clock: AppClock(offset: 0),
                                 translator: Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja"))
        let first = await session.loadAnnouncementsOrNilIfCancelled()
        XCTAssertEqual(first, [], "通信の本当の失敗は従来どおり空")
        let legacy = await session.loadAnnouncements()
        XCTAssertFalse(legacy.isEmpty, "2回目は成功")
    }
}

/// 最初の `announcements` 呼び出しだけ指定のエラーを投げ、他は内側へ委譲する。
private final class CancellingOnceBackend: Backend, @unchecked Sendable {
    private let underlying: Backend
    private let failure: Error
    private let lock = NSLock()
    private var didFail = false

    init(underlying: Backend, failure: Error) {
        self.underlying = underlying
        self.failure = failure
    }

    func announcements(locale: String) async throws -> [Announcement] {
        let shouldFail: Bool = lock.withLock {
            defer { didFail = true }
            return !didFail
        }
        if shouldFail { throw failure }
        return try await underlying.announcements(locale: locale)
    }



    // MARK: すべて `underlying` へ委譲（実装は LocalBackend なので問題なし）
    func isOnline() async -> Bool { await underlying.isOnline() }
    func ensureFreshSession() async { await underlying.ensureFreshSession() }
    func currentUser() async throws -> AppUser? { try await underlying.currentUser() }
    func createAnonymousUser(emoji: String, nickname: String?) async throws -> AppUser {
        try await underlying.createAnonymousUser(emoji: emoji, nickname: nickname)
    }
    func updateProfile(emoji: String, nickname: String?) async throws -> AppUser {
        try await underlying.updateProfile(emoji: emoji, nickname: nickname)
    }
    func deleteAccount() async throws { try await underlying.deleteAccount() }
    func promptState() async throws -> PromptState { try await underlying.promptState() }
    func myPost(promptID: String) async throws -> Post? { try await underlying.myPost(promptID: promptID) }
    func submitPost(promptID: String, body: String, decorations: [PostDecoration], isPlus: Bool) async throws -> Post {
        try await underlying.submitPost(promptID: promptID, body: body, decorations: decorations, isPlus: isPlus)
    }
    func removeMyPost(id: UUID) async throws { try await underlying.removeMyPost(id: id) }
    func recordTermsAcceptance(version: String, at date: Date) async throws {
        try await underlying.recordTermsAcceptance(version: version, at: date)
    }
    func termsAcceptance() async throws -> TermsAcceptance? { try await underlying.termsAcceptance() }
    func timelinePosts(promptID: String) async throws -> [Post] { try await underlying.timelinePosts(promptID: promptID) }
    func nextTimelinePost(promptID: String, excluding: Set<UUID>, autoMarkViewed: Bool) async throws -> TimelineDraw {
        try await underlying.nextTimelinePost(promptID: promptID, excluding: excluding, autoMarkViewed: autoMarkViewed)
    }
    func markPostViewed(_ postID: UUID) async throws { try await underlying.markPostViewed(postID) }
    func viewedPostIDs() async throws -> Set<UUID> { try await underlying.viewedPostIDs() }
    func likedPostIDs() async throws -> Set<UUID> { try await underlying.likedPostIDs() }
    func setLike(postID: UUID, liked: Bool) async throws { try await underlying.setLike(postID: postID, liked: liked) }
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int {
        try await underlying.receivedLikeCount(forPostID: postID)
    }
    func reportPost(postID: UUID, reason: ReportReason) async throws {
        try await underlying.reportPost(postID: postID, reason: reason)
    }
    func reportedPostIDs() async throws -> Set<UUID> { try await underlying.reportedPostIDs() }
    func blockAuthor(of post: Post) async throws { try await underlying.blockAuthor(of: post) }
    func unblockAuthor(id: UUID) async throws { try await underlying.unblockAuthor(id: id) }
    func blockedAuthors() async throws -> [BlockedAuthor] { try await underlying.blockedAuthors() }
    func discardedCandidatesCount() async throws -> Int { try await underlying.discardedCandidatesCount() }
    func currentServerSideStatus() async throws -> String { try await underlying.currentServerSideStatus() }
    func purgeExpiredSafetyLogs() async throws -> Int { try await underlying.purgeExpiredSafetyLogs() }
    func currentServerTime() async throws -> Date { try await underlying.currentServerTime() }
    func recordLanguageEncounter(languageCode: String) async throws {
        try await underlying.recordLanguageEncounter(languageCode: languageCode)
    }
    func topEncounteredLanguages(limit: Int) async throws -> [String] {
        try await underlying.topEncounteredLanguages(limit: limit)
    }
    func lastModelPrepareAttempt(sourceLanguageCode: String) async throws -> Date? {
        try await underlying.lastModelPrepareAttempt(sourceLanguageCode: sourceLanguageCode)
    }
    func recordModelPrepareAttempt(sourceLanguageCode: String, at date: Date) async throws {
        try await underlying.recordModelPrepareAttempt(sourceLanguageCode: sourceLanguageCode, at: date)
    }
}
