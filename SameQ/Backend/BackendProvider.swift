import Foundation

/// アプリが使う `Backend` を1か所で決める。
///
/// 本来の構成は Supabase（Auth 匿名認証 / PostgreSQL / RLS）だが、
/// クラウドプロジェクトが未作成で URL と anon key を持っていないため、
/// スプリント01では `LocalBackend` を使う。
/// 認証情報が用意でき次第、ここで `SupabaseBackend` を返すように差し替える。
/// テーブル定義と RLS ポリシーは `supabase/migrations/0001_init.sql` に先行実装済み。
enum BackendProvider {
    static func make() -> Backend {
        LocalBackend()
    }
}
