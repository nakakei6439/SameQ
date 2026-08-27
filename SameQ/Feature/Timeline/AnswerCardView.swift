import SwiftUI

/// 世界タイムラインの1枚のカード（F06 / F29 / F30）。
///
/// 出す情報は「絵文字・（あれば）ニックネーム・本文」だけ。
/// 国・言語・投稿時刻・いいね数は出さない（ランキング化と属性推測を避けるため）。
/// 操作（次へ／いいね）はカードの外に置く。
///
/// **F23**: `displayedNickname` を受け取る。`TimelineView` が `session.nicknameTransliterator`
/// と `isOwn`（=自分の投稿かどうか）を判定してここへ渡すので、View 自体は transliterator を
/// 持たない。
///
/// **F29（長文）**: `body` が `previewLimit`（既定 140 文字）を超えるとき、先頭から
/// `previewLimit` 文字だけを出して「…続き」を出す。タップで全文に切り替わる。
/// 無料ユーザーでもこの折り畳みは同様に動く（受け入れ条件5）。
///
/// **F30（装飾）**: `decorations` を受け取り、`.emojiStamp` / `.bold` / `.italic` を
/// 本文に重ねて表示する。`.balloon` は本文の先頭にラベルを置き、本文の末尾に「」を
/// 仮想的に置いて、吹き出しらしい見た目を狙う（装飾非対応環境でも `body` 単独で読める）。
struct AnswerCardView: View {
    let post: Post
    let displayedNickname: String?
    /// 本文の折り畳み境界（プレビュー文字数）。`PostBodyInspector.isLongForm` と同じ値を
    /// 呼び出し元（`TimelineView`）から渡してもらう。
    let previewLimit: Int

    @State private var isExpanded: Bool = false

    /// 「…続き」/「閉じる」を出すか。折り畳み候補（長文）のときだけ。
    private var isLongForm: Bool {
        PostBodyInspector.isLongForm(post.body, limit: previewLimit)
    }

    /// いま画面に出す本文。展開時は全文、未展開時は先頭 `previewLimit` 文字まで。
    private var displayBody: String {
        isExpanded ? post.body : PostBodyInspector.previewBody(of: post.body, limit: previewLimit)
    }

    /// 装飾のうち本文に混ぜるもの（太字・斜体）。`.emojiStamp` と `.balloon` は
    /// 本文とは別置きなので、ここでは扱わない。
    private var inlineDecorations: [PostDecoration] {
        post.decorations.filter { $0.kind == .bold || $0.kind == .italic }
    }

    /// 末尾に置くスタンプ。1 件だけ採用（複数あっても先頭だけ。仕様の「絵文字スタンプ」は
    /// 1 投稿につき 1 つを想定したUI）。
    private var trailingStamp: PostDecoration? {
        post.decorations.first { $0.kind == .emojiStamp }
    }

    /// 吹き出し装飾（本文を囲むラベル）。複数ある場合は最初の 1 件。
    private var balloon: PostDecoration? {
        post.decorations.first { $0.kind == .balloon }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            contentBody
        }
        .padding(26)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .cardBackground()
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text(post.authorEmoji)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.background))
                .accessibilityIdentifier("timeline.card.emoji")
            if let nickname = displayedNickname {
                Text(nickname)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("timeline.card.nickname")
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 22)
    }

    /// 本文ブロック。装飾適用のありなしで 2 パターン。
    @ViewBuilder
    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let balloon, let label = balloon.value {
                balloonLabel(label)
            }
            if inlineDecorations.isEmpty {
                plainBody
            } else {
                decoratedBody
            }
            if let stamp = trailingStamp, let value = stamp.value {
                HStack(spacing: 4) {
                    Text(value).font(.system(size: 20))
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .accessibilityIdentifier("timeline.card.stamp")
            }
            if isLongForm {
                Button(action: toggleExpanded) {
                    Text(isExpanded ? L10n.Common.close : L10n.Common.readMore)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("timeline.card.toggleReadMore")
            }
        }
    }

    private func balloonLabel(_ label: String) -> some View {
        let openMark = L10n.useEnglish ? "\u{201C}" : "\u{300C}"
        let closeMark = L10n.useEnglish ? "\u{201D}" : "\u{300D}"
        return Text("\(openMark)\(label)\(closeMark)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Theme.background)
            )
            .accessibilityIdentifier("timeline.card.balloon")
    }

    private var plainBody: some View {
        Text(displayBody)
            .font(.system(size: 21, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.ink)
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.card.body")
    }

    /// 装飾（太字・斜体）が指定された箇所だけ `AttributedString` で書体を変える。
    /// 範囲が本文の長さから外れているときは、安全のため装飾を適用しない
    /// （評価者注記「装飾非対応の状態でも本文として読める」を担保）。
    private var decoratedBody: some View {
        var attributed = AttributedString(displayBody)
        let nsText = displayBody as NSString
        for decoration in inlineDecorations {
            guard let range = decoration.range, NSMaxRange(range) <= nsText.length else {
                continue
            }
            let nsSubstring = nsText.substring(with: range)
            if let substringRange = displayBody.range(of: nsSubstring) {
                guard
                    let startIndex = AttributedString.Index(substringRange.lowerBound, within: attributed),
                    let endIndex = AttributedString.Index(substringRange.upperBound, within: attributed)
                else { continue }
                let attrRange = startIndex..<endIndex
                switch decoration.kind {
                case .bold:
                    attributed[attrRange].font = .system(size: 21, weight: .bold, design: .rounded)
                case .italic:
                    attributed[attrRange].font = .system(size: 21, weight: .medium, design: .rounded).italic()
                default:
                    break
                }
            }
        }
        return Text(attributed)
            .foregroundStyle(Theme.ink)
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline.card.body")
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }
}
