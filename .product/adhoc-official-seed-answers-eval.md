# 単発タスク評価: 本番タイムラインに恒久的な「運営回答」を自己修復で補充する

判定: **PASS**（2026-09-07）

注記: evaluator サブエージェントが2回とも長時間 Bash（xcodebuild / maestro）で
ストリームウォッチドッグに引っかかり停止したため、実機動線の検証はコーディネーターが
直接実施した（実装は generator が担当しており、実装者と検証者は分離されている）。
何を確認済みで何が未確認かを下に明記する。

## 受け入れ条件の結果

| 条件 | 結果 | 根拠 |
|---|---|---|
| 1. `ensure_official_answers` 関数 + 運営アカウント5件が本番に存在 | ✅ | `supabase migration list --linked` に `20260905000001〜3` が Remote 適用済み。`select ... from public.users where nickname='SameQ運営'` → 5件（emoji 🏛️🏷️📜🏮🪧、UUID `00000000-…-00000000000{1..5}`、status active）。`information_schema` で関数存在確認。 |
| 2. 実機/シミュレータで新規アカウント→回答→タイムラインに運営投稿が最低5件、お題のカテゴリに沿った内容で表示 | ✅（追加修正込みで達成。下記条件6と同一） | 下記条件6参照。当初は `.exhausted` で表示されず → 別バグを発見・修正して達成。 |
| 3. 冪等性: 再実行しても運営投稿が重複せず5件のまま | ✅ | `select public.ensure_official_answers()` を2回連続実行 → `count(*) where nickname='SameQ運営' and expires_at>now()` = 5 のまま。`posts_one_per_prompt unique(prompt_id,author_id)` + `on conflict do nothing`。 |
| 4. 回帰: 運営アカウントをブロック/通報しても `world_timeline` から除外。いいね/翻訳等に悪影響なし | ✅（SQL経路） | generator self-review: 既存テストユーザーになりすまして `blocks` 挿入 → `world_timeline` が 5→4、`delete` で 5 に復帰。ビュー where 句の `not exists(reports)` は無変更なので通報も同様。**実機でのブロック操作は未確認**（SQL で構造確認のみ）。 |
| 5. Debug/Release ビルド成功、既存テスト緑 | ✅ | generator: Debug/Release `BUILD SUCCEEDED`、`PromptGenerationTests`/`PromptLifecycleTests`/`TimelineSelectionTests`/`ServerEnforcementTests`/`ReportBlockTests`/`BanAndSpamTests`/`ProfileAndAccountTests` 70/70。追加修正後に再度 42/42。コーディネーター側でも Debug 再ビルド `BUILD SUCCEEDED`。 |
| 6.（追加）シミュレータ・本番Supabase・端末言語ja・`-SameQResetState` で新規アカウント→回答→「世界の回答を読む」で運営の日本語投稿が実際に画面表示、`.exhausted` にならない | ✅ | コーディネーターが Maestro フロー（`tools/screenshot-shoot/flows/verify-official-seed.yaml`）で新規アカウント作成→英語で回答→タイムラインを6回スワイプ。スクショ `/tmp/vo-02〜07`: 「SameQ運営」の異なる日本語投稿が複数表示（🏷️「生垣の匂いが好き」／🏛️「薄紫」／📜「味噌汁の味」）。`.exhausted` は出ず、スワイプで巡回。generator 側スクショ `.product/adhoc-official-seed-timeline-fix.png` も同様（🏛️「薄紫」）。 |
| 7.（追加）追加修正後の Debug/Release ビルド + テスト緑 | ✅ | 上記5に同じ。 |

## 発見した別バグ（本タスクと同時に修正）

`SupabaseBackend.timelinePosts(promptID:)` の `select:` が `body_language` を要求して
おらず（コメントは「ビューに列が無い」としていたが実際には
`20260819000004_server_connection.sql` 適用済みで列は存在）、全投稿が言語 "und" 扱いに
なっていた。その結果、日本語投稿でも `AppSession.drawNextPost` → `Translator.translate`
の「端末言語と同一なら翻訳スキップ」ショートカットに入れず、シミュレータ（Apple 翻訳
全滅）や翻訳モデル未DL端末で他人の回答が無言で全スキップされ、UI が `.exhausted` に
張り付いていた。= レビュアーの iPad で「他ユーザーの投稿が見えない」の再発リスク。

修正: `select:` に `body_language,decorations` を追加（他の呼び出し箇所は既に取得済み、
`timelinePosts` だけ漏れていた）+ 古いコメントを実態に合わせて修正。
`PostRow`/`toPost()` は無変更（既に optional + フォールバック済み）。

## 未確認（実機が必要／今回の範囲外）

- **英語ロケールでの自動翻訳**: シミュレータは Apple 翻訳が使えないため、英語端末で
  運営の日本語投稿が英訳表示されるかは未確認。実機が必要。Apple レビュアーは実 iPad
  なので翻訳は働く見込み。日本語ロケール（主対象）は翻訳スキップで確実に表示される。
- 実機でのブロック/通報操作（条件4は SQL で構造確認のみ）。
- 全件読了後の `.exhausted` への正常遷移（今回は途中までしかスワイプしていない）。

## 本番データの後始末

検証で作った当日 `prompt_20260907` のテスト投稿8件（匿名アカウント、
`autumn osmanthus scent` 等）は削除済み。運営投稿5件のみ残存。ブロック/通報の
テストデータは generator が巻き戻し済み（`blocks` 0件・`reports` 0件を確認）。

## 改善提案（次サイクル以降、今回のブロッカーではない）

- 3本に分かれたマイグレーション（本体＋次元修正＋ROW_COUNT修正）は次回スカッシュ
  余地あり。ただし本番適用済みのため今回は触らない。
- `body_language` は投稿時に `Locale.current.language.languageCode`（端末言語）で
  記録される。英語話者が日本語で書いても "en" になるなど実態とズレる可能性がある
  が、既存仕様であり本タスクの範囲外。
