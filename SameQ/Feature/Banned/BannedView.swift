import SwiftUI

/// BAN状態のアカウントで起動したときの画面（F16）。
///
/// BANは運営がサーバー側で切り替える運用で、アプリ内に運営用の画面は作らない
/// （置いた前提10）。ここから今日のお題・タイムライン・設定への導線は一切置かない
/// （`RootView` の `switch` からもこの画面以外に到達できない）。
///
/// 文言は日本語・英語のどちらの端末でも読めるよう、2行で両方を出す
/// （アプリ全体の多言語対応の基盤はまだ無いため、この画面に限った対応）。
struct BannedView: View {
    var body: some View {
        ZStack {
            Theme.canvas

            VStack(spacing: 18) {
                Text("🚫")
                    .font(.system(size: 44))
                Text("このアカウントは利用できません")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("banned.title")
                Text("This account can no longer be used")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("banned.titleEnglish")
                Text(
                    "運営がこのアカウントの利用を停止しました。今日のお題にも世界の回答にも入れません。\nThe operator has suspended this account. You can't access today's prompt or the timeline."
                )
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("banned.detail")
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
