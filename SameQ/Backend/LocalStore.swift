import Foundation

/// 端末に永続化する内容。アカウント・自分の回答・自分のいいねだけを持つ。
/// 他人の回答は同梱シード（`SeedCatalog`）側にあるので保存しない。
struct PersistedState: Codable, Sendable {
    var schemaVersion: Int
    var user: AppUser?
    var myPosts: [Post]
    var likedPostIDs: [UUID]

    static let currentSchemaVersion = 1

    static let empty = PersistedState(
        schemaVersion: currentSchemaVersion,
        user: nil,
        myPosts: [],
        likedPostIDs: []
    )
}

/// `PersistedState` を JSON 1ファイルとして読み書きする。
///
/// 書き込みは常に「まるごと1回で置き換える」。初回設定の途中で落ちても
/// 中途半端なアカウントが残らないように、保存はアカウント確定時にしか呼ばない。
struct LocalStore: Sendable {
    private let fileURL: URL

    init(fileName: String = "state.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("SameQ", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let state = try? Self.decoder.decode(PersistedState.self, from: data) else {
            // 壊れたファイルを読んで起動不能になるより、初回設定からやり直す方が安全。
            return .empty
        }
        return state
    }

    func save(_ state: PersistedState) throws {
        do {
            let data = try Self.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw BackendError.storageFailure(error.localizedDescription)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
