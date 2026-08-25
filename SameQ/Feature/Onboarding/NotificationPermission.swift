import Foundation
import UserNotifications

/// 通知の許可状態取得とダイアログ表示をまとめる薄い入れ物（F24 / F25）。
///
/// スプリント01では許可を求めるところまでで、通知の予約・配信は行わなかった
/// （F24 はスプリント08）。スプリント08で実際の `UNUserNotificationCenter` への
/// 登録を `NotificationScheduler` に切り出したので、このファイルは UI 側
/// （オンボーディング・設定画面）が「許可状態を聞く／要求する」ための薄い
/// ラッパとして残してある。
enum NotificationPermission {
    /// OS に通知許可を要求する。エラーを握りつぶして `Bool` を返すのは、
    /// 「拒否された」「失敗した」をユーザーには等価に扱って次へ進めるため
    /// （F25「通知を拒否した場合もアプリは通常どおり利用でき」）。
    @discardableResult
    static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// 現在の許可状態を `NotificationAuthorizationStatus` で返す。
    /// 設定画面が「いま拒否されています」案内を出すか判定するために使う。
    static func currentStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }
}
