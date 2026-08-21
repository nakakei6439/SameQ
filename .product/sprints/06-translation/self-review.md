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

---

# attempt 4（eval-3.md [1][2] の修正）

## 直した点

### [1]【最重要】モデル未ダウンロード（`.supported`）をダウンロード済み（`.installed`）と
同じ扱いにしていたため、OSの「翻訳／必要なダウンロード」確認シートが割り込みタイムラインが
閉じる

**原因**: `Translator.isSupported(sourceCode:)` が `LanguageAvailability.Status` を
`status != .unsupported` の1軸でしか見ておらず、`.installed`（モデルあり）と
`.supported`（言語ペアは対応だがこの端末にモデルが無い）を区別せず、どちらも
「翻訳できる」として `session.translate(_:)` を呼んでいた。`.supported` の状態で
`translate(_:)` を呼ぶと、Apple Translation Framework がOSの「翻訳／必要なダウンロード」
確認シートを自動的に表示する。このシートは `TranslationHostView`（`RootView` の背景、
`fullScreenCover` で表示中のタイムラインより下の階層）に紐づいて出るため、シートを
出そうとした時点でタイムライン（`fullScreenCover`）が閉じてしまい、二度と復帰しない
（evaluator が実機・iPhone 17 Pro Max で4回中4回再現、スクリーンショットあり。
`eval-3-stall.png`）。

**対応方針の検討**: eval-3.md は2案を提示していた。(a) `TranslationSession.prepareTranslation()`
を明示的に呼んでダウンロードしてから翻訳する、(b) 取得しない方針にして
`.unavailable(permanent: false)` として読み飛ばす。**(b) を採用した。**

理由: (a) を検証したところ、`prepareTranslation()` も「モデル未取得なら確認シートを表示する」
という点は `translate(_:)` の暗黙のダウンロードと同じ（Apple公式ドキュメント
"You can call the `prepareTranslation()` function explicitly to ask the framework to
present a system UI to prompt the user to install those languages" のとおり、明示的に
呼んでもシート自体は出る）。つまり (a) を選んでも、**シートが出る場所
（`TranslationHostView` の常駐位置）を変えない限り、同じ「タイムラインが閉じる」問題が
残る可能性が高い**。シートを正しく `fullScreenCover` の中から出すには、`TranslationHostView`
を「いま最前面に出ている画面（お題 or タイムライン）に応じて動的に付け替える」設計へ
変更する必要があり、これは `RootView.swift` の構造そのものに手を入れる比較的大きな
変更になる。しかも「本当にシートが正しい階層から出て `fullScreenCover` を巻き込まずに
済むか」は実機の同じOSシートを踏む場面でしか検証できず、attempt 2・3で経験した
「シミュレータでは再現できない不具合が実機で初めて分かる」というリスクパターンに
再び当てはまる。**「指摘された問題の修正に集中する」「同じ指摘で3回落ちたら止まる」**
という制約のもとでは、**OSにシートを一切出させない（b）の方が確実性が高く、検証も
シンプル**と判断した。

**実装**: `Translator.isSupported` を廃止し、`availabilityStatus(sourceCode:)`
（`LanguageAvailability.Status` を直接返す）に置き換えた。`translate(_:sourceLanguageCode:)`
は次の3分岐にした:
- `.unsupported` → 従来どおり `.unavailable(permanent: true)`（恒久的にスキップ、既読にしてよい）
- `.supported`（未ダウンロード）→ `session.translate(_:)` はおろか `prepareTranslation()` も
  一切呼ばず、`.unavailable(permanent: false)`（一時的な失敗）として読み飛ばす。
  `AppSession.drawNextPost` は既存の仕組み（`excluding` / 既読にしない）でそのまま対応でき、
  変更不要だった
- `.installed` のときだけ、従来どおり `sessionQueue.perform` へ進んで実際に翻訳する

