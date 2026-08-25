import Foundation

/// テストと Debug 限定起動引数 `-SameQFakePlus` で使うフェイク実装。
///
/// `PlusService` プロトコルの振る舞いをそのまま置き換え、`setPlusActive(_:)` で
/// 任意の `Bool` を切り替えられるようにした。`availableProducts()` は月額 480 円の
/// `Monthly Plus` を1件だけ返す。`purchase(_)` はユーザーが即購入できる扱い、
/// `restore()` はフェイクが覚えている最新のエンタイトルメントを返す。
///
/// 実機やサンドボックス購入の代わりに、UI テストで「Plus 購入後の振る舞い」を
/// 確実に再現するために使う（F28 / F29 / F30 / F31 の受け入れ条件を満たす検証用）。
///
/// **永続化**（attempt 2: eval-1.md [1] の修正）:
/// `lastEntitlement` は `UserDefaults` のキー `FakePlusService.lastEntitlementKey` に
/// 保存され、アプリを再起動しても引き継がれる。`StoreKitPlusService` が
/// `AppStore.sync()` + `Transaction.currentEntitlements` で OS 側に永続化されるのと
/// 対比すると、`FakePlusService` は `UserDefaults` に保存することで
///「アプリを削除して入れ直しても『購入を復元』で Plus 状態が戻る」
///（spec.md 268行）の振る舞いを Debug 経路でも再現できるようにする。
/// Release ビルド（`-SameQFakePlus` が付かない経路）では `StoreKitPlusService` が
/// 使われるので、この `UserDefaults` の値は影響しない。
@MainActor
final class FakePlusService: PlusService, ObservableObject {
    /// `UserDefaults` にエンタイトルメントを保存するときのキー（attempt 2）。
    /// `StoreKitPlusService` が Release で動く経路では参照されないので、
    /// この定数は Debug 限定の実装詳細として置いてある。
    static let lastEntitlementKey = "FakePlusService.lastEntitlement.v1"

    /// 現在の Plus 状態。手動で切り替えられるように公開する。
    @Published private(set) var active: Bool
    /// 最後に確定したエンタイトルメント。`active == true` のあいだは `non-nil`。
    /// `purchase()` / `setPlusActive(_:)` で更新され、変更のたびに
    /// `UserDefaults`（`FakePlusService.lastEntitlementKey`）へ保存される
    ///（attempt 2: eval-1.md [1] の修正）。
    private var lastEntitlement: PlusEntitlement? {
        didSet { Self.persist(lastEntitlement, defaults: defaults) }
    }

    /// 商品 ID。StoreKit 実装と揃える（F28）。
    private let monthlyProductID = "com.nakakei6439.SameQ.plus.monthly"

    /// `UserDefaults` のバックエンド。テストで独立したキースペースを
    /// 用意できるよう差し替え可能にしておく（attempt 2）。
    private let defaults: UserDefaults

    init(active: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `FakePlusService` は StoreKit 2 の `Transaction.currentEntitlements` と
        // 同じ「購入を復元するまで永続化済みエンタイトルメントを露出しない」
        // 振る舞いをする（attempt 2: eval-1.md [1] の修正）。
        //
        // つまり:
        // - 起動直後は `active == false` のフリをして、ヘッダの `Plus` ラベルや
        //   設定画面のステータス文言は無料ユーザー向けの表示のままになる。
        // - 「購入を復元」が押されると `restore()` が永続化された
        //   エンタイトルメントを引き戻し、その瞬間に `active == true` へ戻る。
        //
        // これにより `StoreKitPlusService`（実機／Sandbox）と FakePlusService（Debug）が
        // 同じ UI シーケンスを踏む。「購入を復元」は purchasedAt が永続化されている
        // ことの**確認**であり、`StoreKitPlusService` の `AppStore.sync()` 相当の
        // 「引き直し」を `FakePlusService.restore()` が担う。
        self.active = active
        if active {
            let now = Date()
            let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
                ?? now.addingTimeInterval(60 * 60 * 24 * 30)
            // 永続化は `lastEntitlement` の `didSet` で行う。
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
        // 永続化は `lastEntitlement` の `didSet` で行う（attempt 2）。
        lastEntitlement = entitlement
        active = true
        return entitlement
    }

    func restore() async throws -> PlusEntitlement? {
        // 永続化済みのエンタイトルメントを引き戻す（attempt 2: eval-1.md [1] の修正）。
        // `init` 時点ではまだ読み込まず、`restore()` が呼ばれた瞬間に UserDefaults を
        // 見に行く。これは `StoreKitPlusService.restore()` が `AppStore.sync()` を呼んで
        // OS 側のトランザクション履歴と再同期するのと同じ役割で、
        // 受け入れ条件6「購入を復元で Plus 状態が戻る」の確定的な再現点になっている。
        guard let persisted = Self.loadPersisted(defaults: defaults),
              persisted.expiresAt >= Date() else {
            // 期限切れや永続化なしは復元失敗。`active` を `false` のままにして
            // 念のため UserDefaults の値も片付ける（古い値の温存を避けるため）。
            if Self.loadPersisted(defaults: defaults) != nil {
                Self.persist(nil, defaults: defaults)
            }
            return nil
        }
        // 永続化は `lastEntitlement` の `didSet` で行う。
        lastEntitlement = persisted
        active = true
        return persisted
    }

    /// Debug / UI テスト用に状態を直接切り替えるためのフック。
    /// `purchase(_:)` と異なり期限も `30日後` で固定。
    func setPlusActive(_ active: Bool) {
        if active {
            let now = Date()
            let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)
                ?? now.addingTimeInterval(60 * 60 * 24 * 30)
            // 永続化は `lastEntitlement` の `didSet` で行う（attempt 2）。
            lastEntitlement = PlusEntitlement(
                productID: monthlyProductID,
                purchasedAt: now,
                expiresAt: expires
            )
        } else {
            // 永続化は `lastEntitlement` の `didSet` で行う（attempt 2）。
            lastEntitlement = nil
        }
        self.active = active
    }

    // MARK: - 永続化ヘルパー（attempt 2: eval-1.md [1] の修正）

    /// `UserDefaults` に保存する。
    /// エンタイトルメントが無いときはキーごと削除する（古い値の温存を避けるため）。
    private static func persist(_ entitlement: PlusEntitlement?, defaults: UserDefaults = .standard) {
        if let entitlement {
            guard let data = try? Self.encoder.encode(entitlement) else { return }
            defaults.set(data, forKey: lastEntitlementKey)
        } else {
            defaults.removeObject(forKey: lastEntitlementKey)
        }
    }

    /// `UserDefaults` から読む。失敗時は `nil`。
    private static func loadPersisted(defaults: UserDefaults) -> PlusEntitlement? {
        guard let data = defaults.data(forKey: lastEntitlementKey) else { return nil }
        return try? Self.decoder.decode(PlusEntitlement.self, from: data)
    }

    /// エンタイトルメントの JSON コーデータ（attempt 2）。
    /// `PersistedState` と同じ ISO8601 / `sortedKeys` 形式に揃えておく。
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
