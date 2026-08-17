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
                identityRow
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer()

                VStack(spacing: 16) {
                    Text("🌙")
                        .font(.system(size: 44))
                    Text("いまはお題がありません")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("waiting.title")
                    Text("次のお題が届くまで、少し待ってください。\n始まったら、この画面から答えられます。")
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

                Text("その日の言葉は、その日のうちに消えます。")
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
