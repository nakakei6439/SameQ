import SwiftUI

/// お問い合わせ（F51 / Apple ガイドライン 1.2「アプリ内に連絡先を掲載する」）。
///
/// **生の `mailto:` をボタンから直接叩くだけにはしない。** シミュレータには
/// メールアプリが無く、実機でも Mail を削除している利用者がいる。連絡先そのものが
/// 画面に文字として出ていて、コピーできる状態を常に保つ（置いた前提41）。
///
/// 設定画面だけでなく、アカウント停止（BAN）の画面からも同じ内容へ到達できる。
/// 停止された利用者にとって、そこが運営に異議を伝える唯一の経路になるため。
struct ContactView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// メールアプリを開けなかったか。開けたときは false のまま。
    @State private var mailUnavailable = false
    @State private var didCopy = false

    /// 運営の連絡先。利用規約・プライバシーポリシーに載せているものと同一。
    static let address = "nakakei6439@gmail.com"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.Settings.supportDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    addressCard

                    Button(L10n.Settings.supportCompose) {
                        compose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("settings.support.compose")

                    if mailUnavailable {
                        Text(L10n.Settings.supportMailUnavailable)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.support.mailUnavailable")
                    }

                    Text(L10n.Settings.supportReportHint)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background { Theme.canvas }
            .navigationTitle(L10n.Settings.supportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                        .accessibilityIdentifier("settings.support.close")
                }
            }
        }
    }

    /// 連絡先そのもの。選択もコピーもできる形で常に画面に出しておく。
    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Settings.supportAddressLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
            HStack(spacing: 12) {
                Text(Self.address)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.support.address")
                Spacer(minLength: 0)
                Button(didCopy ? L10n.Settings.supportCopied : L10n.Settings.supportCopy) {
                    UIPasteboard.general.string = Self.address
                    didCopy = true
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("settings.support.copy")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 16)
    }

    /// 件名と本文を用意してメールアプリを開く。
    ///
    /// 本文には返信のために必要な情報（アプリの版と利用者ID）を入れておく。
    /// 通報のメールが来ても、どのアカウントの話か分からないと24時間以内に
    /// 対処できないため。利用者IDは自分自身のIDなので、本人に見せて問題ない。
    private func compose() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.address
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.Settings.supportMailSubject),
            URLQueryItem(name: "body", value: mailBody)
        ]
        guard let url = components.url else {
            mailUnavailable = true
            return
        }
        // `canOpenURL` は `LSApplicationQueriesSchemes` の宣言が要るので使わない。
        // completion の `accepted` で開けたかどうかを見る。
        openURL(url) { accepted in
            mailUnavailable = !accepted
        }
    }

    private var mailBody: String {
        let separator = L10n.useEnglish
            ? "---- Please keep the lines below so we can reply ----"
            : "---- 以下は返信のための情報です。消さずに送信してください ----"
        let placeholder = L10n.useEnglish
            ? "(Please write your message here)"
            : "（ここにご用件をお書きください）"
        let userLine = session.user.map { "User ID: \($0.id.uuidString)" } ?? "User ID: -"
        return """
        \(placeholder)


        \(separator)
        App: SameQ \(AppVersion.displayString)
        Language: \(L10n.preferredLanguageCode)
        \(userLine)
        """
    }
}
