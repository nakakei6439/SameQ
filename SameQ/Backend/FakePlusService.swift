import Foundation

/// テストと Debug 限定起動引数 `-SameQFakePlus` で使うフェイク実装。
///
/// `PlusService` プロトコルの振る舞いをそのまま置き換え、`setPlusActive(_:)` で
/// 任意の `Bool` を切り替えられるようにした。`availableProducts()` は月額 480 円の
/// `Monthly Plus` を1件だけ返す。`purchase(_:)` はユーザーが即購入できる扱い、
/// `restore()` はフェイクが覚えている最新のエンタイトルメントを返す。
///
/// 実機やサンドボックス購入の代わりに、UI テストで「Plus 購入後の振る舞い」を
/// 確実に再現するために使う（F28 / F29 / F30 / F31 の受け入れ条件を満たす検証用）。
@MainActor
final class FakePlusService: PlusService, ObservableObject {
    /// 現在の Plus 状態。手動で切り替えられるように公開する。
    @Published private(set) var active: Bool
    /// 最後に確定したエンタイトルメント。`active == true` のあいだは `non-nil`。
    private var lastEntitlement: PlusEntitlement?

    /// 商品 ID。StoreKit 実装と揃える（F28）。
    private let monthlyProductID = "com.nakakei6439.SameQ.plus.monthly"

    init(active: Bool = false) {
        self.active = active
        if active {
            let now = Date()
            let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
                ?? now.addingTimeInterval(60 * 60 * 24 * 30)
            self.lastEntitlement = PlusEntitlement(
                productID: "com.nakakei6439.SameQ.plus.monthly",
                purchasedAt: now,
                expiresAt: expires
            )
        }
    }

    func availableProducts() async -> [PlusProduct] {
        [PlusProduct(
            id: monthlyProductID,
            displayName: "Plus （月額）",
            displayPrice: "¥480",
            periodDescription: "月額 / いつでも解約できます"
        )]
    }

    func currentEntitlement() async -> PlusEntitlement? {
        guard active, let last = lastEntitlement else { return nil }
        // 期限切れチェック。FakePlusService では常に「いま」を渡される。
        if last.expiresAt < Date() { return nil }
        return last
    }

    func purchase(_ product: PlusProduct) async throws -> PlusEntitlement {
        // FakePlusService では購入失敗の経路は用意しない（UI テストの単純化のため）。
        // 失敗経路が必要になったら引数でキャンセル / ネットワークエラーを注入できるように拡張する。
        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
            ?? now.addingTimeInterval(60 * 60 * 24 * 30)
        let entitlement = PlusEntitlement(
            productID: product.id,
            purchasedAt: now,
            expiresAt: expires
        )
        lastEntitlement = entitlement
        active = true
        return entitlement
    }

    func restore() async throws -> PlusEntitlement? {
        // `active == false` でもう `lastEntitlement` が期限切れのときは nil を返す。
        if let last = lastEntitlement, last.expiresAt >= Date() {
            active = true
            return last
        }
        return nil
    }

    /// Debug / UI テスト用に状態を直接切り替えるためのフック。
    /// `purchase(_:)` と異なり期限も `30日後` で固定。
    func setPlusActive(_ active: Bool) {
        if active {
            let now = Date()
            let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
                ?? now.addingTimeInterval(60 * 60 * 24 * 30)
            lastEntitlement = PlusEntitlement(
                productID: monthlyProductID,
                purchasedAt: now,
                expiresAt: expires
            )
        } else {
            lastEntitlement = nil
        }
        self.active = active
    }
}
