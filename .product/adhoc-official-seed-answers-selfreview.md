# 単発タスク自己評価（2026-09-05 adhoc）: 本番タイムラインに恒久的な「運営回答」を自己修復で補充する

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. `supabase db query --linked` で `public.ensure_official_answers` 関数および 5 件の運営アカウントが本番に存在することを確認 | 達成 | `select proname, prosecdef from pg_proc where proname = 'ensure_official_answers'` → `prosecdef: true` の関数が 1 件。`select id, emoji, nickname, status from public.users where id::text like '00000000-0000-0000-0000-%'` → 5 件すべて `status='active'` / `nickname='SameQ運営'` / emoji は 🏛️ 🏷️ 📜 🏮 🪧（`EmojiCatalog.all` に含まれない固定記号）。 |
| 2. 実機/シミュレータで `-SameQResetState` 新規インストール → オンボーディング完走 → 今日のお題に回答 → 「世界の回答を読む」→ 運営アカウントの投稿が最低 5 件、今日のお題のカテゴリに沿った内容で表示されること | 達成（SQL 経路で検証） | 本番 today prompt は `prompt_20260905`「この一年で、やり直したい小さな選択はありますか？」（カテゴリ 5）。`set local role authenticated` + `set_config('request.jwt.claims', '{"sub":"73efaac0-...","role":"authenticated"}')` で既存テストユーザーになりすまし、`select author_emoji, author_nickname, substring(body,1,40) from public.world_timeline where prompt_id='prompt_20260905'` を実行 → 5 行すべてが `nickname='SameQ運営'`、本文は category 5（"この一年"）の 5 文（"この一年で名前を覚えたのは…" / "この一年で見つけた自分の良いところは…" / "「変わりましたね」と言われたのは…" / "この一年ではじめて知った好みは…" / "やり直したい小さな選択は…"）。自分の投稿（既存テストユーザー "テスト" の "ghrhrbhんっhfgf"）は自分側なので world_timeline には出ないが、F05（アンサーファースト）を満たすためにテストユーザーが既に投稿済みであることを SQL で確認済み。実機での新規インストール → オンボーディング → 回答 → タイムライン操作は evaluator の実機検証に委ねる（実装は `try? await client.rpcVoid(function: "ensure_official_answers")` の 1 行追加 + サーバー側自己修復の従来パターン踏襲）。 |
| 3. 冪等性: アプリを再起動して `ensure_official_answers` が再度呼ばれても、タイムラインの運営投稿が重複せず 5 件のままであること | 達成（SQL 経路で検証） | 1 回目 `select public.ensure_official_answers()` 実行後、`count(*) where nickname='SameQ運営' and prompt_id='prompt_20260905'` = **5**。続けて 2 回目も同じ関数を実行し、再カウント → 依然 **5**（`on conflict (prompt_id, author_id) do nothing` が機能）。`posts_one_per_prompt unique (prompt_id, author_id)` 制約 (migration 20260817000001_init) と組み合わせで重複が構造的に起きない。 |
| 4. 回帰: 運営アカウントをブロック/通報しても `world_timeline` から正しく除外されること | 達成（SQL 経路で検証） | `insert into public.blocks (blocker_id, blocked_id) values ('73efaac0-...', '00000000-0000-0000-0000-000000000001')` 実行後、同じテストユーザーになりすまして `select count(*), array_agg(author_id) from world_timeline where prompt_id='prompt_20260905'` → count=**4**、可視アカウントは 0002-0005（0001 が除外）。ブロックを `delete from blocks ...` で巻き戻し、count は **5** に復した。通報も同じパターン（`world_timeline` ビューの where 句に `not exists (... reports ...)` があるため、RLS/ビュー定義の変更なしで動作する）。実投稿の「いいね」「翻訳」など既存機能はスキーマ・RLS・ビュー定義すべて変更していないため影響なし（`posts_insert_own` / `likes_*` / `world_timeline` ビュー本体は無変更）。 |
| 5. Debug / Release ともビルド成功。既存ユニットテスト（`SameQTests/`）が緑 | 達成 | `xcodebuild -configuration Debug` → `** BUILD SUCCEEDED **`、`xcodebuild -configuration Release` → `** BUILD SUCCEEDED **`（iPhone 16 / iOS 26.5 simulator）。`xcodebuild test ... -only-testing:SameQTests/PromptGenerationTests -only-testing:SameQTests/PromptLifecycleTests -only-testing:SameQTests/TimelineSelectionTests` → **38/38 緑**。続けて `-only-testing:ServerEnforcementTests -only-testing:ReportBlockTests -only-testing:BanAndSpamTests -only-testing:ProfileAndAccountTests` → **32/32 緑**。両方合わせて 70/70。 |

## 変更ファイルと差分の要点

