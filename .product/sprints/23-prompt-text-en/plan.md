# スプリント23: お題プールに手書きの英語原文（text_en）を追加

## 受け入れ条件（コーディネーターの依頼文から）
- [ ] 999件のお題プールに text_en（予備の英語原文）を追加し、ja の誤字・脱字・不自然な助詞を修正
- [ ] 新マイグレーション1本（20260923000002_prompt_text_en.sql）で prompts.text_en 追加・
      ensure_todays_prompt() 更新・既存行backfill・official_answers のキー更新
- [ ] アプリ側: Prompt.textEn 追加、SupabaseBackend/PromptCatalog/PromptGenerator/SeedCatalog/
      AppSession の対応
- [ ] ユニットテスト追加（SQL⇔Swift同期・.unavailable時のtextEn表示・翻訳成功時は機械翻訳優先）
- [ ] ローカルDB検証（Docker無し、Homebrew Postgres代替）
- [ ] spec.md 前提29・PROGRESS.md の更新

## 実装方針
1. 999件の ja/en を pos（0-indexed、candidatePool と同じ添字）ベースで生成 →
   `.product/prompt-pool-v2/pool-final.tsv`。テンプレート性の高いお題はノート辞書＋テンプレで、
   個別性の高いお題（「もし一日だけ」等）は手作業で翻訳。
2. SQL・Swift の両方に同じ配列を焼き込み、ローカルPostgresでバイト単位一致を検証。
3. AppSession の `.unavailable` 分岐だけをピンポイントで変更（翻訳ロジック本体には触れない）。

## 影響範囲
- `PromptCatalog.swift` の candidatePool 全面差し替え（既存48件のうち5件の文言が変わる →
  `PromptGenerationTests.testCandidatePoolContainsOriginal48Prompts` を更新）。
- `official_answers`（スプリント22・未評価）のキー5件が影響を受けるため、同じマイグレーション内で
  追随して更新。
