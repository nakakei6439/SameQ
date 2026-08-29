import Foundation

/// 言語コードごとに「最後に翻訳モデルのダウンロードを試みた時刻」を永続化する窓口。
///
/// `Translator`（`SameQ/Backend/Translator.swift`）のクールダウン判定
/// （`modelDownloadRetryCooldownSeconds`）は、アプリのプロセス内メモリだけでなく
/// ここを通じて `state.json` へ永続化することで、アプリの終了・再起動をまたいでも
/// 「直近で試したばかりか」を正しく判定できるようにする（受け入れ条件4・attempt 7:
/// eval-6.md [1] の修正）。
///
/// `Backend` に含めているのは、書き込みを常に単一のアクター（`LocalBackend`）へ
/// 集約するため。`Translator` が独自に `LocalStore` へ読み書きすると、`LocalBackend`
/// が保持する `state`（メモリ上のスナップショット）と競合し、どちらかの書き込みが
/// 失われる恐れがある（`LocalBackend` はアクターなので、その内部だけなら
/// 呼び出しは直列化される）。
protocol TranslationAttemptPersisting: Sendable {
    /// `sourceLanguageCode`（小文字化はここでは求めない。実装側が正規化する）について、
    /// 最後にダウンロードを試みた時刻。一度も試みていなければ nil。
    func lastModelPrepareAttempt(sourceLanguageCode: String) async throws -> Date?

    /// `sourceLanguageCode` のダウンロードを `date` の時点で試みたことを記録する。
    func recordModelPrepareAttempt(sourceLanguageCode: String, at date: Date) async throws
}

/// アプリが必要とするデータ操作の全体。
///
/// 実装は今のところ `LocalBackend`（端末内）だけだが、Supabase へ差し替えられるように
/// すべて `async throws` にしてある。UI 層はこのプロトコルしか知らない。
protocol Backend: Sendable, TranslationAttemptPersisting {
    // MARK: アカウント（F02）

    /// アプリ起動のたびに一度呼ぶ。永続化された認証情報（Supabaseの refresh_token）が
    /// あれば、それを使ってアクセストークンを更新しておく（実機で確認された不具合の修正、
    /// 2026-08-29）。`SupabaseClient.refreshToken(refreshToken:)` は元々実装済みだったが、
    /// どこからも呼ばれておらず、access_token の有効期限（既定1時間程度）が切れた状態で
    /// 次に起動すると `promptState()` 等の最初の認証済みリクエストが 401 になり、
    /// 「セッションが切れました」の失敗画面から一切復帰できなかった
    /// （「もう一度試す」を押しても同じ古いトークンで再試行するだけのため）。
    /// 失敗しても致命的にはしない（`throws` にしない）: リフレッシュ自体が一時的な
    /// 通信不調で失敗しただけの可能性があり、ここでトークンやアカウント紐付けを
    /// 消すと復旧不能になる。失敗時は何もせず、後続の実際のリクエストに委ねる
    /// （そちらが本当に 401 なら従来どおり `SupabaseError.unauthorized` として扱われる）。
    /// `LocalBackend` では認証の概念が無いため no-op。
    func ensureFreshSession() async

    /// 保存済みの匿名アカウント。まだ初回設定が完了していなければ nil。
    func currentUser() async throws -> AppUser?

    /// 匿名アカウントを作成して永続化する。初回設定の最後にだけ呼ぶ。
    @discardableResult
    func createAnonymousUser(emoji: String, nickname: String?) async throws -> AppUser

    /// 既存アカウントのプロフィールを更新する（F32）。
    /// 絵文字・ニックネームは `AppUser.emoji` / `AppUser.nickname` を書き換えるだけでなく、
    /// そのユーザーが過去に投稿した `Post` の `authorEmoji` / `authorNickname` も
    /// 遡って更新する（受け入れ条件2「タイムラインへ流れる自分の情報が新しい内容になる」）。
    /// - Parameters:
    ///   - emoji: 新しい絵文字。空文字や空白のみは許可しない。
    ///   - nickname: 新しいニックネーム。nil / 空文字 / 空白のみを渡すと「未設定」になる。
    @discardableResult
    func updateProfile(emoji: String, nickname: String?) async throws -> AppUser

