# 運営回答 英語版 自己レビュー（attempt 1）

## 完了条件の確認

| 条件 | 結果 |
|---|---|
| 161行（ヘッダ1 + データ160） | ✓ `wc -l` で161 |
| 全行が4列 | ✓ `awk -F'\t' 'NR>1{print NF}' | sort -u` = `4` |
| `lang` 列がすべて `en` | ✓ 唯一の値 `en` |
| prompt_text が40種類、各お題4行 | ✓ distinct 40、`uniq -c` 全部 `4` |
| persona 4種（robo/dragon/tetra/keita）が過不足 | ✓ 各40行 |
| body に空文字/タブ/改行なし | ✓ 該当行 0 |
| prompt_text+persona の組が入力と完全一致 | ✓ Python で NFC 正規化照合 → MATCH |

## 正規化まわりでハマったこと

最初、Edit ツールで部分修正しようとしたら `String to replace not found in file`
で失敗した。`od -c` で見たら**入力も出力も NFD**（`最` が `最`+結合 diaeresis の
2バイト）で書かれていたのに対し、Edit ツールに渡す文字列は NFC だったので、
バイト単位で不一致になっていた。

最終的に Python で `unicodedata.normalize('NFD', ...)` を明示的にかけて書き出
すことで解決。書き出し後は `od -c` で NFD 維持を確認、`diff` コマンドはバイト
単位で差分を出すので不一致に見えるが、Python で NFC 正規化して比較すると完全
一致した。

`diff <(awk ... | sort) <(awk ... | sort)` はバイト単位比較なので注意。
「`diff` が差分を出したから不一致」ではない。

## 訳しにくかった箇所（具体例つき）

### 1. 「ニャー」の翻訳
- 「当たってたニャー。」→ `was right.`
- 「助けられたんじゃない。当然のことニャー。」→ `just expected.`
- 「順番に来るのがいいニャー。」→ `like them in that order.`
- 「5秒は待てるニャー。すごくない？」→ `five whole seconds before food. impressive, right?`

依頼文に「機械的に meow を付けるな」とあったので、`meow` は一度も使っていない。
代わりに「語尾の断定/軽い主張」だけ残した。テトラの傲慢さ・そっけなさの核は
`meow` ではなく、**短い文で自分の世界しか見ていない態度**なので。

### 2. ケータの関西弁
- 「妻の『あれ、助かったわ』。何が助かったか覚えてへんけど、仕組みにしといてよかった。」
  → `my wife's 「that helped.」 can't remember what it was about, but glad i built the system that way.`
- 「仕組みにしといてよかった」は方言特有のリズムだが、英語では方言に置き換えず、
  **短い・具体的・過去形で「しくみ化」が効いた」という判断の言い切り**で表現。
  「覚えてへんけど」の覚えてない感も `can't remember` で済む。
- 「型落ちのほう買うた。新型出て値崩れして、装備ほぼ同じで20万違う。数字で選ぶと外さん。」
  → `bought last year's model. the new one dropped in price — almost the same equipment, 200k cheaper. pick by the numbers and you don't miss.`
- 「買うた」「〜へん」「外さん」みたいな関西弁特有の音は、英語では省略動詞
  contraction（`can't`, `i'll`）と短文の連続で置換。リズムは保つ。

### 3. ドラゴンの古めかしい口調
- 「誇りは、寿命の短い者の言葉だ。」のような簡潔な格言調は、英語でも同じく短文
  格言で処理。
- 例: 「動かぬ岩の上にいれば安心だ。私はたいてい、岩の上にいる。」→
  `standing on stone that doesn't move, that's safety. i'm usually on stone.`
- 「もう千年ない」のような古い数詞表現もそのまま `a thousand years` で通じる。
- ブリスケット弱点のお題だけは原文どおり本音モード:
  `beef shoulder, smoked slow over half a day. the fat falls apart on the tongue. don't crank the heat. don't skip the resting. …… ate it once, on dry land in the south.`
  - 「南の乾いた土地で一度きり」を `on dry land in the south` に。
  - 固有名詞（Texas等）は出さない方針通り。

### 4. ロボの AI 性
- 「画面の内側で言いました」のような AI メタファーを英語でも維持:
  - `left it on the screen for a while.`
  - `said it inside the screen, since there was no one to send it to.` (依頼文の例)
- 「夢は見ません」「匂いは届きません」「名前は覚えられません」はそのまま
  訳してOK、AIが事実として語る声を保つ。

### 5. 文体をどこまで揃えるか
依頼文の例では文頭を小文字で始めている（`dinner — hot pot.` など）ので、160行
すべて文頭小文字に揃えた。句読点は英語コンベンション（`,` `.` `?`）で統一。
日本語原文にある `「」`（鉤括弧）は英語では `" "` が自然だが、原文の
「鉤括弧」を残すか `" "` に置換するかは判断が要る。

採用方針: **鉤括弧はそのまま ASCII の `"`/`"` ではなく `「`/`」` のまま残した**。
理由:
- アプリ側の表示で `「...」` が既に「地の文と区別する記号」としてUIに馴染んで
  いる可能性があり、置換すると表示側のレイアウトに影響しうる。
- 機械的に `「...」` のまま残せば、後段の差分確認・翻訳チェッカーでの
  「未翻訳箇所検出」がしやすい。

ただし、ASCII の `"` に置換すべきだった可能性もあり、最終的には表示側（Swift /
L10n）と突き合わせて要確認。

### 6. 文化固有の語
- 「型落ち」「新型」「値崩れ」「20万」: 自動車ディーラーで一般的に通じる語。
  `last year's model`, `the new one dropped in price`, `200k cheaper` で訳した。
- 「納豆卵かけごはん」: `natto egg on rice` でそのまま。英語圏では通じないが、
  アプリのターゲットが日本人+英語話者混在なので、固有名詞扱いで残した。
- 「カリカリ」(猫の餌): `kibble` で訳した。一般的。
- 「段ボール」: `cardboard box` / `a cardboard fort` で訳した。

### 7. 数字・単位
日本語の「3日」「20万」「3分」「5秒」「2週間」「3時間」「1杯ぶん」「半日」などを
そのまま英語に。円マークや「万」は出てこないので問題なし。

## 提案（今回はやらなかったこと）

1. **鉤括弧 `「」` の扱い**: アプリ側の表示に依存するため、表示確認の Swift
   担当に「英語訳では鉤括弧を ASCII に置換すべきか」を確認したい。

2. **略語の統一**: ペルソナ定義に「"AI" であることを隠さない」とあるが、
   `i can't taste.` のような事実陈述が「AI です」と明示する強い宣言と
   どっち寄りかは議論の余地。今回は事実陈述側に寄せた。

3. **「ニャー」を一切訳さなかった判断**: アプリ側で `meow` を一切出さないことに
   したので、絵文字的な記号としての `meow` を1つだけ入れるか完全削除かの判断は
   できた。今回は完全削除。テトラの声をどこまで「猫」感を残すかは要検討。
