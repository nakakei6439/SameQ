import XCTest
@testable import SameQ

/// スプリント11（F34）の安全ログ保持期間と自動削除を、データ層で押さえる。
///
/// UI 側の操作は自動化しづらい（30 日待つ必要がある）ので、`AppClock` の offset で
/// 「postExpiresAt + N 日後」を疑似再現する。
/// `LaunchOptions.safetyLogRetentionSeconds` を短くすることでテストを高速に回す。
final class SafetyLogRetentionTests: XCTestCase {

    private let storeFileName = "safety-log-test-state.json"

    private func makeStore() -> LocalStore {
        let store = LocalStore(fileName: storeFileName)
        try? store.save(.empty)
        return store
    }

    private func makeSchedule(
        reference: Date,
        expiresIn: TimeInterval
    ) -> (PromptSchedule, Prompt) {
        let prompt = Prompt(
            id: "p1",
            text: "1つ目のお題",
            startsAt: reference.addingTimeInterval(-3600),
            endsAt: reference.addingTimeInterval(expiresIn - 3600)
        )
        var posts: [Post] = []
        for index in 0..<3 {
            posts.append(
                Post(
                    id: UUID(),
                    promptID: prompt.id,
                    authorID: UUID(),
                    authorEmoji: "🐢",
                    authorNickname: "Other #\(index)",
                    body: "他の人の回答 #\(index)",
                    bodyLanguage: "ja",
                    createdAt: prompt.startsAt.addingTimeInterval(Double(index) * 60),
                    expiresAt: prompt.endsAt
                )
            )
        }
        return (PromptSchedule(prompts: [prompt], posts: posts), prompt)
    }

    private func makeBackend(
        store: LocalStore,
        schedule: PromptSchedule,
        offset: TimeInterval = 0,
        retention: TimeInterval = 0
    ) -> LocalBackend {
        var options = LaunchOptions()
        options.safetyLogRetentionSeconds = retention
        return LocalBackend(
            store: store,
            clock: AppClock(offset: offset),
            schedule: schedule,
            options: options
        )
    }

    /// 30 日未満では通報の記録が残る（受け入れ条件6）。
    func testReportSurvivesPostExpiryUntilRetentionExpires() async throws {
        let reference = Date()
        let store = makeStore()
        // postExpiresAt = reference + (defaultDuration - 3600) = +27h
        let (schedule, prompt) = makeSchedule(reference: reference, expiresIn: Prompt.defaultDuration)
        let backend = makeBackend(store: store, schedule: schedule, offset: 0)

        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        guard case .post(let reported) = try await backend.nextTimelinePost(promptID: prompt.id) else {
            return XCTFail("通報対象が引けない")
        }
        try await backend.reportPost(postID: reported.id, reason: .discrimination)

        // 1) 通報直後: 記録されている
        let countAtFirst = try await backend.reportedPostIDs().count
        XCTAssertEqual(countAtFirst, 1)

        // 2) 投稿の表示期限を 1 日過ぎただけ: まだ残る（F34）。
        // retention を 30 日にしてテストを高速化、offset は postExpiresAt から 1日後へ。
        let oneDayAfterExpiry = prompt.endsAt.addingTimeInterval(24 * 60 * 60).timeIntervalSince(reference)
        let mid = LocalBackend(
            store: store,
            clock: AppClock(offset: oneDayAfterExpiry),
            schedule: schedule,
            options: makeOptions(retention: 30 * 24 * 60 * 60)
        )
        // `reportedPostIDs` は `pruneExpired` を呼ぶので、ここで確認できる。
        let countAfter1Day = try await mid.reportedPostIDs().count
        XCTAssertEqual(countAfter1Day, 1, "期限切れ1日後でも残る")
    }

    /// 投稿期限 + 30 日 経過で通報が削除される（受け入れ条件6）。
    func testReportAutoDeletes30DaysAfterPostExpiry() async throws {
        let reference = Date()
        let store = makeStore()
        let (schedule, prompt) = makeSchedule(reference: reference, expiresIn: Prompt.defaultDuration)
        let backend = makeBackend(store: store, schedule: schedule)

        try await backend.createAnonymousUser(emoji: "🌙", nickname: nil)
        guard case .post(let reported) = try await backend.nextTimelinePost(promptID: prompt.id) else {
            return XCTFail("通報対象が引けない")
        }
        try await backend.reportPost(postID: reported.id, reason: .discrimination)

        // 30 日 + 1 秒 後に移動して `pruneExpired` をトリガ
        let after30Days = prompt.endsAt.addingTimeInterval(30 * 24 * 60 * 60 + 1).timeIntervalSince(reference)
        let future = LocalBackend(
            store: store,
            clock: AppClock(offset: after30Days),
            schedule: schedule,
            options: makeOptions(retention: 30 * 24 * 60 * 60)
        )
        let countAfter30Days = try await future.reportedPostIDs().count
        XCTAssertEqual(countAfter30Days, 0, "期限切れ+30日経過で自動削除")
    }

    /// テスト用に保持期間を上書きした `LaunchOptions` を作る（DEBUG ガードの影響を受けない）。
    private func makeOptions(retention: TimeInterval) -> LaunchOptions {
        var options = LaunchOptions()
        options.safetyLogRetentionSeconds = retention
        return options
    }

    /// `Report.postExpiresAt` が `createdAt + 28h` のフォールバックで読めること
    ///（schemaVersion 5 の永続ファイルを読み込んだとき用）。
    func testReportDecodesLegacyStateWithoutPostExpiresAt() async throws {
        // schemaVersion 5 のレポートを直接作って JSON 化 → デコード。
        let legacyReport = Report(
            id: UUID(),
            postID: UUID(),
            reason: .other,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            postExpiresAt: Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(28 * 60 * 60)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacyReport)

        // `postExpiresAt` キーを除いた JSON を作って、フォールバック発動を確認する。
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json.removeValue(forKey: "postExpiresAt")
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Report.self, from: strippedData)
        let expectedFallback = Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(28 * 60 * 60)
        XCTAssertEqual(decoded.postExpiresAt, expectedFallback, "postExpiresAt 欠落時は createdAt + 28h")
    }

    /// schemaVersion 6 の永続化ファイルは 6 で保存される。
    func testSchemaVersionBumpedToSix() {
        let store = LocalStore(fileName: "schema-version-test-state.json")
        try? store.save(.empty)
        let loaded = store.load()
        XCTAssertEqual(loaded.schemaVersion, PersistedState.currentSchemaVersion)
        XCTAssertEqual(loaded.schemaVersion, 6, "schemaVersion を 6 にバンプ")
    }
}