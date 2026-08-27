import Foundation
import RevenueCat

/// `PlusService` の RevenueCat 実装（F37 / スプリント14）。
///
/// 仕様の「課金は RevenueCat」に従い、Plus の購入・復元・エンタイトルメント
/// 判定を `RevenueCat.Purchases` SDK 経由で実現する。`PlusService` プロトコルが
/// 境界になっているので、`PlusView` などの UI 層は実装の差を意識しない。
///
/// 商品の取得は `Purchases.products(_:)` を直接叩く方式（Offerings ではなく
/// App Store の Product ID ベース）。`com.nakakei6439.SameQ.plus.monthly` を
/// 唯一の SKU として扱い、エンタイトルメント ID は RevenueCat ダッシュボードで
/// 紐付けた `plus`（spec.md 行23）を `CustomerInfo.entitlements[plus]` で参照する。
///
/// **API キーの扱い**: 公開キー（`appl_` で始まる iOS SDK 用のキー）は iOS バイナリに
/// 埋め込んでよい想定。プロジェクトルートの `.env.local`（`.gitignore` 対象）から
/// ビルド時に `scripts/generate-secrets.sh` が `SameQ/Secrets.swift` を生成し、
/// `Secrets.revenueCatAPIKey` として `Purchases.configure(withAPIKey:)` に渡す。
/// キーが空のときは SDK 側のエラーをそのまま `PlusPurchaseError.other(...)` で
/// ラップして UI に伝える（受け入れ条件5「責めないダイアログ」の精神に従い、
/// 致命的にせず「Plus の商品情報を読み込めませんでした」相当の文言を返す）。
@MainActor
final class RevenueCatPlusService: PlusService {
    /// App Store に登録されている Plus の Product ID。`availableProducts()` で
    /// この ID を `Purchases.products(_:)` に投げて商品情報を取ってくる。
    /// スプリント10 で `StoreKitPlusService` が `com.nakakei6439.SameQ.plus.monthly`
    /// を使っていたのと同じ値を温存し、App Store Connect / RevenueCat 側の
    /// 設定と一致させる。
    private let productIDs: Set<String> = [
        "com.nakakei6439.SameQ.plus.monthly"
    ]

    /// RevenueCat 側で付与したエンタイトルメント ID。spec.md 行23 に従い `plus` を使用。
    private let entitlementID = "plus"

    /// `Purchases.products(_:)` の結果を一時保持するためのキャッシュ。
    /// `purchase(_:)` で ID から実 `StoreProduct` を取り直すときに使う。
    /// `StoreKitPlusService.productsCache` と同じ目的のフィールド。
    private var productsCache: [String: StoreProduct] = [:]

    init() {
        // `Purchases.configure(withAPIKey:)` はプロセスで 1 度だけ呼べばよい
        // （2 回目以降は `shared` がそのまま返ってくる）。複数の PlusService インスタンス
        // が作られても二重初期化にはならない（Purchases 側のガード）。
        // API キーが空のときは RevenueCat 側の API 呼び出しが失敗するだけなので、
        // ここでは throw せずにそのまま先に進める（spec の対象外事項にしないため）。
        let apiKey = Secrets.revenueCatAPIKey
        if !apiKey.isEmpty {
            Purchases.configure(withAPIKey: apiKey)
        }
    }

