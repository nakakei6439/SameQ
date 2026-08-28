import Foundation

/// アプリのバージョン表示ヘルパー（新機能）。
///
/// `Bundle.main.infoDictionary` から `CFBundleShortVersionString`（例: "1.0"）と
/// `CFBundleVersion`（ビルド番号、例: "1"）を読み、"v1.0 (1)" 形式にまとめる。
/// `MenuView` 下部のキャプションに使い、ユーザーが「更新されたかどうか」を
/// あとから見分けられるようにする。
enum AppVersion {
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// 例: "v1.0 (1)"
    static var displayString: String { "v\(shortVersion) (\(buildNumber))" }
}
