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
            /// お題原文の言語（F22 の翻訳可否判定に使う内部情報）。無ければ日本語として扱う。
            let promptLanguage: String?
        }
        let prompts: [SeedPrompt]
        /// BAN状態の投稿者（F16）。同梱シードの誰がBANされているかをここに書く。
        let bannedAuthorIDs: [UUID]
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
            prompts.append(Prompt(
                id: seedPrompt.id,
                text: seedPrompt.text,
                startsAt: startsAt,
                endsAt: endsAt,
                language: seedPrompt.promptLanguage ?? "ja"
            ))

            var promptPosts = seedPrompt.posts.map { seed in
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
            }
            if let requested = options.answerCount {
                promptPosts = resize(
                    to: requested,
                    promptSlot: index,
                    promptID: seedPrompt.id,
                    startsAt: startsAt,
                    endsAt: endsAt
                )
            }
            posts.append(contentsOf: promptPosts)
        }
        return PromptSchedule(prompts: prompts, posts: posts, bannedAuthorIDs: Set(file.bannedAuthorIDs))
    }

    /// `loadSchedule` の上に「今日のお題が無ければ `PromptGenerator` で自動生成して
    /// 末尾へ追加する」薄いラッパ（F26）。
    ///
    /// 返り値は「起動時の PromptSchedule」と「自動生成した結果（破棄記録を含む）」。
    /// `LocalBackend` は結果の `prompt` を schedule にマージし、`discarded` の件数を
    /// `PersistedState.discardedCandidatesCount` へ積算する（受け入れ条件 4）。
    ///
    /// `seedOnly: true` のときは自動生成をスキップして、シードのお題だけ返す。
    /// 検証用（`-SameQSeedOnly` / スプリント02の既存テストの挙動を保ったままにする）。
    ///
    /// `skipSeed: true` のときは**シードを一切読み込まず**、`PromptGenerator` の
    /// 自動生成だけで PromptSchedule を組み立てる。シードに依存しないお題自動生成の
    /// 動作を UI から確認したいとき（`-SameQSkipSeed`）に使う。
    static func loadScheduleWithAutoGeneration(
        reference: Date,
        scenario: PromptScenario,
        options: LaunchOptions = .current,
        seedOnly: Bool = false,
        skipSeed: Bool = false
    ) throws -> (PromptSchedule, PromptGenerator.GenerationResult?) {
        if skipSeed {
            // シードのお題を一切入れず、auto-gen だけで PromptSchedule を組み立てる
            //（Debug 限定の動作確認用。受け入れ条件 6 の検証に使う）。
            let result = PromptGenerator.generate(reference: reference)
            return (
                PromptSchedule(prompts: [result.prompt], posts: []),
                result
            )
        }
        let base = try loadSchedule(reference: reference, scenario: scenario, options: options)
        if seedOnly {
            return (base, nil)
        }
        // シードが「今日の UTC 日付」を既にカバーしているなら、シードのお題を採用する
        // （受け入れ条件 6: 2 つのお題が同時に表示されない）。自動生成は「シードに無い日」を
        // 埋めるためにだけ動く。
        if PromptGenerator.scheduleAlreadyCoversToday(schedule: base, reference: reference) {
            return (base, nil)
        }
        let result = PromptGenerator.generate(reference: reference)
        let merged = merge(schedule: base, generated: result.prompt)
        return (merged, result)
    }

    /// `generated` を `schedule.prompts` に追加する。
    ///
    /// 「同じ ID のお題が既に schedule に入っていないか」を先に確認し、あれば
    /// それを優先する（同じ日に複数起動しても重複して Prompt を増やさないため）。
    /// 開始時刻順を保つために挿入位置を決める（F09・受け入れ条件 6）。
    private static func merge(schedule: PromptSchedule, generated: Prompt) -> PromptSchedule {
        if schedule.prompts.contains(where: { $0.id == generated.id }) {
            // 既に同じ ID のお題がある（= 起動が日をまたいで、その間にシード側で
            // 同じ ID が入ってしまった等の特殊なケース）は、schedule 側を採用する。
            return schedule
        }
        var prompts = schedule.prompts
        // 開始時刻順を維持する位置を決める
        let insertIndex = prompts.firstIndex(where: { $0.startsAt > generated.startsAt })
            ?? prompts.endIndex
        prompts.insert(generated, at: insertIndex)
        return PromptSchedule(
            prompts: prompts,
            posts: schedule.posts,
            bannedAuthorIDs: schedule.bannedAuthorIDs
        )
    }

    // MARK: 検証用の件数調整（`-SameQAnswerCount`）

    /// 各お題の回答を指定件数ちょうどに揃える。
    ///
    /// 件数指定があるときは、同梱シードの実データ（多言語）は使わず**全件を機械的に作る**
    /// （スプリント06で追加）。`-SameQAnswerCount` はタイムライン取得ルール・既読・BAN・
    /// 通報連打制限など（F11〜F17）の検証に使う起動引数で、翻訳（F18〜F22）の検証とは
    /// 役割が別。機械生成は常に端末言語と同じ「ja」で作るので、翻訳を挟まず
    /// スキップも発生しない（＝件数どおりに必ず表示される）。翻訳そのものの検証は
    /// `-SameQAnswerCount` を付けない同梱シードそのまま（多言語）で行う。
    ///
    /// ID は起動ごとに変わらない決め打ちなので、アプリを再起動しても「同じ回答」として
    /// 既読の判定ができる（F12 の検証に必要）。本文には通し番号を入れてあり、
    /// 同じ回答が2回出ていないかを目視で追える。
    private static func resize(
        to count: Int,
        promptSlot: Int,
        promptID: String,
        startsAt: Date,
        endsAt: Date
    ) -> [Post] {
        guard count > 0 else { return [] }
        var posts: [Post] = []
        let span = endsAt.timeIntervalSince(startsAt)
        for number in 1...count {
            let sentence = generatedSentences[(promptSlot + number) % generatedSentences.count]
            let emoji = generatedEmojis[number % generatedEmojis.count]
            // 4件に1件はニックネーム未設定（絵文字のみ表示のレイアウト確認用）。
            let nickname = number % 4 == 0 ? nil : "\(generatedNicknames[number % generatedNicknames.count])\(number)"
            posts.append(
                Post(
                    id: deterministicID(prefix: 0xA0, promptSlot: promptSlot, number: number),
                    promptID: promptID,
                    // 投稿は お題ごとに別物だが、投稿者は お題をまたいで同じ人にする
                    // （1お題1投稿は保ったまま、「ブロックした人が次のお題にも出てこない」を確認できる）。
                    authorID: deterministicID(prefix: 0xB0, promptSlot: 0, number: number),
                    authorEmoji: emoji,
                    authorNickname: nickname,
                    body: "\(sentence)（#\(promptSlot + 1)-\(number)）",
                    bodyLanguage: "ja",
                    createdAt: startsAt.addingTimeInterval(span * Double(number % 100) / 200),
                    expiresAt: endsAt
                )
            )
        }
        return posts
    }

    /// 起動をまたいで同じ値になる UUID。乱数もハッシュも使わない（Swift の Hasher は毎起動で変わるため）。
    private static func deterministicID(prefix: Int, promptSlot: Int, number: Int) -> UUID {
        let string = String(format: "%02X%06X-0000-4000-8000-%012X", prefix, promptSlot, number)
        return UUID(uuidString: string) ?? UUID()
    }

    private static let generatedSentences = [
        "朝の電車で、知らない人が席を譲っていた",
        "コーヒーをこぼしたけど、誰も見ていなかった",
        "犬が信号をちゃんと待っていた",
        "母からの短いメッセージで少し泣いた",
        "夜中に食べたアイスがやたらおいしかった",
        "同僚の口癖がうつっていることに気づいた",
        "洗濯物がよく乾いた日だった",
        "階段を1段飛ばしで上がれた",
        "рядом сидящий человек тихо напевал",
        "The rain stopped exactly when I stepped outside"
    ]

    private static let generatedEmojis = ["🌙", "🐢", "🌵", "🍋", "🧦", "🌿", "🐧", "🫖", "🪐", "🍞"]

    private static let generatedNicknames = ["Mina", "Kai", "ふゆ", "Noor", "Sora", "Leo", "하늘", "Aya"]

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
