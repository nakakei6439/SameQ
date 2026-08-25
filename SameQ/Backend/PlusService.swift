import Foundation

/// アプリが課金を扱うための抽象（F28 / F29 / F30 / F31）。
///
/// 仕様の「RevenueCat」指定に対し、本スプリントでは **StoreKit 2 を直接使う**
/// 実装（`StoreKitPlusService`）で動かす。プロジェクトの方針として外部パッケージ
/// 依存を持たないためで、`PlusService` プロトコルを境界に、将来
/// `RevenueCat.Purchases.shared` へ差し替えても UI 層やテストに影響しないようにしてある。
///
/// テストでは `FakePlusService` を使い、`@MainActor` 経由で購入・復元を確定的に再現する。
@MainActor
protocol PlusService: AnyObject, Sendable {
    /// 購入可能な Plus 商品（SKU）を返す。デバッグや初回ロード前は空配列でもよい。
    func availableProducts() async -> [PlusProduct]

    /// 現在の Plus エンタイトルメント。`isActive == true` のとき Plus とみなす。
    /// `nil` または空でも構わない（購入前は普通そうなる）。
    func currentEntitlement() async -> PlusEntitlement?

    /// 指定した `PlusProduct` の購入を申し込む。
    /// 成功時は新しいエンタイトルメントを返す。失敗時は `PlusPurchaseError` を投げる。
    func purchase(_ product: PlusProduct) async throws -> PlusEntitlement

    /// 購入復元（過去に App Store / StoreKit 側で決済済みのものを引き戻す）。
    /// 成功時は見つかった最新のエンタイトルメントを返す。何もなければ `nil`。
    func restore() async throws -> PlusEntitlement?
}

/// 課金のための SKU。`Plus` はサブスクリプション 1 種類だけを扱う前提で、
/// 商品 ID 文字列と表示情報（価格・ローカライズ済み）を保持する。
struct PlusProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    /// 月額の表示用。1ヶ月あたりの金額（`displayPrice` は StoreKit が返す月額料金で、
    /// 毎年更新の場合は年額のまま返す）。本スプリントでは月額の表示のみを使う。
    let periodDescription: String
}

/// Plus のエンタイトルメント（F28）。期限が切れると `isActive == false` に戻る。
struct PlusEntitlement: Equatable, Codable, Sendable {
    /// 商品 ID。サブスクリプション停止や更新の追跡に使う。
    let productID: String
    /// エンタイトルメントが有効になった時刻。永続化で「いつから」を見せる用途。
    let purchasedAt: Date
    /// 現在の購読期間（または猶予期間）が終わる時刻。これを過ぎると `isActive == false`。
    let expiresAt: Date

    /// `now` の時点で購読期間内なら `true`。猶予期間（グレース）も購読中扱い。
    func isActive(at now: Date) -> Bool {
        now < expiresAt
    }
}

/// `PlusService.purchase(_:)` / `restore()` が投げるエラー。
enum PlusPurchaseError: LocalizedError, Equatable {
    /// ユーザーが購入フローを途中でキャンセルした。
    case userCancelled
    /// ネットワーク障害など一時的な失敗。UI はリトライ可能。
    case network
    /// 商品が見つからない（アプリと App Store Connect の設定不一致など）。
    case productNotFound
    /// その他。`detail` は元のエラーの短い説明。
    case other(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "購入をキャンセルしました。"
        case .network:
            return "通信に問題がありました。電波状況を確認してもう一度お試しください。"
        case .productNotFound:
            return "Plus の商品情報を読み込めませんでした。"
        case .other(let detail):
            return "購入に失敗しました（\(detail)）。"
        }
    }
}
