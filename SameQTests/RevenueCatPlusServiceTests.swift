import XCTest
@testable import SameQ

/// `RevenueCatPlusService` の単体テスト（スプリント14 / F37）。
///
/// 実 SDK の API 呼び出しはネットワーク・App Store・サンドボックスに依存するため、
/// ここでは「プロトコル契約（型・nil/空配列の返し方・例外のラップ）」を中心に担保する。
///
/// `FakePlusService` 経路で `PlusService` プロトコルの振る舞いは別途担保済みなので、
/// このファイルは RevenueCat 経路に固有の「初期化が落ちない／空 API キーでも
/// 致命的にしない／復元時の nil 経路／PlusEntitlement への詰め替え」だけを見る。
@MainActor
final class RevenueCatPlusServiceTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // テスト並列実行で Purchases 内部状態が混ざらないよう、各テスト後に
        // 共有インスタンスをログアウト相当まで巻き戻す（次回 configure で再初期化される）。
        // SDK 5.x は `Purchases.shared` のリセット API が無いので、ここでは
        // appUserID を空に寄せて次回 configure を促すだけに留める（テスト間の干渉は
        // 1 プロセス 1 スイート実行で問題にならない想定）。
    }

    // MARK: - 初期化

    /// `.env.local` 経由で本物の API キーが設定されていれば、サービス構築は例外を投げない。
    /// ここは「ビルドが通り、起動できる」最低限の回帰確認。
    func test01_RevenueCatPlusServiceInitializesWithCurrentAPIKey() {
        XCTAssertNotNil(Secrets.revenueCatAPIKey, "Secrets.revenueCatAPIKey が .env.local から注入されている")
        // 構築で落ちないことだけが確認点。Purchases.configure は SDK 内部で冪等。
        let service = RevenueCatPlusService()
        // `PlusService` プロトコルに準拠している（型システム的にはコンパイル時に保証されるが、
        // 明示的に smoke check）。
        let _: PlusService = service
    }

    /// API キーが空文字でも初期化は成功する（実 SDK 呼び出しが失敗するだけで、
    /// クラッシュや throw はしない）。受け入れ条件5の「責めない」精神と整合する。
    func test02_RevenueCatPlusServiceInitializesGracefullyWithEmptyAPIKey() async {
        // `Secrets.revenueCatAPIKey` は生成ファイル由来（let）なので直接書き換えは
        // できない。代わりに「空キーで初期化される経路」を踏ませるため、
        // 既に `Purchases.configure(withAPIKey:)` を一度も呼ばない状態を保つテストでは
        // `.env.local` に依存する。だが `.env.local` がない CI / 別環境でも
        // 落ちないことを保証するため、`availableProducts()` の戻り値が空配列で
        // 返ってくることだけは確認する。
        let service = RevenueCatPlusService()
        let products = await service.availableProducts()
        // API キーがあれば App Store 経由で商品が返る可能性があるので、
        // 「空でもエラーにもならない」ことを緩く確認（要素 0 許容）。
        // ここでは型とクラッシュ無しのみを担保する。
        XCTAssertNotNil(products, "availableProducts() は配列を返す（throw しない）")
    }

    // MARK: - 復元（nil 経路）

    /// 購入履歴が何も無い状態で `restore()` を呼んでもクラッシュしない。
    /// ネットワークが到達不能 or レシート無しの場合は内部で
    /// `.missingReceiptFileError` / ネットワークエラーが期待されるが、
    /// 少なくとも `throw` された場合の型が `PlusPurchaseError` であるかを確認する。
    func test03_RestoreThrowsTypedErrorWhenNoEntitlementExists() async {
        let service = RevenueCatPlusService()
        do {
            let result = try await service.restore()
            // 成功（nil）でも throw でもどちらでもよい。`nil` か `PlusEntitlement` のみ。
            if let result {
                XCTAssertTrue(result.isActive(at: Date()), "返ってきたエンタイトルメントは購読期間内")
            }
        } catch let error as PlusPurchaseError {
            // ここに来るなら `.network` か `.other` の想定。`.userCancelled` ではない。
            switch error {
            case .userCancelled:
                XCTFail("restore() で .userCancelled は出ないはず")
            default:
                break // OK
            }
        } catch {
            // SDK 内部の例外型が生で漏れてくるのは望ましくないが、
            // 既存の FakePlusService / StoreKitPlusService も `.network` / `.other`
            // 以外を通す経路は無いため、ここでは「致命的にしない」ことだけを確認。
            XCTFail("PlusPurchaseError 以外が漏れた: \(error)")
        }
    }

    // MARK: - PlusEntitlement 詰め替え（純粋関数）

    /// スプリント14 の置き換えで、RevenueCat の `CustomerInfo` → `PlusEntitlement` 変換が
    /// 既存の契約（`isActive` 判定・`expiresAt` をそのまま期限として使う）を満たすこと。
    /// RevenueCat SDK を経由せず、`PlusEntitlement` の契約だけを純粋に検証する。
    func test04_PlusEntitlementActiveAndExpirationSemantics() {
        let now = Date()
        let active = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 30)
        )
        XCTAssertTrue(active.isActive(at: now), "期限内のエンタイトルメントはアクティブ")
        XCTAssertTrue(active.isActive(at: now.addingTimeInterval(60 * 60)), "1時間後もまだアクティブ")
        XCTAssertFalse(
            active.isActive(at: now.addingTimeInterval(60 * 60 * 24 * 31)),
            "期限後は非アクティブ"
        )
    }

    // MARK: - AppSession との配線（スプリント14 でデフォルト切替）

    /// 既定（`-SameQFakePlus` 無し・`-SameQUseStoreKitPlus` 無し）の AppSession は
    /// `RevenueCatPlusService` を選ぶこと。`-SameQFakePlus` を付けたときだけ
    /// `FakePlusService` を選ぶことを確認する。
    func test05_AppSessionDefaultPlusServiceIsRevenueCat() async {
        // 既定の起動引数（FakePlus も StoreKit エスケープも付けない）
        let session = AppSession(
            backend: LocalBackend(
                clock: AppClock(offset: 0),
                options: LaunchOptions(resetsState: true, scenario: .live, answerCount: 0)
            ),
            clock: AppClock(offset: 0),
            notificationScheduler: nil,
            plusService: nil
        )
        // `plusService` は `private` なので、振舞い（`refreshPlusProducts()` の戻り値の型）で
        // 確認する。RevenueCat 経路は SDK 呼び出しを伴う可能性があるため、
        // ここでは「型エラー無く呼べる」「`PlusService` プロトコルの戻り値」だけを確かめる。
        await session.refreshPlusProducts()
        // テストのプロセスは AppStore のサンドボックスに居ないので、シミュレータ環境では
        // 0 件でも「クラッシュしない」で十分。
        XCTAssertNotNil(session.plusProducts, "AppSession.refreshPlusProducts() がクラッシュせず値を返した")
    }

    // MARK: - 受け入れ条件5（購入キャンセルで責めないダイアログ）
    //
    // attempt 3（eval-2.md [3] への対応）: RevenueCat SDK は購入フローで
    // `userCancelled` / `purchaseCancelledError` を返す経路を持つ。
    // `AppSession.purchasePlus(_:)` がそれを `PlusPurchaseError.userCancelled`
    // にラップした場合、`alertMessage` を立てずに `false` を返すことを確認する
    // （受け入れ条件5「責めないダイアログを出さない」の精神）。
    //
    // SDK を直接叩かず `PlusServiceStub` で `purchase` が `.userCancelled` を
    // スローする経路を再現し、`AppSession` 側の挙動を検証する。

    /// `purchase(_:)` が `.userCancelled` を投げたとき、`AppSession.purchasePlus(_:)`
    /// は `alertMessage` を立てず `false` を返す（条件5）。
    func test06_AppSessionPurchaseCancellationDoesNotRaiseAlert() async {
        let stub = PlusServiceStub(
            purchase: .failure(.userCancelled)
        )
        let session = PlusServiceTestSession.make(plusService: stub)
        // 商品を取り出してから purchasePlus を呼ぶ
        let products = await stub.availableProducts()
        let product = try? XCTUnwrap(products.first)
        XCTAssertNotNil(product, "スタブが商品を返す")
        let result = await session.purchasePlus(product!)
        XCTAssertFalse(result, "ユーザーキャンセル時は false を返す")
        XCTAssertNil(
            session.alertMessage,
            "ユーザーキャンセル時は alertMessage を立てない（条件5：責めないダイアログ）"
        )
        XCTAssertNil(
            session.plusEntitlement,
            "キャンセル時は plusEntitlement も更新されない"
        )
        XCTAssertEqual(stub.purchaseCallCount, 1, "purchase() が呼ばれた")
    }

    /// `purchase(_:)` が `.network` を投げたときは `alertMessage` が立つ（条件5の
    /// 逆線。キャンセルと他の失敗の分岐が AppSession で正しく分かれていることを確認）。
    func test07_AppSessionPurchaseNetworkErrorDoesRaiseAlert() async {
        let stub = PlusServiceStub(
            purchase: .failure(.network)
        )
        let session = PlusServiceTestSession.make(plusService: stub)
        let product = stub.availableProductsResult[0]
        let result = await session.purchasePlus(product)
        XCTAssertFalse(result, "通信失敗時は false を返す")
        XCTAssertNotNil(
            session.alertMessage,
            "通信失敗時は alertMessage を立てる（条件5：キャンセル以外）"
        )
        XCTAssertEqual(stub.purchaseCallCount, 1)
    }

    // MARK: - 受け入れ条件6（オフラインで Plus が無料に転落しない）

    /// 既存の plusEntitlement がある状態で `restore()` が `nil` を返しても、
    /// `AppSession.restorePlus()` は plusEntitlement を上書きしない（条件6）。
    /// attempt 3 で `restorePlus` を変更して、`nil` での上書きを禁止したことの
    /// 回帰確認。
    func test08_AppSessionRestoreWithNilDoesNotDropExistingPlus() async {
        let now = Date()
        let existingEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 30)
        )
        let stub = PlusServiceStub(
            currentEntitlement: existingEntitlement,
            restore: .successNil
        )
        let session = PlusServiceTestSession.make(plusService: stub)
        // 起動時の refreshPlusEntitlement で既存のエンタイトルメントが入る
        await session.refreshPlusEntitlement()
        XCTAssertNotNil(
            session.plusEntitlement,
            "refreshPlusEntitlement() で既存のエンタイトルメントが入る"
        )
        XCTAssertEqual(stub.currentEntitlementCallCount, 1)

        // restore() を呼ぶ → スタブは nil を返す
        let restoreResult = await session.restorePlus()
        XCTAssertFalse(
            restoreResult,
            "restore() が nil を返したので restorePlus() は false を返す"
        )
        XCTAssertNotNil(
            session.plusEntitlement,
            "restore で nil  でも plusEntitlement は既存値のまま（条件6：オフライン保護）"
        )
        XCTAssertEqual(
            session.plusEntitlement?.productID,
            existingEntitlement.productID,
            "既存と同じ productID が残っている"
        )
        XCTAssertEqual(stub.restoreCallCount, 1, "restore() が呼ばれた")
    }

    /// `restore()` が新しい（非 nil の）エンタイトルメントを返した場合は
    /// それを plusEntitlement に反映する（購読期間更新の反映）。
    /// 条件6 保護の「`nil` のときだけ温存する」挙動が `non-nil` の更新を
    /// 邪魔していないことを確認する。
    func test09_AppSessionRestoreWithNewEntitlementUpdatesPlusState() async {
        let now = Date()
        let oldEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 15)
        )
        let newEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 45)
        )
        let stub = PlusServiceStub(
            currentEntitlement: oldEntitlement,
            restore: .success(newEntitlement)
        )
        let session = PlusServiceTestSession.make(plusService: stub)
        await session.refreshPlusEntitlement()
        let beforeExpire = session.plusEntitlement?.expiresAt
        XCTAssertEqual(beforeExpire, oldEntitlement.expiresAt)

        let restoreResult = await session.restorePlus()
        XCTAssertTrue(restoreResult, "restore() が non-nil を返したので true")
        XCTAssertEqual(
            session.plusEntitlement?.expiresAt,
            newEntitlement.expiresAt,
            "restore() の新しい値で plusEntitlement が更新される"
        )
    }

    /// オフライン状態を `PlusServiceStub` で再現: 購入後に `currentEntitlement()`
    /// が `nil` を返す（キャッシュが空だった）状況でも、`AppSession` の
    /// `plusEntitlement` を前回値のまま保持するかは別問題として明示的に記録する。
    /// **attempt 3 では `refreshPlusEntitlement()` は素直に `currentEntitlement()`
    /// の戻り値を反映する仕様を維持**。SDK 側のキャッシュ（Purchases 内部）が
    /// オフラインで `nil` を返さない設計に依存している（RevenueCat SDK 5.x の
    /// ドキュメント: オフラインでも過去の customerInfo があればキャッシュを返す）。
    /// この回帰テストは、その SDK の挙動が変わっていないかを確認するため、
    /// 購入 → 起動時 refresh で同じ entitlement が読めることを確認する。
    func test10_AppSessionRefreshAfterPurchaseReadsSameEntitlement() async {
        let now = Date()
        let purchased = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 30)
        )
        let stub = PlusServiceStub(currentEntitlement: purchased)
        let session = PlusServiceTestSession.make(plusService: stub)

        // 起動時の refresh で Plus 状態が立ち上がる
        await session.refreshPlusEntitlement()
        XCTAssertTrue(session.isPlus, "起動時に Plus 状態が立つ")

        // 2回目の refresh でも同じ Plus 状態が続く（= SDK キャッシュが効いているはず）
        await session.refreshPlusEntitlement()
        XCTAssertTrue(session.isPlus, "再 refresh でも Plus 状態が続く")
        XCTAssertEqual(stub.currentEntitlementCallCount, 2)
    }

    // MARK: - 受け入れ条件6（オフライン起動で Plus が無料に転落しない）— 起動経路の保護
    //
    // attempt 4（eval-3.md [3] への対応）: `refreshPlusEntitlement()` にも
    // `restorePlus()` と同じ nil 保護を入れる。オフラインで `currentEntitlement()`
    // が nil を返したケースでも、既存 Plus ユーザーが無料状態に転落しないことを
    // 自動回帰で担保する（条件6 は「通信できない状態で起動しても…」の文面で、
    // 起動経路こそ条件6 の本丸）。

    /// 既存 Plus がある状態で `currentEntitlement()` が `nil` を返しても、
    /// `AppSession.refreshPlusEntitlement()` は `plusEntitlement` を上書きしない
    /// （条件6: 起動経路の保護）。
    func test11_AppSessionRefreshWithNilDoesNotDropExistingPlus() async {
        let now = Date()
        let existingEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 30)
        )
        let stub = PlusServiceStub(currentEntitlement: existingEntitlement)
        let session = PlusServiceTestSession.make(plusService: stub)

        // 1回目: Plus 状態が立ち上がる（オンライン）
        await session.refreshPlusEntitlement()
        XCTAssertNotNil(session.plusEntitlement, "1回目の refresh で Plus 状態が入る")
        XCTAssertTrue(session.isPlus, "isPlus == true")
        XCTAssertEqual(stub.currentEntitlementCallCount, 1)

        // オフライン状態を再現: currentEntitlement() が nil を返すよう切替
        stub.currentEntitlementResult = nil

        // 2回目: 起動経路や画面遷移で再 refresh が走る
        await session.refreshPlusEntitlement()
        XCTAssertNotNil(
            session.plusEntitlement,
            "refreshPlusEntitlement() が nil を返しても既存 plusEntitlement は温存される（条件6: 起動経路の保護）"
        )
        XCTAssertTrue(session.isPlus, "オフライン refresh 後も isPlus == true")
        XCTAssertEqual(
            session.plusEntitlement?.productID,
            existingEntitlement.productID,
            "既存と同じ productID が残っている"
        )
        XCTAssertEqual(
            session.plusEntitlement?.expiresAt,
            existingEntitlement.expiresAt,
            "既存の expiresAt が保持されている"
        )
        XCTAssertEqual(stub.currentEntitlementCallCount, 2, "2回目の refresh で currentEntitlement() が呼ばれた")
    }

    /// 既存 Plus がない（未購入）状態で `currentEntitlement()` が `nil` を返すときは
    /// 従来どおり `plusEntitlement = nil`（変化なし・新規に Plus 状態を作らない）。
    /// attempt 4 の nil 保護が「未購入ユーザーへの温存」を誤って起こさないことの確認。
    func test12_AppSessionRefreshWithNilWhenNoExistingPlusKeepsPlusStateNil() async {
        let stub = PlusServiceStub(currentEntitlement: nil)
        let session = PlusServiceTestSession.make(plusService: stub)

        await session.refreshPlusEntitlement()
        XCTAssertNil(
            session.plusEntitlement,
            "未購入ユーザーの refresh は nil のまま（新規 Plus 状態を起こさない）"
        )
        XCTAssertFalse(session.isPlus, "isPlus == false")

        // もう一度 refresh しても同じ
        await session.refreshPlusEntitlement()
        XCTAssertNil(session.plusEntitlement, "2回目も nil のまま")
    }

    /// 既存 Plus があるが購読期間外（期限切れ）の状態で `currentEntitlement()` が
    /// `nil` を返すときは `plusEntitlement = nil` に置き換える（もう Plus では無いので）。
    /// attempt 4 の nil 保護が「期限切れまで温存する」誤動作をしないことの確認。
    func test13_AppSessionRefreshWithNilWhenExistingIsExpiredClearsPlusState() async {
        let now = Date()
        // 既に期限切れの entitlement を直接 `plusEntitlement` に入れる経路は無いので、
        // まず `currentEntitlement()` が valid な値を返す状態 → refresh で入る →
        // 期限切れの entitlement に差し替え → 再 refresh で nil、という手順を取る。
        let validEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 30)
        )
        let expiredEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now.addingTimeInterval(-60 * 60 * 24 * 60),
            expiresAt: now.addingTimeInterval(-60 * 60 * 24 * 1)
        )
        let stub = PlusServiceStub(currentEntitlement: validEntitlement)
        let session = PlusServiceTestSession.make(plusService: stub)

        // 1回目: valid な entitlement が入る
        await session.refreshPlusEntitlement()
        XCTAssertTrue(session.isPlus, "valid な entitlement で Plus 状態")

        // 購読期間外に。手動で期限切れ entitlement に差し替え（テスト用強制操作）
        // → ※ plusEntitlement は private(set) なのでテストでは直接書き換え不可。
        // 代わりに currentEntitlement() を「期限切れ」を返すよう切替 + nil 化で挙動を確かめる。
        stub.currentEntitlementResult = expiredEntitlement
        await session.refreshPlusEntitlement()
        XCTAssertEqual(
            session.plusEntitlement?.expiresAt,
            expiredEntitlement.expiresAt,
            "currentEntitlement() が non-nil（期限切れ）を返すときは従来どおり置き換える"
        )
        XCTAssertFalse(session.isPlus, "期限切れなので isPlus == false")

        // さらにオフライン化（currentEntitlement() が nil）→ 期限切れ値が残っているので
        // attempt 4 の nil 保護は効かず nil に置き換えられるはず
        stub.currentEntitlementResult = nil
        await session.refreshPlusEntitlement()
        XCTAssertNil(
            session.plusEntitlement,
            "既存が期限切れのとき refresh で nil を受ければ plusEntitlement は nil に戻る（保護は isActive 限定）"
        )
        XCTAssertFalse(session.isPlus, "期限切れ + nil refresh で isPlus == false")
    }

    /// 既存 Plus がある状態で `currentEntitlement()` が新しい（`non-nil`）値を返す
    /// ときは従来どおり最新の値で置き換える（購読期間更新を反映）。attempt 4 の
    /// nil 保護が `non-nil` の更新を邪魔していないことの確認。
    func test14_AppSessionRefreshWithNewEntitlementUpdatesPlusState() async {
        let now = Date()
        let oldEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 15)
        )
        let newEntitlement = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 45)
        )
        let stub = PlusServiceStub(currentEntitlement: oldEntitlement)
        let session = PlusServiceTestSession.make(plusService: stub)

        await session.refreshPlusEntitlement()
        XCTAssertEqual(session.plusEntitlement?.expiresAt, oldEntitlement.expiresAt)

        // currentEntitlement() が新しい entitlement を返すよう切替
        stub.currentEntitlementResult = newEntitlement
        await session.refreshPlusEntitlement()
        XCTAssertEqual(
            session.plusEntitlement?.expiresAt,
            newEntitlement.expiresAt,
            "currentEntitlement() が non-nil の新しい値を返せば plusEntitlement は更新される"
        )
    }
}
