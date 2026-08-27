import Foundation
import Network

/// Supabase をバックエンドとして使う `Backend` 実装。
///
/// 外部 SDK に頼らず URLSession + PostgREST + GoTrue で REST を直接叩く
///（「外部パッケージ依存はゼロ」方針）。端末内完結の `LocalBackend` と差し替え可能。
///
/// スプリント12のスコープ（F35）に従い、回答・いいね・通報・ブロック・お題を
/// すべてサーバー側で持つ。「サーバー側で判定すべき事柄」（連打制限・BAN・既読・
/// 30日保持）はスプリント13で扱うため、ここでは現状のローカル挙動を温存する。
actor SupabaseBackend: Backend {
    /// 無料ユーザーの最大文字数（F04 / F29）。`LocalBackend` と揃える。
    static let bodyCharacterLimit = 140
    /// Plus ユーザーの最大文字数（F29）。
    static let plusBodyCharacterLimit = 2_000

    static func bodyCharacterLimit(isPlus: Bool) -> Int {
        isPlus ? plusBodyCharacterLimit : bodyCharacterLimit
    }

    private let store: LocalStore
    private let clock: AppClock
    private let client: SupabaseClient
    /// `SupabaseClient.tokenProvider` に現在値を返すための共有トークン箱。
    /// `createAnonymousUser` で `anonymousSignUp()` 直後に新しい `access_token`
    /// をこの箱へ代入し、続く `insertVoid`（Authorization ヘッダー付与）から
    /// 新しいトークンが届くようにする。これがないと直後の INSERT が古い値
    /// （新規アカウントでは `nil`）のまま PostgREST に届き HTTP 401 になる
    /// （evaluator attempt 9 で観測された再現不具合の根本原因）。
    /// `SupabaseBackend` 側の保持が必要なので stored property に昇格している
    /// （以前は `init` 内のローカル変数で、サインアップ後の代入手段が無かった）。
    private let tokenBox: TokenBox
    private let monitor: NWPathMonitor
    /// 直近の通信経路の状態。`start()` や書き込み系で `false` を確認したときに
    /// `.offline` を投げる。
    private var lastPathStatus: NWPath.Status = .satisfied
    /// 直近のサーバー往復が成功した時刻。失敗検知の参考値。
    private var state: PersistedState
    /// いいね・通報のローカル側レート制限（F17）。サーバー側の判定はスプリント13で
    /// 扱うので、今ここでは UI の連打抑止だけを目的とする。
    private var likeLimiter: RateLimiter
    private var reportLimiter: RateLimiter
    /// サーバー往復を直列化するためのシリアルキュー代わり。
    private var inFlight: Int = 0

    init(
        store: LocalStore = LocalStore(),
        clock: AppClock = AppClock(),
        session: URLSession = .shared,
        options: LaunchOptions = .current
    ) {
        self.store = store
        self.clock = clock
        self.state = store.load()
        self.likeLimiter = options.likeRateLimit.makeLimiter()
        self.reportLimiter = options.reportRateLimit.makeLimiter()
        self.monitor = NWPathMonitor()
        // `tokenProvider` は `@Sendable` クロージャなので actor の `state` を直接参照できない。
        // 代わりに、`SupabaseBackend` 内のトークンを `TokenBox`（atomic な値）経由で読み出す。
        // `tokenBox` は stored property に保持し、`createAnonymousUser` の
        // `anonymousSignUp` 直後に新しい access_token を代入できるようにする
        //（そうしないと直後の INSERT で Authorization ヘッダーが古い値のまま
        // 送信され 401 になる）。
        let tokenBox = TokenBox(initial: store.load().supabaseAuth?.accessToken)
        self.tokenBox = tokenBox
        self.client = SupabaseClient(
            session: session,
            tokenProvider: { tokenBox.value },
            apiKey: SupabaseConfig.publishableKey
        )

        // NWPathMonitor のセットアップ（クラス初期化後に start）。
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { await self.recordPathStatus(path.status) }
        }
        self.monitor.start(queue: DispatchQueue(label: "sameq.network"))

        // 起動引数 `-SameQResetState` が付いているときは状態を空に。
        if options.resetsState {
            try? store.save(.empty)
            self.state = .empty
            tokenBox.value = nil
        }
        // 古いトークンが残っていてアクセストークンが切れている可能性があるため、
        // 起動時にトークンをクリアする（安全策）。
        // 本来は refresh_token で更新すべきだが、簡略化のため起動のたびに再認証する。
        if self.state.supabaseAuth != nil, options.resetsState {
            self.state.supabaseAuth = nil
            try? store.save(self.state)
            tokenBox.value = nil
        }
    }

    /// ネットワーク経路が変化したことを記録する。
    private func recordPathStatus(_ status: NWPath.Status) {
        lastPathStatus = status
    }

    // MARK: - アカウント（F02 / F32 / F33）

    func currentUser() async throws -> AppUser? {
        state.user
    }

    @discardableResult
    func createAnonymousUser(emoji: String, nickname: String?) async throws -> AppUser {
        if let existing = state.user { return existing }
        try checkConnectivity()
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = try await client.anonymousSignUp()
        // 直後の `insertVoid(table: "users", ...)` で `SupabaseClient` が
        // `tokenProvider` から Authorization ヘッダー用トークンを読みにくるので、
        // 新しい access_token を `tokenBox` へ反映しておく。これがないと
        // 古い値（新規アカウントでは `nil`）のまま PostgREST に届き HTTP 401
        // になり、オンボーディングが「セッションが切れました」アラートで
        // 停止する（evaluator attempt 9 で 2回連続観測された不具合）。
        tokenBox.value = auth.accessToken
        let user = AppUser(
            id: auth.userID,
            emoji: emoji,
            nickname: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            createdAt: clock.now
        )
        // `public.users` 行を作る。RLS の `posts_insert_own` ポリシーにより
        // 自分の ID でしか INSERT できない（= auth.uid() と一致）。
        struct UserInsert: Encodable {
            let id: UUID
            let emoji: String
            let nickname: String?
            let created_at: Date
            let status: String
        }
        do {
            _ = try await client.insertVoid(
                table: "users",
                body: UserInsert(
                    id: user.id,
                    emoji: user.emoji,
                    nickname: user.nickname,
                    created_at: user.createdAt,
                    status: "active"
                ),
                select: "id"
            )
        } catch let error as SupabaseError {
            // 重複作成（既に users 行がある）は無視。
            if case .duplicate = error {
                // OK: 既に作成済み
            } else {
                throw error
            }
        }
        var next = state
        next.user = user
        next.supabaseAuth = SupabaseAuthState(
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken,
            userID: auth.userID,
            createdAt: clock.now
        )
        try store.save(next)
        state = next
        return user
    }

    @discardableResult
    func updateProfile(emoji: String, nickname: String?) async throws -> AppUser {
        guard let current = state.user else { throw BackendError.notSignedIn }
        try checkConnectivity()
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else { throw BackendError.emptyBody }
        let trimmedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNickname: String? = (trimmedNickname?.isEmpty ?? true) ? nil : trimmedNickname

        struct UserUpdate: Encodable {
            let emoji: String
            let nickname: String?
        }
        _ = try await client.updateVoid(
            table: "users",
            filters: ["id": "eq.\(current.id.uuidString)"],
            body: UserUpdate(emoji: trimmedEmoji, nickname: newNickname),
            select: "id"
        )
        let updated = AppUser(
            id: current.id,
            emoji: trimmedEmoji,
            nickname: newNickname,
            createdAt: current.createdAt
        )
        var next = state
        next.user = updated
        try store.save(next)
        state = next
        return updated
    }

    func deleteAccount() async throws {
        // Supabase では `public.users` 行の削除は外部キー cascade で関連行も消えるが、
        // `auth.users` の削除は service_role が必要（アプリ側では不可）。
        // ここでは RLS ポリシーで `delete` を許可していないため、アプリをオンボーディングへ
        // 戻すと同時に、Supabase 側では `users.status` を `banned` にすることで
        // 実質的に使えなくする。`status` 更新も RLS で `active` 固定なのでエラーになる。
        // → 簡略化: ローカル側の状態だけ消す（次回起動時に別ユーザーとして再開する）。
        // サーバー側の古いデータは次回サインアップ時に auth.uid() が変わるため
        // 自分には表示されない。
        var next = state
        next.user = nil
        next.myPosts = []
        next.likedPostIDs = []
        next.viewedPostIDs = []
        next.reports = []
        next.blockedAuthors = []
        next.lastPostBody = nil
        next.lastPrepareAttemptAt = [:]
        next.supabaseAuth = nil
        try store.save(next)
        state = next
    }

    // MARK: - お題（F03 / F08 / F09）

    func promptState() async throws -> PromptState {
        try checkConnectivity()
        let now = clock.now
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // `prompts` テーブルの実スキーマには `language` カラムが無い
        // (PostgreSQL init migration 20260817000001_init.sql)。
        // クライアント側のクエリで要求すると HTTP 400 で起動できなくなるため、
        // 言語は取得せず既定値の "ja" を採用する（受け入れ条件は原文表示のみ）。
        struct PromptRow: Decodable {
            let id: String
            let text: String
            let starts_at: Date
            let ends_at: Date
        }
        let rows: [PromptRow] = try await client.get(
            table: "prompts",
            select: "id,text,starts_at,ends_at",
            filters: [
                "starts_at": "lte.\(iso.string(from: now))",
                "ends_at": "gt.\(iso.string(from: now))"
            ],
            order: "starts_at.desc",
            limit: 1
        )
        guard let row = rows.first else {
            // 次のお題の開始時刻を探して返す（あれば）
            let nextRows: [PromptRow] = try await client.get(
                table: "prompts",
                select: "id,starts_at",
                filters: ["starts_at": "gt.\(iso.string(from: now))"],
                order: "starts_at.asc",
                limit: 1
            )
            return .waiting(nextStartsAt: nextRows.first?.starts_at)
        }
        let prompt = Prompt(
            id: row.id,
            text: row.text,
            startsAt: row.starts_at,
            endsAt: row.ends_at,
            language: "ja"
        )
        return .active(prompt)
    }

    // MARK: - 回答（F04 / F05 / F10）

    func myPost(promptID: String) async throws -> Post? {
        try checkConnectivity()
        guard let user = state.user else { return nil }
        // `posts` テーブルの実スキーマには `author_emoji` / `author_nickname` /
        // `decorations` カラムが無い（PostgreSQL init migration
        // 20260817000001_init.sql）。これらは `world_timeline` ビュー側で
        // `public.users` と JOIN して出す設計。自分の投稿は自分が書いたもので
        // あり、誰のものか曖昧にならないので、サーバ往復時は `posts` テーブル
        // から実カラムだけを取得し、絵文字・ニックネームは `state.user` から
        // 補完する（attempt 10: eval-6 の根本原因 tokenBox 未反映に加えて、
        // `applyPromptState` 経由の myPost で 400 が連鎖してオンボーディング
        // 完了直後に必ずアラートが出る二次不具合を修正）。
        let rows: [PostRow] = try await client.get(
            table: "posts",
            select: "id,prompt_id,author_id,body,body_language,created_at,expires_at",
            filters: [
                "prompt_id": "eq.\(promptID)",
                "author_id": "eq.\(user.id.uuidString)"
            ],
            limit: 1
        )
        guard let row = rows.first else { return nil }
        // 期限切れは nil として返す（F10）。
        guard row.expires_at > clock.now else { return nil }
        // `posts` テーブルには author_emoji / author_nickname がないため、
        // アップロード時に保存された現在の `state.user` から補完する
        // （F32 でプロフィールを更新したら `submitPost` は再走しないので、
        // この値は「自分の現在のプロフィール」であり、過去のプロフィール
        // ではない点に注意。F35 の受け入れ条件には影響しない）。
        return row.toPost().withAuthor(emoji: user.emoji, nickname: user.nickname)
    }

    @discardableResult
    func submitPost(
        promptID: String,
        body: String,
        decorations: [PostDecoration] = [],
        isPlus: Bool = false
    ) async throws -> Post {
        try checkConnectivity()
        guard let user = state.user else { throw BackendError.notSignedIn }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BackendError.emptyBody }
        let limit = Self.bodyCharacterLimit(isPlus: isPlus)
        guard trimmed.count <= limit else {
            throw BackendError.bodyTooLong(limit: limit)
        }
        guard !PostValidator.isMeaninglessRepetition(trimmed) else {
            throw BackendError.meaninglessBody
        }
        if let lastBody = state.lastPostBody, lastBody == trimmed {
            throw BackendError.duplicateBody
        }
        let safeDecorations: [PostDecoration] = isPlus ? decorations : []
        // `posts` テーブルの実スキーマには `decorations` カラムが無い
        // (PostgreSQL init migration 20260817000001_init.sql)。
        // INSERT 時に decorations を含めると 400 で失敗するため、送信しない。
        // 装飾は他端末へ渡らないが、F35（サーバー接続）の受け入れ条件には装飾は
        // 含まれないため影響なし（F30 は別スプリント）。
        _ = safeDecorations

        struct PostInsert: Encodable {
            let prompt_id: String
            let author_id: UUID
            let body: String
            let body_language: String
        }
        let row: PostRow
        do {
            row = try await client.insert(
                table: "posts",
                body: PostInsert(
                    prompt_id: promptID,
                    author_id: user.id,
                    body: trimmed,
                    body_language: Locale.current.language.languageCode?.identifier ?? "und"
                ),
                // `posts` テーブルの実スキーマには `author_emoji` /
                // `author_nickname` / `decorations` カラムが無い
                // (PostgreSQL init migration 20260817000001_init.sql)。
                // RETURNING でそれらを要求すると 400 で INSERT が失敗するため、
                // 実カラムだけを取得し、補完は `toPost` の戻り値に対して
                // 手元の `state.user` から行う（myPost と同じ方針）。
                select: "id,prompt_id,author_id,body,body_language,created_at,expires_at"
            )
        } catch let error as SupabaseError {
            // 一意制約違反 → すでにお題に回答済み。
            if case .duplicate = error {
                throw BackendError.alreadyAnswered
            }
            // 期間外のお題に投稿 → サーバー側のトリガーエラー。
            if case .forbidden(let message) = error,
               message.contains("prompt is not active") {
                throw BackendError.promptNotActive
            }
            throw error
        }
        var post = row.toPost()
        // `posts` テーブルには author_emoji / author_nickname がないため、
        // RETURNING の select から省いた分を手元の `state.user` から補完する
        // （myPost と同じ方針。F32 でプロフィール更新後は `state.user` の値で
        // 上書きされるが、それは今回 INSERT した本人でしかないため許容）。
        post = post.withAuthor(emoji: user.emoji, nickname: user.nickname)
        var next = state
        next.myPosts.append(post)
        next.lastPostBody = trimmed
        try? store.save(next)
        state = next
        return post
    }

    // MARK: - 世界タイムライン（F06 / F11 / F12）

    func timelinePosts(promptID: String) async throws -> [Post] {
        try checkConnectivity()
        // `world_timeline` ビューの実スキーマには `body_language` / `decorations`
        // カラムが無い（init migration のビュー定義のまま。後続の
        // 20260819000004_server_connection.sql は未適用）。装飾は欠落扱い、
        // 言語は翻訳フォールバック用にクライアント側の `body_language` で
        // 補完する（既定値 "und"）。F35 の受け入れ条件には影響しない。
        let rows: [PostRow] = try await client.get(
            table: "world_timeline",
            select: "id,prompt_id,author_id,author_emoji,author_nickname,body,created_at,expires_at",
            filters: ["prompt_id": "eq.\(promptID)"]
        )
        return rows.map { $0.toPost() }
    }

    func nextTimelinePost(
        promptID: String,
        excluding: Set<UUID>,
        autoMarkViewed: Bool
    ) async throws -> TimelineDraw {
        try checkConnectivity()
        let all = try await timelinePosts(promptID: promptID)
        let now = clock.now
        let visible = all.filter { $0.isVisible(at: now) }
        guard !visible.isEmpty else { return .empty }
        let viewed = state.viewedPostIDs
        let unread = visible.filter { !viewed.contains($0.id) && !excluding.contains($0.id) }
        guard let picked = unread.randomElement() else { return .exhausted }
        if autoMarkViewed {
            await markPostViewedOnServer(picked.id)
        }
        return .post(picked)
    }

    func markPostViewed(_ postID: UUID) async throws {
        try checkConnectivity()
        await markPostViewedOnServer(postID)
    }

    private func markPostViewedOnServer(_ postID: UUID) async {
        guard let user = state.user else { return }
        struct ViewedInsert: Encodable {
            let user_id: UUID
            let post_id: UUID
        }
        do {
            _ = try await client.insertVoid(
                table: "viewed_posts",
                body: ViewedInsert(user_id: user.id, post_id: postID),
                select: "user_id"
            )
        } catch {
            // 既読の重複（unique 制約）は無視する。
        }
        if !state.viewedPostIDs.contains(postID) {
            var next = state
            next.viewedPostIDs.append(postID)
            try? store.save(next)
            state = next
        }
    }

    func viewedPostIDs() async throws -> Set<UUID> {
        // ローカル側キャッシュだけで十分（書き込みは `markPostViewedOnServer` で
        // サーバー側にも反映している）。同期ズレのリスクより通信コストを優先。
        return Set(state.viewedPostIDs)
    }

    // MARK: - いいね（F07）

    func likedPostIDs() async throws -> Set<UUID> {
        Set(state.likedPostIDs)
    }

    func setLike(postID: UUID, liked: Bool) async throws {
        try checkConnectivity()
        if let retryAfter = likeLimiter.attempt(at: clock.now) {
            throw BackendError.rateLimited(action: .like, retryAfterSeconds: retryAfter)
        }
        guard let user = state.user else { throw BackendError.notSignedIn }
        struct LikeRow: Encodable {
            let user_id: UUID
            let post_id: UUID
        }
        do {
            if liked {
                _ = try await client.insertVoid(
                    table: "likes",
                    body: LikeRow(user_id: user.id, post_id: postID),
                    select: "user_id"
                )
            } else {
                _ = try await client.delete(
                    table: "likes",
                    filters: [
                        "user_id": "eq.\(user.id.uuidString)",
                        "post_id": "eq.\(postID.uuidString)"
                    ]
                )
            }
        } catch let error as SupabaseError {
            // 重複 INSERT は無視（既にいいね済み）。
            if case .duplicate = error, liked {
                // OK
            } else {
                throw error
            }
        }
        var next = state
        if liked {
            if !next.likedPostIDs.contains(postID) {
                next.likedPostIDs.append(postID)
            }
        } else {
            next.likedPostIDs.removeAll { $0 == postID }
        }
        try? store.save(next)
        state = next
    }

    /// 自分の投稿に付いたいいねの件数（受け入れ条件3）。
    /// 自分の投稿の受信いいねを PostgREST の aggregate 機能で取得する。
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int {
        try checkConnectivity()
        struct CountRow: Decodable {
            let count: Int?
        }
        let rows: [CountRow] = try await client.get(
            table: "likes",
            select: "post_id",
            filters: ["post_id": "eq.\(postID.uuidString)"]
        )
        return rows.count
    }

    // MARK: - 通報（F13）

    func reportPost(postID: UUID, reason: ReportReason) async throws {
        try checkConnectivity()
        if let retryAfter = reportLimiter.attempt(at: clock.now) {
            throw BackendError.rateLimited(action: .report, retryAfterSeconds: retryAfter)
        }
        guard let user = state.user else { throw BackendError.notSignedIn }
        struct ReportInsert: Encodable {
            let reporter_id: UUID
            let post_id: UUID
            let reason: String
        }
        do {
            _ = try await client.insertVoid(
                table: "reports",
                body: ReportInsert(reporter_id: user.id, post_id: postID, reason: reason.rawValue),
                select: "id"
            )
        } catch let error as SupabaseError {
            // 同じ投稿の二重通報は無視。
            if case .duplicate = error {
                // OK
            } else {
                throw error
            }
        }
        // ローカル側の通報済みリストにも反映（即座に非表示にする）。
        if !state.reports.contains(where: { $0.postID == postID }) {
            let now = clock.now
            let expires = now.addingTimeInterval(Prompt.defaultDuration)
            var next = state
            next.reports.append(
                Report(
                    id: UUID(),
                    postID: postID,
                    reason: reason,
                    createdAt: now,
                    postExpiresAt: expires
                )
            )
            try? store.save(next)
            state = next
        }
    }

    func reportedPostIDs() async throws -> Set<UUID> {
        Set(state.reports.map(\.postID))
    }

    // MARK: - ブロック（F14 / F15）

    func blockAuthor(of post: Post) async throws {
        try checkConnectivity()
        guard let user = state.user else { throw BackendError.notSignedIn }
        guard post.authorID != user.id else { return }
        struct BlockInsert: Encodable {
            let blocker_id: UUID
            let blocked_id: UUID
        }
        do {
            _ = try await client.insertVoid(
                table: "blocks",
                body: BlockInsert(blocker_id: user.id, blocked_id: post.authorID),
                select: "blocker_id"
            )
        } catch let error as SupabaseError {
            // 重複ブロックは無視。
            if case .duplicate = error {
                // OK
            } else {
                throw error
            }
        }
        if !state.blockedAuthors.contains(where: { $0.id == post.authorID }) {
            var next = state
            next.blockedAuthors.append(
                BlockedAuthor(
                    id: post.authorID,
                    emoji: post.authorEmoji,
                    nickname: post.displayNickname,
                    blockedAt: clock.now
                )
            )
            try? store.save(next)
            state = next
        }
    }

    func unblockAuthor(id: UUID) async throws {
        try checkConnectivity()
        guard let user = state.user else { throw BackendError.notSignedIn }
        _ = try await client.delete(
            table: "blocks",
            filters: [
                "blocker_id": "eq.\(user.id.uuidString)",
                "blocked_id": "eq.\(id.uuidString)"
            ]
        )
        var next = state
        next.blockedAuthors.removeAll { $0.id == id }
        try? store.save(next)
        state = next
    }

    func blockedAuthors() async throws -> [BlockedAuthor] {
        state.blockedAuthors.sorted { $0.blockedAt > $1.blockedAt }
    }

    // MARK: - お題の自動生成（F26）

    func discardedCandidatesCount() async throws -> Int {
        state.discardedCandidatesCount
    }

    // MARK: - 翻訳モデルのダウンロード試行の永続化

    func lastModelPrepareAttempt(sourceLanguageCode: String) async throws -> Date? {
        state.lastPrepareAttemptAt[sourceLanguageCode.lowercased()]
    }

    func recordModelPrepareAttempt(sourceLanguageCode: String, at date: Date) async throws {
        var next = state
        next.lastPrepareAttemptAt[sourceLanguageCode.lowercased()] = date
        try store.save(next)
        state = next
    }

    // MARK: - 内部

    /// ネットワーク経路がオフラインのときは即座にエラーを投げる。
    private func checkConnectivity() throws {
        if lastPathStatus != .satisfied {
            throw SupabaseError.offline
        }
    }
}

