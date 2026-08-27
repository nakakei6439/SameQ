# スプリント 15 評価（attempt 1） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/7（条件2が未達。条件4も同一原因で一部影響） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線すべて完走 | 0 | ✓ |
| 3 データ整合性 | 問題なし（本スプリントは新規永続化なし。言語は OS 設定由来で再起動後も一致） | 100% | ✓ |
| 4 回帰 | Sprint06 4/4・Sprint07 6/6・Sprint10 7/7・Sprint11 4/4・Sprint13 4/4・ユニット184/184 | 100% | ✓ |
| 5 使用性 | 4（空状態・エラー表示・確認ダイアログ完備。英語も自然。ただし Plus 画面に和文が1箇所露出） | 3以上 | ✓ |

**総合: 不合格（needs_fix）。** 原因は1件、修正は小さい。

## 検証環境
- macOS 26.5.2 / Xcode 26.6 / iPhone 17 シミュレータ（iOS 26.5, UDID 35AAC789-…）
- ビルド: `xcodebuild ... -configuration Debug build-for-testing` → `** TEST BUILD SUCCEEDED **`
- 起動引数: `-SameQResetState -SameQUseLocalBackend -SameQFakeTranslate -AppleLanguages (en|ja|fr)`
- 到達しづらい画面（利用停止・通信失敗・お題待ち）は `-SameQBanned` / `-SameQForceOffline` / `-SameQScenario expired` で再現
- 実施時刻: 2026-08-28 06:35〜07:05 JST
- 自作の XCUITest スクリーンショット巡回で en/ja/fr の各画面を撮影・目視（巡回テストは評価後に削除、作業ツリーは clean）
- スクリーンショット保存先: `/tmp/sameq-eval/tourshots/named/` および `/tmp/sameq-eval/tour2shots/named/`

### 自動テスト結果（自分で実行）
- `SprintFifteenAcceptanceTests` 8/8 passed（80.4s）
- 回帰: `SameQTests` 184/184 + `SprintTen`(7)/`SprintEleven`(4)/`SprintThirteen`(4) = 199/199 passed
- 回帰（条件6 明示分）: `SprintSix` 4/4 + `SprintSeven` 6/6 passed
- クラッシュ 0 / 新規クラッシュレポート 0 / タイムアウト 0

## 不合格の原因（これを直せば通る）

### [1] 端末言語が英語（および fr）でも、Plus 画面の料金補足が日本語のまま出る
- **再現手順**:
  1. 端末言語を英語にして初回起動 → オンボーディングを「Maybe later」まで完了
  2. 今日のお題画面を下スクロールし「Want to write more?」→ Plus 画面を開く（設定→「See Plus」でも可）
  3. 「PRICE」セクションを見る
- **期待**: spec「Plus の各画面を一巡しても、アプリが出す日本語の文言が現れない」（受け入れ条件2）。英語の補足（例:「Monthly / Cancel anytime」）が出る
- **実際**: 「$2.99 / month」の直下に **「月額 / いつでも解約できます」** が日本語のまま表示される。fr 端末でも同じ（受け入れ条件4「英語で表示される」にも反する）
- **根拠**:
  - スクリーンショット `/tmp/sameq-eval/tour2shots/named/en-plus-1-top.png`, `en-plus-4-bottom.png`（PRICE 直下に和文）
  - コード: `SameQ/Feature/Plus/PlusView.swift:159` が `Text(product.periodDescription)` をそのまま描画
  - `periodDescription` は L10n を通っておらず、実装3か所すべてで日本語リテラル固定:
    - `SameQ/Backend/RevenueCatPlusService.swift:67` → `periodDescription: "月額 / いつでも解約できます"`
    - `SameQ/Backend/StoreKitPlusService.swift:34` → 同上
    - `SameQ/Backend/FakePlusService.swift:81` → 同上
  - 本番の RevenueCat 経路（`RevenueCatPlusService`）でも同じ固定文字列なので、実機の英語端末でも必ず日本語が出る
- **補足（同種の潜在リスク・今回は画面に出ていないので不合格理由にはしない）**: 上記3ファイルの `displayName: "Plus （月額）"` も日本語リテラル固定。現状 `PlusView` では未使用だが、将来 `displayName` を表示に使うと同じ問題が再発する。あわせて L10n 化しておくと安全。

**想定される修正**: `L10n.Plus` に `priceMonthlyNote`（`useEnglish ? "Monthly / Cancel anytime" : "月額 / いつでも解約できます"` 相当）を追加し、`PlusView.swift:159` をそれに差し替える。`periodDescription` はプロダクト実体（StoreKit/RevenueCat）由来のロケール非依存メタなので、ビュー側で L10n に置き換えるのが筋。3つの Service の固定文字列は表示に使わないなら空文字でも可。