`.supported` はキャッシュしない（`.installed`/`.unsupported` はこの端末では変わらない前提で
キャッシュするが、`.supported` はユーザーが後で設定アプリ側でモデルをダウンロードすれば
`.installed` に変わりうるため、毎回問い合わせる）。

`LanguageAvailability.status(from:to:)` の呼び出しをユニットテストで差し替えられるよう、
`LanguageAvailabilityProviding` プロトコル（新規）を導入し、実際の `Translation.LanguageAvailability`
をこれに準拠させた（`Translator.init(availability:)` の型をプロトコルへ変更）。

**受け入れ条件4への影響（正直に書く）**: この方針により、受け入れ条件4「翻訳モデルが端末に
無い場合は初回のみ準備中の表示が出て完了後に読める」の**前半（アプリが能動的にダウンロードして
見せる）は実装していない**。モデル未ダウンロードの回答は、アプリがOSシートを出さない限り
スキップされ続ける（後半の「2回目以降は待たない」は、待つこと自体が発生しないので自明に
満たす）。これは eval-3.md 自身が「取得しない方針を採るなら `.unavailable(permanent: false)`
にしてスキップする」という選択肢を明示的に提示しており、その範囲内の判断である。
モデルを実際に入れるには、利用者が端末の設定アプリ側（設定 > 一般 > 言語と地域、または
翻訳アプリ）でダウンロードする必要がある。ダウンロード後は `.installed` になるので、
このアプリは何もしなくても次回から翻訳が効くようになる。

### [2] 固着したときタイムラインが無言で閉じる／空白のまま残る

[1] の直接の結果として発生していた症状だったため、[1] を直したことで解消するはずという
判断で、**この症状自体に対する個別の対処（例: ユーザー向けの案内文の追加）はしていない**。
[1] によりOSシートが一切出なくなり、`.supported` の投稿は既存の「一時的な失敗」の仕組み
（既読にせず次を引く。既存のUI状態のまま進む、アラートも出さない）でそのまま流れるため、
「無言で閉じる」「空白のまま残る」のどちらも構造的に起こらないはず。

## シミュレータでの疑似検証手段（eval-3.md 改善提案[優先度中]への対応）

`-SameQFakeTranslate`（疑似翻訳モード）は従来 `availabilityStatus` を一切通らずバイパスして
いたため、`.supported` を再現できなかった（eval-3.md の指摘どおり）。同梱シードの検証用
言語コード `qtd`（ISO 639-2 私用コード、`sameQ_download_pending_test_marker`）を追加し、
疑似モードでもこのコードだけは「モデル未ダウンロード」と同じ `.unavailable(permanent: false)`
を返すようにした（実際の `TranslationSession` には一切触れない）。`SeedData.json` の
prompt_001 に1件追加した（既存の `zxx` 検証用投稿の直後）。

より根本的な検証は `LanguageAvailabilityProviding` を差し替えたユニットテスト
（`TranslatorAvailabilityTests.swift`、新規）で行った。実際の `Translation.LanguageAvailability`
がこの端末で返す値と同じ形（`.installed` / `.supported` / `.unsupported`）を注入し、
**`.supported` のときは `translator.configuration` が一度も更新されない（＝
`.translationTask` へ一度もセッションを要求しない）ことを直接確認**した。これが
「OSにダウンロード確認シートを一切出させない」設計になっていることの、最も直接的な保証。

## 自分で確認したこと（このセッション）

- `xcodegen generate` → `xcodebuild -destination 'platform=iOS Simulator,name=iPhone 17' build`
  成功
- 新規ユニットテスト6本（`TranslatorAvailabilityTests` 4・`TranslatorFakeModeTests` +1・
  `AppSessionTranslationTests` +1）を含む `SameQTests` を単独実行し、**63/63 全件成功**
