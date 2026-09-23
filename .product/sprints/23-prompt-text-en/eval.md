# スプリント23 評価（attempt 1） — 不合格

対象: お題に予備の英語原文 `text_en` を持たせる（ja の誤字修正を含む）。

## 判定サマリ

| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/7（条件1が不成立。英訳に文法崩れ・意味ずれがある） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / ユニット 275/275 / UI 14/14 + 評価用 UI 7/7 | 0 | ✓ |
| 3 データ整合性 | Swift⇔SQL⇔TSV 999/999 一致。backfill・キー更新・冪等性に問題なし | 100% | ✓ |
| 4 回帰 | 4/4（お題表示・タイムラインのお題帯・シードの英語優先・Sprint20/21 UI） | 100% | ✓ |
| 5 使用性 | 4（日英韓すべて読める言語で出る。「準備中…」の流れは変わっていない） | 3以上 | ✓ |

**不合格の理由は条件1の英訳の質だけ。** データを直せば通る。サーバー・アプリのロジックは問題なし。

## 条件ごとの結果

| # | 条件 | 結果 |
|---|---|---|
| 1 | pool-final.tsv の機械チェック・パイロット一致・英訳の質・ja 修正の範囲 | **✗**（機械チェック・パイロット一致・ja 修正の範囲は ✓。英訳の質で ✗） |
| 2 | Swift ja/en ⇔ SQL の完全一致、旧プールとの添字の対応 | ✓ |
| 3 | 本番の現状の上に積めるか（official_answers キー・今日以降の prompts・カテゴリ判定） | ✓ |
| 4 | ローカルDB（全適用・冪等・ensure_todays_prompt・ensure_official_answers 10件） | ✓ |
| 5 | ビルド・ユニット全件・新規テストの中身・Sprint20 test03 の切り分け | ✓ |
| 6 | シミュレータ（英語・韓国語・日本語端末、FakeTranslate あり/なし） | ✓（実機での機械翻訳優先は手動確認が要る） |
| 7 | 回帰（お題表示・promptStrip・SeedCatalog） | ✓ |

## 検証環境

- 2026-09-23 09:15〜13:50 JST。本機 macOS 26.6、Xcode（iOS 26.5 シミュレータ）。
- **作業ツリーが並行して変わっていた**ため、評価開始時（09:14）の作業ツリーを
  スクラッチ領域にスナップショットし（`rsync`、`.git`/`build` を除く）、そこでビルド・テストした。
  評価終了時に、スプリント23の対象ファイル11本（Swift 8本・マイグレーション2本・pool-final.tsv）が
  スナップショットとバイト一致することを `cmp` で確認済み（評価中に変わっていない）。
- シミュレータは評価専用に3台を新規作成して使い、終了後に削除（他セッションの起動中のシミュレータには触れていない）。
- **起動したバックエンドは LocalBackend のみ**（`-SameQUseLocalBackend`）。SupabaseBackend で起動すると
  本番に匿名ユーザー作成・RPC 実行の書き込みが走るため、依頼の禁止事項に従い起動していない。
- 本番DBへは `supabase db query --linked "select ..."` の読み取りのみ。REST への読み取り GET を1回
  （公開キー、`prompts?select=...`）。書き込みは一切なし。
- ローカルDB: Homebrew PostgreSQL 16.15 を `initdb` した隔離インスタンス（127.0.0.1:55433）で代替。
  シム（`auth` スキーマ・`auth.users`・`auth.uid()` を GUC から読むスタブ・`anon`/`authenticated` 等のロール）。
  終了後 `pg_ctl stop` 済み。既存の postgresql@16 サービスには触れていない。

### 並行作業との切り分け（コーディネーターの指示どおり判定から除外）

- `SameQTests/OfficialAnswerLanguageFilterTests.swift`（未追跡）と `SameQ.xcodeproj/project.pbxproj` の差分は
  スナップショット取得**後**に現れたもので、スナップショットには pbxproj の変更が入っていない（HEAD と同一）。
  そのためスプリント23の判定用テスト（275件）にはこのファイルは含まれていない。
