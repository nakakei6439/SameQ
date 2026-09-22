-- SameQ: 英語の運営回答を追加し、運営名義を各ペルソナ名にする
--
-- ## なぜ必要か
--
-- SameQ は「翻訳できない投稿は表示しない」設計（F20・必須）。翻訳モデルは端末に
-- 最初から入っておらず、`openTimeline()` がダウンロードを試みるものの、OS の確認シートの
-- 許可・1言語60秒/全体90秒の予算・回線、というアプリ外の要因に依存する。
--
-- 一方で投稿は**運営回答5件も含めて全件日本語**だった。つまりモデルが揃わない英語端末では
-- 読めるものが1件も無く、タイムラインが空に見える。F20 はスキップを例外として想定している
-- のに、英語端末ではスキップが全件になっていた。
--
-- スキップの挙動（F20）も、翻訳を意識させない UI（F19）も必須仕様なので変えない。
-- 代わりに **どの端末言語でも「翻訳なしで読める回答」が必ず存在する状態**を作る。
--
-- ## 変更内容
--
-- 1. 英語名義の運営アカウント5件（…0006〜…000a）を追加し、`is_official = true` を付ける。
--    付け忘れると英語の運営回答だけが禁止語フィルタと自動非表示の対象になり、前提39 が
--    英語側だけ破れる。
-- 2. 既存5件のニックネームを `SameQ運営` から各ペルソナ名＋「（運営）」へ変更する
--    （memory の B案）。絵文字もペルソナに合わせる。いずれも `EmojiCatalog.all`
--    （実ユーザーが選べる48件）に含まれないものを使う。
-- 3. `ensure_official_answers()` を、日本語5件＋英語5件の計10件を入れるように拡張する。
--    カテゴリの決め方は 20260922000001 と同じ「その日のお題テキストの前方一致」のまま。
--
-- 効果:
--   英語端末 → 英語5件がそのまま読める。日本語5件はモデルが無ければ静かにスキップ。
--   日本語端末 → 日本語5件がそのまま読める。英語5件はモデルがあれば読め、無ければスキップ。
--   どちらのロケールでも「回答0件」にならない。

-- ---------------------------------------------------------------------------
-- 1) 英語名義の運営アカウント
-- ---------------------------------------------------------------------------
insert into public.users (id, emoji, nickname, created_at, status) values
    ('00000000-0000-0000-0000-000000000006', '🛠️', 'Keita (SameQ)',  now(), 'active'),
    ('00000000-0000-0000-0000-000000000007', '🎒', 'Emily (SameQ)',  now(), 'active'),
    ('00000000-0000-0000-0000-000000000008', '🤖', 'Robo (SameQ)',   now(), 'active'),
    ('00000000-0000-0000-0000-000000000009', '🐈', 'Tetra (SameQ)',  now(), 'active'),
    ('00000000-0000-0000-0000-00000000000a', '🐉', 'Dragon (SameQ)', now(), 'active')
on conflict (id) do nothing;

update public.users
set is_official = true
where id in (
    '00000000-0000-0000-0000-000000000006',
    '00000000-0000-0000-0000-000000000007',
    '00000000-0000-0000-0000-000000000008',
    '00000000-0000-0000-0000-000000000009',
    '00000000-0000-0000-0000-00000000000a'
);

-- ---------------------------------------------------------------------------
-- 2) 既存の日本語名義をペルソナ名にする（memory の B案）
-- ---------------------------------------------------------------------------
-- 20260905000001 は「運営という1つの主体に見せる」ために5件とも `SameQ運営` で共通に
-- していた。B案の採用でその方針は撤回する。
update public.users set emoji = '🛠️', nickname = 'ケータ（運営）'   where id = '00000000-0000-0000-0000-000000000001';
update public.users set emoji = '🎒', nickname = 'エミリー（運営）' where id = '00000000-0000-0000-0000-000000000002';
update public.users set emoji = '🤖', nickname = 'ロボ（運営）'     where id = '00000000-0000-0000-0000-000000000003';
update public.users set emoji = '🐈', nickname = 'テトラ（運営）'   where id = '00000000-0000-0000-0000-000000000004';
update public.users set emoji = '🐉', nickname = 'ドラゴン（運営）' where id = '00000000-0000-0000-0000-000000000005';

