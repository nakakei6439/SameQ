# pool-pilot.tsv 自己評価

対象: pos 238〜337（100件）。入力は
`/tmp/claude-501/-Users-nakagawakeita-Products-iOSApp-SameQ/31c5263b-2e0c-4bd0-8750-3a9abba28c2d/scratchpad/pilot-input.tsv`。
出力は `.product/prompt-pool-v2/pool-pilot.tsv`（pos, text_ja, text_en の3列、タブ区切り、ヘッダ無し）。

## 機械チェック（すべて通過）

- `wc -l`: 100
- `awk -F'\t' '{print NF}' | sort -u`: `3` のみ
- pos: 238〜337 を1回ずつ、過不足なく含む
- text_ja: 入力の2列目と `diff` で完全一致（無差分）
- text_en: 空文字なし、重複なし（`sort | uniq -d` が空）
- text_en: `Do you / Have you / Did you / Is there / Was there / Are you / Were you / Has` で始まる
  はい・いいえ型の書き出しはゼロ件
- text_en: 18語を超える行はゼロ件
- text_en: 全行が `?` で終わる

text_ja は入力ファイルの行をスクリプトでそのまま転記する方式にした（手打ちでの転記ミスを避けるため）。
誤字・重複表記（例: pos267「ととしたら」、pos316「有名の人」、pos318「体のどこを止まりたい」の助詞の
不自然さ）はすべて元のまま残してある。誤字修正はこの作業のスコープ外という指示に従った。

## 英訳に迷った箇所

- **pos245 / 246 / 292 / 296**（「この一年で、はじめて気づいた自分の大事にしている〈日没／水／もの／火〉は？」）
  テンプレートの名詞だけを差し替えた4問が並んでいた。直訳（"a sunset you take care of"）は英語として
  意味不明になるため、「今年になって初めて、大切だと気づいた〈対象〉」という意味を汲んで
  discovered/realized の動詞で言い換えた。4問とも "you first noticed X" という同一パターンの
  反復（＝既存999件プールの build.py に見られる、単調で硬い繰り返し）を避けるため、動詞と文構造を
  少しずつ変えて重複感を消した。
  - 245: "This year, what's a sunset you discovered means a lot to you?"
  - 246: "This year, what's something about water you discovered you love?"
  - 292: "This year, what's something you discovered truly matters to you?"
  - 296: "This year, what's something about fire that you discovered you love?"

- **pos265「いま、好きな途中をひとつだけ挙げるとしたら？」**（「途中」＝道半ば・進行中の状態）
  「途中」は英語に1語で対応する語がなく、直訳すると意味不明になる。「何かの最中にいる、その
  一瞬が好き」という含意を汲んで "your favorite part of being partway through something" と開いた。

- **pos276「いま、好きな指先をひとつだけ挙げるとしたら？」**（「指先」＝指先そのもの、または
  指先で触れる感触）
  「好きな指先」を名詞のまま訳すと "favorite fingertip" になり意味不明。指先で感じる感触・質感を
  尋ねていると解釈し、"your favorite thing to feel with your fingertips" とした。

- **pos335「いま、好きな頂上をひとつだけ挙げるとしたら？」**（「頂上」＝山などの頂）
  一度は "real or imagined" を足して余白を持たせる案を考えたが、原文に無い情報を足すことになるため
  やめ、"What's your favorite peak right now?" とシンプルに留めた。

- **pos311 と pos324**（どちらも「誰にも言っていない／話していないが本当は少し気にしていること」を
  扱うが、末尾がそれぞれ「絵にするとしたら？」「そっと抱えてみるとしたら？」と異なる）
  内容が近い2問だったため、text_en が重複しないよう明確に訳し分けた。
  - 311: "If you turned something you brushed off as 'nothing' into a picture, what would it look like?"
  - 324: "What's something you've quietly been carrying, but haven't told anyone?"

- **pos307「小さい頃、誰かにほめられた一言は？」と pos329「小さい頃、誰かにほめられた記憶は？」**
  （どちらも「ほめられた」経験を聞く近接した2問）こちらも text_en が重複しないよう、
  「一言（せりふ）」と「記憶」という原文のニュアンスの違いをそのまま活かして訳し分けた。
  - 307: "What's a compliment someone gave you as a kid?"
  - 329: "What's a memory of being praised as a kid?"

## 文化依存を置き換えた箇所

該当なし。今回の100件（pos238〜337）は「いま／小さい頃／今日／最近」の身体感覚や気分を聞く
問いが中心で、日本固有の行事・制度・ブランド名を前提にしたものは含まれていなかった。
そのため文化的な置き換えを行った箇所はゼロ件。

## 日本語側が曖昧で解釈を選んだ箇所

- **「自分の体のどこが〜」系の問い**（pos239, 244, 274, 294, 301, 302, 312, 318, 321, 331 の10件）
  同じ構文の使い回しが多く、状態の違い（現在形・願望・過去形）を訳し分けることに注意した。
  - 「落ちついています／悲しんでいます／温かくなっています／怒っています／動いています」＝
    現在の状態 → "Right now, where in your body feels ___?"
  - 「開きたい／縮めたい／止まりたい」＝願望 → "Right now, what part of your body wants to ___?"
  - 「止めました」＝過去に自分が止めた行為 → "Just now, what part of your body did you bring to a stop?"
  - pos318「いま、自分の体のどこを止まりたいですか？」は「止まる」（自動詞）に「を」が付く
    助詞の誤用と思われる原文。「止まりたい」を「休みたい」に近い意味と解釈し、
    "Right now, what part of you wants to stop and rest?" とした。

- **pos259「誰にも言っていない小さな喜びを、みっつだけ教えてください。」**（命令形）
  お題の基準で「命令形にしない」とあるため、疑問文に開いた。ただし「みっつ」（3つ）という
  数の指定は意味の核なので保持した:
  "What are three small joys you've never told anyone about?"

- **pos257「今日、ちょっとうれしい偶然はありましたか？」**（「〜はありましたか？」＝はい/いいえ型）
  基準7に従い、What に開いた: "What's a happy little coincidence from today?"

## 使わなかった既存訳（参考情報）

`.product/prompt-pool-v2/build.py` に999件ぶんの別の英訳ドラフトが既にあったが、
"One way you would love a morning to begin?" のような名詞句止め・硬い直訳パターンが多く、
今回のタスクで「悪い例」として明示された書き方（例: "One way you would love a Sunday to begin?"）
に近かったため参照せず、今回の100件はゼロから書き直した。

## 完了条件チェックの実行結果（再掲）

```
wc -l pool-pilot.tsv          → 100
awk -F'\t' '{print NF}' | sort -u → 3
pos 238..337                  → 過不足なし
diff (text_ja列)              → 無差分
text_en 空文字                → 0件
text_en 重複                  → 0件
```
