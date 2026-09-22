import Foundation
import NaturalLanguage

/// 投稿本文の言語を、**本文そのもの**から判定する。
///
/// ## なぜ必要か
///
/// もとは `Locale.current.language.languageCode`（＝**端末の言語**）をそのまま
/// `posts.body_language` に入れていた。本文が何語かは一切見ていなかった。
///
/// その結果、日本語端末のユーザーが英語で投稿すると `ja` と記録され、
/// - 日本語端末の読み手には翻訳されずに英語のまま出る（読めない人には読めない）
/// - 英語端末の読み手には **ja→en の翻訳にかけられる**。すでに英語の文を日本語として
///   翻訳することになり、結果が壊れるか、モデル未取得なら `drawNextPost` に
///   スキップされて**そもそも表示されない**
///
/// `body_language` は「翻訳可否の判定にのみ使う」列（`20260817000001_init.sql:55`）なので、
/// その判定材料が端末言語の推測では困る。
///
/// ## 判定の方針
///
/// 外すと実害が出る（別言語として翻訳にかけられる／スキップされる）ので、**自信がある
/// ときだけ判定を採用し、それ以外は端末言語に落とす**保守的な作りにしている。
/// SameQ の回答は短文なので、短すぎるものは判定材料が足りず端末言語のままにする。
///
/// 返す言語コードは `Translator.targetLanguageCode` と同じ正規化（素の言語コード・小文字。
/// 例: `zh-Hans` → `zh`）に揃える。揃えないと
/// `AppSession.drawNextPost` の「原文の言語が端末言語と同じなら翻訳しない」判定が
/// すり抜ける。
enum BodyLanguageDetector {

    /// 判定できないときに使う言語コード。
    static let undetermined = "und"

    /// 判定を採用する最低信頼度。短文で誤判定すると実害が出るので低くしすぎない。
    static let minimumConfidence: Double = 0.65

    /// 判定材料として最低限必要な文字数。これ未満は端末言語に落とす。
    static let minimumCharacters = 4

    /// 端末の言語コード。判定できないときの控えに使う。
    static var deviceLanguageCode: String {
        Locale.current.language.languageCode?.identifier.lowercased() ?? undetermined
    }

    /// `body` の言語を判定する。
    ///
    /// - Parameters:
    ///   - body: 投稿本文。
    ///   - fallback: 判定できなかったときに返す言語コード。既定は端末の言語。
    ///     テストから固定値を渡せるように引数にしてある。
    static func detect(_ body: String, fallback: String? = nil) -> String {
        let fallbackCode = (fallback ?? deviceLanguageCode).lowercased()
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return fallbackCode }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard
            let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
            language != .undetermined,
            confidence >= minimumConfidence
        else {
            return fallbackCode
        }
        return normalize(language)
    }

    /// `NLLanguage` を `Translator.targetLanguageCode` と同じ形へ揃える。
    /// `NLLanguage.rawValue` は `zh-Hans` のように script 付きで返ることがあるため、
    /// `Locale.Language` を通して素の言語コードだけを取り出す。
    private static func normalize(_ language: NLLanguage) -> String {
        let raw = language.rawValue
        let base = Locale.Language(identifier: raw).languageCode?.identifier
        return (base ?? raw).lowercased()
    }
}
