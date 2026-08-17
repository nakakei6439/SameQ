import SwiftUI

/// 設定への入り口。今日のお題とお題待ちの右上に置く。
/// 履歴（過去のお題・自分の投稿・いいね一覧）への導線はここにも作らない。
struct SettingsEntryButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            session.isSettingsPresented = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 40, height: 40, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.open")
        .accessibilityLabel(Text("設定"))
    }
}

/// 設定（F15 ブロック管理）。
///
/// スプリント04で必要なのは「ブロック中の一覧と解除」だけなので、それしか置かない。
/// 絵文字・ニックネームの変更、規約、購入復元はスプリント11で足す。
///
/// 一覧に出すのは**絵文字と（あれば）ニックネームだけ**。
/// 国・言語・回答本文・ブロックした時刻は出さない。相手について分かるのは
/// タイムラインで見えていた範囲だけ、という前提を崩さないため。
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ブロック中の人")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                            .tracking(1)
                            .padding(.horizontal, 4)

                        if session.blockedAuthors.isEmpty {
                            emptyState
                        } else {
                            ForEach(session.blockedAuthors) { author in
                                row(author)
                            }
                            Text("解除すると、その人の回答がまた表示されるようになります。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkTertiary)
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("settings.close")
                }
            }
        }
        // `children: .contain` が無いと、中のボタンの識別子まで上書きしてしまう。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.root")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🫧").font(.system(size: 32))
            Text("ブロックしている人はいません")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("settings.blocked.empty")
            Text("タイムラインの ⋯ から、その人の回答を表示しないようにできます。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .cardBackground()
    }

    private func row(_ author: BlockedAuthor) -> some View {
        HStack(spacing: 12) {
            Text(author.emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.background))
                .accessibilityIdentifier("settings.blocked.emoji")

            Text(author.displayNickname ?? "名前のない人")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(author.displayNickname == nil ? Theme.inkTertiary : Theme.ink)
                .lineLimit(1)
                .accessibilityIdentifier("settings.blocked.name")

            Spacer(minLength: 8)

            Button("解除") {
                Task { await session.unblock(authorID: author.id) }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.unblock")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.blocked.row")
    }
}
