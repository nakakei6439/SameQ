# スプリント 12 attempt 3: 環境問題で進められず・blocked

## eval-2.md の不合格理由（要約）
- **[1]** Supabase プロジェクト `loqumzfgnahtclnvnrzb` が evaluator 環境・generator 環境の双方から到達不能（DNS NXDOMAIN、`supabase migration list --linked` も `tenant not found`）。これは attempt 1 から変化なし。
- **[2]** 受け入れ条件1〜7がサーバ到達の前提なので、サーバ到達が不能な環境では全て検証不能。
- eval-1 で指摘された [2][3]（UI テスト回帰・未実行での引き渡し）は attempt 2 で解消済み。evaluator も再実測で確認。

## attempt 3 で何ができるか／何ができないか

### 着手可能な範囲（再評価）
- コード側は attempt 2 ですでに完成（SupabaseBackend / SupabaseClient / TokenBox / NWPathMonitor / world_timeline ビュー / マイグレーション / schemaVersion 7 / decodeIfPresent フォールバック / -SameQUseSupabaseBackend オプトイン / LocalBackend 既定）。
- 既存 UI テストは attempt 2 で 19/19・ユニットは 166/166 が確認済み。attempt 3 で再確認した結果も 166/166 pass（TEST SUCCEEDED）。
- 起動経路は明確: 既定（引数なし）= LocalBackend、`-SameQUseSupabaseBackend` = SupabaseBackend、Release ビルド = SupabaseBackend。

### それでも直せない範囲
- **環境側でしか直せない**：Supabase プロジェクト `loqumzfgnahtclnvnrzb` が DNS 解決不能。generator 側で再作成・修復は不可能：
  - `~/.supabase/` にアクセストークンが無く、`supabase projects list` がハングして認証待ちで応答しない。
  - `https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb` にログインする認証情報は generator に無い。
  - `.env.local` の `SUPABASE_PROJECT_REF=loqumzfgnahtclnvnrzb` と `SupabaseConfig.swift` の URL 定数を変更しても、到達可能な新規プロジェクトを生成する手段が無い。
- attempt 1, 2, 3 でネットワーク診断を再実測したが、対照ドメイン（supabase.com / supabase.co / api.supabase.com）は全て応答でき、`loqumzfgnahtclnvnrzb.supabase.co` だけ名前解決不能のまま（環境・サンドボックス全体の問題ではなく、このプロジェクト参照固有の問題）。

## 何もしない理由
attempt 1 と attempt 2 で同じ指摘（[1]）を2回受けた。「**同じ指摘で3回落ちたら止まる**」の規定に従い、attempt 3 は **blocked** として人間に判断を仰ぐ。コードを追加で変更しても解決不能な環境問題なので、的外れな差分を増やさない判断。

## ユーザー側で必要な作業
1. `https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb` にログインして、プロジェクトの現存・一時停止・削除状態を確認する。
2. 削除されている場合 → 新規 Supabase プロジェクトを作成し、`supabase/migrations/20260819000004_server_connection.sql` を `supabase db push` で適用する。
3. 一時停止されている場合 → サポートに連絡するか、プランを確認する。
4. プロジェクト参照が変わった場合 → `.env.local` の `SUPABASE_PROJECT_REF` と `SUPABASE_URL`、`SameQ/Backend/SupabaseConfig.swift` の `url` と `publishableKey` を更新する。
5. 復旧後、generator（attempt 3）に戻ってきて、`BackendProvider.make()` の `#if DEBUG` 内の `return LocalBackend()` を `return SupabaseBackend()` に1行戻すだけで本番経路が復活する。

## 影響範囲
- コード変更はゼロ。
- `BackendProvider.swift` / `LaunchOptions.swift` / `SupabaseConfig.swift` / `SupabaseBackend.swift` / `SupabaseClient.swift` / `LocalStore.swift` / `supabase/migrations/20260819000004_server_connection.sql` はすべて attempt 2 のまま（正しい状態）。