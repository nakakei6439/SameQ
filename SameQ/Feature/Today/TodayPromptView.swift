import SwiftUI

/// 今日のお題画面（F03 / F04 / F05）。
///
/// 未回答のときは入力欄とロック表示だけを置き、世界タイムラインへの導線を一切出さない。
/// 回答済みのときは自分の回答と、タイムラインを開くボタンを出す。
struct TodayPromptView: View {
    @Environment(AppSession.self) private var session
    @State private var draft: String = ""
    @FocusState private var isEditorFocused: Bool

    private var characterLimit: Int { LocalBackend.bodyCharacterLimit }

    var body: some View {
        @Bindable var session = session

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerRow
                promptCard

                if let myPost = session.myPost {
                    answeredSection(myPost: myPost)
                } else {
                    composer
                    lockedNotice
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background { Theme.canvas }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: session.prompt?.id) { _, _ in
            // お題が新しくなったら書きかけは持ち越さない（前のお題の言葉は消える）。
            draft = ""
            isEditorFocused = false
        }
        .alert(
            "うまくいきませんでした",
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

    // MARK: パーツ

    private var identityRow: some View {
        HStack(spacing: 10) {
            Text(session.user?.emoji ?? "🙂").font(.system(size: 24))
            if let nickname = session.user?.displayNickname {
                Text(nickname)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
        }
        .accessibilityIdentifier("today.identity")
    }

    /// 自分の絵文字・ニックネームと、設定への入り口（F15 のブロック管理はここから）。
    /// 設定ボタンは `today.identity` の外に置く。中に入れると識別子が上書きされてしまう。
    private var headerRow: some View {
        HStack(spacing: 0) {
            identityRow
            SettingsEntryButton()
        }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日のお題")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
            Text(session.prompt?.text ?? "")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.promptText")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("あなたの言葉で答えてみてください")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkTertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 150)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .focused($isEditorFocused)
                    .accessibilityIdentifier("today.input")
                    .onChange(of: draft) { _, newValue in
                        if newValue.count > characterLimit {
                            draft = String(newValue.prefix(characterLimit))
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("完了") { isEditorFocused = false }
                                .accessibilityIdentifier("today.doneEditing")
                        }
                    }
            }
            .cardBackground(cornerRadius: 18)

            HStack {
                Text("1つのお題に答えられるのは1回だけです")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                Spacer()
                Text("\(draft.count)/\(characterLimit)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(draft.count >= characterLimit ? Theme.like : Theme.inkSecondary)
                    .accessibilityIdentifier("today.counter")
            }

            Button(session.isSubmitting ? "送信中…" : "投稿する") {
                isEditorFocused = false
                let body = draft
                Task { await session.submit(body: body) }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
            .disabled(!canSubmit)
            .accessibilityIdentifier("today.submit")
        }
    }

    private var canSubmit: Bool {
        !session.isSubmitting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 未回答のあいだのロック表示（F05）。ここから先へ進むボタンは置かない。
    private var lockedNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.inkTertiary)
            Text("世界の回答はまだ見られません")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text("あなたが答えると、知らない誰かの言葉が1件ずつ見えるようになります。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.hairline.opacity(0.35))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.locked")
    }

    private func answeredSection(myPost: Post) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("あなたの回答")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .tracking(1)
                Text(myPost.body)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.myAnswer")
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()

            Button("世界の回答を読む") {
                Task { await session.openTimeline() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("today.openTimeline")
        }
    }
}
