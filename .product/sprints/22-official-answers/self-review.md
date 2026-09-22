# スプリント22 自己評価（attempt 1）

対象: `supabase/migrations/20260923000001_official_answers_table.sql`（1本のみ、Swift は未変更）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| `official_answers` テーブル作成（RLS select のみ authenticated） | 達成 | ローカルDBで `\d` と `pg_policy` を確認。`official_answers_select_all` (FOR SELECT, TO authenticated, USING true) の1本のみ。insert/update/delete ポリシーは無し（`prompts` と同じ方針）。`relrowsecurity = t` を確認 |
| 480行を on conflict do update で冪等投入 | 達成 | `insert ... values (...480行...) on conflict (prompt_text, persona, lang) do update set body = excluded.body;`。マイグレーションを2回連続適用しても行数480のまま（エラーなし） |
| シングルクォートのエスケープ・絵文字/日英混在を1文字も変えない | 達成 | Python で TSV を読み `s.replace("'", "''")` のみ実施し生成。DB投入後に480行すべてを TSV と `(prompt_text, persona, lang)` キーで機械照合し **mismatches: 0** を確認（下記の検証ログ参照） |
| `ensure_official_answers()`: 手作りが10件揃えばそれを使う | 達成 | 実データにある48お題の1つ（「いま、好きな季節を〜」）を today's prompt にして実行 → `NOTICE: source=custom inserted=10`。ペルソナ↔UUID対応も全件正しい（下記） |
| 揃っていなければ従来のカテゴリ方式にフォールバック | 達成 | today's prompt のテキストを手作りに無い文言（「今日、これといって特に何もなかった日にありがちなことは？」）に差し替えて実行 → `NOTICE: source=fallback category=0 inserted=10`。カテゴリ配列・著者UUID配列・投入ロジックは20260922000002から一字一句変更していない |
| ペルソナ→UUID対応は名前引き（添字を使わない） | 達成 | 詳細は下記セクション参照 |
| 同じお題で2回実行しても重複投稿されない | 達成 | custom経路・fallback経路それぞれで2回連続実行し、2回目は `inserted=0`、`posts` の件数は10のまま |
| `world_timeline` が `is_official` を返す | 達成 | `information_schema.columns` で11列目に追加を確認。さらに `auth.uid()` をテスト用UUIDに差し替えて実際に SELECT し、運営10件すべて `is_official = t` で返ることを確認 |
| ローカルSupabaseで構文エラー無く適用できる | 達成（Supabase CLI 経由ではなく後述の代替手段） | 下記「検証方法」参照 |

**全条件達成（9/9）。**

## 検証方法（重要: Docker が本機に無かったための代替手順）

依頼文は `supabase db reset`（Docker必須）での検証を想定していたが、本機には Docker
（Docker Desktop 本体）がインストールされておらず、`open -a Docker` は
`Unable to find application named 'Docker'` で失敗した。Homebrew にも docker/colima/podman
等の代替コンテナランタイムは入っていなかった。

そのため、**同じ内容を Docker 無しで検証できる代替手段**として、Homebrew で
`postgresql@16` をローカルインストールし、素の PostgreSQL 上で以下を再現した:

1. `pgcrypto` 拡張を有効化（`gen_random_uuid()` 用）
2. `auth` スキーマと `auth.uid()` のスタブ関数（テスト用に戻り値を差し替え可能）、
   `anon` / `authenticated` / `service_role` ロールを作成（Supabase が提供する分だけ）
3. `supabase/migrations/*.sql` を **ファイル名の昇順（=適用順）で全21+1本、頭から順に**
   `psql -f` で適用（`20260817000001_init.sql` 〜 今回の `20260923000001_...sql` まで）
4. 全て `ON_ERROR_STOP=1` でエラー無く完走することを確認（`pg_cron` 拡張が無い環境だが
   `20260827000010_pg_cron_schedule.sql` は拡張の有無を確認してからスキップする作りなので
   問題なし）

この方法の限界（正直に書く）:
- Supabase 固有の PostgREST / GoTrue 連携、実際の JWT 経由の `auth.uid()` 解決、
  Supabase Studio 経由の動作は検証していない（`auth.uid()` は手動で差し替えたスタブ）。
- したがって「PostgreSQL としての構文・制約・トリガー・関数ロジック・RLS ポリシー定義」は
  検証済みだが、Supabase CLI (`supabase db reset` / `supabase start`) 経由の検証ではない。
  本番相当の確認は、Docker が使える環境で改めて `supabase db reset` を一度通すことを推奨する
  （このマイグレーション単体の構文・ロジックに問題が無いことは上記で担保済み）。
- 途中、一つ実装ミスを検出・修正した: 最初 `world_timeline` の SELECT 列順序で
  `is_official` を `author_nickname` の直後に挿入していたところ、PostgreSQL の
  `CREATE OR REPLACE VIEW` は既存ビューの列を途中に挿入できない
  （`cannot change name of view column "body" to "is_official"`）という制約に引っかかった。
  `is_official` を列リストの最後（`decorations` の後）に移動して解決した。これは
  ローカル検証で実際に踏んだ失敗であり、Docker が無くても検証した意味があった箇所。

### 検証結果ログ（抜粋）

```
select count(*) from official_answers;               → 480
distinct prompt_text 件数                              → 48
(prompt_text)ごとの件数が10でないもの                  → 0件
(prompt_text, persona, lang) が重複/欠落しているもの    → 0件
TSV と DB の (prompt_text, persona, lang, body) 完全一致 → mismatches: 0
information_schema.columns(world_timeline) 11列目      → is_official
```

## ペルソナ名から UUID を引く部分の実装（最重要）

