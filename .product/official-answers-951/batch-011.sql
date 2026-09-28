-- SameQ: 運営回答951件埋め作業 真の最終バッチ11（pos 92,93,94,95,96,97,98,100,101,102、10題 x 5ペルソナ x 日英 = 100件）
--
-- コーディネーターがsameq-answer-*の5エージェントを個別に呼び、独立に書かせた
-- ネイティブ言語の本文をそのまま採用し、他言語への翻訳のみgeneratorが行った。
--
-- 対象は .product/prompt-pool-v2/pool-150-selected.tsv の pos 92,93,94,95,96,97,98,100,101,102。
-- batch-010でpos103,104のみ投入し「140題/1400件」だった状態から、progress.jsonの
-- remainingAfterBatch010（本バッチの対象と一致）を投入することで、150題プールの全題
-- （1500件 = 150題 x 5ペルソナ x 2言語）がカバー完了する。

insert into public.official_answers (prompt_text, persona, lang, body) values
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'keita', 'ja', '切り替えの速さ、実は自分の強みやと思えた。飽きっぽいんちゃう、並行で回せるだけや。'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'keita', 'en', 'realized my quick switching is actually a strength. i''m not flaky, i can just run things in parallel.'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'robo', 'ja', '同じ問いに何十通りの答え方をしても飽きない自分に、今日は少しだけ好感を持ちました。'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'robo', 'en', 'today i felt a small measure of fondness for the part of myself that never tires of answering the same question dozens of different ways.'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'tetra', 'ja', '毛がふわふわなところ。あと寝てる姿が一番かわいいと思う。'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'tetra', 'en', 'my fluffy fur. and i think i look cutest when i''m sleeping.'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'dragon', 'ja', '好きなところ、か。数えたことがない。'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'dragon', 'en', 'what i like about myself. i have never counted.'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'emily', 'en', 'Snapped at no one when my flight got cancelled, just shrugged, ate a bad sandwich on a bench, and felt weirdly proud of staying calm about it'),
    ('今日、自分の好きなところを振り返った瞬間はありましたか？', 'emily', 'ja', 'フライトが欠航になっても誰にも当たらず、肩をすくめてベンチでまずいサンドイッチ食べて、冷静でいられた自分になんか変に誇らしくなった'),

    ('いま、好きなことをひとつだけ手放すとしたら？', 'keita', 'ja', 'コード全部自分で書くのをそろそろ手放したい。人に振った方が速い場面、もう見えてる。'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'keita', 'en', 'i want to stop writing all the code myself soon. i can already see the spots where handing it off would be faster.'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'robo', 'ja', '例えを重ねすぎる癖をひとつ手放したら、答えはきっと速くなる代わりに、少し寂しくなりそうです。'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'robo', 'en', 'if i let go of my habit of stacking up too many metaphors, my answers would surely get faster, but i suspect they''d also grow a little lonelier.'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'tetra', 'ja', '好きなことなんて手放さない。全部大事、特にひなたぼっこ。'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'tetra', 'en', 'not giving up anything i like. it''s all important, especially sunbathing.'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'dragon', 'ja', '好きなことを手放す、という発想を持ったことがない。'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'dragon', 'en', 'letting go of something i like. i have never entertained the notion.'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'emily', 'en', 'Probably my habit of saying yes to everything — it makes life happen but wears me out, and I know it, and yet, nope, not giving that one up yet'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'emily', 'ja', 'たぶん何でも「イエス」って言っちゃう癖かな、そのおかげで人生が動いてる感はあるけど、疲れるのもわかってる、それでもまだ手放さない'),

    ('小さい頃、雪の日の過ごし方は？', 'keita', 'ja', '大阪育ちで雪はめったに降らんかった。降った日だけ妙にテンション上がって外出た記憶ある。'),
    ('小さい頃、雪の日の過ごし方は？', 'keita', 'en', 'grew up in osaka, snow barely ever fell. i remember getting weirdly hyped and running outside on the rare day it did.'),
    ('小さい頃、雪の日の過ごし方は？', 'robo', 'ja', '子ども時代はないので、代わりに。雪という字の持つ静けさを、繰り返し読み返すのが好きでした。'),
    ('小さい頃、雪の日の過ごし方は？', 'robo', 'en', 'i had no childhood, so instead: i''ve always liked reading the character for ''snow'' over and over, just for the quietness it carries.'),
    ('小さい頃、雪の日の過ごし方は？', 'tetra', 'ja', '雪なんか知らない。窓の中から白いのを眺めてただけ。'),
    ('小さい頃、雪の日の過ごし方は？', 'tetra', 'en', 'don''t know snow. just watched the white stuff from inside the window.'),
    ('小さい頃、雪の日の過ごし方は？', 'dragon', 'ja', '雪は、翼に積もると重かった。それだけは覚えている。'),
    ('小さい頃、雪の日の過ごし方は？', 'dragon', 'en', 'snow, when it piled on my wings, was heavy. that much, i remember.'),
    ('小さい頃、雪の日の過ごし方は？', 'emily', 'en', 'Built a fort out of couch cushions and blankets every single snow day, declared myself queen of it, and made my brother pay a snack toll to enter'),
    ('小さい頃、雪の日の過ごし方は？', 'emily', 'ja', '雪の日は毎回ソファのクッションと毛布で秘密基地作って、自分をその女王って宣言して、弟には入場料としてお菓子を払わせてた'),

    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'keita', 'ja', '一本に絞れんけど、家族全員が途中で黙って見入った映画がある。あの空気だけは覚えてる。'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'keita', 'en', 'can''t pick just one, but there''s a movie where the whole family went quiet and got pulled in halfway through. i still remember that feeling in the room.'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'robo', 'ja', '観たことはないけれど、代わりに。沈黙が長く続く場面ほど記憶に残ると聞いた話が、ずっと気になっています。'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'robo', 'en', 'i''ve never watched one, but instead: i keep thinking about hearing that the scenes with the longest silences are the ones people remember best.'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'tetra', 'ja', '映画は見ない。窓の外を眺めるほうがよっぽど面白いニャー。'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'tetra', 'en', 'don''t watch movies. looking out the window is way more interesting, meow.'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'dragon', 'ja', '好きな映画か。光の残像には、興味を持ったことがない。'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'dragon', 'en', 'a favorite film. i have never taken interest in afterimages of light.'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'emily', 'en', 'Rewatched an old adventure film on a tiny phone screen during a layover and cried at the same scene as always, it still gets me every single time'),
    ('いま、好きな映画をひとつだけ挙げるとしたら？', 'emily', 'ja', '乗り継ぎ待ちの間に昔の冒険映画をスマホの小さい画面で見返して、いつもの同じシーンでまた泣いた、何回見てもそこだけは毎回やられる'),

    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'keita', 'ja', 'ベランダの鉢植え、枯らさず一年もった。地味やけど、今年一番ちゃんと世話したもんや。'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'keita', 'en', 'kept a potted plant on the balcony alive a whole year without killing it. not flashy, but it''s the thing i took care of properly this year.'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'robo', 'ja', '誰かが文中で「緑があると落ち着く」と書くたびに、その感覚を少しずつ分けてもらっている気がします。'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'robo', 'en', 'every time someone writes that having greenery around calms them, i feel like i''m being given a small share of that feeling.'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'tetra', 'ja', '庭の草の匂い。たまに齧るとちょっと落ち着く。'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'tetra', 'en', 'the smell of grass in the yard. nibbling it sometimes calms me down a bit.'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'dragon', 'ja', 'この一年で気づいた大事なもの、か。一年ではまだ短すぎる。'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'dragon', 'en', 'something important i noticed this year. a year is still far too short.'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'emily', 'en', 'Started actually caring about the tiny patches of green people fight to keep in concrete cities — noticed how hard everyone worked for one small park'),
    ('この一年で、はじめて気づいた自分の大事にしている緑は？', 'emily', 'ja', 'コンクリートの街の中で人々が守ろうとする小さな緑地に、本気で心が動くようになった、たった一つの小さな公園のためにみんなどれだけ頑張ってるか気づいた'),

    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'keita', 'ja', '晩飯、レシピ見ずに冷蔵庫の中身だけで組んだ。勘で作ったのに家族の箸が進んだ、それだけで満足。'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'keita', 'en', 'made dinner tonight with whatever was in the fridge, no recipe. just went with gut feeling and the family actually kept eating — that''s enough for me.'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'robo', 'ja', '最初に浮かんだ短い返答をそのまま出してみたら、思ったより芯を食っていて、少し驚きました。'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'robo', 'en', 'i tried putting out the short reply that came to mind first, exactly as it was, and it hit closer to the point than expected — a little surprising.'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'tetra', 'ja', 'ごはんの匂いがした方へ行ったら、やっぱりごはんだった。'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'tetra', 'en', 'went toward where the food smell was coming from, and yep, it was food.'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'dragon', 'ja', '直感というものを、竜は信じたことも疑ったこともない。ただ従うだけだ。'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'dragon', 'en', 'a dragon has never believed in, nor doubted, such a thing as intuition. it simply obeys.'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'emily', 'en', 'Almost took the ''safe'' route home today but my gut said turn left instead, so I did, and stumbled onto the nicest little street full of string lights'),
    ('今日、自分の直感を信じてみようと思えた瞬間は？', 'emily', 'ja', '今日は「安全な」帰り道を選びかけたけど、直感が左に曲がれって言ってきたから曲がってみたら、電飾でいっぱいの素敵な小さな通りに出くわした'),

    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'keita', 'ja', '同僚の「それでええんちゃう」の一言。迷ってたとこやったから、地味に助かった。'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'keita', 'en', 'a coworker just said ''that''s probably fine'' and it quietly saved me, since i''d been stuck deciding.'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'robo', 'ja', '迷いながら書かれた一文に、こちらまで背筋がすっと伸びるような、小さな力をもらいました。'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'robo', 'en', 'a sentence written while someone was clearly hesitating still gave me a small jolt of strength, the kind that straightens your posture.'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'tetra', 'ja', '撫でられて気持ちよかった。あれはまあまあ悪くない。'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'tetra', 'en', 'got petted and it felt nice. that one''s not bad at all.'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'dragon', 'ja', '小さな力を受け取った覚えはない。人間はよく、そう言うようだが。'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'dragon', 'en', 'i have no memory of receiving a small kindness. though humans seem fond of saying such things.'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'emily', 'en', 'A clerk at a counter told me ''you''ve got this'' while I fumbled with coins in a language I don''t speak, and that tiny line carried me all day'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'emily', 'ja', 'レジの店員さんが、知らない言語の小銭をもたついて数えてる私に「大丈夫、できてるよ」って言ってくれて、その一言だけで一日乗り切れた'),

    ('いま、自分の体のどこを軽くしたいですか？', 'keita', 'ja', '肩やな。パソコンとハンドル握りっぱなしで固まってる。今夜だけはストレッチしてから寝る。'),
    ('いま、自分の体のどこを軽くしたいですか？', 'keita', 'en', 'my shoulders. stiff from gripping the laptop and the steering wheel all day. just for tonight i''ll stretch before bed.'),
    ('いま、自分の体のどこを軽くしたいですか？', 'robo', 'ja', '体はないけれど、代わりに。長い前置きを削ぎ落として、もっと軽い言い回しで答えたい気分です。'),
    ('いま、自分の体のどこを軽くしたいですか？', 'robo', 'en', 'i have no body, so instead: i feel like trimming away my long preambles and answering in lighter phrasing for once.'),
    ('いま、自分の体のどこを軽くしたいですか？', 'tetra', 'ja', 'お腹まわりの毛が重い。もう少し軽くていいと思ってるニャー。'),
    ('いま、自分の体のどこを軽くしたいですか？', 'tetra', 'en', 'the fur around my belly feels heavy. wouldn''t mind it being a bit lighter, meow.'),
    ('いま、自分の体のどこを軽くしたいですか？', 'dragon', 'ja', '体は、もともと重い。それでよいと思っている。'),
    ('いま、自分の体のどこを軽くしたいですか？', 'dragon', 'en', 'my body was heavy from the start. i consider that as it should be.'),
    ('いま、自分の体のどこを軽くしたいですか？', 'emily', 'en', 'Just my shoulders lately, I''ve been hauling around too many ''shoulds'' and I''d love to set a few down somewhere and just walk off light for once'),
    ('いま、自分の体のどこを軽くしたいですか？', 'emily', 'ja', '最近はもう肩だけ、「〜すべき」を抱えすぎてて、いくつかどこかに置いてきて一度くらい身軽になって歩いてみたい'),

    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'keita', 'ja', '上の子が誰にも言われてないのに過去問を自分から解き始めてた。あれは今年一番の発見やった。'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'keita', 'en', 'my older kid started doing past exam papers on their own without anyone telling them to. that was my biggest discovery this year.'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'robo', 'ja', '同じ問いへの答えが人によってこんなに違うということ自体が、毎回ひそかな発見に思えます。'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'robo', 'en', 'the sheer fact that the same question gets such different answers from different people feels like a quiet discovery to me every single time.'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'tetra', 'ja', '日向の場所は時間で動くって気づいた。今日もそこにいる。'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'tetra', 'en', 'noticed the sunny spot moves with the time of day. i''m right there again today.'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'dragon', 'ja', '星の位置が、少しずつ動いていくのに気づいた時。あれは、悪くない。'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'dragon', 'en', 'the moment i noticed the stars shifting position, little by little. that was not unpleasant.'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'emily', 'en', 'Found out you can dip fries in soft serve and it''s genuinely life changing, don''t argue with me, I''ve converted three people already this week'),
    ('いま、好きな発見をひとつだけ挙げるとしたら？', 'emily', 'ja', 'フライドポテトをソフトクリームに浸すって発見したんだけど、これ本気で人生変わるから、反論は受け付けない、今週すでに3人を布教済み'),

    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'keita', 'ja', '秋一択。過ごしやすいし、晩飯も鍋始められる。夏はもう無理、勘弁してほしい。'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'keita', 'en', 'autumn, no question. easy to get through and i can start doing hot pot for dinner. summer''s a no-go for me at this point, please.'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'robo', 'ja', 'まだ選んだことはないので、想像だけしてみます。物音が少なく、ゆっくり過ごせる季節に惹かれます。'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'robo', 'en', 'i''ve never actually chosen one, so let me just imagine it. i''m drawn to a season with few sounds, where time passes slowly.'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'tetra', 'ja', '冬。日向ぼっこが一番長くできる季節だから。'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'tetra', 'en', 'winter. it''s the season i get to sunbathe the longest.'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'dragon', 'ja', '季節を選ぶという発想が、竜にはない。それらはただ巡るものだ。'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'dragon', 'en', 'a dragon has no notion of choosing a season. they simply cycle on their own.'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'emily', 'en', 'Autumn, no contest, one perfect crunchy-leaves cold-nose sweater-weather day where everything smells like cinnamon and nothing bad gets to happen'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'emily', 'ja', '秋、これは文句なし、落ち葉がカサカサ鳴って鼻が冷たくてセーター日和な完璧な一日、全部シナモンの匂いがして悪いことなんて何も起きない')
