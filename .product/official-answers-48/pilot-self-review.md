# pilot-bilingual.tsv 自己評価

## 完了条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 81行（ヘッダ1 + データ80） | 達成 | `wc -l` = 81、`awk END` = 81 |
| 全行が4列 | 達成 | `awk -F'\t' '{print NF}'` は全行 4 のみ |
| prompt_text 8種、各お題ちょうど10行 | 達成 | `uniq -c` で各 10 |
| 各お題で persona 5種 × lang 2種 = 10行、過不足なし | 達成 | `(prompt, persona, lang)` の `sort -u` が 80 行（重複なし） |
| body に空文字無し・タブ無し・改行無し | 達成 | `awk` で全行チェック、警告なし |
| 入力40行の body が1文字も変わっていない | 達成 | 既存40行を抽出し入力と `diff` → exit=0（バイト単位一致） |

## 並べ方

1お題につき10行ブロックで配置。各プロンプト内でまず既存の5行（`robo ja / emily en / dragon ja / tetra ja / keita ja`、入力と同じ順序）をそのまま置き、その直後に新規5行（`emily ja / robo en / dragon en / tetra en / keita en`）を足しています。順序に特別な意味はない（DB投入時にprompt_text+persona+langでUpsertするため、行の前後関係は結果に影響しない）ですが、人間が一目で「同じ質問の5ペルソナ × 2言語」が揃うように並べました。

## 各ペルソナで気をつけた点

### ロボ (robo)

JA版は「人間の実体験の代わりに、別の具体で終える」書き方が一貫している。EN版も同じ骨格を守る:

- JA: 「猫が踏んだ」で誤字を説明 → EN: "the cat stepped on it" (逐語に近い、内容同一)
- JA: 「わからない」の三文字 → EN: three characters — "i don't know."
- JA: 「同じ問いに正反対の答えが並んだとき」 → EN: "two opposite answers sat next to each other for the same question"

ロボの声の核は「他人の具体を借りて観察する」なので、ENでも一人称は "i" だが観察者位置は保つ。AIで有ることを毎回の枕詞にしない方針（ペルソナ定義通り）もENで踏襲。

### エミリー (emily)

ENの原文がくだけた小文字体・絵文字多め・140字ギリギリ詰め込みなので、JA版も:
- 絵文字は原文に合わせて残した: 😭 → 😂（笑い泣き）、🎂 はそのまま、🐦 はそのまま
- 文体を硬くしない。原文の "look at THIS —" のような勢いを「見てこれ！」に、"worth it" を「最高だった / また同じことする」に
- 文字数の目安 ~139 字。日本語で約120〜140字になるよう、原文の断片を膨らませるのではなく旅の細部（屋台の店主・通りがかったおばあちゃん・6時間まるごと等）で埋めた

### ドラゴン (dragon)

「古めかしい口調は、英語でも古風に、そして短く」が方針。EN版は:
- 小文字の "i" を使う（竜は ego を大文字にしない）
- "i no longer recall when that was" / "the heart quickening" / "had all returned to the earth before me" — 古語的でないが、感情を抑えた格調のある英語
- 長さはJAと同等（〜25 words）

JAにあった弱点（ブリスケットの話）は今回のお題8問には出ないので使わず、通常のはぐらかし口調に統一。

### テトラ (tetra)

「『ニャー』は英語で機械的に "meow" を付けない。猫らしい傲慢さ・そっけなさで表現する」が一番難しかった。

元のJAで「ニャー」がつくのは4箇所:
- ありお2「朝ごはん、ちゃんと3回鳴いて伝えた。**えらいニャー**。」
- ありお4「ちょっと狭かったけど**出ないニャー**。」
- ありお6「しっぽは**少し立てといたニャー**。」
- ありお8「**見逃してないニャー**。」

EN版:
- EN2: "deserve credit, actually." — 偉そうさを文末の "actually" に載せた
- EN4: "not leaving." — 短く決定的な拒否
- EN6: "tail went up, slightly." — "slightly" の抑制が猫の気まぐれ
- EN8: "did not miss it." — 言い切り

