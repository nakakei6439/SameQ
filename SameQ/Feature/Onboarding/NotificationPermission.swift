import Foundation
import UserNotifications

/// 通知の許可ダイアログを出すだけの薄い入れ物。
/// スプリント01では許可を求めるところまでで、通知の予約・配信は行わない（F24 はスプリント08）。
enum NotificationPermission {
    @discardableResult
    static func request() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
