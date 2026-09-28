# スプリント 24 評価（attempt 1） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 8/8 | 100% | ✓ |
| 2 安定性 | ユニット 281/281、UI 14/14、全24マイグレーションがエラーなしで適用、クラッシュ 0 | 0 | ✓ |
| 3 データ整合性 | TSV⇔Swift⇔SQL⇔DB上の関数定義 150/150 一致、孤児 0 | 100% | ✓ |
| 4 回帰 | 4/4 | 100% | ✓ |
| 5 使用性 | 4（お題88件は手作り回答、62件は従来どおりのフォールバック。空の日は出ない） | 3以上 | ✓ |

## 検証環境
- 2026-09-28 21:50〜22:10 JST。main の作業ツリー（未コミット）。
- ローカル DB: Homebrew postgresql@16 (16.15)。scratchpad に新規 initdb、TCP 55439 のみ。auth スキーマ・auth.uid() スタブ・3ロールを作成し、`supabase/migrations/*.sql` 24本を昇順・ON_ERROR_STOP=1 で適用。
- 本番は **SELECT のみ**（`supabase db query --linked`）。書き込みなし。`supabase migration list --linked` で 20260928000001 がリモート未適用であることも確認。
- Xcode: iPhone 17 シミュレータ。

## 確認内容（すべて実測）
1. **選定の正しさ**: 期待集合 = 既存48件 ∪ range(0,105) を独自に作ると 150件。`pool-150-selected.tsv` の pos 列は、この集合を昇順に並べたものと完全一致。text_ja / text_en は `pool-final.tsv` の3列目（修正後 ja）と4列目（en）に 150/150 一致。
2. **Swift/SQL の完全一致**: `candidatePool` / `candidatePoolEn` と、新マイグレーションの `v_pool_ja` / `v_pool_en` をそれぞれパースした。4配列とも 150件で、期待列（pool-final から pos 昇順で抽出したもの）と件数・順序・内容が完全一致。重複なし（ja 150 / en 150 ユニーク）。ローカル DB の `pg_get_functiondef` から取り出した配列も同一。20260923000002 との関数の差分は、配列本体とコメントだけ（添字計算・overlap の切り詰め・insert・grant は同一）。
3. **official_answers**:
   - マイグレーション由来 48件 ＋ batch-001〜004 の 40件（= pos0〜39 の修正後 ja と完全一致）で、合計 88件の distinct prompt_text。孤児は 0。
   - 本番 SELECT の結果は distinct 88件・総数 880件。この 88件もすべて 150件プールに含まれ、孤児は 0。
   - ローカルで batch 4本を適用したあと、150件それぞれを今日のお題に設定して `ensure_official_answers()` を実行した。結果は **custom 88 / fallback 62**（想定と一致）。
   - なお self-review の末尾にある「未カバー102件」という記述は誤りで、正しくは 62件（バッチ1〜4を数え漏らしている）。判定には影響しない。
4. **ensure_todays_prompt()**: 実行すると prompt_20260928 に「この一年で、はじめて名前を覚えた人はいますか？」と text_en が入った。Python で添字 `((19628%150)+75)%150=99` を計算すると同じ文言になる。150日連続でシミュレーションすると、150件すべてが1回ずつ出る。
5. **テスト**: `-only-testing:SameQTests` で 281/281 通過（TEST SUCCEEDED）。同期テストの参照先が新マイグレーションに変わっていることも差分で確認した。
6. **spec.md**: F46・前提30・運用節・スプリント19の注記がすべて「約150件（140〜160）／約5ヶ月」で揃っている。旧値（約1,000件・3年）は「当時」の注記として残っているだけで、矛盾はない。

## 回帰（4件）
- スプリント19「アプリ側とサーバー側で候補の数と並びが一致」→ 上記2で一致を確認。
- スプリント19「既存の約48件が欠落・改変されずに含まれている」→ `testCandidatePoolContainsOriginal48Prompts` が通過。48件はプール内に存在する。
- スプリント23「text_en がサーバー生成のお題に入る」→ ensure_todays_prompt() の実行結果に text_en が入っていることを確認。
- スプリント20/21 の UI 受け入れテスト（`SprintTwentyAcceptanceTests` 8件 + `SprintTwentyOneAcceptanceTests` 6件）→ 14/14 通過。

## 不合格の原因
なし。

## 改善提案（合否には影響しない）
- [中] 並びは元の seed=42 の順序を継いでいるため、似た問いが隣り合う箇所が 999件版から残っている。例: 添字55→56「いま、自分の体のどこが緊張していますか？」→「…喜んでいますか？」。こうした箇所は元の pool-final でも隣接しており、今回の変更による回帰ではない。
- [低] self-review.md の「未カバー102件」を 62件に訂正する。
- [低] 本番に反映したあとは、`select id,text from prompts order by starts_at desc limit 3` で、翌日のお題が150件プールから出ていることを SELECT で確かめる。

## 評価できなかったもの
- Supabase CLI（Docker）での `supabase db reset`、PostgREST 経由の RPC、実 JWT での auth.uid() 解決は確認していない。今回の変更は関数の配列差し替えだけなので、影響は小さいと判断した。
