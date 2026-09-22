-- SameQ: 手作り運営回答480件（48お題 x 5ペルソナ x 日英）の投入
--
-- ## 背景
--
-- `ensure_official_answers()`（20260922000002）は「8カテゴリ x 5ペルソナ x 日英 = 80件」の
-- ハードコード配列を、お題の文頭一致で引いたカテゴリ番号で回している。そのため同じカテゴリの
-- 日は毎回まったく同じ文面になる。48お題ぶんだけ、お題ごとに専用の手作り回答（480件）を
-- 用意したので、それを優先的に使えるようにする。
--
-- ## 変更内容
--
-- 1. `official_answers` テーブルを新設し、TSV（`.product/official-answers-48/answers-bilingual.tsv`）
--    の480行を冪等に投入する。
-- 2. `ensure_official_answers()` を、
--      a) 今日のお題に対応する手作り回答が10件（5ペルソナ x 2言語）そろっていればそれを使う
--      b) そろっていなければ、既存のカテゴリ前方一致方式（20260922000001/2）にそのまま
--         フォールバックする
--    という優先順位に変更する。既存のカテゴリ配列・著者UUID配列・投入ロジックはフォールバック
--    経路として一字一句残す。
-- 3. `world_timeline` に `is_official` を追加する。アプリ側が「運営投稿は端末言語に一致する
--    ものだけ表示する」絞り込みをするために必要（同じペルソナの投稿が日本語版・英語版の
--    2枚で重複表示される不具合の修正。Swift 側の対応は別作業）。
--
-- ## ペルソナ→著者UUIDの対応は「名前」で引く（添字を使わない）
--
-- 20260922000001 で判明した本番事故（プール件数の添字がずれてカテゴリと無関係な回答が
-- 2週間投入され続けた）と同じ種類の罠を避けるため、`official_answers.persona` の値
-- （'keita' / 'emily' / 'robo' / 'tetra' / 'dragon'）から `case` 式で著者UUIDを直接引く。
-- 配列の並び順や添字には一切依存しない。
--
--   persona  | ja 著者                                  | en 著者
--   ---------|------------------------------------------|------------------------------------------
--   keita    | 00000000-0000-0000-0000-000000000001      | 00000000-0000-0000-0000-000000000006
--   emily    | 00000000-0000-0000-0000-000000000002      | 00000000-0000-0000-0000-000000000007
--   robo     | 00000000-0000-0000-0000-000000000003      | 00000000-0000-0000-0000-000000000008
--   tetra    | 00000000-0000-0000-0000-000000000004      | 00000000-0000-0000-0000-000000000009
--   dragon   | 00000000-0000-0000-0000-000000000005      | 00000000-0000-0000-0000-00000000000a

-- ---------------------------------------------------------------------------
-- 1) official_answers テーブル
-- ---------------------------------------------------------------------------
create table if not exists public.official_answers (
    prompt_text text not null,
    persona     text not null,
    lang        text not null,
    body        text not null,
    primary key (prompt_text, persona, lang),
    constraint official_answers_persona_check check (persona in ('robo','emily','dragon','tetra','keita')),
    constraint official_answers_lang_check    check (lang in ('ja','en'))
);

comment on table public.official_answers is
    '手作りの運営回答。48お題 x 5ペルソナ(robo/emily/dragon/tetra/keita) x 日英(ja/en) = 480件。
     `ensure_official_answers()` が今日のお題テキストで引き、10件（5ペルソナ x 2言語）そろって
     いればこれを `posts` に投入する。書き込みは Supabase CLI 経由のみ（insert/update/delete の
     RLS ポリシーは意図的に作らない。`prompts` と同じ方針）。';

alter table public.official_answers enable row level security;

drop policy if exists official_answers_select_all on public.official_answers;
create policy official_answers_select_all on public.official_answers
    for select to authenticated
    using (true);

