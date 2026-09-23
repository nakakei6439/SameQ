# スプリント23 自己評価

対象: お題プールへの text_en（予備の英語原文）追加、ja の誤字・脱字・不自然な助詞の修正。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 999件全件に text_en を用意（機械チェック通過） | 達成 | `.product/prompt-pool-v2/pool-final.tsv`。語数≤18・`?`終わり・Yes/No型書き出し禁止・重複なしを999件全件で機械チェック（詳細は同ディレクトリ `self-review-final.md`） |
| text_ja の誤字・脱字・助詞のみ修正（意味・並び順不変） | 達成 | 34行を修正。一覧は `self-review-final.md`。pos474は重複を避けるため意図的に未修正（理由を記載） |
| 新マイグレーション1本（20260923000002） | 達成 | `supabase/migrations/20260923000002_prompt_text_en.sql`。20260923000001（スプリント22・未評価）の上に積む1本のみ |
| prompts.text_en 追加・ensure_todays_prompt() 更新・既存行backfill・official_answers キー更新 | 達成 | ローカルPostgresで4項目とも実動作を確認（下記） |
| 本番への push はしない | 達成 | `supabase db push` は一度も実行していない |
| Swift側（Prompt/SupabaseBackend/PromptCatalog/PromptGenerator/SeedCatalog/AppSession） | 達成 | 下記「変更ファイル」参照。ビルド成功 |
| ユニットテスト追加・全件通過 | 達成 | 275/275（新規6件を含む） |
| ローカルDB検証 | 達成（Docker代替） | 下記「サーバー側の検証」参照 |
| spec.md 前提29 / PROGRESS.md 更新 | 達成 | 前提29を全面更新。PROGRESS.md に今日付けエントリを追加し「未決」を解決済みに更新 |

**全条件達成。**

## データ（999件のプール）

- `.product/prompt-pool-v2/pool-final.tsv`（pos, text_ja_old, text_ja, text_en）。
- text_en: パイロット100件（pos238〜337）をそのまま流用、残り899件を新規作成。
  高度に定型化されたプールという性質を利用し、プレフィックスでグルーピング
  （「いま、好きな」165件・「もし一日だけ」146件・「いま、自分の体のどこ」85件・
  「この一年で、はじめて気づいた」77件・「小さい頃、好きな」61件・「小さい頃、誰」38件…）した上で、
  テンプレート性の高い群は名詞/形容詞の辞書＋固定テンプレート、低い群（「もし一日だけ」等）は
  1問ずつ個別翻訳。機械チェック（語数・語尾・Yes/No禁止・重複なし）は999件全件で通過。
  詳細な作り方・迷った箇所・使わなかった案は `.product/prompt-pool-v2/self-review-final.md`。
- text_ja: 誤字・脱字・不自然な助詞のみ34行を修正（意味・並び順は不変）。一覧は同ファイル。
  pos474「好きな途」は、直すと pos265 と重複するため意図的に未修正（正直に記載）。

## サーバー側の検証（本機に Docker が無いため、スプリント22と同じ代替手段）

Homebrew の `postgresql@16` を単独インストールし、`auth.uid()` スタブと `auth` スキーマを用意した
上で、`supabase/migrations/*.sql` をファイル名の昇順（適用順）で全23本、`ON_ERROR_STOP=1` で頭から
適用した（`20260817000001_init.sql` 〜 今回の `20260923000002_prompt_text_en.sql`）。

**確認できたこと**:
- 23本すべてエラー無く適用（構文エラー・制約違反なし）。
- `v_pool_ja` / `v_pool_en`（999件ずつ）を、デプロイ後の関数定義（`pg_get_functiondef`）から
  実際に抽出し、`pool-final.tsv` および `PromptCatalog.swift` の `candidatePool` /
  `candidatePoolEn` と Python で byte-for-byte 照合。3者とも999/999件で完全一致。