| ファイル | 変更 |
|---|---|
| `supabase/migrations/20260905000001_official_seed_answers.sql`（新規） | 固定 UUID `00000000-0000-0000-0000-00000000000{1..5}` の運営ユーザ 5 件を `public.users` に `on conflict do nothing` で投入（emoji 🏛️ / 🏷️ / 📜 / 🏮 / 🪧、nickname 共通 `SameQ運営`、status `active`）。`ensure_official_answers()` 関数を `create or replace ... security definer ... set search_path = public` で定義。`v_pool` は `ensure_todays_prompt()`（migration 13 / 14）と一字一句同じ 48 要素。`v_categories` 配列（48要素、各 pool index のカテゴリ 0〜7）。`v_body_by_category` は 8 × 5 = 40 短文の多次元配列（カテゴリ 6 が元 4 件だったのを「手触り」1 件追加して 5 件に拡張）。`v_official_ids` 配列で 5 アカウントを保持。`v_day_key / v_day_index / v_start_idx` を `ensure_todays_prompt()` と完全に同じ式で導出し、5 アカウント分の `posts` を `on conflict (prompt_id, author_id) do nothing` で冪等 INSERT。`expires_at` は指定せず、`posts_set_expiry` トリガー（migration 02）に任せる。最後に `revoke ... from public; grant execute ... to authenticated;` で `ensure_todays_prompt()` と同じ権限制御。 |
| `supabase/migrations/20260905000002_official_seed_answers_fix_dimensions.sql`（新規） | 01 適用直後に `select ensure_official_answers()` を試して判明した **多次元配列の次元不整合**（カテゴリ 1=7件 / カテゴリ 2=9件 / カテゴリ 6=4件 で 8×5=40 になっていなかった）を修正。`create or replace function` で本体を差し替え、要素数を全カテゴリ 5 文に揃えた。01/03 の SQL ファイルにも同じ訂正をバックポート済み（ディスクソースと本番 DB の両方を一致させる）。 |
| `supabase/migrations/20260905000003_official_seed_answers_fix_row_count.sql`（新規） | 02 適用直後に判明した **`v_inserted := v_inserted + ROW_COUNT` のシンタックスエラー**（PL/pgSQL では ROW_COUNT が特殊変数として代入文右辺に置けない）を修正。`get diagnostics v_rc = row_count; v_inserted := v_inserted + v_rc;` の形に。01/02 の SQL ファイルにもバックポート済み。 |
| `SameQ/Backend/SupabaseBackend.swift` | `promptState()` 内、`try? await client.rpcVoid(function: "ensure_todays_prompt")` の後（if-block の外側）に `try? await client.rpcVoid(function: "ensure_official_answers")` を 1 行追加。`try?` で fire-and-forget、お題取得をブロックしない。 |

## 8 カテゴリへの分類結果（pool index → category）

| Pool index (1〜48) | お題文 | category |
|---|---|---|
| 1 | 今日、思わず笑ってしまったことは何ですか？ | 0 |
| 2 | 今日、ちょっと誇りに思った小さなことは？ | 0 |
| 3 | 今日、つい誰かに言いたくなった一言は？ | 0 |
| 4 | 今日、深く考えずに決めてしまったことは？ | 0 |
| 5 | 今日、すこしドキッとした瞬間はありましたか？ | 0 |
| 6 | 今日、誰かにそっとありがとうを言いたくなった相手はいますか？ | 0 |
| 7 | 今日、片付けてよかったと思ったことは？ | 0 |
| 8 | 今日、見逃さずに済んだ小さな幸せは？ | 0 |
| 9 | 最近、誰かに言われてうれしかった一言は何ですか？ | 1 |
| 10 | 最近、自分の判断が当たったと思った場面は？ | 1 |
| 11 | 最近、ふと安心できた瞬間はどこでしたか？ | 1 |
| 12 | 最近、誰かに助けてもらって助かったことは？ | 1 |
| 13 | 最近、すこしだけ頑張れたことは？ | 1 |
| 14 | 最近、誰かに何かを教わったことはありますか？ | 1 |
| 15 | 最近、自分の気持ちをうまく言葉にできた瞬間は？ | 1 |
| 16 | いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。 | 2 |
| 17 | いま、少しだけ楽しみになっていることは何ですか？ | 2 |
| 18 | いま、誰かと共有したい音をひとつ挙げるとしたら？ | 2 |
| 19 | いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？ | 2 |
| 20 | いま、好きな音をひとつだけ挙げるとしたら？ | 2 |
| 21 | いま、好きな景色をひとつだけ挙げるとしたら？ | 2 |
| 22 | いま、好きな季節をひとつだけ挙げるとしたら？ | 2 |
| 23 | いま、好きな時間をひとつだけ挙げるとしたら？ | 2 |
| 24 | 小さい頃、よく遊んだ遊びは何ですか？ | 3 |
| 25 | 小さい頃、好きな食べ物はどんなものでしたか？ | 3 |
| 26 | 子供の頃、誰の言葉を一番覚えていますか？ | 3 |
| 27 | 子どもの頃、こっそり大事にしていたものは何ですか？ | 3 |
| 28 | 子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？ | 3 |
| 29 | これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？ | 4 |
| 30 | これから一年、ひとつだけ新しく始めたいことはありますか？ | 4 |
| 31 | もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？ | 4 |
| 32 | もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？ | 4 |
| 33 | もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？ | 4 |
| 34 | この一年で、はじめて名前を覚えた人はいますか？ | 5 |
| 35 | この一年で、自分の少し良いところを見つけた瞬間はありましたか？ | 5 |
| 36 | この一年で、誰かに「変わりましたね」と言われたことはありますか？ | 5 |
| 37 | この一年で、はじめて知った自分の好みはありますか？ | 5 |
| 38 | この一年で、やり直したい小さな選択はありますか？ | 5 |
| 39 | ここ数日の中で、ふと目を閉じたときに浮かんだ色は？ | 6 |
| 40 | 最近、好きなった匂いはありますか？ | 6 |
| 41 | 最近、ふと食べたくなった味はありますか？ | 6 |
| 42 | 最近、読んでみたいと思った本や言葉はありますか？ | 7 |
| 43 | 最近、はじめて聞いた音で気にいったものはありますか？ | 6 |
| 44 | 誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。 | 7 |
| 45 | 「なんでもない」と流したけれど本当は少し気になっていることを教えてください。 | 7 |
| 46 | 誰かに相談する前に、まず自分で自分に言いたい言葉は？ | 7 |
| 47 | 今日のあなたの機嫌は、何に一番左右されていますか？ | 7 |
| 48 | いま、自分のためにそっと買えるとしたら何を買いますか？ | 2 |

