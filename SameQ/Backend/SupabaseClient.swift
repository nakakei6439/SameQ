import Foundation

/// Supabase の REST エンドポイントを叩く薄い HTTP クライアント。
///
/// 外部 SDK を使わず URLSession だけで実装する（プロジェクト方針：
/// 「外部パッケージ依存はゼロ」）。テストでは `URLSession` 部分を差し替えられるよう、
/// `session` を `init` で受け取れる形にしてある。
///
/// 認証は `Authorization: Bearer <access_token>` を全 REST/Auth リクエストに付ける。
/// アクセストークンは `tokenProvider`（クロージャ）から毎回取得する形にして、
/// 401 後にトークンを更新しても次のリクエストから新しい値が届くようにする。
struct SupabaseClient: Sendable {
    /// リクエスト送出に使うセッション。テストでは `URLProtocol` で差し替え可能。
    let session: URLSession
    /// アクセストークン（nullable）。`nil` のときは `apikey` ヘッダーだけ送る。
    /// Supabase の匿名サインアップ直後は未確定なので nil になる瞬間がある。
    let tokenProvider: @Sendable () -> String?
    /// `apikey` ヘッダーに常に載せる公開キー。
    let apiKey: String
    /// REST のベース URL。
    let restBaseURL: URL
    /// Auth のベース URL。
    let authBaseURL: URL

    init(
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String? = { nil },
        apiKey: String = SupabaseConfig.publishableKey,
        restBaseURL: URL = SupabaseConfig.restURL,
        authBaseURL: URL = SupabaseConfig.authURL
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
        self.apiKey = apiKey
        self.restBaseURL = restBaseURL
        self.authBaseURL = authBaseURL
    }

    // MARK: - GET / POST / PATCH / DELETE（PostgREST）

    /// PostgREST 形式のレスポンス。データはボディ、付随情報は `Content-Range` 等のヘッダー。
    struct Response<T> {
        let value: T
        let headers: [AnyHashable: Any]
    }

    /// INSERT/UPDATE の返り値が必要ないときに使う型。
    /// `select=id` で十分（存在確認のため）。
    struct VoidResponse: Decodable {
        let id: UUID?
        let user_id: UUID?
        let post_id: UUID?
        let blocker_id: UUID?
        let blocked_id: UUID?
        let reporter_id: UUID?

        enum CodingKeys: String, CodingKey {
            case id
            case user_id
            case post_id
            case blocker_id
            case blocked_id
            case reporter_id
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decodeIfPresent(UUID.self, forKey: .id)
            user_id = try? container.decodeIfPresent(UUID.self, forKey: .user_id)
            post_id = try? container.decodeIfPresent(UUID.self, forKey: .post_id)
            blocker_id = try? container.decodeIfPresent(UUID.self, forKey: .blocker_id)
            blocked_id = try? container.decodeIfPresent(UUID.self, forKey: .blocked_id)
            reporter_id = try? container.decodeIfPresent(UUID.self, forKey: .reporter_id)
        }
    }

    /// 単一オブジェクトを返す GET。`select` でカラムを絞れる。
    func getOne<T: Decodable>(
        table: String,
        select: String = "*",
        filters: [String: String] = [:],
        as type: T.Type = T.self
    ) async throws -> T? {
        let array: [T] = try await get(table: table, select: select, filters: filters, as: T.self)
        return array.first
    }

    /// 配列を返す GET。
    func get<T: Decodable>(
        table: String,
        select: String = "*",
        filters: [String: String] = [:],
        order: String? = nil,
        limit: Int? = nil,
        as type: T.Type = T.self
    ) async throws -> [T] {
        let url = try restURL(path: table, select: select, filters: filters, order: order, limit: limit)
        var request = makeRestRequest(url: url, method: "GET")
        // 単一オブジェクト取得のため Accept を明示
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        return try decodeArray(data: data, as: T.self)
    }

    /// 単一オブジェクトを返す POST。`Prefer: return=representation` を必ず付ける。
    func insert<T: Decodable, Body: Encodable>(
        table: String,
        body: Body,
        select: String = "*",
        as type: T.Type = T.self
    ) async throws -> T {
        let url = try restURL(path: table, select: select, filters: [:], order: nil, limit: nil)
        var request = makeRestRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encodeJSON(body)
        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        let array: [T] = try decodeArray(data: data, as: T.self)
        guard let first = array.first else {
            throw SupabaseError.malformedResponse("empty insert response")
        }
        return first
    }

