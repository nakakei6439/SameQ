import XCTest
@testable import SameQ

/// `AppSession` を通した翻訳の一連の流れ（F18〜F22）を、疑似翻訳モード
/// （`Translator(fakeTranslate: true, ...)`）で確定的に検証する。
///
/// このシミュレータでは Apple Translation が使えないため（evaluator 確認済み）、
/// 実際の `TranslationSession` 経路（バグ1の核心）は `SessionRequestQueueTests` で
/// フレームワーク非依存に検証している。ここでは疑似翻訳を挟むことで、
/// `AppSession.drawNextPost` / `syncPromptTranslation` が「表示切り替え」
/// 「非対応言語のスキップ」「既読のタイミング」を正しく実装できているかを見る。
final class AppSessionTranslationTests: XCTestCase {

    private let storeFileName = "app-session-translation-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makePost(promptID: String, body: String, bodyLanguage: String, expiresAt: Date) -> Post {
        Post(
            id: UUID(),
            promptID: promptID,
            authorID: UUID(),
            authorEmoji: "🐢",
            authorNickname: nil,
            body: body,
            bodyLanguage: bodyLanguage,
            createdAt: expiresAt.addingTimeInterval(-7200),
            expiresAt: expiresAt
        )
    }

    /// バグ3・お題の翻訳: お題は端末言語（ここでは "en"）へ翻訳された表示用の文字列になる。
    @MainActor
    func testPromptDisplayTextUsesTranslatedValue() async throws {
        let reference = Date()
        let prompt = Prompt(
            id: "p1",
            text: "今日、思わず笑ってしまったことは何ですか？",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600),
            language: "ja"
        )
        let schedule = PromptSchedule(prompts: [prompt], posts: [])
        let backend = LocalBackend(store: makeStore(), clock: AppClock(offset: 0), schedule: schedule, options: LaunchOptions())
        let translator = Translator(fakeTranslate: true, preferredLanguageIdentifier: "en")
        let session = AppSession(backend: backend, clock: AppClock(offset: 0), translator: translator)

        await session.start()
        await session.completeOnboarding(emoji: "🌙", nickname: nil)

        // 翻訳確定まで少し待つ（疑似モードも非同期のまま。実装は `promptDisplayText` が
        // nil のうちは「準備中…」を出す設計なので、ここでは確定後の値だけを見る）。
        var attempts = 0
        while session.promptDisplayText == nil, attempts < 50 {
            try await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
        XCTAssertEqual(session.promptDisplayText, "[EN] 今日、思わず笑ってしまったことは何ですか？")
    }

    /// バグ1/4の統合確認: 同じ原文言語（"en"）が連続しても `advanceTimeline` は毎回すぐ完了し、
    /// 表示された回答はすべて既読になる（＝翻訳経路が固まらず、成功分だけ既読が積み上がる）。
    @MainActor
    func testConsecutiveSameLanguageAnswersDoNotStallTimeline() async throws {
        let reference = Date()
        let prompt = Prompt(
            id: "p1",
            text: "お題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600),
            language: "ja"
        )
        // すべて "en"（端末言語 "ja" とは異なる）の回答を10件用意する。
        // 修正前の設計（同一言語ペアの2件目で固着）なら、1件目のあとで止まっていたはずの状況。
        let posts = (1...10).map {
            makePost(promptID: prompt.id, body: "answer #\($0)", bodyLanguage: "en", expiresAt: prompt.endsAt)
        }
        let schedule = PromptSchedule(prompts: [prompt], posts: posts)
        let backend = LocalBackend(store: makeStore(), clock: AppClock(offset: 0), schedule: schedule, options: LaunchOptions())
        let translator = Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja")
        let session = AppSession(backend: backend, clock: AppClock(offset: 0), translator: translator)

        await session.start()
        await session.completeOnboarding(emoji: "🌙", nickname: nil)
        // `submit(body:)` は成功すると内部で `openTimeline()` を呼ぶ（1件目の draw を含む）ので、
        // ここで重ねて `openTimeline()` を呼ばない（呼ぶと2連続で draw して1件を見落とす）。
        await session.submit(body: "自分の回答")

        // 未読からランダムに1件ずつ引くので順序は保証されない（F11）。
        // ここでは「毎回、疑似翻訳済みの本文が表示され、途中で止まらず全件出せる」ことだけを見る。
        var shownIDs: Set<UUID> = []
        for _ in 0..<10 {
            guard case .post(let post) = session.timelineContent else { break }
            XCTAssertTrue(post.body.hasPrefix("[JA] answer #"), "疑似翻訳の結果が表示に反映されていない: \(post.body)")
            shownIDs.insert(post.id)
            await session.advanceTimeline()
        }
        XCTAssertEqual(shownIDs.count, 10, "同じ言語ペアが連続しても、途中で止まらず全件表示できるはず")
        if case .exhausted = session.timelineContent {} else {
            XCTFail("10件すべて表示したら読み切りになるはず: \(session.timelineContent)")
        }

        let viewed = try await backend.viewedPostIDs()
        XCTAssertEqual(viewed.count, 10, "表示できた回答はすべて既読になっているはず")
    }

    /// バグ4: 恒久的に非対応の回答（`zxx`）はタイムラインに一度も現れず、既読として消費されて
    /// 次の巡回でも二度と出てこない。翻訳できる回答はその裏でちゃんと表示される。
    @MainActor
    func testUntranslatableMarkerNeverAppearsAndIsPermanentlySkipped() async throws {
        let reference = Date()
        let prompt = Prompt(
            id: "p1",
            text: "お題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(Prompt.defaultDuration - 3600),
            language: "ja"
        )
        let untranslatable = makePost(
            promptID: prompt.id,
            body: "sameQ_untranslatable_test_marker",
            bodyLanguage: "zxx",
            expiresAt: prompt.endsAt
        )
        let translatable = makePost(promptID: prompt.id, body: "readable answer", bodyLanguage: "en", expiresAt: prompt.endsAt)
        let schedule = PromptSchedule(prompts: [prompt], posts: [untranslatable, translatable])
        let backend = LocalBackend(store: makeStore(), clock: AppClock(offset: 0), schedule: schedule, options: LaunchOptions())
        let translator = Translator(fakeTranslate: true, preferredLanguageIdentifier: "ja")
        let session = AppSession(backend: backend, clock: AppClock(offset: 0), translator: translator)

        await session.start()
        await session.completeOnboarding(emoji: "🌙", nickname: nil)
        // `submit(body:)` が内部で `openTimeline()` を呼ぶ（上のテストと同じ理由で重ねて呼ばない）。
        await session.submit(body: "自分の回答")

        guard case .post(let post) = session.timelineContent else {
            return XCTFail("翻訳可能な回答が表示されるはず: \(session.timelineContent)")
        }
        XCTAssertEqual(post.id, translatable.id, "非対応言語の回答は一度も表示されてはいけない")

        await session.advanceTimeline()
        if case .exhausted = session.timelineContent {} else {
            XCTFail("残りは非対応言語だけなので読み切りになるはず: \(session.timelineContent)")
        }

        let viewed = try await backend.viewedPostIDs()
        XCTAssertTrue(viewed.contains(untranslatable.id), "非対応言語は恒久的スキップとして既読になっているはず")
        XCTAssertTrue(viewed.contains(translatable.id))
    }
}
