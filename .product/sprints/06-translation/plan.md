# スプリント06 修正計画（attempt 2）

## 受け入れ条件（spec.md 194〜201行）
- [ ] 端末言語と異なる言語の回答が端末言語で表示される
- [x] 翻訳関連UIが存在しない（評価済み・維持のみ）
- [x] 非対応言語は一度も現れずスキップ（評価済み・維持のみ）
- [ ] モデル未取得時は初回のみ準備中表示、2回目以降は待たない（シミュレータでは疑似モードで代替確認）
- [ ] お題も端末言語で表示され、言語設定を変えて起動し直すとその言語になる
- [x] 翻訳失敗時エラーダイアログを出さずスキップ（評価済み・維持のみ）
- [ ] 機内モードでもモデル取得済み言語なら翻訳表示できる（実機必須・今回スコープ外と明記）

## 直す4点（eval-1.md / PROGRESS.md 準拠）
1. **[最優先] 翻訳キューが同一言語ペアの2件目で永久固着**
   - `Translator` のセッション要求を「言語ペアごとに1回だけ要求し、以後はキャッシュを再利用する」設計に変える
     （＝同じ値の `Configuration` を二度と代入しない。根本原因を構造的に無くす）。
   - キュー機構をフレームワーク非依存の `SessionRequestQueue<Session>`（ジェネリック）として切り出し、
     実機・シミュレータ差に関係なくユニットテストで直接検証できるようにする。
   - 保険として、セッションが一定時間（45秒）来なければタイムアウトで諦めて次へ進む。
2. **シミュレータでの実処理経路の検証手段が無い**
   - Debug限定・起動引数 `-SameQFakeTranslate` を追加。有効なとき `Translator.translate` は
     実際の `TranslationSession` を使わず `[<言語コード>] <原文>` の決定的変換を返す。
     `zxx` は非対応固定（既存の非対応投稿検証と一致させる）。
   - キュー・キャッシュ・スキップ判定など「翻訳の周りのロジック」は本番と同じ経路を通す
     （バイパスするのは `TranslationSession` の生成だけ）。
3. **端末言語が日本語以外だとお題が原文のまま**
   - 原因はほぼ1（同一ペア連続でお題の直後にjaの回答を引くと固着）と2（シミュレータでは翻訳不可）の複合。
   - 設計判断: お題は「常に1つだけ有効・スキップの代替が無い」ため、翻訳できない場合は
     引き続き原文へフォールバックする（決定を維持し、self-reviewに理由を明記）。1の修正で
     実際に翻訳が機能する環境では正しく翻訳されるようにする。
4. **翻訳できずスキップした回答が恒久的に既読になる**
   - `Backend.nextTimelinePost` に `excluding` と `autoMarkViewed` を追加（デフォルト値は
     プロトコル拡張で用意し、既存呼び出し元・既存テストは無変更で動く）。
   - 既読にするのは「実際に表示できると確定した時点」（翻訳成功、または恒久的に非対応と判定できた時点）のみ。
   - 一時的な失敗（タイムアウト等）は `markPostViewed` を呼ばず、その巡回内だけ `excluding` に入れて
     無限ループを避ける。次回の巡回では再挑戦できる。

## 影響範囲
- `SameQ/Backend/Translator.swift`（大きく変更）
- 新規 `SameQ/Backend/SessionRequestQueue.swift`
- `SameQ/Backend/LaunchOptions.swift`（`-SameQFakeTranslate` 追加）
- `SameQ/Backend/Backend.swift`（プロトコル拡張で後方互換）
- `SameQ/Backend/LocalBackend.swift`（`nextTimelinePost` 実装・`markPostViewed` 追加）
- `SameQ/Session/AppSession.swift`（`drawNextPost` / `syncPromptTranslation`）
- 新規ユニットテスト（`SessionRequestQueue` の固着再現・修正確認、`Translator` 疑似モード、
  `LocalBackend` の一時失敗/恒久失敗の既読区別）
- 既存の呼び出し元・既存テストは protocol extension のデフォルト引数により無変更のまま通す想定

---

# 修正計画（attempt 3、eval-2.md 対応）

## 直す2点
1. **[最重要] キャッシュしたセッションが実機では無効になる**
   - `SessionRequestQueue` から「セッションをキーごとにキャッシュして使い回す」設計を撤去する。
   - 新しい契約: `perform(key:body:)` は毎回**必ず**新しいセッション取得を要求し（`onNeedsSession`
     を毎回呼ぶ）、取得できたセッションで `body`（実際の `session.translate(_:)`）を
     **`.translationTask` のクロージャと同じ非同期スコープの中で最後まで実行してから**結果を返す。
     セッションを外へ持ち出して後で使う経路を型的に無くす（`resolve` はセッションをキャッシュに
     入れず、その場で `body` に渡して終わるまで待つだけ）。
   - 同一言語ペアの連続要求でも `.translationTask` を確実に再発火させるため、`configuration` の
     差し替えロジックを「新しい `Configuration` を作って上書き」から「既存のインスタンスに対して
     `invalidate()` を呼び、必要なら同じインスタンスの `source`/`target` を書き換える」方式に変える
     （新しいインスタンスに差し替えると、SwiftUI が次のレンダーで見る最終値は無効化前と等価になり
     再実行されない。事前にSDKの `.swiftinterface` を確認し `invalidate()` が `mutating func` で
     `source`/`target` も `var` であることを確認済み）。
2. **`session.translate(_:)` 自体にタイムアウトが無い**
   - `SessionRequestQueue.perform` の中で、取得したセッションに対する `body` の実行を
     `withTaskGroup` でタイムアウト用の `sleep` と競走させる。タイムアウトが勝ったら
     `onJobTimeout(session)` を呼んでから諦める（Translator側で `session.cancel()`(iOS 26+)を
     呼び、応答不能な `translate(_:)` へ中断を伝える保険）。`withTaskGroup` は抜ける前に
     残っている子タスクの完了を待つ仕様のため、`cancel()` を呼ばないとタイムアウトの意味が
     薄れることを検証用の使い捨てスクリプトで確認済み。
   - タイムアウトした場合は `.unavailable(permanent: false)`（既存の仕組みをそのまま使う）。

## 削るもの
- `SessionRequestQueue.sessionsByKey`（セッションキャッシュ）とそれに依存する既存ユニットテスト
  5本（`SessionRequestQueueTests`）。新しい契約（毎回セッション取得・キャッシュしない）に合わせて
  書き直す。

## 影響範囲
- `SameQ/Backend/SessionRequestQueue.swift`（契約を大きく変更）
- `SameQ/Backend/Translator.swift`（`sessionQueue.perform` を使う形に書き換え、`configuration`
  差し替えロジックの修正、`session.cancel()` の呼び出し追加）
- `SameQTests/SessionRequestQueueTests.swift`（新しい契約に合わせて書き直し）
- `SameQ/App/TranslationHostView.swift`（`translator.resolve` が非同期でセッションを使い切るように
  なるだけで、呼び出し方自体は変わらない見込み）
- シミュレータでの `-SameQFakeTranslate` 経路・`TranslationOutcome`・既読区別の仕組みは変更しない
  （壊さないことを既存テストで確認する）
- **実機での確認が必須**（`-SameQFakeTranslate` 無しでタイムラインを読み切りまで）
