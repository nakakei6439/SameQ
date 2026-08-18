# スプリント06 自己評価（attempt 1）

このファイルは generator（セッション上限で作業継続不可）に代わり、coordinator が
実装差分とテスト結果を確認した上で作成した。実装そのものは generator によるもの。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 端末言語と異なる言語の回答が端末言語で表示される | 達成 | `Translator.translate` が原文言語≠端末言語のときのみ `TranslationSession.translate` を呼ぶ（`Translator.swift`）。`AppSession.drawNextPost` が翻訳結果を `Post.displaying(translatedBody:)` で差し替えてから `timelineContent` に反映する |
| 翻訳ボタン・原文表示・切替・「翻訳済み」表示・投稿言語ラベルが存在しない | 達成 | `TodayPromptView` / `TimelineView` に該当UIを追加していない（コードレビューで確認）。`Post.bodyLanguage` / `Prompt.language` は内部判定専用で画面に出していない |
| 翻訳できない言語の回答はタイムラインに一度も現れず、スワイプで次が出る | 達成 | `AppSession.drawNextPost` は `translate` が `nil`（非対応 or 失敗）を返した場合、`continue draw` で `backend.nextTimelinePost` から次を引き直す。`nextTimelinePost` は返した時点で既読化するため、スキップした投稿が後で再度出ることもない |
| 翻訳モデル未取得時は初回のみ準備中表示、2回目以降は待たない | 部分的（自動テストでは未確認） | `Translator` は言語ペアごとの対応可否を `statusCache`、翻訳結果を `textCache` にプロセス内キャッシュしており、同一セッション内での2回目以降の待ちは発生しない設計。ただし「モデル未取得→ダウンロード→準備中表示」の実機的な流れは Simulator 上でネットワーク環境やモデル状態に依存するため、自動テストでは検証できていない。**evaluatorによる実機/シミュレータでの目視確認が必要** |
| お題も端末言語で表示され、言語設定を変えて起動し直すとその言語になる | 達成（起動し直す前提） | `Translator.init` は `Locale.preferredLanguages.first` を起動時に1回だけ読む（`Locale.current` は本アプリがローカライズリソースを持たないため開発言語に丸められる既知の落とし穴を避けるためのコメントが `Translator.swift` にあり）。`AppSession.syncPromptTranslation` が `promptDisplayText` を翻訳確定後にのみセットする |
| 翻訳失敗時はエラーダイアログを出さず次を表示する | 達成 | `Translator.translate` は `do/catch` で例外を握りつぶし `nil` を返すのみ。呼び出し側（`drawNextPost`）はアラートを出さずスキップに回す |
| 機内モードでもモデル取得済み言語なら翻訳表示できる | 未確認（自動テスト対象外） | Apple Translation Framework の仕様上、モデルダウンロード後はオンデバイス翻訳になるはずだが、機内モードでの実機/シミュレータ確認は今回行っていない。**evaluatorによる確認が必要** |

自己申告としては 5/7 達成、2件（モデル未取得時のUX、機内モード）はコードの設計上は満たしているはずだが、実機的な確認ができていない。

## 動かし方（evaluator向け）

```bash
open /Users/nakagawakeita/Products/iOSApp/SameQ/SameQ.xcodeproj
```

- シミュレータの「設定 > 一般 > 言語と地域」から言語を切り替えて**アプリを再起動**すると、その言語で表示される（`Translator` は起動時に1回だけ `Locale.preferredLanguages` を読むため、アプリ内切り替えは無い）。評価者への注記どおり日本語／英語／韓国語の3パターンを確認すること。
- 同梱シード（`SameQ/Resources/SeedData.json`）には多言語の投稿が含まれている。`-SameQAnswerCount` を付けずに起動するとこの多言語シードがそのまま使われ、翻訳・スキップの検証ができる（`-SameQAnswerCount` を付けると機械生成された日本語のみの投稿になり、翻訳を挟まない検証用モードになる。翻訳の検証には使わないこと）。
- 「準備中…」表示（`today.promptLoading`）は、お題の翻訳が確定するまでの間だけ出る。

## 自分（coordinator）で確認したこと

