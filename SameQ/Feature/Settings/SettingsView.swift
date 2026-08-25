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

/// 設定（F15 ブロック管理 / F25 通知設定）。
///
/// スプリント04で必要なのは「ブロック中の一覧と解除」だけだったので、
/// ブロック管理セクションだけを置いた。スプリント08で「通知」セクションを
/// 上に足し、拒否状態のときに「設定アプリからオンにしてね」案内を出すように
/// した（アプリ内から直接許可を再要求するボタンは置かない。 iOS の仕様上、
/// 一旦拒否された後は設定アプリでしか戻せないため）。
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
                    VStack(alignment: .leading, spacing: 24) {
                        notificationSection
                        plusSection
                        blockedSection
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
        .task {
            // 設定を開いた瞬間に最新の許可状態を反映する（拒否 → 許可にした直後など）。
            await session.refreshNotificationAuthorizationStatus()
        }
    }

    /// 通知セクション（F25）。
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通知")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(notificationHeadline)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("settings.notification.status")
                Text(notificationDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let nextAt = session.nextScheduledNotificationAt {
                    Text("次のお知らせ: \(Self.timeFormatter.string(from: nextAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .accessibilityIdentifier("settings.notification.nextAt")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
    }

    /// 現在の許可状態に応じた見出し。
    private var notificationHeadline: String {
        switch session.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "お題のお知らせはオンです"
        case .denied:
            return "お題のお知らせはオフです"
        case .notDetermined:
            return "お題のお知らせはまだ決まっていません"
        case nil:
            return ""
        }
    }

    /// 現在の許可状態に応じた説明文（F25）。
    private var notificationDetail: String {
        switch session.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "1日1回、8:00〜22:00 の間のランダムな時刻に、新しいお題をお届けします。時刻は毎日変わります。"
        case .denied:
            return "通知をオンにすると、1日1回ランダムな時刻に新しいお題が届きます。iOS の「設定 › 通知 › SameQ」からオンにできます。"
        case .notDetermined:
            return "通知をオンにすると、1日1回ランダムな時刻に新しいお題が届きます。あとで設定 › 通知 › SameQ からいつでも変更できます。"
        case nil:
            return ""
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    /// Plus セクション（F28 / F31）。現在の Plus 状態と、購入復元・Plus 画面の入り口を置く。
    /// 設定の中なので「Plus をやめたい」ユーザーがここに来る想定。「購入を復元」も
    /// 同じ場所からアクセスできるようにしておく（F31）。
    private var plusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plusHeadline)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("settings.plus.status")
                    Spacer()
                    if session.isPlus {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(plusDetail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Plus を見る") {
                        session.isPlusViewPresented = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.plus.open")

                    Button("購入を復元") {
                        Task { await session.restorePlus() }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.plus.restore")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
    }

    private var plusHeadline: String {
        session.isPlus ? "Plus に登録済みです" : "Plus を使うと、もっと書ける"
    }

    private var plusDetail: String {
        if session.isPlus {
            return "長文と装飾（スタンプ・太字・斜体・吹き出し）が使えます。購読の管理は iOS の「設定 › Apple ID › サブスクリプション」から行えます。"
        }
        return "長文（140 文字超）と、スタンプ・太字・斜体・吹き出しの装飾が使えます。購入は App Store 経由で、解約はいつでもできます。"
    }

    /// ブロックセクション（F15）。
    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ブロック中の人")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            if session.blockedAuthors.isEmpty {
                blockedEmptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(session.blockedAuthors) { author in
                        row(author)
                    }
                }
                Text("解除すると、その人の回答がまた表示されるようになります。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    private var blockedEmptyState: some View {
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
        let displayed = author.displayedNickname(transliterator: session.nicknameTransliterator)
        return HStack(spacing: 12) {
            Text(author.emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.background))
                .accessibilityIdentifier("settings.blocked.emoji")

            Text(displayed ?? "名前のない人")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(displayed == nil ? Theme.inkTertiary : Theme.ink)
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