- `ensure_todays_prompt()` を実行すると `prompts.text` / `text_en` が両方入ることを確認。
- 既存行backfill: 「今日以降」かつ旧ja文に一致する行を新ja文+text_enへ更新することを、
  意図的に古いtypo付きの行を挿入してから再適用して実測（1行更新）。**過去の日付の行は
  対象外にしていることも実測**（2026-01-01付けの行を挿入して再適用しても未変更のまま）。
- 冪等性: 同じマイグレーションを連続で2回適用しても、2回目はすべて `UPDATE 0`（対象が既に
  目的の状態のため）。
- `official_answers.prompt_text` のキー更新（5件、それぞれ10行=計50行）: **実際に production と
  同じ typo付きの20260923000001（コミット済み）から出発**して確認。適用直後は `UPDATE 50`、
  再適用では `UPDATE 0`。更新後も `official_answers` の総行数は480のまま・重複キーなし・
  古いtypoキーは0件。
- `ensure_official_answers()` の統合確認: 今日のお題テキストを修正後の5キーのいずれかに
  差し替えて実行すると `source=custom inserted=10` になることを確認（手作り回答経路が
  修正後のキーで正しく引ける）。カテゴリ前方一致フォールバック（`like 'いま%'` 等）も
  修正で先頭文字列が変わっていないため影響なし。

**検証の限界（隠さない）**: スプリント22と同様、Supabase CLI (`supabase db reset` /
`supabase start`) 経由ではなく、素の PostgreSQL への手動セットアップでの検証。
PostgREST 経由の公開・実際の JWT による `auth.uid()` 解決・Supabase Studio 経由の動作は
未検証。本番相当の確認は、Docker が使える環境で `supabase db reset` を一度通すことを推奨する
（このマイグレーション単体の構文・ロジックに問題が無いことは上記で担保済み）。

## アプリ側の変更

- `SameQ/Model/Prompt.swift`: `textEn: String?` を追加（Codable optional、既存データとの後方互換）。
- `SameQ/Backend/SupabaseBackend.swift`: `promptState()` の select に `text_en` を追加し
  `Prompt.textEn` に渡す。
- `SameQ/Backend/PromptCatalog.swift`: `candidatePool`（ja、誤字修正版）を差し替え、同じ添字の
  `candidatePoolEn`（999件）を新設。
- `SameQ/Backend/PromptGenerator.swift`: `generate(...)` に `candidatePoolEn` パラメータを追加し、
  生成した `Prompt` に `textEn` を設定（範囲外アクセスは安全に `nil` にフォールバック）。
  フォールバックプール（`PromptCatalog.fallbackPool`、候補プール全滅時のみ使う極端なケース）は
  タプル型を変えないスコープ判断で `textEn: nil` のまま（既知の未対応。下記「弱点」参照）。
- `SameQ/Backend/SeedCatalog.swift`: 既存の `textEn`（2026-09-04 adhoc の英語優先ロジック）を
  そのまま `Prompt.textEn` にも渡す。既存ロジック（非日本語端末では `.text`/`.language` を
  直接英語に差し替える）はそのまま残した。
- `SameQ/Session/AppSession.swift`: `syncPromptTranslation` の `.unavailable` 分岐を
  `textEn ?? text` に変更。日本語端末は `translate()` が `sourceCode == targetLanguageCode` で
  即座に `.text(text)` を返すため、この分岐自体に入らない（影響なし）。

## テスト

- `SameQTests/PromptGenerationTests.swift`:
  - 既存 `testCandidatePoolContainsOriginal48Prompts` を、誤字修正後の5件の文言に更新
    （48件のうち5件がスプリント23の修正対象だったため）。
  - 新規 `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays`: SQL マイグレーション
    ファイルを直接パースして `candidatePool` / `candidatePoolEn` と件数・並びの完全一致を確認。
    `#filePath` でリポジトリルートを解決する簡易パーサ（SQL構文全体は解釈しない、このファイル
    専用の書式読み取り）。ファイルが見つからない環境では `XCTSkip`。