    /// 返り値不要の INSERT。型推論の問題を避けるため `Void` 専用版を用意。
    @discardableResult
    func insertVoid<Body: Encodable>(
        table: String,
        body: Body,
        select: String = "id"
    ) async throws -> VoidResponse {
        return try await insert(
            table: table,
            body: body,
            select: select,
            as: VoidResponse.self
        )
    }

    /// 部分更新。`Prefer: return=representation` を必ず付ける。
    func update<T: Decodable, Body: Encodable>(
        table: String,
        filters: [String: String],
        body: Body,
        select: String = "*",
        as type: T.Type = T.self
    ) async throws -> T? {
        let url = try restURL(path: table, select: select, filters: filters, order: nil, limit: nil)
        var request = makeRestRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encodeJSON(body)
        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        let array: [T] = try decodeArray(data: data, as: T.self)
        return array.first
    }

    /// 返り値不要の UPDATE。型推論の問題を避けるため `Void` 専用版を用意。
    @discardableResult
    func updateVoid<Body: Encodable>(
        table: String,
        filters: [String: String],
        body: Body,
        select: String = "id"
    ) async throws -> VoidResponse? {
        return try await update(
            table: table,
            filters: filters,
            body: body,
            select: select,
            as: VoidResponse.self
        )
    }