    /// アカウントを削除する（F33）。
    /// 自分のアカウント本体に加え、関連する全ての端末内データ
    ///（`myPosts` / `likedPostIDs` / `viewedPostIDs` / `reports` / `blockedAuthors` /
    /// `lastPostBody` / `lastPrepareAttemptAt`）を消去する。
    /// 削除後は `currentUser()` が nil を返す状態になり、UI 側は初回設定へ戻る。
    /// お題の自動生成で積算された破棄件数（`discardedCandidatesCount`）は
    /// 統計情報として残す（リセットしない）。
    func deleteAccount() async throws

    // MARK: お題（F03 / F08 / F09）

    /// いま有効なお題の状態。有効期間外なら `.waiting`（お題待ち画面になる）。
    func promptState() async throws -> PromptState

    // MARK: 回答（F04 / F05 / F10）

    /// そのお題への自分の回答。未回答なら nil。これが nil の間はタイムラインを開けない。
    /// 表示期限を過ぎた回答は nil を返す（お題が変われば再び未回答になる）。
    func myPost(promptID: String) async throws -> Post?

    /// 回答を投稿する。1つのお題につき1回だけ（F04 / F29 / F30）。
    /// - Parameters:
    ///   - promptID: 投稿先のお題
    ///   - body: 本文（前後空白は内部で trim される）
    ///   - decorations: Plus 限定装飾（F30）。`isPlus == false` のときは無視される
    ///   - isPlus: 呼び出し時点の Plus 状態（F29 の長文上限、F30 の装飾受理に使う）
    @discardableResult
    func submitPost(
        promptID: String,
        body: String,
        decorations: [PostDecoration],
        isPlus: Bool
    ) async throws -> Post

    // MARK: 世界タイムライン（F06 / F11 / F12）

    /// そのお題への「自分以外」かつ「表示期限内」の回答（既読も含む候補の全件）。
    /// 画面はこれを直接使わない。件数の把握とテストのために残している。
    func timelinePosts(promptID: String) async throws -> [Post]

    /// タイムラインに次に出す回答を1件だけ引く（F11）。
    ///
    /// 候補は「同一お題／自分以外／表示期限内／BAN外／ブロック外／通報していない」で、
    /// そのうち**未読**かつ `excluding` に入っていないものからランダムに1件選ぶ。
    /// `autoMarkViewed` が true なら返した時点で既読として記録・永続化する（F12・従来どおり）。
    /// 未読が尽きたら `.exhausted`、候補が最初から1件も無ければ `.empty` を返す。
    ///
    /// - Parameters:
    ///   - excluding: 今回の巡回だけで一時的に除外したい投稿ID（永続化しない）。
    ///     翻訳が一時的に失敗した回答を、同じ巡回内で無限に引き直さないために使う（バグ4の修正）。
    ///   - autoMarkViewed: false のときは既読にせず `markPostViewed(_:)` を呼び出し側に任せる。
    ///     翻訳の成否が確定するまで「見せられるかどうか」が分からない `AppSession` 側が、
    ///     実際に表示できると確定した時点でだけ既読にできるようにするため（F18〜F22）。
    func nextTimelinePost(promptID: String, excluding: Set<UUID>, autoMarkViewed: Bool) async throws -> TimelineDraw

    /// `nextTimelinePost(..., autoMarkViewed: false)` で引いた回答を、実際に画面へ出せると
    /// 確定した時点（翻訳成功、または恒久的に翻訳できないと判定できた時点）で既読にする。
    /// 一時的な失敗（モデル未取得のタイムアウト等）では呼ばない（バグ4の修正・F12）。
    func markPostViewed(_ postID: UUID) async throws

    /// 既読として記録済みの投稿ID（検証・デバッグ表示用）。
    func viewedPostIDs() async throws -> Set<UUID>

    // MARK: いいね（F07）

    /// 自分が押したいいねの投稿ID一覧。
    func likedPostIDs() async throws -> Set<UUID>

    /// いいねを付ける／外す。
    func setLike(postID: UUID, liked: Bool) async throws