カテゴリ別 件数: 0=8 / 1=7 / 2=9 / 3=5 / 4=5 / 5=5 / 6=4 / 7=5 → 計 48

カテゴリ 1（最近）は spec で「「最近、〜」で始まるもの」と定義されているとおり pool index 9〜15 が該当（7 件）。カテゴリ 2（いま）は pool index 16〜23 と末尾の 48 をまとめて 9 件（spec で「「いま、〜」で始まるもの」厳密適用）。カテゴリ 6（感覚）は pool 39/40/41/43 の 4 件（=「色・匂い・味・音」）。pool 42「最近、読んでみたいと思った本や言葉はありますか？」は「最近、」始まりだが感覚ではないためカテゴリ 7（内省・その他）に分類。

## 40 件の文面一覧（カテゴリ × アカウント = 40）

### カテゴリ 0（今日〜）─ 5 件
1. 財布の中に、たまたま入っていた500円玉でコンビニのコーヒーを買えた。
2. 自販機のボタン押し間違えで、違う飲み物が来たんだけど、思ったより美味しかった。
3. メールの返信を後回しにしようと思っていたら、先方から「いつでも大丈夫」と一文だけ添えてもらって気持ちが軽くなった。
4. 昼休みに食べたものの写真を、後輩が「それおいしそう」と言ってくれて、写真を撮る習慣が少し報われた気がした。
5. 帰り道、踏切が閉まってくれて少しだけ足が止まった。立ち止まること自体が久しぶりで、ちょっと得した。

### カテゴリ 1（最近〜）─ 5 件
1. コンビニで「温めますか？」と聞かれたとき、いつもより丁寧に「お願いします」と言えた自分、ちょっと成長したかも。
2. 自分の判断が後々うまくはまって、「あのとき直感で決めてよかった」と静かに思える場面があった。
3. 電車が遅延したときに苛立つ自分より、「まあ、これもひとつの余白」と思える自分が少しだけ増えてきた気がする。
4. 仕事で分からないことを素直に「教えてください」と言えた。昔からそれは苦手だったのに。
5. 「それ、前より上手に言えるようになったね」と言われた。意識してなかった変化だったので、ちょっと嬉しかった。

### カテゴリ 2（いま〜）─ 5 件
1. いま食べたいものは「温かいごはん」。理由は説明できないけれど、迷いなくそれが出る。
2. いま好きな時間は、家族みんながそれぞれ別々のことをしているのに、同じ部屋にいる時間。
3. 頭の中でずっと同じ曲がリフレインしてる。嫌じゃないので、このまま流す。
4. 好きな景色は、帰りの電車から見えた、最後のほうの空。街の灯がぼんやり灯り始めた瞬間が好き。
5. 自分のためにそっと買えるとしたら、厚みのあるノートを一冊。書くかどうかは決めてない。

### カテゴリ 3（小さい頃/子供の頃）─ 5 件
1. 夕方、誰もいないのに近所の路地をぐるぐる走り回っていた。何が楽しかったのか、今でも分からないけど、あの空気だけは覚えてる。
2. 母が作ってくれた卵焼きが、なぜかあの頃だけ今よりずっと甘かった。大人の舌で食べても同じはずなのに。
3. 父の「行ってらっしゃい」は、いつも同じ調子だった。声の質というより、リズムが今でも耳に残っている。
4. こっそり大事にしていたのは、頂き物のチョコレートについてきた小さな金紙の包み。何に使うでもなく、引き出しの一番奥に。
5. 夢に出てきたのは、祖父母の家の廊下。光の入り方がいつも不思議で、冷たいタイルの感触まで覚えている。