    func availableProducts() async -> [PlusProduct] {
        let ids = Array(productIDs)
        let storeProducts = await Purchases.shared.products(ids)
        // キャッシュを更新（購入時に ID から実 `StoreProduct` を取り直す用）。
        productsCache = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.productIdentifier, $0) })
        return storeProducts.map { product in
            // 表示価格は RevenueCat 経由でも App Store のローカル化された文字列が返る
            // （¥480 / $4.99 等、ロケールを尊重）。`displayName` は "Plus （月額）" 固定
            // （既存 `StoreKitPlusService` / `FakePlusService` と完全一致を保ち、
            //  受け入れ条件1「同じ見た目・同じ導線」を満たす）。
            PlusProduct(
                id: product.productIdentifier,
                displayName: "Plus （月額）",
                displayPrice: product.localizedPriceString,
                periodDescription: "月額 / いつでも解約できます"
            )
        }
    }

    func currentEntitlement() async -> PlusEntitlement? {
        let info = try? await Purchases.shared.customerInfo()
        return Self.entitlement(from: info, entitlementID: entitlementID)
    }

    func purchase(_ product: PlusProduct) async throws -> PlusEntitlement {
        // キャッシュに無い（購入画面に直接飛んできたなど）のときは取り直す。
        if productsCache[product.id] == nil {
            _ = await availableProducts()
        }
        guard let storeProduct = productsCache[product.id] else {
            throw PlusPurchaseError.productNotFound
        }
        do {
            let data = try await Purchases.shared.purchase(product: storeProduct)
            if data.userCancelled {
                // ユーザーキャンセルは「失敗」ではない（受け入れ条件5の精神）。
                throw PlusPurchaseError.userCancelled
            }
            guard let entitlement = Self.entitlement(from: data.customerInfo, entitlementID: entitlementID) else {
                // 購入処理は通ったもののエンタイトルメントに `plus` が乗っていない
                // （RevenueCat ダッシュボードで Product ↔ Entitlement の紐付け漏れ等）。
                // 既存の `StoreKitPlusService.purchase(_:)` は verified なら無条件で
                // エンタイトルメントを組み立てて返していたが、RevenueCat 経路では
                // ダッシュボード側の不整合を吸い込まないようにする。
                throw PlusPurchaseError.other("Plus のエンタイトルメントが付与されませんでした")
            }
            return entitlement
        } catch let error as PlusPurchaseError {
            throw error
        } catch let error as RevenueCat.ErrorCode {
            // `ErrorCode.purchaseCancelledError` もユーザーキャンセル扱い（`userCancelled`
            // フラグが立たない古い端末や、シートを閉じた経路の保険）。
            if error == .purchaseCancelledError {
                throw PlusPurchaseError.userCancelled
            }
            throw PlusPurchaseError.other(error.localizedDescription)
        } catch {
            // ネットワーク等の一時的失敗は `.network`、それ以外は `.other`。
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw PlusPurchaseError.network
            }
            throw PlusPurchaseError.other(error.localizedDescription)
        }
    }

    func restore() async throws -> PlusEntitlement? {
        do {
            let info = try await Purchases.shared.restorePurchases()
            return Self.entitlement(from: info, entitlementID: entitlementID)
        } catch let error as RevenueCat.ErrorCode {
            // 復元で見つからないのは失敗ではない（spec.md F31 の復元「過去の
            // 購入が無い場合は何もせず戻す」相当）。`missingReceiptFileError` は
            // シミュレータや復元対象が無い状態の典型的なシグナル。
            if error == .missingReceiptFileError || error == .receiptInUseByOtherSubscriberError {
                return nil
            }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw PlusPurchaseError.network
            }
            throw PlusPurchaseError.other(error.localizedDescription)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw PlusPurchaseError.network
            }
            throw PlusPurchaseError.other(error.localizedDescription)
        }
    }

    // MARK: - 内部ヘルパー

    /// `CustomerInfo` から `plus` エンタイトルメントを抜き出し、既存の
    /// `PlusEntitlement` に詰める。期限切れや未付与は `nil`。
    ///
    /// - `expirationDate` は購読期間（または猶予期間）の終端。`isActive == false`
    ///   のものは弾く（グレース期間に入ったら `isActive == false` になる実装だが、
    ///   念のため `expirationDate` も比較に使う）。
    /// - `latestPurchaseDate` を `purchasedAt` の近似値として使う。`originalPurchaseDate`
    ///   は「最初の購入」なので更新購読では古いままになる。
    private static func entitlement(from info: CustomerInfo?, entitlementID: String) -> PlusEntitlement? {
        guard let info, let info = info.entitlements[entitlementID] else { return nil }
        guard info.isActive, let expiresAt = info.expirationDate else { return nil }
        // `latestPurchaseDate` は購読更新で都度更新される。nil のケースは実質無いはず。
        let purchasedAt = info.latestPurchaseDate ?? info.originalPurchaseDate ?? Date()
        return PlusEntitlement(
            productID: info.productIdentifier,
            purchasedAt: purchasedAt,
            expiresAt: expiresAt
        )
    }
}
