# スプリント24 自己評価（attempt 1）

対象: お題プールを999件から150件に縮小する。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| `PromptCatalog.swift` の candidatePool/candidatePoolEn を指定150件・指定順に差し替え | 達成 | Python で pool-final.tsv から指定150 pos（昇順）のtext_ja(修正版)・text_enを抽出し配列を機械生成。Swift側を実際にパースしてTSVと突合（150/150件一致、順序一致、重複なし） |
| 新規SQLマイグレーションで `ensure_todays_prompt()` を150件配列で再定義（他ロジック不変） | 達成 | `supabase/migrations/20260928000001_sprint24_prompt_pool_reduction.sql`。添字計算式・overlap切り詰め・insert文・comment/grantは20260923000002と一字一句同一（コピー）。差分はv_pool_ja/v_pool_enの配列本体のみ |
| `.product/prompt-pool-v2/pool-150-selected.tsv` を新規作成 | 達成 | pos, text_ja, text_en の3列・150行・選定順=最終配列の順 |
| `pool-final.tsv`（999件）は変更しない | 達成 | `git status` で999件版は変更なしを確認。150件版は新規ファイルとして追加 |
| `PromptGenerationTests.swift` を150件基準に更新 | 達成 | 下記「テスト」参照 |
| Xcodeユニットテスト全緑 | 達成 | 281/281（`xcodebuild -only-testing:SameQTests`） |
| ローカルDB（Homebrew Postgres等）で新マイグレーション適用を実測 | 達成 | 下記「サーバー側の検証」参照 |
| 本番 `supabase db push --linked` はしない | 達成 | 一度も実行していない |

**全条件達成。**

## データ（150件の選定）

- 選定基準: 既存の運営回答カバー済み48件のpos ∪ pos 0〜104（連番105件）。重複3件（47, 52, 99）を除いて105+48-3=150件（コーディネーター指定の計算・pos一覧をそのまま採用）。
- pos一覧をPythonで重複・件数チェック（150件・ユニーク150件・昇順であることを確認）した上で、`.product/prompt-pool-v2/pool-final.tsv` から該当行（pos, text_ja_old, text_ja_fixed, text_en の4列）を抽出し、text_ja_fixed（3列目、スプリント23の誤字修正後の文言）と text_en（4列目）だけを使って新150件配列を機械生成した。手打ち転記はしていない。
- 抽出結果の150件は ja・en とも重複なし（ユニーク150件）。

## ファイル間の一致検証（機械照合）

「48→999件拡張時に片方だけ更新して壊れた」過去の事故の再発防止のため、テキスト比較を複数箇所で行った。

1. `PromptCatalog.swift` の `candidatePool` / `candidatePoolEn` を実際に正規表現でパースし、`pool-150-selected.tsv` の該当列と150件全件を突合 → 不一致0件。
2. 新マイグレーションSQLの `v_pool_ja` / `v_pool_en` 配列リテラルをパースし、Swift側の2配列と突合 → 不一致0件（順序・件数とも完全一致）。
3. ローカルPostgreSQLに全24マイグレーションを実際に適用したあと、`pg_get_functiondef('public.ensure_todays_prompt'::regproc)` でDBに実際に登録された関数定義を取得し、そこから配列を再抽出してTSVと突合 → 不一致0件（コード上の一致だけでなく、DBに実際に反映された内容も一致することを確認）。

## サーバー側の検証（本機に Docker が無いため、スプリント22/23と同じ代替手段）

Homebrew の `postgresql@16`（16.15）を新規データディレクトリで単独起動し、`auth` スキーマと `auth.uid()` スタブ、`authenticated`/`anon`/`service_role` ロールを用意した上で、`supabase/migrations/*.sql` をファイル名の昇順（適用順）で全24本（`20260817000001_init.sql` 〜 今回の `20260928000001_sprint24_prompt_pool_reduction.sql`）、`ON_ERROR_STOP=1` で頭から適用した。

**確認できたこと**:
- 24本すべてエラー無く適用（構文エラー・制約違反なし）。
- `ensure_todays_prompt()` を実行すると、`prompts.text` / `text_en` に150件プールから選ばれた値が入ることを実測（例: `prompt_20260928` → 「この一年で、はじめて名前を覚えた人はいますか？」）。
- `array_length(v_pool_ja, 1)` が実行時に150として振る舞うこと（DB内の関数定義から配列を抽出し150件であることを確認）。
- **official_answers との紐付けが壊れていないこと**: 150件プールに含まれる既存カバー済みの1問（「いま、好きな音をひとつだけ挙げるとしたら？」）を `prompts.text` に手動設定して `ensure_official_answers()` を実行し、`source=custom inserted=10` を実測（完全一致文字列検索が配列の件数・添字に依存しないという前提どおり、プール縮小後も正しく手作り回答を引けている）。
- `official_answers` の総行数は480のまま・distinct prompt_text は48のまま（今回のマイグレーションでは変更していないテーブルなので不変であることも確認）。

**検証の限界（隠さない）**: スプリント22/23と同様、Supabase CLI (`supabase db reset` / `supabase start`) 経由ではなく、素の PostgreSQL への手動セットアップでの検証。PostgREST 経由の公開・実際の JWT による `auth.uid()` 解決・Supabase Studio 経由の動作は未検証。本番相当の確認は、Docker が使える環境で `supabase db reset` を一度通すことを推奨する（このマイグレーション単体の構文・ロジックに問題が無いことは上記で担保済み）。