- `SameQ/Backend/SupabaseBackend.swift` の `is_official` 絞り込み（`filterOfficialRowsByDeviceLanguage`・
  `PostRow` の `internal` 化）もスプリント23の self-review に記載が無く、上記テストファイルと対になる
  並行作業の変更と見られる（09:13 に更新）。スプリント23の判定からは除外した。
  本番の `world_timeline` に `is_official` 列があることは SELECT で確認済み（列不在で壊れることは無い）。
- **ビルド・テストへの影響**: 現在の作業ツリー（並行作業の変更込み）でもユニットを別途回した結果
  **280/280 通過**（うち5件が OfficialAnswerLanguageFilterTests）。ビルドは壊れていない。

## 不合格の原因（これを直せば通る）

### [1] 英訳の一部が文法的に崩れている／原文と意味がずれている（条件1）

- **再現手順**: `.product/prompt-pool-v2/pool-final.tsv` の該当 pos の4列目を読む。
  ランダム70件（seed=20260923、パイロット範囲外）の目視で pos531 の文法崩れに当たり、
  その後テンプレート生成の群（「この一年で、はじめて気づいた」77件・「いま、自分の体のどこ」85件・
  「好きな〜をひとつだけ」165件）を全件、残りの個別訳群も約400件を目視した。
- **期待**: 受け入れ条件1「意味が通るか・原文の意味と合うか」。英語端末・韓国語端末などで翻訳が
  使えないときにそのまま画面に出る文なので、文法的に正しく、原文の意味に沿っていること。
- **実際**（直すべきもの。全件）:

| pos | 日本語 | 現在の text_en | 問題 |
|---|---|---|---|
| 1 | この一年で、はじめて気づいた自分の手伝えるタイミングは？ | This year, what's a sense of when you can help you discovered about yourself? | 意味が通らない（help you discovered と読める） |
| 460 | この一年で、はじめて気づいた自分の大事にしている空気は？ | This year, what's **a air** you noticed you truly value? | 冠詞 a→an（または無冠詞） |
| 531 | この一年で、はじめて知った言い回しは？ | This year, what's **a expression** you learned about for the first time? | 冠詞 a→an |
| 786 | この一年で、はじめて気づいた自分の大事にしている夕方は？ | This year, what's **a evening** you found out you love? | 冠詞 a→an |
| 26 | この一年で、はじめて気づいた自分の新たな一面は？ | This year, what's a new side **of yourself** you discovered **about yourself**? | about yourself の重複 |
| 197 | この一年で、はじめて気づいた自分の意外な面は？ | This year, what's a surprising side **of yourself** you discovered **about yourself**? | 同上 |
| 233 | この一年で、はじめて気づいた自分の好きなところは？ | This year, what's a thing you like **about yourself** you discovered **about yourself**? | 同上 |
| 212 | いま、自分の体のどこを敏感にしたいですか？ | Right now, what part of you wants to make more sensitive? | 他動詞の目的語が無く文として成立しない |
| 360 | いま、自分の体のどこを止めたいですか？ | Right now, what part of you wants to bring to a stop? | 同上 |
| 110 | いま、自分の体のどこが一番つらいですか？ | Right now, where in your body feels the most tense? | 意味ずれ（つらい＝痛む・しんどい。tense は「緊張」で pos55 と同義になる） |

- **根拠**: 冠詞は `re.search(r"\b[aA] [aeiouAEIOU]", text_en)` で全999件を走査して3件（460/531/786）のみ。
  about yourself の重複は該当群77件の全件目視。
- **直すときの注意**: text_en は4か所にある。`pool-final.tsv`・`PromptCatalog.candidatePoolEn`・
  マイグレーションの `v_pool_en`・**マイグレーションの backfill の `values` リスト（3列目）**。
  同期テスト `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays` は `v_pool_en` しか見ないので、
  backfill 側の書き換え漏れは検出されない（下の改善提案 P2）。
- **推測（症状とは別）**: 「この一年で…」は `This year, what's a {X} you discovered about yourself?` の
  固定テンプレートに、すでに yourself を含む名詞句や関係節をそのまま差し込んだため。
  「どこを〜したいですか」は `what part of you wants to {動詞}` に他動詞句を差し込んだため。

## 確認できたこと（合格した条件の根拠）

