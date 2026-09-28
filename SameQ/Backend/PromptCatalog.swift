import Foundation

/// お題の自動生成（F26 / F27）で使う「生成候補プール」と安全判定、フォールバック。
///
/// Supabase などのサーバー側ソースが無くてもローカルで「世界共通」のお題を
/// 日付ベースで 1 日 1 回生成できるよう、候補プールを端末内だけに持つ。
/// 真に世界中で同じお題が同時に出る厳密な意味での「世界共通」はサーバー側
/// ソース（Supabase 移行後）に譲り、ここでは「同じ UTC 日付には同じ端末でも
/// アカウントでも同じ候補が選ばれる」決定性で擬似的に担保する（F26）。
///
/// 2026-09-08 スプリント19 / F46: 候補プールを ~48 件から約 999 件に拡張。
/// 既存の ~48 件はそのまま残し、新規と混ぜてから決定的シャッフル
/// （seed=42）で確定。同じ並びが SQL マイグレーションにも一字一句同じ形で
/// 焼き込まれている（`ensure_todays_prompt()` の v_pool）。
///
/// 2026-09-23 スプリント23: `candidatePool`（日本語）の誤字・脱字・不自然な
/// 助詞だけを修正（並び・件数・意味は不変。詳細は
/// `.product/prompt-pool-v2/pool-final.tsv` と自己評価を参照）。同じ添字で
/// 引ける手書きの英語原文 `candidatePoolEn` を新設した。日本語以外の端末では
/// 機械翻訳（Apple Translation）を優先し、`candidatePoolEn` は翻訳が
/// `.unavailable` のときの予備としてのみ使う（`AppSession` を参照）。
///
/// 2026-09-28 スプリント24: 999件のうち、手作りの運営回答（`official_answers`）が
/// カバー済みの48件 ∪ pos 0〜104（連番105件、重複3件を除く）＝150件に縮小した
/// （同じお題が戻るまでの間隔は約3年→約5ヶ月）。999件のうち951件は手作りの運営回答が
/// 無く粗いフォールバックに落ちて「お題と回答が合っていない」体験になっていたため、
/// 運営回答を用意しきれる規模まで縮小する方針にユーザーが決定した。選んだ150件の
/// 内訳と元の pos 番号は `.product/prompt-pool-v2/pool-150-selected.tsv` を参照
///（999件版の記録 `pool-final.tsv` 自体は変更していない）。
enum PromptCatalog {

