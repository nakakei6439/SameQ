import SwiftUI

/// 統合ヘッダー（新機能）: ハンバーガーメニュー・アプリ名・通知ベル・Plus導線・アバター。
/// Today / Waiting の両画面で共通利用する。
///
/// 従来 `identityRow`（絵文字＋ニックネーム）＋ `SettingsEntryButton`（歯車）＋
/// `PlusEntryButton` を個別に並べていたのを1本のヘッダーへ統合した。設定への直接導線は
/// 廃止し、ハンバーガーメニュー（`MenuView`）配下へ集約している
/// （`SettingsEntryButton` 構造体は削除、`"settings.open"` 識別子は `MenuView` 側の
/// 行ボタンへ引き継ぐ）。
///
/// **設計判断**: 参考にしたレイアウトどおり、常時表示するのは絵文字アバターのみで、
/// ニックネーム文字列は表示しない（以前は `identityRow` で常時表示していた）。
/// SameQ の匿名性重視の方針（本名・顔写真は対象外）とも整合する。ニックネームの確認は
/// `MenuView.profileSummary`（`menu.profile.nickname`）で行う。
///
/// 各要素は必ず親 `HStack` の直接の子として並べる。既存コードの実績どおり、
/// `.accessibilityIdentifier` を付けたビューの内側にボタンを置くと識別子が
/// 上書きされる（`TodayPromptView` の旧 `identityRow` コメント参照）ため、
/// この構造（アイデンティティ要素とボタン類が常に兄弟）を崩さないこと。
struct AppHeaderBar: View {
    @Environment(AppSession.self) private var session

    /// 既存 UI テストが `today.identity` / `waiting.identity` を参照しているため、
    /// 呼び出し元ごとに識別子を変えられるようにして互換性を保つ。
    let identityIdentifier: String

    var body: some View {
        HStack(spacing: 10) {
            MenuEntryButton()

            Text(L10n.Common.appName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("header.appName")

            Spacer(minLength: 8)

            NotificationsEntryButton()
            PlusEntryButton()

            Text(session.user?.emoji ?? "🙂")
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .accessibilityIdentifier(identityIdentifier)
                .accessibilityLabel(Text(session.user?.displayNickname ?? ""))
        }
    }
}

/// ハンバーガーメニューへの入り口。旧 `SettingsEntryButton` と同じボタン構造を踏襲。
struct MenuEntryButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            session.isMenuPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 40, height: 40, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.open")
        .accessibilityLabel(Text(L10n.Menu.title))
    }
}

/// 通知（アプリ通知 / 運営お知らせ）画面への入り口。
struct NotificationsEntryButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            session.isNotificationsPresented = true
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 40, height: 40, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.open")
        .accessibilityLabel(Text(L10n.Notifications.title))
    }
}