### 条件1（データ）の機械チェック・パイロット・ja 修正
- 999行・全行4列・pos 0〜998 が昇順で欠けも重複もなし。text_ja・text_en とも重複0、空0。
- text_en: 18語超0件、`?` で終わらない行0件、`Do/Does/Did/Have/Has/Had/Is/Are/Was/Were/Can/Could/Would/Will/Should/Shall/Am`
  で始まる行0件（先頭の "As a kid, did you…" 型は基準どおり許容）。非ASCII文字0件。
- pos 238〜337 の100件は `pool-pilot.tsv` の英訳と100/100一致。パイロットの ja 列も text_ja_old と一致。
- `text_ja_old` は HEAD の `PromptCatalog.candidatePool` と999/999一致（＝旧プールそのもの）。
- ja の修正は **34行**、差分を全件目視した。24件の「ととしたら」・助詞/脱字（pos7, 224, 316, 318, 426, 617, 750, 941）は
  誤字・助詞の範囲。判断が要るもの2件は改善提案 P3 に書いた（不合格の理由にはしていない）。
  「ととしたら」「をを」「がが」等の残存も走査し、残りは0件（pos633「方法でできた」は正しい文）。

### 条件2（同期）
- Python で抽出して比較: `candidatePool` == TSV text_ja == SQL `v_pool_ja`（999/999、順序一致）、
  `candidatePoolEn` == TSV text_en == SQL `v_pool_en`（999/999）。
- 添字の対応: 変更された34行はすべて同じ pos の文字修正のみで、並び替え・挿入・削除なし。
- 本番の現行 `ensure_todays_prompt()` を `pg_get_functiondef` で読み、配列が HEAD の Swift 旧プールと999/999一致、
  添字計算 `((day_index % size) + size/2) % size` が新マイグレーションと同一であることを確認。
- **同期テストが本当に効くかのミューテーション確認**: スナップショットの SQL の `v_pool_en` を1文字変えて
  `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays` を回すと **失敗する**ことを確認（戻して再度通過）。

### 条件3（本番に積めるか。すべて読み取りで照合）
- 本番 `supabase_migrations.schema_migrations` の最新は `20260923000001`（スプリント22 適用済み）。`prompts` に `text_en` 列はまだ無い。
- 本番 `official_answers`: 480行・48キー。キーのうち今回 ja を直した文に当たるのは **5件**
  （いま、好きな季節/時間/景色/音 の「ととしたら」4件＋「最近、好きなった匂い」）。
  マイグレーションの `update official_answers` の対象5件と**完全一致**（取りこぼし0・余分0）。
  48キーはすべて旧プールに存在する。
- 本番の `prompts`（直近）: `prompt_20260921`・`prompt_20260922`（ends 09-23 04:00 UTC）のみで、照会時点（00:16 UTC）
  では今日以降の行は0件。今日以降5日分の予定お題（pos239〜243）はいずれも ja 修正の対象外で、
  backfill は `text` を変えず `text_en` だけを埋める形になる（ローカルで実測、下記）。
- カテゴリ判定: 本番の `ensure_official_answers()` の `like '今日%'/'最近%'/'いま%'/'小さい頃%'/'子どもの頃%'/'もし%'/'この一年%'`
  を999件の旧・新 ja に当てて比較し、カテゴリが変わるお題は0件。

### 条件4（ローカルDB）
- 全23本を `ON_ERROR_STOP=1` で順に適用してエラー0。
- 本番に近い状態を作ってから新マイグレーションを適用: `20260923000001` まで適用 → 旧関数で今日の行を生成 →
  過去（9/1）・未来（10/1, 10/2）に typo 付きの行、未来に独自文言の行を挿入 → 新マイグレーション。
  - 1回目: `UPDATE 3`（今日の行に text_en、10/1・10/2 を新 ja＋text_en に）、`UPDATE 50`（official_answers）。
  - 過去の 9/1 の typo 行と、プールに無い独自文言の行は未変更。
  - 2回目: `UPDATE 1`（今日の行を同じ値で再更新するだけ）・`UPDATE 0`。**prompts 全体の md5 が1回目の後と同一**＝冪等。
    （self-review の「2回目はすべて UPDATE 0」は不正確だが、状態は変わらないので実害なし）
  - official_answers は 480行・48キー・typo キー0。キー以外（persona/lang/body）は1行も変わっていない（EXCEPT で差分0）。
- 新規DBで `ensure_todays_prompt()` → `prompt_20260923` が `text='いま、自分の体のどこが落ちついていますか？'`,
  `text_en='Right now, where in your body feels calm?'` で作られる。
