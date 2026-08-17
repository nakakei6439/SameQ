import Foundation

/// アプリが必要とするデータ操作の全体。
///
/// 実装は今のところ `LocalBackend`（端末内）だけだが、Supabase へ差し替えられるように
/// すべて `async throws` にしてある。UI 層はこのプロトコルしか知らない。
protocol Backend: Sendable {
    // MARK: アカウント（F02）

    /// 保存済みの匿名アカウント。まだ初回設定が完了していなければ nil。
    func currentUser() async throws -> AppUser?

    /// 匿名アカウントを作成して永続化する。初回設定の最後にだけ呼ぶ。
    @discardableResult
    func createAnonymousUser(emoji: String, nickname: String?) async throws -> AppUser

    // MARK: お題（F03 / F08 / F09）

    /// いま有効なお題の状態。有効期間外なら `.waiting`（お題待ち画面になる）。
    func promptState() async throws -> PromptState

    // MARK: 回答（F04 / F05 / F10）

    /// そのお題への自分の回答。未回答なら nil。これが nil の間はタイムラインを開けない。
    /// 表示期限を過ぎた回答は nil を返す（お題が変われば再び未回答になる）。
    func myPost(promptID: String) async throws -> Post?

    /// 回答を投稿する。1つのお題につき1回だけ。
    @discardableResult
    func submitPost(promptID: String, body: String) async throws -> Post

    // MARK: 世界タイムライン（F06）

    /// そのお題への「自分以外」かつ「表示期限内」の回答。
    func timelinePosts(promptID: String) async throws -> [Post]

    // MARK: いいね（F07）

    /// 自分が押したいいねの投稿ID一覧。
    func likedPostIDs() async throws -> Set<UUID>

    /// いいねを付ける／外す。
    func setLike(postID: UUID, liked: Bool) async throws
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

/// バックエンド操作で利用者に見せるエラー。
enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case emptyBody
    case bodyTooLong(limit: Int)
    case alreadyAnswered
    case promptNotActive
    case seedDataMissing
    case storageFailure(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "アカウントが見つかりませんでした。アプリを起動し直してください。"
        case .emptyBody:
            return "回答を入力してください。"
        case .bodyTooLong(let limit):
            return "回答は\(limit)文字までです。"
        case .alreadyAnswered:
            return "このお題にはすでに回答しています。"
        case .promptNotActive:
            return "このお題の時間は終わりました。次のお題をお待ちください。"
        case .seedDataMissing:
            return "お題を読み込めませんでした。"
        case .storageFailure(let detail):
            return "保存に失敗しました（\(detail)）。"
        }
    }
}
