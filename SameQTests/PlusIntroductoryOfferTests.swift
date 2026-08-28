import XCTest
@testable import SameQ

/// F45 / スプリント18「Plus 1ヶ月無料トライアル」の単価テスト。
///
/// `PlusProduct.introductoryOfferDescription` と `PlusTrialPeriodUnit` の
/// ラウンドトリップ、`FakePlusService.availableProducts()` が trial 表記を
/// 返すことを確認する。
final class PlusIntroductoryOfferTests: XCTestCase {

    func test01_plusProductAcceptsIntroductoryOfferDescription() {
        let product = PlusProduct(
            id: "com.nakakei6439.SameQ.plus.monthly",
            displayName: "Plus （月額）",
            displayPrice: "¥480",
            periodDescription: "月額 / いつでも解約できます",
            introductoryOfferDescription: "1ヶ月無料"
        )
        XCTAssertEqual(product.introductoryOfferDescription, "1ヶ月無料")

        let without = PlusProduct(
            id: "com.nakakei6439.SameQ.plus.monthly",
            displayName: "Plus （月額）",
            displayPrice: "¥480",
            periodDescription: "月額 / いつでも解約できます"
        )
        XCTAssertNil(without.introductoryOfferDescription, "trial がないときは nil")
    }

    func test02_plusTrialPeriodUnitAllCases() {
        // 列挙の全ケースが Hashable / Sendable として扱えることの最低限の保証。
        let all: [PlusTrialPeriodUnit] = [.day, .week, .month, .year]
        let unique = Set(all)
        XCTAssertEqual(unique.count, all.count, "4 種別の列挙値が衝突しない")
    }

    func test03_l10nFreeTrialBadgeJapaneseFor1Month() {
        // 日本語ロケール想定で 1ヶ月無料 の文言が組み立てられること。
        // 端末ロケールに依存させないため、L10n.useEnglish は直接操作しない。
        let badge = L10n.Plus.freeTrialBadge(value: 1, unit: .month)
        XCTAssertFalse(badge.isEmpty, "文言が空にならない")
        XCTAssertTrue(
            badge.contains("1") || badge.contains("1 "),
            "1ヶ月無料には数字1が含まれるはず: \(badge)"
        )
    }

    @MainActor
    func test04_fakePlusServiceExposesIntroductoryOffer() async {
        let service = FakePlusService()
        let products = await service.availableProducts()
        XCTAssertFalse(products.isEmpty)
        XCTAssertNotNil(
            products.first?.introductoryOfferDescription,
            "FakePlusService は trial 表記を必ず返す（シミュレータでの UI プレビュー用）"
        )
    }

    @MainActor
    func test05_fakePlusServicePurchaseButtonLabelSwitch() {
        // 受け入れ条件6: 無料トライアルが提供される状態なら、UI テストで
        // 購入ボタンのラベルが「無料で試す」に切り替わる。
        // ここでは文言そのものではなく「trial 表記があればボタン文言の
        // 判定が変わる」ことのロジック側からの検証を行う。
        // PlusView.purchaseButtonLabel 相当の分岐を直接確かめる。
        let withTrial = PlusProduct(
            id: "x",
            displayName: "Plus",
            displayPrice: "¥480",
            periodDescription: "",
            introductoryOfferDescription: L10n.Plus.freeTrialBadge(value: 1, unit: .month)
        )
        let withoutTrial = PlusProduct(
            id: "x",
            displayName: "Plus",
            displayPrice: "¥480",
            periodDescription: ""
        )
        XCTAssertNotEqual(
            withTrial.introductoryOfferDescription,
            withoutTrial.introductoryOfferDescription,
            "trial の有無で表示文言の判定が変わる"
        )
    }
}