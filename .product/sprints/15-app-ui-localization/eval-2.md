# スプリント 15 評価（attempt 2） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7/7（eval-1 の唯一の不合格点＝Plus 画面 PRICE 直下の和文が en/fr で英語化されたことを実機で確認） | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線すべて完走（unit+UI 約40ケース、アプリ側は全 green） | 0 | ✓ |
| 3 データ整合性 | 本スプリントは新規永続化なし。表示言語は OS 設定由来で、再起動しても一部だけ前の言語が残らない | 100% | ✓ |
| 4 回帰 | Sprint06 4/4・Sprint07 6/6・Sprint10 7/7・ユニット184/184・Sprint15 acceptance 8/8 | 100% | ✓ |
| 5 使用性 | 4（空状態・エラー表示・破壊的操作の確認そろう。英語も自然。軽微な引っかかりのみ） | 3以上 | ✓ |

**総合: 合格（passed）。** eval-1 の指摘 [1] は最小修正（`L10n.Plus.priceMonthlyNote` 追加＋`PlusView.swift:159` 差し替え）で解消済み。実機で en / fr / ja の Plus 画面を開いて直接確認した。

## 検証環境
- macOS / Xcode 26.6 / iPhone 17 シミュレータ（iOS 26.5, UDID 35AAC789-…, 起動中のもの）
- ビルド: `xcodebuild ... -configuration Debug build-for-testing` → `** TEST BUILD SUCCEEDED **`
- 起動引数: `-SameQResetState -SameQUseLocalBackend -SameQFakePlus -SameQFakeTranslate -AppleLanguages (en|ja|fr) -AppleLocale (en_US|ja_JP|fr_FR)`
- 到達しづらい画面: `-SameQBanned` / `-SameQForceOffline` / `-SameQRateLimitTestMode -SameQAnswerCount 12` / `-SameQScenario expired`
- 実施時刻: 2026-08-28 07:15〜07:40 JST
- 自作の XCUITest 巡回（`SprintFifteenEvalTourTests` / `SprintFifteenEvalTour2Tests`）で en/ja/fr の Plus・利用停止・通報ブロックシート・連打制限アラート・設定・タイムラインを撮影し、可視 staticText / button を全ダンプ。巡回テストは評価後に削除、`SameQ.xcodeproj` も `git checkout` で復元済み（作業ツリー clean）。
- スクリーンショット: `.product/sprints/15-app-ui-localization/eval-2-shots/`

### 自動テスト結果（自分で実行）
- `SameQTests`（ユニット）**184/184 passed**（5.9s）
- `SprintFifteenAcceptanceTests` **8/8 passed**（78.9s）
- 回帰 `SprintSixAcceptanceTests` **4/4** ＋ `SprintSevenAcceptanceTests` **6/6** ＋ `SprintTenAcceptanceTests` **7/7** = **17/17 passed**（444s）
- クラッシュ 0 / 新規クラッシュレポート 0 / タイムアウト 0
- 巡回テスト側で失敗した3ケースはいずれも **テストスクリプトのナビゲーション不備**（`today.openTimeline` の hittable 判定・`expired` シナリオ後の画面遷移・`-SameQForceOffline` が LocalBackend では失敗画面に落ちない）であり、対象画面のスクリーンショットとテキストダンプで**アプリ挙動そのものは正常**であることを確認済み。

## eval-1 [1]（唯一の不合格点）の再検証 — 解消

実機で Plus 画面を開いて「PRICE / 料金」直下の補足文言を確認した:

| 端末言語 | PRICE 直下の表示 | 判定 |
|---|---|---|
| en | `¥480` `/ month` → **`Monthly / Cancel anytime`** | ✓ 英語化された（旧: 「月額 / いつでも解約できます」） |
| fr | `¥480` `/ month` → **`Monthly / Cancel anytime`**（英語フォールバック） | ✓ |
| ja | `¥480` `/ 月額` → **`月額 / いつでも解約できます`** | ✓ 日本語のまま |

- 根拠: `eval-2-shots/en-plus-3.png`（PRICE 直下が "Monthly / Cancel anytime"）、`eval-2-shots/ja-plus-3.png`（"月額 / いつでも解約できます"）、テキストダンプで en/fr の Plus 画面全 staticText を確認し、和文は「フェイク翻訳のお題本文（`[EN]`/`[FR]` プレフィックス付き）」のみ＝ spec で対象外のユーザー生成コンテンツ。アプリUIの和文は0。
- Plus 画面の他の文言（"More expression with Plus" / "WHAT YOU GET WITH PLUS" / "Long-form posts" / "Plus-only stamps" / "Text decoration" / "Balloon decoration" / "Subscribe to Plus" / "RESTORE PURCHASE" / "Restore purchase" / 免責文）もすべて自然な英語。ja では全て対応する日本語。レイアウト崩れ・見切れなし（iPhone 17 目視）。

