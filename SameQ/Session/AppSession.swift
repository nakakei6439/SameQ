import Foundation
import Observation
import os.log

private let peekLog = Logger(subsystem: "com.nakakei6439.SameQ", category: "peek")

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
    /// Plus 購入・復元の窓口（F28 / F29 / F30 / F31）。`isPlus` の判定は
    /// `currentEntitlement()` を毎回見ず、`isPlus` キャッシュを更新して UI へ配る。
    private let plusService: PlusService?

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
    /// サーバ時計と `clock.now` の差（秒）。`start()` で1回だけ取得し、
    /// `Debug` オーバーレイの「ends in Xs」「next in Xs」表示に使う
    /// (受け入れ条件5、`eval-2.md` 改善提案4)。
    /// 端末時計を N 時間ずらしても、`serverNow = clock.now + serverNowOffset`
    /// は真のサーバ時刻に揃うため、残り秒数は変わらない。
    /// 取得できなかったとき（オフライン・RPC 404）は 0 のまま。
    private(set) var serverNowOffset: TimeInterval = 0
    /// Debug オーバーレイ用。いまのお題で表示しうる回答の総数と、既読の件数。
    private(set) var timelineCandidateCount = 0
    private(set) var timelineViewedCount = 0
    /// いまのお題で**このユーザーがまだ読める未読の回答件数**（F40 / スプリント16）。
    /// `timelineCandidateCount - timelineViewedCount` を `0` で床打ちした計算プロパティで、
    /// `TimelineView` の前向きな案内表示の分岐に使う。`refreshTimelineCounts` で
    /// `timelineCandidateCount` と `timelineViewedCount` が更新されるたび最新になる。
    /// 候補が0件・既読数過多で負になり得ても、UI には「0件」として渡す。
    var unreadTimelineCount: Int {
        max(0, timelineCandidateCount - timelineViewedCount)
    }
    private(set) var reportedCount = 0
    /// お題の自動生成（F26 / F27）で破棄された候補の累計件数
    /// （受け入れ条件 4「破棄された記録が残る」）。UI には出さないが
    /// `-SameQDebugOverlay` で見えるようにするためキャッシュしている。
    private(set) var discardedCandidatesCount = 0

    /// 現在の通知許可状態（F25）。設定画面で「通知はオフです」案内を出すか判定する。
    /// `nil` のときは未確認（オンボーディング前など）。
    private(set) var notificationAuthorizationStatus: NotificationAuthorizationStatus?
    /// 次回の通知が予約されている時刻（Debug オーバーレイ用）。未予約は nil。
    private(set) var nextScheduledNotificationAt: Date?

    /// 自分の回答への受信いいね数（F35・受け入れ条件3）。
    /// 0 のときは表示しない（無いいねは刺激が強いため）。
    /// Supabase から取得し、1秒ごとの `refresh()` で更新する。
    private(set) var receivedLikeCount: Int = 0
    /// 直近の background 先読み（F41・スプリント17 attempt 2）で pre-fetch の対象として
    /// 選ばれた言語コードのスナップショット。Debug オーバーレイでの目視確認と、
    /// UI テストで「先読み対象として qtd が選ばれた」ことを assert するために使う。
    /// エンドユーザー向け UI には出さない（受け入れ条件6・F19）。
    /// 値は background に移るたびに上書きされ、foreground に戻ったあとも残る
    ///（検証で読み取るタイミングを `peek` 直後に固定しなくて済むように）。
    private(set) var lastPeekedLanguages: [String] = []
    /// 直近の background 先読み（F41・スプリント17 attempt 3）で「準備に成功した」
    /// 言語コードのスナップショット。`peeked [xx]` が「対象として選ばれた」を表す
    /// のに対し、`prepared [xx]` は「実際にモデル取得まで完了した（=次回以降の
    /// 初回表示待ちが消えた）」を表す。両者を Debug オーバーレイに並べることで、
    /// 「先読み前 → 先読み後」の差分（eval-2.md [1] 後半の観測不能問題）を
    /// 開発者向けに end-to-end で観測できるようにする。
    /// エンドユーザー向け UI には出さない（受け入れ条件6・F19）。
    /// 値は background に移るたびに上書きされ、foreground に戻ったあとも残る。
    private(set) var lastPreparedLanguages: [String] = []
    /// 通知タップ（F25）で「今日は入力したい」「世界タイムラインを見たい」
    /// 「お題待ち画面を開きたい」のどれを開くべきかを `RootView` へ伝える。
    /// `start()` 完了後に消費される（nil に戻すと RootView も追従する）。
    private(set) var pendingDeepLinkTarget: DeepLinkTarget?
    /// Plus 画面（F28）の表示状態。RootView の `.sheet` から監視する。
    var isPlusViewPresented = false
    /// 直近の Plus エンタイトルメント（復元ボタンや購入後の状態表示に使う）。
    /// `nil` の間は未購入扱い（`isPlus == false`）。
    private(set) var plusEntitlement: PlusEntitlement?
    /// 直近の Plus 商品の表示情報（`PlusView` で価格を出すためにキャッシュ）。
    private(set) var plusProducts: [PlusProduct] = []
    /// 投稿フォームに現在入っている装飾（F30）。投稿完了または画面離脱でクリア。
    /// `@Observable` で追跡される View 側の状態として公開する。
    var pendingDecorations: [PostDecoration] = []

    /// 投稿失敗などの一時的なメッセージ。表示したら nil に戻す。
    var alertMessage: String?

    /// `refreshReceivedLikeCount()` で `SupabaseError.notFound` を一度でも
    /// 検知したかどうか（attempt 13: eval-9.md [2] 改善提案3）。
    /// 毎秒の `refresh()` で同じ PGRST202 が連続しても、`alertMessage` を
    /// 一度しか立てない（OK で閉じた直後に再ポップしない）。
    /// `deleteAccount()` などの明示的な状態リセットでも false に戻す。
    private var hasShownReceivedLikesRpcNotFoundAlert = false

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
    ///
    /// `plusService` を `nil` にすると Plus 機能を一切行わない（既存ユニットテスト用）。
    /// `nil` を渡さないときは `-SameQFakePlus` を見て `FakePlusService` を使うか
    /// `StoreKitPlusService` を使うかを切り替える（受け入れ条件6,3,4,5 の検証用）。
    init(
        backend: Backend = BackendProvider.make(),
        clock: AppClock = AppClock(),
        translator: Translator? = nil,
        notificationScheduler: NotificationScheduling? = nil,
        plusService: PlusService? = nil
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
        if let plusService {
            self.plusService = plusService
        } else if LaunchOptions.current.fakePlus {
            // UI テストや Debug 経路でのみ FakePlusService を使う（スプリント10 で導入）。
            self.plusService = FakePlusService(active: LaunchOptions.current.plusActiveAtLaunch)
        } else {
            // スプリント14（F37）: Plus 課金基盤を RevenueCat に差し替え済み。
            // 既定の Release / Debug 経路は `RevenueCatPlusService`。
            // 旧 `StoreKitPlusService` 経路は `-SameQUseStoreKitPlus` を付けたときだけ
            // 一時的に使う（escape hatch）。運営側のダッシュボード反映確認は
            // RevenueCat 経路で実施する（spec.md 受け入れ条件4）。
            if LaunchOptions.current.useStoreKitPlus {
                self.plusService = StoreKitPlusService()
            } else {
                self.plusService = RevenueCatPlusService()
            }
        }
        self.now = clock.now
    }

    /// Plus 状態が現在有効かどうか（F28）。`plusService` が `nil` のときも `false`。
    var isPlus: Bool {
        plusEntitlement?.isActive(at: clock.now) ?? false
    }

    #if DEBUG
    /// テスト用：`unreadTimelineCount` の境界値検証のために `timelineCandidateCount` /
    /// `timelineViewedCount` を直接書き換える。`refreshTimelineCounts` 相当の内部状態を
    /// 任意の値で再現する目的のみで、本番経路（`drawNextPost` 内）では呼ばれない。
    /// - Note: 単体テスト `TimelineUnreadCountTests` 専用。スプリント16（F40）。
    func replaceTimelineCountsForTest(candidate: Int, viewed: Int) {
        timelineCandidateCount = candidate
        timelineViewedCount = viewed
    }
    #endif

    /// 起動時の読み込み。アカウントが無ければ初回設定へ、
    /// あればお題の状態に応じてお題待ち／今日のお題／タイムラインへ。
    func start() async {
        screen = .loading
        // BAN状態のアカウントは、今日のお題にもタイムラインにも入れない（F16）。
        // 運営がサーバー側でBANを切り替える運用のため、アプリ内に解除UIは無い。
        // スプリント13:
        //   * サーバ側ステータス (`backend.currentServerSideStatus()`) を RPC で取得し、
        //     `banned` ならサーバ起点のBANとして .banned 画面に固定する
        //     (受け入れ条件2・3)。
        //   * Debug限定の `-SameQBanned` も引き続き有効 (LocalBackend 経路での検証用)。
        //   * 通信失敗時は fail-open で起動する (Backend が fail-open を返す前提)。
        let debugBanned = LaunchOptions.current.isBanned
        let serverBanned: Bool
        do {
            let status = try await backend.currentServerSideStatus()
            serverBanned = (status == "banned")
        } catch {
            serverBanned = false
        }
        if debugBanned || serverBanned {
            screen = .banned
            return
        }
        // スプリント13 attempt 2 (eval-1.md [4] の修正):
        //   期限切れ safety logs の自動削除をアプリ起動時にも走らせる。
        //   pg_cron が無くてもこの経路で自動削除が「実際に動く」ことを示す。
        //   失敗しても UI を止めない（fail-open・削除できなくても次回起動時に再試行）。
        if let purged = try? await backend.purgeExpiredSafetyLogs(), purged > 0 {
            #if DEBUG
            print("[SameQ] start: purged \(purged) expired safety logs at launch")
            #endif
        }
        // サーバ時計を 1 度だけ取得し、`serverNowOffset` を確定させる
        // (受け入れ条件5・eval-2.md 改善提案4)。これで `Debug` オーバーレイの
        // 「ends in Xs」「next in Xs」が端末時計ずれに引きずられなくなる。
        // 通信失敗時は 0 のままにし、その間 overlay は `clock.now` 基準で
        // 動く（UI を完全停止させない）。
        if let serverNow = try? await backend.currentServerTime() {
            serverNowOffset = serverNow.timeIntervalSince(clock.now)
            #if DEBUG
            print("[SameQ] start: serverNowOffset \(serverNowOffset)s")
            #endif
        }
        // Plus のエンタイトルメントを起動直後に読む（F28）。サンドボックス購入は
        // OS 側で永続化されているので、アプリを削除して再インストールしても
        // `currentEntitlement()` 経由で復元される。「購入を復元」ボタンの
        // 動作確認（受け入れ条件6）はここでも一定度の再現になる。
        await refreshPlusEntitlement()
        do {
            promptState = try await backend.promptState()
            let loadedUser = try await backend.currentUser()
            user = loadedUser
            // Debug オーバーレイ用にお題自動生成の破棄件数を読み込む（F26）。
            discardedCandidatesCount = try await backend.discardedCandidatesCount()

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

    /// Plus の現在のエンタイトルメントを `plusService` から取り直して `plusEntitlement` に
    /// 反映する（F28 / F31）。「購入を復元」の直後、購入直後、`PlusView` を開いた
    /// タイミングで呼ぶ。
    ///
    /// **attempt 4（eval-3.md [3] への対応・条件6 保護）**: 起動経路や `PlusView` を開く
    /// タイミングで呼ばれる `currentEntitlement()` が `nil` を返したとき、既存
    /// `plusEntitlement` が購読期間内（`isActive(at: clock.now)`）であれば上書きしない。
    /// オフライン + SDK キャッシュ喪失で `nil` が返る状況でも、すでに Plus だった
    /// ユーザーが無料状態に転落しないための保護（受け入れ条件6「通信できない状態で
    /// 起動しても、すでに Plus のユーザーが無料状態に転落せず」）。逆に、エンタイトルメント
    /// 情報が得られた（`non-nil` だった）場合は最新の値で置き換える（購読期間更新を反映）。
    /// `plusService` が `nil` のときは Plus 機能が無いときなので従来どおり `nil` を入れる。
    @discardableResult
    func refreshPlusEntitlement() async -> PlusEntitlement? {
        guard let plusService else {
            plusEntitlement = nil
            return nil
        }
        let entitlement = await plusService.currentEntitlement()
        if let entitlement {
            // 取得できた: 最新の値で置き換える（購読期間更新・サブスク状態の変化を反映）。
            plusEntitlement = entitlement
        } else if let existing = plusEntitlement, existing.isActive(at: clock.now) {
            // 取得できなかった（オフライン等で SDK キャッシュが空）が既存 Plus は生きている:
            // 上書きしない（受け入れ条件6 保護）。 `isActive` が false の既存値（=期限切れ）は
            // `nil` で置き換えて良い（もう Plus では無いので）。
            return existing
        } else {
            // 取得できず、既存も無い or 期限切れ: `nil` で置き換える。
            plusEntitlement = nil
        }
        return plusEntitlement
    }

    /// Plus 画面の表示中に SKU 一覧を取り直す（F28）。初回ロード・復元後に呼ぶ。
    @discardableResult
    func refreshPlusProducts() async -> [PlusProduct] {
        guard let plusService else {
            plusProducts = []
            return []
        }
        let products = await plusService.availableProducts()
        plusProducts = products
        return products
    }

    /// 指定した Plus 商品を購入する（F28）。成功時はエンタイトルメントを更新する。
    /// 失敗時は `alertMessage` にユーザー向けメッセージを流す。
    @discardableResult
    func purchasePlus(_ product: PlusProduct) async -> Bool {
        guard let plusService else { return false }
        do {
            let entitlement = try await plusService.purchase(product)
            plusEntitlement = entitlement
            return true
        } catch let error as PlusPurchaseError {
            // ユーザーキャンセルはエラー表示しない（受け皿がないだけで異常ではない）。
            if case .userCancelled = error { return false }
            alertMessage = error.errorDescription
            return false
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// 購入復元を実行する（F31）。Sandbox 購入の検証用でもある。
    ///
    /// **attempt 3（eval-2.md [3] への対応・条件6 保護）**: `restore()` が
    /// `nil` を返したときは既存の `plusEntitlement` を上書きしない。オフラインで
    /// 偶発的に `nil` が返った場合でも、すでに Plus だったユーザーが無料状態に
    /// 転落しないための保護（受け入れ条件6「通信できない状態で起動しても、すでに
    /// Plus のユーザーが無料状態に転落せず」）。逆に、エンタイトルメント情報が
    /// 得られた（`non-nil` だった）場合は最新の値で置き換える（購読期間更新を反映）。
    @discardableResult
    func restorePlus() async -> Bool {
        guard let plusService else { return false }
        do {
            let entitlement = try await plusService.restore()
            if let entitlement {
                plusEntitlement = entitlement
            }
            // `nil` のときは plusEntitlement を更新しない（既存の Plus 状態を温存）。
            return entitlement != nil
        } catch let error as PlusPurchaseError {
            alertMessage = error.errorDescription
            return false
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// Plus 画面を開く前の準備（F28）。SKU を読み込む。エラーは無い（空配列を返すだけ）。
    func preparePlusView() async {
        await refreshPlusProducts()
        await refreshPlusEntitlement()
    }

    /// 投稿フォームの装飾選択をクリアする（F30）。送信成功後・お題切替時に呼ぶ。
    func clearPendingDecorations() {
        pendingDecorations = []
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
        // 受信いいね数を定期更新（F35・受け入れ条件3）。
        await refreshReceivedLikeCount()
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

    /// 自分の回答（今日のお題）に付いているいいねの件数を更新する（F35・受け入れ条件3）。
    /// Supabase が `Backend.receivedLikeCount(forPostID:)` を持っているときだけ呼ばれる
    /// （ローカルバックエンドでは 0 を返す既定実装）。
    ///
    /// 失敗時の挙動（attempt 12: eval-8.md の改善提案3 / attempt 13: eval-9.md [2]）:
    ///   * `SupabaseError.notFound`（関数未適用 PGRST202 / 404）のときだけ `alertMessage`
    ///     を立て、それ以外は静かに `receivedLikeCount = 0` に戻す（バックエンドが
    ///     まだ古い・権限が無い等の状況でも画面を止めないため）。
    ///   * `alertMessage` は **同一セッションで一度だけ**立てる（attempt 13 追加）。
    ///     `RootView` の 1 秒ごとの `refresh()` で同じ 404 が連続しても、
    ///     OK で閉じた直後に再ポップして毎秒エラーを連発しないようにする。
    ///     「無言で 0 のまま」を放置すると condition 7（通信失敗時に画面表示）の
    ///     趣旨に反するため、関数未適用だけはユーザー（とデバッグログ）に
    ///     知らせる（ただし 1 回だけ）。
    private func refreshReceivedLikeCount() async {
        guard let myPost else {
            receivedLikeCount = 0
            return
        }
        do {
            let count = try await backend.receivedLikeCount(forPostID: myPost.id)
            receivedLikeCount = count
        } catch let error as SupabaseError {
            receivedLikeCount = 0
            if case .notFound = error {
                #if DEBUG
                print("[SameQ] refreshReceivedLikeCount: RPC notFound - migration 20260820000005_received_like_count.sql is not applied on remote.")
                #endif
                if !hasShownReceivedLikesRpcNotFoundAlert {
                    hasShownReceivedLikesRpcNotFoundAlert = true
                    alertMessage = L10n.Errors.supabaseFunctionMissing
                }
            }
        } catch {
            receivedLikeCount = 0
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

    // MARK: プロフィール編集・アカウント削除（F32 / F33）

    /// プロフィール（絵文字・ニックネーム）を更新する（F32）。
    /// 成功時は `user` を差し替え、`myPosts` の `authorEmoji` / `authorNickname` も
    /// バックエンド側で遡って更新される（受け入れ条件2）。
    @discardableResult
    func updateProfile(emoji: String, nickname: String?) async -> Bool {
        do {
            let updated = try await backend.updateProfile(emoji: emoji, nickname: nickname)
            user = updated
            // 自分の回答（`myPost`）が現在表示中であれば、新しい表示情報を即座に反映する。
            if let prompt {
                myPost = try await backend.myPost(promptID: prompt.id)
            }
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// アカウントを削除する（F33）。
    /// 成功時はすべての状態をクリアして初回設定画面へ戻る。
    /// 削除確認は呼び出し側（`SettingsView`）が `.confirmationDialog` 等で行う。
    @discardableResult
    func deleteAccount() async -> Bool {
        do {
            try await backend.deleteAccount()
            await resetToOnboarding()
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    /// アカウント削除後など、関連するすべての画面状態を初期化して
    /// 初回設定（オンボーディング）へ戻すヘルパ。
    private func resetToOnboarding() {
        user = nil
        myPost = nil
        promptState = .waiting(nextStartsAt: nil)
        promptDisplayText = nil
        timelineContent = .loading
        likedPostIDs = []
        blockedAuthors = []
        pendingDecorations = []
        isTimelinePresented = false
        isSettingsPresented = false
        isPlusViewPresented = false
        pendingDeepLinkTarget = nil
        alertMessage = nil
        promptTranslationTask?.cancel()
        promptTranslationTask = nil
        lastTranslatedPromptID = nil
        timelineCandidateCount = 0
        timelineViewedCount = 0
        reportedCount = 0
        discardedCandidatesCount = 0
        receivedLikeCount = 0
        hasShownReceivedLikesRpcNotFoundAlert = false
        screen = .onboarding
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
            let posts = pendingDecorations
            let plus = isPlus
            myPost = try await backend.submitPost(
                promptID: prompt.id,
                body: body,
                decorations: posts,
                isPlus: plus
            )
            // 投稿確定後に装飾選択は破棄する（同じ装飾が次の投稿に引き継がれないように）。
            clearPendingDecorations()
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

    /// F41 先読みの1起動あたり予算。`openTimeline()` の90秒よりずっと短く、
    /// アプリが background に戻った直後に短時間で済ませるための値。
    /// 3言語直列・各20秒 = 60秒まで許容するが、各言語の `modelPrepareJobTimeoutSeconds`
    /// （既定60秒）が個別の時間制限なので、通常はもっと早く終わる。
    private static let backgroundPeekBudgetSeconds: TimeInterval = 30

    /// F41 先読みで対象とする言語の最大数（受け入れ条件1「最大3件まで」）。
    private static let backgroundPeekLimit: Int = 3

    /// アプリが background へ移ったタイミングで、翻訳の先読みを**画面操作と無関係に**
    /// 実行する（受け入れ条件4「アプリを使ってない間に済ませる」）。
    ///
    /// フローチャート:
    ///   1. `user != nil`（初回設定完了）か。完了前は出会いの記録がゼロなので何もしない。
    ///   2. `await backend.isOnline()` か。`false` なら即 return（受け入れ条件5前半）。
    ///   3. `await backend.topEncounteredLanguages(limit: backgroundPeekLimit)` で
    ///      対象言語を最大3件取得（受け入れ条件1）。
    ///   4. 各言語について `Translator.peekPrepareIfNeeded` を直列に呼ぶ。
    ///      `Translator.prepareIfNeeded` の内部で `.supported` / `.unsupported` /
    ///      クールダウンを判定し、不要なら即 return / 必要なら短時間だけ試す。
    ///   5. 合計予算（30秒）超過で打ち切り。
    ///
    /// このメソッドは UI を一切変更しない（F19: pre-fetch の存在を意識させない、
    /// 受け入れ条件6）。`alertMessage` も `isPreparingTimeline` も触らない。
    /// 失敗（個別の `prepareIfNeeded` の throw / 通信失敗）は握り潰す：
    ///   * 個別の throw は `Translator.prepareIfNeeded` 自身が内部で握るので、
    ///     ここに到達するのは言語配列が空のときだけ。
    func peekTranslationsInBackground() async {
        #if DEBUG
        peekLog.notice("peekTranslationsInBackground: start, user=\(self.user != nil, privacy: .public)")
        #endif
        guard user != nil else {
            #if DEBUG
            peekLog.notice("peekTranslationsInBackground: no user, skip")
            #endif
            return
        }
        guard await backend.isOnline() else {
            #if DEBUG
            peekLog.notice("peekTranslationsInBackground: offline, skip")
            #endif
            return
        }
        let candidates = (try? await backend.topEncounteredLanguages(limit: Self.backgroundPeekLimit)) ?? []
        #if DEBUG
        peekLog.notice("peekTranslationsInBackground: candidates=\(candidates.joined(separator: ","), privacy: .public)")
        #endif
        guard !candidates.isEmpty else {
            #if DEBUG
            peekLog.notice("peekTranslationsInBackground: empty candidates, skip")
            #endif
            return
        }

        // Debug オーバーレイと UI テストのためにスナップショットを保持する
        //（スプリント17 attempt 2: eval-1.md [1] の修正検証用）。
        // `lastPreparedLanguages` も併せてリセットし、この run で「実際に準備が
        // 完了した」言語だけを残す（attempt 3: eval-2.md の修正）。
        lastPeekedLanguages = candidates
        lastPreparedLanguages = []

        let deadline = Date().addingTimeInterval(Self.backgroundPeekBudgetSeconds)
        for language in candidates {
            guard Date() < deadline else { break }
            // attempt 3: 戻り値（準備の成否）を見て `prepared` スナップショットを
            // 組み立てる。`false`（既に `.installed`・クールダウン中・失敗など）は
            // 対象から除外する。`prepared` は「先読み前→先読み後」で値が増える側の
            // 観測点として機能する（eval-2.md [1] 後半の観測不能問題への対応）。
            if await translator.peekPrepareIfNeeded(sourceLanguageCode: language) {
                lastPreparedLanguages.append(language)
            }
        }
    }

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
                        // スプリント17（F41）: 翻訳が確定して「表示できた」と確定した瞬間に、
                        // その回答の言語コードをバックエンドへ記録する。
                        // 次回以降 background へ移ったタイミングで、このカウンタを元に
                        // 上位3言語の翻訳モデル先読み（`peekTranslationsInBackground`）が走る。
                        // 端末言語と同じ言語（翻訳スキップ）はここでは絶対に到達しない
                        // （`Translator.translate` が先に `.text(text)` で返している）が、
                        // 念のため同じコードなら重み付けしない。
                        if post.bodyLanguage.lowercased() != translator.targetLanguageCode {
                            try? await backend.recordLanguageEncounter(languageCode: post.bodyLanguage)
                        }
                    case .unavailable(let permanent):
                        if permanent {
                            try await backend.markPostViewed(post.id)
                        }
                        // 「出会った」事実として言語コードをバックエンドへ記録する。
                        // attempt 1 では恒久失敗（`.unavailable(permanent: true)`）の
                        // ときだけ記録していたが、F41 の「直近よく出会う言語」は
                        // 一時失敗（モデル未DL 等）も含むべき。記録しておかないと
                        // `qtd`（疑似モードで「モデル未DL」を再現するマーカー）など、
                        // 「準備中」でスキップされ続けた言語がいつまでも
                        // `topEncounteredLanguages` に入らず、background 先読みの
                        // 対象にもならない（eval-1.md [1] の修正）。
                        // クールダウン判定は `Translator` 側で効くので、過剰に
                        // 再試行する心配は無い。
                        try? await backend.recordLanguageEncounter(languageCode: post.bodyLanguage)
                        if !permanent {
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
        // サーバ時計基準の「now」を計算する。`serverNowOffset` は `start()` で
        // 1 度だけ取得し、`currentServerTime()` が失敗したときは 0 のまま
        // (= `clock.now`) になる。これにより、端末時計をずらしても
        // 「ends in Xs」「next in Xs」がサーバ時計基準で安定する (受け入れ条件5)。
        let serverAdjustedNow = now.addingTimeInterval(serverNowOffset)
        var parts = ["now \(formatter.string(from: now))", "srv \(formatter.string(from: serverAdjustedNow))", "scenario \(LaunchOptions.current.scenario.rawValue)"]
        switch promptState {
        case .active(let prompt):
            parts.append("\(prompt.id) ends in \(Int(prompt.endsAt.timeIntervalSince(serverAdjustedNow)))s")
        case .waiting(let nextStartsAt):
            if let nextStartsAt {
                parts.append("waiting / next in \(Int(nextStartsAt.timeIntervalSince(serverAdjustedNow)))s")
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
        // Plus 状態（F28）を `-SameQDebugOverlay` で目視確認できるようにする。
        parts.append(isPlus ? "plus" : "free")
        // お題自動生成の破棄件数（F26 / 受け入れ条件 4）。
        parts.append("discarded \(discardedCandidatesCount)")
        // 通知の予約状態（F24）を目で確かめられるようにする。
        if let next = nextScheduledNotificationAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parts.append("next notif \(formatter.string(from: next))")
        } else {
            parts.append("next notif none")
        }
        // F41・スプリント17 attempt 2: 直近の background 先読みで対象になった言語を
        // Debug オーバーレイに出し、「実際に走った痕跡」を目視で確認できるようにする。
        // エンドユーザー向け UI ではない（`-SameQDebugOverlay` 指定時のみ）。
        if !lastPeekedLanguages.isEmpty {
            parts.append("peeked [\(lastPeekedLanguages.joined(separator: ", "))]")
        }
        // F41・スプリント17 attempt 3: 「実際に準備が完了した（=次回以降の初回表示待ちが
        // 消えた）」言語を Debug オーバーレイに出す。`peeked` が「対象として選んだ」を
        // 表すのに対し `prepared` は「試行が成功した」を表すため、両者が並んだ状態で
        // background 前後の差分として観測できる（eval-2.md [1] の修正）。
        // 失敗・`.installed`・クールダウン中などはここに出ない。
        if !lastPreparedLanguages.isEmpty {
            parts.append("prepared [\(lastPreparedLanguages.joined(separator: ", "))]")
        }
        return parts.joined(separator: " · ")
    }
}
