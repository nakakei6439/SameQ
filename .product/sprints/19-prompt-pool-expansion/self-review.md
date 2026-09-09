# スプリント19 自己評価（attempt 1）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| `candidatePool`（Swift）と `v_pool`（SQL）が同一件数・同一要素 | 達成 | `verify.py` で byte-exact 検証、`Match: True`、999 件一致 |
| 件数 ~1,000（周期が約 3 年）。既存 ~48 件が欠落・改変なく含まれる | 達成 | 999 件（範囲 950〜1100 内）、`testCandidatePoolContainsOriginal48Prompts` の 48 件全件含まれる。`PromptGenerationTests` 24 件 passed で確認 |
| `PromptGenerationTests` を含む全テストが green | 達成 | PromptGenerationTests 24/24 + PromptLifecycleTests 6/6 + SafetyLogRetentionTests + BanAndSpamTests 16/16 = 46/46 passed |
| 決定的シャッフル（seed=42）で並び確定、Swift と SQL が byte-for-byte 一致 | 達成 | `random.Random(42).shuffle`、`verify.py` で `Match: True` |

## 動かし方（evaluator 向け）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ

# Swift ↔ SQL の byte-exact 一致を確認
python3 .product/prompt-pool-draft/verify.py

# テスト
xcodebuild test -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SameQTests/PromptGenerationTests
```

## 自分で見つけた弱点

1. **タイポ修正 4 件**: 元の `final-pool.txt` にあった 4 件が `挙げるととしたら?` で 1 つ「と」が抜けていた。テスト期待値に強制修正した。MANIFEST.md §7 参照。
2. **既存との偶然重複 17 件**: 新規 Q 声お題 240 件のうち 17 件が既存と偶然合致し除外された。機能影響なし。
3. **重複検証は厳密一致のみ**: 意味的に似た問い（体の感覚、もし一日、もし一日、この一年で...）が多数残っているが、語幹重複（数詞・動詞句のみ違い）は既に除去済み。
4. **supabase db push 未実施**: マイグレーションの動作検証は evaluator タスク。
5. **実機 / シミュレータでの目視未実施**: Q 基準の最終的な品質チェックは evaluator タスク。

## 提案（今回はやらなかったこと）

- **WS2 の着手**: 運営回答コーパス / official_answers / ensure_official_answers 書き換え / users.nickname B案は今回 Keita 決定で中止。別スプリントで再着手する場合、Q 声お題の確定が前提条件。
- **お題プール拡張の 2 回目**: 999 件 ≒ 約 3 年周期。3 年後に再度プール枯渇問題が起きた場合は、1,500〜2,000 件への再拡張が考えられる（spec 範囲外）。
- **「体のどこ」系の集約**: 約 80 件残ったが、より少ない件数 (20 件程度) に集約して他カテゴリを増やすのは別検討。
- **「誰にも言っていないけれど本当は少し気にしている」系の削減**: 8 件残ったが、より明確な個別問いに分散可能。

## 変更したファイル

- `SameQ/Backend/PromptCatalog.swift`: candidatePool を 999 件で書き換え (1,112 行)
- `supabase/migrations/20260908000001_sprint19_prompt_pool_expansion.sql`: 新規作成 (1,079 行、お題プールのみ)
- `supabase/migrations/20260908000001_sprint19_prompt_pool_expansion_and_official_corpus.sql`: 削除 (WS2 中止のため)
- `.product/prompt-pool-draft/MANIFEST.md`: 上書き
- `.product/prompt-pool-draft/final-pool.txt`: 既存 (変更なし、参照のみ)
- `.product/prompt-pool-draft/{filter_pool.py,dedup_pool.py,new_prompts.py,generate_outputs.py,verify.py}`: 作業スクリプト (リポジトリ外の下書き)
- `.product/prompt-pool-draft/{filtered-pool.txt,deduped-pool.txt,expanded-pool.txt,shuffled-final.txt,filter-log.txt,dedup-log.txt,dedup2-log.txt}`: 中間生成物 (リポジトリ外の下書き)