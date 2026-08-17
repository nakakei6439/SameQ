import Foundation
import Observation

/// 画面の出し分けとバックエンド呼び出しをまとめる、アプリで唯一の状態。
///
/// タイムラインへ入れるかどうかの判定（F05）はここに集約する。
/// `openTimeline()` は自分の回答が無い限り何もしないので、
/// どの画面からもロックを迂回できない。
@MainActor
@Observable
final class AppSession {
    enum Screen: Equatable {
        case loading
        case onboarding
        case today
        case failure(String)
    }

    private let backend: Backend

    private(set) var screen: Screen = .loading
    private(set) var user: AppUser?
    private(set) var prompt: Prompt?
    /// 今日のお題への自分の回答。nil の間は世界タイムラインを開けない（F05）。
    private(set) var myPost: Post?
    private(set) var timelinePosts: [Post] = []
    private(set) var likedPostIDs: Set<UUID> = []
    private(set) var isTimelinePresented = false

    /// 投稿失敗などの一時的なメッセージ。表示したら nil に戻す。
    var alertMessage: String?

    var isSubmitting = false

    init(backend: Backend = BackendProvider.make()) {
        self.backend = backend
    }

    /// 起動時の読み込み。アカウントが無ければ初回設定へ、
    /// あれば今日のお題へ（回答済みならそのまま世界タイムラインを開く）。
    func start() async {
        screen = .loading
        do {
            let loadedPrompt = try await backend.activePrompt()
            prompt = loadedPrompt
            let loadedUser = try await backend.currentUser()
            user = loadedUser

            guard loadedUser != nil else {
                myPost = nil
                screen = .onboarding
                return
            }

            myPost = try await backend.myPost(promptID: loadedPrompt.id)
            likedPostIDs = try await backend.likedPostIDs()
            screen = .today

            if myPost != nil {
                await openTimeline()
            }
        } catch {
            screen = .failure(error.localizedDescription)
        }
    }

    // MARK: 初回設定（F01 / F02）

    /// 初回設定の最後にだけ呼ぶ。ここで初めてアカウントが永続化される。
    func completeOnboarding(emoji: String, nickname: String?) async {
        do {
            user = try await backend.createAnonymousUser(emoji: emoji, nickname: nickname)
            if let prompt {
                myPost = try await backend.myPost(promptID: prompt.id)
            }
            likedPostIDs = try await backend.likedPostIDs()
            screen = .today
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
        }
    }

    // MARK: 世界タイムライン（F06）

    /// 自分の回答がある場合だけタイムラインを開く。無い場合は何も起きない。
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
}