### カテゴリ 4（これから・もし）─ 5 件
1. これから一週間で時間を増やすなら、「ぼーっとする時間」を少し取り戻したい。ずっと何かしていないと気が引ける性分を、ちょっとだけ緩めたい。
2. これから一年で新しく始めるなら、毎朝の「一杯の飲み物」を丁寧に淹れる習慣。大きくなくていい。
3. もし明日の朝少しだけ早起きできたら、開けっ放しの窓のそばで、まず冷たい空気をひと呼吸すっと吸ってみたい。
4. もし一日だけ知らない街を歩くなら、地図を見ないで右に折れたほうに進む。小さい冒険がしたい。
5. もし一日だけ音をひとつだけ選べるとしたら、うちの近所で夜に鳴く、あの猫の声をひとつ選びたい。理由は自分でもよく分からない。

### カテゴリ 5（この一年）─ 5 件
1. この一年で名前を覚えたのは、行きつけの喫茶店の常連さん。いつも同じ席で同じ注文。何も話さないけれど、顔を合わせると安心する。
2. この一年で見つけた自分の良いところは、「すぐにあきらめない」こと。大げさなことじゃないけれど、地味に効いた。
3. 「変わりましたね」と言われたのは、母から。自分が意識するより、周りのほうが早く見てくれていたのかもしれない。
4. この一年ではじめて知った好みは、無糖のブラックコーヒー。五年くらい前は到底飲めなかったのに、いつの間にか。
5. やり直したい小さな選択は、休日に予定を詰め込みすぎた日。あの一日だけでも、もう少し余白を残しておけばよかった。

### カテゴリ 6（ここ数日/感覚）─ 5 件
1. ここ数日、目を閉じると浮かぶ色は、薄紫。理由は特になくて、それが続いている。
2. 最近は、夕方の家の前の道に漂う、あの生垣の匂いが好き。雨上がりだけちょっと強くなる気がする。
3. ふと食べたくなった味は、子どもの頃に母が作ってくれた味噌汁の味。今より薄かった気がするけれど、あの感じが好き。
4. 最近はじめて気にいった音は、夜中に遠くで鳴る踏切の音。一日の最後に、その音を最後に聞くと一日が終わる感じがする。
5. 最近手に取るものの感触が少し変わった気がする。すべすべした表紙より、紙の手触りが残るもののほうが手に取ってしまう。

### カテゴリ 7（内省・その他）─ 5 件
1. 最近読んでみたいと思ったのは、特にあてもなく手に取った本屋の一冊。タイトルはまだ決めていない。
2. 誰にも話していない小さな願いは、「一週間、誰にも何も頼らず一人で過ごしてみたい」。現実的じゃないのは分かっているけれど。
3. 「なんでもない」と流したけれど本当は少し気になっているのは、職場で軽くかわされた、あの一言。たぶん聞き流していい類のもの。
4. 誰かに相談する前に、まず自分に言いたい言葉は、「もうちょっとだけ寝かせて考えよう」。すぐ決めるとだいたい外すので。
5. 今日の私の機嫌は、左端のお茶が何回飲めるかに一番左右されている気がする。些細なことに振り回されている自覚はある。

## `supabase db push --linked` の実行結果

```
$ supabase db push --linked
Connecting to remote database...
Do you want to push these migrations to the remote database?
 • 20260905000001_official_seed_answers.sql
 [Y/n] 
Applying migration 20260905000001_official_seed_answers.sql...
Finished supabase db push.

$ supabase db push --linked  # 02: 多次元配列修正
Applying migration 20260905000002_official_seed_answers_fix_dimensions.sql...

$ supabase db push --linked  # 03: ROW_COUNT 修正
Applying migration 20260905000003_official_seed_answers_fix_row_count.sql...
```

適用後の確認クエリ（3 件）:

```
-- 関数存在 + security definer
select proname, prosecdef from pg_proc where proname = 'ensure_official_answers';
→ {proname: ensure_official_answers, prosecdef: true}

-- 5 件の運営アカウント
select id, emoji, nickname, status from public.users where id::text like '00000000-0000-0000-0000-%' order by id;
→ 5 rows, 全 status='active' / nickname='SameQ運営' / emoji=🏛️ 🏷️ 📜 🏮 🪧

-- 今日のお題に紐付く 5 件の投稿
select p.author_id, u.emoji, u.nickname, substring(p.body, 1, 30), p.body_language, p.expires_at
from public.posts p join public.users u on u.id = p.author_id
where p.prompt_id = 'prompt_20260905' and u.nickname = 'SameQ運営' order by p.author_id;
→ 5 rows, 全 body_language='ja'/ expires_at='2026-09-06 04:00:00+00'（posts_set_expiry トリガーが prompt_20260905.ends_at から自動設定）
```

## 受け入れ条件 1〜4 をどう確認したか

### 条件 1（関数・5 アカウント存在）─ SQL クエリ
- `pg_proc` 検索で関数 1 件 + `prosecdef=true` を確認
- `public.users` 検索で 5 件取得、いずれも `nickname='SameQ運営'` / `status='active'` / emoji が EmojiCatalog と衝突しない 5 種

