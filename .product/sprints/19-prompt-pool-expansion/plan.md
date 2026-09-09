# スプリント19: お題プール拡張（WS1 のみ）

## 受け入れ条件（spec.md から転記）
- [ ] `candidatePool`（Swift）と `v_pool`（SQL）が同一件数・同一要素
- [ ] 件数 ~1,000（周期が約 3 年）。既存 ~48 件が欠落・改変なく含まれる
- [ ] `PromptGenerationTests` を含む全テストが green（`testCandidatePoolMeetsSprint19Range` 950〜1100 を満たす）
- [ ] 決定的シャッフル（seed=42）で並び確定、Swift と SQL が byte-for-byte 一致

## 実装方針
- `.product/prompt-pool-draft/final-pool.txt`（1,083 行）を起点にフィルタリング
- 「好きなった」「◯◯の{寸法}は？」「この一年で、はじめて気づいた自分の{属性}」「今日、誰かの前で『...』と言えた瞬間」「誰にも話していない小さな{X}」の機械量産を全削除
- 既存の 48 件は typo 修正を含めて一字一句そのまま残す
- 除去後 776 件 → 不足分を Q の声で 240 件新規作成（うち 17 件重複除外で 223 件追加） → 999 件
- `random.Random(42).shuffle` で決定的シャッフル
- `SameQ/Backend/PromptCatalog.swift` の `candidatePool` と、新新 migration `20260908000001_sprint19_prompt_pool_expansion.sql` の `v_pool` を byte-for-byte 一致で生成
- 旧 `_and_official_corpus` マイグレーションは削除（WS2 は今回やらない）

## 影響範囲
- `PromptCatalog.candidatePool`（Swift）: 48 件 → 999 件
- `ensure_todays_prompt()` (SQL) の `v_pool`: 同上
- `testCandidatePoolMeetsSprint19Range` (950〜1100) は追加済み、合格
- `testCandidatePoolContainsOriginal48Prompts` (48 件保護) は追加済み、合格

## やらないこと（明示的に範囲外）
- WS2（運営回答 / official_answers テーブル / ensure_official_answers 書き換え / users.nickname B案）
- `supabase db push --linked`
- `git commit / git push`
- `README.md` 更新
- `Info.plist` 更新
- TestFlight アップロード
- 実機 / シミュレータ実行