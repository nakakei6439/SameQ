import Foundation

/// 投稿本文の受け入れ判定（F17: 無意味な文字列の拒否）。
///
/// ここでの判定は「意味を成す文か」ではなく、
/// 空白・改行だけ／同じ文字を機械的に並べただけの投稿を弾く程度に留める。
/// 実際の言語判定はしない（多言語の回答を誤って弾かない範囲に閾値を置く）。
/// 空白・改行のみの投稿は `LocalBackend.submitPost` の `emptyBody` チェックで別途弾く。
enum PostValidator {
    /// 有効な文字（空白・改行を除く）がこの数未満なら、繰り返し判定はしない。
    /// 短い相槌（「はい」「OK」など）を誤って弾かないため。
    private static let minimumCharactersToCheck = 4

    /// 最も多く出現する1文字がこの割合以上を占めていたら「意味のない繰り返し」とみなす。
    private static let repetitionRatioThreshold = 0.7

    /// `trimmedBody` は呼び出し側で前後の空白・改行を除去済みであること。
    static func isMeaninglessRepetition(_ trimmedBody: String) -> Bool {
        let characters = trimmedBody.filter { !$0.isWhitespace && !$0.isNewline }
        guard characters.count >= minimumCharactersToCheck else { return false }

        var counts: [Character: Int] = [:]
        for character in characters {
            counts[character, default: 0] += 1
        }
        guard let maxCount = counts.values.max() else { return false }

        let ratio = Double(maxCount) / Double(characters.count)
        return ratio >= repetitionRatioThreshold
    }
}
