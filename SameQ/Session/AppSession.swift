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

    /// 通知タップ時（ディープリンク / F25）の遷移先。
    enum DeepLinkTarget: Equatable, Sendable {
        /// 今日のお題画面（未回答なら入力欄、回答済みなら「あなたの回答」表示）。
        case today
        /// 世界タイムライン（回答済みのときのみ意味がある）。
        case timeline
        /// お題待ち（有効なお題が無い時間帯をタップしたとき）。
        case waiting
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
    /// ニックネームを端末言語の文字体系へ音写する窓口（F23）。
    /// 端末言語の判定は `translator` と一貫させたいので、`Translator.targetLanguageCode` を
    /// そのまま借りて `NicknameTransliterator` を作る。
    let nicknameTransliterator: NicknameTransliterator
    /// 通知の予約・取り消し・状態取得をまとめた窓口（F24 / F25）。
    /// `nil` のときは通知を一切扱わない（既存ユニットテストの後方互換用）。
    private let notificationScheduler: NotificationScheduling?

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
    /// タイムラインを開く前に、モデル未ダウンロードの言語をダウンロードしている間だけ true
    /// （受け入れ条件4・attempt 5）。この間は世界タイムラインを開くボタンを「準備中…」にして
    /// 連打を防ぐ（`TodayPromptView`）。
    private(set) var isPreparingTimeline = false
    /// 設定（今回はブロック管理のみ）。タイムラインの裏側にある画面から開く。
    var isSettingsPresented = false
    /// アプリが認識している「今」。1秒ごとの `refresh()` で更新する。
    private(set) var now: Date
    /// Debug オーバーレイ用。いまのお題で表示しうる回答の総数と、既読の件数。
    private(set) var timelineCandidateCount = 0
    private(set) var timelineViewedCount = 0
    private(set) var reportedCount = 0

    /// 現在の通知許可状態（F25）。設定画面で「通知はオフです」案内を出すか判定する。
    /// `nil` のときは未確認（オンボーディング前など）。
    private(set) var notificationAuthorizationStatus: NotificationAuthorizationStatus?
    /// 次回の通知が予約されている時刻（Debug オーバーレイ用）。未予約は nil。
    private(set) var nextScheduledNotificationAt: Date?
    /// 通知タップ（F25）で「今日は入力したい」「世界タイムラインを見たい」
    /// 「お題待ち画面を開きたい」のどれを開くべきかを `RootView` へ伝える。
    /// `start()` 完了後に消費される（nil に戻すと RootView も追従する）。
    private(set) var pendingDeepLinkTarget: DeepLinkTarget?

    /// 投稿失敗などの一時的なメッセージ。表示したら nil に戻す。
    var alertMessage: String?

    var isSubmitting = false
    /// `submit()` が投稿完了後に裏で起動した `openTimeline()` の `Task`（attempt 6）。
    /// `@Observable` の追跡対象にする必要が無い内部実装詳細。
    @ObservationIgnored
    private var pendingOpenTimelineTask: Task<Void, Never>?

    /// いま有効なお題。お題待ちのあいだは nil。
    var prompt: Prompt? { promptState.prompt }

    /// `translator` を省略した場合は、この `AppSession` が使うのと**同じ `backend` インスタンス**
    /// を `attemptPersistence` として渡した `Translator` を作る（attempt 7: eval-6.md [1] の修正）。
    /// 同じインスタンス（＝同じアクター）を経由させることで、`Translator` が
    /// `lastPrepareAttemptAt` を永続化する書き込みと、`LocalBackend` 自身の書き込みが
    /// 競合してどちらかが失われる、という事態を避ける（`Backend` はアクターなので、
    /// 同じインスタンスへの呼び出しはすべて直列化される）。
    /// テストが `translator` を明示的に渡す場合はそのまま使う（挙動を変えない）。
    ///
    /// `notificationScheduler` を `nil` にすると通知関連を一切行わない（既存ユニットテスト用）。
    /// `nil` を渡さないときは `-SameQNotificationForceDenied` の値を `LiveNotificationScheduler`
    /// へ伝えて「拒否扱い」を強制できる（受け入れ条件6の検証用）。
    init(
        backend: Backend = BackendProvider.make(),
        clock: AppClock = AppClock(),
        translator: Translator? = nil,
        notificationScheduler: NotificationScheduling? = nil
    ) {
        self.backend = backend
        self.clock = clock
        let translator = translator ?? Translator(attemptPersistence: backend)
        self.translator = translator
        // `NicknameTransliterator` の端末言語判定は `Translator` と一貫させる。
        // `translator` だけ後から差し替えたいテストの便宜のため、`NicknameTransliterator` も
        // `init` の引数で上書きできるよう既定では translator から作る。
        self.nicknameTransliterator = NicknameTransliterator(
            targetLanguageCode: translator.targetLanguageCode
        )
        if let notificationScheduler {
            self.notificationScheduler = notificationScheduler
        } else {
            self.notificationScheduler = LiveNotificationScheduler(
                forceDenied: LaunchOptions.current.notificationForceDenied
            )
        }
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

            // 通知許可状態を最初に一度読んでおく（設定画面・Debug オーバーレイ用）。
            // 拒否だった場合は以降の `scheduleDailyReminderIfPossible` が何もしないので、
            // ここで読んだ値が UI 表示の唯一の根拠になる。
            await refreshNotificationAuthorizationStatus()

            guard loadedUser != nil else {
                myPost = nil
                screen = .onboarding
                return
            }

            try await applyPromptState(openTimelineIfAnswered: true)
            // オンボーディング完了アカウントで起動した時点で、お題待ち／今日の両方とも
            // 「次の1回」の通知を予約し直す（F24）。発火後はこの経路を毎巡回で通る。
            await scheduleDailyReminderIfPossible()
        } catch {
            screen = .failure(error.localizedDescription)
        }
    }

    /// 通知許可状態を OS から取り直してキャッシュに反映する（F25）。
    /// 設定画面を開いたときなどに呼ぶ。許可が降りた瞬間に次の通知を予約するため、
    /// 状態が `.authorized` に変わった場合はそのまま `scheduleDailyReminderIfPossible` を実行する。
    @discardableResult
    func refreshNotificationAuthorizationStatus() async -> NotificationAuthorizationStatus {
        guard let scheduler = notificationScheduler else {
            notificationAuthorizationStatus = .notDetermined
            return .notDetermined
        }
        let status = await scheduler.authorizationStatus()
        notificationAuthorizationStatus = status
        return status
    }

    /// オンボーディング完了や、画面の前面復帰・お題切替のたびに呼ぶ。
    /// 許可されているときだけ次の通知を予約する。拒否状態のときは何もしない
    /// （F25「通知を拒否した場合もアプリは通常どおり利用でき」）。
    func scheduleDailyReminderIfPossible() async {
        guard let scheduler = notificationScheduler else { return }
        let status: NotificationAuthorizationStatus
        if let cached = notificationAuthorizationStatus {
            status = cached
        } else {
            status = await refreshNotificationAuthorizationStatus()
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            nextScheduledNotificationAt = nil
            return
        }
        let options = LaunchOptions.current
        let fireDate = await scheduler.scheduleNextRandomNotification(
            now: clock.now,
            timeZone: .current,
            forceDenied: options.notificationForceDenied,
            forcedHour: options.notificationForcedHour
        )
        nextScheduledNotificationAt = fireDate
    }

    // MARK: ディープリンク（F25）

    /// 通知センターからアプリが起動されたときに呼ばれる（F25）。
    /// `RootView` 側が `UNUserNotificationCenterDelegate` から委譲する。
    /// `pendingDeepLinkTarget` が立つので、画面側は `onChange` で反応して遷移する。
    ///
    /// お題待ち中にタップされた場合は `.waiting` を返すだけで、
    /// `RootView` は現在表示中のお題待ち画面をそのまま維持する。
    func handleDeepLink(_ target: DeepLinkTarget) {
        pendingDeepLinkTarget = target
    }

    /// `RootView` が消費したあとに nil へ戻すためのフック。
    func consumeDeepLink() {
        pendingDeepLinkTarget = nil
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
            // お題切替をまたいだときこそ「次の1回」を再計算したいので、ここで通知を再予約する。
            // 「日によって違う時刻」を満たすため、発火のたびに次に拾う時刻が変わる。
            await scheduleDailyReminderIfPossible()
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
            let outcome = await self.translator.translate(text, sourceLanguageCode: language)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .text(let translated):
                self.promptDisplayText = translated
            case .unavailable:
                // お題は投稿と違って「スキップして次を出す」代わりが無い（常に1つだけ有効・
                // 置いた前提2）ので、恒久的な失敗・一時的な失敗のどちらでも原文へフォールバック
                // する（決定を維持。「準備中…」を出し続けると F19「2回目以降は待たない」と
                // 矛盾するため。attempt 2 の self-review に判断理由を記載）。
                self.promptDisplayText = text
            }
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
            // オンボーディング直後の通知許可状態を読み直してから、必要なら通知を予約する
            // （F24・F25）。
            await refreshNotificationAuthorizationStatus()
            await scheduleDailyReminderIfPossible()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    // MARK: 回答投稿（F04）

    /// 投稿に成功したら世界タイムラインを開く。
    ///
    /// **attempt 6（eval-5.md [2] の修正）**: `openTimeline()` の完了は待たない。
    /// `openTimeline()` はモデル未ダウンロードの言語があると数十秒かかりうるが、
    /// 投稿そのもの（`submitPost`）はそれとは独立した処理のはずなので、投稿ボタンは
    /// `submitPost` が終わり次第すぐ解放する（`isSubmitting` を戻す）。投稿完了直後は
    /// `myPost` が入って画面が自動的に「あなたの回答」＋「世界の回答を読む」ボタンへ
    /// 切り替わるので、その裏で始まる準備は `isPreparingTimeline`（「準備中…」表示）で
    /// 見える。ダウンロードが要らなければ、そのままいつもどおりタイムラインが開く。
    func submit(body: String) async {
        guard let prompt, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            myPost = try await backend.submitPost(promptID: prompt.id, body: body)
        } catch {
            alertMessage = error.localizedDescription
            // 投稿しようとした瞬間にお題が終わっていた場合は、お題待ちへ落とす。
            if let backendError = error as? BackendError, backendError == .promptNotActive {
                await refresh()
            }
            return
        }
        pendingOpenTimelineTask?.cancel()
        pendingOpenTimelineTask = Task { [weak self] in
            await self?.openTimeline()
        }
    }

    /// `submit()` が裏で開始したタイムラインの準備・オープンが終わるまで待つ。
    /// 通常のUIコードは呼ぶ必要が無い（`isPreparingTimeline` / `timelineContent` を
    /// 監視すれば足りる）。ユニットテストが「投稿後に実際にタイムラインが開くこと」を
    /// 確定的に検証するために公開している（attempt 6）。
    func waitForPendingTimelineOpen() async {
        await pendingOpenTimelineTask?.value
    }

    // MARK: 世界タイムライン（F06 / F11 / F12）

    /// 有効なお題があり、かつ自分の回答がある場合だけ開く。それ以外では何も起きない。
    /// 開いた時点で1件目を引く。既読は端末に残っているので、開き直しても続きから出る。
    ///
    /// タイムライン（`fullScreenCover`）を実際に開く**前**に、まだ読んでいない回答のうち
    /// この端末にモデルが無い言語があれば能動的にダウンロードしておく（受け入れ条件4・
    /// attempt 5）。この段階ではまだ今日のお題画面（非モーダル）にいるので、OSの
    /// ダウンロード確認シートが出たとしても、それに巻き込まれて閉じる `fullScreenCover` が
    /// 存在しない（attempt 3 の致命的症状の再発防止。詳細は `Translator` クラス冒頭のコメント）。
    func openTimeline() async {
        guard let prompt, myPost != nil, !isPreparingTimeline else { return }
        await prepareTimelineLanguagesIfNeeded(promptID: prompt.id)
        timelineContent = .loading
        isTimelinePresented = true
        do {
            likedPostIDs = try await backend.likedPostIDs()
        } catch {
            alertMessage = error.localizedDescription
        }
        await drawNextPost()
    }

    /// まだ読んでいない候補の言語のうち、この端末にモデルが無い（`.supported`）ものを
    /// 順番にダウンロードしておく（受け入れ条件4・attempt 5）。
    ///
    /// 1件も無ければ即座に返り、`isPreparingTimeline` を立てない（2回目以降・すでに
    /// 全言語が揃っている場合に余計な待ちを作らないため。F19「2回目以降は待たない」）。
    ///
    /// **attempt 6**: 候補の言語がまだ残っていても、`translator.needsPreparation(_:)` で
    /// 「実際に試みる価値があるか（＝クールダウン中でないか）」を先に確認する。直近で
    /// 試して `.supported` のまま完了しなかった言語は、`Translator` 側のクールダウンが
    /// 明けるまで対象から外す。試みる言語が1件も無ければ `isPreparingTimeline` すら
    /// 立てず、即座に返る（eval-5.md [1]: タイムラインを開くたびに毎回60〜120秒待たされる
    /// 問題の修正）。
    ///
    /// 全体の待ちが際限なく伸びないよう、`timelinePreparationBudgetSeconds` を超えたら
    /// 残りの言語は諦めて進む（諦めた言語は、あとで `drawNextPost` が一時的な失敗として
    /// 読み飛ばし、次回の巡回・次回起動で再挑戦する）。
    private func prepareTimelineLanguagesIfNeeded(promptID: String) async {
        let posts = (try? await backend.timelinePosts(promptID: promptID)) ?? []
        let viewed = (try? await backend.viewedPostIDs()) ?? []
        let languages = Set(
            posts
                .filter { !viewed.contains($0.id) }
                .map { $0.bodyLanguage.lowercased() }
        )
        guard !languages.isEmpty else { return }

        var languagesToPrepare: [String] = []
        for language in languages {
            if await translator.needsPreparation(sourceLanguageCode: language) {
                languagesToPrepare.append(language)
            }
        }
        guard !languagesToPrepare.isEmpty else { return }

        isPreparingTimeline = true
        defer { isPreparingTimeline = false }
        let deadline = Date().addingTimeInterval(Self.timelinePreparationBudgetSeconds)
        for language in languagesToPrepare {
            guard Date() < deadline else { break }
            await translator.prepareIfNeeded(sourceLanguageCode: language)
        }
    }

    /// 準備フェーズ全体に掛けてよい時間の上限。未ダウンロードの言語が複数あっても、
    /// 合計でこれを超えたら残りは諦めて世界タイムラインを開く（画面を固まらせないため）。
    private static let timelinePreparationBudgetSeconds: TimeInterval = 90

    /// 次の1件へ進む。前へ戻る操作は用意しない（置いた前提5）。
    func advanceTimeline() async {
        guard isTimelinePresented else { return }
        await drawNextPost()
    }

    /// 次の1件を引いて翻訳する（F18 / F20）。
    ///
    /// 翻訳できない言語ペア、または翻訳に失敗した回答は表示せずスキップし、
    /// バックエンドから次を引き直す。既読にするタイミングは「翻訳できて実際に表示できると
    /// 確定した時点」または「恒久的に翻訳できないと確定した時点」だけにする（バグ4の修正）。
    /// モデル未取得のタイムアウトなど**一時的な失敗**は既読にせず、この巡回のあいだだけ
    /// バックエンドの候補から一時的に除外して無限ループを避ける（永続化しないので、
    /// 次の巡回・次回起動では再挑戦できる）。
    /// 表示を切り替えるのは翻訳が確定してからだけにして、原文が一瞬見えてから
    /// 差し替わる「ちらつき」を避ける（間は `.loading` のまま）。
    private func drawNextPost() async {
        guard let prompt else {
            timelineContent = .empty
            return
        }
        timelineContent = .loading
        do {
            var skippedThisDraw: Set<UUID> = []
            draw: while true {
                switch try await backend.nextTimelinePost(
                    promptID: prompt.id,
                    excluding: skippedThisDraw,
                    autoMarkViewed: false
                ) {
                case .post(let post):
                    switch await translator.translate(post.body, sourceLanguageCode: post.bodyLanguage) {
                    case .text(let translatedBody):
                        try await backend.markPostViewed(post.id)
                        timelineContent = .post(post.displaying(translatedBody: translatedBody))
                    case .unavailable(let permanent):
                        if permanent {
                            try await backend.markPostViewed(post.id)
                        } else {
                            skippedThisDraw.insert(post.id)
                        }
                        continue draw
                    }
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
        // 通知の予約状態（F24）を目で確かめられるようにする。
        if let next = nextScheduledNotificationAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parts.append("next notif \(formatter.string(from: next))")
        } else {
            parts.append("next notif none")
        }
        return parts.joined(separator: " · ")
    }
}