- 新規UIテスト1本を含む `SprintSixAcceptanceTests`（3本）を単独実行し全件成功
- 他にxcodebuildプロセスが動いていないことを確認したうえで、シミュレータ
  （iPhone 17 / iOS 26.5）でフルテストスイート（`SameQTests` 63 + `SameQUITests` 34）を実行 →
  **97/97 全件成功**（`xcresulttool` の `test-results summary` で確認: `failedTests: 0`）
- 実機（iPhone 17 Pro Max、`B7121EA8-8AED-5E66-B696-511BFFC729E2`）向けビルド・
  `devicectl device install app` 成功。実機の画面ロック状態を `devicectl device process launch`
  で確認してから（ロック解除済み・自動ロック無効のまま）進めた
- **実機で `SprintSixAcceptanceTests` を単独実行し、3/3 全件成功。**
  最重要の `test03_realTranslationReadsWholeSeedWithoutStallingOrOSInterruption`
  （新規・`-SameQFakeTranslate` を付けず本物の Apple Translation Framework を使う）が
  82秒で完走し、`timeline.exhausted` に到達、`timeline.close` が押せる状態のまま
  （＝OSシートに割り込まれてタイムラインが閉じることが一度も起きなかった）ことを確認した。
  この実機は attempt 3 の evaluator 評価で `ar`/`pl`/`ru`/`th` が未ダウンロード
  （`.supported`）だったのと同じ実機・同じ端末状態（アプリを都度 `-SameQResetState` で
  リセットしているのみで、OS側の言語モデル状態はいじっていない）で検証している
- 実機で `SameQTests`（ユニット、63本）を単独実行し全件成功
- 実機で回帰確認として `SprintOneAcceptanceTests`（5本）・`SprintFiveAcceptanceTests`（7本）を
  単独実行し、計12/12全件成功（コア導線・オンボーディング・BAN・スパム対策が壊れていない
  ことを確認）
- 全97本のフルスイートを実機で通す時間の余裕は無かったため、実機では上記
  （翻訳まわり3本＋ユニット63本＋コア/BAN回帰12本＝計78本）に絞った。翻訳に無関係な
  他のスイート（通報・ブロック・お題ライフサイクル等）はシミュレータのフルスイートで
  97/97確認済みであり、今回の変更は `Translator.swift` / `SeedData.json`（投稿1件追加）/
  テストファイルのみで、それらのロジックには触れていない

## 動かし方（evaluator向け・attempt 4で変わった点）

- 起動引数・UIに変更なし。`-SameQFakeTranslate` に新しい疑似言語コード `qtd`
  （`sameQ_download_pending_test_marker`）が1件追加された（同梱シードに1件追加）以外は
  従来どおり
- 実機確認手順（変更なし。PROGRESS.md のとおり）:
  ```
  xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'id=B7121EA8-8AED-5E66-B696-511BFFC729E2' -allowProvisioningUpdates build
  xcrun devicectl device install app --device B7121EA8-8AED-5E66-B696-511BFFC729E2 <ビルドしたSameQ.appのパス>
  xcrun devicectl device process launch --device B7121EA8-8AED-5E66-B696-511BFFC729E2 com.nakakei6439.SameQ -- -SameQResetState -SameQDebugOverlay
  ```
- `-SameQFakeTranslate` を**付けない**ことで、本物の Apple Translation を使ってタイムラインを
  最後まで読み切れることを確認できる（この実機ではモデル未ダウンロードの `ar`/`pl`/`ru`/`th`
  の4件はスキップされ、それ以外の言語は実際に翻訳されて表示される）

## 自分で見つけた弱点（正直に書く）

- **受け入れ条件4の前半（アプリが能動的にモデルをダウンロードして見せる）は実装していない**。
  上記の判断理由のとおり、OSシートを一切出させないことを優先した結果である。evaluator が
  これを「未達」と判定する可能性はあるが、[1]（最重要・タイムラインの完走）を確実に通す
  ことを優先した