    /// 自分の投稿に付いているいいねの件数（受け入れ条件3「受信したいいねの総数」）。
    ///
    /// `Backend` プロトコルの要求メソッド。
    /// `extension` のデフォルト実装ではなく `actor` 実装が `any Backend` 経由で
    /// 静的ディスパッチされるようにするため、`LocalBackend` / `SupabaseBackend` の両方に
    /// 実装を置く（attempt 11: eval-7.md [1] a の修正）。
    /// - Supabase 経路: `RPC received_like_count(post_id)` で `security definer` 関数を使い、
    ///   `likes_select_own` RLS をバイパスして他人のいいね行も数えられる（attempt 11:
    ///   eval-7.md [1] b の修正）。
    /// - ローカル経路: `likedPostIDs` には他人のいいねは含まれないため常に 0。
    ///   既定実装を `extension` に置かず、`LocalBackend` で明示的に 0 を返す。
    func receivedLikeCount(forPostID postID: UUID) async throws -> Int

    // MARK: 通報（F13）

    /// 回答を理由付きで通報する。通報した回答は以後、自分の表示対象に入らない。
    /// 相手に伝わるものは何も作らない（通知も、相手側の表示も無い）。
    func reportPost(postID: UUID, reason: ReportReason) async throws

    /// 自分が通報済みの投稿ID（検証・デバッグ表示用）。
    func reportedPostIDs() async throws -> Set<UUID>

    // MARK: ブロック（F14 / F15）

    /// その回答の投稿者をブロックする。以後、その人の回答は1件も表示しない。
    /// 一覧に出すための見た目（絵文字・ニックネーム）は、この回答から写し取る。
    func blockAuthor(of post: Post) async throws

    /// ブロック解除。解除するとその人の回答は再び表示対象に戻る。
    func unblockAuthor(id: UUID) async throws

    /// ブロック中の相手の一覧（新しい順）。設定画面で使う（F15）。
    func blockedAuthors() async throws -> [BlockedAuthor]

    // MARK: お題の自動生成（F26）

    /// お題の自動生成で安全条件により破棄された候補の累計件数
    ///（受け入れ条件 4「破棄された記録が残る」）。`PersistedState` に永続化されている。
    /// ユーザー向け UI には出さず、Debug オーバーレイ用。
    func discardedCandidatesCount() async throws -> Int

    // MARK: サーバー側の認証状態（F36・受け入れ条件2）

    /// 自分のアカウントのサーバ側ステータス。`"active"` / `"banned"` / `"missing"` の3値。
    /// `LocalBackend` は常に `active` を返し（端末内でBANを模擬する経路は
    /// `-SameQBanned` 起動引数のままで、サーバ側ステータスを別途参照する
    /// 必要は無い）、`SupabaseBackend` はサーバ RPC を呼ぶ。
    /// 通信失敗時はサーバ側を `"active"` とみなす (fail-open)。
    func currentServerSideStatus() async throws -> String

    // MARK: 安全ログの自動削除（F34/F36・受け入れ条件6）

    /// 期限切れの safety logs（通報記録）を削除する。アプリ起動時に1度だけ
    /// 呼ぶ（`AppSession.start()`）。pg_cron が無い環境でも「アプリ起動時に
    /// 自分宛の清掃が走る」状態を作るための保険。返り値は削除件数
    ///（デバッグログ・テスト用）。
    /// - `LocalBackend`: 端末内の `state.reports` を保持期間で剪定する。
    /// - `SupabaseBackend`: サーバ RPC `app_purge_expired_safety_logs()` を呼ぶ。
    ///   pg_cron が有効なら別途サーバ側のスケジュールで毎日走る。
    func purgeExpiredSafetyLogs() async throws -> Int

    // MARK: サーバ時計（F36・受け入れ条件5）

    /// サーバ側の「現在の時刻」を返す。`Debug` オーバーレイでお題の残り時間を
    /// 端末時計ではなくサーバ時計基準で表示するために使う (受け入れ条件5)。
    /// 端末時計を N 時間ずらしても `currentPromptEndsAt - serverNow` は常に
    /// 同一の秒数になる。
    /// - `LocalBackend`: `clock.now` をそのまま返す (端末外のものさしと差がない)。
    /// - `SupabaseBackend`: サーバ RPC `current_server_time()` を呼ぶ。
    /// 通信失敗時は実装側で `clock.now` へフォールバックして UI を止めない。
    func currentServerTime() async throws -> Date

