-- SameQ シードデータ（スプリント03時点）
--
-- アプリに同梱している SameQ/Resources/SeedData.json と同じ内容。
-- お題の有効期間は28時間・常に1つだけ有効（置いた前提2・3）。
-- 投稿の表示期限（expires_at）は所属するお題の終了時刻に揃える（F10）。
-- 世界タイムラインの検証には「20件あるとき20回スワイプして重複しない」ことの確認が要るので、
-- prompt_001 には22件用意している（F11 / F12）。
--
-- 注意: このファイルは生成物ではなく手書き相当だが、SeedData.json と1対1で対応させること。

insert into public.prompts (id, text, starts_at, ends_at) values
    ('prompt_001', '今日、思わず笑ってしまったことは何ですか？', now() - interval '2 hours', now() + interval '26 hours'),
    ('prompt_002', '最近、誰かに言われてうれしかった一言は何ですか？', now() + interval '26 hours', now() + interval '54 hours')
on conflict (id) do nothing;

insert into public.users (id, emoji, nickname, created_at) values
    ('F71DC8ED-6519-4F76-9CBD-0ED21889C3C5', '🌙', 'みずき', now() - interval '78 minutes'),
    ('1E56339E-92A5-481A-923D-72C2048CF18C', '🐢', null, now() - interval '95 minutes'),
    ('D1F6A20F-3CCA-48EF-B1A1-7EE9EC475569', '🌵', 'Lucía', now() - interval '112 minutes'),
    ('DEB10675-152C-4EA7-B9F6-1684C5E49CA0', '🍞', '지훈', now() - interval '129 minutes'),
    ('EC0C5044-8484-4369-BA3C-6FAB0E3D1543', '🎈', null, now() - interval '146 minutes'),
    ('95E0E393-C330-4639-889E-DDBC686DAAD3', '🐳', 'Tom', now() - interval '163 minutes'),
    ('408AB191-43F1-4F41-9845-818F89524F68', '☕️', null, now() - interval '180 minutes'),
    ('2F41AE07-4030-47A2-BCE8-110E70798E01', '🌻', 'Ana', now() - interval '197 minutes'),
    ('76755DE6-E6BF-4DCC-BE5D-804276B60AF0', '🛴', 'Jonas', now() - interval '214 minutes'),
    ('FDCBC9EE-01C9-4599-B004-2D7F934B060C', '🍊', null, now() - interval '231 minutes'),
    ('B01B1C76-66B1-476B-B073-984FD13A8E1D', '🪐', 'Noor', now() - interval '248 minutes'),
    ('E9F93D4F-6A9F-45E3-9553-D242D147CD6D', '🐧', 'さとる', now() - interval '265 minutes'),
    ('6EC6D09C-ECAC-4098-AB8B-69A467BF112A', '🎧', 'Marek', now() - interval '282 minutes'),
    ('735F5078-2552-4844-AD91-B3B6D8753E9A', '🍄', null, now() - interval '299 minutes'),
    ('ACCB549C-C91B-44C0-9D96-1B56288514E2', '🌿', 'はるか', now() - interval '316 minutes'),
    ('E63C7BC7-7EA4-4B0C-BEE5-A34FFE01F310', '🧦', null, now() - interval '333 minutes'),
    ('95B19169-409E-4C34-A0C6-D74ACDC61C3F', '🍋', '서연', now() - interval '350 minutes'),
    ('53AEED3B-B0AF-42B3-B213-27E6906015B7', '🌊', 'Mateo', now() - interval '367 minutes'),
    ('B1B6C79D-F7FD-46A5-B72A-B1D26E579417', '🎹', null, now() - interval '384 minutes'),
    ('6705289F-4F47-42F9-8622-27299566FE47', '🧶', 'Elke', now() - interval '401 minutes'),
    ('8DD02152-4A1D-4891-B5DF-F0FD89E8E741', '🥚', 'Rafa', now() - interval '418 minutes'),
    ('74E85C2A-305D-47DD-91BB-00231C11A004', '🐿️', null, now() - interval '435 minutes'),
    ('C712DA6A-92DC-474A-970A-A79E7FE6224D', '🌙', 'Layla', now() - interval '452 minutes'),
    ('A51AB2CE-A716-4D27-96CA-B9F1DFB4B9C7', '🍅', 'Giulia', now() - interval '469 minutes'),
    ('63DA91C8-F2C6-4EA3-80DA-0E8F81F3976B', '🛶', null, now() - interval '486 minutes'),
    ('0B679032-24AC-47EE-A5C0-1475AC49291F', '📚', 'Sam', now() - interval '503 minutes'),
    ('B8F0C2D3-4E56-4A78-9B0C-1D2E3F405162', '🧦', 'Elif', now() - interval '503 minutes'),
    ('C9E1D3E4-5F67-4B89-8C1D-2E3F40516273', '🫖', null, now() - interval '520 minutes'),
    ('D0F2E4F5-6078-4C90-9D2E-3F4051627384', '🌿', 'Sanne', now() - interval '537 minutes'),
    ('E1030506-7189-4D01-8E3F-405162738495', '🪁', 'дима', now() - interval '554 minutes'),
    ('F2140617-8290-4E12-9F40-5162738495A6', '🍋', 'Kanya', now() - interval '571 minutes'),
    ('03251728-93A1-4F23-8051-62738495A6B7', '🐝', 'Mateo', now() - interval '588 minutes'),
    ('14362839-A4B2-4034-9162-738495A6B7C8', '🌙', null, now() - interval '605 minutes'),
    ('2547394A-B5C3-4145-8273-8495A6B7C8D9', '🐢', 'はると', now() - interval '622 minutes')
