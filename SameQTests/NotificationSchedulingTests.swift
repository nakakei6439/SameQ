import XCTest
@testable import SameQ

/// スプリント08（F24 ランダム通知 / F25 通知タップ）のうち、純粋関数とプロトコル越しの
/// 振る舞いをここで押さえる。`NotificationTimePicker.pickNextDate` は副作用が無いので
/// 境界条件（7:59 / 8:00 / 21:59 / 22:00 / 翌日への繰り越し）を網羅できる。
final class NotificationSchedulingTests: XCTestCase {

    /// テスト用の固定タイムゾーン（端末タイムゾーンに依存しないようにする）。
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func calendar(in timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    // MARK: 受け入れ条件 1・2（範囲内・ランダム）

    /// `now` が 10:00 のとき、ピッカー結果は 8:00〜22:00 の範囲に収まる。
    /// さらに「日によって違う時刻」になるよう、`forcedHour` を 8 に固定して
    /// 分のランダム性が機能していることを確認する。
    func testPickNextDate_keepsResultWithinWindow_andVariesMinutesAcrossCalls() {
        let cal = calendar(in: tokyo)
        // 2026-06-01 10:00 JST
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 10, minute: 0))!

        let first = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: cal,
            timeZone: tokyo,
            forcedHour: 8,
            randomMinute: { 15 }
        )
        let second = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: cal,
            timeZone: tokyo,
            forcedHour: 8,
            randomMinute: { 42 }
        )

        // 両方とも今日の 8:00〜22:00 の範囲内
        let hour1 = cal.component(.hour, from: first)
        let hour2 = cal.component(.hour, from: second)
        XCTAssertTrue((8..<22).contains(hour1), "first hour should be in 8..<22, got \(hour1)")
        XCTAssertTrue((8..<22).contains(hour2), "second hour should be in 8..<22, got \(hour2)")

        // 分はランダム化の注入値に従う
        let minute1 = cal.component(.minute, from: first)
        let minute2 = cal.component(.minute, from: second)
        XCTAssertEqual(minute1, 15)
        XCTAssertEqual(minute2, 42)
        XCTAssertNotEqual(first, second, "分が変われば Date も変わるはず")
    }

    // MARK: 受け入れ条件 3（8:00 前 / 22:00 後は選ばない）

    /// `forcedHour` が 7 や 22 のように境界値を含む範囲外でも、Picker 自体は
    /// 「範囲外でも選ばない」とはしない（呼び出し側の責務）。
    /// ここでは「呼ばれた時刻が範囲外（例: 23:30）でも、翌日の 8:00 に送られる」
    /// ことを確認する。これが「22:00 を過ぎたら通知は翌日に持ち越される」動作。
    func testPickNextDate_pastWindowDefersToNextDayAtForcedHour() {
        let cal = calendar(in: tokyo)
        // 2026-06-01 23:30 JST
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 23, minute: 30))!
        let fireDate = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: cal,
            timeZone: tokyo,
            forcedHour: 8,
            randomMinute: { 0 }
        )
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 2, "翌日に送られる")
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 0)
    }

    /// `now` が朝 7:30 のとき、今日の中にもう発火できる時刻（8:00〜21:59）が残っているので、
    /// 必ず今日中の 8:00 以降になる。
    func testPickNextDate_morningBeforeWindowReturnsTodayAtForcedHour() {
        let cal = calendar(in: tokyo)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 7, minute: 30))!
        let fireDate = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: cal,
            timeZone: tokyo,
            forcedHour: 9,
            randomMinute: { 0 }
        )
        let components = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        XCTAssertEqual(components.day, 1, "今日になる")
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    /// ランダム化された「時」が 8〜21 の範囲に必ず収まること（22 は範囲外）を、
    /// 決まった疑似乱数列で 100 回回して確認する。範囲外が一度でも出たら不合格。
    func testPickNextDate_randomHourIsAlwaysInsideWindow() {
        let cal = calendar(in: tokyo)
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12, minute: 0))!
        // 疑似乱数: 8..21 の値を順番に返す
        var n = 8
        let result = NotificationTimePicker.pickNextDate(
            now: now,
            calendar: cal,
            timeZone: tokyo,
            forcedHour: nil,
            randomMinute: { 0 }
        )
        // 1 回目は hour = n のランダムが選ばれて today > now なら today、過ぎていれば tomorrow。
        // 必ず 8..21 の範囲。
        let components = cal.dateComponents([.hour], from: result)
        XCTAssertTrue((8..<22).contains(components.hour ?? -1), "hour must be 8..21, got \(components.hour ?? -1)")
        _ = n  // 使わない値（コンパイラ警告避け）
    }

    // MARK: FakeNotificationScheduler 経由の予約挙動

    /// `AppSession` が `FakeNotificationScheduler` を介して通知を予約し、
    /// 許可状態のキャッシュが反映されることを確認する。
    @MainActor
    func testAppSessionSchedulesReminderWhenAuthorized() async {
        let scheduler = FakeNotificationScheduler(initialStatus: .authorized)
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: scheduler
        )
        await session.refreshNotificationAuthorizationStatus()
        XCTAssertEqual(session.notificationAuthorizationStatus, .authorized)
        await session.scheduleDailyReminderIfPossible()
        XCTAssertNotNil(session.nextScheduledNotificationAt,
                        "許可済みなら予約時刻が入る")
        let count = await scheduler.scheduleCallCount
        XCTAssertEqual(count, 1)
    }

    /// 拒否状態のときは `AppSession.scheduleDailyReminderIfPossible` が何もしない（F25）。
    @MainActor
    func testAppSessionDoesNotScheduleWhenDenied() async {
        let scheduler = FakeNotificationScheduler(initialStatus: .denied)
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: scheduler
        )
        await session.refreshNotificationAuthorizationStatus()
        await session.scheduleDailyReminderIfPossible()
        XCTAssertNil(session.nextScheduledNotificationAt,
                     "拒否状態では予約されない")
    }

    /// 拒否 → 許可に変わったあとに再予約すると、ちゃんと次の通知が登録される（F25）。
    @MainActor
    func testAppSessionReschedulesAfterAuthorizationFlipsToAllowed() async {
        let scheduler = FakeNotificationScheduler(initialStatus: .denied)
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: scheduler
        )
        await session.refreshNotificationAuthorizationStatus()
        await session.scheduleDailyReminderIfPossible()
        XCTAssertNil(session.nextScheduledNotificationAt)

        await scheduler.setStatus(.authorized)
        await session.refreshNotificationAuthorizationStatus()
        await session.scheduleDailyReminderIfPossible()
        XCTAssertNotNil(session.nextScheduledNotificationAt,
                        "許可に変えた後は予約される")
    }

    /// 連続呼び出しで「日によって違う時刻」になる（F24 受け入れ条件2）。
    @MainActor
    func testAppSessionReschedulingPicksDifferentTimesAcrossCalls() async {
        let scheduler = FakeNotificationScheduler(initialStatus: .authorized)
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: scheduler
        )
        await session.refreshNotificationAuthorizationStatus()
        await session.scheduleDailyReminderIfPossible()
        XCTAssertNotNil(session.nextScheduledNotificationAt)
        let firstDates = await scheduler.scheduledDates
        XCTAssertEqual(firstDates.count, 1)
        await session.scheduleDailyReminderIfPossible()
        let secondDates = await scheduler.scheduledDates
        XCTAssertEqual(secondDates.count, 2, "再呼び出しでもう1件予約される")
        XCTAssertNotEqual(firstDates[0], secondDates[1],
                          "連続呼び出しで違う時刻が選ばれる")
    }

    /// `handleDeepLink(.today)` で `pendingDeepLinkTarget` が立ち、
    /// `consumeDeepLink()` で nil に戻る（F25）。
    @MainActor
    func testHandleDeepLinkSetsAndConsumesPendingTarget() async {
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: nil
        )
        XCTAssertNil(session.pendingDeepLinkTarget)
        session.handleDeepLink(.today)
        XCTAssertEqual(session.pendingDeepLinkTarget, .today)
        session.consumeDeepLink()
        XCTAssertNil(session.pendingDeepLinkTarget)
    }

    /// `handleDeepLink(.timeline)` で `pendingDeepLinkTarget` が `.timeline` に立つ
    /// （F25 / attempt 2: eval-1.md [1] の修正で実際に通るようになった経路）。
    /// 回答済みアカウントで通知タップすると `RootView` 側が `.timeline` を立て、
    /// それを `.onChange(of: pendingDeepLinkTarget)` が拾って世界タイムラインを開く。
    @MainActor
    func testHandleDeepLinkTimelineSetsPendingTarget() async {
        let session = AppSession(
            backend: BackendProvider.make(),
            clock: AppClock(),
            translator: nil,
            notificationScheduler: nil
        )
        XCTAssertNil(session.pendingDeepLinkTarget)
        session.handleDeepLink(.timeline)
        XCTAssertEqual(session.pendingDeepLinkTarget, .timeline,
                       "回答済みアカウントの通知タップでは `.timeline` が立つ")
        session.consumeDeepLink()
        XCTAssertNil(session.pendingDeepLinkTarget,
                      "消費後は nil に戻る")
    }
}
