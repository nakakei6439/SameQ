import XCTest
@testable import SameQ

/// 規約・プライバシーポリシーの日英（F52）。
///
/// App Store の審査は英語端末で行われる。英語版に「一切許容しない」と
/// 「24時間以内」の記述が無いと、ガイドライン 1.2 の2番目の要求
/// （EULA に no tolerance を明記すること）を満たさない。
/// 文面は人が書くものなので、ここでは**必ず入っていなければならない要素**だけを固定する。
final class LegalTextTests: XCTestCase {

    func testAllFourDocumentsAreNonEmpty() {
        XCTAssertFalse(LegalText.termsJA.isEmpty)
        XCTAssertFalse(LegalText.termsEN.isEmpty)
        XCTAssertFalse(LegalText.privacyJA.isEmpty)
        XCTAssertFalse(LegalText.privacyEN.isEmpty)
    }

    /// ゼロトレランス条項（ガイドライン 1.2 の要求2）。
    func testZeroToleranceClauseIsPresentInBothLanguages() {
        XCTAssertTrue(
            LegalText.termsJA.contains("一切許容しません"),
            "日本語の規約にゼロトレランスの記述が無い"
        )
        XCTAssertTrue(
            LegalText.termsEN.lowercased().contains("zero tolerance"),
            "英語の規約に zero tolerance の記述が無い"
        )
    }

    /// 24時間以内の対応（ガイドライン 1.2 の要求7）。
    func testTwentyFourHourCommitmentIsPresentInBothLanguages() {
        XCTAssertTrue(
            LegalText.termsJA.contains("24時間以内"),
            "日本語の規約に24時間以内の対応が書かれていない"
        )
        XCTAssertTrue(
            LegalText.termsEN.lowercased().contains("within 24 hours"),
            "英語の規約に within 24 hours が書かれていない"
        )
    }

    /// 違反者の排除（ガイドライン 1.2 の要求7「ejecting the user」）。
    func testSuspensionIsStatedInBothLanguages() {
        XCTAssertTrue(LegalText.termsJA.contains("停止"))
        XCTAssertTrue(LegalText.termsEN.lowercased().contains("suspend"))
    }

    /// 対象年齢 18+（ガイドライン 1.2 の要求1と揃える）。
    func testAgeRequirementIsStatedInBothLanguages() {
        XCTAssertTrue(LegalText.termsJA.contains("18歳以上"))
        XCTAssertTrue(LegalText.termsEN.contains("18"))
    }

    /// 自動更新サブスクリプションの開示（ガイドライン 3.1.2）。
    func testAutoRenewingSubscriptionIsExplainedInBothLanguages() {
        XCTAssertTrue(LegalText.termsJA.contains("自動更新"))
        XCTAssertTrue(LegalText.termsEN.lowercased().contains("auto-renewing"))
    }

    /// 削除しても同じお題へ再回答できないこと（置いた前提1）を規約でも伝える。
    func testDeletionRuleIsStatedInBothLanguages() {
        XCTAssertTrue(LegalText.termsJA.contains("回答することはできません"))
        XCTAssertTrue(LegalText.termsEN.lowercased().contains("cannot answer the same prompt again"))
    }

    /// 本文を外部へ送らないという約束（プライバシーポリシー）。
    /// 外部モデレーション API を採らなかった根拠でもあるので、消さないよう固定する。
    func testPrivacyPolicyStatesNoExternalTransmission() {
        XCTAssertTrue(LegalText.privacyJA.contains("外部サーバーへ送信することはありません"))
        XCTAssertTrue(LegalText.privacyEN.lowercased().contains("never send"))
    }

    /// 連絡先が規約とプライバシーポリシーの両方に載っていること
    /// （ガイドライン 1.2 の要求8）。
    func testContactAddressIsPresentInEveryDocument() {
        for document in [LegalText.termsJA, LegalText.termsEN, LegalText.privacyJA, LegalText.privacyEN] {
            XCTAssertTrue(document.contains("nakakei6439@gmail.com"))
        }
    }

    /// 日英で条の数が一致していること（片方だけ条を足すと Web 版と揃わなくなる）。
    func testArticleCountsMatchBetweenLanguages() {
        // 本文中の参照（「第6条に定める」/ "in Article 6"）を数えないよう、
        // 行頭の見出しだけを数える。
        func headingCount(_ document: String, prefix: String) -> Int {
            document
                .components(separatedBy: .newlines)
                .filter { $0.hasPrefix(prefix) }
                .count
        }
        let japaneseArticles = headingCount(LegalText.termsJA, prefix: "第")
        let englishArticles = headingCount(LegalText.termsEN, prefix: "Article ")
        XCTAssertEqual(
            japaneseArticles, englishArticles,
            "日英で条の数が違う。片方だけ条を足すと Web 版とも揃わなくなる"
        )
        XCTAssertEqual(englishArticles, 14, "条数を変えたら日英と Web 版をすべて揃えること")
    }

    /// 版が空でないこと。同意の記録（F53）と再同意の判定に使う。
    func testVersionIsSet() {
        XCTAssertFalse(LegalText.version.isEmpty)
    }
}
