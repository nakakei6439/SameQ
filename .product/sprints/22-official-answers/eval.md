# スプリント22 評価（attempt 1） — 合格

## 判定サマリ

| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 9/9 | 100% | ✓ |
| 2 安定性 | 適用エラー0 / 例外0 / 全22本の適用が完走 | 0 | ✓ |
| 3 データ整合性 | 480/480 バイト一致・3回再適用で480行維持・480件のマッピング不一致0 | 100% | ✓ |
| 4 回帰 | 7/7（F05 / F13 / F14 / 期限切れ / fallback同一性 / ensure_todays_prompt / Swiftデコード） | 100% | ✓ |
| 5 使用性（運用性） | 4 | 3以上 | ✓ |

## 検証環境

- 2026-09-23 に実施。
- **Docker は本機に存在しない**（`docker` / `colima` / `podman` いずれも未インストール）ため、
  `supabase db reset` は実行できなかった。generator と同じく Homebrew の
  PostgreSQL 16.15 で代替検証した。
- 検証用に**隔離した一時インスタンス**を立てた（`initdb` した専用データディレクトリ、
  TCP 127.0.0.1:55432、`unix_socket_directories=''`）。既存の `postgresql@16` サービスは
  停止したままで、一切触れていない。検証後に `pg_ctl stop` 済み。
- Supabase 相当のシム: `pgcrypto`、`anon` / `authenticated` / `service_role` /
  `supabase_admin` ロール、`auth` スキーマ、`auth.uid()` を GUC
  (`request.jwt.claim.sub`) から読むスタブ関数。これにより `set local role authenticated`
  ＋ `set local request.jwt.claim.sub=...` で実際のユーザーになりきって
  `world_timeline` を SELECT できるようにした。
- `supabase/migrations/*.sql` 全22本をファイル名昇順に `ON_ERROR_STOP=1` で適用。
- **本番DBへの書き込みは一切していない**（`supabase db push` / `db query` は未実行）。

### この環境で検証できていないこと（正直に記載）

- **Supabase CLI 経由（`supabase db reset` / `supabase start`）の検証は通っていない。**
  generator と同じ限界を引き継いでいる。
- PostgREST 経由の REST/RPC 呼び出し、実 JWT による `auth.uid()` の解決、Supabase Studio
  からの見え方は未検証（`auth.uid()` は自前スタブ）。
- **Supabase のデフォルト権限（`alter default privileges ... grant ... to anon,
  authenticated`）を再現していない。** そのため素の PostgreSQL では
  `official_answers` に `authenticated` へのテーブル権限が付かない。ただしこれは
  このプロジェクトの既存テーブル（`prompts` / `posts` / `users` / `announcements`）も
  まったく同じで、**マイグレーションに明示的な `grant` を書いている base table は1つも無い**
  （`grep -rn "^grant .* on public\.(prompts|posts|users|announcements|official_answers)"`
  → 0件）。既存の流儀と一貫しており、欠陥ではない。本番では Supabase の
  デフォルト権限で `authenticated` に SELECT が付き、RLS ポリシーで絞られる。
- Swift 側は現状 `official_answers` も `is_official` も読んでいないため、iOS ビルド・
  シミュレータ操作は行っていない（依頼の指示どおり）。

## 受け入れ条件の確認結果

### 1. `official_answers` テーブル作成（RLS: authenticated に select のみ） ✓

```
relname          | relrowsecurity | relforcerowsecurity
official_answers | t              | f

polname                     | polcmd | qual | wcheck | roles
official_answers_select_all | r      | true | (null) | {authenticated}
```

`polcmd = 'r'`（SELECT）のポリシー1本のみ。insert / update / delete のポリシーは0件。
`relrowsecurity = t`。主キーは `(prompt_text, persona, lang)`、persona / lang に
check 制約あり。条件どおり。

### 2. TSV 480行を on conflict do update で冪等投入 ✓