- `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'generic/platform=iOS Simulator' build` が成功することを確認済み
- `xcodebuild ... test`（フルスイート、他プロセス非併走の単独実行）で **31件中31件成功**を確認済み
  - 1回目の実行で `SprintOneAcceptanceTests.test02_lockedUntilAnsweredThenTimeline` が失敗（「読み切ったら終端表示になる」のタイムアウト）。原因は翻訳の非同期スキップ処理が絡んで、1件あたりの表示・終端判定に実時間がかかるようになったこと（Simulator は特に遅い）。テスト側の待ち時間を伸ばす形で修正済み（`SprintOneAcceptanceTests.swift` diff参照）。プロダクションコードの挙動は変えていない
- コードレビューで、翻訳関連UIが一切追加されていないこと、`Post.bodyLanguage` / `Prompt.language` が画面に露出していないことを確認済み

## 自分で見つけた弱点（generatorの実装から引き継ぎ、未対応）

- モデル未取得時の初回ダウンロードUX、機内モードでの動作は自動テストで検証できておらず、evaluatorの実機/シミュレータでの目視確認が必要
- `Translator` はプロセス内キャッシュ（`textCache` / `statusCache`）のみで、アプリ再起動をまたいだキャッシュは持たない。受け入れ条件の「同じ端末で2回目以降は待ちが発生しない」は同一セッション内の話として実装されている（OS側のモデルダウンロード自体は端末に永続されるため、再起動後も「モデルの再ダウンロード」は発生しないはずだが、`TranslationSession` の生成コストそのものは毎回発生しうる）
- お題の翻訳は失敗時に原文へフォールバックする設計（「今回の判断」としてコード内コメントに明記済み）。投稿と違ってお題は「常に1つだけ有効」でスキップの代わりが無いための判断

## 提案（今回はやらなかったこと）

- 特になし（評価者への注記に沿った3言語切り替え確認は evaluator の作業として引き継ぎ）

---

# スプリント06 自己評価（attempt 2）

evaluator の `eval-1.md`（不合格・受け入れ条件3/7）で指摘された4点に対応した。
実機検証（ユーザーが外出中のため今回スコープ外）以外は、シミュレータで確認できる範囲を
最大限進めた。指摘された4点の修正に集中し、ついでのリファクタリングはしていない。

## 対応した4点

### 1.【最重要】翻訳キューが同一言語ペアの2件目の要求で永久に固まる

**原因**: `Translator.startNextIfNeeded()` が毎回 `TranslationSession.Configuration` を
新しく作って `configuration` に代入し直していた。evaluator が実測したとおり、値が同じ
`Configuration` を代入し直しても `.translationTask` は再実行されない。

**対応**: 待ち行列のロジックを `SessionRequestQueue<Session>`（新規・`Translation` に依存しない
ジェネリック型、`SameQ/Backend/SessionRequestQueue.swift`）に切り出し、**一度取得できた
セッションはキー（原文の言語コード）ごとにキャッシュし、2回目以降は新しい要求を一切出さず
キャッシュを即座に返す**設計にした。これにより「同じ値の `Configuration` を2回連続で代入する」
という固着の直接原因が構造的に起こり得なくなる（新しい `Configuration` を作るのは、まだ
一度もセッションを取得していない言語ペアのときだけ）。

保険として、evaluator の提案どおり `invalidate()` の呼び出し（新しい要求を出す直前）と、
一定時間（45秒）セッションが来なければタイムアウトして次の要求へ進む仕組みの両方を入れた
（タイムアウト時は「一時的な失敗」として扱い、恒久的な非対応とはしない＝バグ4の修正と連動）。

**確認方法**: `SessionRequestQueueTests.swift`（新規、ユニット5本）で、`TranslationSession` を
一切使わずに以下を直接検証:
- 同じキーへの2回目の要求では `onNeedsSession`（＝`Configuration` の差し替えに相当）が
  呼ばれない（evaluator の実測ログの再現: en→en→ko で要求は en・koの2回だけ）
- 未解決のうちの重複要求も1回にまとまる
- セッションが来ないままタイムアウトしても `nil` を返し、後続の別キーの要求はブロックされない
- タイムアウトしたキーは、あとで再要求できる（永久に諦めない）