-- ---------------------------------------------------------------------------
-- 3) 日本語5件＋英語5件を入れる
-- ---------------------------------------------------------------------------
create or replace function public.ensure_official_answers()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_body_by_category text[][] := array[
        -- 0: 今日〜 ─ その日あった小さな取りこぼしや、救われた瞬間
        array[
            '財布の中に、たまたま入っていた500円玉でコンビニのコーヒーを買えた。',
            '自販機のボタン押し間違えで、違う飲み物が来たんだけど、思ったより美味しかった。',
            'メールの返信を後回しにしようと思っていたら、先方から「いつでも大丈夫」と一文だけ添えてもらって気持ちが軽くなった。',
            '昼休みに食べたものの写真を、後輩が「それおいしそう」と言ってくれて、写真を撮る習慣が少し報われた気がした。',
            '帰り道、踏切が閉まってくれて少しだけ足が止まった。立ち止まること自体が久しぶりで、ちょっと得した。'
        ],
        -- 1: 最近〜 ─ ここ数日の変化・気付き・もらった一言 (5 件)
        array[
            'コンビニで「温めますか？」と聞かれたとき、いつもより丁寧に「お願いします」と言えた自分、ちょっと成長したかも。',
            '自分の判断が後々うまくはまって、「あのとき直感で決めてよかった」と静かに思える場面があった。',
            '電車が遅延したときに苛立つ自分より、「まあ、これもひとつの余白」と思える自分が少しだけ増えてきた気がする。',
            '仕事で分からないことを素直に「教えてください」と言えた。昔からそれは苦手だったのに。',
            '「それ、前より上手に言えるようになったね」と言われた。意識してなかった変化だったので、ちょっと嬉しかった。'
        ],
        -- 2: いま〜 ─ 今この瞬間の気分・好き・食べたいもの・頭の中身 (5 件)
        array[
            'いま食べたいものは「温かいごはん」。理由は説明できないけれど、迷いなくそれが出る。',
            'いま好きな時間は、家族みんながそれぞれ別々のことをしているのに、同じ部屋にいる時間。',
            '頭の中でずっと同じ曲がリフレインしてる。嫌じゃないので、このまま流す。',
            '好きな景色は、帰りの電車から見えた、最後のほうの空。街の灯がぼんやり灯り始めた瞬間が好き。',
            '自分のためにそっと買えるとしたら、厚みのあるノートを一冊。書くかどうかは決めてない。'
        ],
        -- 3: 小さい頃/子供の頃 ─ なつかしい記憶、感覚の断片
        array[
            '夕方、誰もいないのに近所の路地をぐるぐる走り回っていた。何が楽しかったのか、今でも分からないけど、あの空気だけは覚えてる。',
            '母が作ってくれた卵焼きが、なぜかあの頃だけ今よりずっと甘かった。大人の舌で食べても同じはずなのに。',
            '父の「行ってらっしゃい」は、いつも同じ調子だった。声の質というより、リズムが今でも耳に残っている。',
            'こっそり大事にしていたのは、頂き物のチョコレートについてきた小さな金紙の包み。何に使うでもなく、引き出しの一番奥に。',
            '夢に出てきたのは、祖父母の家の廊下。光の入り方がいつも不思議で、冷たいタイルの感触まで覚えている。'
        ],
        -- 4: これから・もし ─ 未来・仮定の小さな約束
        array[
            'これから一週間で時間を増やすなら、「ぼーっとする時間」を少し取り戻したい。ずっと何かしていないと気が引ける性分を、ちょっとだけ緩めたい。',
            'これから一年で新しく始めるなら、毎朝の「一杯の飲み物」を丁寧に淹れる習慣。大きくなくていい。',
            'もし明日の朝少しだけ早起きできたら、開けっ放しの窓のそばで、まず冷たい空気をひと呼吸すっと吸ってみたい。',
            'もし一日だけ知らない街を歩くなら、地図を見ないで右に折れたほうに進む。小さい冒険がしたい。',
            'もし一日だけ音をひとつだけ選べるとしたら、うちの近所で夜に鳴く、あの猫の声をひとつ選びたい。理由は自分でもよく分からない。'
        ],
        -- 5: この一年 ─ 一年の振り返り、はじめて知った自分
        array[
            'この一年で名前を覚えたのは、行きつけの喫茶店の常連さん。いつも同じ席で同じ注文。何も話さないけれど、顔を合わせると安心する。',
            'この一年で見つけた自分の良いところは、「すぐにあきらめない」こと。大げさなことじゃないけれど、地味に効いた。',
            '「変わりましたね」と言われたのは、母から。自分が意識するより、周りのほうが早く見てくれていたのかもしれない。',
            'この一年ではじめて知った好みは、無糖のブラックコーヒー。五年くらい前は到底飲めなかったのに、いつの間にか。',
            'やり直したい小さな選択は、休日に予定を詰め込みすぎた日。あの一日だけでも、もう少し余白を残しておけばよかった。'
        ],
        -- 6: ここ数日/感覚 ─ 色・匂い・味・音・手触り
        array[
            'ここ数日、目を閉じると浮かぶ色は、薄紫。理由は特になくて、それが続いている。',
            '最近は、夕方の家の前の道に漂う、あの生垣の匂いが好き。雨上がりだけちょっと強くなる気がする。',
            'ふと食べたくなった味は、子どもの頃に母が作ってくれた味噌汁の味。今より薄かった気がするけれど、あの感じが好き。',
            '最近はじめて気にいった音は、夜中に遠くで鳴る踏切の音。一日の最後に、その音を最後に聞くと一日が終わる感じがする。',
            '最近手に取るものの感触が少し変わった気がする。すべすべした表紙より、紙の手触りが残るもののほうが手に取ってしまう。'
        ],
        -- 7: 内省・その他 ─ 自分の機嫌、言いそびれた言葉、小さな願い
        array[
            '最近読んでみたいと思ったのは、特にあてもなく手に取った本屋の一冊。タイトルはまだ決めていない。',
            '誰にも話していない小さな願いは、「一週間、誰にも何も頼らず一人で過ごしてみたい」。現実的じゃないのは分かっているけれど。',
            '「なんでもない」と流したけれど本当は少し気になっているのは、職場で軽くかわされた、あの一言。たぶん聞き流していい類のもの。',
            '誰かに相談する前に、まず自分に言いたい言葉は、「もうちょっとだけ寝かせて考えよう」。すぐ決めるとだいたい外すので。',
            '今日の私の機嫌は、左端のお茶が何回飲めるかに一番左右されている気がする。些細なことに振り回されている自覚はある。'
        ]
    ];
    v_body_en_by_category text[][] := array[
        -- 0: 今日〜 ─ その日あった小さな取りこぼしや、救われた瞬間
        array[
            'I found a coin in my coat pocket and it covered the coffee I had already decided not to buy.',
            'I pressed the wrong button on the vending machine, and the drink that came out was better than my usual one.',
            'I kept putting off a reply, and then they wrote back saying there was no rush at all. One line, and the day got lighter.',
            'A colleague said the lunch I photographed looked good, and my habit of photographing lunch felt slightly justified.',
            'The crossing gate came down on my way home and I had to stand still. It had been a while since I just stood somewhere.'
        ],
        -- 1: 最近〜 ─ ここ数日の変化・気付き・もらった一言
        array[
            'Lately I have been going to bed earlier, and I still cannot tell whether it is working.',
            'Someone told me I laugh louder than I think I do, and I have been listening for it ever since.',
            'I started leaving the window open while I work, and the room sounds like a different room now.',
            'A friend said I sounded better than last month, and I had not noticed that anything had changed.',
            'I have started reading again. Badly, a few pages at a time, but again.'
        ],
        -- 2: いま〜 ─ 今この瞬間の気分・好き・食べたいもの・頭の中身
        array[
            'Right now I want something warm and salty, and nothing else will do.',
            'My head is mostly taken up by a song I heard once this morning and cannot name.',
            'I am in the mood to reorganise a drawer that does not need reorganising.',
            'What I like right now is that it is quiet and nobody needs me to say anything.',
            'I want to sit somewhere with a view and not check the time for a while.'
        ],
        -- 3: 小さい頃/子供の頃 ─ なつかしい記憶、感覚の断片
        array[
            'The smell of the corridor at my grandparents'' house comes back before any of the pictures do.',
            'I remember the exact weight of my school bag and nothing at all about what was in it.',
            'There was a low wall I used to walk along, one foot in front of the other, every single day.',
            'Summer sounded like an electric fan turning, and almost nothing else.',
            'I liked being the last one picked up, though I would never have admitted it then.'
        ],
        -- 4: これから・もし ─ 未来・仮定の小さな約束
        array[
            'If I had one free day, I would get on a train without deciding where to get off.',
            'I would like to learn one dish well enough to cook it without looking anything up.',
            'If I could hand one thing to someone, it would be an afternoon with nothing in it.',
            'I would like to write letters again. Badly, and late, but actually send them.',
            'If tomorrow were empty, I would sleep until it stopped feeling like a waste.'
        ],
        -- 5: この一年 ─ 一年の振り返り、はじめて知った自分
        array[
            'This year I learned that I am better in the mornings than I have ever claimed to be.',
            'I found out that I do not actually like being busy. I like being asked.',
            'This year I started putting down books I was not enjoying, and ended up reading more.',
            'I learned that I ask for help about two weeks later than I should.',
            'I noticed that I am calmer near water, which is inconvenient where I live.'
        ],
        -- 6: ここ数日/感覚 ─ 色・匂い・味・音・手触り
        array[
            'The air has smelled like rain for three days without it actually raining.',
            'Everything has tasted slightly too sweet this week, including things that are not sweet.',
            'I keep noticing how cold the door handle is first thing in the morning.',
            'There is a low hum in this building that I only ever hear after nine at night.',
            'The afternoon light has gone the colour of weak tea.'
        ],
        -- 7: 内省・その他 ─ 自分の機嫌、言いそびれた言葉、小さな願い
        array[
            'The small wish I have not told anyone is a week where nobody needs anything from me.',
            'I said it was nothing, and it was not nothing. It was one sentence, brushed aside, at work.',
            'Before asking anyone else, I would tell myself to sleep on it. I get things wrong when I decide fast.',
            'My mood today depends almost entirely on how many cups of tea I manage to finish.',
            'There is a thank-you I have been carrying around for months without delivering it.'
        ]
    ];
    v_official_ja uuid[] := array[
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000005'
    ];
    v_official_en uuid[] := array[
        '00000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-000000000008',
        '00000000-0000-0000-0000-000000000009',
        '00000000-0000-0000-0000-00000000000a'
    ];
    v_day_key     text;
    v_prompt_id   text;
    v_prompt_text text;
    v_category    int;
    v_inserted    int;
    v_rc          int;
    i             int;
