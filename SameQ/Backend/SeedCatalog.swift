import Foundation

/// アプリに同梱した「運用側が用意したお題」と「世界の他ユーザーの回答」。
///
/// お題を AI 生成せず、回答も実サーバーから取らないため、この JSON が世界タイムラインの中身になる。
/// JSON は本文だけを持ち、有効期間（開始・終了時刻）は起動時にシナリオから組み立てる。
/// Supabase 側の同じ内容は `supabase/seed.sql` に置いてある。
enum SeedCatalog {
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
        struct SeedPrompt: Decodable {
            let id: String
            let text: String
            let posts: [SeedPost]
        }
        let prompts: [SeedPrompt]
    }

    /// バンドルの SeedData.json を読み、シナリオに沿った日程を割り当てる。
    ///
    /// - Parameters:
    ///   - reference: 日程の基準時刻（＝アプリ起動時の「今」）。
    ///   - scenario: どの局面を再現するか。
    ///   - options: `expiring` の秒数指定などの起動引数。
    static func loadSchedule(
        bundle: Bundle = .main,
        reference: Date,
        scenario: PromptScenario,
        options: LaunchOptions = .current
    ) throws -> PromptSchedule {
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
        guard !file.prompts.isEmpty else { throw BackendError.seedDataMissing }

        let starts = startDates(
            count: file.prompts.count,
            reference: reference,
            scenario: scenario,
            options: options
        )

        var prompts: [Prompt] = []
        var posts: [Post] = []
        for (index, seedPrompt) in file.prompts.enumerated() {
            let startsAt = starts[index]
            let endsAt = startsAt.addingTimeInterval(Prompt.defaultDuration)
            prompts.append(Prompt(id: seedPrompt.id, text: seedPrompt.text, startsAt: startsAt, endsAt: endsAt))
            posts.append(contentsOf: seedPrompt.posts.map { seed in
                // 投稿時刻は画面に出さないので、お題の期間内に収まっていれば十分。
                let createdAt = min(startsAt.addingTimeInterval(Double(seed.minutesAgo) * 60), endsAt)
                return Post(
                    id: seed.id,
                    promptID: seedPrompt.id,
                    authorID: seed.authorID,
                    authorEmoji: seed.authorEmoji,
                    authorNickname: seed.authorNickname,
                    body: seed.body,
                    bodyLanguage: seed.bodyLanguage,
                    createdAt: createdAt,
                    expiresAt: endsAt
                )
            })
        }
        return PromptSchedule(prompts: prompts, posts: posts)
    }

    /// 各お題の開始時刻。期間が重ならないよう、2件目以降は前のお題の終了時刻以降に置く。
    private static func startDates(
        count: Int,
        reference: Date,
        scenario: PromptScenario,
        options: LaunchOptions
    ) -> [Date] {
        let duration = Prompt.defaultDuration
        let firstStart: Date
        var gapAfterFirst: TimeInterval = 0

        switch scenario {
        case .live:
            // 2時間前に始まったお題が有効。残り26時間。
            firstStart = reference.addingTimeInterval(-2 * 60 * 60)
        case .expiring:
            // いま有効なお題が `expirySeconds` 後に終了し、`gapSeconds` の空白のあと次が始まる。
            firstStart = reference.addingTimeInterval(options.expirySeconds - duration)
            gapAfterFirst = options.gapSeconds
        case .expired:
            // 1時間前に終了済み。次のお題は20時間後（お題待ち）。
            firstStart = reference.addingTimeInterval(-duration - 60 * 60)
            gapAfterFirst = 21 * 60 * 60
        case .upcoming:
            // まだ1件も始まっていない（お題待ち）。
            firstStart = reference.addingTimeInterval(2 * 60 * 60)
        }

        var dates: [Date] = []
        var cursor = firstStart
        for index in 0..<count {
            dates.append(cursor)
            cursor = cursor.addingTimeInterval(duration + (index == 0 ? gapAfterFirst : 0))
        }
        return dates
    }
}