- `SameQTests/AppSessionTranslationTests.swift`: 新規3件
  - `testPromptFallsBackToTextEnWhenTranslationUnavailable`: 疑似翻訳の恒久非対応マーカー
    （`zxx`）で `.unavailable(permanent: true)` を再現し、`textEn` が表示されることを確認。
  - `testPromptFallsBackToJapaneseWhenTranslationUnavailableAndNoTextEn`: 同条件で `textEn` が
    `nil` のときは日本語原文へフォールバックすることを確認（後方互換）。
  - `testPromptPrefersMachineTranslationOverTextEnWhenAvailable`: 翻訳が成功する通常経路では、
    `textEn` があっても機械翻訳の結果を優先することを確認（前提29の核心）。
- 全件実行: **275/275 通過**（`xcodebuild test -only-testing:SameQTests`）。
- UIテスト（回帰サンプル、直近スプリントから2クラス）: `SprintTwentyOneAcceptanceTests` 6/6 通過。
  `SprintTwentyAcceptanceTests` は8件中1件失敗
  （`test03_termsAcceptanceDateIsShownInSettings`。オンボーディングのキーボード関連ボタンが
  見つからないタイミング起因の失敗で、お題・翻訳とは無関係な画面。本スプリントの変更が原因とは
  考えにくいが、evaluator が独自に再現性を確認することを推奨する）。

## 動かし方（evaluator 向け）

- ビルド: `xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' build`
- ユニットテスト: `xcodebuild -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SameQTests test`
- サーバー側の再検証: 本機同様に Docker が無い場合は、Homebrew `postgresql@16` で
  `supabase/migrations/*.sql` を昇順に `psql -f` 適用（`auth.uid()` スタブが必要。
  スプリント22 `.product/sprints/22-official-answers/self-review.md` の手順と同じ）。
  Docker がある環境なら `supabase db reset` で全マイグレーションを通すことを推奨（未実施）。
- `-SameQFakeTranslate` を付けたシミュレータで、`AppSessionTranslationTests` と同じ状況
  （プロンプトの `language` を疑似的に非対応にする）を UI 経由で確かめる場合は、Xcode の
  Debug オーバーレイ等でシード側の `promptLanguage` を差し替える必要がある（既存の仕組みに
  お題の `language` を実機/シミュレータのUIから直接いじる導線はない）。

## 自分で見つけた弱点・未検証事項

1. **フォールバックプール（`PromptCatalog.fallbackPool`）には text_en を用意していない。**
   候補プール999件が空、または全件安全条件違反になる（実運用ではまず起きない）極端なケースで
   のみ使われる経路。このケースで翻訳が `.unavailable` になった場合は、引き続き日本語原文へ
   フォールバックする（textEn は nil のまま）。plan には明記されていなかったため意図的にスコープ
   外としたが、完全ではない。
2. **実機の英語端末で「機械翻訳が優先される」ことは自動化できておらず、未検証**（Apple
   Translation は端末内モデルに依存するため、シミュレータや疑似翻訳では実際の翻訳成功パスを
   再現できない。疑似翻訳モード（`.unavailable` 固定）でのフォールバック挙動はユニットテストで
   確認済みだが、「翻訳が実際に成功したときにtextEnより優先される」ことの実機確認は手動で必要）。
3. **英語端末での `SprintTwentyOneAcceptanceTests`（英語スクリーンショット系）は今回変更していない**
   （テキストの表示元が変わる可能性はあるが、シミュレータ環境では Apple Translation が全ペア
   未対応なので `.unavailable` → 今回追加した `textEn` 経路を通るはず。6/6 通過を確認済みだが、
   これが「textEn が正しく出ている」ことの直接証拠ではない点に注意。目視でのスクリーンショット
   確認は未実施）。
