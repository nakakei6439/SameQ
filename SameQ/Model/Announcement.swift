import Foundation

/// 運営からのお知らせ（新機能）。読み取り専用。
///
/// `announcements` テーブルは select の RLS ポリシーしか持たない（insert/update/delete
/// のポリシーは意図的に無い）。運営が直接 SQL / Supabase dashboard から投入する運用で、
/// アプリ内に投稿・編集用の画面は作らない（`.product/spec.md` の前提「アプリ内に運営用
/// 画面は作らない」を踏襲、`Prompt` の運用と同じ）。
struct Announcement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let publishedAt: Date

    init(id: UUID, title: String, body: String, publishedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
    }
}
