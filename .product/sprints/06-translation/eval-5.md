# スプリント 06 評価（attempt 5） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 5/7 達成・**条件4 未達**・条件7 評価不能 | 100% | ✗ |
| 2 安定性 | クラッシュ0 / アプリ由来の未処理エラー0 / 主要動線は完走 | クラッシュ0・完走 | ✓ |
| 3 データ整合性 | 実機・シミュレータとも既読の永続・再起動後の保持が設計どおり | 100% | ✓ |
| 4 回帰 | 抜き取り5件すべて ✓ ＋ シミュレータのフルスイート 107/107 | 100% | ✓ |
| 5 使用性 | **2**（投稿直後に60秒、タイムラインを開くたびに61秒の無反応） | 3以上 | ✗ |

**不合格。** 落ちたのは基準1（受け入れ条件4）と基準5（使用性）。
根本原因は同じ1つで、**`openTimeline()` の前に置いた能動的モデルダウンロードが、
ダウンロードが完了しなかった場合に「毎回・無期限に」60〜120秒の待ちを作り、
しかもその言語は結局読めるようにならない**こと。

---

## 検証環境

- コミット `3819870`（attempt 5）。**本体コードは1行も変更していない**
  （evaluator の一時テストのみ追加し、確認後に削除・`xcodegen generate` で復元済み）
- **実機**: iPhone 17 Pro Max / `B7121EA8-8AED-5E66-B696-511BFFC729E2` / iOS 26.6 / 端末言語 `ja-JP`
- シミュレータ: iPhone 17 / `12050FBD-587B-4910-8812-696BB91BE051`（iOS 26.5）/ 端末言語 `ja-JP`
- 実施 2026-08-20 04:46〜05:30 JST
- evaluator の一時テスト（削除済み）
  - `SameQTests/EvalSixFiveDeviceTests`（P1 / R1）: 実機の `LanguageAvailability` 実測、
    実ウインドウに載せた本物の `TranslationHostView` 経由での `openTimeline()` 2回計測
  - `SameQTests/EvalSixFiveRepeatWaitTests`: `.supported` のまま変わらない言語での
    `openTimeline()` の待ち時間を、タイムアウトを縮めて確定的に3回計測
  - `SameQUITests/EvalSixFiveManualTests` / `EvalSixFiveMarginSwipeTests`: シミュレータでの実操作＋スクショ

### 【最重要】今回もっとも見てほしかった「指でのタップ確認」はできていない

依頼のあった「OSのダウンロード確認シートが実際に出るか、タップして進めるか、
そのあと `fullScreenCover` が正しく開くか」は、**今回も確認できていない**。理由:

- **実機の画面がロックされている**。XCUITest は2回とも
  `Timed out while enabling automation mode.` で失敗し、xcodebuild のログに直接の原因が出ていた:
  ```
  Failed to start remote service "com.apple.mobile.notification_proxy" on device.
  Error Domain=com.apple.dt.MobileDeviceErrorDomain Code=-402653158
  "The device is passcode protected." (MobileDeviceErrorCode=0xE800001A)
  ```
- 原因調査の結果、**「デベロッパモード」は原因ではない**（`devicectl device info details` が
  `developerModeStatus: enabled` を返す）。信頼関係も生きている（`connected`、ビルド・インストール・
  ユニットテスト実行はすべて成功する）。**残る原因は画面ロックのみ**。
  `devicectl` の `lockState` は eval-3・eval-4 と同様、施錠中でも `passcodeRequired: false` /
  `unlockedSinceBoot: true` を返し続けるため判定材料にならない
- パスコードの入力は evaluator が行わない（資格情報の入力に当たるため）。
  `devicectl` は実機のスクリーンショット取得に対応しておらず、画面を見る手段も無い

そのため今回も、**ホストアプリのプロセス内で本物の翻訳経路を動かす**方法で検証した。
指の操作の代わりに `openTimeline()` / `advanceTimeline()` を直接呼ぶが、翻訳・
モデル準備・スキップ・既読の実処理はすべて本番と同じ経路を通る。
画面操作そのものはシミュレータで実施した。