## 条件ごとの詳細

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | en 初回起動でコンセプト/規約同意/絵文字/ニックネーム/通知が全部英語 | ✓ | `en-01-concept` 目視＋`SprintFifteenAcceptanceTests` test02/03/08 green。コンセプト説明は意味の通る自然な英語（"Once a day, the whole world gets the same prompt. You never know when." 他）。**利用規約／プライバシーの本文は日本語のまま**だが spec「今回作る範囲」で本文は明示的に対象外 → 条件1の不合格理由にはしない（改善提案に記載） |
| 2 | en のまま 今日のお題／タイムライン／お題待ち／利用停止／設定／Plus を一巡してアプリの和文が出ない | ✓ | Plus（`en-plus-1〜3`）＝原因[1]解消を確認。利用停止（`en-banned` "This account can no longer be used" / "The operator has suspended this account..."）・通報ブロックシート（`en-safetySheet` "About this reply" / "Report this reply" / "Block this person" / "Cancel"）・連打制限アラート（`en-ratelimit-alert` title "Something went wrong" / body "Likes too fast. Please wait 8s and try again." / "OK"）・空ブロック一覧（"You haven't blocked anyone"）・設定全セクション（NOTIFICATIONS / PLUS / BLOCKED PEOPLE / ACCOUNT）・アカウント削除確認（"Delete your account?" / "Your account, posts, likes, blocks, and reports will all be erased." / "This can't be undone." / "Delete"）・タイムライン（"THE WORLD'S ANSWERS" / "Like" / "Swipe to meet another stranger" / "PROMPT" / "YOUR ANSWER"）すべて英語。ダンプ上の和文はフェイク翻訳のお題／回答本文のみ（対象外） |
| 3 | ja に戻すと同じ画面がすべて日本語 | ✓ | Plus（`ja-plus-3`）・利用停止（`ja-banned`）・連打制限アラート（"うまくいきませんでした" / "いいねが短時間に多すぎます。8秒待ってからもう一度お試しください。"）・通報ブロックシート（"この回答について" / "この回答を通報する" / "この人をブロックする" / "キャンセル"）すべて日本語で自然 |
| 4 | fr など ja/en 以外は英語表示、内部記号の羅列が出ない | ✓ | コンセプト・設定（`SprintFifteenAcceptanceTests` test04/07 green）・Plus（`fr-plus-1〜3` "Monthly / Cancel anytime"）・お題待ち相当画面すべて英語へフォールバック。記号・英数字の羅列なし。ja 見出しへの誤フォールバックなし |
| 5 | 英語表示で見切れ・はみ出し・要素の重なりが無い | ✓ | iPhone 17 で Plus / 設定 / 通報シート / 利用停止 / アラートを目視。ボタンラベル（"Subscribe to Plus" / "Restore purchase" / "Delete account"）・セクション見出し・本文いずれも折り返し正常、クリップ・重なりなし |
| 6 | Sprint06（本文/お題翻訳）・Sprint07（ニックネーム音写）が不変 | ✓ | `SprintSix` 4/4・`SprintSeven` 6/6・ユニット184/184 green。attempt 2 の差分は `L10n.Plus.priceMonthlyNote` 追加と `PlusView.swift:159` の1行差し替えのみで、Translator / NicknameTransliterator に一切触れていない |
| 7 | 端末言語を変えて起動し直すと一部だけ前の言語が残らない | ✓ | `L10n` は `Locale.preferredLanguages.first` を起動時1回だけ確定。`-AppleLanguages` を毎回変えて再起動する acceptance test01〜08 が全 green。ja/en/fr の巡回で混在なし。新規 `priceMonthlyNote` も `useEnglish` の `let` 評価時に確定するので途中でブレない |

## 改善提案（合否には影響しない）

1. **[中] 利用規約・プライバシーポリシー本文が英語端末でも日本語のまま**。spec「今回作る範囲」で本文は対象外と明記のため不合格にはしないが、受け入れ条件1「日本語が1文字も残らない」と文面上ねじれている。英語ユーザーが同意対象を読めない状態は同意取得として弱い。要旨だけでも英訳する価値あり。ユーザーに扱いの確認を推奨（eval-1 でも指摘済み・未対応）。
2. **[小] 連打制限アラートのタイトルが "Something went wrong" / "うまくいきませんでした"**。本文は的確（"Likes too fast. Please wait 8s and try again."）だが、タイトルがエラー全般の使い回しでレート制限の文脈と噛み合っていない。"Slow down" / 「少し落ち着いて」等に寄せると分かりやすい（eval-1 でも指摘済み・未対応）。
3. **[小] 3つの Plus Service の `periodDescription` / `displayName` に残る日本語リテラル固定**（`RevenueCatPlusService.swift:67` / `StoreKitPlusService.swift:34` / `FakePlusService.swift:81`）。今回ビューから `periodDescription` の参照は消えたが、`displayName: "Plus （月額）"` は将来 PlusView 以外で使うと同じ再発リスク。次リリース前チェックで L10n 化推奨。
4. **[小] アカウント削除確認ダイアログにキャンセル導線が視認しづらい**（`en-settings-delete-confirm.png` では "Delete" のみが見える）。スプリント11の範囲であり本スプリントの対象外だが、破壊的操作のキャンセル動線は明示されているほうが安全。

## 評価できなかったもの
- **通信失敗（オフライン）画面の実画面**: `-SameQUseLocalBackend` を付けると LocalBackend が端末内で応答するため `-SameQForceOffline` でも失敗画面に落ちず、今回の巡回では再到達できなかった。ただし該当文言（`L10n.Failure.title = "Couldn't load" / retry = "Try Again"`）は `useEnglish` ゲート済みで attempt 2 の差分は一切触れておらず、attempt 1 の評価で英語表示（"Couldn't load" / "Try Again"）が確認済み。回帰リスクなしと判断。
- **Plus の購入失敗ダイアログ**（spec 評価者注記）: シミュレータに StoreKit 構成が無く購入フローが進まないため未到達。attempt 1 と同じ制約。購入導線周辺の固定文言（"Subscribe to Plus" / 復元セクション / 免責）はすべて英語で確認済み。失敗時アラートは連打制限アラートと同じ `L10n` 経路（英語表示を確認済み）。
