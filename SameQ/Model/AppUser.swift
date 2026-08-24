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

    /// 自分のニックネームは原文のまま表示する（受け入れ条件5）。呼び出し側は
    /// `transliterator` を渡さず（または `nil` を渡して）使う想定。
    func displayedNickname(transliterator: NicknameTransliterator?) -> String? {
        // 自分のニックネームは `transliterator` を経由せず、`displayNickname` をそのまま返す。
        // transliterator は受け入れない（無視する）ことを明示するためシグネチャに残してある
        // （`Post.displayedNickname(transliterator:isOwn:)` と API 形を揃える）。
        _ = transliterator
        return displayNickname
    }
}