**ユーザーへのお願い**: 次回の実機確認までに、iPhone のロックを解除し
「設定 > 画面表示と明るさ > 自動ロック」を **なし** にしておいてほしい。
それだけで XCUITest による指のタップ確認ができるようになる。

---

## 実機での実測（本物の Apple Translation Framework）

### この実機のモデル状況（`LanguageAvailability` を1言語ずつ実測、2026-08-20 04:52）
```
target=ja-JP
ja unsupported / en installed / ko installed / es installed / zh installed
pt installed / it installed / fr installed / de installed / ar installed
tr installed / ru installed / nl installed
th supported   ← 未ダウンロード
pl supported   ← 未ダウンロード
id supported   ← 未ダウンロード
zxx unsupported / qtd unsupported
```

### `openTimeline()` の所要時間（本物の翻訳・ウインドウ実装込み・2回）
```
（投稿 submit() の内部の openTimeline）  約 60 秒
round1 openTimeline 62.1s  準備中を観測=yes → 27件を10.3秒で読み切り
       既読=30 未読=2 未読言語=[pl, th]  alertMessage=nil
round2 openTimeline 61.3s  準備中を観測=yes → 表示0件のまま即「読み切り」
       既読=30 未読=2 未読言語=[pl, th]  alertMessage=nil
テスト全体 195.98 秒（= 60 + 62 + 10 + 61 とほぼ一致）
```

翻訳そのものは良好だった（27件すべて自然な日本語。原文のまま出たものは0件）:
- 仏語 →「私の隣人は毎朝シャワーを浴びているときに偽歌を歌っています。…」
- 伊語 →「後ろの方から誰かに挨拶している人に手を振って挨拶した。…」
- 露語 →「今日は、電子レンジで『こんにちは』を3回言いました。…」
- 아랍어 →「店のドアを開けようとし、3回押したところ、大きな文字で『プル』と書かれていました」

---

## 不合格の原因（これを直せば通る）

### [1] モデル未ダウンロードの言語が候補に残っているあいだ、タイムラインを開くたびに毎回60〜120秒待たされる（受け入れ条件4の後半・spec.md 197行）

- **再現手順（実機）**:
  1. 端末に翻訳モデルが無い言語（この実機では日本語端末で `pl` と `th`）の回答を含む
     同梱シードでアプリを起動し、初回設定を済ませて回答を投稿する
  2. 「投稿する」を押す → **ボタンが「送信中…」のまま約60秒間、画面が変化しない**
     （`AppSession.submit()` が内部で `openTimeline()` を呼ぶため。`SameQ/Session/AppSession.swift:225`）
  3. タイムラインが開いたら最後まで読み切って閉じる
  4. もう一度「世界の回答を読む」を押す → **ボタンが「準備中…」になって無効化され、
     約61秒間その状態が続く**。61秒後に開いたタイムラインは「今は新しい回答がありません」
     （新しく読める回答は0件）
  5. 3回目・4回目も同じだけ待たされる（`pl` / `th` が未読で `.supported` のまま残る限り無期限）
- **期待**（spec.md 197行）: 「翻訳モデルが端末に無い場合は初回のみ準備中の表示が出て
  完了後に読め、**同じ端末で2回目以降は待ちが発生しない**」
- **実際**: 2回目も 61.3 秒待たされた。しかも待った結果、新しく読める回答は0件だった
- **根拠1（実機・実測）**: 上記「`openTimeline()` の所要時間」。round1 62.1s / round2 61.3s
- **根拠2（確定的なユニット検証）**: `LanguageAvailabilityProviding` を
  「`pl` は常に `.supported`（ダウンロードしても変わらない）」に差し替え、
  `sessionAcquireTimeoutSeconds` を 1.0 秒に縮めて `openTimeline()` を3回呼ぶと、
  **3回とも同じだけ待つ**（本番ではこの 1.0 秒が 45 秒、さらに `session.translate` の
  30秒・`prepareTranslation` の 60秒が乗る）:
  ```
  round1 openTimeline 1.01s content=exhausted
  round2 openTimeline 1.01s content=exhausted
  round3 openTimeline 1.01s content=exhausted
  ```
