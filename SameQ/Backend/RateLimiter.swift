import Foundation

/// 短時間の連打を検知する単純なスライディングウィンドウのカウンタ（F17）。
///
/// `window` 秒以内に `maxActions` 回を超えたら、`cooldown` 秒のあいだ拒否する。
/// サーバーを持たないので端末（プロセス）内だけの判定。アプリを再起動すればリセットされる。
/// `attempt(at:)` は `Date` を受け取る純粋な計算なので、実時間を待たずにテストできる。
struct RateLimiter: Sendable {
    let maxActions: Int
    let window: TimeInterval
    let cooldown: TimeInterval

    private var timestamps: [Date] = []
    private var lockedUntil: Date?

    init(maxActions: Int, window: TimeInterval, cooldown: TimeInterval) {
        self.maxActions = maxActions
        self.window = window
        self.cooldown = cooldown
    }

    /// 許可されればその場で記録して `nil` を返す。
    /// 制限中なら、あと何秒で解除されるか（切り上げ・最低1秒）を返す。
    mutating func attempt(at now: Date) -> Int? {
        if let lockedUntil, now < lockedUntil {
            return max(1, Int(ceil(lockedUntil.timeIntervalSince(now))))
        }
        lockedUntil = nil
        let window = self.window
        timestamps.removeAll { now.timeIntervalSince($0) > window }

        guard timestamps.count < maxActions else {
            let until = now.addingTimeInterval(cooldown)
            lockedUntil = until
            // ロックした時点で記録を空にする。`cooldown` が明けたときに真っさらな状態から
            // 再開できるようにするため（`window` が `cooldown` より長いと、消さない限り
            // クールダウンが明けた直後にまた同じ古い記録で再ロックされてしまう）。
            timestamps.removeAll()
            return max(1, Int(ceil(cooldown)))
        }
        timestamps.append(now)
        return nil
    }
}

/// `RateLimiter` の閾値（`LaunchOptions` から渡す）。
struct RateLimitSettings: Sendable {
    var maxActions: Int
    var windowSeconds: TimeInterval
    var cooldownSeconds: TimeInterval

    func makeLimiter() -> RateLimiter {
        RateLimiter(maxActions: maxActions, window: windowSeconds, cooldown: cooldownSeconds)
    }
}