- **48キーすべて**を順に今日のお題にして `ensure_official_answers()` を実行: 全48件で `source=custom inserted=10`、
  投入された10件は ja5/en5 で、すべてそのキーの official_answers の本文と一致（不一致0）。

### 条件5（アプリ・テスト）
- ビルド成功。ユニット **275/275 通過**（スナップショット＝スプリント23のみ）。新規4件
  （`testPromptFallsBackToTextEnWhenTranslationUnavailable`・`…ToJapaneseWhen…NoTextEn`・
  `testPromptPrefersMachineTranslationOverTextEnWhenAvailable`・`testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays`）はすべて実行されて通過（skip ではない）。
- 新規テストの中身: 仕様①（翻訳成功なら text_en があっても `[EN] 原文` が出る）、②（`.unavailable` なら text_en）、
  ③（text_en が nil なら ja）をそれぞれ1件ずつ検証しており、仕様に対応している。
- `SprintTwentyAcceptanceTests`: スプリント23のスナップショットで **8/8 通過**、HEAD を `git worktree add` で出したものでも **8/8 通過**。
  generator が報告した test03 の失敗はどちらでも再現せず、**変更由来ではない（タイミング依存の不安定さと判断）**。
  - 補足: HEAD の worktree は最初 `.env.local` が無く、ビルド時の GenerateSecrets で空の Secrets.swift ができ
    RevenueCat 未設定で起動直後にクラッシュした（環境の問題）。`.env.local` を置いて再実行した結果が上の 8/8。
- `SprintTwentyOneAcceptanceTests` 6/6 通過（スナップショット）。

### 条件6（シミュレータで実操作）
スナップショットの UI テストターゲットに評価用のテストを一時的に足し（**リポジトリには足していない**）、
端末の言語は `simctl spawn defaults write -g AppleLanguages/AppleLocale` → 再起動で切り替えた。
起動は `-SameQUseLocalBackend -SameQResetState -SameQSkipSeed`（シードではなく PromptGenerator の今日のお題 pos239 が出る）。
オンボーディング → 今日のお題を読む → 回答 → タイムラインのお題帯を読む、まで操作した。
操作中 3 秒おきに `xcrun simctl io <udid> screenshot` を撮り、並べたものを目視した。

| 端末言語 | FakeTranslate | 今日のお題 | タイムラインのお題帯 | 判定 |
|---|---|---|---|---|
| 英語 | なし | Right now, where in your body feels calm? | 同左 | ✓ 翻訳失敗 → text_en |
| 英語 | あり | [EN] いま、自分の体のどこが落ちついていますか？ | 同左 | ✓ 機械翻訳が text_en より優先 |
| 韓国語 | なし | Right now, where in your body feels calm? | 同左 | ✓ 翻訳失敗 → text_en（英語） |
| 韓国語 | あり | [KO] いま、自分の体のどこが落ちついていますか？ | 同左 | ✓ 機械翻訳優先 |
| 日本語 | なし／あり | いま、自分の体のどこが落ちついていますか？ | 同左 | ✓ 日本語原文 |

- 証跡: `.product/sprints/23-prompt-text-en/eval-shots/`（`*_today.png`・`*_timeline.png`・`simctl_sheet_{en,ko,ja}.png`＝simctl の連続撮影を並べたもの）。
- 再起動の確認: 英語端末でオンボーディング後にアプリを終了 → リセットなしで再起動し、同じ英文が出続けることを確認。
- 「準備中…」→確定の流れ: 変更は `.unavailable` 分岐の代入1行のみで、`today.promptLoading` の表示条件は未変更。
  連続撮影ではお題が1フレーム目から確定表示で、日本語が一瞬出て英語に切り替わるようなちらつきは見られなかった。
- **実機の英語端末で「翻訳モデルが使えるときに機械翻訳が text_en より優先される」ことは自動化できない。手動確認が要る**
  （シミュレータでは Apple Translation が常に失敗するので、実際の翻訳成功経路は FakeTranslate とユニットテストでしか確認できていない）。

