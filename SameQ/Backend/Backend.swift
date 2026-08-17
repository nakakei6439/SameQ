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

    // MARK: お題（F03）

    /// 今日のお題。スプリント01では運用側が用意した固定の1件を返す。
    func activePrompt() async throws -> Prompt

    // MARK: 回答（F04 / F05）

    /// そのお題への自分の回答。未回答なら nil。これが nil の間はタイムラインを開けない。
    func myPost(promptID: String) async throws -> Post?

    /// 回答を投稿する。1つのお題につき1回だけ。
    @discardableResult
    func submitPost(promptID: String, body: String) async throws -> Post

    // MARK: 世界タイムライン（F06）

    /// そのお題への「自分以外」の回答。
    func timelinePosts(promptID: String) async throws -> [Post]

    // MARK: いいね（F07）

    /// 自分が押したいいねの投稿ID一覧。
    func likedPostIDs() async throws -> Set<UUID>

    /// いいねを付ける／外す。
    func setLike(postID: UUID, liked: Bool) async throws
}

/// バックエンド操作で利用者に見せるエラー。
enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case emptyBody
    case bodyTooLong(limit: Int)
    case alreadyAnswered
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
        case .seedDataMissing:
            return "お題を読み込めませんでした。"
        case .storageFailure(let detail):
            return "保存に失敗しました（\(detail)）。"
        }
    }
}
