import SwiftUI

/// お題待ち画面（F08）。
///
/// 有効なお題が無い時間帯に出る。ここには
/// 回答入力欄・世界タイムラインへの導線・過去のお題や自分の投稿の履歴を**一切置かない**。
/// 次のお題の開始時刻も出さない（「いつ来るか分からない」というリズムを壊さないため）。
struct WaitingPromptView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ZStack {
            Theme.canvas

            VStack(spacing: 0) {
                // 設定ボタンは `waiting.identity` の外に置く（中に入れると識別子が上書きされる）。
                HStack(spacing: 0) {
                    identityRow
                    SettingsEntryButton()
                    PlusEntryButton()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 16) {
                    Text("🌙")
                        .font(.system(size: 44))
                    Text(L10n.Waiting.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("waiting.title")
                    Text(L10n.Waiting.body)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("waiting.description")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 28)
                .cardBackground()
                .padding(.horizontal, 24)

                Spacer()

                Text(L10n.Waiting.footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.bottom, 32)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("waiting.root")
    }

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
        .accessibilityIdentifier("waiting.identity")
    }
}
