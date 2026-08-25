import Foundation
import UserNotifications

/// 通知の予約・取り消し・状態取得を抽象化する窓口（F24 / F25）。
///
/// `AppSession` が直接 `UNUserNotificationCenter` を触らないのは、
/// - テストでは偽の実装に差し替えて「予約された時刻が範囲内か」「許可状態に応じて
///   予約がスキップされるか」などを検証したい
/// - Release ビルドと Debug ビルドで挙動を変えたい（強制拒否・強制時刻など）
/// ため。`nil` を渡せば一切何もしない（既存ユニットテストの後方互換）。
protocol NotificationScheduling: Sendable {
    /// 現在の通知許可状態。UI 側はこの値で「設定からオンにしてね」案内を出すか決める。
    func authorizationStatus() async -> NotificationAuthorizationStatus

    /// 8:00〜22:00 の範囲のランダムな時刻に「次の1回」の通知を予約する。
    /// 既に予約済みのものがあれば取り消してから新しく1件だけ予約する
    /// （重複発火を避けるため）。
    /// - Parameter now: 「いま」。テストから注入できるよう引数で受け取る。
    /// - Parameter forceDenied: Debug 用。`true` のときは許可状態に関係なく何もしない。
    ///   拒否経路の検証に使う。`LiveNotificationScheduler` ではコンストラクタで固定した
    ///   `forceDeniedOverride` も同じ役割（許可状態も `.denied` として返す）。
    /// - Parameter forcedHour: Debug 用。`nil` 以外はその時（0〜23）で固定し、
    ///   分のランダム化はそのまま。境界値確認用。
    /// - Returns: 実際に予約した時刻（範囲内であることを示す）。予約しなかったときは nil
    ///   （拒否されている・許可ダイアログがまだ・対象時間外の日付など）。
    func scheduleNextRandomNotification(
        now: Date,
        timeZone: TimeZone,
        forceDenied: Bool,
        forcedHour: Int?
    ) async -> Date?
}

/// 許可状態の表示用（F25 設定画面の案内表示と、AppSession での予約判定に使う）。
///
/// `UNAuthorizationStatus` の 4 値を、画面に出す言葉に直結する形に丸める。
enum NotificationAuthorizationStatus: String, Sendable, Equatable {
    /// まだ聞いていない（オンボーディングで「許可する」を押す前）。
    case notDetermined
    /// ユーザーが許可した。
    case authorized
    /// 拒否された。
    case denied
    /// プロビジョニングプロファイル経由の特別な状態（ほぼ出ない）。
    case provisional
    /// 通知センターへの到達がシステム全体で止められている（機内モードなど）。
    case ephemeral
}

/// 8:00〜22:00 の範囲で「次に発火させたいローカル時刻」を選ぶ純粋関数。
///
/// 「日によって違う時刻になる」「8:00 前 / 22:00 後は選ばない」を満たすため、
/// 1日の中で 8:00〜21:59 の間のどこか（つまり 22:00 ちょうどを含まない）に置く。
/// 現在時刻が既に 22:00 を過ぎていたり、今日中にもう発火できる時刻が無い場合は
/// 翌日の 8:00 に送る。
///
/// `forcedHour` を渡すと時を固定できる（Debug 限定の起動引数 `-SameQNotificationHour`）。
/// 分のランダム化はそのまま残し、同一プロセス内で連続して呼んでも違う分が出ることだけ確認する。
enum NotificationTimePicker {
    /// 通知の最早時刻（8:00）。
    static let earliestHour = 8
    /// 通知の最遅時刻（22:00 ちょうどは含まない。21:59 が分秒上は最遅）。
    static let latestHour = 22
    /// テストから注入可能な乱数源。本番では `Int.random(in:)` を使う。
    typealias RandomMinuteGenerator = () -> Int

