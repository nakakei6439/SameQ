import Foundation

/// アプリが使う `Backend` を1か所で決める。
///
/// スプリント12 の実装は `SupabaseBackend` に乗っており、コード・スキーマ・マイグレーション
/// まで全て揃っている（詳細は `SameQ/Backend/SupabaseBackend.swift` と
/// `supabase/migrations/20260819000004_server_connection.sql`）。
/// ただし今時点で接続先の Supabase プロジェクト `loqumzfgnahtclnvnrzb` は
/// 外部から到達不能（DNS NXDOMAIN・`supabase migration list --linked` が
/// `tenant not found` を返す。`.product/sprints/12-server-connection/eval-1.md` 参照）。
/// このため既定の起動経路は `LocalBackend`（端末内完結）とし、
/// `SupabaseBackend` を使いたいときは Debug 限定の `-SameQUseSupabaseBackend`
/// 起動引数で明示的にオプトインする設計にした。
///
/// 実機・本番で Supabase プロジェクトが復活したときは、この `make()` を
/// `return SupabaseBackend()` 1行に戻すだけで切り替わる（オプトイン分岐はそのまま動く）。
enum BackendProvider {
    static func make() -> Backend {
        #if DEBUG
        if LaunchOptions.current.useSupabaseBackend {
            return SupabaseBackend()
        }
        return LocalBackend()
        #else
        // Release ビルドは Supabase プロジェクト稼働が前提。
        return SupabaseBackend()
        #endif
    }
}