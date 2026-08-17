import SwiftUI

/// 世界タイムラインの1枚のカード（F06）。
///
/// 出す情報は「絵文字・（あれば）ニックネーム・本文」だけ。
/// 国・言語・投稿時刻・いいね数は出さない（ランキング化と属性推測を避けるため）。
/// 操作（次へ／いいね）はカードの外に置く。
struct AnswerCardView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(post.authorEmoji)
                    .font(.system(size: 30))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.background))
                    .accessibilityIdentifier("timeline.card.emoji")
                if let nickname = post.displayNickname {
                    Text(nickname)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("timeline.card.nickname")
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 22)

            Text(post.body)
                .font(.system(size: 21, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("timeline.card.body")
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .cardBackground()
    }
}