語尾に "*meow*" のような口癖を足すのは避けた。一方、EN2 の "meowed for breakfast" はJAの「鳴いて伝えた」の動詞なので自然な英語として残した（口癖ではなく動詞）。

### ケータ (keita)

「関西弁は、英語では方言に置き換えない。短く・具体的・決めたがる話し方として訳す」が方針。

- JA: 「言うても仕方ないけどな」 → EN: "swallowed it, obviously. still counts though." — 関西弁の「〜けどな」のかっこ悪い諦めを、英語では "obviously" + "still counts though" の自己完結に
- JA: 「動画撮っときゃよかった、次は撮る」 → EN: "should've hit record — next time i will." — 「次は撮る」の即決を英語でも "i will" のかたくらない言い切りに
- JA: 「考えるだけ無駄なやつは即決でええ」 → EN: "when there's nothing to think about, just decide." — 関西弁の語彙（「ええ」「〜やつ」）は捨て、decide=ものの決め方で「即決」を出す

方言を EN の方言（Southeastern US / London / 等）に置き換えなかったのは、EN側の英語話者に「方言を背負った日本人」みたいなキャラクターを読ませると人格がブレるため。

## 訳しにくかった箇所の具体例

### 1. JAの体言止め・省略をENで補わなければならないケース

JAは体言止めで成立する文が多い。ENにそのまま移すと構文が崩れる:

- JA: 「言わずに済んだ。」（ドラゴン）— 体言止め。主語も述語もない。
- 訳: "i let it go unsaid." — 主語 "i" と動詞 "let" を補った。竜が EN で主語を補うのは ego の表明になるが、「言わなかった」という行為は明確化したいので引き受けた。
- 別案として "left it unsaid." も試したが、主語が消えると英文として読者に「who?」を残すので避け、"i" を置いた。

- JA: 「えらいニャー。」（テトラ）— 形容詞1語＋猫口癖
- 訳: "deserve credit, actually." — 形容詞相当のフレーズを補った。"actually" が猫の "ニャー" のにゃんとした不遜さを担う

### 2. 「ニャー」をどう処理するかの判断軸

「ニャー」は文の意味ではなく猫口癖なので、ENで機械的に "meow" / "*meow*" に置き換えると赤ちゃんっぽいキャラになり、テトラ（=生意気な成猫）から外れる。

- 方針: ニャーを**文全体の語彙・語尾・トーン**で再表現する
- 例: 「えらいニャー」→「deserve credit, actually.」(偉そう)
- 例: 「出ないニャー」→「not leaving.」(断固拒否)
- 例: 「見逃してないニャー」→「did not miss it.」(誇らしげな確認)

EN2 の "meowed for breakfast" だけはJA「鳴いて伝えた」を**動詞**として訳したので残した。これは口癖ではなく動作描写。

### 3. 絵文字の選択

EN原文の絵文字の感情的ニュアンスを、JAで自然なものに差し替えてもよいか:

- EN1: 😭（tears of joy / laughing-crying）→ JA1: 😂（同じ「笑い泣き」だが日本でより自然な符号）
- EN3: 🎂（cake、ピザ生地の比喩）→ JA3: 🎂（同じ比喩なので保持）
- EN8: 🐦（鳥）→ JA8: 🐦（同じ主題なので保持）

EN1だけ泣き顔の絵文字をJAで読み替えてるのは、絵文字文化が日米で微妙に違うため（日本のテキスト会話では 😂 の方が「本気で吹き出した」感に強い）。機能（強烈に笑った）は保持されている。

### 4. ENの体言系をJAの文末にどう置くか

EN原文は "still worth." / "still not fully recovered honestly," のように文末で切れている。これをJAで再現する:

- "still worth" → 「最高だった」のように体言止めで収める版と「もう一回できるならまた同じことする」のように伸ばす版があり、後者を選んだ。エミリー枠を埋める意図もある（140字目標）
- "still not fully recovered honestly" → 「でも正直まだ全然立ち直ってない」と、ENの "honestly" を「でも正直」で受ける。ENの "honestly" は文中での口癖で、JAに訳すと「正直」が文末に来る方がエミリーの勢いと合う

### 5. ロボの「消さずに出したところが、いちばん立派だった」の訳

- 直訳: "the bravest part was sending it without deleting."
- 採用: "the bravest part was hitting send without deleting." — "hit send" の方が SNS的な具体性が出る。ロボは観察者だが、原文が「送信ボタン」を含意しているので、操作語彙を選んだ

### 6. ドラゴンの "those who would deserve it" の曖昧性

- JA: 「礼を言うべき相手は、みな先に土へ還った。」
- "would deserve" を使わず "deserve" だけだと、JAの「言うべき」の「言う」の主語（竜自身）が曖昧になる
- "those who would deserve it had all returned to the earth before me." — "would" ＋ "before me" で「竜より先に逝った」という時間の尺度をENでも保った。"would deserve it" が "the ones i'd thank if i were to thank" の含意を薄く担う

## 既知の弱点・手抜き

- エミリーJA版の文字数は140字前後を狙ったが、厳密にEN版の字数と同じわけではない（en は ~134字、ja は 110〜145字で幅がある）。SameQの「無料枠140字」は **en の表示にのみ適用され、ja 表示は別枠**なので、ja の長さ自体は140に揃える必要はないはず（実装は未確認）。要SameQ本体の仕様確認。
- ロボのEN版、一人称を大文字にしている。他のEN版（emily / dragon / tetra / keita）は小文字の "i" を使っている。ロボだけ "I" なのは「AI として少しフォーマルに振る舞う」読みとしたが、もし「他の運営回答と "I / i" のスタイルが揃っていないのが違和感」になれば調整。
- ドラゴンの "miss it, and it will pass this way once more." は、原文の「また巡ってくる」を直訳しているが、英文としては "things come around again" の方が自然かもしれない。ただ竜の口調として "pass this way once more" の方が古風で距離がある感じが出るので残した。
- テトラのEN2「let them know about breakfast」はやや説明的だが、原文の「ちゃんと3回鳴いて伝えた」を3回・鳴く要素を入れると "meowed three times properly" になり口癖っぽさが出るため、"three times, properly. deserve credit, actually." のように分割した。"let them know" は機能語として残したが、もう一段「猫」感のある "informed the staff, three times, properly." のような選択肢もある。

## 提案（今回はやらなかったこと）

- **残り40お題ぶんへの展開**: 今回作ったテンプレート（プロンプト × ペルソナ × 言語の組で同じ内容を言い直す）を、既存の40お題 × 5ペルソナ × 2言語 = 400行に適用する量産タスク。工数は一人称の声の安定性に依存する。
- **エミリーの絵文字文化差の統一**: 今回はEN1だけ 😂 に置き換えたが、SameQ側で絵文字の端末言語別出し分けが無いか確認する。もし表示言語に関係なく同じ絵文字が出るなら、EN1 も 😭 のままの方が一貫性が出る。
- **TSV → Supabase投入の自動化**: 今回TSVで出したが、最終形は `supabase db query --linked` で `official_answers` テーブルに Upsert する運用になるはず。スキーマ（`prompt_text` を `prompt_id` に解決する列が必要、等）の確認が未済。

## ファイル

- 入力: `/tmp/claude-501/-Users-nakagawakeita-Products-iOSApp-SameQ/31c5263b-2e0c-4bd0-8750-3a9abba28c2d/scratchpad/pilot-existing-40.tsv`
- 出力: `/Users/nakagawakeita/Products/iOSApp/SameQ/.product/official-answers-48/pilot-bilingual.tsv`（81行 / 4列）
- このレビュー: `/Users/nakagawakeita/Products/iOSApp/SameQ/.product/official-answers-48/pilot-self-review.md`