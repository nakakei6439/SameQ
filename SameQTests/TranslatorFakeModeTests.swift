import XCTest
@testable import SameQ

/// `-SameQFakeTranslate`（Debug限定・シミュレータ検証用）の周辺ロジックを検証する。
///
/// このシミュレータでは Apple Translation が全言語ペアで `unsupportedLanguagePairing` を
/// 返し、実際の `TranslationSession` 経路（`SessionRequestQueue` の先）は一度も実行できない
/// （evaluator が実測・確認済み）。実機検証は今回のスコープ外（ユーザーが外出中のため）なので、
/// 疑似翻訳モードを使い「翻訳結果が画面表示用の値に反映される」「非対応言語はスキップされる」
/// 「同じ原文は2回目以降キャッシュから即座に返る」という周辺ロジックだけを、
/// 決定的にここで確認する。`Translator` の初期化に `preferredLanguageIdentifier` を渡し、
/// テスト実行機のロケールに関係なく結果を固定できるようにしてある。
final class TranslatorFakeModeTests: XCTestCase {

    @MainActor
    private func makeTranslator(target: String = "ja") -> Translator {
        Translator(fakeTranslate: true, preferredLanguageIdentifier: target)
    }

    /// 原文言語が端末言語と異なるとき、疑似翻訳は `[<端末言語コード>] <原文>` を返す。
    @MainActor
    func testFakeTranslateTransformsDifferentLanguage() async {
        let translator = makeTranslator(target: "ja")
        let outcome = await translator.translate("Hello there", sourceLanguageCode: "en")
        guard case .text(let translated) = outcome else {
            return XCTFail("翻訳できるはずが \(outcome)")
        }
        XCTAssertEqual(translated, "[JA] Hello there")
        XCTAssertTrue(translated.hasSuffix("Hello there"), "原文の内容は保持されているはず")
    }

    /// 原文言語が端末言語と同じなら、疑似モードでも変換せずそのまま返す
    /// （余計な待ちを作らない、という本番経路と同じ挙動）。
    @MainActor
    func testFakeTranslateSkipsWhenSourceMatchesTarget() async {
        let translator = makeTranslator(target: "ja")
        let outcome = await translator.translate("そのままの日本語", sourceLanguageCode: "ja")
        XCTAssertEqual(outcome, .text("そのままの日本語"))
    }

    /// 同梱シードの検証用マーカー（`zxx`）は疑似モードでも「恒久的に非対応」を返す
    /// （F20: 翻訳できない言語の回答は一度も現れない）。
    @MainActor
    func testFakeTranslateTreatsMarkerLanguageAsPermanentlyUnsupported() async {
        let translator = makeTranslator(target: "ja")
        let outcome = await translator.translate("sameQ_untranslatable_test_marker", sourceLanguageCode: "zxx")
        XCTAssertEqual(outcome, .unavailable(permanent: true))

        // 2回目以降も一貫して恒久的に非対応のまま（`unsupportedSourceCodes` のキャッシュ経由）。
        let secondOutcome = await translator.translate("別の本文", sourceLanguageCode: "zxx")
        XCTAssertEqual(secondOutcome, .unavailable(permanent: true))
    }

    /// 同梱シードの検証用マーカー（`qtd`）は疑似モードでも「モデル未ダウンロード
    /// （`.supported`）」と同じ**一時的な失敗**を返す（attempt 4: eval-3.md [1] の
    /// 再発防止）。恒久的な非対応（`zxx`）と違い `permanent: false` になる点が異なる。
    @MainActor
    func testFakeTranslateTreatsMarkerLanguageAsTemporarilyUnavailable() async {
        let translator = makeTranslator(target: "ja")
        let outcome = await translator.translate("sameQ_download_pending_test_marker", sourceLanguageCode: "qtd")
        XCTAssertEqual(outcome, .unavailable(permanent: false))
    }

    /// F19（同じ端末で2回目以降は待ちが発生しない）: 同じ原文・同じ言語ペアなら
    /// 2回目はキャッシュから返る（`translate` 内でキャッシュ判定が疑似モードの分岐より
    /// 先にあるため、本番経路と全く同じキャッシュ機構を共有している）。
    @MainActor
    func testSameTextIsCachedAcrossCalls() async {
        let translator = makeTranslator(target: "ja")
        let first = await translator.translate("同じ本文", sourceLanguageCode: "en")
        let second = await translator.translate("同じ本文", sourceLanguageCode: "en")
        XCTAssertEqual(first, second)
        guard case .text(let value) = first else { return XCTFail("翻訳できるはず") }
        XCTAssertEqual(value, "[JA] 同じ本文")
    }

    /// 空文字は翻訳せずそのまま返す（境界値）。
    @MainActor
    func testEmptyTextIsReturnedAsIs() async {
        let translator = makeTranslator(target: "ja")
        let outcome = await translator.translate("", sourceLanguageCode: "en")
        XCTAssertEqual(outcome, .text(""))
    }

    /// 端末言語が変わっても（＝別の `Translator` インスタンスでも）疑似変換の接頭辞は
    /// 端末言語コードに追従する。
    @MainActor
    func testFakePrefixFollowsTargetLanguage() async {
        let englishDevice = makeTranslator(target: "en")
        let outcome = await englishDevice.translate("今日は笑った", sourceLanguageCode: "ja")
        XCTAssertEqual(outcome, .text("[EN] 今日は笑った"))
    }
}
