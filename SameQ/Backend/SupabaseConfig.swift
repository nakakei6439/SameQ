import Foundation

/// Supabase プロジェクトの接続情報（`.env.local` 由来）。
///
/// 「外部パッケージ依存はゼロ」方針を保つため、URLSession で REST を直接叩く。
/// ここで持つキーは `publishable`（公開キー）のみ。RLS で保護される前提。
/// `secret` キー（service_role）は絶対にここに入れない（PROGRESS.md のブロッカー B01）。
enum SupabaseConfig {
    /// プロジェクト URL（PostgREST / Auth のベース）。
    static let url: URL = URL(string: "https://loqumzfgnahtclnvnrzb.supabase.co")!

    /// 匿名認証に使う公開キー。新形式（`sb_publishable_*`）。
    /// `Authorization: Bearer <key>` で送られるが、Supabase は RLS で保護する。
    static let publishableKey: String = "sb_publishable_-N3uUwv7XYfRIdr4WI_39Q_23swTNEL"

    /// レガシー anon キー。REST/Auth 両方で受け付けるよう、念のため併記する
    /// （SDK バージョンによって要求ヘッダーが異なるため、URLSession 直叩きでは
    ///  publishable を優先しつつ apikey ヘッダーには legacy を入れる）。
    static let anonKeyLegacy: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxvcXVtemZnbmFodGNsbnZucnpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5NjU3NDEsImV4cCI6MjEwMjU0MTc0MX0.wy4Yz4Jjg-vm_Ocvn0RTz7keCuC1tCGddWu8e4QD6Nw"

    /// Auth エンドポイントのベース URL。`url` から組み立てる。
    static var authURL: URL { url.appendingPathComponent("auth/v1") }
    /// PostgREST のベース URL。
    static var restURL: URL { url.appendingPathComponent("rest/v1") }
}