- **原因（症状とは分けて書く・推測）**: `AppSession.prepareTimelineLanguagesIfNeeded`
  （`SameQ/Session/AppSession.swift:265`）にも `Translator.prepareIfNeeded`
  （`SameQ/Backend/Translator.swift:303`）にも、**「この言語は既に試して駄目だった」を
  覚える場所が1つも無い**。`Translator.statusCache` は意図的に `.supported` を
  キャッシュしない設計なので、毎回ゼロから同じ試行を繰り返す。
  直す方向としては、(a) 1プロセス（あるいは1日）に1回だけ試す、
  (b) 準備をタイムラインの表示と並行させて `openTimeline()` を待たせない、
  (c) 待ち時間の上限をもっと短くする、のいずれか（またはその組み合わせ）

### [2] 受け入れ条件4の前半（準備中→完了後に読める）が、実機で一度も成立していない

- **再現手順**: [1] と同じ。読み切ったあとに `pl` / `th` の回答が読めるようになったか見る
- **期待**（spec.md 197行）: 「翻訳モデルが端末に無い場合は**初回のみ準備中の表示が出て
  完了後に読め**」
- **実際**: 準備中の表示（「準備中…」）は出るようになった（attempt 4 からの前進）が、
  **60秒待ったあとも `pl` / `th` は `.supported` のまま**で、その回答は読めるようにならない。
  2回のランとも未読は `pl` / `th` の2件で、attempt 4 の結果と同じ
- **根拠**: 上記「`openTimeline()` の所要時間」の `未読言語=[pl, th]`。
  および評価後に再度実測した `LanguageAvailability`（`th` / `pl` / `id` とも `.supported` のまま）
- **generator の自己評価にある唯一の肯定的証拠（`id` が実際にダウンロードされて読めるようになった）は成立しない**:
  - `id`（インドネシア語）の回答は同梱シードの **`prompt_002` にしか無い**。
    いま有効なお題は `prompt_001` で、その候補32件の言語は
    `[ar, de, en, es, fr, it, ja, ko, nl, pl, pt, qtd, ru, th, tr, zh, zxx]` ＝ **`id` を含まない**
    （実機で `backend.timelinePosts(promptID:)` を直接読んで確認。generator の申告した
    「候補32件」も同じ `prompt_001` を指している）
  - さらに `id` は評価時点でも `.supported`（未ダウンロード）のままで、
    **一度もインストールされていない**
  - つまり「候補32件中30件が既読、未読は `pl`/`th` のみ」という観測結果は、
    `id` のダウンロード成否とは無関係に成り立つ。**受け入れ条件4が働いた実例は、
    実機でまだ1件も観測されていない**
- **未確認（正直に書く）**: この実機は施錠中のため、OSの確認シートが表示できず
  （システムログに `[ProcessScene] ... Scene creation failed: FBWorkspaceScene code 2
  ("scene-creation-failed")` が157件、`[ExtensionXPC] Connection interrupted` が多数）、
  ダウンロードが始まらなかった可能性が高い。**画面のロックを解除した実機で、
  人が確認シートに応答すればダウンロードが完了して条件4が成立する可能性は残っている**。
  ただしその場合でも [1]（応答しなかった／拒否した利用者が毎回60〜120秒待たされる）は解消しない

### [3] 使用性: 60秒間、画面が「送信中…」「準備中…」のまま何も起きない（基準5 = 2点）

- **再現手順**: [1] の手順2・4
- **期待**: 主要動線の途中で「何が起きているか分からない瞬間」が無いこと
- **実際**:
  - 「投稿する」を押した直後、ボタンが「送信中…」に変わったまま**約60秒**動かない。
    進捗表示（`ProgressView`）も、何を待っているかの説明も、中断する手段も無い。
    利用者から見れば「投稿が固まった」としか見えない
  - 「世界の回答を読む」を押すと、ボタンが「準備中…」になって無効化され**約61秒**動かない。
    2回目以降も同じで、しかも61秒待った先が「今は新しい回答がありません」であることがある
  - `timelinePreparationBudgetSeconds` は 90 秒だが、**この上限は各言語を開始する前にしか
    見られない**ため、未ダウンロードの言語が2つあると最大で 60 + 60 = **120 秒**まで伸びうる
    （`SameQ/Session/AppSession.swift:278-281`）
- **採点**: 2（完走はできるが、途中で何が起きたか分からない瞬間がある）。閾値 3 を下回る

