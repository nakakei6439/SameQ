import XCTest
@testable import SameQ

/// 自分の回答の削除（F49）と、規約同意の記録（F53）をデータ層で押さえる。
///
/// 「削除した回答が他人から見えなくなる」ことの実地確認は、別端末・別アカウントで
/// 行う必要があるため UI/評価側の担当（スプリント20の評価者への注記）。
/// ここでは「削除の結果として何が残り、何ができなくなるか」を固定する。
final class PostRemovalTests: XCTestCase {

    private let storeFileName = "post-removal-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeSchedule(reference: Date) -> (PromptSchedule, Prompt) {
        let prompt = Prompt(
            id: "p1",
            text: "今日のお題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600)
        )
        // 他人の回答を1件だけ置いておく（削除後もタイムラインが読めることの確認用）。
        let other = Post(
            id: UUID(),
            promptID: prompt.id,
            authorID: UUID(),
            authorEmoji: "🐢",
            authorNickname: "Kai",
            body: "他の人の回答",
            bodyLanguage: "ja",
            createdAt: reference.addingTimeInterval(-1800),
            expiresAt: prompt.endsAt
        )
        return (PromptSchedule(prompts: [prompt], posts: [other]), prompt)
    }

    private func makeBackend(store: LocalStore, schedule: PromptSchedule) -> LocalBackend {
        LocalBackend(store: store, clock: AppClock(), schedule: schedule, options: LaunchOptions())
    }

    private func prepared(store: LocalStore, schedule: PromptSchedule, prompt: Prompt) async throws -> LocalBackend {
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")
        return backend
    }

    // MARK: 削除の結果

    /// 削除しても `myPost` は nil にならず、`.removed` として返る。
    /// nil にすると呼び出し側が「未回答」と取り違えて入力欄に戻してしまう。
    func testRemovedPostIsStillReturnedWithRemovedStatus() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)

        let before = try await backend.myPost(promptID: prompt.id)
        XCTAssertEqual(before?.status, .visible)

        let beforeID = try XCTUnwrap(before?.id)
        try await backend.removeMyPost(id: beforeID)

        let after = try await backend.myPost(promptID: prompt.id)
        XCTAssertNotNil(after, "削除しても『回答した』という事実は残る")
        XCTAssertEqual(after?.status, .removed)
        XCTAssertTrue(after?.isRemovedByAuthor ?? false)
    }

    /// 削除した回答は、期限内でも「見せてよい回答」ではなくなる。
    func testRemovedPostIsNoLongerVisible() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)

        try await backend.removeMyPost(id: post.id)

        let removedFetched = try await backend.myPost(promptID: prompt.id)
        let removed = try XCTUnwrap(removedFetched)
        XCTAssertFalse(removed.isVisible(at: Date()), "削除した回答は期限内でも見せない")
    }

    /// 削除しても、その日の世界の回答は読み続けられる（置いた前提1）。
    func testWorldTimelineStaysReadableAfterRemoval() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)

        try await backend.removeMyPost(id: post.id)

        let others = try await backend.timelinePosts(promptID: prompt.id)
        XCTAssertEqual(others.count, 1, "削除しても他人の回答は読める（消したら世界も閉じる、にはしない）")
    }

    /// 削除したあと、同じお題には再回答できない（置いた前提1）。
    func testCannotAnswerAgainAfterRemoval() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)

        try await backend.removeMyPost(id: post.id)

        do {
            try await backend.submitPost(promptID: prompt.id, body: "書き直した回答")
            XCTFail("削除後に同じお題へ再回答できてしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .alreadyAnswered)
        }
    }

    /// 取り消した文面で連投判定に引っかからないよう、`lastPostBody` は消す。
    /// （同じお題への再投稿は `alreadyAnswered` が防ぐので、これで穴は開かない）
    func testLastPostBodyIsClearedSoTheWordingIsNotLockedForever() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)

        try await backend.removeMyPost(id: post.id)

        XCTAssertNil(store.load().lastPostBody)
    }

    /// 二重削除は弾く。
    func testRemovingTwiceThrows() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)

        try await backend.removeMyPost(id: post.id)

        do {
            try await backend.removeMyPost(id: post.id)
            XCTFail("削除済みの回答をもう一度削除できてしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .postNotFound)
        }
    }

    /// 再起動（同じ `store` から新しい `LocalBackend`）しても削除は残る。
    func testRemovalSurvivesRelaunch() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)
        try await backend.removeMyPost(id: post.id)

        let relaunched = makeBackend(store: store, schedule: schedule)
        let after = try await relaunched.myPost(promptID: prompt.id)
        XCTAssertEqual(after?.status, .removed)
    }

    /// プロフィールを変えただけで削除済みの回答が復活しないこと。
    /// `updateProfile` は自分の過去投稿を作り直すので、状態の引き継ぎ漏れが起きやすい。
    func testUpdatingProfileDoesNotResurrectRemovedPost() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = try await prepared(store: store, schedule: schedule, prompt: prompt)
        let fetched = try await backend.myPost(promptID: prompt.id)
        let post = try XCTUnwrap(fetched)
        try await backend.removeMyPost(id: post.id)

        try await backend.updateProfile(emoji: "🔥", nickname: "あたらしい名前")

        let after = try await backend.myPost(promptID: prompt.id)
        XCTAssertEqual(after?.status, .removed, "プロフィール更新で削除が取り消されてはいけない")
    }

    // MARK: 禁止表現（F48）がデータ層で効いていること

    func testProhibitedBodyIsRejectedOnSubmit() async throws {
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)

        do {
            try await backend.submitPost(promptID: prompt.id, body: "お前なんか死ね")
            XCTFail("禁止表現を含む回答が投稿できてしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .prohibitedBody)
        }
        let saved = try await backend.myPost(promptID: prompt.id)
        XCTAssertNil(saved, "弾かれた回答は保存されない")
    }

    func testProhibitedNicknameIsRejected() async throws {
        let store = makeStore()
        let (schedule, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)

        do {
            try await backend.createAnonymousUser(emoji: "🌙", nickname: "死ね")
            XCTFail("禁止表現を含むニックネームで登録できてしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .prohibitedNickname)
        }
    }

    func testProhibitedNicknameIsRejectedOnProfileUpdate() async throws {
        let store = makeStore()
        let (schedule, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: "ふつうの名前")

        do {
            try await backend.updateProfile(emoji: "🌙", nickname: "キチガイ")
            XCTFail("禁止表現を含むニックネームへ変更できてしまった")
        } catch let error as BackendError {
            XCTAssertEqual(error, .prohibitedNickname)
        }
    }

    // MARK: 規約への同意（F53）

    func testTermsAcceptanceIsRecordedAndSurvivesRelaunch() async throws {
        let store = makeStore()
        let (schedule, _) = makeSchedule(reference: Date())
        let backend = makeBackend(store: store, schedule: schedule)

        let noAcceptance = try await backend.termsAcceptance()
        XCTAssertNil(noAcceptance)

        let now = Date()
        try await backend.recordTermsAcceptance(version: LegalText.version, at: now)

        let relaunched = makeBackend(store: store, schedule: schedule)
        let stored = try await relaunched.termsAcceptance()
        XCTAssertEqual(stored?.version, LegalText.version)
        XCTAssertEqual(
            stored?.acceptedAt.timeIntervalSince1970 ?? 0,
            now.timeIntervalSince1970,
            accuracy: 1
        )
    }
}