on conflict (id) do nothing;

insert into public.posts (id, prompt_id, author_id, body, body_language, created_at, expires_at) values
    ('A27331CF-683D-46E7-84FE-00FD8A513A16', 'prompt_001', 'F71DC8ED-6519-4F76-9CBD-0ED21889C3C5', '電車で寝てる人が、急にはっきりした声で「それは違うと思います」って言った。誰と話してたんやろ。', 'ja', now() - interval '2 hours' + interval '18 minutes', now() + interval '26 hours'),
    ('A08195C4-4A4C-40BD-91BE-159E77C57C7A', 'prompt_001', '1E56339E-92A5-481A-923D-72C2048CF18C', 'My cat tried to jump onto the table, missed completely, and then walked away like nothing had happened.', 'en', now() - interval '2 hours' + interval '34 minutes', now() + interval '26 hours'),
    ('2735683A-A8DB-4324-ADAD-2DC7C452EA41', 'prompt_001', 'D1F6A20F-3CCA-48EF-B1A1-7EE9EC475569', 'Mi abuela me llamó para preguntarme cómo se apaga la televisión. Estaba usando el mando del aire acondicionado.', 'es', now() - interval '2 hours' + interval '51 minutes', now() + interval '26 hours'),
    ('9CCC14F0-732F-43F5-AE71-D050A5C23277', 'prompt_001', 'DEB10675-152C-4EA7-B9F6-1684C5E49CA0', '출근길에 신발을 짝짝이로 신고 온 걸 회사에 도착해서야 알았다.', 'ko', now() - interval '2 hours' + interval '72 minutes', now() + interval '26 hours'),
    ('E2525BE9-953E-423B-951C-FFF1BA154FD1', 'prompt_001', 'EC0C5044-8484-4369-BA3C-6FAB0E3D1543', 'Mon voisin chante faux tous les matins sous la douche. Aujourd''hui il a oublié les paroles.', 'fr', now() - interval '2 hours' + interval '96 minutes', now() + interval '26 hours'),
    ('9546FA31-6696-4814-8504-BC82D4D7B43D', 'prompt_001', '95E0E393-C330-4639-889E-DDBC686DAAD3', 'I said "you too" to the waiter who told me to enjoy my meal. Every single time.', 'en', now() - interval '2 hours' + interval '110 minutes', now() + interval '26 hours'),
    ('39A70445-7D02-4EAC-BAD6-76A1FCF46CEE', 'prompt_001', '408AB191-43F1-4F41-9845-818F89524F68', '自販機で買ったつもりのコーヒーが、全然違うボタンのやつだった。まあ美味しかったからよし。', 'ja', now() - interval '2 hours' + interval '133 minutes', now() + interval '26 hours'),
    ('163D8D7F-C874-45DD-B512-4F75201243D8', 'prompt_001', '2F41AE07-4030-47A2-BCE8-110E70798E01', 'Meu filho de três anos me apresentou o seu "melhor amigo": uma pedra.', 'pt', now() - interval '2 hours' + interval '158 minutes', now() + interval '26 hours'),
    ('1BB1C854-3541-45D7-841D-EBD5202663E7', 'prompt_001', '76755DE6-E6BF-4DCC-BE5D-804276B60AF0', 'Ich habe zehn Minuten lang meine Brille gesucht. Sie war die ganze Zeit auf meinem Kopf.', 'de', now() - interval '2 hours' + interval '181 minutes', now() + interval '26 hours'),
    ('A972D1B0-E8A3-4A09-8DDC-4B7A0E9A2384', 'prompt_001', 'FDCBC9EE-01C9-4599-B004-2D7F934B060C', '同事把「辛苦了」打成了「幸福了」，整个群突然安静，然后大家都笑了。', 'zh', now() - interval '2 hours' + interval '204 minutes', now() + interval '26 hours'),
    ('396EE953-5D2D-4030-8BC3-F4E8A57835FE', 'prompt_001', 'B01B1C76-66B1-476B-B073-984FD13A8E1D', 'حاولت أن أفتح باب المتجر وأنا أدفعه ثلاث مرات، وكان مكتوباً عليه بخط كبير: اسحب.', 'ar', now() - interval '2 hours' + interval '227 minutes', now() + interval '26 hours'),
    ('D867EBF2-BB8B-449F-81DB-767DF6D2D2FC', 'prompt_001', 'E9F93D4F-6A9F-45E3-9553-D242D147CD6D', '犬が自分のしっぽに驚いてた。毎日同じことしてるのに、毎日はじめてみたいな顔をする。', 'ja', now() - interval '2 hours' + interval '249 minutes', now() + interval '26 hours'),
    ('8D4774DE-5140-47AE-8CBA-CA7FC03B8995', 'prompt_001', '6EC6D09C-ECAC-4098-AB8B-69A467BF112A', 'Pomyliłem szampon z żelem pod prysznic. Włosy pachną cytryną, ale wyglądają dobrze.', 'pl', now() - interval '2 hours' + interval '271 minutes', now() + interval '26 hours'),
    ('27D12B43-097B-417E-AFD9-8BF33ADE17FA', 'prompt_001', '735F5078-2552-4844-AD91-B3B6D8753E9A', 'My grandpa found out what a meme is today. He now sends me one every hour, and none of them make sense.', 'en', now() - interval '2 hours' + interval '294 minutes', now() + interval '26 hours'),
    ('A7BE2A5F-5F1D-4A6A-B67A-BF87A07FBB0B', 'prompt_002', 'ACCB549C-C91B-44C0-9D96-1B56288514E2', '「いつもありがとう」って、母に言われた。当たり前のことをしてるつもりやったのに。', 'ja', now() + interval '26 hours' + interval '21 minutes', now() + interval '54 hours'),
    ('5ED288D2-2979-49AC-B99C-EF38BC68BE0A', 'prompt_002', 'E63C7BC7-7EA4-4B0C-BEE5-A34FFE01F310', 'A stranger told me my laugh made his day better. I have been self-conscious about it for years.', 'en', now() + interval '26 hours' + interval '44 minutes', now() + interval '54 hours'),
    ('87E66E0D-BB76-4838-9E8E-3C2EC473FCF5', 'prompt_002', '95B19169-409E-4C34-A0C6-D74ACDC61C3F', '팀장님이 "네 방식대로 해봐"라고 말해줬다. 처음으로 믿음을 받은 기분.', 'ko', now() + interval '26 hours' + interval '67 minutes', now() + interval '54 hours'),
    ('5E8F4093-3C21-4EB3-99CC-55C73649ADB5', 'prompt_002', '53AEED3B-B0AF-42B3-B213-27E6906015B7', 'Mi hija me dijo: "papá, contigo no tengo miedo". Me quedé sin palabras.', 'es', now() + interval '26 hours' + interval '90 minutes', now() + interval '54 hours'),
    ('96D63DD8-2A85-452C-B403-2E6DF6C72110', 'prompt_002', 'B1B6C79D-F7FD-46A5-B72A-B1D26E579417', 'Une collègue m''a dit que je posais toujours les bonnes questions. Je pensais juste être curieux.', 'fr', now() + interval '26 hours' + interval '113 minutes', now() + interval '54 hours'),
    ('997475B3-0B2D-4280-AE30-EA9683152055', 'prompt_002', '6705289F-4F47-42F9-8622-27299566FE47', 'Meine Nachbarin sagte, das Haus sei freundlicher geworden, seit ich hier wohne.', 'de', now() + interval '26 hours' + interval '136 minutes', now() + interval '54 hours'),
    ('DAF9743C-7CDB-473F-9EE0-A15851F47D42', 'prompt_002', '8DD02152-4A1D-4891-B5DF-F0FD89E8E741', 'Meu chefe disse que confia em mim. Foi só isso, mas carreguei essa frase o dia todo.', 'pt', now() + interval '26 hours' + interval '159 minutes', now() + interval '54 hours'),
    ('8D179A30-B0D3-421C-8B61-CE8ED779B266', 'prompt_002', '74E85C2A-305D-47DD-91BB-00231C11A004', '弟弟说：“哥，我想变成你这样的人。”我偷偷高兴了很久。', 'zh', now() + interval '26 hours' + interval '182 minutes', now() + interval '54 hours'),
    ('CB9B9255-683E-4E0B-830C-E224EB434D21', 'prompt_002', 'C712DA6A-92DC-474A-970A-A79E7FE6224D', 'قال لي صديقي: "وجودك يريحني". لم أعرف بماذا أرد.', 'ar', now() + interval '26 hours' + interval '205 minutes', now() + interval '54 hours'),
    ('A6F50034-4E24-4DBD-853D-C6E82C7150E0', 'prompt_002', 'A51AB2CE-A716-4D27-96CA-B9F1DFB4B9C7', 'Un cliente mi ha detto che il mio pane sa di casa sua. Lavoro da vent''anni per una frase così.', 'it', now() + interval '26 hours' + interval '228 minutes', now() + interval '54 hours'),
    ('0B0CA53F-D3F0-42AA-8B5F-1F854DB2752B', 'prompt_002', '63DA91C8-F2C6-4EA3-80DA-0E8F81F3976B', 'Kata guru saya: "kamu boleh pelan, yang penting jangan berhenti".', 'id', now() + interval '26 hours' + interval '251 minutes', now() + interval '54 hours'),
    ('69866C9E-076F-46B7-81A4-9D4AE0F67592', 'prompt_002', '0B679032-24AC-47EE-A5C0-1475AC49291F', 'My roommate said the flat feels quieter when I am away. Nobody had ever missed me out loud before.', 'en', now() + interval '26 hours' + interval '274 minutes', now() + interval '54 hours'),
    ('3F1B2C5A-9D14-4E77-8B21-0A5C6D7E8F90', 'prompt_001', 'B8F0C2D3-4E56-4A78-9B0C-1D2E3F405162', 'Otobüste yanımdaki adam uyurken benim omzuma yaslandı ve uyanınca bana teşekkür etti.', 'tr', now() - interval '2 hours' + interval '312 minutes', now() + interval '26 hours'),
    ('4A2C3D6B-0E25-4F88-9C32-1B6D7E8F9001', 'prompt_001', 'C9E1D3E4-5F67-4B89-8C1D-2E3F40516273', 'Ho salutato con la mano una persona che salutava qualcuno dietro di me. Poi ho fatto finta di sistemarmi i capelli.', 'it', now() - interval '2 hours' + interval '329 minutes', now() + interval '26 hours'),
    ('5B3D4E7C-1F36-4099-8D43-2C7E8F900112', 'prompt_001', 'D0F2E4F5-6078-4C90-9D2E-3F4051627384', 'Mijn hond blafte tien minuten naar een tas die ik zelf had neergezet.', 'nl', now() - interval '2 hours' + interval '347 minutes', now() + interval '26 hours'),
    ('6C4E5F8D-2047-41AA-9E54-3D8F90011223', 'prompt_001', 'E1030506-7189-4D01-8E3F-405162738495', 'Сегодня я три раза сказал «алло» в микроволновку, потому что она пищала как телефон.', 'ru', now() - interval '2 hours' + interval '365 minutes', now() + interval '26 hours'),
    ('7D5F6091-3158-42BB-8F65-4E9001122334', 'prompt_001', 'F2140617-8290-4E12-9F40-5162738495A6', 'วันนี้ฉันเรียกครูว่า “แม่” หน้าห้องเรียน ทุกคนหัวเราะ แล้วครูก็หัวเราะด้วย', 'th', now() - interval '2 hours' + interval '384 minutes', now() + interval '26 hours'),
    ('8E607102-4269-43CC-9076-5F0112233445', 'prompt_001', '03251728-93A1-4F23-8051-62738495A6B7', 'Le pedí un café al camarero y le dije “gracias, mamá”. Nadie dijo nada, pero todos lo oyeron.', 'es', now() - interval '2 hours' + interval '402 minutes', now() + interval '26 hours'),
    ('9F718213-537A-44DD-8187-601223344556', 'prompt_001', '14362839-A4B2-4034-9162-738495A6B7C8', '엘리베이터에서 혼자인 줄 알고 노래를 불렀는데 거울 뒤에 사람이 있었다.', 'ko', now() - interval '2 hours' + interval '421 minutes', now() + interval '26 hours'),
    ('A0829324-648B-45EE-9298-712334455667', 'prompt_001', '2547394A-B5C3-4145-8273-8495A6B7C8D9', '子どもが「パパの頭、月みたい」って言ってきた。悪気がないから何も言い返せへんかった。', 'ja', now() - interval '2 hours' + interval '439 minutes', now() + interval '26 hours')
on conflict (id) do nothing;

-- 運営お知らせ（新機能・ハンバーガーメニューのお知らせ画面用サンプル）。
insert into public.announcements (id, title, body, published_at) values
    ('B1C2D3E4-F506-4718-8293-A4B5C6D7E8F9', 'SameQ へようこそ', '毎日1つのお題に、世界のどこかの誰かと同時に答えます。答えるまでは、他の人の言葉は見えません。', now() - interval '2 days'),
    ('C2D3E4F5-0617-4829-93A4-B5C6D7E8F9A0', 'Plus をはじめました', '長文投稿やスタンプ・装飾が使える Plus プランをはじめました。設定からいつでも購入・解約できます。', now() - interval '1 day')
on conflict (id) do nothing;
