-- SameQ 緊急対応: ensure_todays_prompt が prompts_no_overlap 制約に阻まれて
-- サイレントに失敗していた不具合を修正（2026-08-30）
--
-- 背景:
--   migration 13 (20260829000013) で追加した `ensure_todays_prompt()` は、
--   本番 `prompts` が空だったときに自己修復として 1 行 INSERT する
--   ものだった。PostgreSQL init migration 02 (20260817000002) で
--   `prompts_no_overlap` という EXCLUDE 制約が
--   `tstzrange(starts_at, ends_at, '[)')` に対して入っており、
--   28h 有効 × 24h 周期の運用（`Prompt.defaultDuration` = 28h、
--   `date_trunc('day', now() at time zone 'utc')` で翌日 0:00 UTC 開始）
--   と相性が悪い。具体的には前プロンプトの
--   `[08-29 00:00, 08-30 04:00)` と当日プロンプトの
--   `[08-30 00:00, 08-31 04:00)` が 4 時間重なるため、
--   INSERT が `23P01 conflicting key value violates exclusion constraint
--   "prompts_no_overlap"` で失敗していた。
--
--   クライアント（`SupabaseBackend.promptState()`）は self-heal RPC を
--   `try?` で呼ぶため失敗を握り潰し、引き続き `prompts` が空のまま
--   になり、画面が「お題がありません」で固定される事故が 2026-08-30 の
--   実機 / TestFlight で観測された（フィードバック ①）。
--
-- 対応方針:
--   制約は生かしたまま、`ensure_todays_prompt()` 側で
--   INSERT 前に「直前のプロンプトの `ends_at` を新プロンプトの
--   `starts_at` に切り詰める」前処理を入れる。28h 有効の意図は維持
--   され、切り詰めは 4 時間だけ（前プロンプトの本来の終端と新プロンプトの
--   開始の差分）。これで `prompts_no_overlap` 制約に違反しなくなる。
--
--   冪等性は引き続き担保（`on conflict (id) do nothing`）。
--   複数クライアントが同時に呼んでも、`update` による切り詰めと
--   `insert on conflict do nothing` の組み合わせで結果は同じになる。
-- ---------------------------------------------------------------------------

create or replace function public.ensure_todays_prompt()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    -- 候補プール48件は migration 13 から一字一句コピー（声色を揃えるため）。
    -- ここを変更したら PromptGenerator.swift / PromptCatalog.swift も必ず同期すること。
    v_pool text[] := array[
        '今日、思わず笑ってしまったことは何ですか？',
        '今日、ちょっと誇りに思った小さなことは？',
        '今日、つい誰かに言いたくなった一言は？',
        '今日、深く考えずに決めてしまったことは？',
        '今日、すこしドキッとした瞬間はありましたか？',
        '今日、誰かにそっとありがとうを言いたくなった相手はいますか？',
        '今日、片付けてよかったと思ったことは？',
        '今日、見逃さずに済んだ小さな幸せは？',
        '最近、誰かに言われてうれしかった一言は何ですか？',
        '最近、自分の判断が当たったと思った場面は？',
        '最近、ふと安心できた瞬間はどこでしたか？',
        '最近、誰かに助けてもらって助かったことは？',
        '最近、すこしだけ頑張れたことは？',
        '最近、誰かに何かを教わったことはありますか？',
        '最近、自分の気持ちをうまく言葉にできた瞬間は？',
        'いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。',
        'いま、少しだけ楽しみになっていることは何ですか？',
        'いま、誰かと共有したい音をひとつ挙げるとしたら？',
        'いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？',
        'いま、好きな音をひとつだけ挙げるとしたら？',
        'いま、好きな景色をひとつだけ挙げるとしたら？',
        'いま、好きな季節をひとつだけ挙げるとしたら？',
        'いま、好きな時間をひとつだけ挙げるとしたら？',
        '小さい頃、よく遊んだ遊びは何ですか？',
        '小さい頃、好きな食べ物はどんなものでしたか？',
        '子供の頃、誰の言葉を一番覚えていますか？',
        '子どもの頃、こっそり大事にしていたものは何ですか？',
        '子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？',
        'これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？',
        'これから一年、ひとつだけ新しく始めたいことはありますか？',
        'もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？',
        'もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？',
        'もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？',
        'この一年で、はじめて名前を覚えた人はいますか？',
        'この一年で、自分の少し良いところを見つけた瞬間はありましたか？',
        'この一年で、誰かに「変わりましたね」と言われたことはありますか？',
        'この一年で、はじめて知った自分の好みはありますか？',
        'この一年で、やり直したい小さな選択はありますか？',
        'ここ数日の中で、ふと目を閉じたときに浮かんだ色は？',
        '最近、好きなった匂いはありますか？',
        '最近、ふと食べたくなった味はありますか？',
        '最近、読んでみたいと思った本や言葉はありますか？',
        '最近、はじめて聞いた音で気にいったものはありますか？',
        '誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。',
        '「なんでもない」と流したけれど本当は少し気になっていることを教えてください。',
        '誰かに相談する前に、まず自分で自分に言いたい言葉は？',
        '今日のあなたの機嫌は、何に一番左右されていますか？',
        'いま、自分のためにそっと買えるとしたら何を買いますか？'
    ];
    v_pool_size int := array_length(v_pool, 1);
    v_day_key text;
    v_day_index int;
    v_start_idx int;
    v_text text;
    v_starts_at timestamptz;
    v_ends_at timestamptz;
    v_truncated_count int;
