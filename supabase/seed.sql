-- SameQ スプリント01 のシードデータ
--
-- アプリに同梱している SameQ/Resources/SeedData.json と同じ内容。
-- 世界タイムラインの検証には自分以外の回答が最低10件必要なので、14件用意している。
-- お題の有効期間は 28 時間（置いた前提 2）。

insert into public.prompts (id, text, starts_at, ends_at)
values ('prompt_001', '今日、思わず笑ってしまったことは何ですか？', now() - interval '6 hours', now() + interval '22 hours')
on conflict (id) do nothing;

insert into public.users (id, emoji, nickname, created_at) values
    ('F71DC8ED-6519-4F76-9CBD-0ED21889C3C5', '🌙', 'みずき', now() - interval '78 minutes'),
    ('1E56339E-92A5-481A-923D-72C2048CF18C', '🐢', null, now() - interval '94 minutes'),
    ('D1F6A20F-3CCA-48EF-B1A1-7EE9EC475569', '🌵', 'Lucía', now() - interval '111 minutes'),
    ('DEB10675-152C-4EA7-B9F6-1684C5E49CA0', '🍞', '지훈', now() - interval '132 minutes'),
    ('EC0C5044-8484-4369-BA3C-6FAB0E3D1543', '🎈', null, now() - interval '156 minutes'),
    ('95E0E393-C330-4639-889E-DDBC686DAAD3', '🐳', 'Tom', now() - interval '170 minutes'),
    ('408AB191-43F1-4F41-9845-818F89524F68', '☕️', null, now() - interval '193 minutes'),
    ('2F41AE07-4030-47A2-BCE8-110E70798E01', '🌻', 'Ana', now() - interval '218 minutes'),
    ('76755DE6-E6BF-4DCC-BE5D-804276B60AF0', '🛴', 'Jonas', now() - interval '241 minutes'),
    ('FDCBC9EE-01C9-4599-B004-2D7F934B060C', '🍊', null, now() - interval '264 minutes'),
    ('B01B1C76-66B1-476B-B073-984FD13A8E1D', '🪐', 'Noor', now() - interval '287 minutes'),
    ('E9F93D4F-6A9F-45E3-9553-D242D147CD6D', '🐧', 'さとる', now() - interval '309 minutes'),
    ('6EC6D09C-ECAC-4098-AB8B-69A467BF112A', '🎧', 'Marek', now() - interval '331 minutes'),
    ('735F5078-2552-4844-AD91-B3B6D8753E9A', '🍄', null, now() - interval '354 minutes')
on conflict (id) do nothing;

insert into public.posts (id, prompt_id, author_id, body, body_language, created_at, expires_at) values
    ('A27331CF-683D-46E7-84FE-00FD8A513A16', 'prompt_001', 'F71DC8ED-6519-4F76-9CBD-0ED21889C3C5', '電車で寝てる人が、急にはっきりした声で「それは違うと思います」って言った。誰と話してたんやろ。', 'ja', now() - interval '18 minutes', now() + interval '22 hours'),
    ('A08195C4-4A4C-40BD-91BE-159E77C57C7A', 'prompt_001', '1E56339E-92A5-481A-923D-72C2048CF18C', 'My cat tried to jump onto the table, missed completely, and then walked away like nothing had happened.', 'en', now() - interval '34 minutes', now() + interval '22 hours'),
    ('2735683A-A8DB-4324-ADAD-2DC7C452EA41', 'prompt_001', 'D1F6A20F-3CCA-48EF-B1A1-7EE9EC475569', 'Mi abuela me llamó para preguntarme cómo se apaga la televisión. Estaba usando el mando del aire acondicionado.', 'es', now() - interval '51 minutes', now() + interval '22 hours'),
    ('9CCC14F0-732F-43F5-AE71-D050A5C23277', 'prompt_001', 'DEB10675-152C-4EA7-B9F6-1684C5E49CA0', '출근길에 신발을 짝짝이로 신고 온 걸 회사에 도착해서야 알았다.', 'ko', now() - interval '72 minutes', now() + interval '22 hours'),
    ('E2525BE9-953E-423B-951C-FFF1BA154FD1', 'prompt_001', 'EC0C5044-8484-4369-BA3C-6FAB0E3D1543', 'Mon voisin chante faux tous les matins sous la douche. Aujourd''hui il a oublié les paroles.', 'fr', now() - interval '96 minutes', now() + interval '22 hours'),
    ('9546FA31-6696-4814-8504-BC82D4D7B43D', 'prompt_001', '95E0E393-C330-4639-889E-DDBC686DAAD3', 'I said "you too" to the waiter who told me to enjoy my meal. Every single time.', 'en', now() - interval '110 minutes', now() + interval '22 hours'),
    ('39A70445-7D02-4EAC-BAD6-76A1FCF46CEE', 'prompt_001', '408AB191-43F1-4F41-9845-818F89524F68', '自販機で買ったつもりのコーヒーが、全然違うボタンのやつだった。まあ美味しかったからよし。', 'ja', now() - interval '133 minutes', now() + interval '22 hours'),
    ('163D8D7F-C874-45DD-B512-4F75201243D8', 'prompt_001', '2F41AE07-4030-47A2-BCE8-110E70798E01', 'Meu filho de três anos me apresentou o seu "melhor amigo": uma pedra.', 'pt', now() - interval '158 minutes', now() + interval '22 hours'),
    ('1BB1C854-3541-45D7-841D-EBD5202663E7', 'prompt_001', '76755DE6-E6BF-4DCC-BE5D-804276B60AF0', 'Ich habe zehn Minuten lang meine Brille gesucht. Sie war die ganze Zeit auf meinem Kopf.', 'de', now() - interval '181 minutes', now() + interval '22 hours'),
    ('A972D1B0-E8A3-4A09-8DDC-4B7A0E9A2384', 'prompt_001', 'FDCBC9EE-01C9-4599-B004-2D7F934B060C', '同事把「辛苦了」打成了「幸福了」，整个群突然安静，然后大家都笑了。', 'zh', now() - interval '204 minutes', now() + interval '22 hours'),
    ('396EE953-5D2D-4030-8BC3-F4E8A57835FE', 'prompt_001', 'B01B1C76-66B1-476B-B073-984FD13A8E1D', 'حاولت أن أفتح باب المتجر وأنا أدفعه ثلاث مرات، وكان مكتوباً عليه بخط كبير: اسحب.', 'ar', now() - interval '227 minutes', now() + interval '22 hours'),
    ('D867EBF2-BB8B-449F-81DB-767DF6D2D2FC', 'prompt_001', 'E9F93D4F-6A9F-45E3-9553-D242D147CD6D', '犬が自分のしっぽに驚いてた。毎日同じことしてるのに、毎日はじめてみたいな顔をする。', 'ja', now() - interval '249 minutes', now() + interval '22 hours'),
    ('8D4774DE-5140-47AE-8CBA-CA7FC03B8995', 'prompt_001', '6EC6D09C-ECAC-4098-AB8B-69A467BF112A', 'Pomyliłem szampon z żelem pod prysznic. Włosy pachną cytryną, ale wyglądają dobrze.', 'pl', now() - interval '271 minutes', now() + interval '22 hours'),
    ('27D12B43-097B-417E-AFD9-8BF33ADE17FA', 'prompt_001', '735F5078-2552-4844-AD91-B3B6D8753E9A', 'My grandpa found out what a meme is today. He now sends me one every hour, and none of them make sense.', 'en', now() - interval '294 minutes', now() + interval '22 hours')
on conflict (id) do nothing;