---

## 受け入れ条件ごとの確認結果

| # | 条件（spec.md 194〜201行） | 判定 | 根拠 |
|---|---|---|---|
| 1 | 端末言語と異なる言語の回答が端末言語で表示される | ✓ | 実機の本物の翻訳で27件を読み切り。仏・西・葡・英・伊・土・韓・蘭・露・中・アラビア語がすべて自然な日本語に。原文のまま出た回答は0件 |
| 2 | 翻訳ボタン・原文表示・切替・「翻訳済み」表示・投稿言語ラベルが1つも存在しない | ✓ | シミュレータでタイムラインの全ラベルを列挙。`["Go Down", "Vertical scroll bar", "あなたの回答", "いいね", "お題", "この回答を通報またはブロック", "スワイプすると、次の知らない誰かへ", "世界の回答", "世界の回答を読む", "今日、思わず笑ってしまったことは何ですか？", "今日のお題", …, "設定", "閉じる", "🌙", "🍄"]`。「翻訳」「原文」「Translate」「Original」および言語名は0件。ボタンも `timeline.close` / `timeline.more` / `timeline.like` / `settings.open` / `today.openTimeline` のみ |
| 3 | 翻訳できない言語の回答は一度も現れず、スワイプで次が表示される | ✓ | `zxx`（検証用マーカー）は実機・シミュレータの全ランで0回表示。スキップ分は黙って消えず次の回答に置き換わる |
| 4 | モデル未取得時は初回のみ準備中表示、2回目以降は待たない | ✗ **未達** | 上記 [1][2]。前半は実機で一度も成立せず（`id` の実例は成立しない）、後半は 61.3 秒の待ちを実測 |
| 5 | お題も端末言語で表示され、言語設定を変えて起動し直すとその言語になる | ✓ | 実機（ja）で `今日、思わず笑ってしまったことは何ですか？`。英語端末の確認はシミュレータのフルスイート（`AppSessionTranslationTests` / `SprintSixAcceptanceTests.test02`）で通過 |
| 6 | 翻訳に失敗した回答はエラーダイアログを出さず、スキップして次を表示する | ✓ | 実機の全ランで `alertMessage` は nil、アプリのアラート0件。`pl`/`th` は黙ってスキップされる |
| 7 | 機内モードでもモデル取得済み言語なら翻訳表示できる | 評価不能 | 端末設定の変更にあたるため evaluator は実施しない。**ユーザー自身に1度確認してほしい**（attempt 3 から持ち越し） |

---

## 安定性・データ整合性・回帰

### 安定性（✓）
- **クラッシュ0**。実機・シミュレータともプロセスは全ラン生存
- アプリ由来の未処理エラー0。実機の全ランで `alertMessage` は nil、アラート0件
- attempt 2 の `Attempted to use TranslationSession after the view…` は0回
- OS 側のログには `[ProcessScene] Scene creation failed`（157件）と
  `[ExtensionXPC] Connection interrupted` が多数出ていた。これは Translation の UI 拡張が
  アプリ内にシーンを立てようとして失敗したもので、**施錠中の実機という環境要因の可能性が高い**。
  アプリの処理は継続し、画面には何も出ない
- 主要動線（初回設定 → 投稿 → タイムライン → 読み切り → 再起動）はシミュレータで最後まで完走

### データ整合性（✓）
- 実機: 読み切り後の既読=30 / 候補=32。**恒久的に翻訳できない `zxx`・`qtd` は既読になり、
  モデル未ダウンロードの `pl`・`th` は既読にならない**（一時的失敗として次回また試される）。設計どおり
- シミュレータ: 読み切り後 `answers 32 · viewed 32`。アプリを終了して再起動しても
  `viewed 32` と自分の回答（`今日は評価者がアプリを触りました。`）が保持され、既読の再登場は0件
- 翻訳結果は永続化されない（`state.json` に入るのは自分の書いた原文だけ）

### 回帰（✓ 抜き取り5件 ＋ フルスイート 107/107）
シミュレータでの実操作（`-SameQFakeTranslate`）:
1. **未投稿のあいだタイムライン導線が無い**（スプリント01/03）✓
   「🔒 世界の回答はまだ見られません / あなたが答えると、知らない誰かの言葉が1件ずつ見えるようになります。」
