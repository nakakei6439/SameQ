import Foundation

/// Supabase との通信で投げられる固有エラー（既存の `BackendError` を拡張する位置付け）。
///
/// URLSession 由来のエラーと、Supabase が返すエラー応答（PostgREST の
/// `message`/`code` フィールド、Auth の `error_description`）をまとめて受け取る。
enum SupabaseError: LocalizedError, Equatable {
    /// ネットワークが届かない（機内モード・圏外・DNS 失敗）。
    case offline
    /// 認証切れ（401）。トークンを破棄してオンボーディングに戻す。
    case unauthorized
    /// 該当リソースが存在しない（404）。
    case notFound
    /// 一意制約違反（23505）。例: 同じお題に2回目の投稿。
    case duplicate
    /// RLS・CHECK 制約違反（42501 / 23514 等）。
    case forbidden(String)
    /// その他の Supabase エラー。
    case server(message: String, code: String?)
    /// JSON パース失敗など、想定外のレスポンス。
    case malformedResponse(String)
    /// その他の URLSession エラー。
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return L10n.Errors.supabaseOffline
        case .unauthorized:
            return L10n.Errors.supabaseUnauthorized
        case .notFound:
            return L10n.Errors.supabaseNotFound
        case .duplicate:
            return L10n.Errors.supabaseDuplicate
        case .forbidden(let detail):
            return L10n.Errors.supabaseForbidden(detail)
        case .server(let message, _):
            return L10n.Errors.supabaseServer(message)
        case .malformedResponse(let detail):
            return L10n.Errors.supabaseMalformed(detail)
        case .transport(let detail):
            return L10n.Errors.supabaseTransport(detail)
        }
    }
}
