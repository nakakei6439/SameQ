import SwiftUI

/// 規約・プライバシーポリシー表示シート（F32）。
///
/// `OnboardingView.legalCard` と同じ見た目で、本文のみを `LegalText` から読み出して
/// 表示する。「リリース前に差し替える」前提のダミー本文（spec.md の「置いた前提12」）。
struct LegalView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background { Theme.canvas }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                        .accessibilityIdentifier("settings.legal.close")
                }
            }
        }
    }

    private var title: String {
        switch document {
        case .terms: return L10n.Settings.legalSheetTermsTitle
        case .privacy: return L10n.Settings.legalSheetPrivacyTitle
        }
    }

    private var content: String {
        switch document {
        case .terms: return LegalText.terms
        case .privacy: return LegalText.privacy
        }
    }
}
