import XCTest
@testable import SameQ

/// `PersistedState` のスキーマバージョン 6 → 7 → 8 移行テスト。
///
/// 6 → 7: `supabaseAuth` フィールドが追加されたが、既存ファイルには存在しないので
///         `decodeIfPresent` で `nil` にフォールバックする必要がある（スプリント12）。
///
/// 7 → 8: `languageEncounters` フィールド（F41・スプリント17）が追加されたが、
///         既存ファイルには存在しないので `decodeIfPresent` で空辞書へフォールバック
///         する必要がある。新しいカウンタは空状態から始まるため、pre-fetch は
///         「出会った言語が1つも無い」状態と同じ振る舞いになる。
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
        XCTAssertEqual(PersistedState.currentSchemaVersion, 9)
    }

    /// スプリント17（F41）: スキーマバージョン 7 の既存ファイル（`languageEncounters`
    /// フィールドが無い）を読み込んだとき、空辞書としてフォールバックする。
    /// `decodeIfPresent` が正しく機能していないと decode 自体が失敗するか、
    /// 実行時にクラッシュするため、新フィールド追加時の最低限の安全網。
    func test_schema7_missingLanguageEncounters_decodesAsEmpty() throws {
        let oldJSON = """
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
          "supabaseAuth": null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(PersistedState.self, from: oldJSON)
        XCTAssertEqual(state.schemaVersion, 7)
        XCTAssertTrue(
            state.languageEncounters.isEmpty,
            "languageEncounters キーが無い旧データは空辞書として読める"
        )
        XCTAssertNil(state.supabaseAuth)
    }
}
