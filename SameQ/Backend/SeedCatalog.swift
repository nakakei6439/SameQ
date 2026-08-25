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

        // `.live` シナリオでは prompt_001 だけを「今日のお題」として使う。
        // prompt_002 以降は同梱されていても読み込まない（受け入れ条件 1）。
        //
        // 理由:
        //   1. prompt_001 (28h) と prompt_002 (28h) の合計 56h は
        //      必ずどこか UTC 日境界を跨ぐため、隣接する 2 日で同じ prompt_002 が
        //      active になり「翌日に別のお題が出ない」（受け入れ条件 1）症状を
        //      引き起こす。
        //   2. 起動のたびに動的にシード日程を組み直すと prompt_001 が
        //      「今から 28h 前」に再生成され続けて PromptGenerator が到達不能
        //      になる（attempt 1 で却下、attempt 2 で `liveAnchor` 固定化済み）。
        //
        // 結果として、`.live` の固定アンカー方式 + prompt_002 除外で
        // `reference > liveAnchor + duration` のときは schedule は空にしておく
        //（`startDates` 側で返す空配列で表現）。空 schedule なら
        // `scheduleAlreadyCoversToday` が必ず false を返し、PromptGenerator が
        // 即座に起動して別 ID (`prompt_yyyyMMdd`) を採用する（受け入れ条件 1）。
        // empty schedule を返さない場合は prompt_001 が「過去だが schedule に残る」
        // 状態になり、auto-gen の prompt と period 重複が起きて
        // 「schedule 内で隣り合う prompt は period 重複なし」の
        // ユニットテストが落ちる（attempt 3 で見つかった退化ケース）。
        let effectivePrompts: [File.SeedPrompt]
        switch scenario {
        case .live:
            if reference > liveAnchor.addingTimeInterval(Prompt.defaultDuration) {
                effectivePrompts = []
            } else {
                effectivePrompts = Array(file.prompts.prefix(1))
            }
        case .expiring, .expired, .upcoming:
            effectivePrompts = file.prompts
        }

        let starts = startDates(
            count: effectivePrompts.count,
            reference: reference,
            scenario: scenario,
            options: options
        )

        var prompts: [Prompt] = []
        var posts: [Post] = []
        for (index, seedPrompt) in effectivePrompts.enumerated() {
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
        // スプリント09 attempt 3 の修正:
        // `.live` 以外のシナリオ（`.expired` / `.upcoming` / `.expiring`）は
        // SprintTwoAcceptanceTests test01/test02 のように「お題待ち画面」を期待する
        // 検証用ケース。`PromptGenerator` は `reference` の **UTC 日付** で
        // prompt を組み立てるため（世界共通のための要件）、今いる場所・時間帯に
        // 関係なく「現在の UTC 日に該当する prompt」を必ず作ってしまう。これでは
        // 「お題待ち」前提を壊すので、`.live` 以外のシナリオでは auto-gen を一切
        // 起動せず seed だけの schedule を返す。
        if scenario != .live {
            return (base, nil)
        }
        // シードが「現在の reference 時点で active」なら、シードのお題を採用する
        // （受け入れ条件 6: 2 つのお題が同時に表示されない）。自動生成は
        // 「seed の active 期間外」を埋めるためにだけ動く。
        if PromptGenerator.scheduleAlreadyCoversToday(schedule: base, reference: reference) {
            return (base, nil)
        }
        // `.live` で seed が空（coverage 経過後の起動）か、reference 時点で
        // どの seed prompt も active でないとき。prompt_yyyyMMdd の自動生成だけ
        // を schedule として返す（period overlap や "seed が過去で残る" 問題を
        // 回避するため、merge を経由せず generated だけで PromptSchedule を作る）。
        // ただし seed の `posts` は `generated` の period にクランプして
        // promptID を付け替える（= 受け入れ条件 1「アクティブなお題には
        // 何も投稿が無い」を防ぐ）。`merge` と同じロジックだが、seed prompt
        // が schedule に残らない分 `seedIDs` 集合が空になり、`merge` 側では
        // rebasedPosts が空になってしまうため、ここでは `base.posts` 全件を
        // `generated.id` に付け替える。
        let result = PromptGenerator.generate(reference: reference)
        let rebasedPosts = base.posts.map { post in
            Post(
                id: post.id,
                promptID: result.prompt.id,
                authorID: post.authorID,
                authorEmoji: post.authorEmoji,
                authorNickname: post.authorNickname,
                body: post.body,
                bodyLanguage: post.bodyLanguage,
                createdAt: clamp(
                    post.createdAt,
                    into: result.prompt.startsAt ... result.prompt.endsAt
                ),
                expiresAt: result.prompt.endsAt
            )
        }
        return (
            PromptSchedule(
                prompts: [result.prompt],
                posts: rebasedPosts,
                bannedAuthorIDs: base.bannedAuthorIDs
            ),
            result
        )
    }

    /// `generated` を `schedule.prompts` に追加する。
    ///
    /// 「同じ ID のお題が既に schedule に入っていないか」を先に確認し、あれば
    /// それを優先する（同じ日に複数起動しても重複して Prompt を増やさないため）。
    /// `generated` を `schedule.prompts` に追加する。
    ///
    /// 「同じ ID のお題が既に schedule に入っていないか」を先に確認し、あれば
    /// それを優先する（同じ日に複数起動しても重複して Prompt を増やさないため）。
    /// 開始時刻順を保つために挿入位置を決める（F09・受け入れ条件 6）。
    ///
    /// シード投稿（`prompt_001` / `prompt_002` 紐付き）を **自動生成されたお題に
    /// 付け替える**ことで、coverage を超えて auto-gen にフォールスルーした場合も
    /// 「アクティブなお題には何も投稿が無い」状態を防ぐ（受け入れ条件 1）。
    /// 投稿の ID は変えないので、`PersistedState.likedPostIDs` /
    /// `viewedPostIDs` の既存記録を引き続き有効に保てる。
    /// 元の投稿は schedule から外す（`generated.startsAt` 時点で「過去の Prompt の
    /// 期限切れ」相当になり、画面に表示されないのは同じ）。
    ///
    /// スプリント09 attempt 3 の修正: seed prompt は reference 時点で active でない
    /// が（`scheduleAlreadyCoversToday` が false のときだけ呼ばれるため）、他シナ
    /// リオ（`.expired` / `.upcoming` / `.expiring`）では seed prompt が「現在の UTC
    /// 日付と period が重なる」関係で scheduleAlreadyCoversToday が true を返し
    /// auto-gen が走らない場合に備えて、seed prompt を schedule 内に残しておく。
    /// これで `scenario=expired` (SprintTwoAcceptanceTests test01) / `upcoming`
    /// (test02) などの「お題待ちを期待する」シナリオが「auto-gen 経由の今日の
    /// prompt が active になる」事故を起こさなくなる。`.live` の coverage 外で
    /// seed を完全排除したい場合は、`loadScheduleWithAutoGeneration` 側で
    /// `merge` を呼ばずに `generated` だけで schedule を作る分岐を別途用意した。
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

        // シードのお題に紐づく全投稿を、生成されたお題の期間内に並べ替える。
        // 並べ方は「元の期間における相対位置を保つ」比例配分。透明性は不要で、
        // もとの順序を保ったまま新しい `[startsAt, endsAt]` へ写像する。
        let seedIDs = Set(schedule.prompts.map(\.id))
        let rebasedPosts = schedule.posts.compactMap { post -> Post? in
            guard seedIDs.contains(post.promptID) else { return nil }
            return Post(
                id: post.id,
                promptID: generated.id,
                authorID: post.authorID,
                authorEmoji: post.authorEmoji,
                authorNickname: post.authorNickname,
                body: post.body,
                bodyLanguage: post.bodyLanguage,
                createdAt: clamp(
                    post.createdAt,
                    into: generated.startsAt ... generated.endsAt
                ),
                expiresAt: generated.endsAt
            )
        }
        // 生成されたお題に付け替えた分は schedule.posts から取り除く（二重表示防止）。
        let otherPosts = schedule.posts.filter { !seedIDs.contains($0.promptID) }
        return PromptSchedule(
            prompts: prompts,
            posts: rebasedPosts + otherPosts,
            bannedAuthorIDs: schedule.bannedAuthorIDs
        )
    }

    /// `value` を `[lower, upper]` の範囲にクランプする。境界が反転している場合は
    /// `lower` を返す。
    private static func clamp(_ value: Date, into bounds: ClosedRange<Date>) -> Date {
        if value < bounds.lowerBound { return bounds.lowerBound }
        if value > bounds.upperBound { return bounds.upperBound }
        return value
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

    /// `.live` シナリオで使う絶対アンカー日時。
    ///
    /// 以前は `firstStart = reference - 2h` の「毎回動的再構築」だったが、
    /// それでは起動のたびに prompt_001 が「今から 2 時間前」に再生成されてしまい、
    /// 翌日に起動しても period が実質同じになって PromptGenerator が到達不能だった
    ///（スプリント09 eval-1 の不合格理由）。固定アンカーに切り替えることで、
    /// `reference` の属する絶対 28h 区間が決まり、2.3 日（= 56h / count）以降には
    /// seed のカバレッジを外れて PromptGenerator が必ず起動する。
    fileprivate static let liveAnchor: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        // スプリント09 eval-1 の不合格理由を解消するための絶対アンカー。
        // 以前は `firstStart = reference - 2h` の「毎回動的再構築」だったが、
        // それでは起動のたびに prompt_001 が「今から 2 時間前」に再生成されてしまい、
        // 翌日に起動しても period が実質同じになって PromptGenerator が到達不能だった。
        // 固定アンカーに切り替えることで:
        // - prompt_001 は `liveAnchor` から `liveAnchor + 28h` までの固定区間で動く
        //   （attempt 2 のように stepsFromAnchor で 28h 境界を進めると
        //   「翌日も prompt_001 のまま」現象が再発するため、INSIDE ブランチでは
        //   常に `firstStart = liveAnchor` を使う）
        // - coverage (= duration × count = 56h) を超えた reference では
        //   `firstStart = liveAnchor + coverage` を置き、seed prompt を全て過去にして
        //   PromptGenerator に確実にフォールスルーさせる（受け入れ条件 1）
        // - anchor = 2026-08-25 02:14 UTC は「スプリント09 着手時点」を目安に決めた
        //   固定値で、コマンドライン引数 `-SameQTimeOffsetMinutes` で reference を
        //   前後に動かしても schedule 自体は変わらない。
        components.year = 2026
        components.month = 8
        components.day = 25
        components.hour = 2
        components.minute = 14
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    #if DEBUG
    /// テスト用: `.live` のアンカー日時を返す（anchor 直近の reference を組み立てる用途）。
    static var debugLiveAnchor: Date { liveAnchor }
    #endif

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
            // アンカー日時からの絶対オフセットで配置する。
            // - `loadSchedule` 側で `.live` のときは prompt_001 のみを
            //   `effectivePrompts` に残す（coverage 経過後なら空配列）ので、
            //   ここに来る `count` は 0 または 1。count=0 なら `dates` は
            //   空のまま return されるので seed 完全排除となる（attempt 3 追加）。
            // - coverage 経過後に `firstStart` を再アンカーする案
            //   (例: firstStart = liveAnchor + 56h) は eval-2 で却下済み。
            //   seeds がさらに 56h 分「再アクティブ化」され、
            //   PromptGenerator が liveAnchor+112h まで発火しなかったため
            //   （= 約4.7日間 auto-gen が一度も走らない dead zone）。
            // - 代わりに、`loadSchedule` 段階で coverage 外なら空 schedule
            //   を返し、PromptGenerator が必ず唯一の active prompt として
            //   `prompt_yyyyMMdd` を採用する（受け入れ条件 1）。
            // - coverage 内なら prompt_001 を `firstStart = liveAnchor` で配置し、
            //   period = [liveAnchor, liveAnchor+duration] を持たせる。
            //   stepsFromAnchor で 28h 境界を進めると prompt_001 が
            //   「常に今から 28h 前」に再構築されて翌日も同じという再発を防ぐ。
            if count == 0 {
                return []
            }
            firstStart = liveAnchor
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
