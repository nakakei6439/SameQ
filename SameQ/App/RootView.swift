import SwiftUI
import UserNotifications

/// 画面の入り口。`AppSession.screen` の値だけで表示を決める。
///
/// 世界タイムラインはここからしか開かず、`AppSession.openTimeline()` は
/// 自分の回答が無いと何もしないので、未回答のまま到達する経路が存在しない。
/// お題の有効期間はここの1秒ごとの `refresh()` で見張り、画面を開いたままでも
/// 期限をまたいだ瞬間にお題待ちへ切り替わる（F09 / F10）。
struct RootView: View {
    @State private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    /// お題の切り替わりを見張る間隔。端末内の判定だけなので1秒でも軽い。
    private let refreshInterval = Duration.seconds(1)

    var body: some View {
        Group {
            switch session.screen {
            case .loading:
                loadingView
            case .onboarding:
                OnboardingView()
            case .waiting:
                WaitingPromptView()
            case .today:
                TodayPromptView()
            case .banned:
                BannedView()
            case .failure(let message):
                failureView(message: message)
            }
        }
        .fontDesign(.rounded)
        .environment(session)
        // 翻訳セッションの供給元（F18 / F22）。画面が切り替わっても常駐させておく必要があるので、
        // 表示中の画面と同じ階層ではなく背景として1つだけ持たせる。
        .background(TranslationHostView(translator: session.translator))
        .background(
            // 通知タップのブリッジ（F25）。`UIViewControllerRepresentable` 経由で
            // `AppSession` にディープリンクを伝える。表示要素を持たない。
            NotificationDelegateHost()
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { debugOverlay }
        .task {
            await session.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                await session.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sameQNotificationTapped)) { _ in
            // 通知タップでアプリが起動・前面化された（F25）。
            // お題の有無に関わらず「今日の画面に遷移したい」という意思だけ伝え、
            // 実際の遷移は `AppSession` 側が開いた画面の状態で判断する。
            session.handleDeepLink(.today)
        }
        .onChange(of: scenePhase) { _, phase in
            // バックグラウンドから戻ったときは、待たずにその場で見直す。
            // 同時に、通知の許可状態は OS 側でも変わり得るので読み直し、
            // 許可されていれば通知を再予約する（F24）。
            if phase == .active {
                Task {
                    await session.refreshNotificationAuthorizationStatus()
                    await session.scheduleDailyReminderIfPossible()
                }
                Task { await session.refresh() }
            }
        }
        .onChange(of: session.pendingDeepLinkTarget) { _, target in
            // 通知タップでディープリンクが届いたとき（F25）。
            // 回答済みアカウントで `.timeline` が指定されたら世界タイムラインを開く。
            // それ以外は `screen` が今日の画面かお題待ちかに応じて、RootView 自体が
            // 既に正しい画面を選んでいるはずなので何もしない（`pendingDeepLinkTarget` を
            // 消費するだけにする）。
            guard let target else { return }
            switch target {
            case .timeline:
                if session.screen == .today, session.myPost != nil {
                    Task { await session.openTimeline() }
                }
            case .today, .waiting:
                break
            }
            session.consumeDeepLink()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { session.isTimelinePresented },
                set: { if !$0 { session.closeTimeline() } }
            )
        ) {
            TimelineView()
                .fontDesign(.rounded)
                .environment(session)
                .safeAreaInset(edge: .bottom, spacing: 0) { debugOverlay }
        }
        // 設定（今回はブロック管理のみ / F15）。今日のお題とお題待ちのどちらからも開ける。
        .sheet(
            isPresented: Binding(
                get: { session.isSettingsPresented },
                set: { session.isSettingsPresented = $0 }
            )
        ) {
            SettingsView()
                .fontDesign(.rounded)
                .environment(session)
        }
    }

    private var loadingView: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ProgressView()
                .tint(Theme.inkSecondary)
        }
    }

    private func failureView(message: String) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("読み込めませんでした")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("もう一度試す") {
                    Task { await session.start() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            }
            .padding(32)
        }
    }

    /// 検証用の状態表示。`-SameQDebugOverlay` を付けた Debug ビルドでだけ出る。
    ///
    /// `overlay` ではなく `safeAreaInset` に置いて、画面の一番下のボタンや文言に
    /// 重ならないようにしている（重なると評価時に何も読めなくなるため）。
    @ViewBuilder
    private var debugOverlay: some View {
        if LaunchOptions.current.showsDebugOverlay {
            Text(session.debugStatusLine)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.78))
                .allowsHitTesting(false)
                .accessibilityIdentifier("debug.status")
        }
    }
}

/// `UNUserNotificationCenterDelegate` の橋渡し（F25）。
///
/// 通知タップを `AppSession.handleDeepLink(_:)` に伝える。`UIViewControllerRepresentable`
/// 経由で `UIViewController` を 1 枚出し、その `viewDidLoad` で `UNUserNotificationCenter.current()`
/// の delegate を自身に設定する。表示要素は一切持たないので、画面レイアウトには影響しない。
private struct NotificationDelegateHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NotificationDelegateViewController {
        NotificationDelegateViewController()
    }

    func updateUIViewController(_ uiViewController: NotificationDelegateViewController, context: Context) {}
}

/// 通知タップのディープリンクを `AppSession` へ流す。
///
/// `UNUserNotificationCenterDelegate` を継承すると `NSObject` が必要になるため、
/// `UIViewController` のサブクラスとして `viewDidLoad` で自分自身を delegate に登録する。
/// フォアグラウンド配信（`willPresent`）でも通知音を鳴らしてユーザに気づかせる。
final class NotificationDelegateViewController: UIViewController, UNUserNotificationCenterDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: UNUserNotificationCenterDelegate

    /// フォアグラウンドにいる間に通知が届いたときも、音とバナーで知らせる
    /// （spec の「通知が来たときに開いて答える」体験を守るため）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// 通知をタップしてアプリが起動・前面化されたとき（F25）。
    /// 現在の画面状態に応じて遷移先を変えるのは `AppSession` 側の責務なので、
    /// ここでは「今日の画面に飛びたい」という意思だけを伝える。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            // お題待ちのときは画面遷移しない（タイムラインも今日のお題もない）。
            // それ以外は「今日の画面 or タイムライン（回答済みの場合）」を開く。
            // 実際にどちらを開くかは `AppSession` 側の `myPost` などで判断する。
            // `RootView` の `onChange(of: pendingDeepLinkTarget)` が拾う。
            NotificationCenter.default.post(
                name: .sameQNotificationTapped,
                object: nil
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    /// 通知タップでアプリが起動・前面化されたことを `AppSession` へ伝える（F25）。
    /// `NotificationDelegateViewController` が発火し、`RootView` が `MainActor` で受け取る。
    static let sameQNotificationTapped = Notification.Name("SameQ.notificationTapped")
}