begin
    v_day_key   := to_char((now() at time zone 'utc')::date, 'YYYYMMDD');
    v_prompt_id := 'prompt_' || v_day_key;

    select p.text into v_prompt_text from public.prompts p where p.id = v_prompt_id;
    if v_prompt_text is null then
        raise notice 'ensure_official_answers: prompt=% がまだ無いので何もしない', v_prompt_id;
        return;
    end if;

    -- お題の文頭から意味カテゴリを引く（20260922000001 と同じ）。
    v_category := case
        when v_prompt_text like '今日%'       then 0
        when v_prompt_text like '最近%'       then 1
        when v_prompt_text like 'いま%'       then 2
        when v_prompt_text like '小さい頃%'   then 3
        when v_prompt_text like '子どもの頃%' then 3
        when v_prompt_text like 'もし%'       then 4
        when v_prompt_text like 'この一年%'   then 5
        else 7
    end;

    v_inserted := 0;

    for i in 1..5 loop
        insert into public.posts (prompt_id, author_id, body, body_language)
        values (v_prompt_id, v_official_ja[i], v_body_by_category[v_category + 1][i], 'ja')
        on conflict (prompt_id, author_id) do nothing;
        get diagnostics v_rc = row_count;
        v_inserted := v_inserted + v_rc;
    end loop;

    -- 英語端末で「翻訳なしで読める回答」を必ず確保する。
    for i in 1..5 loop
        insert into public.posts (prompt_id, author_id, body, body_language)
        values (v_prompt_id, v_official_en[i], v_body_en_by_category[v_category + 1][i], 'en')
        on conflict (prompt_id, author_id) do nothing;
        get diagnostics v_rc = row_count;
        v_inserted := v_inserted + v_rc;
    end loop;

    raise notice 'ensure_official_answers: prompt=% category=% inserted=%', v_prompt_id, v_category, v_inserted;
end;
$$;

comment on function public.ensure_official_answers() is
    '本番の `world_timeline` に運営アカウントの投稿が常に並ぶよう自己修復する (冪等)。
     日本語5件＋英語5件を入れる。英語を入れるのは、翻訳モデルが未取得の英語端末でも
     「翻訳なしで読める回答」が必ず存在するようにするため (F20 のスキップが全件に及ぶと
     タイムラインが空に見えるため)。
     カテゴリはその日の実際のお題テキストの前方一致で決める (20260922000001)。';

revoke all on function public.ensure_official_answers() from public;
grant execute on function public.ensure_official_answers() to authenticated;
