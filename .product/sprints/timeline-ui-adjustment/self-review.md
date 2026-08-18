# タイムラインUI調整 自己評価（スプリント外タスク）

ユーザーからの直接フィードバックに基づく変更。`.product/spec.md` のスプリント計画には無い。
対象は `SameQ/Feature/Timeline/TimelineView.swift` のみ（`TodayPromptView.swift` は表示の作法を
参照しただけで変更していない）。副作用として、✕ボタン削除の影響を受ける既存UIテスト5本を
スワイプ操作に書き換えた。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. 世界タイムライン閲覧中も、今日のお題の文章を常に見える状態にする | 達成 | `TimelineView` に `promptStrip` を追加し、`topBar` の直下・カード表示の上に常設。`.loading` / `.post` / `.empty` / `.exhausted` のどの状態でも表示され続ける（`body` の `switch` の外に置いたため）。翻訳未確定（`session.promptDisplayText == nil`）のときは `TodayPromptView.promptCard` と同じ作法（`ProgressView` ＋「準備中…」、識別子は `today.promptLoading` に揃えて `timeline.promptLoading`）で表示し、確定後は `timeline.promptText` に本文を出す。既存の `promptDisplayText`（翻訳確定済みの文章）をそのまま参照しているだけなので、スプリント06の翻訳ロジック自体には触れていない。 |
| 2. ✕（次へ）ボタンを削除し、操作はスワイプ＋いいねの2つだけにする | 達成 | `actionBar` から `xmark` の `circleButton`呼び出しを削除。`circleButton` ヘルパー自体も使用箇所がいいねボタンのみになったため、専用の実装に置き換えて削除した。次へ進む手段は `cardStack` の `DragGesture`（スワイプ）のみに一本化。影響を受けた既存UIテスト（`timeline.next` をタップしていた箇所）は全て `app.swipeLeft()` に書き換えた（詳細は「UIテストの書き換え」節）。 |
| 3. いいねボタンの位置・見た目を分かりやすく調整する | 達成（generatorの裁量） | ✕ボタンが無くなった分の余白を使い、いいねボタンをカード直下の中央に単独配置。直径82ptの円形ボタンに拡大（旧: 62pt）、押下時は塗り潰し（`Theme.like` 背景＋白いハート、影を強める）、未押下時は白背景＋`Theme.like`の縁取りで「押せる場所」であることを明示。ボタン直下に「いいね」／「いいねしました」の文字ラベルを添えて状態を言葉でも示す。既存デザイントーン（白い角丸カード相当の丸背景、`Theme.like`、丸ゴシック `design: .rounded`）を踏襲。アクセシビリティ識別子 `timeline.like` ・`isSelected` トレイトは変更していないため、いいねの押下判定に依存する既存テストへの影響は無い。 |
| 既存の受け入れ条件・回帰が壊れていないこと | 達成 | 下記「動かし方」の手順でシミュレータ単独実行し、`SameQTests` 57件 ＋ `SameQUITests` 33件、計90件全件成功を確認。 |

## 動かし方（evaluator向け）

1. 他に `xcodebuild` プロセスが動いていないことを確認する（`ps aux | grep xcodebuild`）。
2. シミュレータを起動する（例: `xcrun simctl boot "iPhone 17"`、または Xcode から）。
3. ビルド確認: `xcodebuild build -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=<UDID>'`
4. フルテスト実行:
   `xcodebuild test -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=<UDID>'`
   （`SameQTests` 57件・`SameQUITests` 33件、計90件が全件成功する）
5. 手動確認する場合: アプリを起動し（`-SameQResetState` で初回設定からやり直せる）、オンボーディングを終えてお題に回答すると世界タイムラインが開く。
   - 画面上部、閉じるボタンの下に「お題」ラベルとお題本文（`timeline.promptText`、翻訳確定前は`timeline.promptLoading`の「準備中…」）が常に出ていることを確認する。
   - カードの下に✕ボタンが無く、大きな丸いいいねボタン（`timeline.like`）だけが中央にあることを確認する。押すと赤く塗り潰され「いいねしました」に文言が変わる。
   - カードを左右にスワイプすると次の回答へ進む（✕ボタンは無いのでスワイプのみで進む）。

## 自分で見つけた弱点

- **実機・シミュレータでの目視スクリーンショット確認ができていない**。このセッションでは
  Simulator.app の GUI 操作に必要な Accessibility 権限（System Events 経由のクリック操作）が
  取得できず（`osascript` で `System Events` から `Simulator` プロセスのウィンドウを掴めなかった。
  権限付与はユーザーの明示操作が必要な変更のため、無断で行わなかった）、また `computer-use`
  はこの環境で iOS Simulator が明示的に unsupported（ロールアウトフラグで無効）だったため使えな
  かった。代わりに (a) コードレビューでレイアウトを確認、(b) オンボーディング1画面のみ
  `xcrun simctl io screenshot` で確認、(c) 新しいスワイプ操作を含むUIテスト33本を実機さながらに
  シミュレータ上で動かして全件成功していることで代替した。見た目の最終確認（バランス・余白）は
  evaluatorに委ねる。
- いいねボタンの直径（82pt）や色使いは仕様上の具体的な指定が無く、generatorの裁量判断。
  「押しやすく分かりやすい」の解釈が evaluator の期待とずれる可能性はある。