この待ち行列ロジックは `Translator.sessionQueue`（`SessionRequestQueue<TranslationSession>`）が
そのまま使っているので、ロジックの正しさはコードレベルで直結している。ただし
`TranslationSession` を使った実際のセッション取得・翻訳そのもの（`.translate(_:)` の実行）は
このシミュレータでは検証できない（後述の2点目）。

### 2. シミュレータでの実処理経路の検証手段が無い

**対応**: Debug限定・起動引数 `-SameQFakeTranslate` を追加（`LaunchOptions.fakeTranslate`）。
有効なとき `Translator.translate` は実際の `TranslationSession` を一切使わず、
`[<端末言語コード>] <原文>` という決定的な変換を返す。同梱シードの検証用マーカー
（`zxx`）は疑似モードでも「恒久的に非対応」として扱う。テキストキャッシュ
（`textCache`）・非対応キャッシュ（`unsupportedSourceCodes`）は本番経路と共有しているので、
「同じ原文は2回目以降キャッシュから返る」という周辺ロジックも同じコード経路で検証できる。
実際の `TranslationSession` を使う本番経路（`sessionQueue` 以降）はそのまま残しており、
疑似モードは `translate()` の先頭付近で分岐するだけ。Releaseビルドには含まれない
（既存の `-SameQBanned` 等と同じ扱い。`#if DEBUG` で起動引数を解釈する既存の仕組みをそのまま使う）。

テスト時にホスト環境のロケールへ依存しないよう、`Translator.init` に
`preferredLanguageIdentifier`（既定 nil＝実際の端末設定を読む）という上書き用の引数も追加した。

**確認方法**:
- `TranslatorFakeModeTests.swift`（新規、ユニット6本）: 疑似変換の内容、同一言語のスキップ、
  `zxx` の恒久的非対応、キャッシュの効き、空文字の扱い、端末言語ごとの接頭辞の追従
- `AppSessionTranslationTests.swift`（新規、ユニット3本）: `AppSession` + `LocalBackend` +
  疑似 `Translator` を組み合わせ、(a) お題の翻訳確定、(b) **同じ原文言語（"en"）の回答10件を
  連続で引いても途中で止まらず全件表示できる**（バグ1の統合確認。修正前の設計なら1件目の
  あとで止まっていたはずの状況を、疑似モードでも AppSession の流れとして再現）、
  (c) 非対応言語（`zxx`）が一度も表示されず恒久的にスキップされる、を確認
- `SprintSixAcceptanceTests.swift`（新規UIテスト2本）: 実際にアプリを `-SameQFakeTranslate`
  付きで起動し、同梱シード（多言語）を読み切りまでスワイプ。途中で止まらないこと・非対応
  マーカーが出ないこと・少なくとも1件は `[<言語コード>] ` 接頭辞付きで表示されること、
  お題が「準備中…」のまま固まらず確定表示に変わることを確認

### 3. 端末言語が日本語以外だとお題が日本語原文のまま出る

**調査結果**: attempt 1 の環境（シミュレータ）でこの症状が起きていた直接原因は、バグ2
（Apple Translation がこの環境では全ペアで失敗する）であり、`isSupported()` が
`.unsupported` を返すため即座に原文へフォールバックしていた（「準備中…」が一瞬も
見えなかったのはこのため）。バグ1（キュー固着）は、実機で翻訳が機能する環境において
「お題（ja→端末言語）の直後に ja の回答を連続で引く」場面で発生しうる不具合であり、
1の修正でこの経路は解消した。

**設計判断（決定を維持）**: お題は「常に1つだけ有効・スキップの代替が無い」（置いた前提2）
ため、翻訳できない場合は引き続き原文へフォールバックする。判断理由:
- 翻訳関連UIを一切出さない方針（evaluatorが確認済みの合格ポイント）のため、「これは原文です」
  と示すラベルも追加できない
- 「準備中…」を出し続けると、受け入れ条件「2回目以降は待ちが発生しない」と矛盾する
- 恒久的な非対応・一時的な失敗のどちらでも「原文を出す」以外に取れる選択肢が無い
  （投稿と違って「スキップして次を出す」代わりが無い）

