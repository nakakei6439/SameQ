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
