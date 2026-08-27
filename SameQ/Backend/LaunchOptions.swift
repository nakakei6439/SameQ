import Foundation

/// 起動引数で切り替えられる検証用の設定。
///
/// 実時間で28時間待つ検証はできないので、お題の有効期間の切り替わりを
/// 数十秒〜数分で再現できるようにする。**すべて Debug ビルドでのみ効き**、
/// Release ビルドでは常に既定値（`live` シナリオ・時刻オフセットなし）になる。
///
/// 使える引数:
/// - `-SameQResetState`               保存済みの状態を捨てて初回設定からやり直す
/// - `-SameQResetViewed`              既読の記録だけを消す（アカウント・回答・いいねは残す）
/// - `-SameQScenario <名前>`          お題の日程シナリオ（`live` / `expiring` / `expired` / `upcoming`）
/// - `-SameQExpirySeconds <秒>`       `expiring` で現在のお題が終了するまでの秒数（既定 180）
/// - `-SameQGapSeconds <秒>`          `expiring` で終了から次のお題開始までの秒数（既定 180）
/// - `-SameQAnswerCount <件数>`       各お題の「自分以外の回答」を指定件数に固定する（0 / 1 / 120 など）
/// - `-SameQTimeOffsetMinutes <分>`   アプリが認識する「今」を前後にずらす（負値も可）
/// - `-SameQDebugOverlay`             画面下に現在時刻・お題ID・残り秒数・未読/既読件数を出す
/// - `-SameQBanned`                   自分のアカウントがBAN状態であるかのように起動する（F16）。
///                                    運営がサーバー側でBANを切り替える運用のため、アプリ内にBAN操作UIは無い。
/// - `-SameQRateLimitTestMode`        いいね・通報の連打制限の閾値を短時間で確認できる値に縮める（F17）
/// - `-SameQFakeTranslate`            `Translator` に実際の `TranslationSession` を使わせず、
///                                    決定的な疑似翻訳（`[<言語コード>] <原文>`）を返させる（F18〜F22）。
///                                    シミュレータでは Apple Translation が全言語ペアで
///                                    未対応を返すため、翻訳の周辺ロジック（表示切り替え・
///                                    非対応スキップ・ちらつき防止・キャッシュ）を確定的に
///                                    検証するための Debug 限定モード。
/// - `-SameQNicknameTranslitDebug`     `NicknameTransliterator` を「常に音写失敗」扱いにし、
///                                    絵文字のみ表示へのフォールバックを再現する（F23）。
///                                    受け入れ条件3（音写できないニックネーム）の検証用。
/// - `-SameQNotificationHour <0〜23>`  通知の予約時刻をその時で固定する（Debug 限定・F24）。
///                                    分のランダム化はそのまま。境界値（7, 8, 21, 22）の確認用。
/// - `-SameQNotificationForceDenied`    通知許可状態を強制的に `.denied` として扱う（Debug 限定・F25）。
///                                    拒否経路の検証に使う。
/// - `-SameQSimulateNotificationTap`   `session.start()` の完了直後に、通知タップが届いたのと
///                                    等価な経路（`NotificationCenter` への `.sameQNotificationTapped`
///                                    の post）をアプリ内で発火する（Debug 限定・attempt 2）。
///                                    UI テストで「実際の通知タップ → 画面遷移」を再現するために使う。
struct LaunchOptions: Sendable {
    var resetsState: Bool = false
    var resetsViewed: Bool = false
    var scenario: PromptScenario = .live
    var expirySeconds: TimeInterval = 180
    var gapSeconds: TimeInterval = 180
    /// 各お題に用意する「自分以外の回答」の件数。nil なら同梱シードのまま。
    var answerCount: Int?
    var timeOffset: TimeInterval = 0
    var showsDebugOverlay: Bool = false
    /// `-SameQBanned`（Debug限定）。true の間は起動直後にBAN画面へ固定し、今日のお題・タイムラインへ入れない（F16）。
    var isBanned: Bool = false
    /// `-SameQFakeTranslate`（Debug限定）。true の間は `Translator` が実際の `TranslationSession` を
    /// 使わず、決定的な疑似翻訳を返す（F18〜F22。シミュレータでの検証用）。
    var fakeTranslate: Bool = false
    /// `-SameQNicknameTranslitDebug`（Debug限定）。true の間は `NicknameTransliterator` が
    /// すべての入力に対して音写失敗扱いを返し、絵文字のみ表示へのフォールバックを
    /// 受け入れ条件3（音写できないニックネーム）の検証用に再現できるようにする（F23）。
    var forceNicknameTranslitFailure: Bool = false
    /// `-SameQNotificationHour <時>`（Debug 限定・F24）。通知の予約時刻をその時で固定する。
    /// 境界値（7, 8, 21, 22）の確認用。`nil` のときは 8〜21 のランダム。
    var notificationForcedHour: Int? = nil
    /// `-SameQNotificationForceDenied`（Debug 限定・F25）。許可状態を強制 `.denied` として扱い、
    /// 通知を一切予約しない。拒否経路（設定画面に案内が出る）の検証用。
    var notificationForceDenied: Bool = false
    /// `-SameQSimulateNotificationTap`（Debug 限定・attempt 2: eval-1.md [1] の修正）。
    /// true の間は `RootView` が `session.start()` 完了直後に、通知タップが届いたのと
    /// 等価な `NotificationCenter` 投稿を行い、実際の通知タップ経路を再現する。
    /// UI テストで「回答済みアカウント → 通知タップ → タイムライン直接オープン」を
    /// 自動検証するために使う。
    var simulateNotificationTap: Bool = false
    /// `-SameQSeedOnly`（Debug 限定・スプリント09）。true の間は `PromptGenerator`
    /// を呼ばず、`SeedCatalog.loadSchedule` のシードだけの日程にする。
    /// 自動生成を切った状態でシードのお題スケジュール（F26以前の挙動）を
    /// 検証したいときに使う。
    var seedOnly: Bool = false
    /// `-SameQSkipSeed`（Debug 限定・スプリント09）。true の間は
    /// `SeedCatalog.loadSchedule` を呼ばず、空の PromptSchedule に
    /// `PromptGenerator` の自動生成だけを追加する。シードに依存しない
    /// お題自動生成の動作を UI から確認したいときに使う。
    var skipSeed: Bool = false
    /// `-SameQFakePlus`（Debug 限定・スプリント10）。true の間は `PlusService` を
    /// `RevenueCatPlusService` / `StoreKitPlusService` ではなく `FakePlusService` で動かし、
    /// `Purchase` などの挙動を UI テストで決定的に再現できるようにする。
    /// 既定（false）は App Store と接続する `RevenueCatPlusService`（スプリント14）。
    var fakePlus: Bool = false
    /// `-SameQUseStoreKitPlus`（Debug 限定・スプリント14 / escape hatch）。
    /// true の間は `PlusService` を `RevenueCatPlusService` ではなく
    /// `StoreKitPlusService`（旧 StoreKit 2 直接実装）で動かす。RevenueCat SDK の
    /// 経路を切り分けたい検証や、暫定的に旧経路へ戻したいときに使う。
    /// `fakePlus == true` のときは `FakePlusService` を優先（このフラグは無視）。
    /// Release ビルドではこの値に関わらず常に `RevenueCatPlusService`。
    var useStoreKitPlus: Bool = false
    /// `-SameQPlusActive`（Debug 限定・スプリント10）。`fakePlus` と組み合わせると、
    /// 起動時から Plus 購入済みの状態で開始する。受け入れ条件3,4,5 を UI テストで
    /// 確認するためのショートカット。
    var plusActiveAtLaunch: Bool = false
    /// いいねの連打制限（F17）。既定は15秒間に8回まで、超えたら15秒制限。
    var likeRateLimit = RateLimitSettings(maxActions: 8, windowSeconds: 15, cooldownSeconds: 15)
    /// 通報の連打制限（F17）。既定は30秒間に4回まで、超えたら20秒制限。
    var reportRateLimit = RateLimitSettings(maxActions: 4, windowSeconds: 30, cooldownSeconds: 20)
    /// 安全ログ（通報記録）の保持期間（F34）。0 なら `Backend.safetyLogRetentionSeconds`
    /// （30 日）を使う。検証用に `-SameQSafetyLogRetentionSeconds` で短縮できる。
    var safetyLogRetentionSeconds: TimeInterval = 0
    /// `-SameQUseLocalBackend`（Debug 限定・スプリント12 attempt 8）。
    /// true の間は `BackendProvider.make()` が `SupabaseBackend` ではなく
    /// `LocalBackend` を返す。UI テスト・スモーク確認は既定でこちらを付けて
    /// 起動し、本番相当の Supabase 経路を検証したいときは `-SameQUseLocalBackend`
    /// を付けない（= `useLocalBackend == false` で `SupabaseBackend`）。
    /// Release ビルドではこの値に関わらず常に `SupabaseBackend()` を返す。
    var useLocalBackend: Bool = false
    /// `-SameQForceOffline`（Debug 限定・スプリント12 attempt 11）。
    /// true の間は `SupabaseBackend.checkConnectivity()` が
    /// `NWPathMonitor` の結果に関わらず常に `SupabaseError.offline` を投げる。
    /// eval-7.md で条件6（機内モードでの起動）・条件7（通信失敗の表示と再試行）
    /// の検証手段が無いと指摘された問題に対応するための擬似オフラインフラグ。
    /// UI テストではこのフラグを付けて起動すると、`AppSession.start()` 内の
    /// `backend.promptState()` などが即座に `.offline` を投げ、
    /// 「接続してください」相当のアラート／空状態表示が現れる。
    /// Release ビルドではこの値に関わらず常に false（接続状態は実機の NW に従う）。
    var forceOffline: Bool = false