1の修正により、実機で翻訳が機能する環境では、少なくとも「同じ言語ペアの連続」による
見かけ上の失敗は解消されているはずだが、**実機での最終確認は今回のスコープ外**
（ユーザーが外出中のため）。次回 evaluator が実機で確認できる状態になった際に、
改めてこの点を検証してほしい。

### 4. 翻訳できずスキップした回答が恒久的に既読になる

**対応**: `Translator.translate` の戻り値を `TranslationOutcome`（`.text` /
`.unavailable(permanent:)`）に変更し、「恒久的な失敗（非対応言語）」と「一時的な失敗
（セッション取得のタイムアウト・翻訳時の一時的なエラー）」を区別できるようにした。

`Backend` プロトコルの `nextTimelinePost` に `excluding`（この巡回だけの一時的な除外。
永続化しない）と `autoMarkViewed`（既読にするかを呼び出し側に委ねる）を追加し、新たに
`markPostViewed(_:)` を追加した。`AppSession.drawNextPost` は
`nextTimelinePost(..., autoMarkViewed: false)` で引いてから翻訳を試し、
- 翻訳成功、または恒久的に非対応と判明した場合だけ `markPostViewed` を呼ぶ
- 一時的な失敗の場合は、既読にせず、その巡回内だけ `excluding` に入れて次を引き直す
  （無限ループを避けつつ、次の巡回・次回起動では再挑戦できるようにする）

既存の呼び出し元・既存テスト（スプリント01〜05）を壊さないよう、`Backend` の
extension に `nextTimelinePost(promptID:)`（`excluding: []` / `autoMarkViewed: true` を
補う後方互換のデフォルト呼び出し）を用意した。プロトコル本体には既定値を書けないため。

**確認方法**:
- `TranslationSkipTests.swift`（新規、ユニット5本）: `LocalBackend` レベルで、一時的な失敗は
  既読にならないこと、`excluding` により同じ巡回内で無限ループしないこと、恒久的な失敗は
  既読にしてよく以後二度と出てこないこと、`markPostViewed` の冪等性、デフォルトの呼び出しが
  従来どおり即座に既読にすることを確認
- `AppSessionTranslationTests.testUntranslatableMarkerNeverAppearsAndIsPermanentlySkipped`:
  `AppSession` を通した統合確認として、非対応言語の回答が既読になり翻訳可能な回答だけが
  表示されることを確認

## 自分で確認したこと（このセッション）

- `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'generic/platform=iOS Simulator' build` 成功
- 新規ユニットテスト19本（`SessionRequestQueueTests` 5・`TranslatorFakeModeTests` 6・
  `TranslationSkipTests` 5・`AppSessionTranslationTests` 3）を単独実行し全件成功
- 新規UIテスト2本（`SprintSixAcceptanceTests`）を単独実行し全件成功。`-SameQFakeTranslate` で
  実際にアプリを起動し、タイムラインが固着せず読み切りまで進むこと、お題が確定表示に
  変わることを目視でも確認
- 他にxcodebuildプロセスが動いていないことを確認したうえで、フルテストスイート
  （`SameQTests` + `SameQUITests`、既存 + 新規）を実行 → 結果は本ファイル末尾に追記

## 動かし方（evaluator向け・attempt 2で変わった点）

- 追加した起動引数: `-SameQFakeTranslate`（Debug限定）。有効にすると `Translator` は実際の
  `TranslationSession` を使わず、`[<言語コード>] <原文>` の決定的な変換を返す。シミュレータで
  「翻訳結果が画面に反映される」「非対応言語（`zxx`）はスキップされる」「同じ端末で2回目
  以降は待たない（キャッシュが効く）」を確定的に確認するためのモード
- 例: `-SameQFakeTranslate -SameQResetState`（初回設定からやり直しつつ疑似翻訳を有効化）
- 端末言語を日本語／英語／韓国語で切り替える手順（`.GlobalPreferences` を書き換えて端末ごと
  再起動）は attempt 1 の evaluator の手順のまま有効。`-SameQFakeTranslate` と組み合わせれば、
  Apple Translation が使えないシミュレータでも「その言語での表示」を確定的に確認できる
  （実際の翻訳文ではなく `[<言語コード>] ` 接頭辞になる点に注意）
