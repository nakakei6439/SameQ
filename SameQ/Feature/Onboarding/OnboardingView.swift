import SwiftUI

/// 初回設定フロー（F01）。
/// コンセプト説明 → 利用規約同意 → 絵文字選択 → ニックネーム入力（任意）→ 通知許可 の順に進む。
///
/// アカウントは最後のステップを終えたときに1回だけ作る。
/// 途中でアプリを落とした場合は何も保存されていないので、次回はこの画面の最初から始まる。
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case concept, terms, emoji, nickname, notification
    }

    @Environment(AppSession.self) private var session

    @State private var step: Step = .concept
    @State private var agreedToTerms = false
    @State private var selectedEmoji: String?
    @State private var nickname: String = ""
    @State private var isCompleting = false
    @FocusState private var isNicknameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background { Theme.canvas }
        // オンボーディング中のアカウント作成（F02）や初期ロードで起きたエラーを画面に出す
        // （eval-4.md [2] の修正）。失敗しても `isCompleting` が `defer` でリセットされるため
        // ボタンが押せる状態に戻るが、押すまで何が起きているか分からなかったので、
        // 受け入れ条件7「失敗したことが画面上に表示され、同じ操作をもう一度試せる」を
        // アカウント作成そのものに対しても成立させる。
        // `OnboardingView` は `screen == .onboarding` の間だけ表示されるので、
        // `TodayPromptView` / `TimelineView` の `.alert` とは同時に立ち上がらない
        // （`RootView` の `Group` で排他に表示される）。
        .alert(
            L10n.Onboarding.genericErrorTitle,
            isPresented: Binding(
                get: { session.alertMessage != nil },
                set: { if !$0 { session.alertMessage = nil } }
            )
        ) {
            Button(L10n.Common.ok, role: .cancel) { session.alertMessage = nil }
        } message: {
            Text(session.alertMessage ?? "")
        }
    }

    // MARK: ヘッダー

    private var header: some View {
        HStack {
            if step != .concept {
                Button(L10n.Common.back) { back() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("onboarding.back")
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.hairline)
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            // 左右の重みを揃えるためのダミー
            Text(L10n.Common.back).font(.system(size: 15, weight: .medium)).opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: 各ステップ

    @ViewBuilder
    private var content: some View {
        switch step {
        case .concept: conceptStep
        case .terms: termsStep
        case .emoji: emojiStep
        case .nickname: nicknameStep
        case .notification: notificationStep
        }
    }

    private var conceptStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle(L10n.Onboarding.conceptTitle)
            VStack(alignment: .leading, spacing: 18) {
                conceptRow("🌍", L10n.Onboarding.conceptE1)
                conceptRow("✍️", L10n.Onboarding.conceptE2)
                conceptRow("👋", L10n.Onboarding.conceptE3)
                // 🌫️（U+1F32B + FE0F）は端末のフォントに無く、実機で豆腐（□）になる。
                // `TimelineView.endState` にも同じ注意書きがあるのにここだけ残っていた。
                // オンボーディングはレビュアーが最初に見る画面なので、単一コードポイントで
                // 確実に描画される絵文字にする。
                conceptRow("🍃", L10n.Onboarding.conceptE4)
            }
            .padding(20)
            .cardBackground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func conceptRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 22))
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(L10n.Onboarding.termsTitle)
            legalCard(title: L10n.Onboarding.termsBody, body: LegalText.terms)
            legalCard(title: L10n.Onboarding.privacyBody, body: LegalText.privacy)

            // ゼロトレランス条項の要約（F52）。規約本文は高さ150ptのスクロール
            // ボックスなので、条文の中だけに置くとスクロールされず読まれない。
            // 同意欄のすぐ上に常時出して、必ず目に入るようにする。
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
            .accessibilityIdentifier("onboarding.terms.zeroTolerance")

            Button {
                agreedToTerms.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(agreedToTerms ? Theme.accent : Theme.inkTertiary)
                    Text(L10n.Onboarding.agreeLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .cardBackground(cornerRadius: 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.terms.agree")
            .accessibilityAddTraits(agreedToTerms ? [.isSelected] : [])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
            .frame(height: 150)
            .cardBackground(cornerRadius: 16)
        }
    }

    private var emojiStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(L10n.Onboarding.emojiTitle)
            Text(L10n.Onboarding.emojiDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(EmojiCatalog.all, id: \.self) { emoji in
                    Button {
                        selectedEmoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.system(size: 26))
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selectedEmoji == emoji ? Theme.accent.opacity(0.16) : Theme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selectedEmoji == emoji ? Theme.accent : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.emoji.\(emoji)")
                    .accessibilityLabel(Text(L10n.Onboarding.emojiAccessibility(emoji)))
                    .accessibilityAddTraits(selectedEmoji == emoji ? [.isSelected] : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(L10n.Onboarding.nicknameTitle)
            Text(L10n.Onboarding.nicknameDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)

            HStack(spacing: 12) {
                Text(selectedEmoji ?? "🙂").font(.system(size: 28))
                TextField(L10n.Onboarding.nicknamePlaceholder, text: $nickname)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNicknameFocused)
                    .onSubmit { isNicknameFocused = false }
                    .accessibilityIdentifier("onboarding.nickname")
            }
            .padding(16)
            .cardBackground(cornerRadius: 16)

            Text(L10n.Onboarding.nicknamePrivacyNote)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(L10n.Onboarding.notificationTitle)
            Text(L10n.Onboarding.notificationDescription)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("🔔").font(.system(size: 40))
                Text(L10n.Onboarding.notificationFootnote)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: フッター

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            if let hint = blockingHint {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkTertiary)
            }

            if step == .notification {
                Button(L10n.Onboarding.allowNotifications) {
                    Task { await complete(requestNotifications: true) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isCompleting)
                .accessibilityIdentifier("onboarding.notification.allow")

                Button(L10n.Onboarding.later) {
                    Task { await complete(requestNotifications: false) }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isCompleting)
                .accessibilityIdentifier("onboarding.notification.later")
            } else {
                Button(L10n.Common.next) { advance() }
                    .buttonStyle(PrimaryButtonStyle(enabled: canProceed))
                    .disabled(!canProceed)
                    .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var blockingHint: String? {
        switch step {
        case .terms where !agreedToTerms:
            return L10n.Onboarding.hintAgree
        case .emoji where selectedEmoji == nil:
            return L10n.Onboarding.hintPickEmoji
        default:
            return nil
        }
    }

    private var canProceed: Bool {
        switch step {
        case .concept: return true
        case .terms: return agreedToTerms
        case .emoji: return selectedEmoji != nil
        case .nickname: return true
        case .notification: return true
        }
    }

    // MARK: 遷移

    private func advance() {
        guard canProceed else { return }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        // キーボードを出したまま次のステップへ行くと、下のボタンが隠れたままになる。
        isNicknameFocused = false
        step = next
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        isNicknameFocused = false
        step = previous
    }

    private func complete(requestNotifications: Bool) async {
        isNicknameFocused = false
        guard let emoji = selectedEmoji, agreedToTerms, !isCompleting else { return }
        isCompleting = true
        defer { isCompleting = false }
        if requestNotifications {
            await NotificationPermission.request()
        }
        await session.completeOnboarding(emoji: emoji, nickname: nickname)
    }
}