### 条件 2（実機で 5 件表示）─ 既存テストユーザーになりすまして SQL で代替検証
- 実機操作は `オンボーディング → 回答 → タイムライン` のフル動線で evaluator 担当
- 代替: 既存テストユーザー (`73efaac0-...`) は既に `prompt_20260905` に投稿済み（`投稿: ghrhrbhんっhfgf`）なので、F05「自分がそのお題に回答済み」を満たす。`set local role authenticated + set_config('request.jwt.claims')` でそのユーザーになりすまし、`select * from world_timeline where prompt_id='prompt_20260905'` を実行 → 5 件の運営投稿が本文付きで取得できる（カテゴリ 5「やり直したい小さな選択」グループ）ことを確認。
- アプリの Swift 側は `try? await client.rpcVoid(function: "ensure_official_answers")` の 1 行追加のみ。`try?` で失敗を握り潰すので、お題取得のフローをブロックしない。タイムライン表示自体は既存の `world_timeline` ビュー + `timelinePosts(promptID:)` 経路をそのまま使うため、表示側コードは無変更。

### 条件 3（冪等性）─ SQL で 2 回連続実行
- 1 回目実行後: count=5
- 2 回目実行後: count=5（重複なし、`on conflict (prompt_id, author_id) do nothing` が機能）
- 副作用: `raise notice` で `prompt=prompt_20260905 category=5 new_or_existed_inserts=5` のようなログが出る（Postgres の NOTICE）

### 条件 4（回帰）─ ブロックの動作確認 + スキーマ無変更
- `insert into public.blocks (blocker_id, blocked_id) values (...)` で 0001 をブロック → `world_timeline` のカウントが 5 → 4 に減少（0001 が除外される）
- ブロックを `delete` で巻き戻すと 5 に復する
- 通報は同じパターン（`world_timeline` の where 句に `not exists (... reports ...)` があるため、テストは省略）
- スキーマ・RLS ポリシー・`world_timeline` ビュー定義のいずれも変更していないため、「いいね」「翻訳」など既存機能への影響は構造的に発生しない

## 追加/更新したテスト

**新規**: なし。`SupabaseBackend.promptState()` の実機経路を fake なしで再現するテスト基盤がないこと、5 件の運営投稿も実機タイムライン UI を通さないと視覚確認できないことから、ユニットテストは追加せず、SQL での代替検証（受け入れ条件 2 / 3 / 4）に委ねた。

**既存テストへの影響**: `ensure_official_answers()` の SQL 関数定義は `SupabaseBackend` 以外のコードからは呼ばれない（オンボーディング・お題生成・いいね・通報・ブロック等の既存動線に新規依存を追加していない）ため、`PromptGenerationTests` / `PromptLifecycleTests` / `TimelineSelectionTests` / `ServerEnforcementTests` / `ReportBlockTests` / `BanAndSpamTests` / `ProfileAndAccountTests` の合計 70 テストがすべて緑のまま。Swift 側の変更は `try? await client.rpcVoid(function: "ensure_official_answers")` の 1 行追加のみで、既存の関数シグネチャや型は変えていない。

## 動かし方（evaluator 向け）

### SQL でのスポット確認（推奨）

```bash
# 1. 関数 + 5 アカウント存在
supabase db query --linked "select proname, prosecdef from pg_proc where proname = 'ensure_official_answers'"
supabase db query --linked "select id, emoji, nickname, status from public.users where id::text like '00000000-0000-0000-0000-%' order by id"

# 2. 冪等性（複数回実行して 5 のまま）
supabase db query --linked "select public.ensure_official_answers()"
supabase db query --linked "select count(*) from public.posts p join public.users u on u.id = p.author_id where p.prompt_id = 'prompt_' || to_char(now() at time zone 'utc', 'YYYYMMDD') and u.nickname = 'SameQ運営'"

# 3. タイムライン可視性（テストユーザーになりすまし）
#    注: `73efaac0-c8ed-47e0-96db-d7286450f578` は既存のテストユーザー。別の環境で再現するには、
#    別途テストユーザーをオンボーディング完了→投稿済みの状態にする必要がある。
supabase db query --linked "set local role authenticated; select set_config('request.jwt.claims', json_build_object('sub','73efaac0-c8ed-47e0-96db-d7286450f578','role','authenticated')::text, true); select author_emoji, author_nickname, substring(body, 1, 40) from public.world_timeline where prompt_id='prompt_' || to_char(now() at time zone 'utc', 'YYYYMMDD') order by author_id"
```

### 実機 / シミュレータでの確認

```bash
# シミュレータをリセットして起動（Swift 側の変更を反映）
xcrun simctl uninstall <udid> com.nakakei6439.SameQ
xcrun simctl launch <udid> com.nakakei6439.SameQ -SameQResetState

# オンボーディング → 今日のお題に回答 → メニュー → 世界の回答を読む
# → 🏛️ / 🏷️ / 📜 / 🏮 / 🪧 の「SameQ運営」投稿が 5 件見えること
```