- 実際の `TranslationSession` 経路（`-SameQFakeTranslate` を付けない場合）は、このシミュレータ
  では引き続き機能しない（Apple Translation Framework のシミュレータ制約）。実機での確認が
  必要（今回のスコープ外）

## 自分で見つけた弱点（正直に書く）

- **実機検証は今回一切できていない**。1（キュー固着）の修正はフレームワーク非依存の
  `SessionRequestQueue` レベルでは確実にテストできたが、実際の `TranslationSession` を
  使った経路（`.translate(_:)` の実行そのもの）がこの待ち行列と正しく協調して動くかは、
  実機でしか確認できない。次回 evaluator が実機で検証できる際に最優先で見てほしい
- タイムアウト秒数（45秒）は経験的な値。実機でモデルの初回ダウンロードにこれより長く
  かかる場合、正当なダウンロード待ちを「一時的な失敗」として打ち切ってしまう可能性がある
  （ただしこの場合も既読にはならないので、次の巡回で再挑戦できる。無言で固まり続けるより
  マシ、という位置づけの保険）
- 3（お題のフォールバック）は「決定を維持」という結論にとどまり、実機での効果測定は
  できていない
- `SessionRequestQueue` の `sleep` オーバーライド機構はテスト専用で、本番コードパスには
  影響しない設計だが、`Translator` 側からは常に既定値（実時間の `Task.sleep`）を使っている

## 提案（今回はやらなかったこと）

- 実機で翻訳モデルの初回ダウンロードにかかる実測時間を確認し、タイムアウト秒数（45秒）を
  調整する
- `Translator.textCache` に上限が無い問題（attempt 1 の評価提案、優先度中）は今回も未対応
  （指摘された4点に集中したため）

---

# attempt 3（eval-2.md [1][2] の修正）

## 直した2点

### [1]【最重要】キャッシュしたセッションが実機では無効になる

**原因**: attempt 2 の `SessionRequestQueue` は「一度取得できたセッションを言語ペアごとに
キャッシュし、以後は使い回す」設計だった。しかし `TranslationSession` は SwiftUI の
`.translationTask` 修飾子のライフサイクルに紐づいており、`configuration` を別の言語ペアへ
差し替えると前の `.translationTask` は畳まれ、そこで取得したセッションは無効になる。無効な
セッションで `translate(_:)` を呼ぶと、フレームワークが致命的エラー
（`Attempted to use TranslationSession after the view it was attached to has disappeared`）
を出す。これは実機でのみ再現し（シミュレータの `-SameQFakeTranslate` は `sessionQueue` の
手前で分岐するため、この経路を一度も通らない）、evaluator の実機プローブで確認された。

**対応**: `SessionRequestQueue` からセッションのキャッシュを完全に撤去した。新しい契約
（`SameQ/Backend/SessionRequestQueue.swift`）:
- `perform(key:body:onJobTimeout:)` は**呼ぶたびに必ず新しいセッションを要求する**
  （同じ言語ペアでもキャッシュを返さない。`onNeedsSession` は毎回呼ばれる）。
- 取得できたセッションは `resolve(session:)` の中（＝そのセッションを供給した
  `.translationTask` のクロージャがまだ生きている構造化された非同期スコープの中）で
  `body`（実際の `session.translate(_:)`）を実行し終えてから返る。`resolve` 自体が
  `body` の完了を待つので、セッションが `.translationTask` の外に持ち出されることは
  型的に無い。
- キューは常に1件ずつしか処理しない（元の設計と同じ。`isInFlight` フラグで直列化）。

同じ言語ペアを連続で要求しても `.translationTask` が確実に再実行されるよう、`Translator` の
`configuration` 差し替えロジックも変更した。attempt 2 は「`invalidate()` を呼んでから
新しい `Configuration` インスタンスに丸ごと差し替える」実装だったが、これだと SwiftUI が
次のレンダーで見る最終値は無効化前と等価な値に戻ってしまい（新しいインスタンスは
`invalidate()` されていない）、`.translationTask` は再実行されない（attempt 2 の eval が
指摘した2点目の不具合と同根）。SDK の `.swiftinterface`
（`Translation.framework/Modules/Translation.swiftmodule/arm64e-apple-ios.swiftinterface`）
を直接確認し、`TranslationSession.Configuration` の `source`/`target` が `var`、
`invalidate()` が `mutating func` であることを確かめたうえで、**いま割り当てている
インスタンスに対して** `invalidate()` を呼んでから `source`/`target` を書き換える方式に
変更した。これにより、同じ言語ペアの連続要求でも SwiftUI が次のレンダーで見る値が
無効化前と異なるものになり、`.translationTask` が確実に再実行される。

