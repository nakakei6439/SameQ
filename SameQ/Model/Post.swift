import Foundation

/// お題への回答（F04 / F10）。
/// 表示に必要な投稿者情報（絵文字・ニックネーム）は取得時に埋めて返す。
/// `bodyLanguage` は翻訳可否の判定にのみ使う内部情報で、画面には一切出さない。
struct Post: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let promptID: String
    let authorID: UUID
    let authorEmoji: String
    let authorNickname: String?
    let body: String
    let bodyLanguage: String
    let createdAt: Date
    /// 表示期限。お題の終了時刻に揃える（置いた前提2）。これを過ぎたら誰にも見せない。
    let expiresAt: Date

    /// `date` の時点でまだ見えるか（F10）。期限ちょうどは「期限切れ」として扱う。
    func isVisible(at date: Date) -> Bool {
        date < expiresAt
    }

    /// 表示に使える投稿者名。未設定なら nil（絵文字のみ表示）。
    var displayNickname: String? {
        guard let authorNickname else { return nil }
        let trimmed = authorNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
