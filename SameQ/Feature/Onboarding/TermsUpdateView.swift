import SwiftUI

/// 規約改定後の再同意（F53 / 置いた前提42）。
///
/// ゼロトレランス条項のように「何が許されないか」を変える改定は、既存の利用者にも
/// 読ませなければ意味がない。同意するまで閉じられない全画面にして、投稿させない。
///
/// 初回設定の規約画面（`OnboardingView.termsStep`）と同じ構成にしてある
/// （規約全文＋プライバシーポリシー全文＋ゼロトレランスの要約＋同意ボタン）。
struct TermsUpdateView: View {
    @Environment(AppSession.self) private var session

    @State private var isAccepting = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.Onboarding.termsUpdateTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("termsUpdate.title")
                    Text(L10n.Onboarding.termsUpdateBody)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    legalCard(title: L10n.Onboarding.termsBody, body: LegalText.terms)
                    legalCard(title: L10n.Onboarding.privacyBody, body: LegalText.privacy)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                        Text(L10n.Onboarding.zeroToleranceSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    Button(isAccepting ? L10n.Common.processing : L10n.Onboarding.termsUpdateAgree) {
                        guard !isAccepting else { return }
                        isAccepting = true
                        Task {
                            await session.acceptCurrentTerms()
                            isAccepting = false
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(enabled: !isAccepting))
                    .disabled(isAccepting)
                    .accessibilityIdentifier("termsUpdate.agree")
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("termsUpdate.root")
    }

    /// `OnboardingView.legalCard` と同じ体裁。
    private func legalCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            ScrollView {
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: 180)
            .cardBackground(cornerRadius: 16)
        }
    }
}
