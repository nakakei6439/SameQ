# pool-final.tsv 自己評価（999件、スプリント23）

出力: `.product/prompt-pool-v2/pool-final.tsv`（pos, text_ja_old, text_ja, text_en の4列、
タブ区切り、ヘッダ無し）。pos は `PromptCatalog.candidatePool`（Swift、0-indexed）および
`ensure_todays_prompt()` の v_pool（SQL）の添字と一字一句一致する。

## 機械チェック（すべて通過。999件全件）

- 行数: 999、列数: 全行4列
- pos: 0〜998 を1回ずつ、過不足なく含む
- text_ja: 999件すべて重複なし
- text_en: 999件すべて重複なし（グローバル重複チェック。同じ日本語意味の近い問いも
  英訳の語順・語彙をずらして重複を避けた）
- text_en: 空文字なし
- text_en: 18語を超える行はゼロ件
- text_en: 全行が `?` で終わる
- text_en: `Do you / Have you / Did you / Is there / Was there / Are you / Were you / Has ` で
  始まる Yes/No 型の書き出しはゼロ件（先頭の "Today," "Lately," "As a kid," 等のあとに
  Yes/No 節が来る2文構成は許容: 例 "As a kid, was there homework you actually liked? What was it?"
  — 文字列の先頭が禁止パターンでなければパイロットの基準どおり）

## text_en の作り方（899件、pos238〜337を除く）

パイロット100件（pos238〜337、`.product/prompt-pool-v2/pool-pilot.tsv`）はそのまま流用した。
残り899件は、999件が強く定型化されていることを利用し、以下の手順で作った:

1. 日本語原文をプレフィックスでグルーピング（「いま、好きな」165件、「もし一日だけ」146件、
   「いま、自分の体のどこ」85件、「この一年で、はじめて気づいた」77件、「小さい頃、好きな」
   61件、「小さい頃、誰」38件 …）。
2. テンプレート性が高い群（「いま、好きな{X}をひとつだけ挙げるとしたら？」「いま、自分の
   体のどこが{状態}ですか？」「この一年で、はじめて気づいた自分の{X}は？」等）は、
   名詞・形容詞だけを訳す辞書を作り、固定の英語テンプレートに当てはめた
   （例: `What's your favorite {X} right now?` / `Right now, where in your body feels {X}?`）。
3. テンプレート性が低い群（「もし一日だけ」136件、「今日、誰かに」「最近、誰かと」等の
   人間関係・感情を聞く問い）は1問ずつ個別に訳した。
4. 近い意味の問いが複数ある場合（例: 「誰かとすこし笑い合えたことは？」と「誰かと目が合った
   ときにふっと笑った瞬間は？」）は、pilot と同じ方針で語順・語彙を明確に訳し分け、
   text_en が文字列として重複しないようにした。

## ja の誤字修正（34行。意味・並び順は変えていない）

| pos | 修正前 | 修正後 | 理由 |
|---|---|---|---|
| 0, 129, 180, 185, 205, 267, 354, 421, 469, 499, 616, 659, 667, 730, 743, 744, 788, 850, 871, 893, 897, 912, 955, 956 | 「〜ひとつだけ挙げるととしたら？」 | 「〜挙げるとしたら？」 | 「と」の重複タイプミス（24件） |
| 7 | 「おじいちゃんおばあちゃんなれたら」 | 「〜になれたら」 | 「に」の脱落 |
| 224 | 「好きなった匂いはありますか？」 | 「好きになった匂いはありますか？」 | 「に」の脱落（既存48件 legacy プールにも含まれる文言） |
| 316 | 「有名の人」 | 「有名な人」 | 助詞の誤り |
| 318 | 「体のどこを止まりたいですか？」 | 「体のどこで止まりたいですか？」 | 自動詞「止まる」に「を」は不自然。既存の英訳（pilot pos318: "wants to stop and rest"）と整合する形に「で」へ |
| 426 | 「振り返えた瞬間」 | 「振り返った瞬間」 | 誤字 |
| 617 | 「驚きっていますか？」 | 「驚いていますか？」 | 誤字 |
| 750 | 「好きな同じをひとつだけ」 | 「好きな同じものをひとつだけ」 | 名詞「もの」の脱落 |
| 908 | 「すごしてたえた瞬間」 | 「すごして癒やされた瞬間」 | 脱字と判断（attempt 2で修正。理由は下記「attempt 2」節） |
| 941 | 「一番好きです？」 | 「一番好きですか？」 | 終助詞「か」の脱落 |
| 963 | 「みっつ何を何を買いますか？」 | 「そっとみっつだけ買えるとしたら何を買いますか？」 | 語順の乱れ・重複を修正（attempt 2でコーディネーター指定の文言に変更） |

