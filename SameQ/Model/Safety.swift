import Foundation

/// 通報の理由（F13）。
///
/// 選択肢は `.product/spec.md` 6節（お題の安全条件）に挙がっている観点に揃えてある。
/// 相手には一切表示されない、自分と運営だけが見るラベル。
enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case politics
    case religion
    case discrimination
    case sexual
    case crime
    case privacy
    case other

    var id: String { rawValue }

    /// 選択肢に出す文言。短く、判断に迷わない粒度にする。
    var label: String {
        switch self {
        case .politics: return "政治的な対立をあおる"
        case .religion: return "宗教的な対立をあおる"
        case .discrimination: return "差別・ヘイト"
        case .sexual: return "性的な内容"
        case .crime: return "犯罪をすすめている"
        case .privacy: return "個人情報が書かれている"
        case .other: return "その他の不快な内容"
        }
    }
}

/// 自分が出した通報の記録（F13）。
///
/// 通報した回答は自分のタイムラインから即座に消え、以後の候補にも入らない。
/// 相手に伝わる情報は何も持たない（通知も、相手側の表示も作らない）。
struct Report: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// 通報した回答。表示対象から外す判定に使う。
    let postID: UUID
    let reason: ReportReason
    let createdAt: Date
    /// 通報対象の投稿の表示期限。F34 の 30 日保持期限の起点。
    let postExpiresAt: Date

    init(id: UUID, postID: UUID, reason: ReportReason, createdAt: Date, postExpiresAt: Date) {
        self.id = id
        self.postID = postID
        self.reason = reason
        self.createdAt = createdAt
        self.postExpiresAt = postExpiresAt
    }

    /// schemaVersion 5 以前の `Report` 用フォールバックデコーダ。
    /// `postExpiresAt` が無いものだけ `createdAt + 28h` を仮置きする。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        postID = try container.decode(UUID.self, forKey: .postID)
        reason = try container.decode(ReportReason.self, forKey: .reason)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        postExpiresAt = try container.decodeIfPresent(Date.self, forKey: .postExpiresAt)
            ?? createdAt.addingTimeInterval(28 * 60 * 60)
    }
}

/// ブロック中の相手（F14 / F15）。
///
/// 保持するのは「誰か（内部ID）」と「タイムラインで見えていた見た目」だけ。
/// 国・言語・投稿本文・投稿時刻は**持たない**。ブロック一覧から相手の属性を
/// 推測できてしまうと、「相手について分かるのは絵文字と名前だけ」という前提が崩れるため。
struct BlockedAuthor: Codable, Identifiable, Equatable, Sendable {
    /// 相手のユーザーID（画面には出さない）。
    let id: UUID
    let emoji: String
    /// ブロックした時点のニックネーム。未設定なら nil（絵文字のみ表示）。
    let nickname: String?
    /// 一覧の並び順にだけ使う。画面には出さない（いつ誰を見たかが分かるため）。
    let blockedAt: Date

    /// 一覧に出す名前。未設定なら nil を返し、呼び出し側は絵文字だけを見せる。
    var displayNickname: String? {
        guard let nickname else { return nil }
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 閲覧者用に音写した名前を返す（F23）。設定画面のブロック一覧に出す名前用。
    /// ブロックは自分の操作なので `isOwn` は常に `false`（相手のニックネームを音写する）。
    /// - Parameter transliterator: 端末言語への音写器。`nil` のときは音写せず原文のまま。
    /// - Returns: 表示できる文字列。未設定・音写不能のときは `nil`（呼び出し側は「名前のない人」表記）。
    func displayedNickname(transliterator: NicknameTransliterator?) -> String? {
        guard let transliterator else { return displayNickname }
        return transliterator.transliterate(displayNickname)
    }
}
