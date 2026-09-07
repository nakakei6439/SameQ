# 単発タスク（spec スプリントではない）: 本番タイムラインに恒久的な「運営回答」を自己修復で補充する

## 背景

Apple から2度目のリジェクト（2026-09-05、build 6）。Guideline 2.1(a): レビュアーが
「他ユーザーの投稿を確認する方法がない」と指摘。原因は `public.world_timeline`
（他人の回答の唯一の入口、`supabase/migrations/20260818000003_report_block.sql`）が
「自分がそのお題に回答済みでなければ0件」というアンサーファーストを強制しており、
かつ本番に恒久的なサンプル投稿の仕組みが無いこと。実ユーザーが少ない現状、その日
その時点で他に誰も回答していなければ必ず「まだ誰も答えていません」の空状態になる。
これは審査対応だけでなく、ユーザー自身が日常的に体験している問題でもある
（「毎日見てるけど誰も投稿してくれへん」）。

過去の `supabase/seed.sql` は `now()` 相対の一度きりの使い捨てシードで、投入から
26〜54時間ほどで期限切れになる。Apple の再審査タイミングは予測できず、お題は
日次でローテーションするため、一度きりの手動シードでは同じ理由で再度リジェクトされ得る。

よって「一時しのぎ」ではなく、**常時・恒久的に最低数件の回答が保証される自己修復の
仕組み**を作る。本番はこのプロジェクトの唯一の検証環境（ローカル Docker 無し）で、
`pg_cron` は有効化されていない。代わりに「気づいたクライアントが自己修復する」
パターンの前例が既にある: `public.ensure_todays_prompt()`
（`supabase/migrations/20260829000013_ensure_todays_prompt.sql`）。今回はこれと
同じ設計方針を踏襲した新しい関数を追加する。

**ユーザー確定方針**: 補充投稿は「運営とわかる形」にする（他の匿名ユーザーと
混同されない固定パターンのニックネーム・絵文字にする。実投稿が増えれば自然に埋もれる）。

## やること

### 1. 新規マイグレーション `supabase/migrations/20260905000001_official_seed_answers.sql`

**(a) 固定の運営アカウントを5件、`public.users` に insert**

- 固定 UUID をマイグレーション内にリテラルで埋め込む（例:
  `'00000000-0000-0000-0000-00000000000{1..5}'` のような判別しやすい形で構わない）。
- `emoji` は5種類バラバラ（既存のオンボーディング絵文字選択肢と衝突しないもの。
  `SameQ/Feature/Onboarding/OnboardingView.swift` の `onboarding.emoji.*` を見て
  重複を避ける）。
- `nickname` は全員共通で「運営だとひと目で分かる固定文字列」にする
  （例: `"SameQ運営"`。英語圏の読者にも意味が伝わるよう `"SameQ Team"`等の代替も
  検討可。最終判断は実装者に委ねる。ただし**5アカウントとも同じ nickname にする**
  ——「複数の運営担当者」ではなく「運営という1つの主体」に見せるため）。
- `status = 'active'`。

**(b) 48件のお題プールを8つの意味カテゴリに分類**

- `public.ensure_todays_prompt()`（`20260829000013_ensure_todays_prompt.sql`）の
  `v_pool`（48要素、配列の並び順は変更しない）を読み、内容から以下8カテゴリに
  分類する（目安。実装者が実際の文面を見て多少の調整をしてよい）:
  1. 今日〜（「今日、〜」で始まるもの）
  2. 最近〜（「最近、〜」で始まるもの）
  3. いま〜（「いま、〜」で始まるもの）
  4. 小さい頃/子供の頃〜
  5. これから・もし〜（未来・仮定）
  6. この一年〜
  7. ここ数日/直近の感覚〜（色・匂い・味・音など）
  8. 内省・その他（上記に当てはまらないもの）
- 48要素と1対1対応する `category` 整数配列（0〜7）を関数内に用意する。

**(c) `public.ensure_official_answers()` を新規追加**

- `security definer`, `set search_path = public`。`ensure_todays_prompt()` と
  **全く同じ** `v_day_key` / `v_day_index` / `v_start_idx` の計算式で「今日の
  お題」の pool index（0〜47）を再導出する（`ensure_todays_prompt()` 自体は
  変更しない。ロジックを重複させるだけでよい）。
