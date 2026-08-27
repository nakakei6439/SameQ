import SwiftUI

/// Plus 購入画面（F28 / F31）。
///
/// 「月額価格・提供内容・購入ボタン・購入復元」の 4 つを 1 つのシートにまとめる。
/// 既に購入済みの場合は購入ボタンを「Plus に登録済み」というラベルに変えて
/// 押せなくする（二重課金を防ぐ）。「購入を復元」は何度押しても安全な設計にしておく
/// （StoreKit 側で重複課金は発生しない）。
struct PlusView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// 購入処理中の重複タップ防止。`true` のあいだは購入ボタンも復元ボタンも押せない。
    @State private var isWorking = false

    var body: some View {
        @Bindable var session = session
        return NavigationStack {
            ZStack {
                Theme.canvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        heroSection
                        benefitsSection
                        purchaseSection
                        restoreSection
                        disclaimerSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(L10n.Plus.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                        .accessibilityIdentifier("plus.close")
                }
            }
        }
        // `children: .contain` が無いと、中のボタンの識別子まで上書きしてしまう。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plus.root")
        .overlay(
            // UI テストから「Plus 画面が確実に表示された」ことを判定するための不可視アンカー。
            // accessibilityIdentifier は AccessibilityElement に乗らないケースがあるため、
            // 透明な Text を 1 枚重ねて確実に拾えるようにする。
            Text("Plus")
                .accessibilityIdentifier("plus.root.anchor")
                .opacity(0)
                .frame(width: 1, height: 1)
        )
        .task {
            await session.preparePlusView()
        }
    }

    // MARK: パーツ

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("✨").font(.system(size: 32))
                Text(L10n.Plus.heroTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Text(L10n.Plus.heroBody)
                .font(.system(size: 14))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityIdentifier("plus.hero")
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Plus.benefitsTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                benefitRow(
                    icon: "📝",
                    title: L10n.Plus.benefitLongTitle,
                    detail: L10n.Plus.benefitLongBody
                )
                Divider().padding(.leading, 56)
                benefitRow(
                    icon: "🌸",
                    title: L10n.Plus.benefitStampTitle,
                    detail: L10n.Plus.benefitStampBody
                )
                Divider().padding(.leading, 56)
                benefitRow(
                    icon: "🖋️",
                    title: L10n.Plus.benefitDecorationTitle,
                    detail: L10n.Plus.benefitDecorationBody
                )
                Divider().padding(.leading, 56)
                benefitRow(
                    icon: "💬",
                    title: L10n.Plus.benefitBalloonTitle,
                    detail: L10n.Plus.benefitBalloonBody
                )
            }
            .padding(.vertical, 6)
            .cardBackground()
        }
        .accessibilityIdentifier("plus.benefits")
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(icon)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.background))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Plus.priceTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(spacing: 14) {
                if let product = session.plusProducts.first {
                    HStack(alignment: .firstTextBaseline) {
                        Text(product.displayPrice)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        Text(L10n.Plus.priceMonthlySuffix)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                    }
                    Text(L10n.Plus.priceMonthlyNote)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // 商品情報を読み込み中の表示。`-SameQFakePlus` で
                    // `FakePlusService` を使うときは常に出る（実機なしでも値が分かる）。
                    HStack {
                        ProgressView().tint(Theme.inkSecondary)
                        Text(L10n.Common.loadingPrices)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: handlePurchase) {
                    Text(purchaseButtonLabel)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !isWorking && canPurchase))
                .disabled(!canPurchase || isWorking)
                .accessibilityIdentifier("plus.purchase")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        .accessibilityIdentifier("plus.purchaseSection")
    }

    private var purchaseButtonLabel: String {
        if session.isPlus { return L10n.Plus.purchaseActive }
        return L10n.Plus.purchaseInactive
    }

    private var canPurchase: Bool {
        // 商品情報が読めない（StoreKit 構成未完了 / オフライン）ときは押せない。
        guard !session.plusProducts.isEmpty else { return false }
        // 既に Plus なら二重課金を防ぐために押せない。
        return !session.isPlus
    }

    private func handlePurchase() {
        guard let product = session.plusProducts.first else { return }
        guard !isWorking else { return }
        isWorking = true
        Task {
            await session.purchasePlus(product)
            isWorking = false
            // 購入成功時はシートを閉じて、利用可能な状態にすぐ戻す。
            if session.isPlus {
                dismiss()
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Plus.restoreTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)
                .tracking(1)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                Text(L10n.Plus.restoreBody)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: handleRestore) {
                    Text(isWorking ? L10n.Plus.restoreActive : L10n.Plus.restoreButton)
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("plus.restore")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
        }
        .accessibilityIdentifier("plus.restoreSection")
    }

    private func handleRestore() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await session.restorePlus()
            isWorking = false
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Plus.disclaimer1)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.Plus.disclaimer2)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("plus.disclaimer")
    }
}
