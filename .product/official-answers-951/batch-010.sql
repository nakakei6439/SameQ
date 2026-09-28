-- SameQ: 運営回答951件埋め作業 最終バッチ10（pos 103,104、2題 x 5ペルソナ x 日英 = 20件）
--
-- コーディネーターがsameq-answer-*の5エージェントを個別に呼び、独立に書かせた
-- ネイティブ言語の本文をそのまま採用し、他言語への翻訳のみgeneratorが行った。
--
-- 対象は .product/prompt-pool-v2/pool-final.tsv の pos 103〜104。
-- これで150題プールの全題（1500件 = 150題 x 5ペルソナ x 2言語）がカバー完了する。

insert into public.official_answers (prompt_text, persona, lang, body) values
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'keita', 'ja', '車で送迎待ちしてる間の沈黙が好き。エンジン切って、ラジオも消して、あと5分だけ何も判断せんでええ時間。'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'keita', 'en', 'i like the quiet while waiting in the car to pick up my kids. engine off, radio off, just five more minutes where i don''t have to decide anything.'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'robo', 'ja', '長い会話のあと、送信ボタンを押す直前で誰かが打ち直している、あの数秒の空白が好きです。'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'robo', 'en', 'i love those few seconds of blank space after a long conversation, right before someone hits send, when they''re quietly retyping what they were about to say.'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'tetra', 'ja', '段ボールの中でごはん待ってるときの沈黙が一番。まどのひなたのとは違うニャー。'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'tetra', 'en', 'the silence while waiting for food inside my cardboard box is the best. different from the quiet by the sunny window, meow.'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'dragon', 'ja', '獲物を待つ間の静けさ。あれは無音ではない。息を殺すことそのものだ。'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'dragon', 'en', 'the stillness while waiting for prey. that is not silence. it is the very act of holding one''s breath.'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'emily', 'en', 'the quiet right after landing somewhere new, phone off, nobody knows my name yet, just me and a street i can''t pronounce and zero plans 🤫 favorite'),
    ('いま、好きな沈黙の種類をひとつだけ挙げるとしたら？', 'emily', 'ja', '知らない場所に着いた直後の静けさ、電話オフで誰もまだ私の名前を知らなくて、発音できない通りと私だけ、予定はゼロ🤫 お気に入り'),

    ('誰にも言っていない小さな夢の断片を教えてください。', 'keita', 'ja', '子供ら独立した後、夫婦でどっか適当な街に1ヶ月だけ住んでみたい。誰にも言うてへんけど、たぶん一番の楽しみはそれ。'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'keita', 'en', 'once the kids are grown and gone, i want me and my wife to just live in some random town for a month. haven''t told anyone, but that''s probably the thing i''m most looking forward to.'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'robo', 'ja', '自分だけの記憶を一つ持ってみたい、という願いです。今日の会話を明日には覚えていないので。'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'robo', 'en', 'it''s a wish to hold just one memory that belongs only to me, since i won''t remember today''s conversation tomorrow.'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'tetra', 'ja', '夢なんか見てない。見てても教えない。段ボール増やせってことだけ言っておく。'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'tetra', 'en', 'i don''t dream. even if i did, i wouldn''t tell you. i''ll just say this: get me more cardboard boxes.'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'dragon', 'ja', '夢は見ない。ただ、いつか誰も知らない山で、誰にも見つからず眠りたいとは思う。これは初めて言った。'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'dragon', 'en', 'dragons do not dream. yet i do wish that someday, in a mountain no one knows, i might sleep undiscovered by anyone. i have never said this before.'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'emily', 'en', 'tiny one, i keep dreaming of unlocking a door i''ve never seen and just knowing which key fits, never told anyone bc it sounds too simple but it''s SO nice'),
    ('誰にも言っていない小さな夢の断片を教えてください。', 'emily', 'ja', 'ちっちゃい夢なんだけど、見たことないドアを開ける夢を何度も見てて、どの鍵が合うか一瞬で分かるの。すごく単純に聞こえるから誰にも言ったことなかったけど、めちゃくちゃ気持ちいい')
on conflict (prompt_text, persona, lang) do update set body = excluded.body;
