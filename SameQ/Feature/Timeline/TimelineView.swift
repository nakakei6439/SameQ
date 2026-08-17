import SwiftUI

/// 世界タイムライン（F06 / F11 / F12）。
///
/// 表示するのは常に1件だけ。次の1件は `AppSession.advanceTimeline()` が
/// 「同一お題／自分以外／期限内／未読」からランダムに引いてくる。
/// 手元に配列を持たないので、前の回答へ戻る操作は原理的に作れない（置いた前提5）。
struct TimelineView: View {
    @Environment(AppSession.self) private var session

    @State private var dragOffset: CGSize = .zero
    @State private var isAdvancing = false
    /// 通報・ブロックの操作シートに渡す回答（F13 / F14）。nil のあいだシートは出ない。
    @State private var safetyTarget: Post?

    var body: some View {
        VStack(spacing: 0) {
            topBar

            switch session.timelineContent {
            case .loading:
                loadingState
            case .post(let post):
                cardStack(post: post)
                actionBar(post: post)
            case .empty:
                endState(
                    symbol: "🫧",
                    title: "まだ誰も答えていません",
                    detail: "世界の誰かが答えると、ここに1件ずつ出てきます。",
                    identifier: "timeline.empty"
                )
            case .exhausted:
                endState(
                    // 🌫️ はシミュレータのフォントで欠け表示になるので使わない
                    symbol: "☁️",
                    title: "今は新しい回答がありません",
                    detail: "このお題の回答はすべて読みました。読んだ言葉は、しばらくすると消えます。",
                    identifier: "timeline.exhausted"
                )
            }
        }
        .background { Theme.canvas }
        .sheet(item: $safetyTarget) { post in
            SafetySheetView(post: post)
                .fontDesign(.rounded)
                .environment(session)
        }
        // いいね・通報の連打制限（F17）など、タイムライン上の操作で起きたエラーをここに出す。
        // 閉じてもタイムラインの位置はそのまま（操作不能にならない）。
        // `TodayPromptView` も裏で生きていて同じ `alertMessage` を見ているので、
        // タイムライン表示中はこちらだけが `isPresented` になるようにする
        // （両方が同時に立つと、提示の競合でタイムラインごと閉じてしまうことがある）。
        .alert(
            "うまくいきませんでした / Something went wrong",
            isPresented: Binding(
                get: { session.alertMessage != nil && session.isTimelinePresented },
                set: { if !$0 { session.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { session.alertMessage = nil }
        } message: {
            Text(session.alertMessage ?? "")
        }
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

            // 通報・ブロック（F13 / F14）。回答が出ているときだけ押せる。
            // 出ていないときも同じ幅を占めて、中央の見出しがずれないようにする。
            Button {
                safetyTarget = session.timelineContent.post
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 64, height: 32, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(session.timelineContent.post == nil ? 0 : 1)
            .disabled(session.timelineContent.post == nil)
            .accessibilityIdentifier("timeline.more")
            .accessibilityLabel(Text("この回答を通報またはブロック"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .tint(Theme.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("timeline.loading")
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
    /// 「前へ」は置かない（置いた前提5）。通報・ブロックは上部の ⋯ から。
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

    /// 読み切ったとき／1件も無いときの明示表示。
    /// どちらも `timeline.end` を持たせ、内訳は `identifier` で見分ける。
    private func endState(
        symbol: String,
        title: String,
        detail: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Text(symbol)
                .font(.system(size: 40))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier(identifier)
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Spacer()
            Button("閉じる") { session.closeTimeline() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 空振りのスワイプでも壊れないよう、ここでもジェスチャを受けて何もしない。
        .contentShape(Rectangle())
        .gesture(DragGesture().onEnded { _ in })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.end")
    }

    // MARK: 遷移（進むのみ）

    private func advance(towards translation: CGSize) {
        guard !isAdvancing, session.timelineContent.post != nil else { return }
        isAdvancing = true
        let horizontal: CGFloat = translation.width >= 0 ? 700 : -700
        let vertical = translation.height * 2
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: horizontal, height: vertical)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            await session.advanceTimeline()
            dragOffset = .zero
            isAdvancing = false
        }
    }
}
