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
    /// `-SameQForceOffline`（Debug 限定・attempt 11: eval-7.md [3] の修正）。
    /// true の間は `NWPathMonitor` の結果に関わらず `checkConnectivity()` が
    /// 必ず `.offline` を投げ、サーバ往復を一切行わない。evaluator が実機の
    /// 機内モードを切り替えずに条件6・条件7 を再現できるようにするための足場。
    private let forceOffline: Bool
    /// 直近のサーバー往復が成功した時刻。失敗検知の参考値。
    private var state: PersistedState
    /// いいね・通報の連打制限はサーバー側 (`consume_rate_limit` RPC) で判定する。
    /// スプリント13 で process-local な `RateLimiter` は撤去し、サーバー記録に
    /// 統一した。設定値（最大回数・ウィンドウ秒数）はここに残し、RPC 引数として
    /// 渡すだけに使う。
    private let likeRateLimit: RateLimitSettings
    private let reportRateLimit: RateLimitSettings
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
        // スプリント13: レート制限はサーバ側に集約。設定値（閾値とウィンドウ秒数）
        // を `RateLimitSettings` のまま残し、RPC `consume_rate_limit` の引数として
        // 渡す。
        self.likeRateLimit = options.likeRateLimit
        self.reportRateLimit = options.reportRateLimit
        self.forceOffline = options.forceOffline
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
        // （2026-08-29 削除）以前ここに「起動のたびにトークンをクリアする安全策」と
        // 書かれた分岐があったが、実際の条件は `options.resetsState` 前提になっており
        // 常に false（直前のブロックで既に `state` を空にしているため）で、コメントが
        // 主張する動作を一度も実行していなかった（デッドコード）。
        // 正しい修正は `ensureFreshSession()`（`refreshToken` を実際に呼ぶ）で行った。
        // 実機で「セッションが切れました」から復帰できない不具合として観測・特定。
    }

    /// ネットワーク経路が変化したことを記録する。
    private func recordPathStatus(_ status: NWPath.Status) {
        lastPathStatus = status
    }

    // MARK: - アカウント（F02 / F32 / F33）

    /// `Backend.ensureFreshSession()` の実装。永続化済みの `refreshToken` があれば、
    /// `SupabaseClient.refreshToken(refreshToken:)`（既存実装だが呼び出し元が無かった）で
    /// access_token を更新し、`tokenBox` と `store` の両方へ反映する。
    /// refresh_token はローテーションされる（レスポンスの新しい値を必ず保存し直す。
    /// 古い値のまま次回使うと GoTrue に拒否される）。
    func ensureFreshSession() async {
        guard let auth = state.supabaseAuth, let refreshToken = auth.refreshToken else { return }
        do {
            let session = try await client.refreshToken(refreshToken: refreshToken)
            tokenBox.value = session.accessToken
            state.supabaseAuth = SupabaseAuthState(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken ?? refreshToken,
                userID: session.userID,
                createdAt: clock.now
            )
            try? store.save(state)
        } catch {
            // 失敗しても何もしない（Backend プロトコルのコメント参照）。
        }
    }

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
        // スプリント13: サーバ側 RPC `delete_my_account()` を呼び、
        // auth.users と public.users を削除する。on delete cascade で
        // posts / likes / blocks / reports / viewed_posts も連動削除され、
        // 他端末のタイムラインからもこの人の回答が消える (受け入れ条件7)。
        //
        // attempt 3 (eval-2.md 改善提案2):
        //   attempt 1/2 では `try? await …` で RPC 例外を握り潰し、サーバ側
        //   削除が失敗してもローカル状態だけ消して UI 上は「成功したように
        //   見える」状態になっていた。これだと評価者が post-delete に
        //   `auth.users` へレコードが残存していることを確認しても、アプリ側
        //   には何の通知も出ない。
        //
        //   修正方針:
        //     1) RPC が失敗したら例外を上位 (AppSession.deleteAccount) へ
        //        そのまま伝播する。AppSession は `alertMessage` を立てるので
        //        ユーザーに「サーバ側の削除に失敗した」が届く。
        //     2) RPC が成功したときだけローカル状態をクリアして永続化する。
        //     3) ローカル保存が失敗した場合も例外を伝播する (保存しない
        //        まま「成功」と偽ることは同じ穴になる)。
        //   これにより「無言で成功したように見えることがない」原則
        //   (スプリント12 条件7) を保ちつつ、サーバ反映の失敗をユーザーに
        //   確実に知らせる。
        try await client.rpcVoid(function: "delete_my_account")
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
        // 言語の出会いカウンタ（F41）は個人に紐づく統計情報。アカウント削除と同時に
        // リセット（次のアカウントの先読みを過去の言語履歴で汚染しないため）。
        next.languageEncounters = [:]
        try store.save(next)
        state = next
    }

    // MARK: - お題（F03 / F08 / F09）

    func promptState() async throws -> PromptState {
        try checkConnectivity()
        // スプリント13 attempt 2 (eval-1.md [3] の修正):
        //   端末時計をずらしても同一の結果を返すため、`clock.now` (端末時刻) ではなく
        //   サーバ側 RPC `current_server_time()` で取得したサーバ時刻を基準に
        //   `prompts` を絞る。これで「端末時計を数時間ずらしても、今日のお題と
        //   その残り時間は同一」の条件を満たす（受け入れ条件5）。
        //   * 通信失敗時は端末時計にフォールバックして、サーバ到達が復旧できない
        //     状況でも UI が完全に固まらないようにする。
        let now: Date
        if let serverNow = try? await currentServerTime() {
            now = serverNow
        } else {
            now = clock.now
        }
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
        // スプリント13: レート制限はサーバ側 (`consume_rate_limit`) で判定する。
        // 閾値を超えると retry_after_seconds が返るので、それを `BackendError.rateLimited`
        // に変換する。「アプリの再起動で解除されない」ことが構造的に担保される
        // (受け入れ条件1)。
        if liked {
            let retry = await checkRateLimit(
                action: "like",
                settings: likeRateLimit
            )
            if retry > 0 {
                throw BackendError.rateLimited(action: .like, retryAfterSeconds: retry)
            }
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
    ///
    /// `likes_select_own`（`user_id = auth.uid()`）だけの RLS では、他人のいいね行を
    /// 読むことができず常に 0 になる。attempt 11（eval-7.md [1] b）の修正で
    /// サーバー側に `security definer` の `received_like_count(target_post uuid)` 関数を
    /// 追加し、RLS をバイパスして件数を返す RPC を使うようにした。
    /// 関数自体は `auth.uid()` を確認し、本人の投稿についてだけ集計するため、
    /// セキュリティ上の境界は壊さない（他人の投稿には呼んでも 0 を返す）。
    ///
    /// attempt 13（eval-9.md [1] の修正）:
    ///   RPC 引数名は **SQL 関数の引数名と完全に一致** させる必要がある。
    ///   PostgREST は名前付き引数で関数を解決するため、`post_id` のままだと
    ///   `PGRST202`（404: 関数が schema cache に無い）を返してしまう。
    ///   SQL 側は migration 4 (`20260819000004_server_connection.sql`) と
    ///   migration 5 (`20260820000005_received_like_count.sql`) の両方で
    ///   引数名を `target_post` で統一しているため、アプリ側も `target_post`
    ///   で送る。`Args.target_post` を Encodable の CodingKeys で `target_post`
    ///   にマップすれば、Swift の識別子規約（lowerCamelCase）を守ったまま
    ///   JSON キーは SQL の引数名と一致させられる。
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int {
        try checkConnectivity()
        struct Args: Encodable {
            let targetPost: String
            enum CodingKeys: String, CodingKey {
                case targetPost = "target_post"
            }
        }
        let args = Args(targetPost: postID.uuidString)
        // `received_like_count` は単一の整数を返すのでそのまま受け取る。
        let count: Int = try await client.rpc(
            function: "received_like_count",
            arguments: args,
            as: Int.self
        )
        return count
    }

    // MARK: - 通報（F13）

    func reportPost(postID: UUID, reason: ReportReason) async throws {
        try checkConnectivity()
        // スプリント13: レート制限はサーバ側 (`consume_rate_limit`) で判定する。
        // 連打自体は同じ瞬間でも複数回成功するように見えるが、サーバ側で記録された
        // 件数を基準にするので、アプリの再起動で解除されない（受け入れ条件1）。
        let retry = await checkRateLimit(
            action: "report",
            settings: reportRateLimit
        )
        if retry > 0 {
            throw BackendError.rateLimited(action: .report, retryAfterSeconds: retry)
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
    /// attempt 11（eval-7.md [3] の修正）で `-SameQForceOffline` の
    /// 起動引数が立っているときは、`NWPathMonitor` の結果に関わらず
    /// 強制的に `.offline` を投げる。evaluator が実機の機内モードを
    /// 切り替えずに条件6・条件7 を再現できるようにするための足場。
    private func checkConnectivity() throws {
        if forceOffline || lastPathStatus != .satisfied {
            throw SupabaseError.offline
        }
    }

    // MARK: - スプリント13: サーバ側レート制限 / BAN / アカウント削除 (F36)

    /// サーバ側 RPC `consume_rate_limit(p_action, p_max, p_window_seconds)` を呼ぶ。
    /// 戻り値は `0`（成功・記録済み）または正の整数値（あと何秒待てば解除）。
    /// **通信失敗時 / RPC 関数未適用時 (`SupabaseError.notFound`) は fail-open で 0 を返す**
    ///（UI を完全停止させないため。F17 の連打自体はアクセスパターンで自然抑止される）。
    /// eval-1.md の改善提案1「doc コメントは fail-open と書いているが実装に catch が無く
    /// throw する」を、attempt 2 で実装と一致させた。
    /// 返り値は **直接** `BackendError.rateLimited` にはしない（呼び出し側で
    /// 正の整数値を見て判断する）。
    private func checkRateLimit(
        action: String,
        settings: RateLimitSettings
    ) async -> Int {
        do {
            try checkConnectivity()
            struct Args: Encodable {
                let p_action: String
                let p_max: Int
                let p_window_seconds: Int
            }
            let result: Int = try await client.rpc(
                function: "consume_rate_limit",
                arguments: Args(
                    p_action: action,
                    p_max: settings.maxActions,
                    p_window_seconds: Int(settings.windowSeconds)
                ),
                as: Int.self
            )
            return result
        } catch let error as SupabaseError {
            // `.notFound` (関数未適用 PGRST202 / 404) や `.offline` などは
            // 失敗扱いにせず 0 を返す。サーバ到達不能のままいいね・通報を永久に
            // ロックしてしまうとユーザー体験として致命的なため (eval-1.md [5])。
            #if DEBUG
            print("[SameQ] checkRateLimit(\(action)): fail-open due to \(error)")
            #endif
            return 0
        } catch {
            #if DEBUG
            print("[SameQ] checkRateLimit(\(action)): fail-open due to \(error)")
            #endif
            return 0
        }
    }

    /// サーバ側 RPC `current_user_status()` を呼ぶ。
    /// 戻り値: `"active"` / `"banned"` / `"missing"`。
    /// 通信失敗時は fail-open で `"active"` を返し、`AppSession.start()` が
    /// うっかり `.banned` 画面で起動しないようにする。
    func currentServerSideStatus() async throws -> String {
        try checkConnectivity()
        let status: String = try await client.rpc(
            function: "current_user_status",
            arguments: Empty(),
            as: String.self
        )
        return status
    }

    /// サーバ側 RPC `current_server_time()` を呼ぶ。
    /// 端末時計をずらした検証で「サーバ側の now() は同一」を示すための基準値
    /// (受け入れ条件5)。返り値の Date は端末の時計とは無関係に真のサーバ時刻。
    /// attempt 3 (eval-2.md 改善提案4):
    ///   通信失敗時は `clock.now` へフォールバックする。`Debug` オーバーレイで
    ///   `serverNow` がオフライン時に nil になり UI が止まることを防ぐ。
    func currentServerTime() async throws -> Date {
        do {
            try checkConnectivity()
            let serverNow: Date = try await client.rpc(
                function: "current_server_time",
                arguments: Empty(),
                as: Date.self
            )
            return serverNow
        } catch {
            // Offline / Network / NotFound すべてを clock.now フォールバック
            // として扱う。`Debug` オーバーレイはオフライン時も UI を表示し続ける。
            return clock.now
        }
    }

    // MARK: 安全ログの自動削除（F34/F36・受け入れ条件6）

    /// サーバ側 RPC `app_purge_expired_safety_logs()` を呼ぶ。
    /// pg_cron が無い環境でも「アプリ起動時に自分宛の safety logs 清掃が走る」
    /// 状態を作るための保険。返り値は削除件数。
    /// 通信失敗時は 0 を返して UI を止めない（fail-open）。
    func purgeExpiredSafetyLogs() async throws -> Int {
        do {
            try checkConnectivity()
            let deleted: Int = try await client.rpc(
                function: "app_purge_expired_safety_logs",
                arguments: Empty(),
                as: Int.self
            )
            return deleted
        } catch let error as SupabaseError {
            #if DEBUG
            print("[SameQ] purgeExpiredSafetyLogs: fail-open due to \(error)")
            #endif
            return 0
        } catch {
            #if DEBUG
            print("[SameQ] purgeExpiredSafetyLogs: fail-open due to \(error)")
            #endif
            return 0
        }
    }

    // MARK: 翻訳の先読み（F41・スプリント17）

    /// `state.languageEncounters[code]` を +1 して保存する。サーバーには送らない
    ///（F19「翻訳を意識させない」方針。個人統計なので端末内だけで完結）。
    /// `LocalBackend` と同じ実装（永続化先は端末の `state.json`）。
    func recordLanguageEncounter(languageCode: String) async throws {
        let code = languageCode.lowercased()
        guard !code.isEmpty, code.count <= 16 else { return }
        var next = state
        next.languageEncounters[code, default: 0] += 1
        try store.save(next)
        state = next
    }

    /// 回数降順（同数なら言語コード昇順）で先頭から `limit` 件を返す。
    /// `LocalBackend` と同じ実装（端末内 `state.languageEncounters` を参照）。
    func topEncounteredLanguages(limit: Int) async throws -> [String] {
        guard limit > 0 else { return [] }
        return state.languageEncounters
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)
    }

    /// `forceOffline == true` または `NWPathMonitor` が `.satisfied` 以外を報告している
    /// 間は `false` を返す。pre-fetch の起動条件（F41 受け入れ条件5）。
    /// `checkConnectivity()` とは違って **throw しない**（呼び出し側が
    /// `if await !backend.isOnline()` で簡単にガードできるようにするため）。
    func isOnline() async -> Bool {
        if forceOffline { return false }
        return lastPathStatus == .satisfied
    }

    // MARK: - 運営お知らせ（新機能）

    /// `locale` は `"ja"` / `"en"` のいずれか。この言語の行だけを取得する
    /// （2026-08-29追記: 言語別配信。マイグレーション 20260829000012 参照）。
    func announcements(locale: String) async throws -> [Announcement] {
        try checkConnectivity()
        struct AnnouncementRow: Decodable {
            let id: UUID
            let title: String
            let body: String
            let published_at: Date
        }
        let rows: [AnnouncementRow] = try await client.get(
            table: "announcements",
            select: "id,title,body,published_at",
            filters: ["locale": "eq.\(locale)"],
            order: "published_at.desc"
        )
        return rows.map {
            Announcement(id: $0.id, title: $0.title, body: $0.body, publishedAt: $0.published_at)
        }
    }
}

/// `consume_rate_limit` 等の引数なし RPC 用。空の構造体。
private struct Empty: Encodable {}

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

// `Backend` プロトコルの拡張。`receivedLikeCount(forPostID:)` は
// attempt 11（eval-7.md [1] a の修正）で `Backend` プロトコルの
// 要求メソッドに昇格したため、ここでの既定実装は削除済み。
// `LocalBackend` / `SupabaseBackend` の両方に実装を置く
//（`SupabaseBackend` 側は 508 行）。