- マイグレーション内の INSERT タプルを正規表現で480個パースし、`''` を `'` に戻して
  `.product/official-answers-48/answers-bilingual.tsv`（ヘッダ1＋データ480、
  **CSV 引用規則つきのタブ区切り**）と `(prompt_text, persona, lang)` キーで照合:
  - TSV 側にのみ存在するキー: 0
  - MIG 側にのみ存在するキー: 0
  - 本文のバイト単位不一致: **0**
  - 重複キー: 0
- さらに**実際にDBへ投入してから** `copy ... to stdout (format csv, delimiter E'\t')`
  で書き出し、TSV と再照合:
  - `BODY MISMATCHES (exact bytes, DB vs TSV): 0`
  - 絵文字（😭🎂 等）、鉤括弧、`''` エスケープ、日英混在すべて一致。
- **Unicode 正規化**: DB 内の480本文・48 prompt_text とも **NFC 形式で一致**
  （`normalize('NFC', v) != v` となる行は 0 件）。NFD 混入は無い。
- 冪等性: 同じマイグレーションを**3回連続適用**してエラーなし、行数は480のまま。

### 3. `ensure_official_answers()` の custom / fallback 分岐 ✓

- **custom 経路**: 48お題の1つを今日のお題にして実行
  → `NOTICE: source=custom inserted=10`、`posts` は10件。
- **2回目の実行**: `inserted=0`、`posts` は10件のまま（`on conflict (prompt_id,
  author_id) do nothing` が効いている。`posts_one_per_prompt UNIQUE (prompt_id,
  author_id)` が実在することも確認済み）。
- **fallback 経路（0件）**: 手作りに無い文言 → `source=fallback category=7 inserted=10`、
  2回目は `inserted=0`。
- **fallback 経路（中途半端な件数）**: 10件のうち1件（dragon/en）を削除して9件にした状態で
  実行 → `source=fallback` に倒れた。0件だけでなく1〜9件でも安全側に倒れることを実測で確認。

### 4. persona → UUID が配列添字に依存していないこと ✓（本スプリントの主題）

- 実装は `for r in select ... from official_answers` の**行ループ**で、各行の
  `r.persona` と `r.lang` から `case` 式で UUID リテラルを直接引いている。
  関数内に残る配列（`v_official_ja` / `v_official_en` / `v_body_*_by_category`）は
  **fallback 経路でしか参照されていない**ことをソース全体で確認。custom 経路には
  配列添字が1箇所も無い。
- **48お題ぜんぶを総当たりで実行**して検証（1お題ずつ prompts を差し替えて
  `ensure_official_answers()` を呼び、結果の posts を退避）:
  - 生成された posts: **480件 / 48お題**
  - `official_answers` から名前引きで期待値を組み立てて突き合わせた結果、
    **author_id・body・body_language の不一致は 0 件**。
- `users` テーブル上の実体も期待どおり:
  `…0001 ケータ（運営）` / `…0006 Keita (SameQ)` / `…0002 エミリー` / `…0007 Emily` /
  `…0003 ロボ` / `…0008 Robo` / `…0004 テトラ` / `…0009 Tetra` /
  `…0005 ドラゴン` / `…000a Dragon`。case 式の対応と完全一致。
- 想定外の persona/lang では `v_author_id is null` → `raise notice` して `continue`
  する安全弁あり。

### 5. fallback 側が 20260922000002 から1行も変わっていないこと ✓

- テキスト diff: 変更は「コメント1行追加」「declare の空白揃え＋変数3つ追加」
  「`v_inserted := 0;` の位置がカテゴリ判定の前に移動」「`raise notice` に
  `source=fallback` を追加」「コメント1行削除」のみ。
  **カテゴリ配列（ja/en 各8カテゴリ×5件）、著者UUID配列、カテゴリ前方一致の case 式、
  5件×2言語の投入ループは完全に同一。**