- その pool index に対応する `category`（0〜7）を引く。
- 今日のお題の `id`（`'prompt_' || v_day_key`）に対して、5アカウント分
  `insert into public.posts (prompt_id, author_id, body, body_language)
   values (...) on conflict (prompt_id, author_id) do nothing` を実行。
  - `body` は該当カテゴリ用に用意した短文（下記2.参照）。
  - `body_language = 'ja'`。
  - `expires_at` は書かない（既存の `posts_set_expiry` トリガーが
    `prompt_id` から自動で埋める。手動計算しない）。
  - `posts_body_length`（`btrim(body)` の文字数 1〜1000）を満たすこと。
- `revoke all on function public.ensure_official_answers() from public;`
  `grant execute on function public.ensure_official_answers() to authenticated;`
  （`ensure_todays_prompt()` と同一パターン）。
- 関数・テーブルへの `comment on` も既存スタイルに合わせて書く。

### 2. 運営回答の文面（40件 = 8カテゴリ × 5アカウント）

- カテゴリごとに5パターン（5アカウント分）の短文を執筆する。1つのカテゴリの
  5パターンは**言い回しを変えつつ意味が重複しすぎない**ようにする（5人が
  ほぼ同じことを言っているように見えると不自然）。
- トーン: `.product/adhoc-seed-localization.md` やお知らせ文面のルール
  （前向き・誇張しない、過度に赤裸々な告白にしない）に準拠。「運営です」を
  毎回名乗る必要は無い。テンプレ的で空虚な一文（「いい一日でした」だけ等）は避け、
  具体性のある一言にする。
- 日本語のみでよい（英語話者への表示は既存の on-device Translation に任せる。
  他の実ユーザー投稿と同じ経路で、特別扱いしない）。

### 3. Swift 側の呼び出し追加

`SameQ/Backend/SupabaseBackend.swift` の既存の
`try? await client.rpcVoid(function: "ensure_todays_prompt")` 呼び出し
（320行目付近）の直後に、同じ fire-and-forget 方針で

```swift
try? await client.rpcVoid(function: "ensure_official_answers")
```

を追加する。失敗しても本来の機能（お題取得）をブロックしないこと。

### 4. マイグレーションの適用

`supabase db push --linked` で本番（linked project）に適用する。**このリポジトリに
ローカル Docker 検証環境は無い**ため、本番が唯一の検証環境（既存の全マイグレーション
もこの方法で適用されてきた）。適用後、`supabase db query --linked` で
`public.ensure_official_answers` 関数と5件の運営アカウントが存在することを確認する。

## 触ってよいファイル

- `supabase/migrations/20260905000001_official_seed_answers.sql`（新規）
- `SameQ/Backend/SupabaseBackend.swift`（1行追加のみ）
- 必要なら対応するユニットテスト（`SameQTests/`）

## 触らないもの

- `public.ensure_todays_prompt()` 本体（ロジックを複製するだけで、既存関数は変更しない）
- `LocalBackend` / `SeedCatalog`（Debug専用のオフライン経路。今回の対象は本番 Supabase のみ）
- オンボーディング・UI コード

## 受け入れ条件（evaluator が確認する）

1. `supabase db query --linked` で `public.ensure_official_answers` 関数、および
   5件の運営アカウント（`public.users`、共通 nickname）が本番に存在することを確認。
2. 実機/シミュレータで `-SameQResetState` の新規インストール（**本番 Supabase 経路
   （LocalBackend フラグ無し）**、通常起動）→ オンボーディング完走 → 今日のお題に
   回答 → 「世界の回答を読む」→ **運営アカウントの投稿が最低5件、今日のお題の
   カテゴリに沿った内容で表示される**こと（自分の投稿以外に real な他ユーザー
   投稿があればそれも追加で見える）。
3. 冪等性: アプリを再起動して `ensure_official_answers` が再度呼ばれても、
   タイムラインの運営投稿が重複せず5件のままであること。
4. 回帰: 運営アカウントをブロック/通報しても `world_timeline` から正しく除外
   されること。実投稿の「いいね」「翻訳」など既存機能に悪影響が無いこと。
5. Debug / Release ともビルド成功。既存ユニットテスト（`SameQTests/`）が緑
   （関連: `PromptGenerationTests`, `PromptLifecycleTests`, `TimelineSelectionTests` 等）。

## 自己評価（self-review）に書くこと

