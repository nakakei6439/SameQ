import XCTest
@testable import SameQ

/// `SupabaseClient` の単体テスト。
///
/// 外部 SDK を使わず `URLSession` を直接扱う実装のため、
/// `URLProtocol` スタブでリクエスト／レスポンスを再現する。
final class SupabaseClientTests: XCTestCase {
    /// スタブ用 `URLProtocol`。指定したレスポンス（status, body）を返す。
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var response: (status: Int, body: Data, headers: [String: String]?)?
        nonisolated(unsafe) static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lastRequest = request
            guard let response = Self.response else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let urlResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers ?? ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        static func reset() {
            response = nil
            lastRequest = nil
        }
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    /// JSON 200 の GET 1 件をデコードできる。
    func test_get_decodesSingleObject() async throws {
        let body = """
        [{"id":"11111111-1111-1111-1111-111111111111","text":"hello","starts_at":"2026-08-26T00:00:00Z","ends_at":"2026-08-27T00:00:00Z","language":"ja"}]
        """.data(using: .utf8)!
        StubURLProtocol.response = (status: 200, body: body, headers: nil)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(
            session: session,
            tokenProvider: { "test-token" },
            restBaseURL: URL(string: "https://example.test/rest/v1")!,
            authBaseURL: URL(string: "https://example.test/auth/v1")!
        )

        struct Row: Decodable { let id: UUID; let text: String }
        let rows: [Row] = try await client.get(table: "prompts", filters: [:])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.text, "hello")
        // 認証ヘッダーが付いている
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertNotNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "apikey"))
    }

    /// 401 応答は `SupabaseError.unauthorized` を投げる。
    func test_get_unauthorizedThrows() async {
        StubURLProtocol.response = (status: 401, body: Data(), headers: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(session: session, restBaseURL: URL(string: "https://example.test/rest/v1")!)

        do {
            struct Row: Decodable { let id: Int }
            _ = try await client.get(table: "prompts", as: Row.self)
            XCTFail("expected to throw")
        } catch let error as SupabaseError {
            XCTAssertEqual(error, SupabaseError.unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// 404 応答は `SupabaseError.notFound` を投げる。
    func test_get_notFoundThrows() async {
        StubURLProtocol.response = (status: 404, body: Data(), headers: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(session: session, restBaseURL: URL(string: "https://example.test/rest/v1")!)

        do {
            struct Row: Decodable { let id: Int }
            _ = try await client.get(table: "prompts", as: Row.self)
            XCTFail("expected to throw")
        } catch let error as SupabaseError {
            XCTAssertEqual(error, SupabaseError.notFound)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// INSERT は `Prefer: return=representation` を必ず付ける。
    func test_insert_setsPreferHeader() async throws {
        // `select=id` で返ってくる想定の、id を含む行を1件返す。
        let body = """
        [{"id":"11111111-1111-1111-1111-111111111111"}]
        """.data(using: .utf8)!
        StubURLProtocol.response = (status: 201, body: body, headers: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(session: session, restBaseURL: URL(string: "https://example.test/rest/v1")!)

        struct Body: Encodable { let name: String }
        _ = try await client.insertVoid(table: "users", body: Body(name: "test"), select: "id")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Prefer"), "return=representation")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
    }

    /// DELETE は影響行数を返す。
    func test_delete_returnsCount() async throws {
        StubURLProtocol.response = (status: 200, body: Data("[1,2,3]".utf8), headers: nil)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = SupabaseClient(session: session, restBaseURL: URL(string: "https://example.test/rest/v1")!)

        let count = try await client.delete(table: "likes", filters: ["user_id": "eq.x"])
        XCTAssertEqual(count, 3)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "DELETE")
    }
}