### 条件7（回帰）
- お題表示（今日の画面）とタイムラインのお題帯（`timeline.promptText`）が3言語とも同じ文言で出る（上表）。
- SeedCatalog: 変更は `textEn:` を渡す1行のみで、非日本語端末でシードの英語を優先するロジックは未変更。
  シードありで英語端末を起動し、今日のお題が英語で出ることを確認。SeedCatalog を使うユニット（PromptLifecycle 等）も全件通過。
- Sprint20（8/8）・Sprint21（6/6）の UI テスト通過。

## 改善提案（合否には影響しない）

- **P1（高・出す順番）**: 新アプリは `prompts` を `select=id,text,starts_at,ends_at,text_en` で読む。本番に今この列は無く、
  公開キーでの読み取り GET で `HTTP 400 {"code":"42703","message":"column prompts.text_en does not exist"}` を確認した。
  つまり**マイグレーションを本番に入れる前に新アプリ（TestFlight・Debug の既定の SupabaseBackend も含む）を動かすと、お題が取れない**。
  計画どおり「サーバーを先に push → 本番を SELECT で確認 → アプリ」の順を必ず守ること。列が無いときは
  `text_en` を外して取り直すなど、アプリ側で耐える作りにしておくとより安全。
- **P2（中）**: 同期テストは `v_pool_en` だけを見ており、backfill の `values` リスト（old_ja, new_ja, en）は見ていない。
  今回は3者一致を確認したが、英訳を直すときに backfill 側だけ古いままでも検出されない。テストで backfill リストも照合するとよい。
- **P3（低・ユーザー判断）**: ja 修正のうち2件は純粋な誤字修正ではなく、推測を含む:
  pos908「すごしてたえた」→「すごして**癒えた**」（原文が崩れていたための推測。「癒えた」は傷に使う語で、「癒やされた」の方が自然かもしれない）、
  pos963「みっつ何を何を」→「みっつ**だけ**何を」（「何を」の重複を消すだけなら「みっつ何を買いますか」で足り、「だけ」は追加）。
  意味は大きく変わらないので不合格の理由にはしていない。
- **P4（低）**: 「もし一日だけ〜」146件のうち124件を "…today" と訳している（パイロット10件は "for a day" 系で today は0件）。
  「一日だけ」の含みが「今日」に変わっている。問いとしては成り立つが、パイロットと揃えるなら "for a day" に寄せる。
- **P5（低）**: 「自分の許せる／譲れない／譲りたくなるポイント」系（58, 195, 229, 543, 578, 922）の
  "a thing you can forgive you discovered about yourself" は文法上は成り立つが読みにくい。
- **P6（低）**: `fallbackPool` に text_en が無い（self-review の弱点1どおり。候補999件が全滅する極端なケースのみ）。

## 評価できなかったもの

- 実機の英語端末で、Apple Translation が成功したときに機械翻訳が text_en より優先されること（**手動確認が要る**）。
- SupabaseBackend での起動（本番への書き込みになるため起動していない）。Supabase 経由の `text_en` の受け渡しは、
  コード（select と `Prompt(textEn: row.text_en)`）と REST の列エラーの確認までにとどまる。
- `supabase db reset`（Docker が無い）。PostgREST 経由の公開、実 JWT での `auth.uid()`、Supabase の既定の権限は未検証（スプリント22と同じ限界）。
- 空入力・極端に長い入力は、今回の変更（お題の表示元）には入力経路が無いため試していない。

---

# スプリント23 評価（attempt 2） — 合格

## 判定サマリ

| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7/7（attempt 1 で落ちた条件1の英訳の質を再確認して通過） | 100% | ✓ |
| 2 安定性 | クラッシュ0 / ユニット 281/281（うち5件は並行作業の OfficialAnswerLanguageFilterTests） | 0 | ✓ |
| 3 データ整合性 | TSV・Swift・SQL 配列・backfill リストの4か所が999/999一致。冪等性も確認 | 100% | ✓ |
| 4 回帰 | 修正対象外のランダム60件・パイロット100件・日本語32行が変わっていない。ロジックのファイルは attempt 1 とバイト一致 | 100% | ✓ |
| 5 使用性 | 4（attempt 1 と同じ。表示ロジックは変わっていない） | 3以上 | ✓ |

## 検証環境

- 2026-09-23 13:55〜14:20 JST。attempt 1 と同じく、評価開始時の作業ツリーをスナップショット（`snap2`）にしてそこでビルド・テストした。
  評価終了時に、対象のファイル10本がスナップショットとバイト一致することを `cmp` で確認した（評価中に変わっていない）。