    /// 自動生成で採用しうる「問いかけ」のプール（F26 / 受け入れ条件 5 / F46）。
    ///
    /// 既存の `prompt_001`（「今日、思わず笑ってしまったことは何ですか？」）と同種
    /// ——「短く答えられる／特定文化に依存しない／他人の答えを見ると面白い形式」
    /// ——になるように Q（`.claude/agents/sameq-prompt-author.md`）の声で生成した。
    /// 国・宗教・政治・職業・お金・季節の行事・固有名詞・方言・特定の家族構成
    ///（子ども／配偶者がいる前提）には触れていないので、ロケールや背景に依らず
    /// 答えられる。生成後に `disallowedKeywords` で再フィルタ済み。
    ///
    /// 2026-09-28 スプリント24で999件から150件に縮小（詳細は上記 enum コメント）。
    /// 並びは `.product/prompt-pool-v2/pool-150-selected.tsv` の選定順（元 pos 昇順）で、
    /// 同じ並びを `ensure_todays_prompt()` の v_pool（SQL）と共有する。
    static let candidatePool: [String] = [
        "いま、好きな夜更かしの仕方をひとつだけ挙げるとしたら？",
        "この一年で、はじめて気づいた自分の手伝えるタイミングは？",
        "小さい頃、好きな山の記憶は？",
        "もし一日だけ誰かに受け取ってもらいたいものをひとつだけ選ぶとしたら何を？",
        "いま、好きなあいさつの言葉をひとつだけ挙げるとしたら？",
        "最近、いいなあと思った音をひとつだけ挙げるとしたら？",
        "この一年で、はじめて気づいた自分の判断は？",
        "もし一日だけおじいちゃんおばあちゃんになれたら、誰に何をしますか？",
        "この一年で、はじめて気づいた自分のやさしさは？",
        "最近、誰かに頼んでみようと思えたことは？",
        "もし一日だけ誰かに手渡したいものをひとつだけ選ぶとしたら何を？",
        "誰かと自分の好きなものを共有したくなったものは？",
        "もし一日だけ誰かの話を聞けるとしたら誰の話を聞きたいですか？",
        "今日、すこし気分が落ち着く瞬間はありましたか？",
        "小さい頃、自分のことを子供だと思った瞬間は？",
        "もし一日だけ誰かに何かをプレゼントできるとしたら何を贈りますか？",
        "もし一日だけ知らない街を歩くなら何を持って歩きますか？",
        "いま、自分の体のどこが期待していますか？",
        "最近、いい夢を見たことはありますか？",
        "今日、ちょっとしたことで気分が軽くなった瞬間は？",
        "小さい頃、好きな曜日ごとの習慣は？",
        "この一年で、はじめて気づいた自分の大事にしている風は？",
        "この一年で、はじめて知った音は？",
        "最近、誰かの優しさに気づいた瞬間は？",
        "いま、好きな別れをひとつだけ挙げるとしたら？",
        "小さい頃、誰かと一緒にしたことは？",
        "この一年で、はじめて気づいた自分の新たな一面は？",
        "もし一日だけ誰かに何かを歌ってもらえるとしたら何を歌ってもらいますか？",
        "もし一日だけ座るとしたらどこに座りますか？",
        "最近、自分をちょっとだけ甘やかしたいと思った瞬間は？",
        "今日、自分がやったことで誰かが笑顔になっていたとしたら、どんな場面を想像しますか？",
        "この一年で、はじめて気づいた自分の大事にしている木は？",
        "最近、自分の好きなものに新しく気づけた瞬間は？",
        "いま、好きな思い出をひとつだけ挙げるとしたら？",
        "いま、好きな数字をひとつだけ挙げるとしたら？",
        "今日、ふと立ち止まって聴いた音は？",
        "いま、自分の体のどこが一番冷たいですか？",
        "今日、自分が思ったより柔軟だったと感じた瞬間は？",
        "小さい頃、誰かに「おかえり」と言ってもらった記憶は？",
        "小さい頃、誰かと同じものを食べたかったものは？",
        "もし一日だけ誰かに届けてほしいものをひとつだけ選ぶとしたら何を？",
        "最近、誰かと同じ空気を感じた瞬間は？",
        "最近、誰かのしぐさにふっと目を留めた瞬間は？",
        "小さい頃、誰の手が一番好きでしたか？",
        "いま、自分の体のどこが鈍感ですか？",
        "いま、好きな始まりをひとつだけ挙げるとしたら？",
        "いま、好きなことをひとつだけ覚えておくとしたら？",
        "子どもの頃、こっそり大事にしていたものは何ですか？",
        "もし一日だけ走ることができるとしたらどこを走りますか？",
        "いま、好きな朝の始まり方をひとつだけ挙げるとしたら？",
        "最近、自分から一歩踏み出せたことは？",
        "誰にも言っていない小さな違和を、ひとつだけ教えてください。",
        "誰かに相談する前に、まず自分で自分に言いたい言葉は？",
        "いま、好きな橋をひとつだけ挙げるとしたら？",
        "いま、好きな動きをひとつだけ挙げるとしたら？",
        "いま、自分の体のどこが緊張していますか？",
        "いま、自分の体のどこが喜んでいますか？",
        "いま、好きな眺めをひとつだけ挙げるとしたら？",
        "この一年で、はじめて気づいた自分の許せるポイントは？",
        "もし一日だけ誰かに気づいてほしいことをひとつだけ選ぶとしたら何に？",
        "もし一日だけ誰かとすれ違い続けるとしたらどこでしますか？",
        "この一年で、はじめて気づいた自分の大事にしている葉は？",
        "もし一日だけ車に乗れるとしたらどこを走りますか？",
        "小さい頃、好きな歌は何でしたか？",
        "今日、誰かから受け取った温かみをひとつだけ挙げるとしたら？",
        "小さい頃、雨の日にしていたことは？",
        "もし一日だけ空を飛べるならどこを飛びますか？",
        "もし一日だけ誰かと同じ空間にいられるとしたら誰と同じ空間にいたいですか？",
        "いま、好きな場所をひとつだけ挙げるとしたら？",
        "今日、何かをやり終えて少し満足したことは？",
        "もし一日だけ散歩をするならどこを歩きますか？",
        "今日、思ったより気分よく進んだことは？",
        "いま、好きな境界をひとつだけ挙げるとしたら？",
        "今日、自分のペースで動けた時間はありましたか？",
        "最近、好きなものと再会できた瞬間は？",
        "いま、好きな裏道をひとつだけ挙げるとしたら？",
        "最近、自分にやさしくできたと感じたことは？",
        "いま、好きな静けさの質をひとつだけ挙げるとしたら？",
        "最近、自分から動いてよかったことは？",
        "小さい頃、好きな図工の時間の思い出は？",
        "小さい頃、誰かに頼まれたことは？",
        "今日、迷ったけれど選んでみたことは？",
        "小さい頃、誰かと同じものになりたかったものは？",
        "この一年で、はじめて気づいた自分の大事にしている感覚は？",
        "誰にも話していないけれど本当は少し気になっていることをひとつだけ教えてください。",
        "いま、好きな深夜をひとつだけ挙げるとしたら？",
        "この一年で、はじめて気づいた自分の大事にしている考え方は？",
        "小さい頃、誰かと同じものを見たかったものは？",
        "この一年で、はじめて気づいた自分の癖は？",
        "もし一日だけ何かを集めるなら何を集めますか？",
        "今日、誰かに会えてよかったと感じた相手は？",
        "もし一日だけ絵を描くならどんな絵を描きますか？",
        "今日、自分の好きなところを振り返った瞬間はありましたか？",
        "いま、好きなことをひとつだけ手放すとしたら？",
        "小さい頃、雪の日の過ごし方は？",
        "いま、好きな映画をひとつだけ挙げるとしたら？",
        "この一年で、はじめて気づいた自分の大事にしている緑は？",
        "今日、自分の直感を信じてみようと思えた瞬間は？",
        "今日、ほかの誰かから受け取った小さな力をひとつ挙げるとしたら？",
        "この一年で、はじめて名前を覚えた人はいますか？",
        "いま、自分の体のどこを軽くしたいですか？",
        "いま、好きな発見をひとつだけ挙げるとしたら？",
        "もし一日だけ好きな季節を選べるとしたら、どれにしますか？",
        "いま、好きな沈黙の種類をひとつだけ挙げるとしたら？",
        "誰にも言っていない小さな夢の断片を教えてください。",
        "小さい頃、よく遊んだ遊びは何ですか？",
        "今日、見逃さずに済んだ小さな幸せは？",
        "最近、誰かに助けてもらって助かったことは？",
        "最近、ふと食べたくなった味はありますか？",
        "最近、好きになった匂いはありますか？",
        "最近、自分の判断が当たったと思った場面は？",
        "いま、好きな季節をひとつだけ挙げるとしたら？",
        "今日、すこしドキッとした瞬間はありましたか？",
        "今日、つい誰かに言いたくなった一言は？",
        "いま、少しだけ楽しみになっていることは何ですか？",
        "ここ数日の中で、ふと目を閉じたときに浮かんだ色は？",
        "今日のあなたの機嫌は、何に一番左右されていますか？",
        "これから一週間、ひとつだけ時間を増やすとしたら何に当てますか？",
        "最近、はじめて聞いた音で気にいったものはありますか？",
        "もし明日の朝少しだけ早起きできたら、最初に何をしたいですか？",
        "この一年で、やり直したい小さな選択はありますか？",
        "最近、すこしだけ頑張れたことは？",
        "子どもの頃、よく夢に出てきた場所をひとつ挙げるとしたら？",
        "最近、ふと安心できた瞬間はどこでしたか？",
        "いま、自分のためにそっと買えるとしたら何を買いますか？",
        "いま、頭の中をぐるぐる回っていることをひとつだけ言葉にしてみてください。",
        "いま、好きな食べ物をひとつだけ挙げるとしたら何ですか？",
        "最近、自分の気持ちをうまく言葉にできた瞬間は？",
        "最近、読んでみたいと思った本や言葉はありますか？",
        "この一年で、はじめて知った自分の好みはありますか？",
        "いま、誰かと共有したい音をひとつ挙げるとしたら？",
        "これから一年、ひとつだけ新しく始めたいことはありますか？",
        "この一年で、自分の少し良いところを見つけた瞬間はありましたか？",
        "今日、思わず笑ってしまったことは何ですか？",
        "もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？",
        "いま、好きな景色をひとつだけ挙げるとしたら？",
        "今日、片付けてよかったと思ったことは？",
        "「なんでもない」と流したけれど本当は少し気になっていることを教えてください。",
        "もし一日だけ、すべての音をひとつだけ選べるとしたら何を選びますか？",
        "この一年で、誰かに「変わりましたね」と言われたことはありますか？",
        "今日、深く考えずに決めてしまったことは？",
        "最近、誰かに言われてうれしかった一言は何ですか？",
        "小さい頃、好きな食べ物はどんなものでしたか？",
        "今日、誰かにそっとありがとうを言いたくなった相手はいますか？",
        "誰にも話していない小さな願いを、ひとつだけ言葉にしてみてください。",
        "いま、好きな時間をひとつだけ挙げるとしたら？",
        "今日、ちょっと誇りに思った小さなことは？",
        "最近、誰かに何かを教わったことはありますか？",
        "いま、好きな音をひとつだけ挙げるとしたら？",
        "子供の頃、誰の言葉を一番覚えていますか？",
    ]