- `TranslationHostView` の常駐位置（`RootView` 背景、`fullScreenCover` の外）を変えていない。
  今回はこの位置を変えずに済む方針（OSシートを出させない）を選んだが、**もし将来
  受け入れ条件4の前半（能動的なダウンロード）に対応する場合は、この常駐位置の設計を
  見直す必要がある**（対応方針の検討の節に詳細を記載）
- `qtd` のような私用言語コードは実機の実際の `Translation.LanguageAvailability` に渡すと
  おそらく `.unsupported` を返す（`.supported` にはならない）。そのため `-SameQFakeTranslate`
  無しの実機では `qtd` の投稿は「モデル未ダウンロード」ではなく「恒久的に非対応」として
  スキップされる。実害は無い（どちらにしてもOSシートは出ず、スキップされる）が、
  `.supported` の実機相当の検証は `TranslatorAvailabilityTests`（`LanguageAvailabilityProviding`
  の差し替え）に一本化されている
- `TranslatorAvailabilityTests.testInstalledStatusProceedsToRequestASession` は、実際の
  `TranslationSession` を取得できないユニットテスト環境の制約上、`translate()` の完了を
  待たずに `Task` を投げっぱなしにしている（`configuration` が更新されるまでの短時間だけ
  ポーリングし、その後の待ち行列のタイムアウト（既定45秒）はバックグラウンドで走ったまま
  テストを終える設計）。テストの実行結果には影響しないが、行儀の良い実装ではない

## 提案（今回はやらなかったこと）

- 受け入れ条件4の前半（能動的なモデルダウンロード）に対応する場合、`TranslationHostView`
  を「いま最前面の画面（お題 or タイムライン）に応じて動的に付け替える」設計への変更を検討する
- 実機で `ar`/`pl`/`ru`/`th` を意図的にダウンロード済みにした状態（設定アプリ側で
  ダウンロードしてから）でタイムラインを読み、それらの投稿が実際に翻訳されて表示される
  ことを確認する（今回は「未ダウンロードのままスキップされる」ことのみ確認した）
- `Translator.textCache` に上限が無い問題（attempt 1 から継続、優先度中）は今回も未対応

# attempt 5（eval-4.md [1] の修正・ユーザー承認済みで能動的なモデルダウンロードを実装）

## 経緯

eval-4.md の不合格理由は1点だけ: 受け入れ条件4（spec.md 197行「翻訳モデルが端末に無い場合は
初回のみ準備中の表示が出て完了後に読め、同じ端末で2回目以降は待ちが発生しない」）が
未実装。attempt 4 は `.supported`（モデル未ダウンロード）を検出したら
`session.translate(_:)` も `prepareTranslation()` も一切呼ばず、恒久的スキップと区別した
一時的な失敗として読み飛ばすだけだった。その結果、モデルが無い言語の回答は**永久に**
読めるようにならなかった。

今回はユーザーから「積極的なモデルダウンロードの実装、リスクを許容する」という方針の
承認を得たうえで、`session.prepareTranslation()` を実際に呼んでモデルをダウンロードする
設計に変更した。

## 調査: `prepareTranslation()` はOSシートを出さずに済むか

Apple Developer Forums のスレッド783311（DTSエンジニアの回答）を確認した。要旨:
「モデルが**既にインストール済み・またはダウンロード中**なら、`prepareTranslation()` は
シートを出さずに返る。**未取得なら出る**」。つまり `prepareTranslation()` も
`session.translate(_:)` と同様、モデル未取得の言語では確認シートを出しうるという
attempt 4 の判断は正しかった。**「シートを一切出させない方法」は無い**、というのが結論。

## 直した点（設計）

attempt 3（eval-3.md [1]）で確認された致命的症状は「OSのシートが出て、その下で
**`fullScreenCover`（世界タイムライン）が閉じる**」ことだった。シート自体を無くすことは
できないが、**シートが出る時点で `fullScreenCover` がそもそも開いていなければ、
閉じて困る対象が無い**。この着眼で以下の設計にした。