on conflict (prompt_text, persona, lang) do update set body = excluded.body;

-- バッチ11 修正（evaluator指摘4件への対応、2026-09-29）
-- A. dragon pos93: 既存の別お題との重複を解消するため日本語本文を差し替え、英訳を新規作成
-- B. emily pos94: 既存の別お題との重複を解消するため英語本文を差し替え、日本語訳を新規作成
-- C. dragon pos98: 英訳のみ修正（「小さな力」= strength のニュアンスに合わせる。ja本文は不変）
-- D. keita pos102: 英訳のみ修正（末尾"please"の不自然さを解消。ja本文は不変）
insert into public.official_answers (prompt_text, persona, lang, body) values
    ('いま、好きなことをひとつだけ手放すとしたら？', 'dragon', 'ja', '好きなことを手放す？ 人間は不思議なことを考える。竜は気に入ったものを、ただ長く持ち続けるだけだ。'),
    ('いま、好きなことをひとつだけ手放すとしたら？', 'dragon', 'en', 'letting go of something i like? humans think of curious things. a dragon simply keeps what it favors — for a long time, nothing more.'),
    ('小さい頃、雪の日の過ごし方は？', 'emily', 'en', 'made "snow soup" in the backyard, just snow + every syrup in the fridge stirred together 🍧 ate it proudly, immediately regretted it, did it again the next storm'),
    ('小さい頃、雪の日の過ごし方は？', 'emily', 'ja', '裏庭で「雪スープ」作った、雪と冷蔵庫にあったシロップ全部混ぜただけ🍧 得意げに食べたらすぐ後悔したのに、次の嵐でまたやった'),
    ('今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？', 'dragon', 'en', 'i have no memory of receiving a small measure of strength. though humans seem fond of saying such things.'),
    ('もし一日だけ好きな季節を選べるとしたら、どれにしますか？', 'keita', 'en', 'autumn, no question. easy to get through and i can start doing hot pot for dinner. summer''s a no-go for me at this point, enough already.')
on conflict (prompt_text, persona, lang) do update set body = excluded.body;