## アプリ側の変更

- `SameQ/Backend/PromptCatalog.swift`: `candidatePool`（ja）・`candidatePoolEn`（en）を999件→150件に差し替え。ヘッダーコメント（enum全体・candidatePool直上）にスプリント24での縮小理由と参照先（`pool-150-selected.tsv`）を追記。`candidatePoolEn` 直上のコメントは事実に変更が無いため据え置き。

## サーバー側の変更

- 新規 `supabase/migrations/20260928000001_sprint24_prompt_pool_reduction.sql`: `ensure_todays_prompt()` を `create or replace function` で再定義。v_pool_ja/v_pool_enを150件配列に差し替え、それ以外（添字計算式・overlap切り詰め・insert・comment/grant）は20260923000002と完全に同一。

## データファイル

- 新規 `.product/prompt-pool-v2/pool-150-selected.tsv`（pos, text_ja, text_en の3列・150行、選定順=最終配列の順）。
- `.product/prompt-pool-v2/pool-final.tsv`（999件）は変更なし。

## テスト

`SameQTests/PromptGenerationTests.swift` の変更:
- `testCandidatePoolMeetsSprint19Range` → `testCandidatePoolMeetsSprint24Range` にリネームし、アサートを 950〜1100件 から 140〜160件 に変更。コメントも150件縮小の経緯に更新。
- `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays`: 読みに行くマイグレーションファイルを `20260923000002_prompt_text_en.sql`（999件版。過去の履歴として残るだけで実行時には使われない）から `20260928000001_sprint24_prompt_pool_reduction.sql`（最新の `ensure_todays_prompt()` 定義）に変更。件数・並びの比較ロジック自体は変更していない（自動的に150件同士の比較になる）。
- `testCandidatePoolContainsOriginal48Prompts`: 変更なし。150件プールは元48件の pos を必ず含む構成（コーディネーター指定の計算）なので、48件全件が新配列にも含まれており、無変更のまま緑になることを確認した。
- `testBackfillValuesListMatchesPoolFinalTsv`: 変更なし。このテストが検証しているのは「スプリント23の誤字修正backfill用SQL（20260923000002内の一回限りのデータ移行）の values リストと999件版pool-final.tsvの行数が一致するか」であり、backfillロジック自体は今回のスコープ外（過去に一度実行済みの移行データの整合性チェック）。プール縮小とは無関係のため据え置いた。
- `testCandidatePoolIsAllSafe` / `testFallbackPoolContainsSafeSeedTexts` / その他: ロジックの変更なし。ループが150件を回るだけで自動的に対応。

**全件実行: 281/281 通過**（`xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SameQTests test`）。うち `PromptGenerationTests` は26/26。

UIテスト（回帰サンプル、直近2スプリントから2クラス）: `SprintTwentyAcceptanceTests`（8件）+ `SprintTwentyOneAcceptanceTests`（6件）= **14/14 通過**（`-only-testing:SameQUITests/SprintTwentyAcceptanceTests -only-testing:SameQUITests/SprintTwentyOneAcceptanceTests`）。スプリント23自己評価で記録されていた `SprintTwentyAcceptanceTests` の1件の既知の不安定挙動（`test03_termsAcceptanceDateIsShownInSettings`）は今回は再現せず、全件通過した。

## 動かし方（evaluator 向け）

- ビルド: `xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' build`
- ユニットテスト: `xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SameQTests test`
- UI回帰サンプル: `xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SameQUITests/SprintTwentyAcceptanceTests -only-testing:SameQUITests/SprintTwentyOneAcceptanceTests test`
- サーバー側の再検証: 本機同様に Docker が無い場合は、Homebrew `postgresql@16` で `auth` スキーマ・`auth.uid()` スタブを用意した上で `supabase/migrations/*.sql` を昇順に `psql -f` 適用（スプリント22/23の手順と同じ）。**本番への `supabase db push --linked` は今回一切行っていない**（コーディネーターの最終確認後に実施する指示のため）。

## 自分で見つけた弱点・未検証事項

- PostgREST 経由の公開・実際の JWT による `auth.uid()` 解決・Supabase Studio 経由の動作は未検証（Docker が無い環境の既知の限界。スプリント22/23と同様）。
- 150件に縮小したことで、同じお題が戻ってくる間隔は約5ヶ月になる。ユーザーが長期間（1年以上）使い続けた場合に同じお題に2回出会う頻度が上がる点は、今回の縮小方針として明示的に受け入れられている（`.product/spec.md` 前提30に理由を記載済み）。
- 999件版の残り849件（150件に選ばれなかった分）は今回削除も改変もしていない。将来また拡張したくなった場合の予備として `pool-final.tsv` にそのまま残っている。

## 提案（今回はやらなかったこと）

- 選ばれなかった849件・未カバーの102件（150件のうち運営回答が無い102件）に対する運営回答の追加バッチは、今回のスコープ外（ユーザー原文に「必要な追加作業を約7バッチに減らす」とある、次スプリント以降の話）。