    // MARK: 翻訳の先読み（F41・スプリント17）

    /// タイムラインで実際に表示した回答の言語コードを1件分カウントアップする
    /// （受け入れ条件1「直近よく出会う言語」の素データ）。
    ///
    /// 呼び出しタイミングは「翻訳が確定して画面に出せると確定した瞬間」
    ///（`AppSession.drawNextPost` の `case .text` 内）だけ。スキップ
    ///（`.unavailable(permanent: true)`）も含むが、それ以外（モデル未DLなど
    /// 一時的な失敗）は含めない。バックエンド実装は `PersistedState.languageEncounters`
    /// を増分して保存する。
    /// - Parameters:
    ///   - languageCode: 表示した回答の `bodyLanguage`（小文字化は実装側の責務）。
    func recordLanguageEncounter(languageCode: String) async throws

    /// よく出会う言語の上位 `limit` 件を、回数降順（タイは言語コード昇順）で返す
    ///（受け入れ条件1「最大3件まで」）。
    ///
    /// 戻り値は pre-fetch の対象として `Translator.prepareIfNeeded(_:)` に渡す
    /// ための言語コード列。件数が `limit` 未満なら全件、`limit == 0` なら空配列、
    /// 1件も記録が無ければ空配列。F19 の方針に従い UI には出さない（値の検証は
    /// ユニットテストと Debug オーバーレイのみで使う）。
    /// - Parameters:
    ///   - limit: 上限。F41 では常に 3 を渡す。
    func topEncounteredLanguages(limit: Int) async throws -> [String]

    /// その瞬間にネットワーク接続があるかどうか（F41 受け入れ条件5）。
    /// pre-fetch は true の間だけ走らせる（false の間に走らせても
    /// `Translator.prepareIfNeeded` の中で個別にタイムアウトを待つだけで
    /// ユーザー体験を損なうだけなので、起動側で一括スキップする）。
    /// - `LocalBackend`: 常に true（端末内完結で外部通信が無い）。
    /// - `SupabaseBackend`: `forceOffline == true` の間、または
    ///   `NWPathMonitor` が `.satisfied` 以外を返している間は false。
    /// 失敗はしない（false を返すことで呼び出し側が安全にスキップできるようにする）。
    func isOnline() async -> Bool

    // MARK: 運営お知らせ（新機能）

    /// 運営からのお知らせ一覧を新しい順で返す。読み取り専用
    ///（`announcements` テーブルは insert/update/delete の RLS ポリシーを持たない。
    /// 管理者が直接 SQL / Supabase dashboard から投入する運用。アプリ内投稿・編集
    /// UI は作らない、`Prompt` の運用と同じ方針）。
    /// - `LocalBackend`: 固定のサンプル配列を返す（オフライン開発用）。
    /// - `SupabaseBackend`: `announcements` テーブルへ GET するだけ。
    func announcements() async throws -> [Announcement]
}

extension Backend {
    /// `excluding` / `autoMarkViewed` を省略した呼び出し（スプリント01〜05から変わらない
    /// 「引いた時点で既読にする」挙動）。既存の呼び出し元・既存テストをそのまま通すための
    /// 後方互換のデフォルト（プロトコル本体に既定値は書けないため extension で用意する）。
    func nextTimelinePost(promptID: String) async throws -> TimelineDraw {
        try await nextTimelinePost(promptID: promptID, excluding: [], autoMarkViewed: true)
    }

    /// 装飾と Plus 状態を渡さない従来の `submitPost`（スプリント10 より前の呼び出し元
    /// ・既存テストを通すための後方互換デフォルト）。
    func submitPost(promptID: String, body: String) async throws -> Post {
        try await submitPost(
            promptID: promptID,
            body: body,
            decorations: [],
            isPlus: false
        )
    }