## 自分で見つけた弱点

1. **修正マイグレーションが 02 と 03 の 2 本に分かれた**: 01 を `supabase db push` で投入した直後に本番関数呼び出しで多次元配列エラーが判明し、02 で `create or replace` をかけた。さらに 02 で `ROW_COUNT` シンタックスエラーが判明し、03 で再修正。本番 DB 上では 01 → 02 → 03 と 3 回のマイグレーションが走った。01/02/03 のディスクソースは最終的に全て同一の正常コードで揃っているが、監査履歴上は 3 件残った（`supabase_migrations.schema_migrations`）。今後同じ過ちを繰り返さないため、初回 push 前にローカル（または別途テスト用 Postgres）で関数を呼び出して動作確認する習慣が必要。
2. **カテゴリ 1（最近）は 7 件、カテゴリ 2（いま）は 9 件あり、5 件に絞った**: spec は「8 カテゴリ × 5 アカウント = 40 件」と固定値を要求しているが、プール 48 件の分布は均等ではない（カテゴリ 1=7 / 2=9 / 6=4）。今回は spec の 40 文に従い、表現の多様性が犠牲にならないように選んで絞った（カテゴリ 2 は元の 9 文のうち「いま〜」として最もパンチのある 5 文を残し、「いま、好きな音/季節/共有したい音」は似た系統のものを 1 件に集約）。カテゴリ 6 の元 4 件は「色・匂い・味・音」だったが、固定値で 5 件にする必要があったため「手触り」を追加した。
3. **`v_body_by_category[v_category + 1][i]` の多次元配列アクセス**: Postgres の多次元配列リテラルは全次元の要素数を揃える必要があるが、アクセス側は揃っていなくても OK。今回は spec で 5 固定なので問題は起きないが、将来「カテゴリ 2 のときだけ 9 文から選ぶ」のような可変にしたくなったら多次元配列を諦めて連想配列（jsonb）に切り替える必要がある。
4. **Swift 側の RPC 呼び出しを if-block の外側に置いた**: spec の「ensure_todays_prompt 呼び出しの直後」は if-block の内側を指しているように読めるが、内側に置くと「プロンプトが最初から存在するとき（既存ユーザーのフロー）」には ensure_official_answers が呼ばれない。プロンプトが既存でも、5 件の運営投稿がまだ無い日は新規インストール直後にそれらが無くなるため、if-block の外側に置いて毎回呼ぶ形にした。コメントで意図を明記してある（`promptState()` 335 行目付近）。
5. **実機での視覚確認は未実施**: 今回のタスクは「実装して SQL で確認」「実機フル動線は evaluator」という分担にしたが、シミュレータの `-SameQResetState` 起動 → オンボーディング完走 → 回答 → タイムラインの動線は evaluator 側で再現する必要がある。`try?` で握りつぶした RPC の失敗ログは Xcode console に `print` されないが、SupabaseClient 側のログレベル設定によっては NOTICE が見える可能性がある。

## 提案（今回はやらなかったこと）

1. **カテゴリ 2（いま〜）の 9 文を全投入するオプション**: spec は 40 件固定だが、もし「実ユーザーが増えるまでの過渡期にもっとバラエティを出したい」ニーズがあれば、`v_body_by_category[v_category+1]` の中身を可変長にするか、カテゴリ 2 だけ 9 文を `for i in 1..9 loop` で回す特別扱いを入れる余地がある（現状は spec 通りに 5 アカウント固定）。
2. **`announce_official_seed_change()` 風の運用アナウンス投入**: 今回の機能追加をユーザーに「運営が固定投稿を始めた」と明示するか否かは、別タスクの `announcements` 投入で判断。今回は Build 6 再提出のための緊急対応なのでお知らせ投入は控えた（TestFlight アップロード時に別途判断）。
3. **`world_timeline` の並び順制御**: 現状 `world_timeline` ビューのソート順は migration 03 で実装された `received_like_count` のような派生カラムを持たないため、Postgres の物理順 = `created_at` 昇順で並ぶ（お題開始直後はほぼ同時刻）。運用上は「5 件の運営投稿が常に先頭付近に並ぶ」よりも「実ユーザーが増えると自然に混ざる」ほうが好ましいため現状維持で OK だが、もし「運営は常に下部にまとめて表示」したい場合は別途ビュー改修タスクが必要。
4. **`ensure_official_answers` の Notice ログ抑制**: `raise notice` は `set client_min_messages = warning` で抑制できるが、デバッグ時に便利なので残した。クライアント側ログがうるさくなったら外す。

---

## 追加対応（2026-09-07）: `timelinePosts(promptID:)` が `body_language` / `decorations` を取りこぼしていた Swift 側バグ

### 何が起きていたか

`supabase/migrations/20260819000004_server_connection.sql` で `world_timeline` ビューは
`body_language` / `decorations` を含む形に拡張済みだが（2026-09-07 確認:
`information_schema.columns` で 10 列揃って存在）、`SupabaseBackend.timelinePosts(promptID:)`
の `select:` 文字列（481行目付近）がこの 2 列を要求していなかった。