- `promptStrip` の識別子は `TodayPromptView` と完全に同一（`today.promptText` 等）ではなく、
  画面ごとに `timeline.` 接頭辞を付けた別名にした（同じ識別子を2画面で使うと、タイムラインが
  `fullScreenCover` で重なっている間は `TodayPromptView` も裏で生き続けている設計上、
  UIテストの要素検索が意図しない方を拾う可能性があるため、安全側に倒した判断）。表示の作法
  （「準備中…」＋ ProgressView）は仕様どおり揃えている。

## 提案（今回はやらなかったこと）

- お題テキストが長い場合、`promptStrip` は2行で省略（`lineLimit(2)`）にしている。お題は仕様上
  短文が前提だが、将来長文お題を許容するなら全文表示への切り替え（タップで展開等）が要るかもしれない。
- いいねボタンにハプティクスを付けると「押したことが分かる」がさらに強化されるが、今回のフィード
  バックは視覚的な分かりやすさのみだったため見送った。

---

## 追記（スプリント外の小さな修正、2026-08-19）

`eval-1.md` の「合否には影響しないが要対応・優先度高」の指摘2件（[A][C]）への対応。
合格判定を受けた変更に、副作用への手当てを追加するもので、新しい受け入れ条件は無い。
対象は `SameQ/Feature/Timeline/TimelineView.swift` と `SameQUITests/SprintFiveAcceptanceTests.swift`
のみ。スプリント06関連ファイルには触れていない。

### 対応内容

| 指摘 | 状態 | 内容 |
|---|---|---|
| [A] カードの上下の余白（実測 約138pt／約139pt）でスワイプが効かず画面の約1/3が無反応 | 対応済み | `cardStack` の `DragGesture` を `AnswerCardView` 本体から `ZStack` 側へ移動。`ZStack` に `.frame(maxWidth: .infinity, maxHeight: .infinity)` を先に適用したうえで `.contentShape(Rectangle())` を付け、お題表示〜いいねボタンに挟まれた領域全体（カードの上下の余白を含む）でジェスチャを受け取るようにした。カード自体の `offset`／`rotationEffect` は変更していない。 |
| [C] `SprintFiveAcceptanceTests` の2箇所で「スワイプ後に実際に次へ進んだこと」の検証が抜けていた | 対応済み | `test04_likeRateLimitBlocksThenRecovers` と `test05_reportRateLimitBlocksThenShowsMessage` の `app.swipeLeft()` 直後に、`SprintOneAcceptanceTests` / `SprintThreeAcceptanceTests` と同じ実装の `waitForBodyToChange`（スワイプ前の本文を保持し、変わるか終端表示に移るまで待つ）を追加。スワイプ前の本文を保持してから比較する形にした。 |

指摘[B]（お題とカードの間の空白が大きい・視線が落ち着きにくい）と[D]（長文お題での2行省略）は
今回のタスクの依頼範囲外（デザイン調整の裁量判断・スプリント09の材料）のため対応していない。

### 確認方法

1. ビルド確認: `xcodebuild build -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=12050FBD-587B-4910-8812-696BB91BE051'` → `** BUILD SUCCEEDED **`。
2. フルテストスイート（他の `xcodebuild` プロセスが無いことを `ps aux | grep xcodebuild` で確認したうえで単独実行）:
   `xcodebuild test -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=12050FBD-587B-4910-8812-696BB91BE051'`
   → `SameQTests` 57件 ＋ `SameQUITests` 33件、**計90件すべて成功**（`** TEST SUCCEEDED **`）。
   `SprintFiveAcceptanceTests`（新しい検証を追加した箇所を含む）も全件成功。
3. [A]の修正が実際に効いていることの自己確認: 一時的なUIテスト（`TempSwipeMarginProbeTests`、
   コミットせず）を作り、`timeline.prompt` の下端と `timeline.card.body` の上端の中間 y座標、
   および `timeline.card.body` の下端と `timeline.like` の上端の中間 y座標で、ウィンドウ座標を
   直接指定してスワイプ（`XCUICoordinate.press(forDuration:thenDragTo:)`）した。どちらも
   スワイプ後に本文が変わることを確認できた（`test_swipeInMarginAboveAndBelowCardAdvances` 1件、
   単独実行で成功）。このテストをビルドに含めるため `project.pbxproj` に一時的にエントリを追加して
   実行し、確認後は `project.pbxproj` をコミット前の状態に復元、テストファイルは削除した
   （`git status` で pbxproj に差分が残っていないことを確認済み）。

### 自分で見つけた弱点

- `.contentShape(Rectangle())` を `ZStack` の `.frame(maxWidth: .infinity, maxHeight: .infinity)` の
  後段に付けたため、スワイプの反応領域は「お題表示の直下〜いいねボタンの直上」の画面幅いっぱいに
  広がった。これは evaluator の提案どおりだが、副作用として、カードの左右（画面端に近い余白）でも
  スワイプが反応するようになった。従来はカード本体（`.padding(.horizontal, 20)` の内側）でしか
  反応しなかった領域が広がる形なので、意図しない挙動ではないと判断したが、evaluator の目視確認を
  お願いしたい。
- 一時的な確認用UIテスト（`TempSwipeMarginProbeTests`）はリポジトリに残していない。再現したい場合は
  上記「確認方法」の3番の手順で再作成できる。

### 提案（今回はやらなかったこと）

- なし（今回は指摘された2点のみに対応）。
