import Foundation

/// 世界共通のお題（F03）。
/// スプリント01では運用側が用意した固定のお題を1つだけ扱う。
/// 有効期間（開始・終了日時）による切り替えはスプリント02で扱うため、ここでは持たない。
struct Prompt: Codable, Identifiable, Equatable, Sendable {
    /// 世界共通の ID（例: prompt_001）
    let id: String
    /// お題の原文。スプリント01では翻訳せずそのまま表示する。
    let text: String
}
