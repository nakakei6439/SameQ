import XCTest
@testable import SameQ

/// スプリント10 / F28〜F31 の `PlusService` と `LocalBackend` の振る舞いを
/// 単体テストで担保する。
///
/// `FakePlusService` を `AppSession` に注入して Plus 状態を切り替え、
/// `LocalBackend.bodyCharacterLimit(isPlus:)` の分岐と装飾受理・非受理を確認する。
@MainActor
final class PlusServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // attempt 2: 永続化導入後のテスト間リーク防止。
        // 既存テスト（test01〜test09）は引数なしの `FakePlusService()` を経由して
        // `UserDefaults.standard` を共有するため、各テスト開始時に永続化キーを
        // クリアしないとテスト順序で結果が変わる（test04 などが影響を受けていた）。
        UserDefaults.standard.removeObject(forKey: FakePlusService.lastEntitlementKey)
    }

    override func tearDown() {
        // 念のため後片付け
        UserDefaults.standard.removeObject(forKey: FakePlusService.lastEntitlementKey)
        super.tearDown()
    }

    // MARK: PlusService プロトコル

    func test01_FakePlusServiceStartsInactive() async {
        let service = FakePlusService()
        let entitlement = await service.currentEntitlement()
        XCTAssertNil(entitlement, "初期状態は未購入")
        let products = await service.availableProducts()
        XCTAssertFalse(products.isEmpty, "商品は1件以上ある")
        XCTAssertEqual(products.first?.displayPrice, "¥480", "価格は仕様の想定月額480円")
    }

    func test02_FakePlusServicePurchaseActivatesEntitlement() async throws {
        let service = FakePlusService()
        let products = await service.availableProducts()
        let product = try XCTUnwrap(products.first)
        let entitlement = try await service.purchase(product)
        XCTAssertTrue(entitlement.isActive(at: Date()), "購入直後は購読期間内")
        let current = await service.currentEntitlement()
        XCTAssertNotNil(current, "購入後のエンタイトルメントは残る")
    }

    func test03_FakePlusServiceRestoreReturnsExistingEntitlement() async throws {
        let service = FakePlusService()
        let products = await service.availableProducts()
        let product = try XCTUnwrap(products.first)
        _ = try await service.purchase(product)
        // `restore()` は現在のエンタイトルメントを返す（F31）
        let restored = try await service.restore()
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.productID, product.id)
    }

    func test04_FakePlusServiceDeactivateClearsEntitlement() async {
        let service = FakePlusService()
        // 初期化時は未購入 → エンタイトルメントは無し
        let initial = await service.currentEntitlement()
        XCTAssertNil(initial)
        // `setPlusActive(true)` で有効化するとエンタイトルメントが現れる
        service.setPlusActive(true)
        let active = await service.currentEntitlement()
        XCTAssertNotNil(active)
        // `setPlusActive(false)` で無効化すると消える
        service.setPlusActive(false)
        let after = await service.currentEntitlement()
        XCTAssertNil(after)
    }

    // MARK: LocalBackend.bodyCharacterLimit

    func test05_FreeLimitIs140_PlusLimitIs2000() {
        XCTAssertEqual(LocalBackend.bodyCharacterLimit(isPlus: false), 140)
        XCTAssertEqual(LocalBackend.bodyCharacterLimit(isPlus: true), 2_000)
    }

    // MARK: LocalBackend 長文投稿（F29）

    /// 同梱シードが 22 件あるシナリオで、お題を取得 → 自分のアカウントを作って
    /// 200 文字の長文を投稿し、永続化 → 復元で同じ長さで読める、を確認する。
    func test06_LongPostRejectedForFreeUserAndAcceptedForPlus() async throws {
        let backend = LocalBackend(
            clock: AppClock(offset: 0),
            options: LaunchOptions(resetsState: true, scenario: .live, answerCount: 5)
        )
        let promptState = try await backend.promptState()
        guard case .active(let prompt) = promptState else {
            XCTFail("seeded prompt should be active at offset 0")
            return
        }
        _ = try await backend.createAnonymousUser(emoji: "🌸", nickname: "Test")

        // 200 文字（無料ユーザーの上限 140 を超える）。`PostValidator.isMeaninglessRepetition` に
        // 弾かれないよう、複数種類の文字を織り交ぜる（同じ文字が 70% を超えると拒否される）。
        let longSource = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめも")
        let longBody = String((0..<200).map { longSource[$0 % longSource.count] })

        // 無料ユーザーは長文投稿を拒否される
        do {
            _ = try await backend.submitPost(
                promptID: prompt.id,
                body: longBody,
                decorations: [],
                isPlus: false
            )
            XCTFail("無料ユーザーが長文を投稿できてしまった")
        } catch let error as BackendError {
            switch error {
            case .bodyTooLong(let limit):
                XCTAssertEqual(limit, 140, "拒否時の limit は無料ユーザーの上限")
            default:
                XCTFail("期待: bodyTooLong、実際のエラー: \(error)")
            }
        }

        // Plus ユーザーは長文投稿を受理される
        let posted = try await backend.submitPost(
            promptID: prompt.id,
            body: longBody,
            decorations: [],
            isPlus: true
        )
        XCTAssertEqual(posted.body.count, 200, "Plus なら 200 文字も保存される")

        // 永続化 → 復元でも同じ長さで読める（state.json のスキーマを跨いでも長文が落ちることはない）
        let restored = LocalBackend(
            clock: AppClock(offset: 0),
            options: LaunchOptions(scenario: .live, answerCount: 5)
        )
        let myPost = try await restored.myPost(promptID: prompt.id)
        XCTAssertEqual(myPost?.body.count, 200, "再起動後も長文はそのまま残る")
    }

    // MARK: 装飾（F30）

    /// 無料ユーザーが装飾付きの本文を送ったとき、装飾は受理されず無視される。
    func test07_FreeUserDecorationsAreIgnored() async throws {
        let backend = LocalBackend(
            clock: AppClock(offset: 0),
            options: LaunchOptions(resetsState: true, scenario: .live, answerCount: 5)
        )
        let promptState = try await backend.promptState()
        guard case .active(let prompt) = promptState else {
            XCTFail("seeded prompt should be active at offset 0")
            return
        }
        _ = try await backend.createAnonymousUser(emoji: "🌸", nickname: nil)

        let stamp = PostDecoration(kind: .emojiStamp, value: "🌸")
        let posted = try await backend.submitPost(
            promptID: prompt.id,
            body: "装飾付きの本文",
            decorations: [stamp],
            isPlus: false
        )
        XCTAssertTrue(posted.decorations.isEmpty, "無料ユーザーの装飾は無視される")
    }

    /// Plus ユーザーの装飾は受理される。
    func test08_PlusUserDecorationsAreStored() async throws {
        let backend = LocalBackend(
            clock: AppClock(offset: 0),
            options: LaunchOptions(resetsState: true, scenario: .live, answerCount: 5)
        )
        let promptState = try await backend.promptState()
        guard case .active(let prompt) = promptState else {
            XCTFail("seeded prompt should be active at offset 0")
            return
        }
        _ = try await backend.createAnonymousUser(emoji: "🌸", nickname: nil)

        let stamp = PostDecoration(kind: .emojiStamp, value: "✨")
        let posted = try await backend.submitPost(
            promptID: prompt.id,
            body: "装飾付きの本文",
            decorations: [stamp],
            isPlus: true
        )
        XCTAssertEqual(posted.decorations.count, 1)
        XCTAssertEqual(posted.decorations.first?.kind, .emojiStamp)
        XCTAssertEqual(posted.decorations.first?.value, "✨")
    }

    // MARK: PostBodyInspector（F29）

    func test09_PostBodyInspectorDetectsLongFormAndPreviews() {
        let body = String(repeating: "x", count: 200)
        XCTAssertTrue(PostBodyInspector.isLongForm(body, limit: 140))
        XCTAssertFalse(PostBodyInspector.isLongForm("short", limit: 140))
        let preview = PostBodyInspector.previewBody(of: body, limit: 140)
        XCTAssertEqual(preview.count, 140, "折り畳みは previewLimit 文字")
    }

    // MARK: FakePlusService の永続化（attempt 2: eval-1.md [1] の修正）

    /// 購入後に `FakePlusService` を破棄し、別インスタンスで `restore()` を呼ぶと
    /// Plus 状態が戻ること（受け入れ条件6・attempt 2）。
    /// `UserDefaults` のテスト用スイート（`UserDefaults(suiteName:)`）で分離して、
    /// 本物の `UserDefaults.standard` を汚さない。
    func test10_FakePlusServicePersistsEntitlementAcrossInstances() async throws {
        let suiteName = "FakePlusServiceTests.persistence"
        let defaults = UserDefaults(suiteName: suiteName)!
        // 念のため初期化
        defaults.removePersistentDomain(forName: suiteName)

        // 1回目: 購入して永続化
        do {
            let service = FakePlusService(defaults: defaults)
            let products = await service.availableProducts()
            let product = try XCTUnwrap(products.first)
            _ = try await service.purchase(product)
        }

        // インスタンスを破棄し、新たに作る（アプリ再起動を模倣）
        let rehydrated = FakePlusService(defaults: defaults)
        // 起動直後はまだ無料ユーザー扱い（永続化は restore() が引く）
        let beforeRestore = await rehydrated.currentEntitlement()
        XCTAssertNil(beforeRestore, "再起動直後はまだ Plus ではない（restore 前）")
        let restored = try await rehydrated.restore()
        XCTAssertNotNil(restored, "再起動後の restore() で Plus 状態が戻る")
        XCTAssertTrue(restored?.isActive(at: Date()) == true)
        // restore 後は active
        let afterRestore = await rehydrated.currentEntitlement()
        XCTAssertNotNil(afterRestore, "restore 後は currentEntitlement() が非 nil")

        // 後片付け（テスト用スイートを削除）
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// 永続化されたエンタイトルメントが期限切れなら、新規 `FakePlusService` は
    /// 未購入状態として起動すること（attempt 2: 期限切れの偽 Plus を持ち越さない）。
    func test11_FakePlusServiceDoesNotRehydrateExpiredEntitlement() async throws {
        let suiteName = "FakePlusServiceTests.expired"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // 過去に切れたエンタイトルメントを直接書き込む
        let past = Date().addingTimeInterval(-60 * 60)        // 1時間前
        let expired = PlusEntitlement(
            productID: "com.nakakei6439.SameQ.plus.monthly",
            purchasedAt: past.addingTimeInterval(-60 * 60 * 24 * 30),
            expiresAt: past
        )
        let data = try JSONEncoder().encode(expired)
        defaults.set(data, forKey: FakePlusService.lastEntitlementKey)

        // 新規インスタンスで起動 → 期限切れのため未購入扱いに落ちる
        let service = FakePlusService(defaults: defaults)
        let current = await service.currentEntitlement()
        XCTAssertNil(current, "期限切れのエンタイトルメントは復元されない")
        // 古い値もクリーンされている（再度 restore() を押しても反応しない）
        let restored = try await service.restore()
        XCTAssertNil(restored, "期限切れ状態からの restore() は nil")

        defaults.removePersistentDomain(forName: suiteName)
    }

    /// `setPlusActive(false)` を呼ぶと永続化されたエントリも削除されること
    ///（attempt 2: 「Plus をキャンセルした」状態を再現するため）。
    func test12_FakePlusServiceDeactivateClearsPersistedEntitlement() async {
        let suiteName = "FakePlusServiceTests.deactivate"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let service = FakePlusService(defaults: defaults)
        service.setPlusActive(true)
        XCTAssertNotNil(defaults.data(forKey: FakePlusService.lastEntitlementKey),
                        "setPlusActive(true) で UserDefaults に書き込まれる")
        service.setPlusActive(false)
        XCTAssertNil(defaults.data(forKey: FakePlusService.lastEntitlementKey),
                     "setPlusActive(false) で UserDefaults のエントリが削除される")

        defaults.removePersistentDomain(forName: suiteName)
    }
}
