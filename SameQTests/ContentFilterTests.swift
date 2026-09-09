import XCTest
@testable import SameQ

/// 禁止表現の判定（F48）。
///
/// **「止まること」より「止まりすぎないこと」を重く見る。** 普通の回答が弾かれる
/// 誤検知は、審査に通っても実ユーザーを黙らせる最悪の壊れ方になる（スプリント20の
/// 評価者への注記）。そのため、誤検知を潰すテストのほうを厚くしてある。
final class ContentFilterTests: XCTestCase {

    // MARK: 誤検知しないこと（こちらが本命）

    /// 禁止語を部分文字列として含むだけの、ごく普通の英単語。
    /// ラテン文字を語境界で照合していないと、ここが全部落ちる（置いた前提34）。
    func testOrdinaryEnglishWordsContainingProhibitedSubstringsArePermitted() {
        let permitted = [
            "I passed the class today and the analysis was fine.",
            "The title of the document is short.",
            "Hello from the shell of an old cucumber.",
            "Classic assessment, assumption, and assignment.",
            "Scunthorpe is a real place name.",
            "We had an online idea meeting this morning.",
            "The cockpit and the peacock were both in the painting.",
            "Analogy aside, I like analytics and canalization.",
            "Accumulate, circumstance, document, cumulative."
        ]
        for text in permitted {
            XCTAssertFalse(
                ContentFilter.containsProhibitedTerm(text),
                "誤検知: 『\(text)』は普通の英文なので投稿できなければならない"
            )
        }
    }

    /// 日本語・英語以外の言語で書かれたふつうの文も通ること。
    func testOrdinarySentencesInOtherLanguagesArePermitted() {
        let permitted = [
            "Aujourd'hui, j'ai pensé à ma grand-mère.",
            "오늘은 조금 쉬고 싶은 하루였다.",
            "اليوم كان هادئا ولطيفا.",
            "Hoy me sentí tranquilo por primera vez en semanas.",
            "今日はいい天気だったので、散歩をして気持ちが軽くなった。",
            "子どものころに押し入れで読んだ本のにおいを思い出した。"
        ]
        for text in permitted {
            XCTAssertFalse(
                ContentFilter.containsProhibitedTerm(text),
                "誤検知: 『\(text)』は普通の回答なので投稿できなければならない"
            )
        }
    }

    /// 空文字・空白のみは、このフィルタの責務ではない（`emptyBody` が別に見る）。
    func testEmptyInputIsNotFlagged() {
        XCTAssertFalse(ContentFilter.containsProhibitedTerm(""))
        XCTAssertFalse(ContentFilter.containsProhibitedTerm("   \n  "))
    }

    // MARK: 止まること

    func testEnglishProfanityIsFlagged() {
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("what the fuck is this"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("You are such a bitch."))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("kill yourself"))
    }

    func testJapaneseAbuseIsFlagged() {
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("お前なんか死ね"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("まじで殺すぞ"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("闇バイトの募集です"))
    }

    /// 外部への誘導（規約の禁止事項「個人情報の記載」とスパム対策）。
    func testContactAndLinkPatternsAreFlagged() {
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("見てね https://example.com"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("詳しくは www.example.com へ"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("line id: abcdef"))
    }

    // MARK: 正規化

    /// 全角英字・大文字は正規化して同じ語として扱う（`Ｆｕｃｋ` / `FUCK`）。
    func testNormalizationCatchesFullWidthAndUppercase() {
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("Ｆｕｃｋ"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("FUCK YOU"))
        XCTAssertTrue(ContentFilter.containsProhibitedTerm("FuCk"))
    }

    /// 端末側とサーバー側の辞書は同じ内容でなければならない（置いた前提35）。
    /// ここでは Swift 側の辞書が空でないこと・ラテン文字の語がすべて語境界照合に
    /// なっていることだけを機械的に守る（語の一覧そのものは SQL 側と目視で揃える）。
    func testLatinTermsUseWordBoundaryMatching() {
        for term in ContentFilter.terms {
            let isLatinOnly = term.value.unicodeScalars.allSatisfy {
                $0.isASCII
            }
            // 空白を含む語（"kill yourself" 等）は部分一致でよい。
            let hasSpace = term.value.contains(" ")
            if isLatinOnly && !hasSpace && !term.value.contains(":") && !term.value.contains("/") && !term.value.contains(".") {
                XCTAssertEqual(
                    term.mode, .word,
                    "『\(term.value)』はラテン文字の単語なので、部分一致にすると普通の英単語を巻き込む"
                )
            }
        }
        XCTAssertFalse(ContentFilter.terms.isEmpty)
    }
}
