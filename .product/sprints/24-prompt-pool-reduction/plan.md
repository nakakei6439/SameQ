# スプリント 24: お題プールを999件から150件に縮小

## 受け入れ条件（コーディネーター指示より）
- [ ] `PromptCatalog.swift` の candidatePool / candidatePoolEn を150件（指定pos順）に差し替え
- [ ] 新規SQLマイグレーションで `ensure_todays_prompt()` を150件配列で再定義（他ロジック不変）
- [ ] `.product/prompt-pool-v2/pool-150-selected.tsv` を新規作成（pos, text_ja, text_en）
- [ ] `pool-final.tsv`（999件）は変更しない
- [ ] `PromptGenerationTests.swift` を150件基準に更新
- [ ] `.product/spec.md` の F46・前提30 を「約150件・間隔約5ヶ月」に更新
- [ ] Xcodeユニットテスト全緑
- [ ] ローカルDB（Homebrew Postgres等）で新マイグレーション適用を実測
- [ ] 本番 `supabase db push --linked` はしない

## 実装方針
1. pool-final.tsv から指定150 posのtext_ja(修正版)・text_enをPythonスクリプトで抽出し、
   選定順（指定pos昇順）でSwift配列リテラルとSQL配列リテラルを機械生成する（手打ち転記
   による事故を避ける）。
2. `PromptCatalog.swift`: candidatePool/candidatePoolEnをこの150件に置換。コメントを更新。
3. 新規マイグレーション `20260928000001_sprint24_prompt_pool_reduction.sql`:
   `create or replace function ensure_todays_prompt()` で v_pool_ja/v_pool_en を150件に
   差し替え。添字計算式・overlap切り詰め・insert文は完全に不変（コピー）。
4. `pool-150-selected.tsv` 新規作成。
5. テスト: 件数レンジ140〜160件、SQL比較先のファイル名を新マイグレーションに変更。
   original48件テストはそのまま（150件に全部含まれるので自動的に緑になるはず）。
6. spec.md: F46行・前提30・スプリント19セクション該当箇所を150件/5ヶ月に更新。

## 影響範囲
- `ensure_official_answers()` 等、official_answersの紐付けは文字列一致なので無影響。
- 過去のprompts実データはon conflict do nothingのため不変。
- 本番適用はしない（ローカル検証のみ）。
