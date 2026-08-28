import XCTest
@testable import SameQ

/// F41（スプリント17）「直近よく出会う言語の先読み」のうち、
/// `Backend.recordLanguageEncounter` と `Backend.topEncounteredLanguages` の
/// 永続化・カウント・トップN選出が spec を満たしていることを検証する。
///
/// 仕様上の受け入れ条件1「最大3件まで」、4「アプリを使っていない間に済ませる」の
/// 素データとなる encounter カウンタが正しく回るかを単体テストとして担保する。
final class LanguageEncounterTests: XCTestCase {

    private let storeFileName = "language-encounter-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeBackend(store: LocalStore, schedule: PromptSchedule = PromptSchedule(prompts: [], posts: [])) -> LocalBackend {
        LocalBackend(
            store: store,
            clock: AppClock(offset: 0),
            schedule: schedule,
            options: LaunchOptions()
        )
    }

    // MARK: カウンタの基本動作

    /// 同じ言語を複数回記録すると回数が増える（最低要件）。
    func testRecordLanguageEncounterIncrementsCounter() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertEqual(top, ["fr"], "fr が3回記録された時点でトップ1は fr だけ")
    }

    /// 大文字小文字が混じっても、内部では小文字に正規化して同一視する
    /// （仕様: 言語コードは小文字で扱う。`bodyLanguage.lowercased()` を渡す呼び出し側と整合）。
    func testRecordLanguageEncounterNormalisesCase() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "FR")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "Fr")
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertEqual(top, ["fr"], "大文字小文字の違いは同じ言語として合算される")
    }

    /// 複数の言語を混ぜても回数が独立して数えられる。
    func testRecordLanguageEncounterCountsPerLanguage() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "es")
        try await backend.recordLanguageEncounter(languageCode: "de")
        try await backend.recordLanguageEncounter(languageCode: "de")
        try await backend.recordLanguageEncounter(languageCode: "de")
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertEqual(top, ["de", "fr", "es"], "de(3回) > fr(2回) > es(1回) の降順")
    }

    /// 空文字や異常に長い言語コードは無視する（pre-fetch の入力として不正なため）。
    /// spec の F41 に具体的な上限は無いが、ISO 639 系コードは通常 2〜8 文字。
    /// 16 文字を超える異常値は将来の保守性のため静かに捨てる。
    func testRecordLanguageEncounterIgnoresInvalidCodes() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "")
        try await backend.recordLanguageEncounter(languageCode: String(repeating: "x", count: 64))
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertTrue(top.isEmpty, "無効な言語コードはカウントされず、トップ言語も空")
    }

    // MARK: top-N 選出

    /// 受け入れ条件1「最大3件まで」: 6 言語を記録しても 3 件しか返らない。
    func testTopEncounteredLanguagesRespectsLimit() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        let languages = ["de", "es", "fr", "it", "pl", "ru"]
        for (index, language) in languages.enumerated() {
            // 言語ごとに index+1 回記録する（長いほど多い＝昇順）
            for _ in 0...index {
                try await backend.recordLanguageEncounter(languageCode: language)
            }
        }
        let top3 = try await backend.topEncounteredLanguages(limit: 3)
        XCTAssertEqual(top3.count, 3, "limit=3 なので必ず3件以下")
        // ru(6) > pl(5) > it(4) > es(3) > fr(2) > de(1)
        XCTAssertEqual(Set(top3), Set(["ru", "pl", "it"]), "トップ3は回数上位の3言語")
    }

    /// 同数のタイは言語コード昇順で安定する（再現性のため）。
    func testTopEncounteredLanguagesBreaksTiesAlphabetically() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "ru")
        try await backend.recordLanguageEncounter(languageCode: "de")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertEqual(top, ["de", "fr", "ru"], "タイは言語コード昇順で並ぶ")
    }

    /// limit == 0 のときは空配列（F19: pre-fetch を無効化する余地を残す）。
    func testTopEncounteredLanguagesLimitZeroReturnsEmpty() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "fr")
        let top = try await backend.topEncounteredLanguages(limit: 0)
        XCTAssertTrue(top.isEmpty, "limit=0 は pre-fetch 無効化の目印として空配列を返す")
    }

    /// 1件も記録がないときは空配列。
    func testTopEncounteredLanguagesEmptyWhenNoEncounters() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        let top = try await backend.topEncounteredLanguages(limit: 3)
        XCTAssertTrue(top.isEmpty, "記録ゼロのときは空配列")
    }

    // MARK: 永続化

    /// 別インスタンスでも同じ store を読めばカウンタが引き継がれる
    ///（アプリの再起動を模したシナリオ。F19: 端末内のみ）。
    func testEncountersPersistAcrossBackendInstances() async throws {
        let store = makeStore()
        let backend1 = makeBackend(store: store)
        try await backend1.recordLanguageEncounter(languageCode: "fr")
        try await backend1.recordLanguageEncounter(languageCode: "fr")
        try await backend1.recordLanguageEncounter(languageCode: "de")

        // 新しい LocalBackend（=別プロセス = 再起動）を作成。同じ store を指す。
        let backend2 = makeBackend(store: store)
        let top = try await backend2.topEncounteredLanguages(limit: 5)
        XCTAssertEqual(top, ["fr", "de"], "別インスタンスでも同じ store なら回数が引き継がれる")
    }

    /// アカウント削除（F33）でカウンタがリセットされる。
    func testDeleteAccountClearsEncounters() async throws {
        let store = makeStore()
        let backend = makeBackend(store: store)
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "fr")
        try await backend.recordLanguageEncounter(languageCode: "de")
        // アカウントが無いと deleteAccount は失敗するので、最低限のアカウントを作る。
        _ = try await backend.createAnonymousUser(emoji: "🐢", nickname: "keita")
        try await backend.deleteAccount()
        let top = try await backend.topEncounteredLanguages(limit: 5)
        XCTAssertTrue(top.isEmpty, "アカウント削除で言語エンカウンタもリセットされる")
    }

    // MARK: isOnline

    /// LocalBackend はネットワーク非依存のため常に true。
    /// pre-fetch の offline 判定（F41 受け入れ条件5前半）の前提として確認。
    func testIsOnlineAlwaysTrueForLocalBackend() async {
        let store = makeStore()
        let backend = makeBackend(store: store)
        let online = await backend.isOnline()
        XCTAssertTrue(online, "LocalBackend は通信経路を持たないため常時オンライン扱い")
    }
}