- テキスト diff だけでなく**挙動でも同一性を実証**した。新関数で8カテゴリ全部
  （`今日` / `最近` / `いま` / `小さい頃` / `子どもの頃` / `もし` / `この一年` / その他）の
  お題を流して `(お題, author_id, body_language, md5(body))` を80行取得 → 同じDBに
  20260922000002 を再適用して旧関数で同じ80行を取得 → **diff は空（IDENTICAL）**。
  951日ぶんの非48お題の挙動は変わらない。

### 6. `world_timeline` の列追加 ✓

- `information_schema.columns` の並び:
  `1 id / 2 prompt_id / 3 author_id / 4 author_emoji / 5 author_nickname / 6 body /
   7 body_language / 8 created_at / 9 expires_at / 10 decorations / **11 is_official**`
  → **末尾**に追加されている（`CREATE OR REPLACE VIEW` の制約を満たす）。
- 直前の定義（20260819000004）と WHERE 句を突き合わせ、
  `status='visible'` / `u.status='active'` / `expires_at > now()` /
  `author_id <> auth.uid()` / blocks / reports / 自分が回答済み、の7条件すべて不変。
- `reloptions = {security_invoker=off}` が維持されている。
  `grant select ... to authenticated` / `revoke ... from anon` も維持。
- **Swift 側は壊れない**（`grep -rn "world_timeline" --include="*.swift"`）:
  - `SameQ/Backend/SupabaseBackend.swift:579` の唯一の読み取り箇所は
    `select: "id,prompt_id,author_id,author_emoji,author_nickname,body,body_language,created_at,expires_at,decorations"`
    と**明示的な列リスト**を渡しており `*` ではない。増えた列は要求すらされない。
  - デコード先の `PostRow` は素の `Decodable` 構造体で、合成イニシャライザは
    未知のキーを無視する。列順にも依存しない（PostREST の JSON キー引き）。
  - `SameQUITests/SprintTwelveEvalE2ETests.swift:67` も同様に壊れない。

### 7. RLS ✓（上記1に記載）

### 8. ローカル適用（代替手段） ✓

全22本が `ON_ERROR_STOP=1` でエラーなく完走。

## 回帰の抜き取り（7件、いずれも合格）

実ユーザー（`11111111-…`）になりきって `world_timeline` を SELECT して確認。

| # | 過去条件 | 期待 | 実測 | 判定 |
|---|---|---|---|---|
| 1 | F05: 未回答なら世界タイムラインは0件 | 0 | 0 | ✓ |
| 2 | F06/F11: 回答後は他人の回答が見える・自分のは出ない | 10件 / 自分0件 | 10 / 0 | ✓ |
| 3 | F13: ブロックした相手の回答が消える | 9件（robo が消える） | 9 / 当該著者0 | ✓ |
| 4 | F14: 通報した回答が消える | 8件 | 8 | ✓ |
| 5 | 期限切れ投稿は返さない | 0件 | 0 | ✓ |
| 6 | 非48お題の運営回答が従来どおり（20260922000002 の回帰） | 旧関数と同一 | md5 で80行 IDENTICAL | ✓ |
| 7 | `ensure_todays_prompt()` が999プールから決定的に引く | 変化なし | `prompt_20260922` を生成 | ✓ |

追加で確認したもの:
- 日英の内訳: `ja 5件 / en 5件`、10件すべて `is_official = t`。
- `posts` のトリガー（`posts_reject_prohibited_trigger` = スプリント20 の UGC 安全弁）に
  **480件すべてが弾かれない**ことを総当たりで確認（`status` は480件すべて `visible`）。
  本文長は最小11 / 最大166文字で、`posts_body_length CHECK (1..2000)` に余裕で収まる。
- `ensure_official_answers()` は `security definer` / `search_path=public` /
  `authenticated` にのみ EXECUTE、を維持。

## 本番適用シミュレーション（追加検証）

