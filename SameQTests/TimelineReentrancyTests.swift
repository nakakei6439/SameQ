import XCTest
@testable import SameQ

/// `AppSession.openTimeline()` の再入防止（2026-09-22 の実機事故の回帰テスト）。
///
/// ## 何が起きたか
///
/// 削除リクエストが返らず UI が「削除しています…」のまま固まった状態で、利用者が
/// 「世界の回答を読む」ボタンを連打した。`openTimeline()` には
/// 「すでに開いているか」のガードが無かったため、**1タップにつき1件が
/// `drawNextPost()` で引かれて既読になり、画面には一度も出ないまま消えた**。
/// 本番DBの `viewed_posts` に7秒間で5件の既読が並び、その日の回答が全部尽きた。
///
/// 連打は「反応しないボタン」に対するごく自然な操作なので、押せてしまう以上は
/// セッション側で止める必要がある。
final class TimelineReentrancyTests: XCTestCase {

    private let storeFileName = "timeline-reentrancy-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    /// 端末言語と同じ言語の投稿だけを用意する（翻訳を挟まず必ず表示できる状態にして、
    /// 「既読が増えるかどうか」だけを見る）。
    private func makeSchedule(reference: Date, postCount: Int) -> PromptSchedule {
        let prompt = Prompt(
            id: "p1",
            text: "今日、思わず笑ってしまったことは何ですか？",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600),
            language: "ja"
        )
        let posts = (1...postCount).map { number in
            Post(
                id: UUID(),
                promptID: prompt.id,
                authorID: UUID(),
                authorEmoji: "🐢",
                authorNickname: nil,
                body: "回答\(number)",
                bodyLanguage: "ja",
                createdAt: reference.addingTimeInterval(-1800),
                expiresAt: prompt.endsAt
            )
        }
        return PromptSchedule(prompts: [prompt], posts: posts)
    }

    @MainActor
    func test01_repeatedOpenTimelineDoesNotConsumeExtraPosts() async throws {
        let reference = Date()
        let backend = LocalBackend(
            store: makeStore(),
            clock: AppClock(offset: 0),
            schedule: makeSchedule(reference: reference, postCount: 5),
            options: LaunchOptions()
        )
        let translator = Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja")
        let session = AppSession(backend: backend, clock: AppClock(offset: 0), translator: translator)

        await session.start()
        await session.completeOnboarding(emoji: "🌙", nickname: nil)
        // `submit(body:)` が裏で `openTimeline()` を起動する。
        await session.submit(body: "自分の回答")
        await session.waitForPendingTimelineOpen()

        guard case .post = session.timelineContent else {
            return XCTFail("1件目が表示されるはず: \(session.timelineContent)")
        }
        let viewedAfterFirstOpen = try await backend.viewedPostIDs().count
        XCTAssertEqual(viewedAfterFirstOpen, 1, "開いた時点で既読は1件だけ")

        // ここが本題。固まったと思った利用者が連打する状況を再現する。
        for _ in 1...4 {
            await session.openTimeline()
        }

        let viewedAfterTaps = try await backend.viewedPostIDs().count
        XCTAssertEqual(
            viewedAfterTaps,
            1,
            "連打しても既読が増えてはいけない（画面に出ないまま回答が消費される事故の再発）"
        )
        XCTAssertTrue(session.isTimelinePresented, "開いたままであること")
    }

    /// 閉じたあとは再び開ける（ガードが強すぎて開かなくなっていないか）。
    @MainActor
    func test02_timelineCanBeReopenedAfterClosing() async throws {
        let reference = Date()
        let backend = LocalBackend(
            store: makeStore(),
            clock: AppClock(offset: 0),
            schedule: makeSchedule(reference: reference, postCount: 5),
            options: LaunchOptions()
        )
        let translator = Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja")
        let session = AppSession(backend: backend, clock: AppClock(offset: 0), translator: translator)

        await session.start()
        await session.completeOnboarding(emoji: "🌙", nickname: nil)
        await session.submit(body: "自分の回答")
        await session.waitForPendingTimelineOpen()
        XCTAssertTrue(session.isTimelinePresented)

        session.closeTimeline()
        await session.openTimeline()
        XCTAssertTrue(session.isTimelinePresented, "閉じたあとは開き直せる")
    }
}
