import XCTest
@testable import SameQ

/// スプリント10 / F28〜F31 の `PlusService` と `LocalBackend` の振る舞いを
/// 単体テストで担保する。
///
/// `FakePlusService` を `AppSession` に注入して Plus 状態を切り替え、
/// `LocalBackend.bodyCharacterLimit(isPlus:)` の分岐と装飾受理・非受理を確認する。
@MainActor
final class PlusServiceTests: XCTestCase {

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
}
