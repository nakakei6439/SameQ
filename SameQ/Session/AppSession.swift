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
        /// BAN状態のアカウント（F16）。今日のお題にもタイムラインにも入れない。
        /// 運営がサーバー側でBANを切り替える運用のため、ここから解除する導線は作らない。
        case banned
        case failure(String)
    }

    /// 世界タイムラインの表示内容（F11 / F12）。
    /// 「まだ誰も答えていない」と「自分が読み尽くした」は別の文言で出す。
    enum TimelineContent: Equatable {
        case loading
        case post(Post)
        case empty
        case exhausted

        var post: Post? {
            if case .post(let post) = self { return post }
            return nil
        }
    }

    private let backend: Backend
    private let clock: AppClock
    /// 投稿本文とお題本文を端末言語へ変換する窓口（F18 / F20 / F21 / F22）。
    /// `RootView` がこれを `TranslationHostView` へ渡し、常駐する `.translationTask` から
    /// `TranslationSession` を受け取れるようにする。
    let translator: Translator

    private(set) var screen: Screen = .loading
    private(set) var user: AppUser?
    private(set) var promptState: PromptState = .waiting(nextStartsAt: nil)
    /// 今日のお題への自分の回答。nil の間は世界タイムラインを開けない（F05）。
    private(set) var myPost: Post?
    /// 今日のお題を端末言語へ翻訳した表示用の本文（F22）。
    /// 翻訳が終わるまでは nil にして、画面側に準備中の表示をさせる
    /// （原文が一瞬見えてから翻訳に差し替わる「ちらつき」を避けるため）。
    private(set) var promptDisplayText: String?
    private var promptTranslationTask: Task<Void, Never>?
    private var lastTranslatedPromptID: String?
    /// タイムラインにいま出しているもの（F11 / F12）。回答は常に1件だけ持ち、配列で先読みしない。
    private(set) var timelineContent: TimelineContent = .loading
    private(set) var likedPostIDs: Set<UUID> = []
    /// ブロック中の相手（F15）。設定画面の一覧はこれだけを見る。
    private(set) var blockedAuthors: [BlockedAuthor] = []
    private(set) var isTimelinePresented = false
    /// 設定（今回はブロック管理のみ）。タイムラインの裏側にある画面から開く。
    var isSettingsPresented = false
    /// アプリが認識している「今」。1秒ごとの `refresh()` で更新する。
    private(set) var now: Date
    /// Debug オーバーレイ用。いまのお題で表示しうる回答の総数と、既読の件数。
    private(set) var timelineCandidateCount = 0
    private(set) var timelineViewedCount = 0
    private(set) var reportedCount = 0

    /// 投稿失敗などの一時的なメッセージ。表示したら nil に戻す。
    var alertMessage: String?

    var isSubmitting = false

    /// いま有効なお題。お題待ちのあいだは nil。
    var prompt: Prompt? { promptState.prompt }

    init(backend: Backend = BackendProvider.make(), clock: AppClock = AppClock(), translator: Translator = Translator()) {
        self.backend = backend
        self.clock = clock
        self.translator = translator
        self.now = clock.now
    }

    /// 起動時の読み込み。アカウントが無ければ初回設定へ、
    /// あればお題の状態に応じてお題待ち／今日のお題／タイムラインへ。
    func start() async {
        screen = .loading
        // BAN状態のアカウントは、今日のお題にもタイムラインにも入れない（F16）。
        // 運営がサーバー側でBANを切り替える運用のため、アプリ内に解除UIは無く、
        // Debug限定の起動引数 `-SameQBanned` でこの状態を模擬する。
        if LaunchOptions.current.isBanned {
            screen = .banned
            return
        }
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
        case .loading, .onboarding, .failure, .banned:
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
        blockedAuthors = try await backend.blockedAuthors()
        switch promptState {
        case .waiting:
            // お題待ちでは自分の回答も世界の回答も見せない（F08 / F10）。
            isTimelinePresented = false
            timelineContent = .loading
            myPost = nil
            likedPostIDs = try await backend.likedPostIDs()
            promptTranslationTask?.cancel()
            promptDisplayText = nil
            lastTranslatedPromptID = nil
            screen = .waiting
        case .active(let prompt):
            myPost = try await backend.myPost(promptID: prompt.id)
            likedPostIDs = try await backend.likedPostIDs()
            try await refreshTimelineCounts(promptID: prompt.id)
            if !openTimelineIfAnswered || myPost == nil {
                isTimelinePresented = false
                timelineContent = .loading
            }
            screen = .today
            syncPromptTranslation(prompt: prompt)
            if openTimelineIfAnswered, myPost != nil {
                await openTimeline()
            }
        }
    }

    // MARK: お題の翻訳（F22）

    /// お題本文を端末言語へ翻訳し、`promptDisplayText` に入れる。
    ///
    /// 同じお題を翻訳し直さないよう `lastTranslatedPromptID` で保護する。
    /// 翻訳が終わるまで `promptDisplayText` は nil のまま（画面側が準備中の表示を出す）にして、
    /// 原文が一瞬見えてから翻訳に差し替わる「ちらつき」を避ける。
    private func syncPromptTranslation(prompt: Prompt) {
        guard lastTranslatedPromptID != prompt.id else { return }
        promptTranslationTask?.cancel()
        promptDisplayText = nil
        let promptID = prompt.id
        let text = prompt.text
        let language = prompt.language
        promptTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let translated = await self.translator.translate(text, sourceLanguageCode: language)
            guard !Task.isCancelled else { return }
            // お題は投稿と違って「スキップして次を出す」代わりが無い（常に1つだけ有効）ので、
            // 翻訳できなかった場合は原文へフォールバックする（今回の判断）。
            self.promptDisplayText = translated ?? text
            self.lastTranslatedPromptID = promptID
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

    // MARK: 世界タイムライン（F06 / F11 / F12）

    /// 有効なお題があり、かつ自分の回答がある場合だけ開く。それ以外では何も起きない。
    /// 開いた時点で1件目を引く。既読は端末に残っているので、開き直しても続きから出る。
    func openTimeline() async {
        guard let prompt, myPost != nil else { return }
        timelineContent = .loading
        isTimelinePresented = true
        do {
            likedPostIDs = try await backend.likedPostIDs()
        } catch {
            alertMessage = error.localizedDescription
        }
        await drawNextPost()
    }

    /// 次の1件へ進む。前へ戻る操作は用意しない（置いた前提5）。
    func advanceTimeline() async {
        guard isTimelinePresented else { return }
        await drawNextPost()
    }

    /// 次の1件を引いて翻訳する（F18 / F20）。
    ///
    /// 翻訳できない言語ペア、または翻訳に失敗した回答は表示せずスキップし、
    /// バックエンドから次を引き直す（`nextTimelinePost` は返した時点で既読にするので、
    /// スキップした回答が後で出てくることもない）。
    /// 表示を切り替えるのは翻訳が確定してからだけにして、原文が一瞬見えてから
    /// 差し替わる「ちらつき」を避ける（間は `.loading` のまま）。
    private func drawNextPost() async {
        guard let prompt else {
            timelineContent = .empty
            return
        }
        timelineContent = .loading
        do {
            draw: while true {
                switch try await backend.nextTimelinePost(promptID: prompt.id) {
                case .post(let post):
                    guard let translatedBody = await translator.translate(
                        post.body,
                        sourceLanguageCode: post.bodyLanguage
                    ) else {
                        continue draw
                    }
                    timelineContent = .post(post.displaying(translatedBody: translatedBody))
                case .empty:
                    timelineContent = .empty
                case .exhausted:
                    timelineContent = .exhausted
                }
                break draw
            }
            try await refreshTimelineCounts(promptID: prompt.id)
        } catch {
            // 読めなかったときも無限ローディングにはせず、読み切りと同じ明示状態に落とす。
            alertMessage = error.localizedDescription
            timelineContent = .exhausted
        }
    }

    /// Debug オーバーレイに出す件数をまとめて取り直す。
    private func refreshTimelineCounts(promptID: String) async throws {
        timelineCandidateCount = try await backend.timelinePosts(promptID: promptID).count
        timelineViewedCount = try await backend.viewedPostIDs().count
        reportedCount = try await backend.reportedPostIDs().count
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

    // MARK: 通報とブロック（F13 / F14 / F15）

    /// 回答を理由付きで通報する。
    /// 送信できたらその場で次の1件を引くので、シートを閉じたときには通報した回答は消えている。
    /// 相手には何も伝わらない（通知も、相手側の表示も作らない）。
    func report(postID: UUID, reason: ReportReason) async -> Bool {
        do {
            try await backend.reportPost(postID: postID, reason: reason)
            await drawNextPost()
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// その回答の投稿者をブロックする。以後その人の回答は1件も出てこない。
    func block(post: Post) async -> Bool {
        do {
            try await backend.blockAuthor(of: post)
            blockedAuthors = try await backend.blockedAuthors()
            await drawNextPost()
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// ブロックを解除する。解除するとその人の回答は再び表示対象に戻る（F15）。
    func unblock(authorID: UUID) async {
        do {
            try await backend.unblockAuthor(id: authorID)
            blockedAuthors = try await backend.blockedAuthors()
            if let prompt {
                try await refreshTimelineCounts(promptID: prompt.id)
            }
        } catch {
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
        // 未読優先と既読の永続を目で確かめられるようにする（F11 / F12）。
        parts.append("answers \(timelineCandidateCount)")
        parts.append("viewed \(timelineViewedCount)")
        parts.append("liked \(likedPostIDs.count)")
        // 通報・ブロックの効き方を目で確かめられるようにする（F13 / F14）。
        parts.append("reported \(reportedCount)")
        parts.append("blocked \(blockedAuthors.count)")
        return parts.joined(separator: " · ")
    }
}
