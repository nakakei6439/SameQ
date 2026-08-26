import Foundation

/// アプリが使う `Backend` を1か所で決める。
///
/// スプリント12以降は `SupabaseBackend` を既定で使う（実機・検証用）。
/// 端末内完結の `LocalBackend` はテスト・オフライン開発用に残し、
/// Debug 限定の起動引数 `-SameQUseLocalBackend` で切り替えられる。
/// テーブル定義と RLS ポリシーは `supabase/migrations/` に置いてある。
enum BackendProvider {
    static func make() -> Backend {
        #if DEBUG
        if LaunchOptions.current.useLocalBackend {
            return LocalBackend()
        }
        #endif
        return SupabaseBackend()
    }
}
