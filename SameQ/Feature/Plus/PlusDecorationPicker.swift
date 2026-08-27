import SwiftUI

/// 投稿フォームで使う Plus 限定装飾ピッカー（F30）。
///
/// 装飾は「本文にスタンプを足す」「範囲を太字にする」「吹き出しで囲む」の 3 種。
/// 装飾ピッカーは Plus ユーザーだけに表示する（無料ユーザーには UI ごと非表示）。
///
/// 装飾の適用結果は `session.pendingDecorations` に乗せ、本文送信時に
/// `Backend.submitPost(... decorations: pendingDecorations, isPlus:)` で一緒に送る。
struct PlusDecorationPicker: View {
    @Environment(AppSession.self) private var session

    /// Plus 限定スタンプの候補。意味の重複しない 6 種に絞って、操作を迷わせない。
    private let stampOptions: [String] = ["🌸", "🍵", "🌙", "✨", "☔️", "🕊️"]

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accent)
                Text(L10n.Plus.pickerHeader)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }

            // スタンプ（本文の末尾に emoji を追加する装飾）
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Plus.pickerStampLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stampOptions, id: \.self) { emoji in
                            stampButton(emoji)
                        }
                        if hasStamp(emoji: nil) {
                            removeStampButton
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // 装飾の取り消し（太字・斜体・吹き出しなど）の入口。
            HStack(spacing: 10) {
                decorationToggleButton(
                    label: L10n.Plus.pickerBoldLabel,
                    systemImage: "bold",
                    isOn: hasDecoration(kind: .bold)
                ) {
                    toggleDecoration(kind: .bold, value: nil)
                }
                decorationToggleButton(
                    label: L10n.Plus.pickerItalicLabel,
                    systemImage: "italic",
                    isOn: hasDecoration(kind: .italic)
                ) {
                    toggleDecoration(kind: .italic, value: nil)
                }
                decorationToggleButton(
                    label: L10n.Plus.pickerBalloonLabel,
                    systemImage: "bubble.left",
                    isOn: hasDecoration(kind: .balloon)
                ) {
                    toggleDecoration(kind: .balloon, value: L10n.Plus.pickerBalloonValue)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 18)
        .accessibilityIdentifier("plus.decorations")
    }

    // MARK: スタンプ

    private func stampButton(_ emoji: String) -> some View {
        let isOn = hasStamp(emoji: emoji)
        return Button {
            toggleStamp(emoji: emoji)
        } label: {
            Text(emoji)
                .font(.system(size: 24))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isOn ? Theme.accent.opacity(0.18) : Theme.background)
                )
                .overlay(
                    Circle()
                        .strokeBorder(isOn ? Theme.accent : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plus.stamp.\(emoji)")
        .accessibilityLabel(isOn ? L10n.Plus.pickerStampAccessibilityOn(emoji) : L10n.Plus.pickerStampAccessibilityOff(emoji))
    }

    private var removeStampButton: some View {
        Button {
            removeStamp()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.background))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .foregroundStyle(Theme.inkSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plus.stamp.remove")
        .accessibilityLabel(L10n.Plus.pickerRemoveStamp)
    }

    // MARK: 装飾トグル

    private func decorationToggleButton(
        label: String,
        systemImage: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Theme.accent : Theme.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plus.decoration.\(label)")
    }

    // MARK: 装飾ヘルパ（session.pendingDecorations の読み書き）

    private func hasStamp(emoji: String?) -> Bool {
        session.pendingDecorations.contains { decoration in
            if decoration.kind == .emojiStamp {
                if let emoji { return decoration.value == emoji }
                return true
            }
            return false
        }
    }

    private func toggleStamp(emoji: String) {
        // 単一選択（同時に 1 つまで）。同じものを再タップしたら外す。
        let existing = session.pendingDecorations.first {
            $0.kind == .emojiStamp
        }
        if let existing, existing.value == emoji {
            removeStamp()
        } else {
            removeStamp()
            session.pendingDecorations.append(
                PostDecoration(kind: .emojiStamp, value: emoji, range: nil)
            )
        }
    }

    private func removeStamp() {
        session.pendingDecorations.removeAll { $0.kind == .emojiStamp }
    }

    private func hasDecoration(kind: PostDecoration.Kind) -> Bool {
        session.pendingDecorations.contains { $0.kind == kind }
    }

    private func toggleDecoration(kind: PostDecoration.Kind, value: String?) {
        if let index = session.pendingDecorations.firstIndex(where: { $0.kind == kind }) {
            session.pendingDecorations.remove(at: index)
        } else {
            session.pendingDecorations.append(
                PostDecoration(kind: kind, value: value, range: nil)
            )
        }
    }
}
