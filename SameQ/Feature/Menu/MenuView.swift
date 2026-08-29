import SwiftUI

/// ハンバーガーメニュー（新機能）。
///
/// 設計方針（低リスク優先）:
///   * `SettingsView` の内部実装は一切変更しない。プロフィール編集・規約表示・
///     ブロック管理・アカウント削除は既存の `SettingsView` へリンクアウトする。
///   * `session.isSettingsPresented` / `isPlusViewPresented` / `isNotificationsPresented`
///     を直接立てるだけで、`RootView` 側の既存 `.sheet` がそのまま反応する
///     （`SettingsView.plusSection` が同じパターンで既に動いている実績を踏襲）。
///
/// **隠し開発者モード**: 下部のバージョン表示を8回連続タップすると生年月日の入力を求め、
/// 正しければ Plus 状態を強制的にON/OFFできるデバッグ用トグルが現れる（RevenueCat/StoreKit
/// の実システムを介さずに Plus 表示を素早く切り替えて動作確認するための機能）。
struct MenuView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var versionTapCount = 0
    @State private var isDevGateShown = false
    @State private var devPasscodeInput = ""
    @State private var isDevModeUnlocked = false

    /// 生年月日ゲートの正解値。サーバーや決済を一切バイパスしないローカル限定の
    /// 誤操作防止用のため、ソース内ハードコードで問題ない。
    private static let devGatePasscode = "19820427"

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        profileSummary
                        menuList
                        if isDevModeUnlocked {
                            devModeSection
                        }
                        versionFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.Menu.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                        .accessibilityIdentifier("menu.close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu.root")
        .alert(L10n.Menu.devGateTitle, isPresented: $isDevGateShown) {
            TextField(L10n.Menu.devGatePlaceholder, text: $devPasscodeInput)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("menu.devGate.passcodeField")
            Button(L10n.Menu.devGateSubmit) {
                submitDevGate()
            }
            .accessibilityIdentifier("menu.devGate.submit")
            Button(L10n.Common.cancel, role: .cancel) {
                devPasscodeInput = ""
                versionTapCount = 0
            }
        } message: {
            Text(L10n.Menu.devGateMessage)
        }
    }

    /// タップするとプロフィール編集を開く（2026-08-29追記）。中の絵文字・ニックネームの
    /// `Text` はそのまま残す（既存テストが `menu.profile.nickname` を staticText として
    /// 参照するため、要素の種類を変えない）。タップ可能なのは外側の `Button` コンテナ。
    private var profileSummary: some View {
        Button {
            openChildSheet { session.isProfileEditPresented = true }
        } label: {
            HStack(spacing: 14) {
                Text(session.user?.emoji ?? "🙂")
                    .font(.system(size: 28))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.background))
                    .accessibilityIdentifier("menu.profile.emoji")
                Text(session.user?.displayNickname ?? L10n.Settings.profilePlaceholder)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        session.user?.displayNickname == nil ? Theme.inkTertiary : Theme.ink
                    )
                    .accessibilityIdentifier("menu.profile.nickname")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .cardBackground(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.profile.edit")
    }

    private var menuList: some View {
        VStack(spacing: 0) {
            menuRow(title: L10n.Menu.notifications, identifier: "notifications.open") {
                session.isNotificationsPresented = true
            }
            Divider().padding(.leading, 16)
            menuRow(title: L10n.Menu.plus, identifier: "plus.open") {
                session.isPlusViewPresented = true
            }
            Divider().padding(.leading, 16)
            // "settings.open" 識別子を再利用: 既存 UI テストの改修を
            // 「メニューを開く一手間」の追加だけに抑えるため。
            menuRow(title: L10n.Menu.settings, identifier: "settings.open") {
                session.isSettingsPresented = true
            }
        }
        .cardBackground(cornerRadius: 18)
    }

    /// `menuRow` のタップハンドラをラップする。
    ///
    /// **attempt 2（eval-1.md [1] の修正）**: 従来は子画面を開くだけで
    /// メニュー自身のシートが残ってしまい、子画面を閉じると再びメニューが
    /// 前面に出る導線バグがあった。メニューを `dismiss()` で先に閉じてから
    /// シートの dismissal アニメーションが落ち着くのを待ち、子の画面を開く
    /// ようにした。これで「メニュー → 子画面 → 閉じる → ホーム」の動線が
    /// 成立する（Sprint04 test03 の回帰も解消）。
    private func openChildSheet(_ action: @escaping () -> Void) {
        // まずメニュー自身を閉じる（`session.isMenuPresented` も false に戻る）
        dismiss()
        // シートが完全に消える前に次のシートを立てるとスタックして見えるので
        // 少しだけ間を置いてから子画面を開く。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            action()
        }
    }

    private func menuRow(title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            openChildSheet(action)
        } label: {
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

    // MARK: 隠し開発者モード

    private var devModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Menu.devSectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.Menu.devPlusOverrideLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                Picker(L10n.Menu.devPlusOverrideLabel, selection: devPlusOverrideBinding) {
                    Text(L10n.Menu.devPlusOverrideActual).tag(DevPlusOverrideOption.actual)
                    Text(L10n.Menu.devPlusOverrideAlwaysOn).tag(DevPlusOverrideOption.alwaysOn)
                    Text(L10n.Menu.devPlusOverrideAlwaysOff).tag(DevPlusOverrideOption.alwaysOff)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("menu.dev.plusOverride")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(cornerRadius: 18)
        }
    }

    private enum DevPlusOverrideOption: Hashable {
        case actual
        case alwaysOn
        case alwaysOff
    }

    private var devPlusOverrideBinding: Binding<DevPlusOverrideOption> {
        Binding(
            get: {
                switch session.debugPlusOverride {
                case .some(true): return .alwaysOn
                case .some(false): return .alwaysOff
                case .none: return .actual
                }
            },
            set: { newValue in
                switch newValue {
                case .actual: session.debugPlusOverride = nil
                case .alwaysOn: session.debugPlusOverride = true
                case .alwaysOff: session.debugPlusOverride = false
                }
            }
        )
    }

    private var versionFooter: some View {
        Text(AppVersion.displayString)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture {
                versionTapCount += 1
                if versionTapCount >= 8 {
                    versionTapCount = 0
                    devPasscodeInput = ""
                    isDevGateShown = true
                }
            }
            .accessibilityIdentifier("menu.version")
    }

    private func submitDevGate() {
        if devPasscodeInput == Self.devGatePasscode {
            isDevModeUnlocked = true
        }
        devPasscodeInput = ""
    }
}