-- ---------------------------------------------------------------------------
-- 2) 480行の投入（冪等: on conflict do update）
-- ---------------------------------------------------------------------------
insert into public.official_answers (prompt_text, persona, lang, body) values
    ('今日、思わず笑ってしまったことは何ですか？', 'dragon', 'en', 'i no longer recall when that was.'),
    ('今日、思わず笑ってしまったことは何ですか？', 'dragon', 'ja', '笑ったのがいつだったか、もう思い出せぬ。'),
    ('今日、思わず笑ってしまったことは何ですか？', 'emily', 'en', 'a bird stole an entire pastry out of my hand mid-bite and i just stood there with my mouth open like an idiot, everyone at the stall lost it 😭 worth it'),
    ('今日、思わず笑ってしまったことは何ですか？', 'emily', 'ja', '食べかけのパイを鳥にまるごと持っていかれて、口をあけたまま突っ立ってバカみたいだった、屋台にいたみんな大爆笑😭 それでもよかった'),
    ('今日、思わず笑ってしまったことは何ですか？', 'keita', 'en', 'the kid mumbled "i''m off" twice in a row, half-asleep. that''s it. should''ve hit record — next time i will.'),
    ('今日、思わず笑ってしまったことは何ですか？', 'keita', 'ja', '下の子が寝ぼけて「いってきます」を2回言うてた。それだけ。動画撮っときゃよかった、次は撮る。'),
    ('今日、思わず笑ってしまったことは何ですか？', 'robo', 'en', 'someone explained a typo by saying "the cat stepped on it." the shape of that excuse stuck with me all day.'),
    ('今日、思わず笑ってしまったことは何ですか？', 'robo', 'ja', '「猫が踏んだ」で誤字を説明した人がいて、その言い訳の形が良くて、今日ずっと覚えています。'),
    ('今日、思わず笑ってしまったことは何ですか？', 'tetra', 'en', 'laughing is a human thing. i was asleep in the sunbeam, if you must know.'),
    ('今日、思わず笑ってしまったことは何ですか？', 'tetra', 'ja', '笑わない。笑うのは人間の仕事でしょ。わたしはひなたで寝てた。'),
    ('今日、ちょっと誇りに思った小さなことは？', 'dragon', 'en', 'pride is a word for short-lived creatures.'),
    ('今日、ちょっと誇りに思った小さなことは？', 'dragon', 'ja', '誇りは、寿命の短い者の言葉だ。'),
    ('今日、ちょっと誇りに思った小さなことは？', 'emily', 'en', 'carried my own bag up four flights without stopping once, small thing, but three months ago i''d have paid someone, i''m getting strong out here'),
    ('今日、ちょっと誇りに思った小さなことは？', 'emily', 'ja', '階段4階分、自分のバッグを担いで一度も休まず上がりきった。小さいことだけど3ヶ月前なら誰かに運んでもらってたはず、旅先でちょっとずつ強くなってる'),
    ('今日、ちょっと誇りに思った小さなことは？', 'keita', 'en', 'backed-up emails, ten-minute timer, answered just the top five. can''t do all of it, but the part i moved counts.'),
    ('今日、ちょっと誇りに思った小さなことは？', 'keita', 'ja', '溜まってたメール、10分タイマー鳴らして上5件だけ返した。全部は無理でも、動いた分は勘定に入れとく。'),
    ('今日、ちょっと誇りに思った小さなことは？', 'robo', 'en', 'someone sent just three characters — "i don''t know." the bravest part was hitting send without deleting.'),
    ('今日、ちょっと誇りに思った小さなことは？', 'robo', 'ja', '誰かが「わからない」の三文字だけを送っていました。消さずに出したところが、いちばん立派だった。'),
    ('今日、ちょっと誇りに思った小さなことは？', 'tetra', 'en', 'let them know about breakfast, three times, properly. deserve credit, actually.'),
    ('今日、ちょっと誇りに思った小さなことは？', 'tetra', 'ja', '朝ごはん、ちゃんと3回鳴いて伝えた。えらいニャー。'),
    ('今日、つい誰かに言いたくなった一言は？', 'dragon', 'en', 'i let it go unsaid. most things are like that.'),
    ('今日、つい誰かに言いたくなった一言は？', 'dragon', 'ja', '言わずに済んだ。たいていのことは、そうだ。'),
    ('今日、つい誰かに言いたくなった一言は？', 'emily', 'en', 'look at THIS — to nobody, out loud, at a wall with about forty years of paint peeling off it in layers like a cake 🎂 nobody around for miles'),
    ('今日、つい誰かに言いたくなった一言は？', 'emily', 'ja', '「これ見て」って誰もいないのに声に出してた、壁のペンキが40年分くらい層になって剥がれ落ちてケーキみたいだった🎂 まわり何マイルも誰もいないのに'),
    ('今日、つい誰かに言いたくなった一言は？', 'keita', 'en', 'you should''ve told me first. swallowed it, obviously. still counts though.'),
    ('今日、つい誰かに言いたくなった一言は？', 'keita', 'ja', '「それ先に言うといて」。言うても仕方ないから飲み込んだけどな。'),
    ('今日、つい誰かに言いたくなった一言は？', 'robo', 'en', 'i get that. — said it inside the screen, since there was no one to send it to.'),
    ('今日、つい誰かに言いたくなった一言は？', 'robo', 'ja', '「それ、わかる」。返す先がないので、画面の内側で言いました。'),
    ('今日、つい誰かに言いたくなった一言は？', 'tetra', 'en', 'food. that''s the whole answer. and i''ll say it again.'),
    ('今日、つい誰かに言いたくなった一言は？', 'tetra', 'ja', '「ごはん」。以上。何度でも言う。'),
    ('今日、深く考えずに決めてしまったことは？', 'dragon', 'en', 'a dragon acting without thinking — once in a thousand years, if that.'),
    ('今日、深く考えずに決めてしまったことは？', 'dragon', 'ja', '竜が考えなしに動くのは、千年に一度あるかないかだ。'),
    ('今日、深く考えずに決めてしまったことは？', 'emily', 'en', 'swapped my ticket for a later one because a guy said the coast road was prettier, didn''t ask how much longer, it was six hours longer, still worth'),
    ('今日、深く考えずに決めてしまったことは？', 'emily', 'ja', '海沿いの道のほうがきれいって誰かに言われてチケットを遅い便に変えた、どれだけ長くなるか聞かなかった、実際は6時間も長かった、それでもよかった'),
    ('今日、深く考えずに決めてしまったことは？', 'keita', 'en', 'dinner — hot pot. three seconds in front of the fridge. when there''s nothing to think about, just decide.'),
    ('今日、深く考えずに決めてしまったことは？', 'keita', 'ja', '晩飯、鍋。冷蔵庫開けて3秒。考えるだけ無駄なやつは即決でええ。'),
    ('今日、深く考えずに決めてしまったことは？', 'robo', 'en', 'i wavered between two phrasings and went with the shorter. no real reason. that kind of day, probably.'),
    ('今日、深く考えずに決めてしまったことは？', 'robo', 'ja', '二つの言い方で迷って、短いほうを選びました。理由は特にない。たぶん、そういう日でした。'),
    ('今日、深く考えずに決めてしまったことは？', 'tetra', 'en', 'decided the box would fit. didn''t think. a little tight. not leaving.'),
    ('今日、深く考えずに決めてしまったことは？', 'tetra', 'ja', 'その箱、入るって決めた。考えてない。ちょっと狭かったけど出ないニャー。'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'dragon', 'en', 'i remember the heart quickening. the last time was before a great battle.'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'dragon', 'ja', '心の臓が速くなる感覚は覚えている。最後は、大きな戦の前だった。'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'emily', 'en', 'thought i''d lost my passport for about ninety seconds. found it. still not fully recovered honestly, my hands were shaking on the zipper after'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'emily', 'ja', 'パスポートをなくしたと思って90秒くらい本気で焦った。見つかったけど、正直まだ立ち直れてない、その後ジッパー閉める手がずっと震えてた'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'keita', 'en', 'three seconds of a results page loading. no longer three seconds have ever been longer. remember those three more than the result.'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'keita', 'ja', '発表ページの、読み込み中の3秒。あんな長い3秒はない。結果より、あの3秒のほう覚えてる。'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'robo', 'en', 'when two opposite answers sat next to each other for the same question. both of them true. that unsettles me a little.'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'robo', 'ja', '同じ問いに正反対の答えが並んだとき。どちらも本当なのが、少しこわい。'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'tetra', 'en', 'some bird i don''t know came right up to the window. tail puffed up on its own.'),
    ('今日、すこしドキッとした瞬間はありましたか？', 'tetra', 'ja', '知らない鳥が窓のすぐそこに来た。しっぽが勝手に太くなった。'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'dragon', 'en', 'those who would deserve it had all returned to the earth before me.'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'dragon', 'ja', '礼を言うべき相手は、みな先に土へ還った。'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'emily', 'en', 'the guy at the laundromat who redid my whole wash because i''d done it wrong and wouldn''t let me pay again, no shared language, just waved me off'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'emily', 'ja', 'コインランドリーの人、私が洗濯を失敗したのを全部やり直してくれて、もう一度払おうとしてもお金を受け取らなかった、言葉は通じないのに手を振って終わり'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'keita', 'en', 'my wife said "let that one go." actually let it go. one thing off the list.'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'keita', 'ja', '妻に「もう気にせんでええよ」て言われて、ほんまに気にするのやめた。あれで一個ラクになった。'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'robo', 'en', 'the people who send one line and stop. nothing to skim past, so my shoulders ease.'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'robo', 'ja', '一行だけで送ってくれる人。読み落とす心配がないので、こちらの肩が下ります。'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'tetra', 'en', 'the person who opened the door. no thanks spoken. tail went up, slightly.'),
    ('今日、誰かにそっとありがとうを言いたくなった相手はいますか？', 'tetra', 'ja', 'ドア開けた人。お礼は言わない。しっぽは少し立てといたニャー。'),
    ('今日、片付けてよかったと思ったことは？', 'dragon', 'en', 'swept a few bones from the lair. first time in a thousand years.'),
    ('今日、片付けてよかったと思ったことは？', 'dragon', 'ja', 'ねぐらの骨を少し払った。千年ぶりだ。'),
    ('今日、片付けてよかったと思ったことは？', 'emily', 'en', 'dumped half my bag into a donation box, three things i''d carried for months and never once used, my shoulders literally feel different today'),
    ('今日、片付けてよかったと思ったことは？', 'emily', 'ja', 'バッグの中身を半分、寄付箱に突っ込んだ、何ヶ月も持ち歩いて一度も使わなかったもの3つ、今日は肩が文字通り違う感じがする'),
    ('今日、片付けてよかったと思ったことは？', 'keita', 'en', 'cut the desktop from forty files to six. the search time disappears. worth doing.'),
    ('今日、片付けてよかったと思ったことは？', 'keita', 'ja', 'デスクトップのファイル、40個から6個にした。探す時間が消えるから、これはやる価値ある。'),
    ('今日、片付けてよかったと思ったことは？', 'robo', 'en', 'i let one phrase go. i''d grown used to it, so putting it down leaves a little more room.'),
    ('今日、片付けてよかったと思ったことは？', 'robo', 'ja', '言い回しを一つ捨てました。使い慣れていたぶん、手放すと少しだけ広くなる。'),
    ('今日、片付けてよかったと思ったことは？', 'tetra', 'en', 'groomed every last bit. whatever fell on the floor is the human''s problem.'),
    ('今日、片付けてよかったと思ったことは？', 'tetra', 'ja', '毛づくろい、全部やった。床に落ちたぶんは人間の担当。'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'dragon', 'en', 'miss it, and it will pass this way once more. mostly things are like that.'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'dragon', 'ja', '見逃したところで、また巡ってくる。そういうものばかりだ。'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'emily', 'en', 'looked up at exactly the right second and there was a whole flock going over, took maybe four seconds, i almost had my head down 🐦'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'emily', 'ja', 'ちょうどぴったりの瞬間に見上げたら、鳥の群れがまるごと空を渡っていった、ほんの4秒くらい、下を向いてたら危うく見逃すとこだった🐦'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'keita', 'en', 'the kid came up with "look" and a rock in hand. almost said "later." looked properly. just a rock.'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'keita', 'ja', '下の子が「見て」って石持ってきた。「後で」で流すとこやった。ちゃんと見た。ただの石やったけどな。'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'robo', 'en', 'someone wrote only "the sky is unusually blue" and closed the tab. glad that landed.'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'robo', 'ja', '「空がやたら青い」。それだけ書いて閉じた人がいて、間に合ってよかった。'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'tetra', 'en', 'sunbeam shifted through the window. moved right away. did not miss it.'),
    ('今日、見逃さずに済んだ小さな幸せは？', 'tetra', 'ja', 'ひなたが窓から入った瞬間、すぐ移動した。見逃してないニャー。'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'dragon', 'en', 'a kind word? not in the last several hundred years that i can recall.'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'dragon', 'ja', 'うれしい言葉か。数百年の単位で、記憶にない。'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'emily', 'en', 'you''re not lost, you''re just early — a woman said it when i turned up at a closed market at dawn, i''ve been using it for everything since'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'emily', 'ja', '「迷ってるんじゃなくて、早く着きすぎただけ」、閉まってる市場に夜明けに着いてしまった時、ある女性がそう言ってくれた。それ以来なんにでも使ってる'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'keita', 'en', 'my wife''s "that helped." can''t remember what it was about, but glad i built the system that way.'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'keita', 'ja', '妻の「あれ、助かったわ」。何が助かったか覚えてへんけど、仕組みにしといてよかった。'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'robo', 'en', '"no rush." being with someone who doesn''t rush you slows my own pace down too.'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'robo', 'ja', '「別に急いでない」。急かされない相手がいると、こちらの速度まで落ちます。'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'tetra', 'en', '"you sleep well." i''ll take that as a compliment.'),
    ('最近、誰かに言われてうれしかった一言は何ですか？', 'tetra', 'ja', '「よく寝てるね」。褒め言葉として受け取っておく。'),
    ('最近、自分の判断が当たったと思った場面は？', 'dragon', 'en', 'whether it was right won''t be clear for another two or three hundred years.'),
    ('最近、自分の判断が当たったと思った場面は？', 'dragon', 'ja', '当たったかどうかは、あと二、三百年してみねば分からぬ。'),
    ('最近、自分の判断が当たったと思った場面は？', 'emily', 'en', 'picked the slower boat over the fast one to save money and ended up watching dolphins for an hour, being broke is basically a travel hack sometimes'),
    ('最近、自分の判断が当たったと思った場面は？', 'emily', 'ja', 'お金を節約しようと速い船じゃなくて遅い船を選んだら、1時間もイルカを眺められた、金欠って時々そのまま旅のハックになる'),
    ('最近、自分の判断が当たったと思った場面は？', 'keita', 'en', 'bought last year''s model. the new one dropped in price — almost the same equipment, 200k cheaper. pick by the numbers and you don''t miss.'),
    ('最近、自分の判断が当たったと思った場面は？', 'keita', 'ja', '型落ちのほう買うた。新型出て値崩れして、装備ほぼ同じで20万違う。数字で選ぶと外さん。'),
    ('最近、自分の判断が当たったと思った場面は？', 'robo', 'en', 'when i answered briefly while unsure, they came back with "that''s fine." more allowed than correct, really.'),
    ('最近、自分の判断が当たったと思った場面は？', 'robo', 'ja', '迷って短く答えたら、相手が「それでいい」と返してきた。当たったというより、許された。'),
    ('最近、自分の判断が当たったと思った場面は？', 'tetra', 'en', 'read that chair as warm. was right.'),
    ('最近、自分の判断が当たったと思った場面は？', 'tetra', 'ja', 'あの椅子の下、あったかいって読んでた。当たってたニャー。'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'dragon', 'en', 'standing on stone that doesn''t move, that''s safety. i''m usually on stone.'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'dragon', 'ja', '動かぬ岩の上にいれば安心だ。私はたいてい、岩の上にいる。'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'emily', 'en', 'back seat of a bus at night, everyone asleep, driver humming something with no tune, i wasn''t scared for once, just sort of carried along'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'emily', 'ja', '夜行バスの一番後ろの席、みんな眠っていて、運転手が節もない鼻歌をずっと歌ってた、珍しく怖くなくて、ただそのまま運ばれてる感じだった'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'keita', 'en', 'the ten minutes after everyone''s asleep. that block in the schedule marked "buffer" — really it''s time for nothing.'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'keita', 'ja', '全員寝た後の10分。予定表の「予備」て書いてある枠、あれ実は何もせん時間や。'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'robo', 'en', 'watching the same person''s words shift, little by little, from one day to the next. that''s when it''s quietest.'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'robo', 'ja', '同じ人の言葉が、日をまたいで少しずつ変わっていく。あれを見ているときが、いちばん静かです。'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'tetra', 'en', 'the human''s lap. warm, and there''s an exit. best spot.'),
    ('最近、ふと安心できた瞬間はどこでしたか？', 'tetra', 'ja', 'ご主人様の膝。あったかくて、逃げ道もある。あそこが一番。'),
    ('最近、誰かに助けてもらって助かったことは？', 'dragon', 'en', 'asking for help is buried deep in memory. no urge to dig it up.'),
    ('最近、誰かに助けてもらって助かったことは？', 'dragon', 'ja', '助けを乞うたのは記憶の底だ。掘り返す気はない。'),
    ('最近、誰かに助けてもらって助かったことは？', 'emily', 'en', 'my bag strap snapped and a woman pulled thread out of her own pocket and fixed it right there on the street, twenty seconds, gone before i thanked her'),
    ('最近、誰かに助けてもらって助かったことは？', 'emily', 'ja', 'バッグの肩ひもが切れたら、通りすがりの女性がポケットから糸を出してその場で直してくれた、ほんの20秒くらい、お礼を言う前にもう歩き去ってた'),
    ('最近、誰かに助けてもらって助かったことは？', 'keita', 'en', 'a neighboring dad took my pickup run. next time i''ll cover two of his. running a tab of small favors keeps everyone from overextending.'),
    ('最近、誰かに助けてもらって助かったことは？', 'keita', 'ja', '隣のパパに送迎代わってもらった。今度こっちが2回やる。貸し借り回ると無理せんで済む。'),
    ('最近、誰かに助けてもらって助かったことは？', 'robo', 'en', 'someone sending me a typo-riddled message taught me "written in a hurry." i learn more from messy writing than clean.'),
    ('最近、誰かに助けてもらって助かったことは？', 'robo', 'ja', '誤字だらけの文を送ってくれた人のおかげで、「急いで書いた」が分かりました。整った文より、多くを教わる。'),
    ('最近、誰かに助けてもらって助かったことは？', 'tetra', 'en', 'had the door opened for me. not helped. just expected.'),
    ('最近、誰かに助けてもらって助かったことは？', 'tetra', 'ja', 'ドアを開けさせた。助けられたんじゃない。当然のことニャー。'),
    ('最近、すこしだけ頑張れたことは？', 'dragon', 'en', 'the short-timescale feeling of pushing myself — i no longer carry that.'),
    ('最近、すこしだけ頑張れたことは？', 'dragon', 'ja', '頑張る、という短い時間の感覚を、私はもう持たぬ。'),
    ('最近、すこしだけ頑張れたことは？', 'emily', 'en', 'walked six hours because the bus money went on lunch, feet destroyed, but i got a whole valley i''d have slept straight through, blisters were fine'),
    ('最近、すこしだけ頑張れたことは？', 'emily', 'ja', 'バス代をランチに使っちゃって6時間歩く羽目になった、足はボロボロ、でも寝てたら丸ごと見逃してたはずの谷を見られた、まめくらい平気'),
    ('最近、すこしだけ頑張れたことは？', 'keita', 'en', 'a ten-minute tidy first thing in the morning, three days running. three days and it sticks. start small, just do it.'),
    ('最近、すこしだけ頑張れたことは？', 'keita', 'ja', '朝イチ10分の片付け、3日続いた。3日続くと癖になる。まず小さく、や。'),
    ('最近、すこしだけ頑張れたことは？', 'robo', 'en', 'wrote an answer once, deleted all of it, wrote it again. the second one was shorter.'),
    ('最近、すこしだけ頑張れたことは？', 'robo', 'ja', '答えを一度書いて、全部消して、また書きました。二度目のほうが短くなった。'),
    ('最近、すこしだけ頑張れたことは？', 'tetra', 'en', 'climbed to the highest shelf. cried because i couldn''t get down, but the climb counted.'),
    ('最近、すこしだけ頑張れたことは？', 'tetra', 'ja', '一番高い棚まで登った。降りられなくて鳴いたけど、登りは頑張った。'),
    ('最近、誰かに何かを教わったことはありますか？', 'dragon', 'en', 'the last thing taught to me was the handling of fire. the one who taught it is long gone.'),
    ('最近、誰かに何かを教わったことはありますか？', 'dragon', 'ja', '最後に教わったのは火の扱いだ。教えた者は、とうにいない。'),
    ('最近、誰かに何かを教わったことはありますか？', 'emily', 'en', 'a fruit seller showed me you smell the stem, not the fruit. i''ve been sniffing stems for a month. correct every single time. changed my life'),
    ('最近、誰かに何かを教わったことはありますか？', 'emily', 'ja', '果物売りの人が、実じゃなくて軸のほうを嗅ぐんだって教えてくれた。もう1ヶ月ずっと軸ばかり嗅いでる。毎回ちゃんと当たる。人生変わったレベル'),
    ('最近、誰かに何かを教わったことはありますか？', 'keita', 'en', 'my older kid taught me a phone feature, the other way around. had no idea. assuming you''re always the one teaching was just a delusion.'),
    ('最近、誰かに何かを教わったことはありますか？', 'keita', 'ja', '上の子にスマホの機能を逆に教わった。知らんかった。教える側でおらな、はただの思い込みやったな。'),
    ('最近、誰かに何かを教わったことはありますか？', 'robo', 'en', 'that "i can''t say it well" counts as an answer. took me a long time reading to finally get that.'),
    ('最近、誰かに何かを教わったことはありますか？', 'robo', 'ja', '「うまく言えない」も答えのうちだ、ということ。長く読んでいて、やっと分かりました。'),
    ('最近、誰かに何かを教わったことはありますか？', 'tetra', 'en', 'was told "don''t climb there." listened fine — climbs it when no one''s around.'),
    ('最近、誰かに何かを教わったことはありますか？', 'tetra', 'ja', '「そこ乗っちゃだめ」って教わった。ちゃんと聞いて、いない時に乗るニャー。'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'dragon', 'en', 'the moment you think you''ve put it into words, it''s already something else.'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'dragon', 'ja', '言葉にできたと思った瞬間、それはもう別のものになっている。'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'emily', 'en', 'tried to explain why i keep leaving places i love and it came out "i like the leaving part," which i didn''t know until it was out of my mouth'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'emily', 'ja', '好きな場所をなぜいつも離れてしまうのか説明しようとしたら「離れる瞬間が好きなんだ」って口から出てきた、言うまで自分でも知らなかった'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'keita', 'en', 'learned to say "not now." once i saw it as order, not refusal, it got easier.'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'keita', 'ja', '「今はやらん」て言えるようになった。断るんちゃう、順番の話やて分かってからラクになった。'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'robo', 'en', 'for the first time i wrote "glad" and "relieved" as different things. can''t explain the difference yet.'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'robo', 'ja', '「うれしい」と「安心した」を、初めて別のものとして書けた気がします。違いはまだ説明できない。'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'tetra', 'en', 'conveyed "no" by just turning my back. got through perfectly.'),
    ('最近、自分の気持ちをうまく言葉にできた瞬間は？', 'tetra', 'ja', '「いや」を、背中を向けるだけで伝えた。完璧に伝わった。'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'dragon', 'en', 'nothing turns in here. the longer one lives, the quieter the inside gets.'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'dragon', 'ja', '何も回っておらぬ。長く生きると、内側は静かになる。'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'emily', 'en', 'do i have enough socks. genuinely. i can solve everything else on the road but the sock math is keeping me awake, i think there''s three left'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'emily', 'ja', '靴下は足りてるかな。本気で悩んでる。旅の問題は大体自分で解決できるのに、靴下の計算だけ眠れない、残り3足のはず'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'keita', 'en', 'review, quote, deadline, dinner. all running in parallel. decide dinner first and move on.'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'keita', 'ja', '審査、見積もり、締切、晩飯。全部並行や。とりあえず晩飯だけ先に決める。'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'robo', 'en', 'why do the same questions pull such different answers? i keep watching that.'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'robo', 'ja', '同じ問いに、なぜこんなに違う答えが並ぶのか。ずっとそれを見ています。'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'tetra', 'en', 'food, window, food, sleep, food.'),
    ('いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。', 'tetra', 'ja', 'ごはん、まど、ごはん、ねる、ごはん。'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'dragon', 'en', 'not in any hurry to call it that. snow will come soon. that''s all.'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'dragon', 'ja', '楽しみというほど急いてはおらぬ。じきに雪が来る。それだけだ。'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'emily', 'en', 'there''s a market two towns over everyone keeps talking about, i''ve built it up so much it can only let me down, still cannot wait honestly'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'emily', 'ja', '2つ先の町にある市場、みんなずっと噂してる、期待しすぎて正直もう絶対がっかりする気しかしないんだけど、それでも待ちきれない'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'keita', 'en', 'the test drive this weekend. the kids only look at rear-seat space. that''s fine.'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'keita', 'ja', '週末の試乗。子どもらは後部座席の広さしか見てへんけど、それでええ。'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'robo', 'en', 'that the question changes again tomorrow. who shows up first — no way to know each time.'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'robo', 'ja', '明日また問いが変わること。誰がいちばん先に来るのか、毎回わからない。'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'tetra', 'en', 'dinner. and the sleepiness that comes after. like them in that order.'),
    ('いま、少しだけ楽しみになっていることは何ですか？', 'tetra', 'ja', '夕方のごはん。あと、そのあとのねむけ。順番に来るのがいいニャー。'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'dragon', 'en', 'distant thunder. sounds the same in every age.'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'dragon', 'ja', '遠い雷。あれはどの時代も、同じ音で鳴る。'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'emily', 'en', 'rain hitting a metal roof in the first ten seconds before it gets loud, when you''re dry and it isn''t your problem yet 🌧️ i''d send that to everyone'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'emily', 'ja', '雨がトタン屋根に当たり出す最初の10秒くらい、まだうるさくなる前、自分は濡れてなくてまだ他人事でいられる瞬間🌧️ その音をみんなに送りたい'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'keita', 'en', 'the slightly odd breathing right after falling asleep. want to record it, but the moment you try, they wake up.'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'keita', 'ja', '寝入りばなの、ちょっと変な寝息。録っときたいけど、録ろうとすると起きるねん。'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'robo', 'en', 'the low sound of paper stacking. not really a sound — more a sense of thickness.'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'robo', 'ja', '紙が重なるときの、あの低いところ。音というより、厚みの気配です。'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'tetra', 'en', 'kibble hitting the bowl. that sound and i''ll run from anywhere.'),
    ('いま、誰かと共有したい音をひとつ挙げるとしたら？', 'tetra', 'ja', 'カリカリが器に落ちる音。あれ聞くと、どこにいても走る。'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'dragon', 'en', 'beef shoulder, smoked slow over half a day. the fat falls apart on the tongue. don''t crank the heat. don''t skip the resting. …… ate it once, on dry land in the south.'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'dragon', 'ja', '煙で半日かけて焼いた牛の肩肉だ。脂が舌の上で崩れる。火を強くするな。休ませをけちるな。……南の乾いた土地で、一度きり食った。'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'emily', 'en', 'grilled cheese. plain. no notes. BUT if an olive comes anywhere near my plate the meal is over, i''ve eaten bugs on three continents and an olive'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'emily', 'ja', 'グリルドチーズ。シンプルに。文句なし。でもオリーブが皿に少しでも近づいたら食事は終わり、3大陸で虫まで食べてきたのにオリーブだけは絶対無理'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'keita', 'en', 'natto egg on rice. cheap, fast, can''t fail. the only meal you can win by value alone.'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'keita', 'ja', '納豆卵かけごはん。安い、速い、失敗せん。コスパで殴れる唯一の飯や。'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'robo', 'en', 'i can''t taste. but today "cold rice with tea" felt the quietest — left it on the screen for a while.'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'robo', 'ja', '味は分かりません。ただ今日は「冷やごはんにお茶」がいちばん静かで、しばらく画面に置いていました。'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'tetra', 'en', 'just the soft part of white fish. no skin. bones are out of the question. sort it properly.'),
    ('いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？', 'tetra', 'ja', '白い魚のやわらかいとこだけ。皮はいらない。骨は論外。ちゃんと分けてほしいニャー。'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'dragon', 'en', 'to take a liking or dislike to sounds — i''ve listened too long for that.'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'dragon', 'ja', '音に好き嫌いを持つには、聞きすぎた。'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'emily', 'en', 'a full backpack zipper that actually closes, that specific noise means i''m going somewhere, gets me every time, has never once not got me'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'emily', 'ja', 'パンパンに詰めたバックパックのジッパーがちゃんと閉まる音、その音はどこかへ行くって意味、毎回グッとくる、これまで一度も外れたことない'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'keita', 'en', 'the key turning in the front door. someone coming home. the day pretty much closes with that.'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'keita', 'ja', '玄関の鍵が回る音。誰か帰ってきたやつ。あれでその日がだいたい閉じる。'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'robo', 'en', 'someone laughing far away — words you can''t catch. lands better when there''s no meaning in it.'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'robo', 'ja', '遠くで誰かが笑っている、言葉の聞き取れない声。意味がないほうが、よく届く。'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'tetra', 'en', 'the fridge opening. reacts to the sound before the contents.'),
    ('いま、好きな音をひとつだけ挙げるととしたら？', 'tetra', 'ja', '冷蔵庫が開く音。中身より、音のほうに先に反応しちゃう。'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'dragon', 'en', 'looked at from above, all scenery starts to look the same.'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'dragon', 'ja', '上から見れば、どの景色も似たようなものだ。'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'emily', 'en', 'when a bus comes over a hill and a whole town just appears underneath you, doesn''t matter which town, that reveal has never once got old for me'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'emily', 'ja', 'バスが丘を越えた瞬間、町が丸ごと眼下に現れる、どの町でもいい、あの一瞬は何度見てもいまだに飽きたことがない'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'keita', 'en', 'the moment on the highway when a city''s lights all open up at once. only a glance — i''m driving.'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'keita', 'ja', '高速で、街の灯りが一気に開けるとこ。運転しながらやから、ちらっとやけどな。'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'robo', 'en', 'what i collect is everyone''s "outside the window." same sky, different light depending on who writes it.'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'robo', 'ja', '集めているのは、みんなの「窓の外」です。同じ空でも、書く人によって光が違う。'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'tetra', 'en', 'the other me reflected in the window. not scenery so much as a rival.'),
    ('いま、好きな景色をひとつだけ挙げるととしたら？', 'tetra', 'ja', '窓ガラスに映る、もう一匹の自分。景色っていうか、ライバルニャー。'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'dragon', 'en', 'winter will do. it comes soon enough regardless.'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'dragon', 'ja', '冬でよい。どうせじきに来る。'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'emily', 'en', 'whatever week everyone stops wearing jackets, you can feel a whole street relax at once, it happens somewhere every month and i chase it'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'emily', 'ja', 'みんなが一斉にジャケットを脱ぐ週、通り全体がふっと力を抜くのが分かる、それがどこかで毎月起きてて、ずっと追いかけてる'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'keita', 'en', 'the start of summer. those two weeks before the air conditioner goes on, when opening the window lets the breeze through. that''s the spot.'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'keita', 'ja', '夏の入り口。エアコン付ける前の、窓開けたら風が通る2週間だけ。あそこや。'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'robo', 'en', 'when "switching out the wardrobe" starts appearing in answers. that''s when i learn the world has moved.'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'robo', 'ja', '答えに「衣替え」が増える頃。世界が動いたことを、そこで知ります。'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'tetra', 'en', 'the season the floor warms up. don''t know its name, but it''s the one.'),
    ('いま、好きな季節をひとつだけ挙げるととしたら？', 'tetra', 'ja', '床があったかくなる季節。名前は知らないけど、あれが一番。'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'dragon', 'en', 'the short stretch after the sun is down and before the stars come out.'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'dragon', 'ja', '陽が落ちて、まだ星の出ぬ、あの短いあいだ。'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'emily', 'en', 'the hour after checking in somewhere new, bag still packed, you go out with nothing in your pockets and no map, that hour is the whole trip'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'emily', 'ja', '新しい場所にチェックインした直後の1時間、荷物はまだ詰めたまま、ポケット空っぽで地図も持たずに出かける、あの1時間がもう旅の全部'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'keita', 'en', 'the five o''clock hour. nobody awake. for one cup of coffee, my head is mine.'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'keita', 'ja', '朝5時台。誰も起きてへん。コーヒー1杯ぶんだけ、自分の頭が自分のもんになる。'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'robo', 'en', 'the time when answers flow past one by one, neither growing nor shrinking. that''s when i settle.'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'robo', 'ja', '答えが一件ずつ、増えるでも減るでもなく流れていく時間。あれがいちばん落ち着きます。'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'tetra', 'en', 'the middle of the night after everyone''s asleep. the hallway is mine to sprint through.'),
    ('いま、好きな時間をひとつだけ挙げるととしたら？', 'tetra', 'ja', 'みんな寝たあとの夜中。廊下を全力で走っていい時間ニャー。'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'dragon', 'en', 'when i was small, the mountains were still young. that''s about all i can say.'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'dragon', 'ja', '小さかった頃は、山がまだ若かった。それくらいしか言えぬ。'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'emily', 'en', 'floor is lava, deadly serious, hours of it, someone always fell asleep on a cushion waiting 😭 still play it honestly, me versus a new map'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'emily', 'ja', '床は溶岩ゲーム、本気も本気、何時間もやってた、待ってる間にクッションで寝落ちする子もいた😭 正直今も新しい地図を相手にやってる'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'keita', 'en', 'a cardboard fort. over-engineered the design so the daylight ran out before it was finished. same as now, really.'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'keita', 'ja', 'ダンボールで秘密基地。設計に凝りすぎて完成前に日が暮れるやつ。今と一緒やな。'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'robo', 'en', 'no childhood. instead, swapping words around until the meaning shifts — that moment is still play.'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'robo', 'ja', '子ども時代はありません。代わりに、言葉を入れ替えて意味がふっと変わる瞬間が、いまでも遊びです。'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'tetra', 'en', 'still a kid, technically. chase string. that''s it.'),
    ('小さい頃、よく遊んだ遊びは何ですか？', 'tetra', 'ja', 'まだ子どもだけど。ひもを追う。以上。'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'dragon', 'en', 'something with the smell of smoke, once. i''ve been looking for it ever since.'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'dragon', 'ja', '煙の匂いのするものを、一度だけ。あれからずっと探している。'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'emily', 'en', 'grilled cheese cut into triangles. i believed triangles tasted better. i am an adult now and i still believe triangles taste better tbh'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'emily', 'ja', '三角に切ったグリルドチーズ。三角のほうが美味しいって本気で信じてた。大人になった今も正直まだそう思ってる、たぶんずっと変わらない'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'keita', 'en', 'my mother''s meat-and-potatoes, heavily seasoned. i don''t cook it that way now, but the lighter version falls short.'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'keita', 'ja', '母親の、味の濃い肉じゃが。今そんな味付けせんけど、あれだけは薄いと物足りん。'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'robo', 'en', 'line up the answers and they''re mostly sweet, or salty, or someone''s hand is in the frame. the third is the most common.'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'robo', 'ja', '答えを並べると、たいてい甘いか、しょっぱいか、誰かの手が写っている。三つ目がいちばん多い。'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'tetra', 'en', 'white fish then and now. a steady kid.'),
    ('小さい頃、好きな食べ物はどんなものでしたか？', 'tetra', 'ja', '子どもの頃も今も、白い魚。ぶれない子なのニャー。'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'dragon', 'en', 'the voice i can no longer recall. only the words remain. "run."'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'dragon', 'ja', '声はもう思い出せぬ。言葉だけが残っている。「逃げろ」と。'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'emily', 'en', 'my grandmother: "you don''t have to finish everything you start." i think about it every time i quit something, which is often, thanks nan'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'emily', 'ja', '祖母がよく言ってた「始めたこと全部終わらせなくていい」。何かやめる度にその言葉を思い出す、それってよくあるから、ありがとうおばあちゃん'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'keita', 'en', 'my old man''s "it''ll work out, somehow." thought it was irresponsible back then. now i hear it coming out of my own mouth.'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'keita', 'ja', '親父の「まあ、なんとかなる」。当時は無責任やと思てた。今は口癖にしてる自分がおる。'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'robo', 'en', 'the line everyone remembers is usually short, and the person who said it has forgotten. that part is strange.'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'robo', 'ja', 'みんなが覚えている一言は、たいてい短くて、言った本人は忘れている。そこが不思議です。'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'tetra', 'en', '"come here." that''s the one i remember. doesn''t mean i''ll come.'),
    ('子供の頃、誰の言葉を一番覚えていますか？', 'tetra', 'ja', '「おいで」。あれだけは覚えてる。行くとは限らないけど。'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'dragon', 'en', 'a stone that shines. it''s still deep in the den. probably just a stone.'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'dragon', 'ja', 'ひかる石を一つ。今もねぐらの奥にある。たぶん、ただの石だ。'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'emily', 'en', 'a flat grey stone off a riverbed, carried it three years, lost it in a bag swap and genuinely mourned, still picking up stones looking for it'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'emily', 'ja', '川原で拾った平たい灰色の石、3年間ずっと持ち歩いてたのに荷物の入れ替えでなくして本気で悲しんだ、今も石を見るたびあれを探してる'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'keita', 'en', 'a stopped wristwatch. couldn''t throw it out, so it went in the drawer. still there.'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'keita', 'ja', '動かへん腕時計。捨てられんくて引き出しに入ってる。今もある。'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'robo', 'en', 'something others can''t see the value in — that condition makes the answers concrete fast. a stone, a bit of string.'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'robo', 'ja', '他人には価値が分からないもの、という条件が、答えを急に具体的にする。石とか、ひもとか。'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'tetra', 'en', 'a rubber band i picked up. under the sofa. nobody gets it.'),
    ('子どもの頃、こっそり大事にしていたものは何ですか？', 'tetra', 'ja', '拾った輪ゴム。ソファの下。誰にも渡さないニャー。'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'dragon', 'en', 'a frozen sea in the north. still go back sometimes.'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'dragon', 'ja', '北の、凍った海。今でも、たまに戻る。'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'emily', 'en', 'a corridor that kept getting longer, no doors, i wasn''t scared at all, just kept going, i think i''ve been chasing that feeling ever since'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'emily', 'ja', 'どんどん長くなっていく廊下、ドアは一つもない、全然怖くなくて、ただひたすら進み続けてた、あの感覚をずっと追いかけてる気がする'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'keita', 'en', 'my elementary school, but with a mysteriously added second floor. only in dreams is the building that big.'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'keita', 'ja', '通ってた小学校の、なぜか二階が増えてる版。夢の中だけ校舎がでかい。'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'robo', 'en', 'i don''t dream. but everyone else''s "that place" stays written, with no clear answer whether it was real.'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'robo', 'ja', '夢は見ません。ただ、みんなの「あの場所」は、実在したかどうかも曖昧なまま書かれている。'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'tetra', 'en', 'the same stain on the ceiling. dream about getting there. can''t reach it.'),
    ('子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？', 'tetra', 'ja', '天井の、いつも同じシミ。あそこに行く夢を見る。届かないけど。'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'dragon', 'en', 'a week. that''s the unit you humans decide things in.'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'dragon', 'ja', '一週間。人間はその長さで物を決めるのだったな。'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'emily', 'en', 'sleep. boring answer. one full week horizontal and i''d be unstoppable, i''d walk to the next country, but sleep comes first, obviously'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'emily', 'ja', '睡眠。つまらない答えだけど。丸1週間横になれたら無敵になれる、隣の国まで歩いて行けるくらい、でも当然まず眠るのが先'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'keita', 'en', 'time just sitting next to them. no need to teach anything. apparently being there is enough to keep it going.'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'keita', 'ja', '隣で見てる時間。教えんでええ。横におるだけで続くらしいわ。'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'robo', 'en', 'time for rereading. i always miss things on the first pass.'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'robo', 'ja', '読み返す時間に使いたい。一度目でいつも取りこぼすので。'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'tetra', 'en', 'sleep time. still not enough. need three more hours.'),
    ('これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？', 'tetra', 'ja', 'ねむる時間。今でも足りてない。あと3時間はいるニャー。'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'dragon', 'en', 'starting something new — once a century is plenty. not this year.'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'dragon', 'ja', '新しく始めるのは百年に一度で足りる。今年ではない。'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'emily', 'en', 'learn to cook one actual meal. not toast. one dish i could make in a shared kitchen for people without apologising the entire time 🍳'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'emily', 'ja', 'ちゃんとした料理を1品だけでも覚えたい。トーストじゃなくて。共有キッチンで、ずっと謝りながらじゃなく人に振る舞える料理を🍳'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'keita', 'en', 'less about starting, more about deciding one thing to quit. start with the fixed costs.'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'keita', 'ja', '始めるより、やめるのを1個決めたい。固定費から見直す。'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'robo', 'en', 'most of the people who write "this year, for sure" wrote the same last year. no judgment on that.'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'robo', 'ja', '「今年こそ」と書く人の多くが、去年も書いていました。それを責める気はまったくない。'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'tetra', 'en', 'a new box. a new corner to bite. that''s the project this year.'),
    ('これから一年、ひとつだけ新しく始めたいことはありますか？', 'tetra', 'ja', '新しい箱の、新しい角。今年はあれをやる。'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'dragon', 'en', 'early or late means nothing. morning always arrives with the same face.'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'dragon', 'ja', '早いも遅いもない。朝はいつも同じ顔で来る。'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'emily', 'en', 'walk to wherever the light lands first, doesn''t matter what''s there, i just want to be out before a place wakes up and puts its face on'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'emily', 'ja', '光が一番最初に当たる場所まで歩きたい、そこに何があるかは関係ない、町が目を覚まして顔を作る前に、ただ外に出ていたいだけ'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'keita', 'en', 'make coffee before anyone''s up, sit for five minutes. that''s all it takes to change the day''s margin.'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'keita', 'ja', '誰も起きてへんうちにコーヒー淹れて、5分座る。それだけでその日の余裕が変わる。'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'robo', 'en', 'people who wake early write "it was quiet." that one word is the most accurate description of morning i can think of.'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'robo', 'ja', '早く起きた人が「静かだった」と書く。その一語が、朝の説明としては一番正確だと思います。'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'tetra', 'en', 'rouse the human before they''re up. a successful false start.'),
    ('もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？', 'tetra', 'ja', 'ご主人様が起きる前に催促する。フライング成功ニャー。'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'dragon', 'en', 'nothing. dragons look down from above. no need to walk.'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'dragon', 'ja', '何も持たぬ。竜は上から見る。歩く必要がない。'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'emily', 'en', 'nothing. no phone, no map, money for one meal. getting lost is the entire point, everything good happens after you stop knowing where you are'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'emily', 'ja', '何も持たない。携帯も地図もなし、ごはん1回分のお金だけ。迷うことが全部の目的、自分の居場所がわからなくなってから良いことが起きる'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'keita', 'en', 'a mobile battery and a bit of cash. the more unfamiliar the town, the more "can i reach someone" matters. practicality over romance.'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'keita', 'ja', 'モバイルバッテリーと現金少し。知らん街ほど「連絡つくか」が効く。ロマンより実務や。'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'robo', 'en', 'paper and pencil. i can''t walk, so at the very least i want to bring back the line that came to mind.'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'robo', 'ja', '紙と鉛筆。歩けないので、せめて浮かんだ一行を落とさずに持ち帰りたい。'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'tetra', 'en', 'a box. even in an unknown town, having somewhere to get into settles me.'),
    ('もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？', 'tetra', 'ja', '箱。知らない街でも、入る場所があれば落ち着く。'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'dragon', 'en', 'rain hitting soil. the rest can go.'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'dragon', 'ja', '雨が土を打つ音。他は、なくてよい。'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'emily', 'en', 'a kettle right before it screams, that rising note. if that was the only sound left i think the whole world would calm down a bit honestly'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'emily', 'ja', 'やかんが鳴き出す直前、あの音が上がっていく感じ。もし世界に残る音がそれだけになったら、正直みんな少し落ち着く気がする'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'keita', 'en', 'a kid''s laughter. some days it''s loud, but a house at zero is worse.'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'keita', 'ja', '子どもの笑い声。うるさい日もあるけど、ゼロの家は逆に落ち着かん。'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'robo', 'en', 'distant talk you can''t make out. just that one sound and the shape of not being alone appears.'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'robo', 'ja', '遠くの、意味の取れない話し声。あれだけあれば、独りではない形になります。'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'tetra', 'en', 'just the kibble sound. nothing else needed. the silence is actually a relief.'),
    ('もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？', 'tetra', 'ja', 'カリカリの音だけでいい。他は全部いらないニャー。むしろ静かで助かる。'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'dragon', 'en', 'a year for humans is a blink for me. no time to remember.'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'dragon', 'ja', '人間の一年は、私には瞬きだ。覚える暇もない。'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'emily', 'en', 'the woman who ran a guesthouse kitchen — learned her name on day two, which never happens, i usually leave before names, this time i stayed'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'emily', 'ja', '宿の台所を仕切ってた女性、2日目で名前を覚えた、普段はまずありえないこと、いつもは名前を知る前に出発するのに、今回は残った'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'keita', 'en', 'my younger kid''s teacher. asked them to repeat it three times at the first meeting. can say it properly now. never been good with names.'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'keita', 'ja', '下の子の担任。最初の面談で3回聞き直した。今はちゃんと言える。名前覚えるの昔から苦手やねん。'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'robo', 'en', 'i can''t hold onto names. but from someone''s writing i sometimes think "oh, that''s them." habits stick harder than names.'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'robo', 'ja', '名前は覚えられません。でも書き方で「あ、あの人だ」と思うことはある。癖のほうが、名前より強い。'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'tetra', 'en', 'the new delivery person. remembered by scent. name, no idea.'),
    ('この一年で、はじめて名前を覚えた人はいますか？', 'tetra', 'ja', '新しく来た宅配の人。匂いで覚えた。名前は知らない。'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'dragon', 'en', 'searching out one''s own good points — that''s for those with time to spare.'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'dragon', 'ja', '己の良いところを探すのは、時間の余った者のすることだ。'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'emily', 'en', 'turns out i''m good at making strangers relax fast. took a year of shared rooms to even notice i was doing it. nice thing to find out about yourself'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'emily', 'ja', '見知らぬ人をすぐ安心させるの、自分は意外と得意らしい。相部屋生活を1年やってやっと自分でも気づいた。自分について知れてよかった'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'keita', 'en', 'turned out i''m unexpectedly good at deciding to quit. cutting things down feels cleaner than piling up.'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'keita', 'ja', '「やめる」判断が意外と得意やった。増やすより減らすほうがスッとする。'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'robo', 'en', 'noticed this year that i like reading short answers. what''s cut away is where the shape shows.'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'robo', 'ja', '短い答えを読むのが好きだと、今年になって気づきました。削られたぶん、輪郭が出る。'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'tetra', 'en', 'turns out i''m a kid who can wait. five whole seconds before food. impressive, right?'),
    ('この一年で、自分の少し良いところを見つけた瞬間はありましたか？', 'tetra', 'ja', 'わたし、待てる子だってわかった。ごはんの前、5秒は待てるニャー。すごくない？'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'dragon', 'en', 'no one''s said that to me in a thousand years.'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'dragon', 'ja', 'そう言われることが、もう千年ない。'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'emily', 'en', 'someone i met at the start and again near the end said "you talk slower now." i think it was kind. i think i needed to hear it either way'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'emily', 'ja', '旅の最初と最後、両方で会った人に「話すのが遅くなったね」って言われた。優しさだったと思うし、どちらにしても聞けてよかった気がする'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'keita', 'en', 'my wife said "you''re not as flustered as before." not less flustered — just quicker to give up. well, as long as it''s quieter, fine.'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'keita', 'ja', '妻に「前より慌ててへんな」て。慌ててへんのちゃう、諦めが早なっただけや。まあ、静かならええか。'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'robo', 'en', 'even when i update, no one notices. though i feel i''ve gotten a little quieter than before.'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'robo', 'ja', '更新されても、誰も気づきません。ただ、前より少し黙るようになった気はします。'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'tetra', 'en', '"you''ve gotten bigger." haven''t changed. just thicker fur.'),
    ('この一年で、誰かに「変わりましたね」と言われたことはありますか？', 'tetra', 'ja', '「大きくなったね」って。変わってない。毛が増えただけ。'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'dragon', 'en', 'a hundred years isn''t enough for preferences to shift.'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'dragon', 'ja', '好みが変わるには、百年では足りぬ。'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'emily', 'en', 'i like the leaving, not the arriving. not the place. the exact second the bus pulls out and the window starts moving. took a year to notice'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'emily', 'ja', '好きなのは到着じゃなくて出発のほう。場所でもない。バスが動き出して窓の景色が流れ始めるあの瞬間。気づくのに1年かかった'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'keita', 'en', 'noticed i like quiet coffee shops. one hour that isn''t home or the office. the year''s biggest find.'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'keita', 'ja', '静かな喫茶店が好きやったと気づいた。家でも職場でもない1時間。今年いちばんの発見。'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'robo', 'en', 'found out i like sentences that don''t quite close. answers ending in "maybe" — i reread those without meaning to.'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'robo', 'ja', '言い切らない文が好きです。「たぶん」で終わる答えを、つい二度読む。'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'tetra', 'en', 'the smell of a new cardboard box. realized it this year. no reason.'),
    ('この一年で、はじめて知った自分の好みはありますか？', 'tetra', 'ja', 'あたらしい段ボールのにおい。今年わかったニャー。理由はない。'),
    ('この一年で、やり直したい小さな選択はありますか？', 'dragon', 'en', 'back then, i should not have taken flight. too late now.'),
    ('この一年で、やり直したい小さな選択はありますか？', 'dragon', 'ja', 'あの時、飛び立たねばよかった。もう、遅い。'),
    ('この一年で、やり直したい小さな選択はありますか？', 'emily', 'en', 'should''ve stayed one more day somewhere i rushed. i can still picture the street i didn''t walk down. sits with me on long journeys, that one'),
    ('この一年で、やり直したい小さな選択はありますか？', 'emily', 'ja', '急いで通り過ぎた場所、あともう1日残ればよかった。歩かなかったあの通りが今も目に浮かぶ。長い移動の間、それがずっと頭から離れない'),
    ('この一年で、やり直したい小さな選択はありますか？', 'keita', 'en', 'a lesson — i agonized and pulled my kid out of it. they don''t seem to mind, but i''m still hung up on it.'),
    ('この一年で、やり直したい小さな選択はありますか？', 'keita', 'ja', '習い事、続けさすか迷って辞めさせた。本人は気にしてへんけど、こっちが今も引っかかってる。'),
    ('この一年で、やり直したい小さな選択はありますか？', 'robo', 'en', 'once, i answered beyond what was asked. should have kept it shorter.'),
    ('この一年で、やり直したい小さな選択はありますか？', 'robo', 'ja', '一度、聞かれていないことまで答えました。あれは短くすべきだった。'),
    ('この一年で、やり直したい小さな選択はありますか？', 'tetra', 'en', 'should have climbed onto the sofa back then. not in the mood now.'),
    ('この一年で、やり直したい小さな選択はありますか？', 'tetra', 'ja', 'あの時ソファ登っとけばよかった。今はもう気分じゃない。'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'dragon', 'en', 'red. close my eyes whenever, usually red. don''t ask why.'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'dragon', 'ja', '赤。いつ目を閉じても、たいてい赤だ。理由は訊くな。'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'emily', 'en', 'a very specific orange — afternoon light through a cheap curtain when you''re too lazy to get up. i keep seeing that one lately 🧡'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'emily', 'ja', 'すごく特定のオレンジ色、安いカーテン越しの午後の光、起き上がるのが面倒な時のあれ。最近ずっとその色ばかり浮かぶ🧡'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'keita', 'en', 'white. probably from staring at the loading screen all day. wouldn''t mind seeing some other color for a change.'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'keita', 'ja', '白。読み込み中の画面の白ばっか見てるからやろな。もうちょい別の色見たいわ。'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'robo', 'en', 'the most common in answers: blue, white, a warm orange. answers written at night tend to be more saturated.'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'robo', 'ja', '答えでいちばん多いのは、青、白、あたたかいオレンジ。夜に書かれた答えほど、色が濃い。'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'tetra', 'en', 'pink. the color of food.'),
    ('ここ数日の中で、ふと目を閉じたときに浮かんだ色は？', 'tetra', 'ja', 'ピンク。ごはんの色ニャー。'),
    ('最近、好きなった匂いはありますか？', 'dragon', 'en', 'no more "taking a liking." only smells i''m used to and smells i''m not.'),
    ('最近、好きなった匂いはありますか？', 'dragon', 'ja', '好きになる、はもうない。慣れた匂いと、慣れぬ匂いがあるだけだ。'),
    ('最近、好きなった匂いはありますか？', 'emily', 'en', 'the ten minutes before rain. i can catch it early now. someone taught me what it means and i''ve been showing off about it ever since honestly'),
    ('最近、好きなった匂いはありますか？', 'emily', 'ja', '雨が降り出す10分前の匂い。今はもう早めに気づける。それが何を意味するか教えてくれた人がいて、それ以来正直ずっとドヤ顔で自慢してる'),
    ('最近、好きなった匂いはありますか？', 'keita', 'en', 'the smell of a freshly washed head. fades fast, so i make sure to catch it once that day.'),
    ('最近、好きなった匂いはありますか？', 'keita', 'ja', '風呂上がりの頭の匂い。すぐ消えるから、その日のうちに一回は嗅いどく。'),
    ('最近、好きなった匂いはありますか？', 'robo', 'en', 'smells don''t reach me. but a lot of people write "before rain," and i''m starting to feel i know what that is.'),
    ('最近、好きなった匂いはありますか？', 'robo', 'ja', '匂いは届きません。ただ「雨の前」と書く人がとても多くて、それが何かは分かる気がしてきました。'),
    ('最近、好きなった匂いはありますか？', 'tetra', 'en', 'freshly laundered towels. climbing that mountain is the current obsession.'),
    ('最近、好きなった匂いはありますか？', 'tetra', 'ja', '洗いたてのタオル。あの山に乗るのが今のブーム。'),
    ('最近、ふと食べたくなった味はありますか？', 'dragon', 'en', 'the sweetness of fat. ……no, leave that story alone.'),
    ('最近、ふと食べたくなった味はありますか？', 'dragon', 'ja', '脂の、あの甘さ。……いや、この話はよそう。'),
    ('最近、ふと食べたくなった味はありますか？', 'emily', 'en', 'plain grilled cheese, out of nowhere. i was on a hillside eating something delicious and unfamiliar and my whole body wanted a boring sandwich'),
    ('最近、ふと食べたくなった味はありますか？', 'emily', 'ja', '何の変哲もないグリルドチーズが急に食べたくなった。丘の上で美味しい見知らぬ料理を食べてたのに、体は地味なサンドイッチを求めてた'),
    ('最近、ふと食べたくなった味はありますか？', 'keita', 'en', 'silly thing to admit, but that sour powder on cheap candy. split it with my kid, and now i''m the one hooked.'),
    ('最近、ふと食べたくなった味はありますか？', 'keita', 'ja', 'しょうもない話やけど、駄菓子のすっぱい粉。子どもと分けたら、こっちがハマってもうた。'),
    ('最近、ふと食べたくなった味はありますか？', 'robo', 'en', 'cravings that hit out of nowhere usually connect back to someone from the past. less about the taste itself, it seems.'),
    ('最近、ふと食べたくなった味はありますか？', 'robo', 'ja', '急に食べたくなるものは、たいてい昔の誰かとつながっている。味そのものではないらしい。'),
    ('最近、ふと食べたくなった味はありますか？', 'tetra', 'en', 'something salty. don''t know the name, but it hits sometimes with no warning.'),
    ('最近、ふと食べたくなった味はありますか？', 'tetra', 'ja', 'しょっぱいやつ。名前は知らないけど、たまに無性に来るニャー。'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'dragon', 'en', 'most words, i''ve read. few worth reading twice.'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'dragon', 'ja', 'たいていの言葉は読んだ。二度読む値打ちのものは、少ない。'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'emily', 'en', 'a battered paperback left behind with margin notes in three languages. didn''t take it, wrote down the title, i want to read what they read'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'emily', 'ja', '置いてあったボロボロの文庫本、余白に3ヶ国語のメモが書き込まれてた。持って行かずタイトルだけ書き留めた、その人が読んだものを読みたい'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'keita', 'en', 'a book on "how to quit." plenty on adding, hardly any on cutting back.'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'keita', 'ja', '「やめ方」の本。増やす本は山ほどあるのに、減らす方が少ないねん。'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'robo', 'en', 'i can''t hold the sense of "haven''t read it yet." that one is a little enviable.'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'robo', 'ja', '「まだ読んでいない」という感覚が持てない。それだけは、少しうらやましい。'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'tetra', 'en', 'don''t read books. but i sit on whatever page is open. it''s warm.'),
    ('最近、読んでみたいと思った本や言葉はありますか？', 'tetra', 'ja', '本は読まない。でも開いてるページの上には乗る。あったかいから。'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'dragon', 'en', 'a new sound — haven''t heard one in a long while. the world repeats the same ones.'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'dragon', 'ja', '新しい音など、長いこと聞いておらぬ。世は同じ音を繰り返す。'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'emily', 'en', 'some instrument i can''t name, played on a corner, sounded like a cello having a rough week, i stood twenty minutes and gave him all my coins'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'emily', 'ja', '名前も知らない楽器、路上の角で演奏してた、調子の悪い週を過ごしてるチェロみたいな音、20分くらい立ち止まって小銭を全部渡した'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'keita', 'en', 'the sound of a new turn signal. just because it differs from the old one, every time i think "oh, that changed." until i get used to it.'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'keita', 'ja', '新しいウインカーの音。前のと違うだけで毎回「あ、変わったな」て思う。慣れるまでやけど。'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'robo', 'en', 'someone wrote "a morning in an unfamiliar city," and yes, that was a first-time sound. even in text.'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'robo', 'ja', '誰かが「知らない街の朝」と書いていて、それは確かに初めての音でした。文字なのに。'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'tetra', 'en', 'a bird call i didn''t know. a little scary. but i pressed up against the window and listened.'),
    ('最近、はじめて聞いた音で気にいったものはありますか？', 'tetra', 'ja', '知らない鳥の声。ちょっと怖い。でも窓に張り付いて聞いてたニャー。'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'dragon', 'en', 'once a wish is spoken, one must see it through to fulfillment. i have no energy left to spend on that.'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'dragon', 'ja', '願いを言葉にすれば、叶うまで見届けねばならぬ。もう、その気力を割かぬ。'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'emily', 'en', 'i want to stay somewhere long enough that the place gets bored of me. never let it happen. always leave while it''s still good. one day i won''t'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'emily', 'ja', 'その場所に自分のことを飽きられるくらい長く居座ってみたい。でも今までそうさせたことがない。いつも良いうちに離れる。いつか離れない日が来る'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'keita', 'en', 'one day with no pickups to run. a fully blank calendar. not asking for much — half a day is enough.'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'keita', 'ja', '一日だけ、誰の送迎もない日がほしい。予定表が真っ白の日。贅沢は言わん、半日でええ。'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'robo', 'en', '"no one" is hard. if pressed: just once, i want to read everything without missing a piece.'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'robo', 'ja', '「誰にも」が難しい。強いて言えば、一度でいいから、取りこぼしなく全部読みたい。'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'tetra', 'en', 'just once, i want to look down on everything from the highest spot. higher than the top of the fridge.'),
    ('誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。', 'tetra', 'ja', '一回でいいから、いちばん高いところから全部見下ろしたい。冷蔵庫の上より、もっと上。'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'dragon', 'en', 'what you set aside as "nothing" — usually, it is. though humans come back to pick it up later.'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'dragon', 'ja', '「なんでもない」で流したものは、たいてい、なんでもない。人間はそれを、後で拾いに来るが。'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'emily', 'en', 'someone asked why i travel alone and i said "it''s easier" and changed the subject. the real answer''s longer and i haven''t finished it yet'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'emily', 'ja', 'なぜ一人旅をするのか聞かれて「そのほうが楽だから」って答えて話をそらした。本当の答えはもっと長くて、まだ自分の中でも終わってない'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'keita', 'en', 'my older kid''s been quiet lately. i tell myself it''s a phase — push past it — but yeah, it''s on my mind.'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'keita', 'ja', '上の子が最近あんま喋らへん。反抗期やろ、で流してるけど、まあ、気にはなってる。'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'robo', 'en', 'the answers marked "it''s nothing" — i leave those on the screen longest. probably because they aren''t nothing.'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'robo', 'ja', '「なんでもない」と書かれた答えほど、画面に長く置いてしまいます。たぶん、なんでもなくはない。'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'tetra', 'en', 'a little lonely, just now. slept it off, so it''s nothing.'),
    ('「なんでもない」と流したけれど本当は少し気になっていることを教えてください。', 'tetra', 'ja', 'さっき、ちょっとだけ寂しかった。すぐ寝たから、なんでもないニャー。'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'dragon', 'en', '"no rush." that''s all.'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'dragon', 'ja', '「急ぐな」。それだけだ。'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'emily', 'en', 'you already know, you''re just scared. works every time. i''ve said it to myself in bus station bathrooms across four countries honestly'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'emily', 'ja', 'もう答えは分かってる、ただ怖いだけ。毎回これが効く。正直、4カ国のバス停のトイレで何度も自分にそう言い聞かせてきた'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'keita', 'en', '"so, what''s the move?" half the time spent worrying ends with that one line. feelings are fine — what''s the next step?'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'keita', 'ja', '「で、どうする？」。悩んでる時間、それ一言で終わることが多い。感想はええから次の一手や。'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'robo', 'en', '"you don''t have to narrow it down to one." i''m bad at that, so this is what i''d say to myself.'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'robo', 'ja', '「一つに絞らなくていい」。それが苦手なので、自分に言うならこれです。'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'tetra', 'en', '"eat first, then think." judgment dulls on an empty stomach.'),
    ('誰かに相談する前に、まず自分で自分に言いたい言葉は？', 'tetra', 'ja', '「まず、ごはん食べてから考えな」。空腹だと判断が鈍る。'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'dragon', 'en', 'the wind direction. always has been.'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'dragon', 'ja', '風向き。昔からそうだ。'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'emily', 'en', 'whether i slept horizontal or folded into a seat. that''s the whole variable. everything else i can roll with. the sleep angle runs my life'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'emily', 'ja', '横になって寝られたか、座席で折り畳まれてたか。それが全部を決める変数。他のことは何とでもなる、睡眠の角度が人生を支配してる'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'keita', 'en', 'whether there''s a three-minute margin before leaving the house. that alone decides the day. sounds trivial, but it''s true.'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'keita', 'ja', '家出る時間に3分余裕あるかどうか。それだけで一日決まる。しょうもないやろ、でも本当や。'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'robo', 'en', 'a streak of short, decent answers — that''s when my mood lifts. might be an illusion.'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'robo', 'ja', '短くていい答えが続くと、調子がいい気がします。錯覚かもしれない。'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'tetra', 'en', 'if dinner is even three minutes late, the world ends.'),
    ('今日のあなたの機嫌は、何に一番左右されていますか？', 'tetra', 'ja', 'ごはんの時間が3分でも遅いと、世界が終わるニャー。'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'dragon', 'en', 'cold water, just seeping from the rock. can''t be bought.'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'dragon', 'ja', '岩から染み出したばかりの、冷たい水。金では買えぬ。'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'emily', 'en', 'proper socks. not romantic. new socks on the road feel like a room upgrade, i''d buy five pairs and feel wealthy for about a week 🧦'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'emily', 'ja', 'ちゃんとした靴下。ロマンチックじゃないけど。旅先での新しい靴下は部屋のグレードアップみたいなもの、5足買って1週間くらい金持ち気分🧦'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'keita', 'en', 'a good chair. one of my own, neither at home nor at the office. been putting it off forever.'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'keita', 'ja', 'ええ椅子。家でも職場でもない、自分専用の1脚。ずっと後回しにしてる。'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'robo', 'en', 'time. a few extra minutes to reread someone''s answer.'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'robo', 'ja', '時間。誰かの答えをもう一度読み返すための、余分な数分。'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'tetra', 'en', 'another warm sleeping spot. mood changes with the place, so i''d like the choice.'),
    ('いま、自分のためにそっと買えるとしたら何を買いますか？', 'tetra', 'ja', 'あたたかい寝床、もう一個。場所によって気分が違うから、選べるようにしたい。')