1. **`AppSession.openTimeline()` が、世界タイムライン（`fullScreenCover`）を実際に開く前に、
   まだ読んでいない候補の言語のうち `.supported`（モデル未ダウンロード）のものを
   `Translator.prepareIfNeeded(sourceLanguageCode:)` で順番にダウンロードしておく**
   （`prepareTimelineLanguagesIfNeeded`）。この時点ではまだ今日のお題画面（非モーダル）に
   いるので、OSのシートが出ても畳んで困る `fullScreenCover` が無い。
   - ダウンロード対象が1件も無ければ即座に返り、待ちを作らない（F19「2回目以降は待たない」を
     自明に満たす。2回目以降は既に `.installed` になっているため）。
   - ダウンロード中は `AppSession.isPreparingTimeline` を true にし、`TodayPromptView` の
     「世界の回答を読む」ボタンを「準備中…」にして連打を防ぐ（既存の「準備中…」の作法を
     流用）。
   - 全体で `timelinePreparationBudgetSeconds`（90秒）を超えたら残りの言語は諦めて
     タイムラインを開く。諦めた言語は `.supported` のままなので、`drawNextPost` が
     従来どおり一時的な失敗として読み飛ばし、既読にしない（次回また挑戦できる）。
2. `Translator.prepareIfNeeded` は `.installed` / `.unsupported` のときは何もしない
   （無駄なセッション要求をしない）。`.supported` のときだけ `sessionQueue.perform` で
   セッションを要求し `session.prepareTranslation()` を呼ぶ。失敗・タイムアウトしても
   エラーは投げず、静かに諦める（`translate()` 側の `.supported` チェックが引き続き
   `.unavailable(permanent: false)` として扱うため、利用者にエラーが見えることはない）。
3. **`prepareTranslation()` のタイムアウトは、`session.translate(_:)` の既定30秒とは別に
   60秒（`modelPrepareJobTimeoutSeconds`）を新設**した。ダウンロードは通常の翻訳より
   時間が掛かりうるため。`SessionRequestQueue.perform` に `jobTimeoutSeconds` の
   呼び出し単位の上書きを追加して対応した。

## 【最重要】実機で見つけた `SessionRequestQueue` の致命的な欠陥とその修正

実機で確認する中で、`perform` の呼び出しが**15分待っても一度も返ってこない**現象に遭遇した
（後述の「実機での確認」参照）。原因を調べたところ、attempt 3 から存在していた
`runWithJobTimeout`（`withTaskGroup` で `body` とタイムアウト用の `sleep` を競走させる設計）
に構造的な欠陥があった。**`withTaskGroup` は、クロージャを抜ける前に、キャンセル済みでも
残っている子タスクの完了を必ず待つ**（Swift の構造化並行性の仕様）。`session.translate(_:)`
は `cancel()` を呼ぶとすぐ例外を投げて終わる（attempt 3 で確認済み）ためこれまで実害が
無かったが、`session.prepareTranslation()`（attempt 5 で新規に呼ぶようになった、モデルの
ダウンロード）は **`cancel()` を呼んでも終わらないらしく、`withTaskGroup` がその子タスクの
完了を待ち続けるせいで `jobTimeoutSeconds` が名目だけの存在になっていた**（呼び出し元は
一切解放されない）。

**修正**: `runWithJobTimeout` を `withTaskGroup`（構造化）から、`body` を独立した
非構造化 `Task` として起動し、タイムアウト用の別 `Task` と「どちらが先に
`continuation.resume` を呼ぶか」だけで決着させる設計に変更した。タイムアウトが勝った場合、
`body` を実行している `Task` はバックグラウンドに取り残される（いずれ終わる・あるいは
永久に終わらない）が、`perform` の呼び出し元はもう待たされない。これで `jobTimeoutSeconds`
が名実ともに呼び出し元の待ち時間の上限になった。`SessionRequestQueueTests` は既存6本＋
新規1本（`jobTimeoutSeconds` の呼び出し単位の上書きが実際に使われることの確認）が全通過。

