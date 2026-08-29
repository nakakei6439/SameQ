import SwiftUI

/// 通知画面（新機能）。「アプリ通知」（プッシュ通知の受信履歴 — 本アプリは履歴を
/// 保存しないため常に空状態）と「運営お知らせ」（Supabase の `announcements` を
/// 読むだけの読み取り専用フィード）の2タブ。
///
/// タブはネイティブ `Picker(.segmented)` ではなく、独自ボタン2つで実装している。
/// セグメンテッドコントロールの各セグメントには `.accessibilityIdentifier` を
/// 確実に付けられないため（SwiftUI が `UISegmentedControl` としてネイティブ描画し、
/// 内側の `Text` の識別子がセグメント自体には伝播しない）、`MenuView.menuRow` と同じ
/// 手作りボタンパターンを踏襲する。
struct NotificationsView: View {
    private enum Tab: Hashable {
        case app
        case operatorAnnouncements
    }

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .operatorAnnouncements
    @State private var announcements: [Announcement] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                VStack(spacing: 0) {
                    tabBar
                    switch selectedTab {
                    case .app:
                        appNotificationsEmptyState
                    case .operatorAnnouncements:
                        operatorAnnouncementsList
                    }
                }
            }
            .navigationTitle(L10n.Notifications.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                        .accessibilityIdentifier("notifications.close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notifications.root")
        .task { await loadAnnouncementsIfNeeded() }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            tabButton(title: L10n.Notifications.tabApp, tab: .app, identifier: "notifications.tab.app")
            tabButton(
                title: L10n.Notifications.tabOperator,
                tab: .operatorAnnouncements,
                identifier: "notifications.tab.operator"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func tabButton(title: String, tab: Tab, identifier: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Theme.accent : Theme.surface)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var appNotificationsEmptyState: some View {
        VStack(spacing: 8) {
            Text("🔔").font(.system(size: 32))
            Text(L10n.Notifications.appEmptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text(L10n.Notifications.appEmptyBody)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .accessibilityIdentifier("notifications.app.empty")
    }

    @ViewBuilder
    private var operatorAnnouncementsList: some View {
        if isLoading && announcements.isEmpty {
            ProgressView()
                .tint(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if announcements.isEmpty {
            VStack(spacing: 8) {
                Text("📮").font(.system(size: 32))
                Text(L10n.Notifications.operatorEmptyTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            .accessibilityIdentifier("notifications.operator.empty")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(announcements) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            // 公開日時（attempt 2: eval-1.md [4] の修正）。
                            // spec 受け入れ条件5「見出し・本文・公開日時が読める」要求に
                            // 対応するため、`publishedAt` を画面にも出す。端末ロケールの
                            // 短い日付書式（日本語: 2026/08/29 / 英語: 8/29/2026）で表示する。
                            Text(item.publishedAt, format: .dateTime.year().month().day())
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkTertiary)
                                .accessibilityIdentifier("notifications.operator.publishedAt")
                            Text(item.body)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground(cornerRadius: 18)
                        .accessibilityIdentifier("notifications.operator.row")
                    }
                }
                .padding(20)
            }
        }
    }

    private func loadAnnouncementsIfNeeded() async {
        guard announcements.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        announcements = await session.loadAnnouncements()
    }
}