24件の「ととしたら」修正は該当する pos すべてで確認済み（0, 129, 180, 185, 205, 267, 354, 421,
469, 499, 616, 659, 667, 730, 743, 744, 788, 850, 871, 893, 897, 912, 955, 956）。

## 意図的に直さなかった箇所

- **pos474「いま、好きな途をひとつだけ挙げるとしたら？」**: 「途」は単独では不自然な語
  （「途中」等の脱字の可能性がある）。ただし同じプール内の pos265 が既に
  「いま、好きな途中をひとつだけ挙げるとしたら？」を使っており、「途」→「途中」に直すと
  ja が重複してしまう（999件のプールで唯一の重複を新たに作ることになる）。誤字修正より
  「プール内で ja が重複しない」ことを優先し、意図的に直さなかった。text_en は「途」を
  「進行中の道・行程」の意で "your favorite path you're on right now?" と訳し、pos265
  （"partway through something"）とは別の表現にして区別した。

## 完了条件チェックの実行結果（再掲）

```
wc -l pool-final.tsv                         → 999
awk -F'\t' '{print NF}' | sort -u             → 4
pos 0..998                                    → 過不足なし
text_ja 999件                                 → 重複なし
text_en 999件                                 → 重複なし
text_en 空文字                                → 0件
text_en 18語超過                              → 0件
text_en が「?」で終わらない                    → 0件
text_en の Yes/No 型書き出し                   → 0件
```

## attempt 2（eval-1.md の指摘対応）

evaluator の指摘（`.product/sprints/23-prompt-text-en/eval.md`）を受けて、text_en の質を
以下のとおり修正した。日本語（`text_ja`）は pos908 / pos963 の2件のみ変更（下表参照）。

### [1] 英訳10件の文法崩れ・意味ずれを修正

| pos | 修正前 | 修正後 | 種別 |
|---|---|---|---|
| 1 | This year, what's a sense of when you can help you discovered about yourself? | This year, when did you first discover you had a good sense for when to help? | 破綻文 |
| 460 | This year, what's a air you noticed you truly value? | This year, what's an air you noticed you truly value? | 冠詞 a→an |
| 531 | This year, what's a expression you learned about for the first time? | This year, what's an expression you learned about for the first time? | 冠詞 a→an |
| 786 | This year, what's a evening you found out you love? | This year, what's an evening you found out you love? | 冠詞 a→an |
| 26 | This year, what's a new side of yourself you discovered about yourself? | This year, what's a new side of yourself you discovered? | about yourself 重複 |
| 197 | This year, what's a surprising side of yourself you discovered about yourself? | This year, what's a surprising side of yourself you discovered? | about yourself 重複 |
| 233 | This year, what's a thing you like about yourself you discovered about yourself? | This year, what's something you like about yourself that you only just noticed? | about yourself 重複 |
| 212 | Right now, what part of you wants to make more sensitive? | Right now, what part of you wants to become more sensitive? | 目的語欠落 |
| 360 | Right now, what part of you wants to bring to a stop? | Right now, what part of you wants to come to a stop? | 目的語欠落 |
| 110 | Right now, where in your body feels the most tense? | Right now, where in your body feels the most pain? | 意味ずれ（つらい≠緊張。緊張は pos55 で使用済み） |

修正方法: テンプレート生成のもとになった辞書（`noun_en` / `state_adj` / `desire_verb` /
`daiji_noun_en` 等）の該当エントリ、または個別の specials を直接修正し、999件全体を
再生成した（手作業でTSVの1セルだけを書き換えるのではなく、生成元から直したので
Swift/SQLとの同期スクリプトを再実行すれば常に一致する）。

### [2] 「もし一日だけ」の "today" を "for a day" 系へ書き換え（136件中124件）

パイロット10件（pos249, 254, 255, 284, 298, 306, 313, 316, 320, 333）はもともと
"for a day" / "for one day" / "for a whole day" / "for just one day" を使っており
"today" は0件だった。残り136件（パイロット範囲外）のうち124件が機械的な生成時に
"today" を使ってしまっていたため、全136件を対象に "today" → "for a day"（原則）に
置き換えた。以下は単純な文字列置換では不自然になった9件の個別対応:

