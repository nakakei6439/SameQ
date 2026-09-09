import SwiftUI

/// BAN状態のアカウントで起動したときの画面（F16）。
///
/// BANは運営がサーバー側で切り替える運用で、アプリ内に運営用の画面は作らない
/// （置いた前提10）。ここから今日のお題・タイムライン・設定への導線は一切置かない
/// （`RootView` の `switch` からもこの画面以外に到達できない）。
///
/// 文言は端末言語に合わせて1言語のみ表示する（スプリント15 / F38）。
struct BannedView: View {
    @Environment(AppSession.self) private var session

    /// お問い合わせシート（F51）。停止された利用者にとって、ここが運営に
    /// 異議を伝える唯一の経路になる（置いた前提41 / ガイドライン 1.2）。
    @State private var showsContact = false

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

                Text(L10n.Banned.contactHint)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L10n.Settings.supportContact) {
                    showsContact = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("banned.contact")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 28)
            .cardBackground()
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showsContact) {
            ContactView()
                .fontDesign(.rounded)
                .environment(session)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banned.root")
    }
}