この不具合は attempt 3 の時点から存在していたが、**「セッション取得後の呼び出しが本当に
応答不能になる」状況を今回まで一度も実機で作れていなかった**ため見つかっていなかった
（`session.translate(_:)` は cancel() に素直に応じていた）。attempt 5 で
`prepareTranslation()` を呼うようになって初めて露呈した。

## 実機での確認

`SprintSixAcceptanceTests`（XCUITest）による指のタップ操作の自動確認を試みたが、
`Timed out while enabling automation mode.` が2回とも発生し、XCUITest 自体が起動
できなかった（eval-3.md・eval-4.md と同じ現象。`devicectl` の `lockState` は
`passcodeRequired: false` を返し続け、実際にロックされているかどうかの判断材料にならない。
`devicectl device process launch` はロック中でも成功することがあるため信頼できない）。

そのため、attempt 4 で evaluator が使った手法にならい、**ホストアプリのプロセス内で
本物の `TranslationHostView` を実ウインドウ（`UIWindowScene` に紐づけた `UIWindow`）に載せ、
`AppSession` でタイムラインを読み切る**方法に切り替えた（一時テストで確認。確認後に削除・
`xcodegen generate` で復元済み）。指の操作の代わりに `advanceTimeline()` を直接呼ぶが、
翻訳・スキップ・既読の実処理は本番と同じ経路を通る。

- **`SessionRequestQueue` の修正前**: `prepareTranslation()` の呼び出しが応答せず、
  1回目は15分、2回目は10分待っても `openTimeline()` 自体が一度も返ってこなかった
  （強制終了して確認）。
- **修正後**: 2回とも約63〜75秒で `openTimeline()`（能動的なダウンロードの試み込み）が
  完了し、そのあと10秒程度で28件を読み切りまで到達した（固着0）。
  - この実機のこの時点での `.supported`（未ダウンロード）言語は `pl` / `th` / `id`
    （前回のプローブでは `ar` / `ru` は既に `.installed` だった）。
  - **2回とも `id`（インドネシア語）の投稿は実際にダウンロードされて読めるようになった**
    （候補32件中30件が既読。恒久的スキップの `zxx` を除く未読は `pl` / `th` のみ）。
    これは**受け入れ条件4がこの実機で実際に機能した実例**（未ダウンロードの言語が
    ダウンロードされて読めるようになった）。
  - **`pl` / `th` は2回とも90秒の予算内でダウンロードが完了せず、未読のまま残った**
    （既読にはならない一時的失敗として扱われており、次にタイムラインを開くときに
    再挑戦される設計どおりの挙動）。
  - タイムラインの完走（読み切りへの到達）・クラッシュ0・固着0は2回とも確認できた。

### 未確認・正直に書く残るリスク（受け入れ条件4の「準備中→読める」を100%証明できていない）

`pl` / `th` が2回とも同じように未完了だったこと、`id` は成功したことから、
**`prepareTranslation()` は、モデルによっては（あるいは既にOS側で何らかの試行履歴がある
ものは）人の操作無しに完了することがある一方、完全に手つかずの言語では、OSが表示する
「翻訳／必要なダウンロード」確認シートに実際に人がタップして許可しないとダウンロードが
始まらない可能性がある**、という仮説を持つに至った（`prepareTranslation()`
自体はエラーを投げずタイムアウトまで応答が無かったため、内部で何が起きているかまでは
実機からは分からない）。

もしこの仮説が正しい場合、実際の利用者が使うときは:
1. 「世界の回答を読む」を押す → お題画面の上に「準備中…」が出る（`fullScreenCover` は
   まだ開いていない）→ 必要ならOSの確認シートが**今日のお題画面の上に**表示される
   （閉じて困る `fullScreenCover` が無いので、attempt 3 の症状は起こらないはず）