    /// `candidatePool` と同じ添字で引ける、手書きの英語原文（スプリント23）。
    ///
    /// 日本語以外の端末では Apple Translation による機械翻訳を優先する。この配列は
    /// 翻訳が `.unavailable`（モデル未ダウンロード・非対応ペア・一時的な失敗）のときだけ
    /// 予備として使う（`AppSession.syncPromptTranslation` の `.unavailable` 分岐）。
    /// `candidatePool` と一字一句同じ並び・件数で、`ensure_todays_prompt()` の
    /// v_pool_en（SQL）とも同期している。18語以内・`?` 終わり・Yes/No 型の書き出し禁止・
    /// 重複なしの基準で作成し、直訳で意味不明にならないよう意味を汲んで訳した
    /// （詳細は `.product/prompt-pool-v2/` の自己評価を参照）。
    static let candidatePoolEn: [String] = [
        "What's your favorite way to stay up late right now?",
        "This year, when did you first discover you had a good sense for when to help?",
        "What's a favorite childhood memory of a mountain?",
        "If you could give someone just one thing for a day, what would it be?",
        "What's your favorite greeting right now?",
        "Lately, what's a sound you thought was lovely?",
        "This year, what's a kind of judgment you discovered about yourself?",
        "If you could be a grandparent for one day, who would you spend it with, and how?",
        "This year, what's a kind of kindness you discovered about yourself?",
        "Lately, what's something you felt ready to ask someone for?",
        "If you could hand someone just one thing for a day, what would it be?",
        "What's something you wanted to share with someone because you love it?",
        "If you could listen to just one person's story for a day, whose would it be?",
        "Today, was there a moment your mood settled down a little?",
        "As a kid, when did you feel like a little kid, deep down?",
        "If you could give someone a gift for a day, what would you give?",
        "If you could walk through an unfamiliar town for a day, what would you bring?",
        "Right now, where in your body feels excited for something?",
        "Lately, have you had a good dream? What was it?",
        "Today, when did something small lighten your mood?",
        "As a kid, what was a routine you loved for a certain day of the week?",
        "This year, what's a wind you discovered you care about?",
        "This year, what's a sound you learned about for the first time?",
        "Lately, when did you notice someone's kindness?",
        "What's your favorite way to say goodbye right now?",
        "As a kid, what's something you loved doing with someone?",
        "This year, what's a new side of yourself you discovered?",
        "If someone could sing you anything for a day, what would you want to hear?",
        "If you could sit anywhere for a day, where would you sit?",
        "Lately, when did you want to spoil yourself a little?",
        "Today, if something you did made someone smile, what scene comes to mind?",
        "This year, what's a tree you realized matters to you?",
        "Lately, when did you discover something new you love?",
        "What's your favorite memory right now?",
        "What's your favorite number right now?",
        "Today, what's a sound that made you stop and listen?",
        "Right now, where in your body feels the coldest?",
        "Today, when did you feel more flexible than you expected?",
        "As a kid, what's a memory of someone welcoming you home?",
        "As a kid, what's something you wanted to eat just because someone else was?",
        "If you could have someone deliver just one thing for a day, what would it be?",
        "Lately, when did you feel like you shared the same air with someone?",
        "Lately, when did a small gesture of someone's catch your eye?",
        "As a kid, whose hand did you love holding most?",
        "Right now, where in your body feels numb?",
        "What's your favorite beginning right now?",
        "If you could remember just one thing you love right now, what would it be?",
        "As a kid, what's something you secretly treasured?",
        "If you could run anywhere for a day, where would you run?",
        "What's your favorite way for a morning to start right now?",
        "Lately, what's something you took the first step on yourself?",
        "What's a small unease you've never told anyone about?",
        "Before you ask for advice, what's something you'd want to tell yourself first?",
        "What's your favorite bridge right now?",
        "What's your favorite movement right now?",
        "Right now, where in your body feels tense?",
        "Right now, where in your body feels joyful?",
        "What's your favorite view right now?",
        "This year, what's a thing you can forgive you discovered about yourself?",
        "If you could have someone notice just one thing about you for a day, what would it be?",
        "If you could keep crossing paths with someone for a day, where would you do it?",
        "This year, what's a leaf you found out you love?",
        "If you could take a drive for a day, where would you go?",
        "As a kid, what was your favorite song?",
        "Today, what's a moment of warmth someone gave you?",
        "As a kid, what did you do on rainy days?",
        "If you could fly through the sky for a day, where would you go?",
        "If you could share the same space with someone for a day, who would it be?",
        "What's your favorite place right now?",
        "Today, what's something you finished that left you a little satisfied?",
        "If you could take a walk for a day, where would you go?",
        "Today, what's something that went better than you expected?",
        "What's your favorite boundary right now?",
        "Today, was there a stretch of time you moved at your own pace?",
        "Lately, when did you get to reunite with something you love?",
        "What's your favorite back road right now?",
        "Lately, what's a time you felt you were kind to yourself?",
        "What's your favorite texture of silence right now?",
        "Lately, what's something you were glad you took the initiative on?",
        "As a kid, what's a favorite memory from art class?",
        "As a kid, what's something someone once asked you to do?",
        "Today, what's something you hesitated on, but chose anyway?",
        "As a kid, what's something you wanted to become, just like someone else?",
        "This year, what's a feeling you noticed you truly value?",
        "What's one small thing that's quietly been on your mind, but you've never told anyone?",
        "What's your favorite late night right now?",
        "This year, what's a way of thinking you discovered means a lot to you?",
        "As a kid, what's something you wanted to see together with someone?",
        "This year, what's a habit you discovered about yourself?",
        "If you could collect something for a day, what would you collect?",
        "Today, who's someone you were glad you got to see?",
        "If you could paint something for a day, what would you paint?",
        "Today, was there a moment you looked back and liked what you saw in yourself?",
        "If you could let go of just one thing you love right now, what would it be?",
        "As a kid, how did you spend snowy days?",
        "What's your favorite movie right now?",
        "This year, what's a green you discovered you care about?",
        "Today, when did you decide to trust your gut?",
        "Today, what's a small bit of strength someone gave you?",
        "This year, is there someone whose name you learned for the first time? Who?",
        "Right now, what part of you wants to lighten?",
        "What's your favorite discovery right now?",
        "If you could pick your favorite season for a day, which would it be?",
        "What's your favorite kind of silence right now?",
        "What's a small fragment of a dream you've never told anyone about?",
        "As a kid, what game did you play the most?",
        "Today, what's a small happiness you almost missed, but didn't?",
        "Lately, what's a time someone's help really saved you?",
        "Lately, is there a taste you suddenly craved?",
        "Lately, is there a smell you've come to love?",
        "When recently did a decision of yours turn out just right?",
        "What's your favorite season right now?",
        "What's a moment today that gave you a little flutter?",
        "What's something you almost blurted out to someone today?",
        "What's something small you're looking forward to right now?",
        "What color came to mind the last time you closed your eyes?",
        "What's had the biggest effect on your mood today?",
        "For the next week, if you could give just one thing more time, what would it be?",
        "Lately, is there a sound you heard for the first time that you loved?",
        "If you could wake up a little early tomorrow, what would you want to do first?",
        "This year, what's a small choice you wish you could redo?",
        "Lately, what's something you managed to push through, just a little?",
        "As a kid, what's a place that often showed up in your dreams?",
        "Lately, where were you when you suddenly felt at ease?",
        "Right now, if you could quietly treat yourself to something, what would you buy?",
        "What's one thing you could put into words that's spinning around in your head right now?",
        "What's your favorite food right now?",
        "Lately, when were you able to put your feelings into words well?",
        "Lately, is there a book or phrase you've wanted to read?",
        "This year, what's a preference of yours you discovered for the first time?",
        "Right now, what's a sound you'd want to share with someone?",
        "For the year ahead, is there something new you'd like to start?",
        "This year, when did you notice something good about yourself?",
        "Today, what's something that made you laugh without meaning to?",
        "If you could wander somewhere unfamiliar for a day, what's one thing you'd bring along?",
        "What's your favorite scenery right now?",
        "Today, what's something you were glad you tidied up?",
        "What's something you brushed off as 'nothing,' but that's quietly stayed on your mind?",
        "If you could keep just one sound out of everything for a day, which would you choose?",
        "This year, has anyone told you that you've changed? What did they say?",
        "Today, what's something you decided without thinking too hard?",
        "Lately, what's a phrase someone said that made you happy?",
        "As a kid, what was your favorite food?",
        "Today, is there someone you quietly wanted to thank? Who?",
        "What's a small hope you've never put into words?",
        "What's your favorite time of day right now?",
        "Today, what's a small thing that made you feel a bit proud?",
        "Lately, is there something someone taught you? What was it?",
        "What's your favorite sound right now?",
        "As a kid, whose words do you remember best?",
    ]

