import SwiftUI

/// 設定（F15 ブロック管理 / F25 通知設定 / F28-F31 Plus / F32 プロフィール・規約・削除）。
///
/// **新機能（ハンバーガーメニュー導入）**: 従来 Today / Waiting の右上に置いていた
/// `SettingsEntryButton`（歯車アイコン）は廃止し、`MenuView` の「設定」行から
/// `session.isSettingsPresented = true` を直接立てて開く方式に変わった
/// （`"settings.open"` 識別子は `MenuView` 側の行ボタンが引き継ぐ）。この画面自体の
/// 実装・受け入れ条件は変更していない。
///
/// スプリント04で必要なのは「ブロック中の一覧と解除」だけだったので、
/// ブロック管理セクションだけを置いた。スプリント08で「通知」セクションを
/// 上に足し、拒否状態のときに「設定アプリからオンにしてね」案内を出すように
/// した（アプリ内から直接許可を再要求するボタンは置かない。 iOS の仕様上、
/// 一旦拒否された後は設定App からでしか戻せないため）。スプリント10 で
/// 「Plus」セクションを足し、購入復元と Plus 画面の入り口を置いた。
/// スプリント11 で「プロフィール」「規約・プライバシー」「アカウント削除」
/// の3セクションを追加し、設定を完成形にした（F32 / F33）。
///
/// 一覧に出すのは**絵文字と（あれば）ニックネームだけ**。
/// 国・言語・回答本文・ブロックした時刻は出さない。相手について分かるのは
/// タイムラインで見えていた範囲だけ、という前提を崩さないため。
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// プロフィール編集シート（F32）。nil のあいだは出さない。
    @State private var profileEditor: ProfileEditorPresentation?
    /// 規約・プライバシーポリシー表示シート（F32）。nil のあいだは出さない。
    @State private var legalDocument: LegalDocument?
    /// アカウント削除の確認ダイアログ（F33）。true のあいだ表示。
    @State private var showsDeleteConfirmation = false
    /// お問い合わせシート（F51）。true のあいだ表示。
    @State private var showsContact = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        profileSection
                        // 審査でも実利用でも、設定を開いた瞬間に連絡先が見えることが
                        // 大事なので先頭に置く（F51 / ガイドライン 1.2）。
                        supportSection
                        legalSection
                        notificationSection
                        plusSection
                        blockedSection
                        dangerZoneSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
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
        .sheet(item: $profileEditor) { presentation in
            ProfileEditView(initialEmoji: presentation.emoji, initialNickname: presentation.nickname)
                .fontDesign(.rounded)
                .environment(session)
        }
        .sheet(item: $legalDocument) { document in
            LegalView(document: document)
                .fontDesign(.rounded)
                .environment(session)
        }
        .sheet(isPresented: $showsContact) {
            ContactView()
                .fontDesign(.rounded)
                .environment(session)
        }
        .confirmationDialog(
            L10n.Settings.deleteDialogTitle,
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Settings.deleteDialogConfirm, role: .destructive) {
                Task { await session.deleteAccount() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Settings.deleteDialogMessage)
        }
    }

    /// 通知セクション（F25）。
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.notificationSection)
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
                    Text("\(L10n.Settings.notificationNextPrefix)\(Self.timeFormatter.string(from: nextAt))")
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
            return L10n.Settings.notificationHeadlineOn
        case .denied:
            return L10n.Settings.notificationHeadlineOff
        case .notDetermined:
            return L10n.Settings.notificationHeadlineUnknown
        case nil:
            return ""
        }
    }

    /// 現在の許可状態に応じた説明文（F25）。
    private var notificationDetail: String {
        switch session.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.Settings.notificationDetailOn
        case .denied:
            return L10n.Settings.notificationDetailOff
        case .notDetermined:
            return L10n.Settings.notificationDetailUnknown
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
            Text(L10n.Settings.plusSection)
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
                    Button(L10n.Settings.plusOpen) {
                        session.isPlusViewPresented = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.plus.open")

                    Button(L10n.Settings.plusRestore) {
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
        session.isPlus ? L10n.Settings.plusHeadlineActive : L10n.Settings.plusHeadlineInactive
    }

    private var plusDetail: String {
        if session.isPlus {
            return L10n.Settings.plusDetailActive
        }
        return L10n.Settings.plusDetailInactive
    }

    /// ブロックセクション（F15）。
    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.blockedSection)
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
                Text(L10n.Settings.blockedUnblockHint)
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
            Text(L10n.Settings.blockedEmptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("settings.blocked.empty")
            Text(L10n.Settings.blockedEmptyBody)
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

            Text(displayed ?? L10n.Settings.blockedNamePlaceholder)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(displayed == nil ? Theme.inkTertiary : Theme.ink)
                .lineLimit(1)
                .accessibilityIdentifier("settings.blocked.name")

            Spacer(minLength: 8)

            Button(L10n.Common.remove) {
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

    // MARK: プロフィールセクション（F32）

    /// 自分の絵文字とニックネームを表示し、「編集」ボタンで `ProfileEditView` を sheet で開く。
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.profileSection)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            HStack(spacing: 14) {
                Text(session.user?.emoji ?? "🙂")
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.background))
                    .accessibilityIdentifier("settings.profile.emoji")

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.user?.displayNickname ?? L10n.Settings.profilePlaceholder)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(session.user?.displayNickname == nil ? Theme.inkTertiary : Theme.ink)
                        .accessibilityIdentifier("settings.profile.nickname")
                    Text(L10n.Settings.profileEditHint)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                }

                Spacer()

                Button(L10n.Common.edit) {
                    profileEditor = ProfileEditorPresentation(
                        emoji: session.user?.emoji ?? EmojiCatalog.all.first ?? "🙂",
                        nickname: session.user?.nickname ?? ""
                    )
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.profile.edit")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
    }

    // MARK: 規約・プライバシーポリシーセクション（F32）

    /// 利用規約 / プライバシーポリシーを `LegalView` で sheet 表示する。
    /// リリース前にダミー本文を差し替える想定（`LegalText`）。
    // MARK: お問い合わせセクション（F51）

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.supportSection)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                legalRow(
                    title: L10n.Settings.supportContact,
                    identifier: "settings.support.contact"
                ) {
                    showsContact = true
                }
            }
            .cardBackground(cornerRadius: 18)
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.legalSection)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                legalRow(
                    title: L10n.Settings.legalTerms,
                    identifier: "settings.legal.terms"
                ) {
                    legalDocument = .terms
                }
                Divider().padding(.leading, 16)
                legalRow(
                    title: L10n.Settings.legalPrivacy,
                    identifier: "settings.legal.privacy"
                ) {
                    legalDocument = .privacy
                }
            }
            .cardBackground(cornerRadius: 18)

            // 規約に同意した日（F53）。いつ同意したかを本人が確認できるようにする。
            if let acceptance = session.termsAcceptance {
                Text(L10n.Settings.legalAcceptedOn(Self.acceptedOnFormatter.string(from: acceptance.acceptedAt)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("settings.legal.acceptedOn")
            }
        }
    }

    /// 同意日の表示用。端末のロケールに従った日付だけの表記にする。
    private static let acceptedOnFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func legalRow(
        title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: アカウント削除セクション（F33）

    /// アカウント削除のエントリ。確認ダイアログを挟んでから実行する。
    /// 画面下部に Danger Zone として独立セクションで置く（誤タップ防止）。
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Settings.accountSection)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                HStack {
                    Text(L10n.Settings.accountDelete)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
            .accessibilityIdentifier("settings.account.delete")
        }
    }
}

/// プロフィール編集シートに渡す初期値（F32）。
/// `Identifiable` にして `sheet(item:)` 駆動にする。
struct ProfileEditorPresentation: Identifiable, Equatable {
    let id = UUID()
    let emoji: String
    let nickname: String
}

/// 規約・プライバシーポリシー表示シート（F32）。
/// `sheet(item:)` 駆動のため `Identifiable` を持たせる。
enum LegalDocument: String, Identifiable {
    case terms
    case privacy
    var id: String { rawValue }
}