    /// 安全ログ（通報記録）の既定保持期間（F34）。サーバ側 `safety_logs` テーブルの
    /// 30 日保持と一致させる。検証用には `LaunchOptions.safetyLogRetentionSeconds`
    /// で短縮できる（`LocalBackend` がそちらを優先する）。
    /// プロトコルへの static 追加は制限があるため、`(any Backend).Type.defaultSafetyLogRetentionSeconds`
    /// 経由ではなく `SafetyLogDefaults` 経由で参照する。
    static var defaultSafetyLogRetentionSeconds: TimeInterval {
        SafetyLogDefaults.defaultRetentionSeconds
    }
}

/// 安全ログの既定保持期間（F34）。プロトコル extension の static 制約を回避するため
/// グローバル名前空間に置く。サーバ側 `safety_logs` の 30 日保持と一致させる。
enum SafetyLogDefaults {
    static let defaultRetentionSeconds: TimeInterval = 30 * 24 * 60 * 60
}

/// タイムラインから引いた1件の結果（F11 / F12）。
///
/// 「まだ誰も答えていない」と「自分が読み尽くした」は利用者にとって意味が違うので分ける。
enum TimelineDraw: Equatable, Sendable {
    /// 次に見せる回答。引いた時点で既読になっている。
    case post(Post)
    /// 自分以外の回答がそもそも1件も無い（自分の回答しか存在しない場合を含む）。
    case empty
    /// 自分以外の回答はあるが、すべて既読・ブロック・通報で出せない。
    case exhausted
}

/// お題の状態（F08 / F09）。有効なお題は常に多くても1つ（置いた前提3）。
enum PromptState: Equatable, Sendable {
    /// 有効期間中のお題がある。
    case active(Prompt)
    /// 有効なお題が無い時間帯。`nextStartsAt` は次のお題の開始時刻（予定が無ければ nil）。
    /// 画面には出さない（「いつ来るか分からない」体験を壊さないため）。
    case waiting(nextStartsAt: Date?)

    var prompt: Prompt? {
        if case .active(let prompt) = self { return prompt }
        return nil
    }
}

/// いいね・通報のうち、連打制限に引っかかった操作の種類（F17）。
enum RateLimitedAction: Sendable, Equatable {
    case like
    case report
}

/// バックエンド操作で利用者に見せるエラー。
///
/// `duplicateBody` / `meaninglessBody` / `rateLimited` はスプリント05（F17）で追加した。
/// これらと、既存のうち投稿フォームで実際にユーザーへ見せる可能性がある
/// `emptyBody` / `bodyTooLong` は、評価者への注記（日本語・英語どちらの端末でも読めるか）に
/// 対応するため、1つの文字列に日本語行と英語行の両方を入れて返す
/// （アプリ全体の多言語対応の基盤はまだ無いため、範囲をスプリント05で追加した制限メッセージに絞った）。
enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case emptyBody
    case bodyTooLong(limit: Int)
    case alreadyAnswered
    case promptNotActive
    case seedDataMissing
    case storageFailure(String)
    /// 直近の自分の投稿と本文が完全一致（F17）。
    case duplicateBody
    /// 空白のみ、または同一文字の過剰な繰り返し（F17）。
    case meaninglessBody
    /// いいね・通報の連打制限（F17）。`retryAfterSeconds` は解除までの目安秒数。
    case rateLimited(action: RateLimitedAction, retryAfterSeconds: Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L10n.Errors.notSignedIn
        case .emptyBody:
            return L10n.Errors.emptyBody
        case .bodyTooLong(let limit):
            return L10n.Errors.bodyTooLong(limit)
        case .alreadyAnswered:
            return L10n.Errors.alreadyAnswered
        case .promptNotActive:
            return L10n.Errors.promptNotActive
        case .seedDataMissing:
            return L10n.Errors.seedDataMissing
        case .storageFailure(let detail):
            return L10n.Errors.storageFailure(detail)
        case .duplicateBody:
            return L10n.Errors.duplicateBody
        case .meaninglessBody:
            return L10n.Errors.meaninglessBody
        case .rateLimited(let action, let retryAfterSeconds):
            let actionName = action == .like
                ? L10n.Errors.rateLimitedActionLike
                : L10n.Errors.rateLimitedActionReport
            return L10n.Errors.rateLimited(actionName, retryAfterSeconds)
        }
    }
}
