# スプリント 14 attempt 1: 仕様未定義のため着手不可（blocked）

## 状況

`autoloop.sh`（scripts/autoloop.sh, 行26）が `last_sprint="11"` を
ハードコードしたまま**スプリント番号を機械的にインクリメント**する実装のため、
2026-08-27 15:59:27 にスプリント13が合格した直後に `current_sprint=14` へ
自動進行した（コミット `6e13f22 autoloop: advance to sprint 14`、
`.product/autoloop-logs/main.log` iteration 4〜5）。

しかし `.product/spec.md` の「スプリント計画」セクション（行108〜334）は
スプリント01〜13までしか定義していない。機能一覧も F01〜F36 までで、
F01〜F34 はすべて01〜11のいずれかに含まれ、F35/F36 は12/13に含まれている。
**`.product/spec.md` には「スプリント 14」が存在しない**。

この状態で generator が「現在のスプリントの実装」を進めると、仕様に無い機能を
作り込むことになる。`generator.md` の「仕様に無いものを作らない」「
複数スプリントをまとめて進めない」「先のスプリントの機能を先取りしない」に
直接反するため、**着手を停止してユーザー（planner）に判断を仰ぐ**。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| （受け入れ条件が存在しない） | 未達 | `.product/spec.md` にスプリント14の定義が無い。バックログの「アプリ自体のUIローカライズ」(PROGRESS.md 行75〜88) はユーザー確定済み・スプリント未割当 |

## 動かし方（evaluator 向け）

該当なし（着手していない）。

## 自分で見つけた弱点

1. **autoloop.sh の `last_sprint="11"` が古いまま**。スプリント12・13が追加された際に
   更新されていないため、本来終了すべきでない iteration で generator を起動し続ける。
   修正案：`last_sprint` を `spec.md` の `### スプリント \d+` の最大値から動的に
   取得する or、`spec.md` に存在しないスプリント番号へ進んだら正常終了する。
2. **state.json の `current_sprint="14"` はユーザー操作無しには解消しない**。
   autoloop は `current_sprint == last_sprint` のときのみ終了するため、
   `last_sprint` を直すか、`state.json` を手で `current_sprint="13"` に戻すか、
   `.product/spec.md` にスプリント14の定義を追加するかのいずれかが必要。

## 提案（今回はやらなかったこと）

**A. バックログ「アプリ自体のUIローカライズ」をスプリント14として正式採用する案**（推奨）

- PROGRESS.md 行75〜88 でユーザー確定済み（2026-08-18）
- 方針案:
  - String Catalog（iOS 15+ の正式機構、`.xcstrings`）を導入
  - 既存11スプリントで追加・変更した日本語文字列のうち、ユーザー向け文言を
    `.xcstrings` ベースキーに差し替え（利用規約本文など法的テキストは対象外）
  - 対象言語: 日本語 / 英語 / 韓国語 / アラビア語（RTLレイアウト確認込み）
  - 翻訳ソース: 自前（生成AI 翻訳は禁止・外部翻訳APIも禁止の方針）。
    まず ja と en を揃え、ko/ar は F23 のニックネーム音写同様に端末内翻訳
    （Translation Framework の`.translationTask` を活用）に寄せる案が筋
  - 影響範囲: `SameQ/Feature/Onboarding`, `Today`, `Timeline`, `Waiting`,
    `Banned`, `Settings`, `Plus` 配下の全 View（`Localizable.strings` 等が
    現状ゼロのため、影響範囲は実装しながら膨らむ可能性あり）
- ただし**方針確定は planner の仕事**。generator は仕様が追加されるまで着手しない。

**B. autoloop.sh の `last_sprint` を直すだけの案**（最低限）

- `last_sprint="13"` へ更新、もしくは spec.md から動的に取る
- スプリント14 を「プロジェクト完了」とみなし、autoloop を正常終了させる
- バックログを着手したい場合はユーザーが別途 spec.md を更新してから autoloop 再起動

**C. state.json を `current_sprint="13"` に戻す案**（最小）

- autoloop を回さないことが前提
- バックログの着手は次回以降のセッションで別途ユーザーが spec.md を更新する

## 申し送り（次セッション / ユーザー宛）

- 状態: `current_sprint="14"`、`status="in_progress"`、`attempt=1`
- autoloop は本作業の冒頭で `pkill -f autoloop.sh` により停止済み
  （多重起動を避けるため `.product/autoloop.lock` は autoloop の trap で削除済み。
   次回 autoloop 起動時はそのまま走らせられる）
- **判断が必要**: バックログの「アプリ自体のUIローカライズ」を
  `.product/spec.md` のスプリント14として正式採用するか / autoloop を直して終了するか
- 上記の `A` を採用する場合、`.product/spec.md` の `### スプリント 14` 節と
  受け入れ条件（PROGRESS.md 行83「Localizable.strings 等が現状ゼロのため、
  影響範囲は実装しながら膨らむ可能性あり」を反映）を planner が先に書き、
  generator はその plan を読んで着手する形が筋