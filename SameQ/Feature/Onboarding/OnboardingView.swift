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
            "うまくいきませんでした / Something went wrong",
            isPresented: Binding(
                get: { session.alertMessage != nil },
                set: { if !$0 { session.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.alertMessage = nil }
        } message: {
            Text(session.alertMessage ?? "")
        }
    }

    // MARK: ヘッダー

    private var header: some View {
        HStack {
            if step != .concept {
                Button("戻る") { back() }
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
            Text("戻る").font(.system(size: 15, weight: .medium)).opacity(0)
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
            stepTitle("同じ問いに、\n答えるだけ。")
            VStack(alignment: .leading, spacing: 18) {
                conceptRow("🌍", "1日1回、世界共通のお題が届きます。いつ届くかは分かりません。")
                conceptRow("✍️", "あなたが答えて初めて、世界の誰かの答えが見えるようになります。")
                conceptRow("👋", "フォローも検索もランキングもありません。いいねを押して、次へ進むだけ。")
                conceptRow("🌫️", "その日の言葉は、しばらくすると消えます。")
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
            stepTitle("はじめる前に")
            legalCard(title: "利用規約", body: LegalText.terms)
            legalCard(title: "プライバシーポリシー", body: LegalText.privacy)

            Button {
                agreedToTerms.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(agreedToTerms ? Theme.accent : Theme.inkTertiary)
                    Text("利用規約とプライバシーポリシーに同意します")
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
            stepTitle("あなたの印を\n1つ選んでください")
            Text("世界の誰かには、この絵文字だけが見えます。あとから変えられます。")
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
                    .accessibilityLabel(Text("絵文字 \(emoji)"))
                    .accessibilityAddTraits(selectedEmoji == emoji ? [.isSelected] : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nicknameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("呼び名を\n決めますか？")
            Text("空のままでも進めます。未設定のときは絵文字だけが表示されます。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)

            HStack(spacing: 12) {
                Text(selectedEmoji ?? "🙂").font(.system(size: 28))
                TextField("ニックネーム（任意）", text: $nickname)
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

            Text("本名は書かないでください。国や言語が分からないことが、このアプリの前提です。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("お題が届いたら\nお知らせします")
            Text("通知は1日1回だけ。届く時刻は毎日変わります。あとで設定から変えられます。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("🔔").font(.system(size: 40))
                Text("通知を切っていても、アプリを開けばその日のお題に答えられます。")
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
                Button("通知を許可する") {
                    Task { await complete(requestNotifications: true) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isCompleting)
                .accessibilityIdentifier("onboarding.notification.allow")

                Button("あとで設定する") {
                    Task { await complete(requestNotifications: false) }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isCompleting)
                .accessibilityIdentifier("onboarding.notification.later")
            } else {
                Button("次へ") { advance() }
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
            return "同意すると次へ進めます"
        case .emoji where selectedEmoji == nil:
            return "絵文字を1つ選んでください"
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
