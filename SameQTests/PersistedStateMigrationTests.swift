import XCTest
@testable import SameQ

/// `PersistedState` のスキーマバージョン 6 → 7 移行テスト（スプリント12）。
///
/// `supabaseAuth` フィールドが追加されたが、既存ファイルには存在しないので
/// `decodeIfPresent` で `nil` にフォールバックする必要がある。
final class PersistedStateMigrationTests: XCTestCase {
    func test_schema6_missingSupabaseAuth_decodesAsNil() throws {
        // schemaVersion 6 の既存ファイル相当（supabaseAuth フィールドなし）。
        let oldJSON = """
        {
          "schemaVersion": 6,
          "user": null,
          "myPosts": [],
          "likedPostIDs": [],
          "viewedPostIDs": [],
          "reports": [],
          "blockedAuthors": [],
          "lastPostBody": null,
          "lastPrepareAttemptAt": {},
          "discardedCandidatesCount": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PersistedState.self, from: oldJSON)
        XCTAssertEqual(state.schemaVersion, 6)
        XCTAssertNil(state.supabaseAuth, "supabaseAuth キーが無い旧データは nil として読める")
        XCTAssertNil(state.user)
    }

    func test_schema7_withSupabaseAuth_decodesCorrectly() throws {
        let json = """
        {
          "schemaVersion": 7,
          "user": null,
          "myPosts": [],
          "likedPostIDs": [],
          "viewedPostIDs": [],
          "reports": [],
          "blockedAuthors": [],
          "lastPostBody": null,
          "lastPrepareAttemptAt": {},
          "discardedCandidatesCount": 0,
          "supabaseAuth": {
            "accessToken": "abc",
            "refreshToken": "def",
            "userID": "11111111-1111-1111-1111-111111111111",
            "createdAt": "2026-08-26T00:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PersistedState.self, from: json)
        XCTAssertEqual(state.schemaVersion, 7)
        XCTAssertNotNil(state.supabaseAuth)
        XCTAssertEqual(state.supabaseAuth?.accessToken, "abc")
        XCTAssertEqual(state.supabaseAuth?.refreshToken, "def")
        XCTAssertEqual(state.supabaseAuth?.userID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }

    func test_emptyState_hasCurrentSchemaVersion() {
        XCTAssertEqual(PersistedState.empty.schemaVersion, PersistedState.currentSchemaVersion)
        XCTAssertEqual(PersistedState.currentSchemaVersion, 7)
    }
}
