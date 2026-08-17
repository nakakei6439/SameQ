import Foundation

/// 端末内で完結する `Backend` 実装。
///
/// Supabase のクラウドプロジェクトがまだ存在せず、URL / anon key を持っていないため、
/// スプリント01ではこの実装で動かす。テーブル構成と RLS は `supabase/migrations/` に
/// 先に定義してあり、そちらへ差し替えても UI 層は変更不要。
actor LocalBackend: Backend {
    /// 回答の最大文字数（無料ユーザー。Plus の長文はスプリント10）。
    static let bodyCharacterLimit = 140

    private let store: LocalStore
    private let seed: SeedCatalog
    private var state: PersistedState

    /// 起動引数にこれが含まれていると、保存済みの状態を捨てて初回設定からやり直す。
    /// UI テストと評価者の再検証用。Debug ビルドでのみ効く。
    static let resetLaunchArgument = "-SameQResetState"

    init(store: LocalStore = LocalStore(), seed: SeedCatalog? = nil) {
        self.store = store
        self.seed = seed ?? ((try? SeedCatalog.load()) ?? SeedCatalog(prompt: Prompt(id: "prompt_000", text: ""), posts: []))

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.resetLaunchArgument) {
            try? store.save(.empty)
            self.state = .empty
            return
        }
        #endif
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
            createdAt: Date()
        )
        var next = state
        next.user = user
        try store.save(next)
        state = next
        return user
    }

    // MARK: お題

    func activePrompt() async throws -> Prompt {
        seed.prompt
    }

    // MARK: 回答

    func myPost(promptID: String) async throws -> Post? {
        state.myPosts.first { $0.promptID == promptID }
    }

    @discardableResult
    func submitPost(promptID: String, body: String) async throws -> Post {
        guard let user = state.user else { throw BackendError.notSignedIn }
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
            createdAt: Date()
        )
        var next = state
        next.myPosts.append(post)
        try store.save(next)
        state = next
        return post
    }

    // MARK: 世界タイムライン

    func timelinePosts(promptID: String) async throws -> [Post] {
        let myAuthorID = state.user?.id
        return seed.posts.filter { post in
            post.promptID == promptID && post.authorID != myAuthorID
        }
    }

    // MARK: いいね

    func likedPostIDs() async throws -> Set<UUID> {
        Set(state.likedPostIDs)
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
}
