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
    /// 候補は「同一お題／自分以外／表示期限内／BAN外／ブロック外／通報していない」で、
    /// そのうち**未読だけ**からランダムに1件選ぶ。
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
            return "アカウントが見つかりませんでした。アプリを起動し直してください。"
        case .emptyBody:
            return Self.bilingual(
                ja: "空白や改行だけの回答は投稿できません。",
                en: "You can't post a reply that's only blank space or line breaks."
            )
        case .bodyTooLong(let limit):
            return Self.bilingual(
                ja: "回答は\(limit)文字までです。",
                en: "Replies can be at most \(limit) characters."
            )
        case .alreadyAnswered:
            return "このお題にはすでに回答しています。"
        case .promptNotActive:
            return "このお題の時間は終わりました。次のお題をお待ちください。"
        case .seedDataMissing:
            return "お題を読み込めませんでした。"
        case .storageFailure(let detail):
            return "保存に失敗しました（\(detail)）。"
        case .duplicateBody:
            return Self.bilingual(
                ja: "直前の自分の投稿と同じ内容です。別の言葉に変えて投稿してください。",
                en: "This is identical to your previous post. Please try different wording."
            )
        case .meaninglessBody:
            return Self.bilingual(
                ja: "同じ文字を並べただけの投稿はできません。",
                en: "A post made of the same character repeated isn't allowed."
            )
        case .rateLimited(let action, let retryAfterSeconds):
            let ja = action == .like ? "いいね" : "通報"
            let en = action == .like ? "Likes" : "Reports"
            return Self.bilingual(
                ja: "\(ja)が短時間に多すぎます。\(retryAfterSeconds)秒待ってからもう一度お試しください。",
                en: "\(en) too fast. Please wait \(retryAfterSeconds)s and try again."
            )
        }
    }

    /// 日本語行と英語行を1つの文字列にまとめる（両言語の端末で読めるようにするため）。
    private static func bilingual(ja: String, en: String) -> String {
        "\(ja)\n\(en)"
    }
}
