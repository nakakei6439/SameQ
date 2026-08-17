import Foundation

/// 起動引数で切り替えられる検証用の設定。
///
/// 実時間で28時間待つ検証はできないので、お題の有効期間の切り替わりを
/// 数十秒〜数分で再現できるようにする。**すべて Debug ビルドでのみ効き**、
/// Release ビルドでは常に既定値（`live` シナリオ・時刻オフセットなし）になる。
///
/// 使える引数:
/// - `-SameQResetState`               保存済みの状態を捨てて初回設定からやり直す
/// - `-SameQScenario <名前>`          お題の日程シナリオ（`live` / `expiring` / `expired` / `upcoming`）
/// - `-SameQExpirySeconds <秒>`       `expiring` で現在のお題が終了するまでの秒数（既定 180）
/// - `-SameQGapSeconds <秒>`          `expiring` で終了から次のお題開始までの秒数（既定 180）
/// - `-SameQTimeOffsetMinutes <分>`   アプリが認識する「今」を前後にずらす（負値も可）
/// - `-SameQDebugOverlay`             画面下に現在時刻・お題ID・残り秒数を出す
struct LaunchOptions: Sendable {
    var resetsState: Bool = false
    var scenario: PromptScenario = .live
    var expirySeconds: TimeInterval = 180
    var gapSeconds: TimeInterval = 180
    var timeOffset: TimeInterval = 0
    var showsDebugOverlay: Bool = false

    /// このプロセスの設定。起動時に1度だけ解釈する。
    static let current = parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        #if DEBUG
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }

        options.resetsState = arguments.contains("-SameQResetState")
        options.showsDebugOverlay = arguments.contains("-SameQDebugOverlay")
        if let name = value(after: "-SameQScenario"), let scenario = PromptScenario(rawValue: name) {
            options.scenario = scenario
        }
        if let seconds = value(after: "-SameQExpirySeconds").flatMap(Double.init) {
            options.expirySeconds = seconds
        }
        if let seconds = value(after: "-SameQGapSeconds").flatMap(Double.init) {
            options.gapSeconds = seconds
        }
        if let minutes = value(after: "-SameQTimeOffsetMinutes").flatMap(Double.init) {
            options.timeOffset = minutes * 60
        }
        #endif
        return options
    }
}

/// アプリが認識する「今」。
///
/// お題の有効期間の判定はすべてここを通す。Debug ビルドでは
/// `-SameQTimeOffsetMinutes` の分だけずらせるので、期限切れ後の状態を待たずに確認できる。
struct AppClock: Sendable {
    let offset: TimeInterval

    init(offset: TimeInterval = LaunchOptions.current.timeOffset) {
        self.offset = offset
    }

    var now: Date { Date().addingTimeInterval(offset) }
}
