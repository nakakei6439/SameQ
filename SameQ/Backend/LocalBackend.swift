import Foundation

/// 端末内で完結する `Backend` 実装。
///
/// Supabase のクラウドプロジェクトがまだ存在せず、URL / anon key を持っていないため、
/// この実装で動かす。テーブル構成と RLS は `supabase/migrations/` に
/// 先に定義してあり、そちらへ差し替えても UI 層は変更不要。
///
/// お題の日程は起動時に `PromptSchedule` として1回だけ組み立て、
/// 「今」の判定はすべて `AppClock` を通す（F09 / F10）。
actor LocalBackend: Backend {
    /// 無料ユーザーの最大文字数（F04 / F29）。Plus の長文は `plusBodyCharacterLimit`。
    static let bodyCharacterLimit = 140
    /// Plus ユーザーの最大文字数（F29）。本文の折りたたみターゲットは
    /// 無料と同じ 140 文字（`PostBodyInspector.isLongForm` の判定）。
    static let plusBodyCharacterLimit = 2_000

    /// `isPlus` の状態に応じた本文文字数上限を返す。
    /// Plus でないユーザーが長文を投稿しようとしたら `bodyTooLong`（F29 / F30）。
    static func bodyCharacterLimit(isPlus: Bool) -> Int {
        isPlus ? plusBodyCharacterLimit : bodyCharacterLimit
    }

    private let store: LocalStore
    private let clock: AppClock
    private let schedule: PromptSchedule
    private var state: PersistedState
    /// いいね・通報の連打制限（F17）。プロセス内だけの状態（再起動でリセットされる）。
    private var likeLimiter: RateLimiter
    private var reportLimiter: RateLimiter

    init(
        store: LocalStore = LocalStore(),
        clock: AppClock = AppClock(),
        schedule: PromptSchedule? = nil,
        options: LaunchOptions = .current
    ) {
        self.store = store
        self.clock = clock
        // お題の自動生成（F26 / F27）を取り込んだ日程構築。
        // `seedOnly: options.seedOnly` でユニットテストや特定検証用にシードのみの日程に
        // 戻せる（既定では自動生成あり）。
        let built = (try? SeedCatalog.loadScheduleWithAutoGeneration(
            reference: clock.now,
            scenario: options.scenario,
            options: options,
            seedOnly: options.seedOnly,
            skipSeed: options.skipSeed
        )) ?? (PromptSchedule(prompts: [], posts: []), nil)
        let builtSchedule = built.0
        let builtGeneration = built.1
        self.schedule = schedule ?? builtSchedule
        self.likeLimiter = options.likeRateLimit.makeLimiter()
        self.reportLimiter = options.reportRateLimit.makeLimiter()

        if options.resetsState {
            // 起動引数 `-SameQResetState`（Debug のみ）。UI テストと評価者の再検証用。
            try? store.save(.empty)
            self.state = .empty
            // 破棄件数の積算は別フィールドなので、`resetsState` でクリアされない問題はない。
            // 起動時の自動生成分の破棄は別途 `discardedCandidatesCount` に積算するため、
            // resetsState 経路でも生成結果を反映する。
            if let generation = builtGeneration {
                var empty = PersistedState.empty
                empty.discardedCandidatesCount = generation.discarded.count
                try? store.save(empty)
            }
            return
        }
        var loaded = store.load()
        if options.resetsViewed {
            // 起動引数 `-SameQResetViewed`（Debug のみ）。
            // アカウント・自分の回答・いいねは残したまま、既読だけを消して読み直せるようにする。
            loaded.viewedPostIDs = []
            try? store.save(loaded)
        }
        // 起動時の自動生成で破棄された候補があれば、`PersistedState` の累計件数に足す
        // （受け入れ条件 4）。`save` はまとめて 1 回で済ませる。
        if let generation = builtGeneration, !generation.discarded.isEmpty {
            loaded.discardedCandidatesCount += generation.discarded.count
            try? store.save(loaded)
        }
        self.state = loaded
    }

    // MARK: アカウント

    func currentUser() async throws -> AppUser? {
        state.user
    }

    @discardableResult
    func createAnonymousUser(emoji: String, nickname: String?) async throws -> AppUser {
        if let existing = state.user { return existing }
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = AppUser(
            id: UUID(),
            emoji: emoji,
            nickname: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            createdAt: clock.now
        )
        var next = state
        next.user = user
        try store.save(next)
        state = next
        return user
    }

    /// 絵文字・ニックネームを更新し、過去の自分の `Post` の表示情報も書き換える（F32）。
    ///
    /// 仕様では「自分の情報が新しい内容になる」とだけ書かれている。
    /// `myPosts`（保存済みの自分の回答）の `authorEmoji` / `authorNickname` を
    /// 遡って更新することで、タイムラインの候補に出てきた自分の過去回答が
    /// 新しい見た目で表示される（受け入れ条件2）。
    @discardableResult
    func updateProfile(emoji: String, nickname: String?) async throws -> AppUser {
        guard let current = state.user else { throw BackendError.notSignedIn }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else { throw BackendError.emptyBody }
        let trimmedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNickname: String? = (trimmedNickname?.isEmpty ?? true) ? nil : trimmedNickname

        var next = state
        let updated = AppUser(
            id: current.id,
            emoji: trimmedEmoji,
            nickname: newNickname,
            createdAt: current.createdAt
        )
        next.user = updated
        // 自分の過去の投稿の見た目も更新する。
        // 期限切れの投稿も `myPosts` には残っているので（削除は次の `pruneExpired` の役）、
        // ここでは全件を更新する。表示期限を過ぎたものは画面に出ないので副作用はない。
        next.myPosts = state.myPosts.map { post in
            guard post.authorID == current.id else { return post }
            return Post(
                id: post.id,
                promptID: post.promptID,
                authorID: post.authorID,
                authorEmoji: trimmedEmoji,
                authorNickname: newNickname,
                body: post.body,
                bodyLanguage: post.bodyLanguage,
                createdAt: post.createdAt,
                expiresAt: post.expiresAt,
                decorations: post.decorations
            )
        }
        try store.save(next)
        state = next
        return updated
    }

    /// アカウントを削除する（F33）。
    ///
    /// ユーザー本体に加え、関連する全ての端末内データを消去する。
    /// `discardedCandidatesCount` だけは「積算統計」として残す（リセットしない）。
    /// 削除後は `currentUser()` が nil を返し、UI 側は初回設定へ戻れる。
    func deleteAccount() async throws {
        var next = state
        next.user = nil
        next.myPosts = []
        next.likedPostIDs = []
        next.viewedPostIDs = []
        next.reports = []
        next.blockedAuthors = []
        next.lastPostBody = nil
        next.lastPrepareAttemptAt = [:]
        // `discardedCandidatesCount` は積算情報なので保持する。
        try store.save(next)
        state = next
    }

    // MARK: お題

    func promptState() async throws -> PromptState {
        let now = clock.now
        pruneExpired(at: now)
        if let prompt = schedule.activePrompt(at: now) {
            return .active(prompt)
        }
        return .waiting(nextStartsAt: schedule.nextStart(after: now))
    }

    // MARK: 回答

    func myPost(promptID: String) async throws -> Post? {
        let now = clock.now
        pruneExpired(at: now)
        return state.myPosts.first { $0.promptID == promptID && $0.isVisible(at: now) }
    }

    @discardableResult
    func submitPost(
        promptID: String,
        body: String,
        decorations: [PostDecoration] = [],
        isPlus: Bool = false
    ) async throws -> Post {
        let now = clock.now
        pruneExpired(at: now)
        guard let user = state.user else { throw BackendError.notSignedIn }
        // 期限が切れたお題や、まだ始まっていないお題には投稿させない（F09）。
        guard let prompt = schedule.prompt(id: promptID), prompt.isActive(at: now) else {
            throw BackendError.promptNotActive
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空白・改行のみ（F17）。
        guard !trimmed.isEmpty else { throw BackendError.emptyBody }
        let limit = Self.bodyCharacterLimit(isPlus: isPlus)
        guard trimmed.count <= limit else {
            throw BackendError.bodyTooLong(limit: limit)
        }
        // 同一文字の過剰な繰り返し（F17）。
        guard !PostValidator.isMeaninglessRepetition(trimmed) else {
            throw BackendError.meaninglessBody
        }
        guard !state.myPosts.contains(where: { $0.promptID == promptID }) else {
            throw BackendError.alreadyAnswered
        }
        // 直近の自分の投稿と同一の本文（F17）。`myPosts` は期限切れで掃除されるが、
        // `lastPostBody` はお題をまたいで残すのでここで検出できる。
        if let lastBody = state.lastPostBody, lastBody == trimmed {
            throw BackendError.duplicateBody
        }
        // 装飾は無料ユーザーは付けられない（F30）。Plus のときだけ装飾を受理する。
        let safeDecorations: [PostDecoration] = isPlus ? decorations : []

        let post = Post(
            id: UUID(),
            promptID: promptID,
            authorID: user.id,
            authorEmoji: user.emoji,
            authorNickname: user.displayNickname,
            body: trimmed,
            bodyLanguage: Locale.current.language.languageCode?.identifier ?? "und",
            createdAt: now,
            // 表示期限はお題の終了時刻に揃える（置いた前提2 / F10）。
            expiresAt: prompt.endsAt,
            decorations: safeDecorations
        )
        var next = state
        next.myPosts.append(post)
        next.lastPostBody = trimmed
        try store.save(next)
        state = next
        return post
    }

    // MARK: 世界タイムライン

    func timelinePosts(promptID: String) async throws -> [Post] {
        let now = clock.now
        pruneExpired(at: now)
        return candidates(promptID: promptID, at: now)
    }

    func nextTimelinePost(promptID: String, excluding: Set<UUID>, autoMarkViewed: Bool) async throws -> TimelineDraw {
        let now = clock.now
        pruneExpired(at: now)
        // 「そもそも誰も答えていない」と「ブロック・通報で出せるものが無くなった」を混同しない。
        guard !visibleOthers(promptID: promptID, at: now).isEmpty else { return .empty }
        let all = candidates(promptID: promptID, at: now)
        guard !all.isEmpty else { return .exhausted }

        let viewed = Set(state.viewedPostIDs)
        // `excluding` は永続化しない一時的な除外（バグ4の修正）。翻訳が一時的に失敗した回答を
        // 同じ巡回内で引き直さないためのもので、未読が尽きた扱いにはこれも含めて判定する
        // （除外中の候補しか残っていなければ `.exhausted` と同様に扱い、無限ループにしない）。
        let unread = all.filter { !viewed.contains($0.id) && !excluding.contains($0.id) }
        // 未読からランダムに1件（F11）。順番を持たないので「次に誰が出るか」は毎回変わる。
        guard let picked = unread.randomElement() else { return .exhausted }

        if autoMarkViewed {
            // 出したその場で既読にする（F12・従来どおり）。保存に失敗しても表示は続ける。
            var next = state
            next.viewedPostIDs.append(picked.id)
            try? store.save(next)
            state = next
        }
        return .post(picked)
    }

    /// `nextTimelinePost(..., autoMarkViewed: false)` で引いた回答を、実際に表示できると
    /// 確定した時点で既読にする（F12・バグ4の修正）。すでに既読なら何もしない。
    func markPostViewed(_ postID: UUID) async throws {
        guard !state.viewedPostIDs.contains(postID) else { return }
        var next = state
        next.viewedPostIDs.append(postID)
        try? store.save(next)
        state = next
    }

    func viewedPostIDs() async throws -> Set<UUID> {
        pruneExpired(at: clock.now)
        return Set(state.viewedPostIDs)
    }

    /// タイムラインに出しうる回答（既読を含む）。
    /// 同一お題・自分以外・表示期限内・BAN外・ブロック外・通報していない、をここで満たす
    /// （F11 / F13 / F14 / F16）。BAN外は `visibleOthers` 側で満たしている。
    private func candidates(promptID: String, at now: Date) -> [Post] {
        let blocked = Set(state.blockedAuthors.map(\.id))
        let reported = Set(state.reports.map(\.postID))
        guard !blocked.isEmpty || !reported.isEmpty else {
            return visibleOthers(promptID: promptID, at: now)
        }
        return visibleOthers(promptID: promptID, at: now).filter {
            !blocked.contains($0.authorID) && !reported.contains($0.id)
        }
    }

    /// 「同一お題・自分以外・表示期限内・BAN外」までの回答。
    /// ブロックと通報を**適用する前**の集合なので、`.empty`（誰も答えていない）の判定に使う。
    ///
    /// BAN状態の投稿者（F16）はここで除外する。運営のBAN切り替えはサーバー側の想定運用で、
    /// アプリ内にBAN管理UIは無いため、除外対象は `schedule.bannedAuthorIDs`
    /// （同梱シードの `bannedAuthorIDs`、または検証用に生成した投稿者）が持つ。
    private func visibleOthers(promptID: String, at now: Date) -> [Post] {
        // 期限切れの回答は誰にも見せない（F10）。有効期間外のお題なら 0 件。
        guard let prompt = schedule.prompt(id: promptID), prompt.isActive(at: now) else { return [] }
        let myAuthorID = state.user?.id
        return schedule.visiblePosts(promptID: prompt.id, at: now).filter {
            $0.authorID != myAuthorID && !schedule.bannedAuthorIDs.contains($0.authorID)
        }
    }

    // MARK: いいね

    func likedPostIDs() async throws -> Set<UUID> {
        pruneExpired(at: clock.now)
        return Set(state.likedPostIDs)
    }

    func setLike(postID: UUID, liked: Bool) async throws {
        // 短時間の連打制限（F17）。押す／外すのどちらも1回の操作として数える。
        if let retryAfter = likeLimiter.attempt(at: clock.now) {
            throw BackendError.rateLimited(action: .like, retryAfterSeconds: retryAfter)
        }
        var next = state
        if liked {
            guard !next.likedPostIDs.contains(postID) else { return }
            next.likedPostIDs.append(postID)
        } else {
            next.likedPostIDs.removeAll { $0 == postID }
        }
        try store.save(next)
        state = next
    }

    /// 自分の投稿に付いているいいねの件数（F35・受け入れ条件3）。
    /// 端末内完結の `LocalBackend` では他人のいいね情報は保持しないので常に 0。
    /// `Backend` プロトコルの要求メソッドになった（attempt 11: eval-7.md [1] a）。
    /// - Parameter postID: 対象投稿（ローカルには存在しない参照）。
    /// - Returns: 常に 0。
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int {
        // ローカルには受信いいねの記録が無いため 0。
        // Supabase 経路だけが「実機 2 台」で正しい値を返す（RPC で RLS バイパス）。
        _ = postID
        return 0
    }

    // MARK: 通報（F13）

    func reportPost(postID: UUID, reason: ReportReason) async throws {
        guard state.user != nil else { throw BackendError.notSignedIn }
        // 短時間の連打制限（F17）。同じ回答への二重送信の試みも1回として数える。
        if let retryAfter = reportLimiter.attempt(at: clock.now) {
            throw BackendError.rateLimited(action: .report, retryAfterSeconds: retryAfter)
        }
        // 通報対象の投稿の表示期限を `Report` に保持する（F34）。
        // 「投稿の表示期限から 30 日後に安全ログを自動削除」の起点に使う。
        // 候補（自分の `myPosts` 含む / 同梱シードの `schedule.posts`）を当たっても見つからない
        // 場合は、`createdAt + 28h`（お題の標準有効期間）でフォールバック。
        let postExpiresAt = postExpiresAt(forPost: postID)
            ?? clock.now.addingTimeInterval(Prompt.defaultDuration)
        var next = state
        // 同じ回答を二重に通報しても記録は1件だけ（表示対象から外れるのは同じ）。
        guard !next.reports.contains(where: { $0.postID == postID }) else { return }
        next.reports.append(
            Report(
                id: UUID(),
                postID: postID,
                reason: reason,
                createdAt: clock.now,
                postExpiresAt: postExpiresAt
            )
        )
        try store.save(next)
        state = next
    }

    /// 該当投稿の `expiresAt` を、自分の過去投稿・同梱シードのスケジュールから探して返す。
    /// 見つからなければ nil（呼び出し側でフォールバックする）。
    private func postExpiresAt(forPost postID: UUID) -> Date? {
        if let mine = state.myPosts.first(where: { $0.id == postID }) {
            return mine.expiresAt
        }
        return schedule.posts.first(where: { $0.id == postID })?.expiresAt
    }

    func reportedPostIDs() async throws -> Set<UUID> {
        pruneExpired(at: clock.now)
        return Set(state.reports.map(\.postID))
    }

    // MARK: ブロック（F14 / F15）

    func blockAuthor(of post: Post) async throws {
        guard let user = state.user else { throw BackendError.notSignedIn }
        // 自分をブロックさせない（起こらないはずだが、起きると自分の回答が消える）。
        guard post.authorID != user.id else { return }
        var next = state
        guard !next.blockedAuthors.contains(where: { $0.id == post.authorID }) else { return }
        next.blockedAuthors.append(
            BlockedAuthor(
                id: post.authorID,
                emoji: post.authorEmoji,
                nickname: post.displayNickname,
                blockedAt: clock.now
            )
        )
        // ブロックした相手の回答は「読んだ」ことにしない。
        // 解除したときに再び表示対象へ戻す（受け入れ条件4）ため。
        let authorPostIDs = Set(
            schedule.posts.filter { $0.authorID == post.authorID }.map(\.id)
        ).union([post.id])
        next.viewedPostIDs.removeAll { authorPostIDs.contains($0) }
        try store.save(next)
        state = next
    }

    func unblockAuthor(id: UUID) async throws {
        var next = state
        guard next.blockedAuthors.contains(where: { $0.id == id }) else { return }
        next.blockedAuthors.removeAll { $0.id == id }
        try store.save(next)
        state = next
    }

    func blockedAuthors() async throws -> [BlockedAuthor] {
        // 新しくブロックした人を上に。表示するのは絵文字とニックネームだけ（F15）。
        state.blockedAuthors.sorted { $0.blockedAt > $1.blockedAt }
    }

    // MARK: お題の自動生成（F26）

    func discardedCandidatesCount() async throws -> Int {
        state.discardedCandidatesCount
    }

    // MARK: サーバー側ステータス（F36）

    /// `LocalBackend` はサーバを持たないため常に `"active"` を返す。
    /// BAN の模擬は引き続き `-SameQBanned` 起動引数（`LaunchOptions.isBanned`）が
    /// `AppSession.start()` の冒頭で `.banned` 画面固定にする経路で行う。
    func currentServerSideStatus() async throws -> String {
        "active"
    }

    // MARK: 翻訳モデルのダウンロード試行の永続化（受け入れ条件4・attempt 7）

    /// `Translator` のクールダウン判定用。アクター内なので他の書き込みと競合しない。
    func lastModelPrepareAttempt(sourceLanguageCode: String) async throws -> Date? {
        state.lastPrepareAttemptAt[sourceLanguageCode.lowercased()]
    }

    /// `Translator` が実際にダウンロードを試みた直後に呼ばれる。
    func recordModelPrepareAttempt(sourceLanguageCode: String, at date: Date) async throws {
        var next = state
        next.lastPrepareAttemptAt[sourceLanguageCode.lowercased()] = date
        try store.save(next)
        state = next
    }

    // MARK: 期限切れの掃除（F10 / F34）

    /// 表示期限を過ぎた自分の回答と、そこに紐づくいいね・既読を保存から落とす。
    ///
    /// 「その日の言葉は消える」ため履歴は持たない。消えた投稿への いいね も既読も残さない。
    /// 保存内容が変わったときだけ書き込む。
    ///
    /// 既読は「期限切れと**確認できた**投稿」に限って落とす。
    /// 検証用の起動引数で回答の顔ぶれが変わったときに、既読が黙って消えないようにするため。
    ///
    /// 通報（F34）は仕様により、**投稿の表示期限 + 30 日**まで安全対策のログとして残す。
    /// 30 日を過ぎたものは自動で削除する（サーバ側の `safety_logs` 30 日保持と一致）。
    /// 検証用には `LaunchOptions.safetyLogRetentionSeconds` で短縮できる
    ///（既定は `Backend.safetyLogRetentionSeconds` = 30 日）。
    ///
    /// ブロックは投稿ではなく相手に対するものなので、ここでは消さない（解除するまで残る）。
    private func pruneExpired(at now: Date) {
        let liveMyPosts = state.myPosts.filter { $0.isVisible(at: now) }
        let livePostIDs = Set(liveMyPosts.map(\.id)).union(
            schedule.posts.filter { $0.isVisible(at: now) }.map(\.id)
        )
        let expiredPostIDs = Set(state.myPosts.filter { !$0.isVisible(at: now) }.map(\.id)).union(
            schedule.posts.filter { !$0.isVisible(at: now) }.map(\.id)
        )
        let liveLikes = state.likedPostIDs.filter { livePostIDs.contains($0) }
        let liveViewed = state.viewedPostIDs.filter { !expiredPostIDs.contains($0) }
        // F34: 通報は「投稿の表示期限 + 30 日」が経過するまで残す。
        let retention = Self.resolveSafetyLogRetention()
        let liveReports = state.reports.filter { report in
            // まだ表示中の投稿なら常に残す。
            if !expiredPostIDs.contains(report.postID) { return true }
            // 表示期限切れの通報は `postExpiresAt + retention` を越えた時点で削除。
            return now.timeIntervalSince(report.postExpiresAt) < retention
        }

        guard liveMyPosts.count != state.myPosts.count
            || liveLikes.count != state.likedPostIDs.count
            || liveViewed.count != state.viewedPostIDs.count
            || liveReports.count != state.reports.count else {
            return
        }
        var next = state
        next.myPosts = liveMyPosts
        next.likedPostIDs = liveLikes
        next.viewedPostIDs = liveViewed
        next.reports = liveReports
        try? store.save(next)
        state = next
    }

    /// 安全ログの保持期間。`LaunchOptions.safetyLogRetentionSeconds` が 0 でなければ
    /// そちらを優先（検証用）。既定は 30 日。
    private static func resolveSafetyLogRetention() -> TimeInterval {
        let override = LaunchOptions.current.safetyLogRetentionSeconds
        return override > 0 ? override : SafetyLogDefaults.defaultRetentionSeconds
    }

    // MARK: 安全ログの自動削除（F36・受け入れ条件6）

    /// `pruneExpired(at: clock.now)` を呼び、削除された通報の件数を返す。
    /// `AppSession.start()` から 1 度だけ呼ばれる。
    func purgeExpiredSafetyLogs() async throws -> Int {
        let before = state.reports.count
        pruneExpired(at: clock.now)
        let after = state.reports.count
        return max(before - after, 0)
    }

    // MARK: サーバ時計（F36・受け入れ条件5・Backend プロトコル）

    /// LocalBackend は外部時計と無関係に `clock.now` を返す。サーバ時計とは
    /// 「端末の時計」と同じものを指す（端末内完結のため）。
    func currentServerTime() async throws -> Date {
        return clock.now
    }
}
