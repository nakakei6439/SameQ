import Foundation
@testable import SameQ

/// スプリント14 attempt 3 で `AppSession` の Plus 関連挙動をテストするための
/// `PlusService` スタブ。実 SDK に依存せず、`currentEntitlement` / `availableProducts` /
/// `purchase` / `restore` の戻り値を呼び出しごとに注入できる。
///
/// テスト用（`@testable import SameQ` のテストターゲット内）の実装詳細。
/// 本体のアプリには同梱されない（生成物ターゲット外）。
@MainActor
final class PlusServiceStub: PlusService {
    /// `currentEntitlement()` の戻り値。`nil` を返す「Plus ではない」状態を再現できる。
    var currentEntitlementResult: PlusEntitlement?
    /// `availableProducts()` の戻り値。1件以上の商品を返すデフォルトは
    /// `PlusService` プロトコル要件を満たすために最低限必要な形にする。
    var availableProductsResult: [PlusProduct] = []
    /// `purchase(_:)` の挙動。`.success(entitlement)` か `.failure(error)` を返す。
    enum PurchaseBehavior {
        case success(PlusEntitlement)
        case failure(PlusPurchaseError)
    }
    var purchaseBehavior: PurchaseBehavior = .success(PlusEntitlement(
        productID: "com.nakakei6439.SameQ.plus.monthly",
        purchasedAt: Date(),
        expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30)
    ))
    /// `restore()` の挙動。`.success(entitlement)` / `.successNil` / `.failure(error)` を返す。
    enum RestoreBehavior {
        case success(PlusEntitlement)
        case successNil
        case failure(PlusPurchaseError)
    }
    var restoreBehavior: RestoreBehavior = .successNil
    /// 呼び出し履歴（テスト側でアサート用）。
    private(set) var purchaseCallCount: Int = 0
    private(set) var restoreCallCount: Int = 0
    private(set) var currentEntitlementCallCount: Int = 0
    private(set) var availableProductsCallCount: Int = 0

    init(
        currentEntitlement: PlusEntitlement? = nil,
        purchase: PurchaseBehavior = .success(PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: Date(),
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30)
        )),
        restore: RestoreBehavior = .successNil
    ) {
        self.currentEntitlementResult = currentEntitlement
        self.purchaseBehavior = purchase
        self.restoreBehavior = restore
        self.availableProductsResult = [
            PlusProduct(
                id: "com.nakakei6439.SameQ.plus.monthly",
                displayName: "Plus （月額）",
                displayPrice: "¥480",
                periodDescription: "月額 / いつでも解約できます"
            )
        ]
    }

    func availableProducts() async -> [PlusProduct] {
        availableProductsCallCount += 1
        return availableProductsResult
    }

    func currentEntitlement() async -> PlusEntitlement? {
        currentEntitlementCallCount += 1
        return currentEntitlementResult
    }

    func purchase(_ product: PlusProduct) async throws -> PlusEntitlement {
        purchaseCallCount += 1
        switch purchaseBehavior {
        case .success(let entitlement):
            return entitlement
        case .failure(let error):
            throw error
        }
    }

    func restore() async throws -> PlusEntitlement? {
        restoreCallCount += 1
        switch restoreBehavior {
        case .success(let entitlement):
            return entitlement
        case .successNil:
            return nil
        case .failure(let error):
            throw error
        }
    }
}

/// AppSession を stub PlusService で起動するための薄いヘルパ（テスト用）。
@MainActor
enum PlusServiceTestSession {
    static func make(
        plusService: PlusServiceStub,
        backend: Backend = LocalBackend(
            clock: AppClock(offset: 0),
            options: LaunchOptions(resetsState: true, scenario: .live, answerCount: 0)
        ),
        clock: AppClock = AppClock(offset: 0),
        notificationScheduler: NotificationScheduling? = nil
    ) -> AppSession {
        AppSession(
            backend: backend,
            clock: clock,
            notificationScheduler: notificationScheduler,
            plusService: plusService
        )
    }
}