    /// このプロセスの設定。起動時に1度だけ解釈する。
    static let current = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        #if DEBUG
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        options.resetsState = arguments.contains("-SameQResetState")
        options.resetsViewed = arguments.contains("-SameQResetViewed")
        options.showsDebugOverlay = arguments.contains("-SameQDebugOverlay")
        options.isBanned = arguments.contains("-SameQBanned")
        options.fakeTranslate = arguments.contains("-SameQFakeTranslate")
        options.forceNicknameTranslitFailure = arguments.contains("-SameQNicknameTranslitDebug")
        options.notificationForceDenied = arguments.contains("-SameQNotificationForceDenied")
        options.simulateNotificationTap = arguments.contains("-SameQSimulateNotificationTap")
        options.seedOnly = arguments.contains("-SameQSeedOnly")
        options.skipSeed = arguments.contains("-SameQSkipSeed")
        options.fakePlus = arguments.contains("-SameQFakePlus")
        options.useStoreKitPlus = arguments.contains("-SameQUseStoreKitPlus")
        options.plusActiveAtLaunch = arguments.contains("-SameQPlusActive")
        if let hour = value(after: "-SameQNotificationHour").flatMap(Int.init),
           (0...23).contains(hour) {
            options.notificationForcedHour = hour
        }
        if arguments.contains("-SameQRateLimitTestMode") {
            // 手動検証・UIテストで実時間を長く待たなくて済むように回数を減らす。
            // ウィンドウは「操作を数回繰り返す」のに十分な長さを残す
            // （タップ間隔が空く実機・UIテスト環境でも、古い記録がウィンドウから外れて
            // カウントが増えなくなることがないように）。
            options.likeRateLimit = RateLimitSettings(maxActions: 3, windowSeconds: 30, cooldownSeconds: 8)
            options.reportRateLimit = RateLimitSettings(maxActions: 2, windowSeconds: 40, cooldownSeconds: 8)
        }
        if let count = value(after: "-SameQAnswerCount").flatMap(Int.init) {
            options.answerCount = max(0, count)
        }
        if let name = value(after: "-SameQScenario"), let scenario = PromptScenario(rawValue: name) {
            options.scenario = scenario
        }
        if let seconds = value(after: "-SameQExpirySeconds").flatMap(Double.init) {
            options.expirySeconds = seconds
        }
        if let seconds = value(after: "-SameQGapSeconds").flatMap(Double.init) {
            options.gapSeconds = seconds
        }
        if let minutes = value(after: "-SameQTimeOffsetMinutes").flatMap(Double.init) {
            options.timeOffset = minutes * 60
        }
        if let seconds = value(after: "-SameQSafetyLogRetentionSeconds").flatMap(Double.init) {
            options.safetyLogRetentionSeconds = seconds
        }
        options.useLocalBackend = arguments.contains("-SameQUseLocalBackend")
        options.forceOffline = arguments.contains("-SameQForceOffline")
        #endif
        return options
    }
}

/// アプリが認識する「今」。
///
/// お題の有効期間の判定はすべてここを通す。Debug ビルドでは
/// `-SameQTimeOffsetMinutes` の分だけずらせるので、期限切れ後の状態を待たずに確認できる。
struct AppClock: Sendable {
    let offset: TimeInterval

    init(offset: TimeInterval = LaunchOptions.current.timeOffset) {
        self.offset = offset
    }

    var now: Date { Date().addingTimeInterval(offset) }
}