- attempt 1 のスナップショットと比べて変わったのは、`pool-final.tsv`・`PromptCatalog.swift`・`20260923000002_prompt_text_en.sql`・
  `PromptGenerationTests.swift`（と並行作業の pbxproj）のみ。`Prompt.swift`・`SupabaseBackend.swift`・`PromptGenerator.swift`・
  `SeedCatalog.swift`・`AppSession.swift`・`AppSessionTranslationTests.swift` は attempt 1 とバイト一致（＝表示ロジックは変わっていない）。
  `20260923000001` は HEAD と一致。
- 本番は読み取りのみ（`supabase db query --linked "select ..."`）。ローカルDBは attempt 1 と同じ隔離 PG16（終了後に停止）。
  シミュレータは評価専用に作って削除した。

## 確認したこと

### 1. 機械的に置き換えた「もし一日だけ」113行を全件読んだ
- attempt 1 → 2 で英語が変わった行は135行: 「もし一日だけ」124行（手で書き直した11行＝149, 354, 392, 394, 453, 537, 603, 639, 684, 736, 842 を含む）、
  指摘10行＋pos753。**機械置換だけの行は113行**（依頼文の「134行」と数は違うが、差分を実際に数えた数字）。
- 113行すべてを読んだ。文法の崩れ・語の衝突（"for a day today"・"for a day for a day" のような重複、"all day for a day" 等）は **0件**。
  機械チェックでも、「もし一日だけ」に "today" が残っている行0件、単語の2連続重複0件。
- 意味: どれも原文の「一日だけ〜できるとしたら」に沿っている。ただし約15行は、"for a day" が一回で終わる動作に付いているため
  「一日だけ貸す／一時的に」とも読める（下の改善提案 A2-P1）。日本語の原文も同じ構造（「一日だけ何かを捨てるなら」など）で、
  意味が原文とずれてはいないので不合格の理由にはしていない。

### 2. 指摘10行＋pos753＋手で書き直した11行
全22行を読み、すべて文法的に正しく、原文の意味に合っている。
- 1 "This year, when did you first discover you had a good sense for when to help?"／26・197 は about yourself の重複が解消／
  233 "…something you like about yourself that you only just noticed?"／212 "…wants to become more sensitive?"／360 "…wants to come to a stop?"／
  460・531・786 は an に修正／110 "…feels the most pain?"（つらい＝痛み。緊張の pos55 と区別できた）／753 "What's your favorite sound you're hearing right now?"
- 手で書き直した11行（149, 354, 392, 394, 453, 603, 684, 736, 842, 537, 639）は自然な英文で、意味も合っている。
  537・639 は18語以内で、171・487 とは文言が重複しない。
- 日本語の2行: 908「誰かと同じ時間をすごして癒やされた瞬間は？」、963「いま、自分のためにそっとみっつだけ買えるとしたら何を買いますか？」。
  どちらも依頼どおりの文言で、英訳（soothed／treat yourself to three things）とも合っている。

### 3. それ以外の行に回帰がないか
- 英語が変わっていない行（パイロット範囲を除く）から、attempt 1 とは別の seed（424242）で60件を抜いて読んだ。問題なし
  （pos58 の読みにくさは attempt 1 の P5 のまま）。
- パイロット100件は `pool-pilot.tsv` と100/100一致のまま。`text_ja_old` 列は attempt 1 と同一（旧プールの添字どおり）。
  日本語が変わったのは908と963の2行だけ。
- 全999件に機械チェックを再実行: 999行・4列・pos 0〜998 が順に並ぶ。英語・日本語とも重複0。18語超0、`?` で終わらない行0、
  yes/no 型の書き出し0、`a`＋母音0、非ASCII0。

### 4. 4か所の同期・新しいテスト・本番のキー
- TSV の text_ja／text_en ＝ `candidatePool`／`candidatePoolEn` ＝ SQL `v_pool_ja`／`v_pool_en`（999/999）。
  **backfill の `values` リスト（999行）が TSV の (old_ja, new_ja, en) と3列とも完全一致**。official_answers のキー更新は5件のまま。
