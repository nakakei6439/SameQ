-- SameQ 緊急対応: 本番 prompts が空のままお題が出ない不具合の恒久対策（2026-08-29）
--
-- 背景:
--   spec.md の F26（「お題生成は生成AI APIをEdge Functionから1日1回呼ぶ」）は
--   実際には実装されなかった。`supabase/functions/` は存在しない。代わりに
--   sprint09 で実装されたのは UTC暦日ベースの決定的な候補選出ロジック
--   （`SameQ/Backend/PromptGenerator.swift` / `PromptCatalog.swift`）だが、
--   これは `LocalBackend`（オフライン開発用）にのみ配線されており、Release
--   ビルドが常に使う `SupabaseBackend` からは一度も呼ばれていなかった。
--   `SupabaseBackend.promptState()` は `prompts` への GET のみを行い、
--   書き込み（insert/upsert）経路は一切存在しない。
--
--   本番 `prompts` に過去唯一データが入ったのは sprint12 attempt8 での手動
--   `seed.sql` 投入（2026-08-27）だが、相対時刻（`now()-2h`/`now()+26h`）で
--   投入したため約1日強で自然に期限切れとなり、以後 `prompts` は0件のまま
--   だった。TestFlight外部テスト準備中に発覚（2026-08-29）。
--
-- 対応方針:
--   `ensure_todays_prompt()` という自己修復用の RPC 関数を追加する。
--   `PromptGenerator.swift` と全く同じ決定的アルゴリズム（UTC暦日の
--   `dayKey`/`dayIndex`、候補プールからの選出、28時間の有効期間、
--   `id = 'prompt_' || dayKey`）を SQL に移植し、`on conflict (id) do nothing`
--   で冪等にupsertする。候補プール48件は `PromptCatalog.candidatePool`
--   （Swift側）から一字一句コピーして移植している（声色を揃えるため）。
--
--   `SupabaseBackend.promptState()` 側で、`prompts` に有効行が見つからない
--   ときにこの関数を RPC 呼び出ししてから再取得する（コード側の変更は別コミット）。
--   これにより pg_cron のような日次バッチジョブが無くても、最初に気づいた
--   クライアントが自動的にサーバー側の空白を埋める。pg_cron は本番で未有効化
--   （`cron.job` テーブルが存在しないことを確認済み）のため、これに依存しない
--   設計にした。
--
-- 冪等性:
--   `on conflict (id) do nothing` により、同じ UTC 日に何度呼ばれても安全
--   （2件目以降は何もしない）。認証済みユーザー（匿名アカウント含む）なら
--   誰が呼んでも同じ結果になるため、副作用の心配はない。
-- ---------------------------------------------------------------------------

create or replace function public.ensure_todays_prompt()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
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
    v_day_key   text;
    v_day_index int;
    v_pool_size int := array_length(v_pool, 1);
    v_start_idx int;
    v_text      text;
    v_starts_at timestamptz;
    v_ends_at   timestamptz;
begin
    -- `PromptGenerator.dayKey(for:)` / `.dayIndex(for:)` と同じ定義:
    -- UTC暦日を "yyyyMMdd" にした文字列、および 1970-01-01 UTC からの経過日数。
    v_day_key   := to_char(now() at time zone 'utc', 'YYYYMMDD');
    v_day_index := (date(now() at time zone 'utc') - date '1970-01-01');

    -- `PromptGenerator.generate(dayKey:dayIndex:...)` の `startIndex` 計算式と同じ
    -- （プールの隣接日に近いお題が続けて出ないよう、中盤から走査する）。
    v_start_idx := ((v_day_index % v_pool_size) + v_pool_size / 2) % v_pool_size;
    v_text      := v_pool[v_start_idx + 1]; -- Postgres 配列は 1-indexed

    -- `PromptGenerator` の `startOfDay(forDayKey:)` / `Prompt.defaultDuration`（28時間）と同じ。
    v_starts_at := date_trunc('day', now() at time zone 'utc') at time zone 'utc';
    v_ends_at   := v_starts_at + interval '28 hours';

    insert into public.prompts (id, text, starts_at, ends_at)
    values ('prompt_' || v_day_key, v_text, v_starts_at, v_ends_at)
    on conflict (id) do nothing;
end;
$$;

comment on function public.ensure_todays_prompt() is
    '本番 prompts に今日の有効なお題が1件も無いとき、決定的アルゴリズムで
     1件生成してupsertする（冪等）。SupabaseBackend.promptState() が
     有効な行を見つけられなかったときに自己修復として呼ぶ。
     PromptGenerator.swift/PromptCatalog.swiftのロジックと候補プールを
     SQLへ移植したもの。2026-08-29 緊急対応で追加。';

-- 認証済みユーザー（匿名アカウント含む）なら誰が呼んでも安全・冪等なので、
-- authenticated ロールに実行権を付与する。
revoke all on function public.ensure_todays_prompt() from public;
grant execute on function public.ensure_todays_prompt() to authenticated;
