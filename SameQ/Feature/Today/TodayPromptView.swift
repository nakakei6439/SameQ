import SwiftUI

/// 今日のお題画面（F03 / F04 / F05）。
///
/// 未回答のときは入力欄とロック表示だけを置き、世界タイムラインへの導線を一切出さない。
/// 回答済みのときは自分の回答と、タイムラインを開くボタンを出す。
///
/// **Plus 対応（スプリント10 / F28 / F29 / F30）**:
/// - 文字数上限を `session.isPlus` によって切り替える（140 ⇄ 2000）
/// - Plus のときは装飾ピッカー（`PlusDecorationPicker`）を composer の下に出す
/// - 入力欄の最大高さを Plus のとき自動で伸ばす（長文が打ちやすいように）
struct TodayPromptView: View {
    @Environment(AppSession.self) private var session
    @State private var draft: String = ""
    @FocusState private var isEditorFocused: Bool

    /// 現在のモードに応じた文字数上限（F04 / F29）。
    /// `session.isPlus` が変わったら即座に反映する（購入直後の再 compose に対応）。
    private var characterLimit: Int {
        LocalBackend.bodyCharacterLimit(isPlus: session.isPlus)
    }

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
                    if session.isPlus {
                        PlusDecorationPicker()
                    }
                    lockedNotice
                }

                if !session.isPlus {
                    plusHint
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
            session.clearPendingDecorations()
        }
        // タイムラインは `fullScreenCover` で重ねているだけで、この画面は裏で生き続けている。
        // タイムライン表示中は `TimelineView` 側の `.alert` にだけ出す
        // （両方が同時に `isPresented` になると、片方の提示がもう片方の提示を巻き込んで
        // タイムラインごと閉じてしまうことがあるため、必ずどちらか一方だけにする）。
        .alert(
            L10n.Onboarding.genericErrorTitle,
            isPresented: Binding(
                get: { session.alertMessage != nil && !session.isTimelinePresented },
                set: { if !$0 { session.alertMessage = nil } }
            )
        ) {
            Button(L10n.Common.ok, role: .cancel) { session.alertMessage = nil }
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
            PlusEntryButton()
        }
    }

    /// お題本文は端末言語への翻訳が終わるまで表示しない（F22）。
    /// 原文をいったん出してから翻訳済みの文章に差し替える「ちらつき」を避けるため、
    /// 準備中は代わりにローディング表示を出す（F21）。
    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Today.promptLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
            if let text = session.promptDisplayText {
                Text(text)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.promptText")
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Theme.inkSecondary)
                    Text(L10n.Common.loading)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .accessibilityIdentifier("today.promptLoading")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(L10n.Today.composerPlaceholder)
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
                    .frame(height: composerHeight)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .focused($isEditorFocused)
                    .accessibilityIdentifier("today.input")
                    .onChange(of: draft) { _, newValue in
                        if newValue.count > characterLimit {
                            // 受け入れ条件1: 140文字（無料）/ 2000文字（Plus）を超える入力は
                            // ここで止まる。Plus のときは 2000 文字まで打てる。
                            draft = String(newValue.prefix(characterLimit))
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button(L10n.Common.done) { isEditorFocused = false }
                                .accessibilityIdentifier("today.doneEditing")
                        }
                    }
            }
            .cardBackground(cornerRadius: 18)

            HStack {
                Text(messageText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                Spacer()
                Text("\(draft.count)/\(characterLimit)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(draft.count >= characterLimit ? Theme.like : Theme.inkSecondary)
                    .accessibilityIdentifier("today.counter")
            }

            Button(session.isSubmitting ? L10n.Today.submittingButton : L10n.Today.submitButton) {
                isEditorFocused = false
                let body = draft
                Task { await session.submit(body: body) }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canSubmit))
            .disabled(!canSubmit)
            .accessibilityIdentifier("today.submit")
        }
    }

    /// Plus のときは高さを広げて、長文が打ちやすいように調整する（F29）。
    private var composerHeight: CGFloat {
        session.isPlus ? 240 : 150
    }

    /// 1お題1投稿の説明と、Plus モードの案内（無料ユーザーだけ）。
    private var messageText: String {
        if session.isPlus {
            return L10n.Today.oneAnswerPerPromptPlus
        }
        return L10n.Today.oneAnswerPerPrompt
    }

    /// ボタンの有効条件は「何か入力されているか」だけにする（trim 後の判定にしない）。
    /// 空白・改行だけの入力もボタンを押せる状態にして、`submitPost` 側の `emptyBody` チェックまで
    /// 届かせる。そうしないとボタンが灰色になるだけで拒否メッセージが一切出せない
    /// （スプリント05 evaluator 指摘、eval-1.md [1]）。
    private var canSubmit: Bool {
        !session.isSubmitting && !draft.isEmpty
    }

    /// 未回答のあいだのロック表示（F05）。ここから先へ進むボタンは置かない。
    private var lockedNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.inkTertiary)
            Text(L10n.Today.lockedTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(L10n.Today.lockedBody)
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
                Text(L10n.Today.yourAnswer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .tracking(1)
                Text(myPost.body)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.myAnswer")
                // 受信いいね数（F35・受け入れ条件3）。0 のときは刺激が強いので出さない。
                if session.receivedLikeCount > 0 {
                    Text(L10n.Today.receivedLikesCount(session.receivedLikeCount))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.like)
                        .padding(.top, 4)
                        .accessibilityIdentifier("today.receivedLikes")
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()

            // モデル未ダウンロードの言語をダウンロードしている間は「準備中…」にして
            // 連打を防ぐ（受け入れ条件4・attempt 5）。1件もダウンロードが要らなければ
            // 一瞬も表示されず、いつもどおりすぐタイムラインが開く。
            Button(session.isPreparingTimeline ? L10n.Today.preparingTimeline : L10n.Today.openTimeline) {
                Task { await session.openTimeline() }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !session.isPreparingTimeline))
            .disabled(session.isPreparingTimeline)
            .accessibilityIdentifier("today.openTimeline")
        }
    }

    /// 無料ユーザー向け Plus の案内（F28）。強制ではなく「あってもいいかも」程度の小さなカード。
    private var plusHint: some View {
        Button {
            session.isPlusViewPresented = true
        } label: {
            HStack(spacing: 10) {
                Text("✨").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Today.plusHintTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(L10n.Today.plusHintBody)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.plusHint")
    }
}

/// Plus 画面の入り口（スプリント10 / F28）。
/// 設定ボタン（F15）の右にそっと置く。「Plus」の文字を直接出さず、控えめな星マークで
/// 察せる形にして、無料ユーザーの画面を圧迫しない。
struct PlusEntryButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            session.isPlusViewPresented = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(session.isPlus ? Theme.accent : Theme.inkSecondary)
                if session.isPlus {
                    Text("Plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(minWidth: 32, minHeight: 32)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plus.open")
        .accessibilityLabel(Text(session.isPlus ? L10n.Today.plusEntryLabelActive : L10n.Today.plusEntryLabelInactive))
    }
}
