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
            promptStrip

            switch session.timelineContent {
            case .loading:
                loadingState
            case .post(let post):
                cardStack(post: post)
                actionBar(post: post)
            case .empty:
                endState(
                    symbol: "🫧",
                    title: L10n.Timeline.emptyTitle,
                    detail: L10n.Timeline.emptyBody,
                    identifier: "timeline.empty"
                )
            case .exhausted:
                endState(
                    // 🌫️ はシミュレータのフォントで欠け表示になるので使わない
                    symbol: "☁️",
                    title: L10n.Timeline.exhaustedTitle,
                    detail: L10n.Timeline.exhaustedBody,
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
            L10n.Onboarding.genericErrorTitle,
            isPresented: Binding(
                get: { session.alertMessage != nil && session.isTimelinePresented },
                set: { if !$0 { session.alertMessage = nil } }
            )
        ) {
            Button(L10n.Common.ok, role: .cancel) { session.alertMessage = nil }
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
                    Text(L10n.Common.close)
                }
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityIdentifier("timeline.close")

            Spacer()

            Text(L10n.Timeline.title)
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
            .accessibilityLabel(Text(L10n.Timeline.moreAccessibility))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// 今日のお題を、タイムライン閲覧中も上部に小さく常設表示する（並行タスク：UI調整）。
    /// 翻訳が確定するまでの「準備中…」の作法は `TodayPromptView.promptCard` に揃える。
    private var promptStrip: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L10n.Timeline.promptLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.top, 1)

            if let text = session.promptDisplayText {
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timeline.promptText")
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(Theme.inkSecondary)
                    Text(L10n.Common.loading)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .accessibilityIdentifier("timeline.promptLoading")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.hairline.opacity(0.35))
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.prompt")
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
            AnswerCardView(
                post: post,
                // 自分のニックネームは原文のまま表示する（受け入れ条件5）。
                // それ以外は transliterator を通した表示名（受け入れ条件1）。
                displayedNickname: post.displayedNickname(
                    transliterator: session.nicknameTransliterator,
                    isOwn: post.authorID == session.user?.id
                ),
                // 無料ユーザーの上限（140 文字）を境界として長文を折り畳む（F29）。
                // Plus ユーザーであっても、表示上の折り畳みは同じ 140 文字でよい
                // （受け手側の画面では Free / Plus 関係なく同じ動作にする＝「閲覧に
                // 課金制限がかからない」方針を保つ）。
                previewLimit: LocalBackend.bodyCharacterLimit
            )
                .padding(.horizontal, 20)
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 32)))
                .id(post.id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // カード本体だけでなく、お題表示〜いいねボタンに挟まれた余白全体でもスワイプを
        // 受け取れるようにする（カードの上下に生まれる空白ではジェスチャが効かなかった不具合の修正）。
        .contentShape(Rectangle())
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
    }

    /// カードの下の操作。いいねだけ（並行タスク：UI調整で✕「次の人へ」ボタンを撤去）。
    /// 次の人へ進む操作はスワイプのみになったので、その導線を文言で示す。
    /// 「前へ」は置かない（置いた前提5）。通報・ブロックは上部の ⋯ から。
    private func actionBar(post: Post) -> some View {
        let isLiked = session.isLiked(post.id)
        return VStack(spacing: 10) {
            Button {
                Task { await session.toggleLike(postID: post.id) }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(isLiked ? Color.white : Theme.like)
                    .frame(width: 82, height: 82)
                    .background(
                        Circle()
                            .fill(isLiked ? Theme.like : Theme.surface)
                            .overlay(
                                Circle()
                                    .strokeBorder(Theme.like.opacity(isLiked ? 0 : 0.4), lineWidth: 2)
                            )
                            .shadow(
                                color: Theme.like.opacity(isLiked ? 0.35 : 0.08),
                                radius: isLiked ? 16 : 10,
                                x: 0,
                                y: 6
                            )
                    )
                    .scaleEffect(isLiked ? 1.06 : 1.0)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isLiked)
            .accessibilityIdentifier("timeline.like")
            .accessibilityLabel(Text(isLiked ? L10n.Timeline.liked : L10n.Timeline.like))
            .accessibilityAddTraits(isLiked ? [.isSelected] : [])

            Text(isLiked ? L10n.Timeline.likedStatus : L10n.Timeline.like)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isLiked ? Theme.like : Theme.inkTertiary)

            Text(L10n.Timeline.swipeHint)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 4)
        }
        .padding(.top, 10)
        .padding(.bottom, 28)
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
            Button(L10n.Common.close) { session.closeTimeline() }
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
