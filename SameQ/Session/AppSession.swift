import Foundation
import Observation

/// 画面の出し分けとバックエンド呼び出しをまとめる、アプリで唯一の状態。
///
/// タイムラインへ入れるかどうかの判定（F05）と、お題の有効期間による
/// 画面の切り替え（F08 / F09 / F10）はここに集約する。
/// `openTimeline()` は自分の回答が無い限り何もしないので、どの画面からもロックを迂回できない。
@MainActor
@Observable
final class AppSession {
    enum Screen: Equatable {
        case loading
        case onboarding
        /// 有効なお題が無い時間帯（F08）。入力欄もタイムライン導線も持たない。
        case waiting
        case today
        case failure(String)
    }

    private let backend: Backend
    private let clock: AppClock

    private(set) var screen: Screen = .loading
    private(set) var user: AppUser?
    private(set) var promptState: PromptState = .waiting(nextStartsAt: nil)
    /// 今日のお題への自分の回答。nil の間は世界タイムラインを開けない（F05）。
    private(set) var myPost: Post?
    private(set) var timelinePosts: [Post] = []
    private(set) var likedPostIDs: Set<UUID> = []
    private(set) var isTimelinePresented = false
    /// アプリが認識している「今」。1秒ごとの `refresh()` で更新する。
    private(set) var now: Date

    /// 投稿失敗などの一時的なメッセージ。表示したら nil に戻す。
    var alertMessage: String?

    var isSubmitting = false

    /// いま有効なお題。お題待ちのあいだは nil。
    var prompt: Prompt? { promptState.prompt }

    init(backend: Backend = BackendProvider.make(), clock: AppClock = AppClock()) {
        self.backend = backend
        self.clock = clock
        self.now = clock.now
    }

    /// 起動時の読み込み。アカウントが無ければ初回設定へ、
    /// あればお題の状態に応じてお題待ち／今日のお題／タイムラインへ。
    func start() async {
        screen = .loading
        do {
            promptState = try await backend.promptState()
            let loadedUser = try await backend.currentUser()
            user = loadedUser

            guard loadedUser != nil else {
                myPost = nil
                screen = .onboarding
                return
            }

            try await applyPromptState(openTimelineIfAnswered: true)
        } catch {
            screen = .failure(error.localizedDescription)
        }
    }

    /// お題の有効期間をまたいだかどうかを見直す。
    /// 画面を開いたままでも切り替わるように、1秒ごと（`RootView`）と前面復帰時に呼ぶ。
    func refresh() async {
        now = clock.now
        guard user != nil else { return }
        switch screen {
        case .loading, .onboarding, .failure:
            return
        case .waiting, .today:
            break
        }
        do {
            let latest = try await backend.promptState()
            guard latest != promptState else { return }
            promptState = latest
            // お題が変わった／終わったので、開いているタイムラインは閉じる（古い回答を出し続けない）。
            try await applyPromptState(openTimelineIfAnswered: false)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// いまのお題の状態から画面と手元のデータを組み直す。
    private func applyPromptState(openTimelineIfAnswered: Bool) async throws {
        switch promptState {
        case .waiting:
            // お題待ちでは自分の回答も世界の回答も見せない（F08 / F10）。
            isTimelinePresented = false
            timelinePosts = []
            myPost = nil
            likedPostIDs = try await backend.likedPostIDs()
            screen = .waiting
        case .active(let prompt):
            myPost = try await backend.myPost(promptID: prompt.id)
            likedPostIDs = try await backend.likedPostIDs()
            if !openTimelineIfAnswered || myPost == nil {
                isTimelinePresented = false
                timelinePosts = []
            }
            screen = .today
            if openTimelineIfAnswered, myPost != nil {
                await openTimeline()
            }
        }
    }

    // MARK: 初回設定（F01 / F02）

    /// 初回設定の最後にだけ呼ぶ。ここで初めてアカウントが永続化される。
    func completeOnboarding(emoji: String, nickname: String?) async {
        do {
            user = try await backend.createAnonymousUser(emoji: emoji, nickname: nickname)
            promptState = try await backend.promptState()
            try await applyPromptState(openTimelineIfAnswered: false)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: 回答投稿（F04）

    /// 投稿に成功したら世界タイムラインを開く。
    func submit(body: String) async {
        guard let prompt, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            myPost = try await backend.submitPost(promptID: prompt.id, body: body)
            await openTimeline()
        } catch {
            alertMessage = error.localizedDescription
            // 投稿しようとした瞬間にお題が終わっていた場合は、お題待ちへ落とす。
            if let backendError = error as? BackendError, backendError == .promptNotActive {
                await refresh()
            }
        }
    }

    // MARK: 世界タイムライン（F06）

    /// 有効なお題があり、かつ自分の回答がある場合だけ開く。それ以外では何も起きない。
    func openTimeline() async {
        guard let prompt, myPost != nil else { return }
        do {
            timelinePosts = try await backend.timelinePosts(promptID: prompt.id).shuffled()
            likedPostIDs = try await backend.likedPostIDs()
            isTimelinePresented = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func closeTimeline() {
        isTimelinePresented = false
    }

    // MARK: いいね（F07）

    func isLiked(_ postID: UUID) -> Bool {
        likedPostIDs.contains(postID)
    }

    func toggleLike(postID: UUID) async {
        let liked = !likedPostIDs.contains(postID)
        // 押した瞬間に見た目を変えたいので、先にローカルを更新して保存する。
        if liked {
            likedPostIDs.insert(postID)
        } else {
            likedPostIDs.remove(postID)
        }
        do {
            try await backend.setLike(postID: postID, liked: liked)
        } catch {
            // 保存できなかったら見た目を元に戻す。
            if liked {
                likedPostIDs.remove(postID)
            } else {
                likedPostIDs.insert(postID)
            }
            alertMessage = error.localizedDescription
        }
    }

    // MARK: 検証用（Debug オーバーレイ）

    /// `-SameQDebugOverlay` を付けたときだけ画面下に出す1行。通常のビルドでは使わない。
    var debugStatusLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var parts = ["now \(formatter.string(from: now))", "scenario \(LaunchOptions.current.scenario.rawValue)"]
        switch promptState {
        case .active(let prompt):
            parts.append("\(prompt.id) ends in \(Int(prompt.endsAt.timeIntervalSince(now)))s")
        case .waiting(let nextStartsAt):
            if let nextStartsAt {
                parts.append("waiting / next in \(Int(nextStartsAt.timeIntervalSince(now)))s")
            } else {
                parts.append("waiting / no next prompt")
            }
        }
        parts.append(myPost == nil ? "unanswered" : "answered")
        return parts.joined(separator: " · ")
    }
}