- 変更したファイルと差分の要点（マイグレーション本体、40件の文面一覧、Swift差分）
- 8カテゴリへの分類結果（どのお題がどのカテゴリか、簡単な対応表）
- `supabase db push --linked` の実行結果と、適用後の確認クエリの結果
- 受け入れ条件1〜4をどう確認したか（シミュレータ操作 or SQL クエリ）
- 追加/更新したテスト

---

## 追加対応（2026-09-07、evaluator/コーディネーター検証で判明）

### 症状
シミュレータ（本番Supabase経路、端末言語 ja）で新規アカウント→今日のお題に回答→
「世界の回答を読む」を開くと、`world_timeline` は 10 件（運営5＋実/テスト匿名5）を
正しく返しているのに、UI は「今は新しい回答がありません／このお題の回答はすべて
読みました」（`.exhausted`）になり、運営投稿が1件も表示されない。

### 原因（本タスクとは別の既存バグ。ただし 2.1(a) の可視化を妨げているので同時に直す）
`SupabaseBackend.timelinePosts(promptID:)`（`SameQ/Backend/SupabaseBackend.swift` 472行目
付近）の `select:` 文字列が `body_language` を要求していない:

```
select: "id,prompt_id,author_id,author_emoji,author_nickname,body,created_at,expires_at",
```

その直前のコメント（474〜478行目）は「`world_timeline` に `body_language` /
`decorations` カラムが無い（20260819000004 は未適用）」と書いているが、**これは
現状に合っていない**。`supabase migration list --linked` で 20260819000004 は
Remote に適用済みで、本番 `world_timeline` ビューには実際に `body_language` /
`created_at` / `expires_at` / `decorations` 列が存在する（`information_schema.columns`
で確認済み）。

`body_language` を SELECT しないため `PostRow.toPost()`（964・976行目、`body_language`
は既に `String?` として定義済み）が `bodyLanguage: body_language ?? "und"` で全投稿を
"und" にしてしまう。すると `AppSession.drawNextPost()`（1016行目）の
`translator.translate(post.body, sourceLanguageCode: "und")` が「端末言語と同じ言語なら
翻訳スキップして `.text` を即返す」ショートカット（`Translator.translate` 冒頭）に
入れず、必ず Apple 翻訳を実行する。シミュレータでは Apple 翻訳が全ペア `.unavailable`
なので、恒久失敗扱いで全投稿が `markPostViewed` され、巡回しきって `.exhausted` になる。
実機でも「翻訳モデル未DL・オフライン・翻訳不調」のときに同じ経路で他人の回答が
無言で全部スキップされる（＝Apple レビュアーの iPad で「他ユーザーの投稿が見えない」の
再発リスクそのもの）。

### やること（generator）
1. `timelinePosts(promptID:)` の `select:` に `body_language` と `decorations` を追加する
   （他の呼び出し箇所 373・442行目は既に `body_language` を要求している。ここだけ漏れ）。
2. 474〜478行目の古いコメントを実態に合わせて直す（「ビューに列が無い」→「ビューは
   `body_language` / `decorations` を返すのでそのまま取得する。端末言語と同じ投稿は
   `AppSession.drawNextPost` の translator ショートカットで翻訳をスキップできる」）。
3. `PostRow` / `toPost()` は変更不要（既に `body_language: String?` / `decorations:
   [PostDecoration]?` を持ち、`?? "und"` / `?? []` でフォールバックしている）。
4. 回帰確認: `nextTimelinePost` / いいね / 通報・ブロック除外は `world_timeline` の
   他の列に依存しているだけなので影響しないはずだが、`timelinePosts` を使う全経路
   （`AppSession.drawNextPost`, `timelineCandidateCount`, `refreshTimelineCounts`）を
   ざっと確認する。

### 追加の受け入れ条件
6. **シミュレータ（本番Supabase、端末言語 ja、`-SameQResetState`）**で新規アカウント→
   今日のお題に回答→「世界の回答を読む」を開くと、**運営（"SameQ運営"）の日本語投稿が
   実際に画面に表示される**こと（1件ずつ表示のUIなら数回スワイプして複数の運営投稿が
   出てくること）。`.exhausted` にならないこと。
7. Debug/Release ビルド成功、既存テスト緑（1〜5 は前回達成済みなので差分のみ再確認で可）。
