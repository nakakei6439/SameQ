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
            return "通信できません。ネットワーク接続を確認してください。"
        case .unauthorized:
            return "セッションが切れました。もう一度やり直してください。"
        case .notFound:
            return "該当のデータが見つかりませんでした。"
        case .duplicate:
            return "すでに同じデータが存在します。"
        case .forbidden(let detail):
            return "この操作は許可されていません（\(detail)）。"
        case .server(let message, _):
            return "サーバーでエラーが発生しました（\(message)）。"
        case .malformedResponse(let detail):
            return "サーバーからの応答を解釈できませんでした（\(detail)）。"
        case .transport(let detail):
            return "通信エラー（\(detail)）。"
        }
    }
}