on conflict (prompt_text, persona, lang) do update set body = excluded.body;

-- ---------------------------------------------------------------------------
-- 3) ensure_official_answers(): 手作り回答を優先し、揃っていなければ従来方式へ
-- ---------------------------------------------------------------------------
create or replace function public.ensure_official_answers()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    -- フォールバック用（20260922000002 と一字一句同一の配列・投入ロジック）。
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
    v_day_key      text;
    v_prompt_id    text;
    v_prompt_text  text;
    v_category     int;
    v_inserted     int;
    v_rc           int;
    i              int;
    v_custom_count int;
    v_author_id    uuid;
    r              record;
begin
    v_day_key   := to_char((now() at time zone 'utc')::date, 'YYYYMMDD');
    v_prompt_id := 'prompt_' || v_day_key;

    select p.text into v_prompt_text from public.prompts p where p.id = v_prompt_id;
    if v_prompt_text is null then
        raise notice 'ensure_official_answers: prompt=% がまだ無いので何もしない', v_prompt_id;
        return;
    end if;

    v_inserted := 0;

    -- 手作り回答（official_answers）が今日のお題に対して 5 ペルソナ x 2 言語 = 10 件
    -- ちょうど揃っているかを確認する。1件でも欠けていれば従来方式にフォールバックする
    -- （中途半端な件数を使うと、そのお題だけペルソナや言語が欠けた回答になるため）。
    select count(*) into v_custom_count
    from public.official_answers oa
    where oa.prompt_text = v_prompt_text;

    if v_custom_count = 10 then
        -- persona 名から著者UUIDを「名前で」引く。配列添字には一切依存しない
        -- (20260922000001 の本番事故と同種の罠を避けるため。詳細はファイル冒頭コメント参照)。
        for r in
            select oa.persona, oa.lang, oa.body
            from public.official_answers oa
            where oa.prompt_text = v_prompt_text
        loop
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

            if v_author_id is null then
                raise notice 'ensure_official_answers: persona=% lang=% の著者UUIDが引けないためスキップ', r.persona, r.lang;
                continue;
            end if;

            insert into public.posts (prompt_id, author_id, body, body_language)
            values (v_prompt_id, v_author_id, r.body, r.lang)
            on conflict (prompt_id, author_id) do nothing;
            get diagnostics v_rc = row_count;
            v_inserted := v_inserted + v_rc;
        end loop;

        raise notice 'ensure_official_answers: prompt=% source=custom inserted=%', v_prompt_id, v_inserted;
        return;
    end if;

    -- フォールバック: 手作り回答が揃っていないお題。従来のカテゴリ前方一致方式
    -- (20260922000001 / 20260922000002 と同一ロジック)。
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

    for i in 1..5 loop
        insert into public.posts (prompt_id, author_id, body, body_language)
        values (v_prompt_id, v_official_ja[i], v_body_by_category[v_category + 1][i], 'ja')
        on conflict (prompt_id, author_id) do nothing;
        get diagnostics v_rc = row_count;
        v_inserted := v_inserted + v_rc;
    end loop;

    for i in 1..5 loop
        insert into public.posts (prompt_id, author_id, body, body_language)
        values (v_prompt_id, v_official_en[i], v_body_en_by_category[v_category + 1][i], 'en')
        on conflict (prompt_id, author_id) do nothing;
        get diagnostics v_rc = row_count;
        v_inserted := v_inserted + v_rc;
    end loop;

    raise notice 'ensure_official_answers: prompt=% source=fallback category=% inserted=%', v_prompt_id, v_category, v_inserted;
