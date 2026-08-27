import SwiftUI

/// BAN状態のアカウントで起動したときの画面（F16）。
///
/// BANは運営がサーバー側で切り替える運用で、アプリ内に運営用の画面は作らない
/// （置いた前提10）。ここから今日のお題・タイムライン・設定への導線は一切置かない
/// （`RootView` の `switch` からもこの画面以外に到達できない）。
///
/// 文言は端末言語に合わせて1言語のみ表示する（スプリント15 / F38）。
struct BannedView: View {
    var body: some View {
        ZStack {
            Theme.canvas

            VStack(spacing: 18) {
                Text("🚫")
                    .font(.system(size: 44))
                Text(L10n.Banned.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("banned.title")
                Text(L10n.Banned.body)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("banned.titleEnglish")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 28)
            .cardBackground()
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banned.root")
    }
}