2. **空白・改行だけの投稿は拒否され、日英併記のダイアログが出る**（スプリント05）✓
   `うまくいきませんでした / Something went wrong` ＋
   `空白や改行だけの回答は投稿できません。 You can't post a reply that's only blank space or line breaks.`
3. **BAN状態のアカウントで起動するとボタンが1つも無い画面に固定される**（スプリント05）✓
   ボタン数=0、`🚫` / `このアカウントは利用できません` / `This account can no longer be used` ＋ 日英併記の説明
4. **カード外の余白のスワイプで次へ進む・✕ボタンが無い・いいねボタンが 82×82pt**（直前のUI調整）✓
   カード下端(516.7pt)といいねボタン上端(676pt)の中間 y=596.3pt で左スワイプ →
   `[JA] My cat tr…` から `[JA] Pomyliłem…` に切り替わることを確認
5. **タイムラインにお題が常設表示される**（直前のUI調整）✓ 「お題 今日、思わず笑ってしまったことは何ですか？」
- **シミュレータのフルテストスイート 107/107 全件成功**（他の xcodebuild が動いていないことを
  確認したうえで単独実行。所要 1141 秒。generator の申告と一致）

### 回帰確認の注意（テストの有効性について）
`SprintSixAcceptanceTests.test04_allCandidatesEventuallyBecomeViewedAfterActiveModelDownload`
（attempt 5 で追加された、条件4を守るためのテスト）は、**シミュレータでは常に無条件に通る**。
このシミュレータの `LanguageAvailability` は全18言語に対して `.unsupported` を返すため
（evaluator が実測）、すべての回答が「恒久的に翻訳できない」扱いで既読になり、
`viewed == answers` が自明に成立する。**`.supported`（モデル未ダウンロード）の経路には
一度も入らない**。107/107 という数字は、条件4については何も保証していない。

---

## 改善提案（合否には影響しない）
- **[優先度 高]** `submit()` が内部で `openTimeline()` を待つ構造をやめる（投稿の完了と
  タイムラインを開く待ちを分ける）。いまは投稿ボタンが最大120秒「送信中…」のままになる
- **[優先度 高]** 準備中の表示に `ProgressView` と「翻訳の準備をしています」程度の説明を足す。
  無効化されたボタンのラベルが変わるだけでは、固まったのか進んでいるのか区別できない
- **[優先度 中]** 翻訳できずスキップした件数がある場合の読み切り表示を、通常の読み切りと
  分ける（eval-1 から継続・未対応）
- **[優先度 中]** `AppSession.prepareTimelineLanguagesIfNeeded` の `guard !languages.isEmpty`
  は「未読の回答の言語が1つでもあれば」で真になるため、**全言語がインストール済みでも
  `isPreparingTimeline` が一瞬 true になる**。self-review.md の
  「ダウンロード対象が1件も無ければ `isPreparingTimeline` を立てない」という説明とは食い違う
  （実害は小さいが、説明とコードが合っていない）
- **[優先度 中]** `Translator.textCache` に上限が無い（attempt 1 から継続・未対応）
- **[優先度 低]** `SprintSixAcceptanceTests.test04` がシミュレータで自明に通ってしまうため、
  `-SameQFakeTranslate` の `qtd`（モデル未DL相当）を使って、
  「1回目は準備中→2回目は待たない」を確定的に検証するテストに置き換えると、
  条件4の実装が壊れたときにシミュレータで気づける

## 評価できなかったもの
- **OSの「翻訳／必要なダウンロード」確認シートが実際に表示されるか、タップして進めた場合に
  `fullScreenCover` が正しく開くか（attempt 3 の再発が無いか）**。
  実機が施錠されており、XCUITest の automation mode を有効化できなかった
  （`The device is passcode protected.`）。デベロッパモードは有効・信頼関係も生きているので、
  **画面のロックを解除して自動ロックを「なし」にすれば次回は確認できる**
- **受け入れ条件7（機内モードでの翻訳表示）**。端末設定の変更にあたるため evaluator は実施しない
- 韓国語端末での確認（実機は ja のみ、シミュレータのスイートで en を確認）
