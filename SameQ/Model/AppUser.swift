import Foundation

/// 匿名アカウント（F02）。
/// メールも電話番号も持たず、内部 ID だけで identity を作る。
struct AppUser: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var emoji: String
    /// 入力必須ではないので nil / 空文字を許す。空文字は nil と同じ「未設定」として扱う。
    var nickname: String?
    let createdAt: Date

    /// 表示に使えるニックネーム。未設定なら nil を返す（呼び出し側は絵文字のみ表示する）。
    var displayNickname: String? {
        guard let nickname else { return nil }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
