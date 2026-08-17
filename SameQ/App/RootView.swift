import SwiftUI

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
            case .failure(let message):
                failureView(message: message)
            }
        }
        .fontDesign(.rounded)
        .environment(session)
        .overlay(alignment: .bottom) { debugOverlay }
        .task {
            await session.start()
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                await session.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // バックグラウンドから戻ったときは、待たずにその場で見直す。
            if phase == .active {
                Task { await session.refresh() }
            }
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
                .overlay(alignment: .bottom) { debugOverlay }
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
    @ViewBuilder
    private var debugOverlay: some View {
        if LaunchOptions.current.showsDebugOverlay {
            Text(session.debugStatusLine)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(.bottom, 4)
                .allowsHitTesting(false)
                .accessibilityIdentifier("debug.status")
        }
    }
}