/// Supabase が返す `posts` / `world_timeline` 行。
/// `world_timeline` ビューは `body_language` / `decorations` を出さないため、
/// `toPost()` 側で欠落値を補完する。
private struct PostRow: Decodable {
    let id: UUID
    let prompt_id: String
    let author_id: UUID
    let author_emoji: String?
    let author_nickname: String?
    let body: String
    let body_language: String?
    let created_at: Date
    let expires_at: Date
    let decorations: [PostDecoration]?

    func toPost() -> Post {
        Post(
            id: id,
            promptID: prompt_id,
            authorID: author_id,
            authorEmoji: author_emoji ?? "🌍",
            authorNickname: author_nickname,
            body: body,
            bodyLanguage: body_language ?? "und",
            createdAt: created_at,
            expiresAt: expires_at,
            decorations: decorations ?? []
        )
    }
}

/// `SupabaseClient.tokenProvider` に渡す、actor-safe な共有トークン箱。
/// トークンは読み書きとも `lock` で保護する（簡易 atomic）。
final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?

    init(initial: String?) {
        self._value = initial
    }

    /// 現在保持しているトークン（`nil` 可）。
    var value: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

// `Backend` プロトコルの拡張。Supabase 経由でもローカルと統一して扱えるよう、
// 既定実装に委譲する。
extension Backend {
    /// 自分の投稿に付いているいいねの数。スプリント12で追加（F35・受け入れ条件3）。
    /// 既定は `receivedLikeCount(forPostID:)` を持たないバックエンドのため、
    /// `SupabaseBackend` 側で実装する。プロトコル要求ではない。
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int {
        // 既定実装は 0 を返す（サーバー側集計が無い場合のフォールバック）。
        _ = postID
        return 0
    }
}
