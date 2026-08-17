import SwiftUI

/// 世界タイムライン（F06）。
///
/// 回答を1件ずつ表示し、スワイプで次へ進む。前の回答へは戻れない。
/// 表示するのは `AppSession.timelinePosts`（自分以外の回答）だけ。
struct TimelineView: View {
    @Environment(AppSession.self) private var session

    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isAdvancing = false

    private var posts: [Post] { session.timelinePosts }
    private var currentPost: Post? { index < posts.count ? posts[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let post = currentPost {
                cardStack(post: post)
                actionBar(post: post)
            } else {
                endState
            }
        }
        .background { Theme.canvas }
    }

    // MARK: パーツ

    private var topBar: some View {
        HStack {
            Button {
                session.closeTimeline()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                    Text("閉じる")
                }
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("timeline.close")

            Spacer()

            Text("世界の回答")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)

            Spacer()

            // 左右の重みを揃えるためのダミー
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                Text("閉じる")
            }
            .font(.system(size: 15, weight: .medium))
            .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func cardStack(post: Post) -> some View {
        ZStack {
            AnswerCardView(post: post)
                .padding(.horizontal, 20)
            .offset(dragOffset)
            .rotationEffect(.degrees(Double(dragOffset.width / 32)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isAdvancing else { return }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isAdvancing else { return }
                        let distance = max(abs(value.translation.width), abs(value.translation.height))
                        if distance > 70 {
                            advance(towards: value.translation)
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .id(post.id)
        }
        .frame(maxHeight: .infinity)
    }

    /// カードの下の操作。スキップ（次の人へ）といいねの2つだけ。
    /// 通報はスプリント04で足す。
    private func actionBar(post: Post) -> some View {
        let isLiked = session.isLiked(post.id)
        return VStack(spacing: 14) {
            HStack(spacing: 28) {
                circleButton(
                    systemName: "xmark",
                    tint: Theme.inkSecondary,
                    filled: false,
                    label: "次の人へ",
                    identifier: "timeline.next"
                ) {
                    advance(towards: CGSize(width: -1, height: 0))
                }

                circleButton(
                    systemName: isLiked ? "heart.fill" : "heart",
                    tint: Theme.like,
                    filled: isLiked,
                    label: isLiked ? "いいね済み" : "いいね",
                    identifier: "timeline.like",
                    isSelected: isLiked
                ) {
                    Task { await session.toggleLike(postID: post.id) }
                }
            }

            Text("スワイプすると、次の知らない誰かへ")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private func circleButton(
        systemName: String,
        tint: Color,
        filled: Bool,
        label: String,
        identifier: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: 62, height: 62)
                .background(
                    Circle()
                        .fill(filled ? tint : Theme.surface)
                        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var endState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("🌫️")
                .font(.system(size: 40))
            Text(posts.isEmpty ? "まだ誰も答えていません" : "今日はここまで")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("読んだ言葉は、しばらくすると消えます。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
            Button("閉じる") { session.closeTimeline() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.end")
    }

    // MARK: 遷移（進むのみ）

    private func advance(towards translation: CGSize) {
        guard !isAdvancing, index < posts.count else { return }
        isAdvancing = true
        let horizontal: CGFloat = translation.width >= 0 ? 700 : -700
        let vertical = translation.height * 2
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: horizontal, height: vertical)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            index += 1
            dragOffset = .zero
            isAdvancing = false
        }
    }
}
