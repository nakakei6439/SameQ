import Foundation

/// Plus 限定装飾（F30）。投稿本文に添える「絵文字・文字装飾・吹き出し装飾」の種別。
///
/// `body` には装飾マークアップを含めない（`body` は翻訳対象・永続化対象として
/// プレーンな本文だけを保つ）。装飾は表示専用の `decorations` フィールドに乗せる。
///
/// 装飾非対応の状態（仕様・受け入れ条件の注記「装飾を付けた投稿が、装飾非対応の
/// 状態でも本文として読めるか」）では、`decorations` を一切無視して `body` を
/// そのまま表示すればよい。
struct PostDecoration: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable {
        /// 絵文字スタンプ（F30）。`value` に絵文字リテラル（例: "🌸"）。
        case emojiStamp
        /// 太字（範囲指定）。`range` で本文の `lowerBound..<upperBound` を示す。
        case bold
        /// 斜体。`range` で本文の範囲を示す。
        case italic
        /// 吹き出し装飾（本文の前後に挿入）。`value` にラベル（例: "小声"）。
        case balloon
    }

    let id: UUID
    let kind: Kind
    /// 装飾の意味が文字列で完結する装飾（絵文字スタンプ・吹き出し）の値。
    /// `bold` / `italic` のように本文の位置で意味が決まる種類のときは `nil`。
    let value: String?
    /// `bold` / `italic` のとき装飾対象の本文範囲。UTF-16 オフセット（NSRange 相当）。
    /// 他の装飾のときは `nil`。
    let range: NSRange?

    init(id: UUID = UUID(), kind: Kind, value: String? = nil, range: NSRange? = nil) {
        self.id = id
        self.kind = kind
        self.value = value
        self.range = range
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, value, range
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        if let rangeDict = try c.decodeIfPresent([String: Int].self, forKey: .range),
           let lower = rangeDict["lower"], let upper = rangeDict["upper"] {
            range = NSRange(location: lower, length: upper - lower)
        } else {
            range = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(value, forKey: .value)
        if let range {
            try c.encode(
                ["lower": range.location, "upper": range.location + range.length],
                forKey: .range
            )
        }
    }
}

/// 投稿本文を装飾込みで評価するときのヘルパ。
enum PostBodyInspector {
    /// `body` のうち、装飾なしの本文を「先頭から `limit` 文字」までに切り詰めたもの。
    /// タイムラインで「続きを読む」を出すときの折り畳み用（F29）。
    static func previewBody(of body: String, limit: Int) -> String {
        guard body.count > limit else { return body }
        return String(body.prefix(limit))
    }

    /// `body` が「長文」として折り畳み対象になるか（F29）。
    /// `Plus` 投稿で `limit`（既定 140 文字）を超えるものが対象。
    static func isLongForm(_ body: String, limit: Int) -> Bool {
        body.count > limit
    }
}
