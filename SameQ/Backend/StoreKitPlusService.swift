import Foundation
import StoreKit

/// `PlusService` の StoreKit 2 実装（F28 / F29 / F30 / F31）。
///
/// 仕様は「課金は RevenueCat」とあるが、本スプリントでは外部パッケージ依存を
/// 増やさない方針に従い、StoreKit 2 を直接使う。RevenueCat の SDK も同じ
/// StoreKit 2 を内部で叩いているので、ここを差し替えるだけで RevenueCat へ
/// 移行できる（`PlusService` プロトコルが境界になっているため）。
///
/// 商品 ID は `com.nakakei6439.SameQ.plus.monthly` のみ。将来 Yearly Plus を
/// 追加する際は `availableProducts()` を複数返し、エンタイトルメントの
/// `productID` でどちらを買ったかを識別する想定（spec.md 23行）。
@MainActor
final class StoreKitPlusService: PlusService {
    /// StoreKit から取得する商品 ID のセット。`availableProducts()` に反映される。
    /// Spec は「将来 Yearly Plus」と書いているが、現状は月額のみ。
    private let productIDs: Set<String> = [
        "com.nakakei6439.SameQ.plus.monthly"
    ]

    /// 商品キャッシュ。`availableProducts()` のたびに StoreKit を叩かないように。
    private var productsCache: [Product] = []

    func availableProducts() async -> [PlusProduct] {
        do {
            let products = try await Product.products(for: productIDs)
            productsCache = products
            return products.map { product in
                PlusProduct(
                    id: product.id,
                    displayName: "Plus （月額）",
                    displayPrice: product.displayPrice,
                    periodDescription: "月額 / いつでも解約できます"
                )
            }
        } catch {
            // ストアから商品が引けない状態（オフライン・未設定等）は UI で「読み込み中」を
            // 見せた上で、購入ボタンを一時的に押せなくする側で扱う。
            productsCache = []
            return []
        }
    }

    func currentEntitlement() async -> PlusEntitlement? {
        // `Transaction.currentEntitlements` は購読中のすべてのエンタイトルメントを返す。
        // 本スプリントでは月額のみなので、先頭のものを返す。
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil {
                let purchasedAt = transaction.purchaseDate
                // 自動更新サブスクリプションの `expirationDate` を期限として使う。
                // `expirationDate` が `nil` になることはない（サブスクリプションの場合）。
                let expiresAt = transaction.expirationDate
                    ?? Calendar.current.date(byAdding: .day, value: 30, to: purchasedAt)
                    ?? purchasedAt.addingTimeInterval(60 * 60 * 24 * 30)
                return PlusEntitlement(
                    productID: transaction.productID,
                    purchasedAt: purchasedAt,
                    expiresAt: expiresAt
                )
            }
        }
        return nil
    }

    func purchase(_ product: PlusProduct) async throws -> PlusEntitlement {
        guard let storeKitProduct = try await findStoreKitProduct(id: product.id) else {
            throw PlusPurchaseError.productNotFound
        }
        let result = try await storeKitProduct.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let purchasedAt = transaction.purchaseDate
                let expiresAt = transaction.expirationDate
                    ?? Calendar.current.date(byAdding: .day, value: 30, to: purchasedAt)
                    ?? purchasedAt.addingTimeInterval(60 * 60 * 24 * 30)
                await transaction.finish()
                return PlusEntitlement(
                    productID: transaction.productID,
                    purchasedAt: purchasedAt,
                    expiresAt: expiresAt
                )
            case .unverified(_, let error):
                throw PlusPurchaseError.other(error.localizedDescription)
            }
        case .pending:
            // Ask to Buy など。仕様にないが、UI では「保留中」扱いに。
            throw PlusPurchaseError.other("購入は保留中です")
        case .userCancelled:
            throw PlusPurchaseError.userCancelled
        @unknown default:
            throw PlusPurchaseError.other("未知の購入結果")
        }
    }

    func restore() async throws -> PlusEntitlement? {
        try await AppStore.sync()
        return await currentEntitlement()
    }

    private func findStoreKitProduct(id: String) async throws -> Product? {
        if let hit = productsCache.first(where: { $0.id == id }) {
            return hit
        }
        // キャッシュに無い（購入画面に直接飛んできたなど）のときは取り直す。
        let products = try await Product.products(for: productIDs)
        productsCache = products
        return products.first(where: { $0.id == id })
    }
}
