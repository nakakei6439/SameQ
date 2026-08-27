import SwiftUI

/// プロフィール編集シート（F32）。
///
/// 初回設定の `OnboardingView.emojiStep` / `nicknameStep` とほぼ同じ UI を
/// 「あとから変更」用に再利用する。`Session` 経由で `AppSession.updateProfile(_:)`
/// を呼び、成功したらシートを閉じる。
struct ProfileEditView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// シートを開いた時点の絵文字・ニックネーム。キャンセル時に元の値へ戻せるように保持。
    let initialEmoji: String
    let initialNickname: String

    @State private var selectedEmoji: String
    @State private var nickname: String
    @State private var isSaving = false
    @FocusState private var isNicknameFocused: Bool

    init(initialEmoji: String, initialNickname: String) {
        self.initialEmoji = initialEmoji
        self.initialNickname = initialNickname
        _selectedEmoji = State(initialValue: initialEmoji)
        _nickname = State(initialValue: initialNickname)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.Settings.profileEditEmojiTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                        spacing: 10
                    ) {
                        ForEach(EmojiCatalog.all, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selectedEmoji == emoji ? Theme.accent.opacity(0.16) : Theme.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(selectedEmoji == emoji ? Theme.accent : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.profile.emoji.\(emoji)")
                            .accessibilityLabel(Text(L10n.Onboarding.emojiAccessibility(emoji)))
                            .accessibilityAddTraits(selectedEmoji == emoji ? [.isSelected] : [])
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.profileEditNicknameLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        HStack(spacing: 12) {
                            Text(selectedEmoji).font(.system(size: 24))
                            TextField(L10n.Settings.profileEditNicknamePlaceholder, text: $nickname)
                                .font(.system(size: 16))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isNicknameFocused)
                                .onSubmit { isNicknameFocused = false }
                                .accessibilityIdentifier("settings.profile.nickname.field")
                        }
                        .padding(14)
                        .cardBackground(cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background { Theme.canvas }
            .navigationTitle(L10n.Settings.profileEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.profile.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.save) {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("settings.profile.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.Common.done) { isNicknameFocused = false }
                        .accessibilityIdentifier("settings.profile.keyboard.done")
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let success = await session.updateProfile(emoji: selectedEmoji, nickname: nickname)
        if success {
            dismiss()
        }
    }
}