begin
    v_day_key  := to_char((now() at time zone 'utc')::date, 'YYYYMMDD');
    v_day_index := date(now() at time zone 'utc') - date '1970-01-01';

    -- 候補プールの選択（隣接日に近いお題が続けて出ないよう中盤から走査）。
    v_start_idx := ((v_day_index % v_pool_size) + v_pool_size / 2) % v_pool_size;
    v_text      := v_pool[v_start_idx + 1]; -- Postgres 配列は 1-indexed

    v_starts_at := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
    v_ends_at   := v_starts_at + interval '28 hours';

    -- 2026-08-30 追加: 直前のプロンプトで新プロンプトと重なるものを
    -- `ends_at = v_starts_at` に切り詰めて overlap を消す。
    -- これがないと `prompts_no_overlap` EXCLUDE 制約（migration 02）に
    -- 弾かれて INSERT が失敗し、自己修復が無効になる（フィードバック ①）。
    -- 切り詰めるのは「`ends_at` が `v_starts_at` より後」かつ
    -- 「`starts_at` が `v_starts_at` より前」という overlap 条件のものだけ。
    -- 28h 有効のうち、最大 4h 分だけ前プロンプトの有効期間が短くなるが、
    -- 新プロンプトが直ちに active になるため UI 上の悪影響は出ない。
    update public.prompts
    set ends_at = v_starts_at
    where ends_at > v_starts_at
      and starts_at < v_starts_at;
    get diagnostics v_truncated_count = row_count;
    raise notice 'ensure_todays_prompt: truncated % previous prompt(s) to ends_at = %', v_truncated_count, v_starts_at;

    insert into public.prompts (id, text, starts_at, ends_at)
    values ('prompt_' || v_day_key, v_text, v_starts_at, v_ends_at)
    on conflict (id) do nothing;
end;
$$;

comment on function public.ensure_todays_prompt() is
    '本番 prompts に今日の有効なお題が1件も無いとき、決定的アルゴリズムで
     1件生成してupsertする（冪等）。SupabaseBackend.promptState() が
     有効な行を見つけられなかったときに自己修復として呼ぶ。
     28h 有効・24h 周期のため直前プロンプトと 4h overlap するが、
     INSERT 直前に直前プロンプトの `ends_at` を新プロンプトの `starts_at`
     に切り詰めることで `prompts_no_overlap` 制約 (migration 02) を満たす
     （2026-08-30 修正）。PromptGenerator.swift/PromptCatalog.swiftの
     ロジックと候補プールを SQL へ移植。';

revoke all on function public.ensure_todays_prompt() from public;
grant execute on function public.ensure_todays_prompt() to authenticated;