| pos | 修正前 | 修正後 |
|---|---|---|
| 149 | If you could spend today with anyone, who would it be? | If you could spend a day with anyone, who would it be? |
| 354 | If you could spend today without deciding anything, what would you do? | If you could spend a day without deciding anything, what would you do? |
| 392 | If you could spend today's time on someone else, what would you do? | If you could give someone else a whole day of your time, what would you do? |
| 394 | If you could spend today's time only on yourself, what would you do? | If you could give yourself a whole day of your own time, what would you do? |
| 453 | If you could decide everything for yourself today, what would you do? | If you could decide everything yourself for one day, what would you do? |
| 603 | If you could stay with someone all day without ever parting today, who would it be? | If you could stay with someone all day without ever parting, who would it be? |
| 684 | If today only had a tenth of the usual time, what would you want to do most? | If one day only lasted a tenth as long, what would you want to do most? |
| 736 | If you could pick your favorite time of day today, which would it be? | If you could make your favorite time of day last all day, which would you pick? |
| 842 | If today had ten times the usual time, what would you want to do most? | If one day lasted ten times as long, what would you want to do most? |

このほか、機械置換の結果18語を超えた2件（537, 639）は語数を減らしつつ言い回しを変え、
既存の近い意味の問い（171「食事をする」、487「話す」）と文字列が重複しないように書き分けた:

| pos | 修正後 |
|---|---|
| 537 | If you could treat your favorite person to a meal for a day, what would you serve? |
| 639 | If you could chat with someone you like all day, what's the first thing you'd say? |

### [3] 追加のグローバル機械チェック（999件全件、eval.md の指示どおり）

- `\b[aA] [aeiouAEIOU]` を全 text_en に実行 → 0件（修正前は460/531/786の3件）。
- 「もし一日だけ」の text_en に "today" が残っていないか → 0件（修正前は124件）。
- 単語2〜4-gram の同一フレーズ繰り返しを検出するスクリプトを全件に実行 → 検出3件のうち
  2件（105「did you」・685「would you」）は2つの疑問文が並ぶ自然な英文で問題なし、
  1件（753「right now right now」）は実際のバグで修正した:
  - pos753: `いま、好きな今の音をひとつだけ挙げるとしたら？` の text_en が
    "What's your favorite sound from right now right now?" になっていた
    （名詞句の訳「sound from right now」に、テンプレートの末尾「right now?」が
    重なって二重になっていた）。"What's your favorite sound you're hearing right now?" に修正。
- 999件の text_en 重複チェック・text_ja 重複チェックは0件を再確認。
- 元の完了条件（18語以内・`?`終わり・Yes/No型書き出し禁止）も999件で再実行し、0件を再確認。

### [4] pos908 / pos963 の ja 修正の確定

- pos908: 「すごしてたえた瞬間は？」→「すごして**癒やされた**瞬間は？」
  （attempt 1では「癒えた」としたが、「癒える」は傷に使う語で「一緒に時間を過ごして
  癒える」という文脈に合わないという evaluator の指摘どおり。受け身形「癒やされた」に修正。
  text_en は元々 "leave you feeling soothed" で意味が合っていたため変更不要）。
- pos963: 「みっつ何を何を買いますか？」→「そっと**みっつだけ**買えるとしたら何を買いますか？」
  （コーディネーター指定の文言にそのまま変更。text_en "treat yourself to three things" は
  意味が合っているため変更不要）。
- どちらも `official_answers` のキー（48件）には含まれていないため、マイグレーションの
  キー更新リスト（5件）に変更は無い。

## SQL / Swift との同期

`supabase/migrations/20260923000002_prompt_text_en.sql` の `v_pool_ja` / `v_pool_en`、
`SameQ/Backend/PromptCatalog.swift` の `candidatePool` / `candidatePoolEn` は、いずれも
`pool-final.tsv` から機械生成し、Python で byte-for-byte 一致を確認した（999/999件、順序も一致）。
デプロイ後の PostgreSQL 関数定義（`pg_get_functiondef`）から実際に配列を抽出して再照合済み
（詳細はスプリント自己評価 `.product/sprints/23-prompt-text-en/self-review.md` を参照）。