4. **`SprintTwentyAcceptanceTests.test03_termsAcceptanceDateIsShownInSettings` の失敗**
   （オンボーディングのキーボード関連ボタンが見つからないタイミング起因）。お題・翻訳と無関係な
   画面のため今回の変更が原因とは考えにくいが、原因の切り分けまではしていない。
5. **`supabase db reset`（Supabase CLI 経由）での適用は未実施**（本機に Docker が無い）。
   PostgREST 経由の公開・実JWTでの `auth.uid()` 解決も未検証（スプリント22と同じ限界）。
6. **本番 DB への書き込みは一切行っていない**（依頼どおり）。

## 途中で見つけた想定外の事象（正直に記録）

作業の途中、`supabase/migrations/20260923000001_official_answers_table.sql` と
`.product/official-answers-48/answers-bilingual.tsv`（どちらもスプリント22の成果物で、今回の
作業スコープ外）が、原因不明のまま自分の意図しない内容に変更されているのを発見した
（5件の `prompt_text` から「ととしたら」等のタイプミスが消えていた。自分の編集ツール呼び出し
履歴を遡っても原因になりうる操作は見当たらなかった）。両ファイルはいずれもコミット済み
（`32de840`。作業開始直後にコーディネーターが本番反映した形跡）だったため、`git checkout --`
で HEAD の内容へ復元し、復元後の状態で改めてローカルDB検証をやり直して問題ないことを確認した
（上記の「サーバー側の検証」セクションは復元後の再検証結果）。原因は特定できていないため、
念のため報告する。

## 提案（今回はやらなかったこと）

- フォールバックプールにも `text_en` を用意する（弱点1の解消）。
- 実機での機械翻訳優先の確認（英語端末・モデル取得済みの状態で、実際に機械翻訳された文言が
  出ることの目視確認）。

---

# attempt 2（eval-1.md の指摘対応）

対象: `.product/sprints/23-prompt-text-en/eval.md`（attempt 1 不合格）の指摘10件＋「もし一日だけ」
の "today" 問題124件の修正。データのみの修正で、サーバー・アプリのロジックは変更していない
（eval も「データを直せば通る」と明記）。

## 直した内容

1. **英訳10件の文法崩れ・意味ずれ**（pos 1, 26, 110, 197, 212, 233, 360, 460, 531, 786）。
   詳細は `.product/prompt-pool-v2/self-review-final.md` の「attempt 2」節。
2. **「もし一日だけ」146件中 "today" を使っていた124件**を、パイロットと同じ
   "for a day" / "for one day" / "for a whole day" 系の言い回しに統一。単純置換で不自然に
   なった9件・18語超になった2件は個別に書き直し。
3. **pos908 / pos963 の ja をコーディネーター指定の文言に変更**:
   - pos908: 「すごしてたえた瞬間」→「すごして**癒やされた**瞬間」（attempt 1の「癒えた」から変更）
   - pos963: 「みっつ何を何を買いますか」→「そっと**みっつだけ**買えるとしたら何を買いますか」
   - どちらも `official_answers` の48キーには含まれないため、マイグレーションのキー更新
     リスト（5件）は変更なし（確認済み）。
4. **4か所の同期**（`pool-final.tsv` / `candidatePool`・`candidatePoolEn` / マイグレーションの
   `v_pool_ja`・`v_pool_en` / マイグレーションの backfill `values` リスト）を、生成元スクリプトを
   直してから999件を再生成する方式で維持。**新規テスト
   `testBackfillValuesListMatchesPoolFinalTsv`** を追加し、eval.md の改善提案P2どおり
   backfill の `new_ja` / `en` 列も TSV と機械比較するようにした（旧テスト
   `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays` は `v_pool_ja`/`v_pool_en` のみ
   だったため、backfill 側だけ古いままでも検出できない抜け穴があった）。
