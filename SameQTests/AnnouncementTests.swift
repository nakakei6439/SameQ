import XCTest
@testable import SameQ

/// F44 / スプリント18「運営お知らせ」機能で使う `Announcement` モデルの
/// 単体テスト。Codable ラウンドトリップと `LocalBackend.announcements()` の
/// 固定サンプルを確認する。
final class AnnouncementTests: XCTestCase {

    func test01_announcementCodableRoundTrip() throws {
        let original = Announcement(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "新機能を追加しました",
            body: "本日より、新しい画面が追加されました。",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(Announcement.self, from: data)

        XCTAssertEqual(restored, original, "Codable ラウンドトリップで情報が落ちない")
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.body, original.body)
        XCTAssertEqual(
            restored.publishedAt.timeIntervalSince1970,
            original.publishedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func test02_announcementIsIdentifiable() {
        // `Announcement` が `Identifiable` に準拠していることは `ForEach` で
        // そのまま使えることの最小確認。
        let a = Announcement(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "t1",
            body: "b1",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let b = Announcement(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "t2",
            body: "b2",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.id.uuidString, "00000000-0000-0000-0000-000000000001")
    }

    func test03_localBackendAnnouncementsReturnsSample() async throws {
        let backend = LocalBackend()
        let items = try await backend.announcements()
        XCTAssertFalse(items.isEmpty, "オフライン開発用に最低1件返す")
        XCTAssertEqual(items.first?.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertFalse(items.first?.title.isEmpty ?? true)
        XCTAssertFalse(items.first?.body.isEmpty ?? true)
    }
}