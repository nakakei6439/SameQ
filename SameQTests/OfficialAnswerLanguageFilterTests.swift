import XCTest
@testable import SameQ

/// スプリント22 attempt: 「同じペルソナの運営回答カードが2枚出る」不具合の修正。
///
/// 運営5ペルソナは日本語・英語それぞれ別アカウントで毎日投稿するため、絞り込まずに
/// 返すと端末内翻訳が効く端末で日本語版・英語版の両方が表示されてしまう
/// （2026-09-22 の設計は「読めない言語は F20 でスキップされる」前提だったが、
/// 端末内翻訳が効くとその前提が崩れる）。
///
/// `SupabaseBackend.filterOfficialRowsByDeviceLanguage(_:isJapanese:)` は
/// `actor` の static メンバー（非分離。SE-0306）なので、ネットワークにもアクター
/// 分離にも触れずに同期的にテストできる。`L10n.isJapanese` は起動時に一度だけ
/// 確定する `static let` で差し替えられないため、絞り込みロジック自体を
/// 「言語を引数で受け取る純粋関数」として `timelinePosts()` から切り出し、
/// ここでは `isJapanese` を true/false 両方で直接呼び出して確認する
/// （`timelinePosts()` 側は `L10n.isJapanese` の値をそのままこの関数に渡すだけ）。
final class OfficialAnswerLanguageFilterTests: XCTestCase {

    private func makeRow(
        idSeed: String,
        isOfficial: Bool?,
        bodyLanguage: String?
    ) -> PostRow {
        PostRow(
            id: UUID(),
            prompt_id: "p1",
            author_id: UUID(),
            author_emoji: "🙂",
            author_nickname: idSeed,
            body: idSeed,
            body_language: bodyLanguage,
            created_at: Date(),
            expires_at: Date().addingTimeInterval(3600),
            decorations: nil,
            status: nil,
            is_official: isOfficial
        )
    }

    /// 日本語端末では、運営投稿のうち日本語のものだけが残る。
    func test01_japaneseDevice_keepsOnlyJapaneseOfficialPosts() {
        let rows = [
            makeRow(idSeed: "official-ja", isOfficial: true, bodyLanguage: "ja"),
            makeRow(idSeed: "official-en", isOfficial: true, bodyLanguage: "en"),
        ]
        let result = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: true)
        XCTAssertEqual(result.map(\.author_nickname), ["official-ja"])
    }

    /// 英語端末では、運営投稿のうち英語のものだけが残る。
    func test02_englishDevice_keepsOnlyEnglishOfficialPosts() {
        let rows = [
            makeRow(idSeed: "official-ja", isOfficial: true, bodyLanguage: "ja"),
            makeRow(idSeed: "official-en", isOfficial: true, bodyLanguage: "en"),
        ]
        let result = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: false)
        XCTAssertEqual(result.map(\.author_nickname), ["official-en"])
    }

    /// `is_official` が false / nil の一般ユーザー投稿は、言語に関係なく常に残る
    /// （F20 のスキップ・F22 の翻訳の対象のまま。ここでの絞り込みの対象外）。
    func test03_nonOfficialPosts_alwaysKeptRegardlessOfLanguage() {
        let rows = [
            makeRow(idSeed: "user-ja-false", isOfficial: false, bodyLanguage: "ja"),
            makeRow(idSeed: "user-en-false", isOfficial: false, bodyLanguage: "en"),
            makeRow(idSeed: "user-ja-nil", isOfficial: nil, bodyLanguage: "ja"),
            makeRow(idSeed: "user-en-nil", isOfficial: nil, bodyLanguage: "en"),
        ]
        let ja = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: true)
        let en = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: false)
        XCTAssertEqual(Set(ja.map(\.author_nickname)), Set(rows.map(\.author_nickname)))
        XCTAssertEqual(Set(en.map(\.author_nickname)), Set(rows.map(\.author_nickname)))
    }

    /// `is_official = true` でも `body_language` が nil の投稿は、取りこぼして
    /// 運営回答がゼロになるのを避けるため、言語に関係なく残す（安全側に倒す）。
    func test04_officialPostWithNilLanguage_isKept() {
        let rows = [
            makeRow(idSeed: "official-nil-language", isOfficial: true, bodyLanguage: nil),
        ]
        let ja = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: true)
        let en = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: false)
        XCTAssertEqual(ja.map(\.author_nickname), ["official-nil-language"])
        XCTAssertEqual(en.map(\.author_nickname), ["official-nil-language"])
    }

    /// 依頼にある実際の状況を再現する: 1つのお題に対して運営5ペルソナ×2言語（10件）+
    /// 一般ユーザーの投稿が混ざっているとき、日本語端末では運営5件（日本語）+一般全件、
    /// 英語端末では運営5件（英語）+一般全件になる。
    func test05_mixedTimeline_officialCountBecomesFivePerDevice() {
        let personas = ["keita", "emily", "robo", "tetra", "dragon"]
        var rows: [PostRow] = []
        for persona in personas {
            rows.append(makeRow(idSeed: "official-\(persona)-ja", isOfficial: true, bodyLanguage: "ja"))
            rows.append(makeRow(idSeed: "official-\(persona)-en", isOfficial: true, bodyLanguage: "en"))
        }
        rows.append(makeRow(idSeed: "user1", isOfficial: false, bodyLanguage: "ja"))
        rows.append(makeRow(idSeed: "user2", isOfficial: nil, bodyLanguage: "en"))

        let ja = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: true)
        let en = SupabaseBackend.filterOfficialRowsByDeviceLanguage(rows, isJapanese: false)

        XCTAssertEqual(ja.filter { $0.is_official == true }.count, 5)
        XCTAssertEqual(en.filter { $0.is_official == true }.count, 5)
        XCTAssertEqual(ja.count, 7) // 運営5 + 一般2
        XCTAssertEqual(en.count, 7)
    }
}