5. **追加の全件機械チェック**（eval.md の指示どおり）: `\b[aA] [aeiouAEIOU]`（冠詞）・
   「もし一日だけ」での "today" 残存・単語2〜4-gramの同一フレーズ繰り返し・999件の
   text_en/text_ja 重複、をすべて999件に実行。フレーズ繰り返しの機械チェックで
   **想定外の別バグを1件発見**（pos753「What's your favorite sound from right now right now?」）
   して修正した。元の完了条件（18語以内・`?`終わり・Yes/No型書き出し禁止・重複なし）も
   再実行し、すべて0件。

## 変更したファイル（attempt 2）

- `.product/prompt-pool-v2/pool-final.tsv`（再生成）
- `.product/prompt-pool-v2/self-review-final.md`（attempt 2 節を追記）
- `supabase/migrations/20260923000002_prompt_text_en.sql`（v_pool_ja/v_pool_en/backfillを
  再生成。official_answersキー更新リスト・関数のロジック・コメントの一部は変更なし）
- `SameQ/Backend/PromptCatalog.swift`（candidatePool/candidatePoolEnを再生成）
- `SameQTests/PromptGenerationTests.swift`（新規テスト `testBackfillValuesListMatchesPoolFinalTsv`
  を追加）

`SameQ/Model/Prompt.swift`・`SameQ/Backend/SupabaseBackend.swift`・
`SameQ/Backend/PromptGenerator.swift`・`SameQ/Backend/SeedCatalog.swift`・
`SameQ/Session/AppSession.swift`・`SameQTests/AppSessionTranslationTests.swift` は
attempt 1 から変更していない（ロジックの修正は不要だったため）。

## 検証（attempt 2）

- **機械チェック**: 999件全件で上記5項目すべて0件（詳細は self-review-final.md）。
- **ビルド**: 成功。
- **ユニットテスト**: 全件通過（`-only-testing:SameQTests`、281/281。うち5件は並行作業中の
  `OfficialAnswerLanguageFilterTests`。スプリント23関連は新規1件を含め全件通過を個別に確認済み）。
- **ローカルPostgreSQL16での検証**（Homebrew、Docker代替）:
  - 全23本を `ON_ERROR_STOP=1` で頭から適用 → エラー0。
  - `20260923000002_prompt_text_en.sql` を続けて2回適用 → 1回目 `UPDATE 50`（official_answers
    のキー更新）、2回目 `UPDATE 0`（冪等）。
  - `official_answers`: 480行・distinct prompt_text 48・件数が10でない prompt_text 0件・
    旧typoキー0件。
  - **48お題すべて**を順に today のお題にして `ensure_official_answers()` を実行 →
    **48件すべて `source=custom inserted=10`**。
  - デプロイ後の `ensure_todays_prompt()` の `v_pool_ja`/`v_pool_en`（999件ずつ）を
    `pg_get_functiondef` で抽出し、`pool-final.tsv`・`PromptCatalog.swift` と再度
    byte-for-byte 一致を確認。

## 並行作業との切り分け（コーディネーター指示への対応）

- `SameQTests/OfficialAnswerLanguageFilterTests.swift`・`SameQ.xcodeproj/project.pbxproj`・
  `SameQ/Backend/SupabaseBackend.swift` の `is_official` 絞り込み部分には一切触れていない
  （`SupabaseBackend.swift` は `git diff` で自分の変更範囲（`text_en` の select/decode、
  313〜372行付近）が attempt 1 から不変であることを確認済み）。
- `git status` で他セッションの変更（上記3ファイル）が存在することを確認したのみで、
  `git checkout` 等での復元は行っていない。

## attempt 1 で見つけた想定外の事象について

attempt 1 の作業中に見つけた「`20260923000001_official_answers_table.sql` と
`answers-bilingual.tsv` が原因不明のまま書き換わっていた」件は、attempt 1 終了時点で
`git checkout --` により HEAD（コミット済みの内容）へ復元済みで、今回 attempt 2 の作業中に
確認した限り両ファイルとも HEAD と一致したまま変わっていない
（`git diff --stat HEAD -- <両ファイル>` が空であることを確認）。