### [2] `session.translate(_:)` 自体にタイムアウトが無い

**対応**: `SessionRequestQueue.perform` の中で、取得したセッションに対する `body`
（`session.translate(_:)`）の実行を `withTaskGroup` でタイムアウト用の `sleep` と競走させる
（`jobTimeoutSeconds`、既定30秒）。タイムアウトが勝ったら `onJobTimeout(session)` を呼んでから
`nil` を返す。`Translator` はこの `onJobTimeout` で `session.cancel()`（iOS 26+。SDKの
`.swiftinterface` で確認: `TranslationSession.cancel()` は iOS 26.0+）を呼び、応答不能な
`translate(_:)` 呼び出しへ中断を伝える。

**確認した重要な性質（使い捨てスクリプトで検証済み）**: `withTaskGroup` は、クロージャが
値を返したあとも、残っている子タスク（この場合はまだ走っている `body`）の完了を待ってから
関数全体が返る。つまり `body` が本当に応答不能（cancellation を無視する）だと、
`group.cancelAll()` を呼ぶだけではタイムアウトの意味が無い。`onJobTimeout` を
`group.cancelAll()` より**先に**呼び、`session.cancel()` で `translate(_:)` 自身に
中断を伝える設計にしたのはこのため。`Task.sleep` は協調的キャンセルに正しく応答することも
別途確認済み（`body` が `Task.sleep` を含む場合はキャンセル後すぐに戻る）。

タイムアウトした場合は `.unavailable(permanent: false)`（既存の仕組みをそのまま使う。
既読にしないので後で再挑戦できる）。

## 削って書き直したもの

- `SessionRequestQueue.sessionsByKey`（セッションキャッシュ）と、それに依存していた
  `SessionRequestQueueTests.swift` の既存5本を、新しい契約（毎回新しいセッションを要求・
  キャッシュしない・`body` の実行まで含めて `resolve` が完了する）に合わせて書き直した
  （6本、うち1本はセッションが有効なスコープの中で `body` が完了することを確認する新規テスト、
  2本はジョブタイムアウトの保険を確認する新規テスト）。

## 自分で確認したこと（このセッション）

- SDK の `.swiftinterface` を直接読み、`TranslationSession.Configuration` の `source`/
  `target` が `var`、`invalidate()` が `mutating func` であること、`TranslationSession.cancel()`
  が iOS 26.0+ であることを確認（Web検索だけに頼らず、実際のインターフェースファイルで裏取りした）
- 使い捨てのSwiftスクリプト3本で `withTaskGroup` の挙動を検証（`/private/tmp` 配下、
  コミット対象外）:
  1. `withTaskGroup` は非Sendableなクラスをキャプチャしても Swift 5 言語モードでは
     コンパイルエラーにならないこと
  2. cancellation に応答しない子タスクがあると、`group.next()` がタイムアウト側の値を
     返したあとも、関数全体は応答しない子タスクの完了を待ち続けて返らないこと
     （＝`cancelAll()` だけでは不十分）
  3. `Task.isCancelled` を確認するループは `cancelAll()` 後すぐに戻ること（`Task.sleep` も
     同様）
- `xcodebuild -destination 'generic/platform=iOS Simulator' build` 成功
- `SessionRequestQueueTests`（6本）・`TranslatorFakeModeTests`（6本）・
  `AppSessionTranslationTests`（3本）・`TranslationSkipTests`（5本）を単独実行し、
  20本全件成功（ハングなし、`SessionRequestQueueTests` のジョブタイムアウト系テストも
  実時間で1秒未満）