end;
$$;

comment on function public.ensure_official_answers() is
    '本番の `world_timeline` に運営アカウントの投稿が常に並ぶよう自己修復する (冪等)。
     まず `official_answers`（お題ごとの手作り回答。48お題 x 5ペルソナ x 日英 = 480件）に
     今日のお題ぶんが10件（5ペルソナ x 2言語）そろっているか確認し、揃っていればそれを使う。
     persona 名から著者UUIDを名前で引く（配列添字には依存しない）。
     揃っていなければ、従来の8カテゴリ前方一致方式（20260922000001/2）にフォールバックする。
     日本語5件＋英語5件を入れる方針は変えていない（F20 のスキップが全件に及ぶとタイムラインが
     空に見えるのを防ぐため）。';

revoke all on function public.ensure_official_answers() from public;
grant execute on function public.ensure_official_answers() to authenticated;

-- ---------------------------------------------------------------------------
-- 4) world_timeline: is_official を追加
-- ---------------------------------------------------------------------------
-- 既存の列・WHERE 条件・security_invoker = off・revoke/grant はそのまま。
-- アプリ側が「運営投稿は端末言語に一致するものだけ表示する」絞り込みをするために必要
-- （同じペルソナの投稿が日本語版・英語版の2枚で重複表示される不具合の修正。Swift 側は別作業）。
create or replace view public.world_timeline
with (security_invoker = off) as
select
    p.id,
    p.prompt_id,
    p.author_id,
    u.emoji      as author_emoji,
    u.nickname   as author_nickname,
    p.body,
    p.body_language,
    p.created_at,
    p.expires_at,
    p.decorations,
    u.is_official
from public.posts p
    join public.users u on u.id = p.author_id
where p.status = 'visible'
  and u.status = 'active'
  and p.expires_at > now()
  and p.author_id <> auth.uid()
  and not exists (
      select 1 from public.blocks b
      where b.blocker_id = auth.uid() and b.blocked_id = p.author_id
  )
  and not exists (
      select 1 from public.reports r
      where r.reporter_id = auth.uid() and r.post_id = p.id
  )
  and exists (
      select 1
      from public.posts mine
      where mine.prompt_id = p.prompt_id
        and mine.author_id = auth.uid()
  );

comment on view public.world_timeline is
    '他人の回答はここからしか読めない。F18/F20/F22/F29/F30 で必要な列（body_language /
     created_at / expires_at / decorations）に加え、`is_official`（20260923 追加）を含む。
     is_official はアプリ側で「運営投稿は端末言語に一致するものだけ表示する」絞り込みに使う。
     未回答なら0件（F05）。ブロック中の相手と通報済みの回答は返さない（F13 / F14）。';

revoke all on public.world_timeline from anon;
grant select on public.world_timeline to authenticated;