`ensure_official_answers()` 内、手作り回答を使う分岐で、`official_answers` から取得した
1行（`persona`, `lang`, `body`）ごとに、**persona名とlangの組み合わせに対する `case` 式**で
著者UUIDを直接指定した（配列や添字は一切使っていない）:

```sql
v_author_id := case
    when r.persona = 'keita'  and r.lang = 'ja' then '00000000-0000-0000-0000-000000000001'::uuid
    when r.persona = 'keita'  and r.lang = 'en' then '00000000-0000-0000-0000-000000000006'::uuid
    when r.persona = 'emily'  and r.lang = 'ja' then '00000000-0000-0000-0000-000000000002'::uuid
    when r.persona = 'emily'  and r.lang = 'en' then '00000000-0000-0000-0000-000000000007'::uuid
    when r.persona = 'robo'   and r.lang = 'ja' then '00000000-0000-0000-0000-000000000003'::uuid
    when r.persona = 'robo'   and r.lang = 'en' then '00000000-0000-0000-0000-000000000008'::uuid
    when r.persona = 'tetra'  and r.lang = 'ja' then '00000000-0000-0000-0000-000000000004'::uuid
    when r.persona = 'tetra'  and r.lang = 'en' then '00000000-0000-0000-0000-000000000009'::uuid
    when r.persona = 'dragon' and r.lang = 'ja' then '00000000-0000-0000-0000-000000000005'::uuid
    when r.persona = 'dragon' and r.lang = 'en' then '00000000-0000-0000-0000-00000000000a'::uuid
    else null
end;
```

`official_answers` は `select ... from official_answers where prompt_text = v_prompt_text`
で行単位に取得し、`for r in ... loop` で1行ずつ処理するため、そもそも配列の並び順に依存する
余地が無い（依頼文にあった 20260922000001 の事故は「配列の並び順」と「別配列の並び順」が
食い違ったことが原因なので、根本的に配列添字を使わない設計にした）。

`v_author_id is null`（persona/langの組み合わせが想定外）の場合は `raise notice` して
その行だけ `continue` でスキップする安全弁を入れた（テーブルの check 制約で理論上は
発生し得ないが、防御的に残した）。

実測（today's prompt = 「いま、好きな季節をひとつだけ挙げるととしたら？」）:

```
robo  → author_id 00000000-...0003 (ja) / 00000000-...0008 (en)  ✓
dragon→ author_id 00000000-...0005 (ja) / 00000000-...000a (en)  ✓
（emily / tetra / keita も同様に全一致）
```

## フォールバックの分岐をどう書いたか

`ensure_official_answers()` の先頭でお題テキストを引いた直後に、

```sql
select count(*) into v_custom_count
from public.official_answers oa
where oa.prompt_text = v_prompt_text;

if v_custom_count = 10 then
    -- 手作り回答（persona名からUUIDを引いてposts投入）
    ...
    return;
end if;

-- ここから下は 20260922000001/2 と一字一句同じフォールバック
v_category := case when v_prompt_text like '今日%' then 0 ... else 7 end;
for i in 1..5 loop  -- ja
for i in 1..5 loop  -- en
```

- 分岐条件は「ちょうど10件（5ペルソナ×2言語）そろっているか」の1点のみ。0件はもちろん、
  データ不整合などで1〜9件しか無い場合も安全側（フォールバック）に倒す設計にした
  （中途半端な件数を使うと、そのお題だけ特定のペルソナや言語が欠けた回答になるため）。
- custom分岐は末尾で `return;` して抜けるので、フォールバック側のロジック（カテゴリ配列・
  著者UUID配列・5件ずつの投入ループ・`raise notice`）は **20260922000002 からコピーしたまま
  1行も変更していない**。カテゴリ判定の前方一致条件も文字列も完全一致。
- 両分岐とも `on conflict (prompt_id, author_id) do nothing` を使うため、custom→fallback
  やその逆に切り替わっても（お題入れ替えなどで）二重投稿にはならない（ただし通常運用では
  同じお題に対して分岐が変わることは無い。テストで意図的に text を書き換えて両方の経路を
  踏んだ）。

## 自分で見つけた弱点

- ローカル検証が Supabase CLI (`supabase db reset`) ではなく素の PostgreSQL 代替である点
  （Docker 未インストールのため）。SQL としての正しさは機械照合込みで確認済みだが、
  Supabase 実環境固有の挙動（PostgREST 経由のRPC呼び出し、実JWTでの `auth.uid()` 等）は
  未検証。本番相当の最終確認は、Docker が使える環境で `supabase db reset` を一度通すことを
  勧める。
- `official_answers` の `insert` 文は480行を1つの `insert ... values (...)` にまとめている
  ため、将来1件だけ手直ししたい場合でも差分がファイル全体に見えてしまう（可読性の妥協）。
  今回は依頼の「TSVを読んでinsert文を生成する」を素直に実装した結果であり、機能的な問題は無い。
- テストで作った検証用ユーザー（`11111111-...`）やテスト用の `auth.uid()` スタブは
  ローカル検証専用の Homebrew PostgreSQL インスタンス内にのみ存在し、リポジトリやマイグレーション
  ファイルには一切含めていない（`dropdb` 済み、後片付け不要）。

## 提案（今回はやらなかったこと）

- 手作り回答が枯渇した後（48お題を一周した後）の扱いは依頼スコープ外のため未実装
  （現状は単純に「その日のお題テキストと完全一致する行が無ければ従来方式」に自動フォールバック
  するので、48お題を使い切ってもエラーにはならない。追加の手作り回答を増やしたくなったら
  同じ形式のTSVをこのテーブルに追加投入すればよい設計にした）。