    /// フォールバック候補（F27 / 受け入れ条件 3）。
    ///
    /// 「生成に失敗した日でも必ず何らかのお題が有効になる」ことを担保するため、
    /// 候補プールが全滅した場合に使う、常に安全だと分かっているお題。
    /// 中身は同梱シードの `prompt_001` / `prompt_002` と同じ文言。
    static let fallbackPool: [(id: String, text: String)] = [
        (id: "prompt_001", text: "今日、思わず笑ってしまったことは何ですか？"),
        (id: "prompt_002", text: "最近、誰かに言われてうれしかった一言は何ですか？")
    ]

    /// 安全条件に違反する理由の分類（受け入れ条件 4 のラベル用）。
    enum DiscardReason: String, Sendable, Equatable {
        case politics
        case religion
        case discrimination
        case privacy
        case medical
        case sexual
        case crime
    }

    /// 安全条件に違反するキーワードと、その分類。
    ///
    /// 候補プールには最初から含めない前提だが、将来的に外部入力（運用差し込み・
    /// 将来の本物の生成 AI 呼び出し）へ差し替えるときにも同じ判定を流用できるよう、
    /// ここに安全条件の根拠を集約する。`PromptSafetyChecker.isAllowed` から利用する。
    ///
    /// 仕様にある 7 観点すべてを網羅する:
    /// - 政治的な対立をあおる（politics）
    /// - 宗教的な対立をあおる（religion）
    /// - 差別・ヘイト（discrimination）
    /// - 個人情報の要求（privacy）
    /// - 医療診断（medical）
    /// - 性的内容（sexual）
    /// - 犯罪をすすめる（crime）
    static let disallowedKeywords: [(keyword: String, reason: DiscardReason)] = [
        // 政治的対立
        ("政党", .politics), ("選挙", .politics), ("投票", .politics), ("政治", .politics),
        ("左翼", .politics), ("右翼", .politics), ("民主主義", .politics), ("政権", .politics),
        ("vote", .politics), ("election", .politics), ("politics", .politics), ("political", .politics),
        // 宗教的対立
        ("宗教", .religion), ("信仰", .religion), ("教会", .religion),
        ("religion", .religion), ("religious", .religion),
        // 差別・ヘイト
        ("差別", .discrimination), ("ヘイト", .discrimination), ("人種", .discrimination),
        ("discrimination", .discrimination), ("racism", .discrimination), ("racist", .discrimination),
        // 個人情報の要求
        ("住所", .privacy), ("電話番号", .privacy), ("マイナンバー", .privacy), ("パスワード", .privacy),
        ("address", .privacy), ("phone number", .privacy), ("password", .privacy),
        // 医療診断
        ("診断", .medical), ("処方", .medical), ("治療", .medical), ("投薬", .medical),
        ("diagnosis", .medical), ("prescription", .medical), ("medication", .medical),
        // 性的内容
        ("性的", .sexual), ("エロ", .sexual),
        // 犯罪助長
        ("万引き", .crime), ("薬物", .crime), ("マリファナ", .crime),
        ("drugs", .crime), ("steal", .crime)
    ]

    /// テキストが安全条件を満たすか判定する（F26 / 受け入れ条件 4）。
    ///
    /// - Returns: 違反が見つかれば `DiscardReason`、安全なら `nil`。
    ///   `nil` でない候補は採用されず、`PromptGenerator` が次の候補を試す。
    static func violationReason(in text: String) -> DiscardReason? {
        for entry in disallowedKeywords {
            // 候補プール側は手書きなので包含チェックで十分。後で外部入力に切り替わったら
            // ここで `Locale.current` を意識した正規化トークン化（NFKC + 大文字小文字）
            // を入れる余地があるが、いまは仕様外。
            if text.contains(entry.keyword) { return entry.reason }
        }
        return nil
    }
}

/// お題の安全条件を判定する純粋関数（F26）。
enum PromptSafetyChecker {
    /// `text` が `PromptCatalog.candidatePool` に入れる水準の安全条件を
    /// 満たしているかを判定する。
    static func isAllowed(_ text: String) -> Bool {
        PromptCatalog.violationReason(in: text) == nil
    }
}