    /// 次に発火させたい `Date` を `Calendar.current`（`timeZone` で上書き可）で返す。
    ///
    /// - Parameters:
    ///   - now: 「いま」。
    ///   - calendar: テストから `Calendar(identifier: .gregorian)` などを差し込みやすいよう公開。
    ///   - randomMinute: テストから固定の分を返せるようにする。
    ///   - forcedHour: 強制したい時（0〜23）。`nil` のときは 8〜21 のランダム。
    /// - Returns: `Date` または「翌日以降の 8:00」。失敗しない（必ず候補があるため）。
    static func pickNextDate(
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone = .current,
        forcedHour: Int? = nil,
        randomMinute: RandomMinuteGenerator = { Int.random(in: 0...59) }
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone

        let hour = forcedHour ?? Int.random(in: earliestHour...(latestHour - 1))
        let minute = randomMinute()
        // 今日の (hour, minute) を組み立てて、それが now より後なら今日を返す。
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let candidate = calendar.date(from: components) ?? now
        if candidate > now {
            return candidate
        }
        // 今日の候補が既に過ぎている → 翌日の同時刻へ。
        // hour 自体をランダムで選んでいる場合、翌日も同じ時で構わない
        // （翌日の 8:00〜21:59 のランダムな (hour, minute) になる）。
        let tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: now.addingTimeInterval(86400))
        var tomorrowCandidateComponents = tomorrowComponents
        let tomorrowHour = forcedHour ?? Int.random(in: earliestHour...(latestHour - 1))
        let tomorrowMinute = randomMinute()
        tomorrowCandidateComponents.hour = tomorrowHour
        tomorrowCandidateComponents.minute = tomorrowMinute
        tomorrowCandidateComponents.second = 0
        return calendar.date(from: tomorrowCandidateComponents) ?? now.addingTimeInterval(86400)
    }
}

/// `NotificationScheduling` の本番実装。`UNUserNotificationCenter` を直接使う。
///
/// `AppSession` の `init` で既定として作られる。テストや Release ビルド以外で
/// 動かしたい場合は `LaunchOptions` 経由で「強制拒否」「強制時刻」を渡す。
final class LiveNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    /// 通知識別の固定キー。識別子を上書きすることで重複予約を避ける。
    static let dailyReminderIdentifier = "SameQ.dailyPromptReminder"

    /// 通知本文。端末言語を区別せず固定（深夜の言語切替にも耐えるよう短く）。
    static let notificationBody = "新しいお題が届きました"

    private let center: UNUserNotificationCenter
    /// `-SameQNotificationForceDenied`（Debug 限定）のとき true。許可状態・
    /// 予約ともにすべて「拒否」として振る舞う。
    private let forceDeniedOverride: Bool

    init(center: UNUserNotificationCenter = .current(), forceDenied: Bool = false) {
        self.center = center
        self.forceDeniedOverride = forceDenied
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        if forceDeniedOverride { return .denied }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .notDetermined
        }
    }

    func scheduleNextRandomNotification(
        now: Date,
        timeZone: TimeZone,
        forceDenied: Bool,
        forcedHour: Int?
    ) async -> Date? {
        // 拒否状態では予約しない（F25「通知を拒否した場合もアプリは通常どおり利用でき」）。
        // 設定画面で案内だけ出す。デバッグ用の `forceDenied` もここで弾く。
        if forceDenied {
            await cancelAllPending()
            return nil
        }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            await cancelAllPending()
            return nil
        }
        let fireDate = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: Calendar.current,
            timeZone: timeZone,
            forcedHour: forcedHour
        )
        await cancelAllPending()
        let content = UNMutableNotificationContent()
        content.title = Self.notificationBody
        content.body = Self.notificationBody
        content.sound = .default
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        // repeating: false → 1回限りの発火。発火後は `scheduleNextRandomNotification` を
        // 次の起動 / プロンプト切替時に再実行することで「日によって違う時刻」になる。
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return fireDate
        } catch {
            return nil
        }
    }

    /// 既存の SameQ 通知を全て取り消す（再予約時の重複発火防止）。
    func cancelAllPending() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyReminderIdentifier])
    }
}

/// テスト用の偽実装。`AppSession` の init に渡して、副作用を伴わず
/// 「何時に予約したか」「許可状態は何か」を記録するだけにする。
///
/// アクターとして実装して並行呼び出しからも安全にする（Swift 6 言語モードでの
/// async context 内の NSLock 警告を避ける）。
actor FakeNotificationScheduler: NotificationScheduling {
    private(set) var status: NotificationAuthorizationStatus
    private(set) var lastScheduledAt: Date?
    private(set) var scheduledDates: [Date] = []
    private(set) var scheduleCallCount: Int = 0

    init(initialStatus: NotificationAuthorizationStatus = .notDetermined) {
        self.status = initialStatus
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func setStatus(_ status: NotificationAuthorizationStatus) {
        self.status = status
    }

    func scheduleNextRandomNotification(
        now: Date,
        timeZone: TimeZone,
        forceDenied: Bool,
        forcedHour: Int?
    ) async -> Date? {
        scheduleCallCount += 1
        if forceDenied { return nil }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return nil
        }
        let fireDate = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: Calendar.current,
            timeZone: timeZone,
            forcedHour: forcedHour
        )
        lastScheduledAt = fireDate
        scheduledDates.append(fireDate)
        return fireDate
    }
}
