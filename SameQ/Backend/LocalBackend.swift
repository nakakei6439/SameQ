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
    /// 回答の最大文字数（無料ユーザー。Plus の長文はスプリント10）。
    static let bodyCharacterLimit = 140

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
        self.schedule = schedule ?? ((try? SeedCatalog.loadSchedule(
            reference: clock.now,
            scenario: options.scenario,
            options: options
        )) ?? PromptSchedule(prompts: [], posts: []))
        self.likeLimiter = options.likeRateLimit.makeLimiter()
        self.reportLimiter = options.reportRateLimit.makeLimiter()

        if options.resetsState {
            // 起動引数 `-SameQResetState`（Debug のみ）。UI テストと評価者の再検証用。
            try? store.save(.empty)
            self.state = .empty
            return
        }
        var loaded = store.load()
        if options.resetsViewed {
            // 起動引数 `-SameQResetViewed`（Debug のみ）。
            // アカウント・自分の回答・いいねは残したまま、既読だけを消して読み直せるようにする。
            loaded.viewedPostIDs = []
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
    func submitPost(promptID: String, body: String) async throws -> Post {
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
        guard trimmed.count <= Self.bodyCharacterLimit else {
            throw BackendError.bodyTooLong(limit: Self.bodyCharacterLimit)
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
            expiresAt: prompt.endsAt
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

    // MARK: 通報（F13）

    func reportPost(postID: UUID, reason: ReportReason) async throws {
        guard state.user != nil else { throw BackendError.notSignedIn }
        // 短時間の連打制限（F17）。同じ回答への二重送信の試みも1回として数える。
        if let retryAfter = reportLimiter.attempt(at: clock.now) {
            throw BackendError.rateLimited(action: .report, retryAfterSeconds: retryAfter)
        }
        var next = state
        // 同じ回答を二重に通報しても記録は1件だけ（表示対象から外れるのは同じ）。
        guard !next.reports.contains(where: { $0.postID == postID }) else { return }
        next.reports.append(
            Report(id: UUID(), postID: postID, reason: reason, createdAt: clock.now)
        )
        try store.save(next)
        state = next
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

    // MARK: 期限切れの掃除（F10）

    /// 表示期限を過ぎた自分の回答と、そこに紐づくいいね・既読を保存から落とす。
    ///
    /// 「その日の言葉は消える」ため履歴は持たない。消えた投稿への いいね も既読も残さない。
    /// 保存内容が変わったときだけ書き込む。
    ///
    /// 既読と通報だけは「期限切れと**確認できた**投稿」に限って落とす。
    /// 検証用の起動引数で回答の顔ぶれが変わったときに、既読が黙って消えないようにするため。
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
        let liveReports = state.reports.filter { !expiredPostIDs.contains($0.postID) }

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
}
