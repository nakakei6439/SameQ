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

    // MARK: 世界タイムライン（F06 / F11 / F12）

    /// そのお題への「自分以外」かつ「表示期限内」の回答（既読も含む候補の全件）。
    /// 画面はこれを直接使わない。件数の把握とテストのために残している。
    func timelinePosts(promptID: String) async throws -> [Post]

    /// タイムラインに次に出す回答を1件だけ引く（F11）。
    ///
    /// 候補は「同一お題／自分以外／表示期限内」で、そのうち**未読だけ**からランダムに1件選ぶ。
    /// 返した回答はその場で既読として記録・永続化する（F12）ので、同じ回答は
    /// アプリを再起動しても二度と出てこない。未読が尽きたら `.exhausted`、
    /// 候補が最初から1件も無ければ `.empty` を返す。
    func nextTimelinePost(promptID: String) async throws -> TimelineDraw

    /// 既読として記録済みの投稿ID（検証・デバッグ表示用）。
    func viewedPostIDs() async throws -> Set<UUID>

    // MARK: いいね（F07）

    /// 自分が押したいいねの投稿ID一覧。
    func likedPostIDs() async throws -> Set<UUID>

    /// いいねを付ける／外す。
    func setLike(postID: UUID, liked: Bool) async throws
}

/// タイムラインから引いた1件の結果（F11 / F12）。
///
/// 「まだ誰も答えていない」と「自分が読み尽くした」は利用者にとって意味が違うので分ける。
enum TimelineDraw: Equatable, Sendable {
    /// 次に見せる回答。引いた時点で既読になっている。
    case post(Post)
    /// 表示できる回答が最初から1件も無い（自分の回答しか存在しない場合を含む）。
    case empty
    /// 候補はあるが、すべて既読になっている。
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
