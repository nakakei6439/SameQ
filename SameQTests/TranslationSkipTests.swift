import XCTest
@testable import SameQ

/// スプリント06 attempt 2 の修正（バグ4: 翻訳できずスキップした回答が恒久的に既読になる）を
/// `LocalBackend` の層で検証する。
///
/// `AppSession.drawNextPost` は「翻訳が確定してから既読にする」ため、`Backend` 側に
/// `excluding`（この巡回だけの一時的な除外）・`autoMarkViewed`（既読にするかを呼び出し側へ
/// 委ねる）・`markPostViewed`（確定した時点で既読にする）を用意した。ここでは
/// `Translator` を使わずに、その3つの組み合わせが「一時的な失敗は既読にしない・
/// 恒久的な失敗（または成功）は既読にする」を満たすことを確認する。
final class TranslationSkipTests: XCTestCase {

    private let storeFileName = "translation-skip-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeSchedule(reference: Date, otherCount: Int) -> (PromptSchedule, Prompt) {
        let prompt = Prompt(
            id: "p1",
            text: "お題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600)
        )
        let posts = (1...max(otherCount, 1)).prefix(otherCount).map {
            Post(
                id: UUID(),
                promptID: prompt.id,
                authorID: UUID(),
                authorEmoji: "🐢",
                authorNickname: nil,
                body: "回答#\($0)",
                bodyLanguage: "en",
                createdAt: prompt.endsAt.addingTimeInterval(-7200),
                expiresAt: prompt.endsAt
            )
        }
        return (PromptSchedule(prompts: [prompt], posts: posts), prompt)
    }

    private func makeBackend(store: LocalStore, schedule: PromptSchedule) -> LocalBackend {
        LocalBackend(store: store, clock: AppClock(offset: 0), schedule: schedule, options: LaunchOptions())
    }

    /// 一時的な失敗（`autoMarkViewed: false` のまま `markPostViewed` を呼ばない）は
    /// 既読にならず、`excluding` に入れなければ何度でも同じ回答が引ける（あとで再挑戦できる）。
    func testTemporaryFailureIsNotMarkedViewed() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, otherCount: 3)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [], autoMarkViewed: false
        ) else {
            return XCTFail("1件目が引けなかった")
        }
        // 「翻訳が一時的に失敗した」を模して、既読にしない。
        let viewedAfterTemporaryFailure = try await backend.viewedPostIDs()
        XCTAssertFalse(viewedAfterTemporaryFailure.contains(post.id), "一時的な失敗を既読にしてはいけない")

        // 除外していなければ、同じ回答がまた引ける（再挑戦できる）。
        guard case .post(let sameOrOther) = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [], autoMarkViewed: false
        ) else {
            return XCTFail("2回目が引けなかった")
        }
        _ = sameOrOther // 未読集合が変わっていないので同じ回答が出ることもある。件数の担保は下のテストで。

        // あとで実際に表示できたと確定したら、そこで初めて既読にする。
        try await backend.markPostViewed(post.id)
        let viewedAfterSuccess = try await backend.viewedPostIDs()
        XCTAssertTrue(viewedAfterSuccess.contains(post.id), "確定した時点で既読になっていない")
    }

    /// `excluding` に入れた投稿は、既読になっていなくてもその巡回では選ばれない
    /// （無限ループの防止）。除外候補が尽きれば `.exhausted` になる。
    func testExcludingSetKeepsSameTemporaryFailureFromRepeating() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [], autoMarkViewed: false
        ) else {
            return XCTFail("1件目が引けなかった")
        }
        // まだ既読にはしていない（一時的な失敗）が、この巡回では引き直させない。
        let draw = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [post.id], autoMarkViewed: false
        )
        XCTAssertEqual(draw, .exhausted, "唯一の候補を除外したら、他人の回答が1件も無いのと同じ扱いになるはず")
        // 既読としては記録されていない（永続化されていない一時的な除外なので、次の巡回では再挑戦できる）。
        let viewed = try await backend.viewedPostIDs()
        XCTAssertFalse(viewed.contains(post.id))
    }

    /// 恒久的な失敗（非対応言語）は既読にしてよい。マークすると、以後の巡回では出てこない。
    func testPermanentFailureCanBeMarkedViewedAndNeverReappears() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [], autoMarkViewed: false
        ) else {
            return XCTFail("1件目が引けなかった")
        }
        // 「非対応言語だと判明した」を模して、恒久的な失敗として既読にする。
        try await backend.markPostViewed(post.id)

        let afterMark = try await backend.nextTimelinePost(
            promptID: prompt.id, excluding: [], autoMarkViewed: false
        )
        XCTAssertEqual(afterMark, .exhausted, "恒久的な失敗として既読にした回答は二度と出てこないはず")
    }

    /// `nextTimelinePost(promptID:)`（引数省略のオーバーロード）は、スプリント01〜05から
    /// 変わらず「返した時点で既読にする」動作のまま（既存の呼び出し元・既存テストの回帰確認）。
    func testDefaultOverloadStillAutoMarksViewed() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(promptID: prompt.id) else {
            return XCTFail("1件目が引けなかった")
        }
        let viewed = try await backend.viewedPostIDs()
        XCTAssertTrue(viewed.contains(post.id), "デフォルトの呼び出しは従来どおり即座に既読にするはず")
    }

    /// `markPostViewed` を既読済みの投稿へもう一度呼んでも壊れない（冪等）。
    func testMarkPostViewedIsIdempotent() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, otherCount: 1)
        let backend = makeBackend(store: store, schedule: schedule)
        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        try await backend.submitPost(promptID: prompt.id, body: "自分の回答")

        guard case .post(let post) = try await backend.nextTimelinePost(promptID: prompt.id) else {
            return XCTFail("1件目が引けなかった")
        }
        try await backend.markPostViewed(post.id)
        try await backend.markPostViewed(post.id)
        let viewed = try await backend.viewedPostIDs()
        XCTAssertEqual(viewed.filter { $0 == post.id }.count, 1, "重複して記録されてはいけない")
    }
}
