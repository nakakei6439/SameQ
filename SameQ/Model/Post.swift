import Foundation

/// お題への回答（F04 / F10 / F29 / F30）。
/// 表示に必要な投稿者情報（絵文字・ニックネーム）は取得時に埋めて返す。
/// `bodyLanguage` は翻訳可否の判定にのみ使う内部情報で、画面には一切出さない。
/// `decorations` は Plus 限定装飾（F30）。装飾非対応環境では `body` だけを
/// 表示すれば本文として読める（評価者注記）。
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
    /// Plus 限定装飾（F30）。無料ユーザーの投稿では常に空。
    /// 本体（`body`）とは独立に保存されるので、装飾非対応の環境では無視するだけで
    /// 本文を完全に復元できる。
    let decorations: [PostDecoration]

    init(
        id: UUID,
        promptID: String,
        authorID: UUID,
        authorEmoji: String,
        authorNickname: String?,
        body: String,
        bodyLanguage: String,
        createdAt: Date,
        expiresAt: Date,
        decorations: [PostDecoration] = []
    ) {
        self.id = id
        self.promptID = promptID
        self.authorID = authorID
        self.authorEmoji = authorEmoji
        self.authorNickname = authorNickname
        self.body = body
        self.bodyLanguage = bodyLanguage
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.decorations = decorations
    }

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

    /// 閲覧者用に音写した表示名を返す（F23）。
    /// - Parameters:
    ///   - transliterator: 端末言語への音写器。`nil` のときは音写せず原文をそのまま返す
    ///     （`displayNickname` と同じ動作）。
    ///   - isOwn: 自分の回答のときは `true` を渡す。受け入れ条件5により、自分のニックネームは
    ///     入力した原文のまま表示する（音写しない）。
    /// - Returns: 表示できる文字列。未設定・音写不能のときは `nil`（呼び出し側は絵文字のみ表示）。
    func displayedNickname(transliterator: NicknameTransliterator?, isOwn: Bool) -> String? {
        // 自分のニックネームは原文のまま表示する（受け入れ条件5）。
        if isOwn { return displayNickname }
        guard let transliterator else { return displayNickname }
        return transliterator.transliterate(displayNickname)
    }

    /// 本文を端末言語へ翻訳した表示用コピーを返す（F18）。他のフィールドは変えない。
    /// `state.json` には保存せず、`AppSession.timelineContent` の中でだけ使う使い捨ての値。
    /// `decorations` の `range` は原文基準で記録されているため、翻訳後は意味が
    /// 崩れる可能性がある。装飾非対応の挙動（本文のみ表示）に揃えて、
    /// 翻訳時には装飾を一時的に落として返す。
    func displaying(translatedBody: String) -> Post {
        Post(
            id: id,
            promptID: promptID,
            authorID: authorID,
            authorEmoji: authorEmoji,
            authorNickname: authorNickname,
            body: translatedBody,
            bodyLanguage: bodyLanguage,
            createdAt: createdAt,
            expiresAt: expiresAt,
            decorations: decorations
        )
    }
}