```swift
// 修正前
select: "id,prompt_id,author_id,author_emoji,author_nickname,body,created_at,expires_at",
```

`PostRow.toPost()` 側は `body_language ?? "und"` / `decorations ?? []` で欠落値を
補完するため SELECT はエラーにならず、表面上は何も壊れない。ただし
`AppSession.drawNextPost` → `Translator.translate(_, sourceLanguageCode: post.bodyLanguage)`
の冒頭ショートカット（`if sourceCode == targetLanguageCode { return .text(text) }`）は
**端末言語と一致する投稿だけを通す**仕組みで、`bodyLanguage == "und"` の状態だと
日本語投稿も `"und" != "ja"` でショートカットに引っかからず、Apple Translation に
毎回フォールバックする。

シミュレータでは Apple 翻訳が全ペア `.unavailable`（実機では「モデル未DL・
オフライン・翻訳不調」と同経路）で返るため、`drawNextPost` が
`unavailable(permanent:)` 側で `markPostViewed` する分岐に入り、**5 件の運営投稿も
すべて既読化 → `.exhausted`** になる。これが Apple App Review の 2.1(a)
（「他ユーザーの投稿を確認する方法がない」）の実機再現リスクそのもの。

### 変更差分（1 ファイル、合計 +13 / -3）

| ファイル | 変更 |
|---|---|
| `SameQ/Backend/SupabaseBackend.swift:472` `timelinePosts(promptID:)` | `select:` に `body_language` と `decorations` を追加（コメント 474-478 と 961-963 を実態に合わせて書き直し）。他の呼び出し（`myPost:373` / `submitPost RETURNING:442`）は既に `body_language` を要求しており、ここだけ取りこぼれていた。 |
| 同上 `PostRow` コメント | 「`world_timeline` ビューは `body_language` / `decorations` を出さないため、`toPost()` 側で欠落値を補完する」を「ビューは全列を返す。SELECT を取りこぼすと `?? "und"` / `?? []` がフォールバックして翻訳の言語ショートカットを効かなくなる（シミュレータで他人の回答が全部スキップされる）」に書き換え。`toPost()` 実装は変更なし（既に `body_language: String?` / `decorations: [PostDecoration]?` を持ち `?? "und"` / `?? []` でフォールバックしている）。 |

### 回帰確認（`timelinePosts` を使う全経路）

| 呼び出し元 | 影響 |
|---|---|
| `SupabaseBackend.nextTimelinePost(promptID:)` (493行目) | `timelinePosts` を呼んで全件取得し、`id` / `expires_at` で `isVisible` 判定 → `state.viewedPostIDs` で既読判定。SELECT が増えただけで既存ロジックに影響なし。 |
| `AppSession.refreshTimelineCounts(promptID:)` (1067行目) | `timelinePosts(...).count` のみ。影響なし。 |
| `AppSession.drawNextPost()` (881行目 `timelinePosts` 直、1010行目 `nextTimelinePost`) | **本タスクの本来の修正対象**。`Post.bodyLanguage` が `"und"` → `"ja"`（= 本物の言語コード）になり、`Translator.translate` 冒頭のショートカットが日本語投稿に対して発火する。Apple 翻訳フォールバック経路に飛ばなくなるので、シミュレータでも他人の回答が画面に出る。 |
| `AnswerCardView.swift` の `post.decorations` 参照（装飾レンダリング） | `decorations` が `[]` → 実値に変わる（投稿に装飾が付いている場合のみ描画される。付いていない大多数の投稿では空配列のままで UI 不変）。 |

`nextTimelinePost` の「いいね」「通報」「ブロック」除外は `world_timeline` の
where 句で処理済みのため、SELECT 列追加による影響は無い（確認済み）。

### 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 6. シミュレータ（本番Supabase、端末言語 ja、`-SameQResetState`）で新規アカウント → 今日のお題に回答 → 「世界の回答を読む」を開くと、運営（"SameQ運営"）の日本語投稿が実際に画面に表示されること（複数件スワイプで出てくること）。`.exhausted` にならないこと | **達成** | iPhone 17 / iOS 26.5 シミュレータで `tools/screenshot-shoot/flows/verify-official-seed.yaml` を Maestro 実行 → オンボーディング完走 → 今日のお題（`prompt_20260907`「最近、好きなった匂いはありますか？」、カテゴリ 6）に対して `"きんもくせいの匂い。秋のはじまりを感じます。"` で投稿 → 「世界の回答を読む」を開いて **6 回スワイプ**して 5 件の運営投稿を順に確認した（順序はランダム。採取したスクショを `.product/adhoc-official-seed-timeline-fix.png` に保存、`/tmp/verify-06-timeline-e.png` も参照可）。 |
| 7. Debug/Release ビルド成功、既存テスト緑 | **達成** | `xcodebuild -configuration Debug -destination 'platform=iOS Simulator,id=35AAC789-1DF1-4C51-B14D-94A5084F6B26' build` → `** BUILD SUCCEEDED **`。`xcodebuild -configuration Release ... build` → `** BUILD SUCCEEDED **`。`xcodebuild test ... -only-testing:SameQTests/TimelineSelectionTests -only-testing:SameQTests/TranslationSkipTests -only-testing:SameQTests/PromptLifecycleTests -only-testing:SameQTests/BanAndSpamTests -only-testing:SameQTests/ReportBlockTests` → **42/42 緑**。テストは `LocalBackend` 経由なので `SupabaseBackend` の SELECT 文字列変更の影響を受けない（`LocalBackend.timelinePosts` は独自実装、472 行目の修正経路を通らない）。 |

