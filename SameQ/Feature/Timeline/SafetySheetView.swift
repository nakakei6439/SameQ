import SwiftUI

/// 通報とブロック（F13 / F14）の操作シート。
///
/// 回答の下にある「通報・ブロック」（`Timeline.moreLabel`）から開く。1枚のシートの中で
/// 「何をするか」→「理由を選ぶ／確認する」→「完了」まで進む。
/// 送信・ブロックはその場でデータ層に反映し、同時に裏のタイムラインを次の回答へ進める。
/// そのため閉じたときには、通報した回答もブロックした人の回答も、もう出ていない。
///
/// 相手に伝わるものはここでは何も作らない。文言でも「相手には通知されません」と明示する。
struct SafetySheetView: View {
    let post: Post

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case menu
        case reasons
        case blockConfirm
        case reportDone
        case blockDone
    }

    @State private var stage: Stage = .menu
    @State private var selectedReason: ReportReason?
    @State private var isSending = false
    @State private var detent: PresentationDetent = .medium

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .menu: menu
            case .reasons: reasons
            case .blockConfirm: blockConfirm
            case .reportDone:
                done(
                    symbol: "checkmark.circle.fill",
                    title: L10n.Safety.reportDoneTitle,
                    detail: L10n.Safety.reportDoneBody,
                    identifier: "safety.reportDone"
                )
            case .blockDone:
                done(
                    symbol: "checkmark.circle.fill",
                    title: L10n.Safety.blockDoneTitle,
                    detail: L10n.Safety.blockDoneBody,
                    identifier: "safety.blockDone"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { Theme.canvas }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // `children: .contain` を付けないと、この識別子が中のボタンにまで伝播して
        // それぞれの識別子を上書きしてしまう。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safety.sheet")
    }

    // MARK: 何をするか

    private var menu: some View {
        VStack(spacing: 14) {
            header(title: L10n.Safety.menuHeader, detail: L10n.Safety.menuHeaderDetail)

            actionRow(
                symbol: "flag",
                title: L10n.Safety.reportAction,
                detail: L10n.Safety.reportActionDetail,
                identifier: "safety.report"
            ) {
                selectedReason = nil
                detent = .large
                stage = .reasons
            }

            actionRow(
                symbol: "hand.raised",
                title: L10n.Safety.blockAction,
                detail: L10n.Safety.blockActionDetail,
                identifier: "safety.block"
            ) {
                stage = .blockConfirm
            }

            Spacer(minLength: 0)
            cancelButton(title: L10n.Common.cancel)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    // MARK: 通報の理由

    private var reasons: some View {
        VStack(spacing: 12) {
            header(title: L10n.Safety.reasonsTitle, detail: L10n.Safety.reasonsDetail)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(ReportReason.allCases) { reason in
                        reasonRow(reason)
                    }
                }
                .padding(.vertical, 2)
            }

            Button(isSending ? L10n.Common.submitting : L10n.Common.submit) {
                guard let selectedReason, !isSending else { return }
                isSending = true
                Task {
                    let sent = await session.report(postID: post.id, reason: selectedReason)
                    isSending = false
                    if sent {
                        detent = .medium
                        stage = .reportDone
                    } else {
                        dismiss()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: canSend))
            .disabled(!canSend)
            .accessibilityIdentifier("safety.reportSubmit")

            cancelButton(title: L10n.Common.stop)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    private var canSend: Bool { selectedReason != nil && !isSending }

    private func reasonRow(_ reason: ReportReason) -> some View {
        let isSelected = selectedReason == reason
        return Button {
            selectedReason = reason
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkTertiary)
                Text(reason.label)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("safety.reason.\(reason.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: ブロックの確認

    private var blockConfirm: some View {
        VStack(spacing: 14) {
            header(
                title: L10n.Safety.blockConfirmTitle,
                detail: L10n.Safety.blockConfirmDetail
            )

            Spacer(minLength: 0)

            Button(isSending ? L10n.Common.processing : L10n.Safety.blockConfirmAction) {
                guard !isSending else { return }
                isSending = true
                Task {
                    let blocked = await session.block(post: post)
                    isSending = false
                    if blocked {
                        stage = .blockDone
                    } else {
                        dismiss()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(enabled: !isSending))
            .disabled(isSending)
            .accessibilityIdentifier("safety.blockConfirm")

            cancelButton(title: L10n.Common.stop)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    // MARK: 完了

    private func done(symbol: String, title: String, detail: String, identifier: String) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier(identifier)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(L10n.Common.close) { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("safety.close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    // MARK: パーツ

    private func header(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func actionRow(
        symbol: String,
        title: String,
        detail: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func cancelButton(title: String) -> some View {
        Button(title) { dismiss() }
            .buttonStyle(QuietButtonStyle())
            .padding(.top, 4)
            .accessibilityIdentifier("safety.cancel")
    }
}
