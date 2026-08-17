import Foundation

/// アプリに同梱した「運用側が用意したお題」と「世界の他ユーザーの回答」。
///
/// スプリント01ではお題を AI 生成せず、回答も実サーバーから取らないため、
/// この JSON が世界タイムラインの中身になる。
/// Supabase 側の同じ内容は `supabase/seed.sql` に置いてある。
struct SeedCatalog: Sendable {
    let prompt: Prompt
    let posts: [Post]

    private struct File: Decodable {
        struct SeedPost: Decodable {
            let id: UUID
            let authorID: UUID
            let authorEmoji: String
            let authorNickname: String?
            let body: String
            let bodyLanguage: String
            let minutesAgo: Int
        }
        let prompt: Prompt
        let posts: [SeedPost]
    }

    /// バンドルの SeedData.json を読む。`now` を基準に投稿時刻を組み立てる。
    static func load(bundle: Bundle = .main, now: Date = Date()) throws -> SeedCatalog {
        guard let url = bundle.url(forResource: "SeedData", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw BackendError.seedDataMissing
        }
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw BackendError.seedDataMissing
        }
        let posts = file.posts.map { seed in
            Post(
                id: seed.id,
                promptID: file.prompt.id,
                authorID: seed.authorID,
                authorEmoji: seed.authorEmoji,
                authorNickname: seed.authorNickname,
                body: seed.body,
                bodyLanguage: seed.bodyLanguage,
                createdAt: now.addingTimeInterval(-Double(seed.minutesAgo) * 60)
            )
        }
        return SeedCatalog(prompt: file.prompt, posts: posts)
    }
}