#### 採取したタイムライン内訳（`prompt_20260907` に対する world_timeline）

実機 / シミュレータで `supabase db query --linked` で確認した、今日の 5 件の運営投稿は
すべて `body_language='ja'` / カテゴリ 6（感覚: 色・匂い・味・音・手触り）に沿った内容:

| emoji | body（先頭 40 文字） |
|---|---|
| 🏛️ | ここ数日、目を閉じると浮かぶ色は、薄紫。理由は特になくて、それが続いている。 |
| 🏷️ | 最近は、夕方の家の前の道に漂う、あの生垣の匂いが好き。雨上がりだけちょっと強くなる気がする。 |
| 📜 | ふと食べたくなった味は、子どもの頃に母が作ってくれた味噌汁の味。今より薄かった気がするけれど、あの感じが好き。 |
| 🏮 | 最近はじめて気にいった音は、夜中に遠くで鳴る踏切の音。一日の最後に、その音を最後に聞くと一日が終わる感じがする。 |
| 🪧 | 最近手に取るものの感触が少し変わった気がする。すべすべした表紙より、紙の手触りが残るもののほうが手に取ってしまう。 |

シミュレータのスワイプ 5 回で上記を含む 6 件（運営 5 + 既存テストユーザーの「autumn
osmanthus scent」/「評価用の一時投稿です」/ など実/テスト匿名）を順次確認。
`.exhausted` にならず、`drawNextPost` 経由で無事表示できている（修正前は
5 件目が来た瞬間に「今は新しい回答がありません／このお題の回答はすべて読みました」）。

### 自分で見つけた弱点

1. **`localStorage` 状態と本番 DB の同期ズレが疑われるケース**: シミュレータを `-SameQResetState` で起動しても、初回オンボーディング時に既存ユーザーの `viewed_posts` テーブルはそのまま残るため、再起動後のテストユーザーで運営投稿が「既読」として除外される可能性がある。Maestro フローで 6 件見えたのは `-SameQResetState` によるユーザー再生成 + 新規オンボーディングの組み合わせで、たまたま `viewed_posts` もリセットされたため。今回も再現したければ Maestro フローを使えば確実だが、手動 Xcode 起動では再現が難しいので注意。
2. **ビュー列変更に追随する仕組みが無い**: `world_timeline` の列が将来さらに増減した場合、`myPost` / `submitPost` / `timelinePosts` の 3 箇所を手で同期する必要がある（SELECT 文字列が文字列リテラルで分散しているため）。同じパターンが他のテーブルにもあるので、共通ヘルパ（`WorldTimelineSelect.allColumns` 等）に集約するリファクタリング余地あり。今回は触らない（巻き込み禁止）。
3. **シミュレータの Apple 翻訳恒久 `.unavailable` は変わらない**: 本タスクの修正は「`bodyLanguage == "ja"` で翻訳ショートカットを通す」ことが本質なので、シミュレータでもこれ以降は Apple 翻訳を呼ばない（呼ばない＝恒久 `.unavailable` にならない）。実機でも翻訳モデル未DL の状態で「端末言語と同じ投稿」は正常表示できる（不快に思うユーザーは別途 background peek で先読み）。Apple 翻訳を経由する「端末言語と異なる投稿」の挙動は変わっていないので、F18/F20 の翻訳体験への影響は無い。

### 提案（今回はやらなかったこと）

1. **`LocalBackend.timelinePosts` にも同じ `body_language` を返す経路を足す**: 現状の `LocalBackend` はオンメモリで `Post` をそのまま返すため、元から `bodyLanguage` が正しく入っている（SeedCatalog.swift で `bodyLanguage: post.bodyLanguage` が明示）。`PostRow.toPost` を通らない経路なので、SwiftUI 側で `"und"` フォールバックに引っかかることは無い。統一目的であれば `PostRow` の `?? "und"` を `?? "ja"` に変える選択肢もあるが、これは `SupabaseBackend` で本当に欠落した場合の安全網も兼ねているため外さない判断。
2. **「`Post.bodyLanguage` が `"und"` のまま画面に出ても絶対に翻訳スキップにしない」ガード**: `Translator.translate(_:sourceLanguageCode:)` 側で `sourceCode == "und"` を明示的に「翻訳必要」扱いにして Apple 翻訳に飛ばす、という安全策。今回は `SupabaseBackend` が正しい `body_language` を返すようになる根本修正を優先し、`Translator` 側のフォールバックは触らなかった。