## 条件ごとの詳細

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | en 初回起動でコンセプト/規約同意/絵文字/ニックネーム/通知が全部英語 | △ | コンセプト・絵文字・ニックネーム・通知の各画面は文言・ボタンとも英語で和文なし（`en-ob-1〜6`）。規約同意画面はナビ・見出し・チェック文言・ボタンは英語。**利用規約／プライバシーの本文は日本語のまま**だが、これは spec「今回作る範囲」で明示的に対象外（本文は除外）なので条件1の不合格理由にはしない。改善提案に記載 |
| 2 | en のまま今日のお題/タイムライン/お題待ち/利用停止/設定/Plus を一巡してアプリの和文が出ない | ✗ | 利用停止（`en-banned`）・通信失敗（`en-offline` "Couldn't load / Try Again"）・お題待ち（`en-waiting-real`）・投稿拒否系の連打制限アラート（`en-like-limit-alert-final` "Likes too fast. Please wait 8s…"）・通報/ブロックの全ステージ（`en-safety-1〜5`）・空のブロック一覧（"You haven't blocked anyone"）・設定全セクション（`en-settings-top/mid`）はすべて英語。**Plus 画面のみ「月額 / いつでも解約できます」が日本語**（原因[1]） |
| 3 | ja に戻すと同じ画面が全部日本語 | ✓ | 設定（`ja-settings-top`）・お題待ち（`ja-waiting-real`）・利用停止（`ja-banned`）・通信失敗（`ja-offline`）・オンボーディング（acceptance test08）すべて日本語で自然 |
| 4 | fr など ja/en 以外は英語表示、内部記号の羅列が出ない | △ | コンセプト・設定・利用停止・通信失敗・お題待ちすべて英語へフォールバック（`fr-*`）。記号羅列なし。ただし Plus 画面は原因[1]の日本語が fr でも出る |
| 5 | 英語表示で見切れ・はみ出し・重なりが無い | ✓ | iPhone 17 で全画面を目視。ボタンラベル・文字数カウンター（`en-today-overlimit-counter` "140/140"）・設定項目名いずれも折り返し正常、クリップ・重なりなし。iPhone SE 幅・iPad は未確認（対象デバイスは iPhone のみ・generator も申告済み） |
| 6 | Sprint06（本文/お題翻訳）・Sprint07（ニックネーム音写）が不変 | ✓ | `SprintSix` 4/4・`SprintSeven` 6/6・`AppSessionTranslationTests`/`NicknameTransliteratorTests` 含むユニット184/184 すべて green。en 端末でもニックネーム音写は従来どおり（`SprintSeven test02`） |
| 7 | 端末言語を変えて起動し直すと一部だけ前の言語が残らない | ✓ | `L10n` は `Locale.preferredLanguages.first` を起動時1回だけ確定（`L10n.swift:22-35`）。`-AppleLanguages` を変えて再起動する acceptance test01〜08 が全 green。ja↔en↔fr 切替の巡回でも混在なし |

## 改善提案（合否には影響しない）

1. **[中] 利用規約・プライバシーポリシー本文が英語端末でも日本語のまま**（`en-ob-2-terms.png`, `en-legal-sheet.png`）。spec「今回作る範囲」で本文は対象外と明記されているため不合格にはしないが、英語ユーザーが「同意します」にチェックする対象を一切読めない状態は同意取得として弱い。spec 側の「対象外」と受け入れ条件1「日本語が1文字も残らない」は文面上ねじれているので、ユーザーに扱いの確認を推奨。少なくとも要旨だけでも英訳を用意する価値あり。
2. **[小] 連打制限アラートのタイトルが "Something went wrong"**（`en-like-limit-alert-final.png`）。本文「Likes too fast. Please wait 8s and try again.」は的確だが、タイトルがエラー全般の使い回しで、レート制限という文脈と噛み合っていない。日本語側の相当文言も確認のうえ、"Slow down" 等に寄せると分かりやすい。
3. **[小] Plus 画面 `displayName` の日本語リテラル固定**（原因[1]補足）。今は非表示だが将来の地雷。`periodDescription` を直すついでに L10n 化推奨。
4. **[小] 広い画面での英語レイアウト目視**（generator も申告済み）。iPhone SE 幅で "Restore Purchase" / "Subscribe to Plus" 等の長いボタンラベルの折り返しを一度確認しておくと安心。

## 評価できなかったもの
- **Plus の購入失敗ダイアログ**（spec 評価者注記に記載）: `plus.purchase` タップ後の失敗表示までは到達できなかった（StoreKit 構成がシミュレータに無く、購入フローが進まない）。ただし購入導線周辺の固定文言（"Subscribe to Plus" / 復元セクション / 免責）はすべて英語であることを確認済み。失敗時のアラート文言は `AppSession` 経由で `L10n.errorMessage(for:)` を通す実装になっており、他のエラーアラート（連打制限）が英語化されていることから同経路と推定されるが、実画面は未確認。
- **実機の Apple Translation 経路**（`-SameQFakeTranslate` 使用のため）。UI 言語と翻訳は独立なので本スプリントの評価には影響しないと判断。
