import Foundation

/// お題の日程シナリオ（検証用）。
///
/// 本番の日程はサーバー（Supabase の `prompts.starts_at` / `ends_at`）が持つが、
/// クラウド未接続の間は起動時にこのシナリオから日程を組み立てる。
/// 実時間で28時間待たずに切り替わりを確認するために用意している。
enum PromptScenario: String, Sendable, CaseIterable {
    /// 既定。1つ目のお題が有効期間の途中（残り約26時間）。
    case live
    /// 1つ目のお題がまもなく終了し、少し間を空けて2つ目が開始する。
    case expiring
    /// 1つ目のお題は終了済みで、次のお題はまだ先（お題待ち）。
    case expired
    /// 1つ目のお題がまだ開始していない（お題待ち）。
    case upcoming
}

/// 有効期間つきのお題と、その回答の一覧。
///
/// 「常に1つだけ有効」（置いた前提3）を守るため、お題は開始時刻順に並び、
/// 期間は重ならない。回答の表示期限はお題の終了時刻に揃える（置いた前提2 / F10）。
struct PromptSchedule: Sendable {
    /// 開始時刻の昇順。
    let prompts: [Prompt]
    /// 全お題ぶんの回答。`expiresAt` は所属するお題の終了時刻。
    let posts: [Post]

    /// その時刻に有効なお題。無ければ nil（お題待ち）。
    func activePrompt(at date: Date) -> Prompt? {
        prompts.first { $0.isActive(at: date) }
    }

    /// 次に始まるお題の開始時刻。今後の予定が無ければ nil。
    func nextStart(after date: Date) -> Date? {
        prompts.first { $0.startsAt > date }?.startsAt
    }

    func prompt(id: String) -> Prompt? {
        prompts.first { $0.id == id }
    }

    /// そのお題への回答のうち、まだ表示期限内のもの。
    func visiblePosts(promptID: String, at date: Date) -> [Post] {
        posts.filter { $0.promptID == promptID && $0.isVisible(at: date) }
    }
}