本番は「20260922000002 まで適用済み＋実データあり」の状態に**この1本だけ**が乗る。
その状況を再現した:

1. 新規DBに 20260923000001 を**除いた**全マイグレーションを適用
2. `ensure_todays_prompt()` → `ensure_official_answers()` を実行し、一般ユーザーの
   投稿も1件入れる（posts 11件 / prompts 1件）
3. **そこへ新マイグレーションだけを適用**

結果: `APPLY OK`。既存 posts は11件のまま保持、`official_answers` 480行が入り、
`world_timeline` は11列になり、認証ユーザーから見て運営10件が `is_official = t` で返る。
既存データの破壊・重複は発生しない。

## 基準5（使用性 = 運用性）: 4点

- `raise notice` が `source=custom` / `source=fallback category=N` を出し分けるので、
  本番でどちらの経路を通ったかがログから即判別できる。これは運用上かなり効く。
- persona/lang が想定外のときに黙って落ちず notice を出してその行だけスキップする
  安全弁がある。
- ファイル冒頭に背景・変更内容・persona→UUID 対応表が書かれており、次に触る人が読める。
- 4止まりの理由: 480行を単一の `insert ... values` にまとめているため、1件だけ直したい
  ときの差分が読みづらい（generator 自身も弱点として挙げている）。機能上の問題は無い。

## 不合格の原因

なし。

## 改善提案（合否には影響しない）

### [優先度: 高] 本番適用後に「fallback のまま」でも異常ではない

- 今日（UTC 2026-09-22）のお題は
  `誰にも言っていないけれど本当は少し気になっていることは？`（プール添字238）で、
  **48お題には含まれていない**。したがって本番適用直後も運営回答は従来のカテゴリ方式のまま
  出る。これをバグと誤認しないこと。
- 999件プールを1日1つ順に引く仕組みなので、手作り回答が出る日は
  **今後400日でわずか24日**（約6%）。最初の該当日は **2026-10-16**
  （`最近、自分の判断が当たったと思った場面は？`）、次が 2026-10-21 / 10-22 / 10-27 /
  11-02 / 11-18 / 11-28。
- 本番で custom 経路を実地確認したいなら、2026-10-16 を待つか、その日まで
  `prompts` の当日行の `text` を48お題のどれかに差し替えて `ensure_official_answers()`
  を呼ぶ必要がある。
- 48お題ぶんしか無いのは依頼スコープどおりなので減点していないが、「手作り480件を入れた
  のに滅多に出ない」という期待値のズレが起きうるため、プール側の重み付け（48お題を
  優先的に引く）を将来検討する価値はある。

### [優先度: 中] `is_official` は追加されたがまだ誰も使っていない

ビューに列は増えたが、Swift の `timelinePosts` は明示列リストに `is_official` を
入れていないため、本来の目的（運営投稿を端末言語で絞る）は未達のまま。
これは「Swift 側は別作業」と明記されておりスコープ外だが、**この列を使う Swift 側の
スプリントを実施するまで、ユーザーから見える変化は「48日ぶんの運営回答の文面が変わる」
だけ**であることを認識しておく。

### [優先度: 低] `official_answers` の明示 grant

既存テーブルと同じくマイグレーションに `grant` を書いていない（Supabase のデフォルト権限
頼み）。プロジェクトの一貫性は保たれているので今回は指摘扱いにしないが、将来
デフォルト権限の設定が変わると `authenticated` から読めなくなる余地はある。

## 評価できなかったもの

- **`supabase db reset`（Supabase CLI 経由）の適用確認。** Docker が本機に無いため。
  素の PostgreSQL 16.15 ＋ 手製シムでの検証に留まっており、generator と同じ限界がある。
  PostgREST 経由の公開、実 JWT での `auth.uid()`、Supabase のデフォルト権限は未検証。
- 本番DBへの実適用は依頼どおり行っていない（コーディネーターの担当）。