- **新しいテスト `testBackfillValuesListMatchesPoolFinalTsv` を壊して確認した**: スナップショットの SQL で backfill リストの
  en を1件だけ（pos998）書き換えると、このテストは **失敗**した（`…someone TODAY…` と `…someone for a day…` が一致しない、と表示）。
  このとき既存の `testCandidatePoolAndCandidatePoolEnMatchSqlMigrationArrays` は **通過**しており、新しいテストが attempt 1 の
  抜け穴を実際に塞いでいることを確認した。確認後に元へ戻し、リポジトリのファイルと一致することも確かめた。
- 本番の読み取り: `official_answers` は480行・48キー。pos908・963 は、旧文言・新文言・attempt 1 の文言のどれも48キーに含まれない。
  日本語を直した34行のうち、旧文言がキーに当たるのは5件（224, 267, 659, 893, 956）で、マイグレーションの更新5件と一致する。
  本番の最新マイグレーションは `20260923000001` のまま（今回のマイグレーションは未適用）。

### 5. ビルド・テスト・ローカルDB
- ビルド成功。ユニット **281/281 通過**（スプリント23のテスト276件＋並行作業の5件）。スプリント23の新規テスト5件はすべて実行されて通過した（skip なし）。
- PG16: 新しいDBに23本を順に適用してエラー0。`ensure_todays_prompt()` が `text_en` 付きで今日の行を作る。
- 本番に近い状態から新しいマイグレーションを適用した: 過去の typo 行、未来の typo 行（908・963 の旧文言と「好きなった」）、
  プールに無い独自のお題を入れておいた。
  - 1回目 `UPDATE 4`／`UPDATE 50`。今日の行に text_en が入り、未来の3行は新しい日本語＋text_en に変わった。過去の行と独自のお題は変わらない。
  - 2回目 `UPDATE 1`（同じ値での上書き）／`UPDATE 0`。**prompts と official_answers の md5 が1回目の後と同じ**なので冪等。
  - official_answers は480行・48キー・typo 0。キー以外の列（persona/lang/body）の差分は0。
- **48キーすべて**を今日のお題にして `ensure_official_answers()` を実行した: 全件10件（日本語5・英語5）で、本文も official_answers と一致（不一致0）。
- シミュレータで1件確認: 英語端末・LocalBackend・翻訳なしで、`-SameQTimeOffsetMinutes 154080`（107日後。
  機械置換された pos346 が今日のお題になる日）で起動すると、今日のお題に
  "If you could climb a mountain for a day, which one would you climb?" が出た
  （`eval-shots/a2_future_en.png`）。表示ロジックは attempt 1 とバイト一致なので、3言語の実操作は attempt 1 の結果がそのまま当てはまる。

## 不合格の原因
なし。

## 改善提案（合否には影響しない）
- **A2-P1（低）**: 機械置換の行のうち約15行は、"for a day" が一回で終わる動作の後ろに付き、「一時的に」とも読める:
  3, 10, 15, 40（あげる・手渡す・贈る・届ける）、440（捨てる）、623（新しく買う）、919（残す）、522, 652, 656, 973（書いてもらう・描いてもらう・届ける言葉）、
  59, 223, 439, 983（気づいてほしい・感じ取ってほしい・見直してほしい・知ってほしい）。
  "For one day, if you could …" のように文頭に出すと自然になる。原文も同じ構造なので、急がない。
- **A2-P2（低）**: 新しいテストは backfill の `new_ja`／`en` だけを見ていて、`old_ja` 列（本番の既存の行と照合するキー）は見ていない。
  今回は3列一致を確認済み。また、SQL の書式が変わってパースに失敗すると **fail ではなく skip** になる（`XCTSkip`）。気づかずに素通りしうる。
- **P1（attempt 1 から継続・高）**: 本番にマイグレーションを入れる前に新しいアプリを動かすと、お題の取得が `42703` で失敗する。
  出す順番は「`supabase db push` → 本番を SELECT して `text_en` 列を確認 → アプリ」を守ること。
- attempt 1 の P5（58, 195, 229, 543, 578, 922 の読みにくさ）と P6（fallbackPool に text_en が無い）はそのまま。

## 評価できなかったもの
- attempt 1 と同じ: 実機の英語端末で機械翻訳が text_en より優先されること（**手動確認が要る**）、SupabaseBackend での起動、`supabase db reset`（Docker なし）。