    /// 削除。`Prefer: return=representation` を付けない（影響行だけ返す）。
    @discardableResult
    func delete(
        table: String,
        filters: [String: String]
    ) async throws -> Int {
        let url = try restURL(path: table, select: "*", filters: filters, order: nil, limit: nil)
        var request = makeRestRequest(url: url, method: "DELETE")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        // 空配列 or `[]` が返る。件数は Status `204` なら 0、`200` で中身を数える。
        if data.isEmpty { return 0 }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return array.count
        }
        return 0
    }

    // MARK: - RPC（PostgREST /rpc/<関数名>）

    /// `POST /rest/v1/rpc/<function>` を呼び出す（PostgREST の RPC エンドンド）。
    /// 引数は `JSON` オブジェクトとして body に載せる。返り値は `T` にデコードされる。
    /// `received_like_count(post_id)` のような `security definer` 関数を叩くために使う
    ///（attempt 11: eval-7.md [1] b の修正）。
    /// - Parameters:
    ///   - function: PostgREST の関数名（snake_case）
    ///   - arguments: 関数に渡す引数の辞書（`Codable` の `JSONEncoder` 互換型）
    ///   - type: レスポンスをデコードする型
    func rpc<Args: Encodable, T: Decodable>(
        function: String,
        arguments: Args,
        as type: T.Type = T.self
    ) async throws -> T {
        let url = restBaseURL.appendingPathComponent("rpc/\(function)")
        var request = makeRestRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encodeJSON(arguments)
        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        return try decode(T.self, from: data)
    }

    /// `T` が配列（`[Element]`）のときに使うショートカット。
    func rpc<Args: Encodable, Element: Decodable>(
        function: String,
        arguments: Args,
        asArray elementType: Element.Type = Element.self
    ) async throws -> [Element] {
        let array: [Element] = try await rpc(
            function: function,
            arguments: arguments,
            as: [Element].self
        )
        return array
    }

    // MARK: - Auth

    /// 匿名サインアップ。`POST /auth/v1/signup`。
    /// 成功時はアクセストークンと更新トークンを返す。
    struct AuthSession: Codable, Sendable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let userID: UUID

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case userID = "user_id"
        }
    }

    /// Supabase の Auth レスポンス本体。`user` の `id` を抜き出して `AuthSession` を作る。
    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let user: AuthUser

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }

        struct AuthUser: Decodable {
            let id: UUID
        }
    }

    func anonymousSignUp() async throws -> AuthSession {
        var request = URLRequest(url: authBaseURL.appendingPathComponent("/signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        // 匿名サインアップは `data` フィールドにユーザー作成用のメタデータを入れられるが、
        // 必須ではない（サインアップと同時に `public.users` を作るので、ここでは空で良い）。
        request.httpBody = try encodeJSON(["data": [String: String]()])

        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        let parsed = try decode(AuthResponse.self, from: data)
        return AuthSession(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken,
            expiresIn: parsed.expiresIn,
            userID: parsed.user.id
        )
    }

    /// `POST /auth/v1/token?grant_type=refresh_token` でアクセストークンを更新する。
    func refreshToken(refreshToken: String) async throws -> AuthSession {
        var request = URLRequest(url: authBaseURL.appendingPathComponent("/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        // grant_type をクエリで指定
        guard var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else {
            throw SupabaseError.malformedResponse("invalid auth url")
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        request.url = components.url
        request.httpBody = try encodeJSON(["refresh_token": refreshToken])

        let (data, response) = try await performRequest(request)
        try validate(response: response, data: data)
        let parsed = try decode(AuthResponse.self, from: data)
        return AuthSession(
            accessToken: parsed.accessToken,
            refreshToken: parsed.refreshToken,
            expiresIn: parsed.expiresIn,
            userID: parsed.user.id
        )
    }

    // MARK: - 内部実装

    /// PostgREST の URL を組み立てる。
    private func restURL(
        path: String,
        select: String,
        filters: [String: String],
        order: String?,
        limit: Int?
    ) throws -> URL {
        guard var components = URLComponents(
            url: restBaseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw SupabaseError.malformedResponse("invalid path: \(path)")
        }
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "select", value: select)]
        for (key, value) in filters {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        if let order {
            queryItems.append(URLQueryItem(name: "order", value: order))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw SupabaseError.malformedResponse("invalid query: \(path)")
        }
        return url
    }

    /// REST リクエストの雛形を作る（共通ヘッダー）。
    private func makeRestRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// URLSession でリクエストを送り、エラーを `SupabaseError` に丸める。
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw SupabaseError.offline
            case .timedOut:
                throw SupabaseError.transport("タイムアウトしました")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw SupabaseError.offline
            default:
                throw SupabaseError.transport(error.localizedDescription)
            }
        } catch {
            throw SupabaseError.transport(error.localizedDescription)
        }
    }

    /// HTTP ステータスコードとレスポンスボディからエラーを判定する。
    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.malformedResponse("non-http response")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw SupabaseError.unauthorized
        case 404:
            throw SupabaseError.notFound
        case 409, 23505 where data.contains(0x32): // 23505 は PostgREST ではなく PGRST エラー
            throw SupabaseError.duplicate
        case 403, 42501:
            // RLS 違反やポリシー拒否
            let message = parseErrorMessage(data: data) ?? "forbidden"
            throw SupabaseError.forbidden(message)
        case 400...499:
            let message = parseErrorMessage(data: data) ?? "client error \(http.statusCode)"
            throw SupabaseError.server(message: message, code: nil)
        default:
            let message = parseErrorMessage(data: data) ?? "server error \(http.statusCode)"
            throw SupabaseError.server(message: message, code: nil)
        }
    }

    /// Supabase の `{ "message": "...", "code": "..." }` 形式から `message` だけ抜く。
    private func parseErrorMessage(data: Data) -> String? {
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = dict["message"] as? String { return msg }
            if let desc = dict["error_description"] as? String { return desc }
            if let err = dict["error"] as? String { return err }
        }
        return nil
    }

    /// JSON エンコード（`iso8601` タイムスタンプ）。
    private func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(value)
        } catch {
            throw SupabaseError.malformedResponse("encode failed: \(error.localizedDescription)")
        }
    }

    /// JSON 配列を `Decodable` 配列として読む。空ボディは空配列。
    private func decodeArray<T: Decodable>(data: Data, as type: T.Type) throws -> [T] {
        if data.isEmpty { return [] }
        do {
            return try decode([T].self, from: data)
        } catch {
            // PostgREST は単一オブジェクトを返すことがあるので `T` 単体にフォールバック。
            if let single = try? decode(T.self, from: data) {
                return [single]
            }
            throw SupabaseError.malformedResponse("decode array failed: \(error.localizedDescription)")
        }
    }

    /// `Decodable` のための共通デコーダ（`iso8601` タイムスタンプ）。
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.malformedResponse("decode failed: \(error.localizedDescription)")
        }
    }
}
