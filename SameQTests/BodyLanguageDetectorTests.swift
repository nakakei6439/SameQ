import XCTest
@testable import SameQ

/// `BodyLanguageDetector` の判定。
///
/// もとは `posts.body_language` に**端末の言語**をそのまま入れており、本文が何語かは
/// 見ていなかった。日本語端末から英語で投稿すると `ja` と記録され、英語端末の読み手が
/// ja→en の翻訳にかけてしまう（結果が壊れるか、モデル未取得ならスキップされて表示されない）。
/// ここでは「本文から判定できること」と「自信が無いときは端末言語に落ちること」を確かめる。
final class BodyLanguageDetectorTests: XCTestCase {

    // MARK: 本文から判定する

    func test01_japaneseBodyIsDetectedAsJapaneseEvenOnAnEnglishDevice() {
        let code = BodyLanguageDetector.detect(
            "朝の電車で、知らない人が席を譲っていた。小さいことだけど、少し救われた気がした。",
            fallback: "en"
        )
        XCTAssertEqual(code, "ja", "端末が英語でも、本文が日本語なら ja と記録する")
    }

    func test02_englishBodyIsDetectedAsEnglishEvenOnAJapaneseDevice() {
        let code = BodyLanguageDetector.detect(
            "The rain stopped exactly when I stepped outside, and I took that as a small win.",
            fallback: "ja"
        )
        XCTAssertEqual(code, "en", "端末が日本語でも、本文が英語なら en と記録する（これが直したかった穴）")
    }

    // MARK: 判定できないときは端末言語に落とす

    func test03_emptyBodyFallsBackToTheDeviceLanguage() {
        XCTAssertEqual(BodyLanguageDetector.detect("", fallback: "ja"), "ja")
        XCTAssertEqual(BodyLanguageDetector.detect("   \n  ", fallback: "en"), "en")
    }

    func test04_tooShortBodyFallsBackToTheDeviceLanguage() {
        // 短すぎる本文は判定材料が足りない。外すと別言語として翻訳にかけられるので、
        // 判定しにいかず端末言語のままにする。
        XCTAssertEqual(BodyLanguageDetector.detect("ab", fallback: "ja"), "ja")
    }

    func test05_emojiOnlyBodyFallsBackToTheDeviceLanguage() {
        XCTAssertEqual(BodyLanguageDetector.detect("🌙🐢🌵🍋", fallback: "ja"), "ja")
    }

    // MARK: 返す形

    func test06_returnsABareLowercasedLanguageCode() {
        // `Translator.targetLanguageCode` と同じ正規化（素の言語コード・小文字）でないと、
        // 「原文の言語が端末言語と同じなら翻訳しない」判定がすり抜ける。
        let code = BodyLanguageDetector.detect(
            "The rain stopped exactly when I stepped outside, and I took that as a small win.",
            fallback: "ja"
        )
        XCTAssertEqual(code, code.lowercased())
        XCTAssertFalse(code.contains("-"), "script 付き（zh-Hans 等）のまま返してはいけない")
    }
}
