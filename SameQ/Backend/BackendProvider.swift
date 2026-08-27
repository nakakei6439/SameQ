import Foundation

/// アプリが使う `Backend` を1かところで決める。
///
/// スプリント12 の実装は `SupabaseBackend` に乗っており、コード・スキーマ・マイグレーション
/// まで全て揃っている（詳細は `SameQ/Backend/SupabaseBackend.swift` と
/// `supabase/migrations/20260819000004_server_connection.sql`）。
///
/// attempt 8（2026-08-27）で、Supabase プロジェクト `loqumzfgnahtclnvnrzb` の
/// 匿名サインイン有効化・migration 4 適用・seed 投入が完了したため、Debug 既定も
/// `SupabaseBackend` に戻した。UI テストは `-SameQUseLocalBackend` で
/// 引き続き `LocalBackend`（端末内完結）に固定できる。
///
/// `-SameQUseLocalBackend`（Debug 限定）は UI テスト・スモーク確認用の
/// 強制オプトイン。Release ビルドでは引数に関わらず常に `SupabaseBackend()` を返す。
enum BackendProvider {
    static func make() -> Backend {
        #if DEBUG
        // attempt 8: Debug 既定も SupabaseBackend。-SameQUseLocalBackend を
        // 付けたときだけ LocalBackend に切り替わる（UI テスト・スモーク確認用）。
        if LaunchOptions.current.useLocalBackend {
            return LocalBackend()
        }
        return SupabaseBackend()
        #else
        // Release ビルドは Supabase プロジェクト稼働が前提。
        return SupabaseBackend()
        #endif
    }
}