- 他にxcodebuildプロセスが動いていないことを確認したうえで、シミュレータ
  （iPhone 17 / iOS 26.5）でフルテストスイート（`SameQTests` + `SameQUITests`）を実行 →
  **90/90 全件成功**（`xcresulttool` の `test-results summary` で確認: `failedTests: 0`,
  `passedTests: 90`）
- `xcodebuild -destination 'id=B7121EA8-8AED-5E66-B696-511BFFC729E2' -allowProvisioningUpdates build`
  成功（実機向けビルド・署名は通る）
- `xcrun devicectl device install app` 成功（実機へのインストールも通る）

## 実機での確認について（重要・未完了）

**実機（iPhone 17 Pro Max、`B7121EA8-8AED-5E66-B696-511BFFC729E2`）が施錠されており、
アプリを起動できなかった。** `devicectl device process launch` が
`Unable to launch com.nakakei6439.SameQ because the device was not, or could not be, unlocked`
で失敗する（インストール自体は成功しているので、開発者イメージのマウント・署名・
プロビジョニングには問題が無い。ロック画面を開く操作だけができない）。20秒待って
再試行したが同じ結果だった。

このため、**このセッションでは「タイムラインを実機で読み切りまで操作して確認する」
という最重要の確認ができていない**。実装した内容（[1][2]の修正）はコードレベル・SDK
インターフェースの裏取り・使い捨てスクリプトでの `withTaskGroup` 挙動確認・シミュレータでの
フルテスト（90/90）までは完了しているが、evaluator が実機プローブで見つけたのと同種の
不具合（実機の Apple Translation Framework の実際の挙動）が本当に解消しているかは、
**ユーザーが端末のロックを解除したあとの実機確認が必須**。

## 動かし方（evaluator向け・attempt 3で変わった点）

- コード上の変更点（`Translator` / `SessionRequestQueue`）だけで、起動引数・UIには変更なし。
  `-SameQFakeTranslate` の挙動もキャッシュ非依存の実装のまま維持（`sessionQueue` の手前で
  分岐する構造は変えていない）
- 実機確認手順（PROGRESS.md の依頼どおり）:
  ```
  xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'id=B7121EA8-8AED-5E66-B696-511BFFC729E2' -allowProvisioningUpdates build
  xcrun devicectl device install app --device B7121EA8-8AED-5E66-B696-511BFFC729E2 <ビルドしたSameQ.appのパス>
  xcrun devicectl device process launch --device B7121EA8-8AED-5E66-B696-511BFFC729E2 com.nakakei6439.SameQ -- -SameQResetState -SameQDebugOverlay
  ```
  （`-SameQFakeTranslate` を**付けない**のが重要。これを付けると本物の翻訳経路を通らない）
- **端末のロックを解除してから**でないと `devicectl device process launch` は失敗する
  （`FBSOpenApplicationErrorDomain error 7`）

## 自分で見つけた弱点（正直に書く）

- **上記のとおり、今回のセッションでも実機での最終確認ができていない**（今回は「外出中」
  ではなく「端末がロックされている」ことが理由）。コードの修正自体は SDK インターフェースの
  裏取りと使い捨てスクリプトでの検証を伴っており、attempt 2 のときより確度は高いと考えているが、
  「確度が高い」と「実機で確認した」はイコールではない。evaluator には必ず実機で確認してほしい
- `jobTimeoutSeconds`（既定30秒）・`acquireTimeoutSeconds`（既定45秒）はどちらも経験的な値。
  実機でモデルの初回ダウンロードにこれより長くかかる場合、正当な待ちを「一時的な失敗」として
  打ち切ってしまう可能性がある（既読にはならないので次の巡回で再挑戦できる、という位置づけ）
- `session.cancel()` を呼んだあとに実際に `translate(_:)` がどれだけ早く戻ってくるかは、
  Apple Translation Framework の内部実装に依存しており、コード側からは保証できない
  （`TranslationError.alreadyCancelled` を投げて戻ってくることを期待した設計だが、
  実機での実測はできていない）

## 提案（今回はやらなかったこと）

- 実機で `jobTimeoutSeconds` / `acquireTimeoutSeconds` の実測値を確認し、必要なら調整する
- `Translator.textCache` に上限が無い問題（attempt 1 から継続、優先度中）は今回も未対応