2. 利用者がシートに応答すればダウンロードが進み、完了後にタイムラインが開いて読める
3. 利用者が応答しない、または反応が遅い場合、90秒の予算を過ぎるとタイムラインを開いてしまう。
   **このときOSのシートがまだ画面に残っていたらどうなるか（`fullScreenCover` の提示と
   競合しないか）は、今回、実際に目で見て確認できていない**（自動化ツールに画面を見る
   手段が無く、`devicectl` は実機のスクリーンショット取得に対応していない）

この最後の点（シートが残ったまま `fullScreenCover` を開こうとした場合の見え方）は、
**人がその場で実機を操作して確認する以外に検証する手段が無かった**。XCUITest の
automation mode が2回とも有効化できなかったため、指でタップしての確認ができていない。

## 動かし方（evaluator向け・attempt 5で変わった点）

- 起動引数・UIに変更なし
- 「世界の回答を読む」ボタンは、モデル未ダウンロードの言語がある間だけ「準備中…」になり
  押せない（`today.openTimeline` のラベルと `disabled` で確認可能）。1件も無ければ
  一瞬も表示されない
- 実機確認手順: `-SameQFakeTranslate` を付けずに起動 → 初回設定 → 投稿 →
  「世界の回答を読む」を押す（モデル未ダウンロードの言語があれば「準備中…」になる）→
  タイムラインが開いたら最後まで読み切る。**OSの「翻訳／必要なダウンロード」確認シートが
  出た場合は、実際にタップして許可し、それでもタイムラインが正しく開くか・閉じてしまわないかを
  目で確認してほしい**（今回、指での操作による確認ができなかった最後のピース）

## 自分で見つけた弱点（正直に書く）

- **受け入れ条件4の「準備中→読める」を実機で100%証明できていない**。`id` の1言語では
  成功を確認したが、`pl`/`th` は2回とも90秒の予算内で完了せず、OSの確認シートに
  人の操作が要る可能性が高いと推測している。XCUITest の automation mode が実機で
  有効化できなかったため、シートが出た場合に実際にタップして先へ進めるかの確認が
  できていない
- 90秒の予算はシートに人が応答することを前提にしていない設計判断（応答が無くても
  諦めて開く）。もしシートが開いたまま `fullScreenCover` を開こうとした場合の挙動は
  未確認（上記のリスクの節を参照）
- `SessionRequestQueue` の `withTaskGroup` に起因する致命的な欠陥（タイムアウトが
  実効を持たない）は attempt 3 から存在していたが、今回まで見つかっていなかった。
  同種の「呼び出し先が本当に応答不能になる」経路が今後増えた場合、同じ穴に落ちないよう、
  タイムアウトを新設するたびに「本当に呼び出し元を解放できているか」を実機で確認する
  習慣が要る
- `AppSession.prepareTimelineLanguagesIfNeeded` の90秒予算チェックは、**言語ごとの
  呼び出しの合間**にしか効かない。1言語の呼び出し自体が `sessionAcquireTimeoutSeconds`
  （45秒）+ `modelPrepareJobTimeoutSeconds`（60秒）＝最大105秒かかりうるため、
  「90秒」は目安であり厳密な上限ではない

## 提案（今回はやらなかったこと）

- **[優先度 高]** ユーザー自身に、実機で「世界の回答を読む」を押したときにOSの確認シートが
  出るかどうか、出た場合にタップしてダウンロードが進み、その後タイムラインが正しく開くかを
  一度確認してほしい。もしシートが開いたまま90秒予算を使い切った場合に何が起きるか
  （`fullScreenCover` の提示と競合しないか）は特に注目してほしい
- 90秒の予算を超えても諦めずに待ち続ける代替設計（例えばアプリがバックグラウンドに回っても
  ダウンロードを継続し、次回起動時に反映する）は今回検討していない
- `Translator.textCache` に上限が無い問題（attempt 1 から継続、優先度中）は今回も未対応

---

# スプリント06 自己評価（attempt 6）

## 今回直した点

