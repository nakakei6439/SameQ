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

        if options.resetsState {
            // 起動引数 `-SameQResetState`（Debug のみ）。UI テストと評価者の再検証用。
            try? store.save(.empty)
            self.state = .empty
            return
        }
        self.state = store.load()
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
        guard !trimmed.isEmpty else { throw BackendError.emptyBody }
        guard trimmed.count <= Self.bodyCharacterLimit else {
            throw BackendError.bodyTooLong(limit: Self.bodyCharacterLimit)
        }
        guard !state.myPosts.contains(where: { $0.promptID == promptID }) else {
            throw BackendError.alreadyAnswered
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
        try store.save(next)
        state = next
        return post
    }

    // MARK: 世界タイムライン

    func timelinePosts(promptID: String) async throws -> [Post] {
        let now = clock.now
        pruneExpired(at: now)
        // 期限切れの回答は誰にも見せない（F10）。有効期間外のお題なら 0 件。
        guard let prompt = schedule.prompt(id: promptID), prompt.isActive(at: now) else { return [] }
        let myAuthorID = state.user?.id
        return schedule.visiblePosts(promptID: prompt.id, at: now).filter { $0.authorID != myAuthorID }
    }

    // MARK: いいね

    func likedPostIDs() async throws -> Set<UUID> {
        pruneExpired(at: clock.now)
        return Set(state.likedPostIDs)
    }

    func setLike(postID: UUID, liked: Bool) async throws {
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

    // MARK: 期限切れの掃除（F10）

    /// 表示期限を過ぎた自分の回答と、そこに紐づくいいねを保存から落とす。
    ///
    /// 「その日の言葉は消える」ため履歴は持たない。消えた投稿への いいね も残さない。
    /// 保存内容が変わったときだけ書き込む。
    private func pruneExpired(at now: Date) {
        let liveMyPosts = state.myPosts.filter { $0.isVisible(at: now) }
        let livePostIDs = Set(liveMyPosts.map(\.id)).union(
            schedule.posts.filter { $0.isVisible(at: now) }.map(\.id)
        )
        let liveLikes = state.likedPostIDs.filter { livePostIDs.contains($0) }

        guard liveMyPosts.count != state.myPosts.count || liveLikes.count != state.likedPostIDs.count else {
            return
        }
        var next = state
        next.myPosts = liveMyPosts
        next.likedPostIDs = liveLikes
        try? store.save(next)
        state = next
    }
}