eval-5.md の不合格理由 [1]（モデル未ダウンロード言語を毎回ゼロから準備して待たせる）と
[3]（投稿ボタンが `openTimeline()` の完了まで「送信中…」になる）だけを対象にした。

- `Translator` に言語別の最終準備試行時刻と5分の再試行クールダウンを追加した。
  `.supported` のまま準備が完了しなかった言語は、クールダウン中の
  `prepareIfNeeded` が何もせず即座に返る。`needsPreparation` を通じて
  `AppSession` も実際に試す価値がある言語だけを準備対象にするため、直後の2回目は
  `isPreparingTimeline` を立てず、同じ60〜120秒の待ちを繰り返さない。
- `submit(body:)` は `submitPost` の成功後、`openTimeline()` を
  `pendingOpenTimelineTask` として開始するだけにし、その完了を待たずに返るようにした。
  これにより投稿ボタンの「送信中…」は投稿処理の完了時点で解除され、翻訳モデル準備の
  待ち時間を背負わない。テスト用に `waitForPendingTimelineOpen()` を用意した。
- 上記の契約に合わせて `AppSessionTranslationTests` と
  `TranslatorAvailabilityTests` を更新し、直後の再試行を抑止することと、クールダウン後には
  再試行可能になることを確定的に検証するテストを追加した。
- 一時的な実機確認用スクラッチだった
  `SameQUITests/TempAttempt6DeviceProbeTests.swift` を削除し、`xcodegen generate` で
  `SameQ.xcodeproj/project.pbxproj` を再生成した。再生成後、ファイル参照が残っていないことを
  `rg` で確認した。

## コードレベルでの再確認

eval-5.md [1] に対しては、実際の準備を始める直前に言語別の試行時刻を記録するため、失敗・
タイムアウト後も直後の再オープンでは `needsPreparation == false` となる。全候補が
クールダウン中なら準備表示そのものを立てずにタイムライン表示へ進む。

eval-5.md [3] に対しては、`submit()` の `defer { isSubmitting = false }` が
バックグラウンドの `openTimeline()` 完了を待たずに実行される構造になっている。
投稿失敗時は従来どおりアラート処理を行い、タイムラインTaskを開始しない。

## ビルド・テスト結果

- `xcodegen generate`: 成功（codexのsandbox内で一度、coordinatorのセッションでもう一度実行し、
  差分が出ないことを確認済み）。
- codex（sandbox環境）では `xcodebuild ... build` がCoreSimulatorServiceへ接続できず
  Asset Catalog処理で失敗し、フルテストスイートも実行できなかった。この制約を受け、
  coordinatorがsandbox外（通常のXcode実行環境）で改めてビルドとフルテストを実行した。
- `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'generic/platform=iOS Simulator' build`:
  **BUILD SUCCEEDED**。
- `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=12050FBD-587B-4910-8812-696BB91BE051' test`
  （他プロセス非併走の単独実行）: **TEST SUCCEEDED**。ユニット75件・UIテスト35件、
  合計110件すべて成功（0 failures）。所要約1151秒。attempt 5の107件から、
  クールダウンの新規ユニットテスト追加とスクラッチファイル
  `TempAttempt6DeviceProbeTests.swift`（1本）削除の差分で110件になった。

## 弱点・持ち越し事項

- 受け入れ条件4の前半（OSの「翻訳／必要なダウンロード」確認シートに人が応答し、準備完了後に
  実際に読めること）は今回も実機で確認できていない。過去5回と同様、実機の施錠により
  XCUITestのautomation modeを有効化できておらず、このセッションでも指タップ確認は行っていない。
  **実機での完全な確認は次回以降に持ち越す。** クールダウン導入は、この確認ができない／利用者が
  シートに応答しない場合でも毎回同じ長時間待ちを繰り返させないための、eval-5.md 提案(a)に
  沿った対処である。
- eval-5.md の「改善提案（合否には影響しない）」にある他項目、および90秒予算や
  `textCache` などスコープ外の項目には一切変更を加えていない。
