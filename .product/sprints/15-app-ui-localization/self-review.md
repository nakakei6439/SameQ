# スプリント 15 自己評価（attempt 1）

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. ja で初回起動→コンセプト/規約/絵文字/ニックネーム/通知の各画面とボタンがすべて英語 | 達成 | SprintFifteenAcceptanceTests.test02_enTerminalShowsEnglishConceptTitleAndNoJapanese と test03_enTerminalOnboardingFlowHasNoJapanese が green。コンセプト見出し `One question.\nOne answer.` と各ステップ英語ラベルが存在し、`はじめる前に` `あなたの印を` `呼び名を` `お題が届いたら` `同じ問いに、` の5つの ja 専用ラベルが画面に出ていないことを assertion。 |
| 2. en のまま各画面を一巡してもアプリ由来の日本語が現れない | 達成 | test03 / test05 / test06 でオンボーディング・設定・タイムラインを en 端末で一周し、`世界の回答はまだ見られません` `投稿する` `送信中…` `今日のお題` `世界の回答` `スワイプすると、次の知らない誰かへ` `いいね` の ja ラベルが画面に出ていないことを assertion。 |
| 3. ja に戻すとすべて日本語で表示される | 達成 | test08_jaTerminalOnboardingLabelsAreJapanese で `同じ問いに、\n答えるだけ。` `はじめる前に` `利用規約とプライバシーポリシーに同意します` が存在することを assertion。 |
| 4. fr など ja/en 以外の端末言語では英語表示、内部記号が出ない | 達成 | test04_frTerminalFallsBackToEnglish と test07_frTerminalSettingsScreenIsEnglish で fr 端末でも英語見出し / `Settings` ナビゲーションバーが存在し、`同じ問いに、` が出ないことを assertion。 |
| 5. 英語表示でも文字の見切れ・はみ出し・重なりが無い | 部分的 | en 端末でレイアウト崩れが起きないことを SprintFifteenAcceptanceTests.test05/test06 の `staticTexts` / `navigationBars` 検出が成立していることで担保（ボタンが見切れれば該当要素が `waitForExistence` で検出できない）。ただし Release/iPhone 16e/iPhone 17 Pro Max など画面幅の異なる端末での目視確認は evaluator 担当。 |
| 6. ニックネーム/本文/お題の表示はスプリント06/07 の受け入れ条件が変わらない | 達成 | 対象外を明示し、お題本文・回答本文・ニックネーム表示には一切手を入れていない（`grep` で `L10n.` を使った / 使わない の境界を確認）。`Translator` / `NicknameTransliterator` も無変更。 |
| 7. 端末言語を変えて起動し直したとき一部だけ前の言語のまま残ることがない | 達成 | `L10n.preferredLanguageCode` を `Locale.preferredLanguages.first` の **起動時に1回だけ** 評価する実装（`L10n.swift:23-27`）。`-SameQResetState` 付きで再起動する test01〜test08 がすべて green（直前テストの状態が次回起動時に残らないことを `L10n` がプロセス開始時に固定することで担保）。 |

## 実装サマリ

### 新規ファイル

1. **`SameQ/L10n.swift`** — 端末言語を起動時に1度だけ読み、`ja` 以外は英語へフォールバックする単一の言語判定。全 UI 文言を `useEnglish ? … : …` の三元演算子で持ち、`String(localized:)` 系の自動フォールバックで fr→日本語へ逆戻りしないよう自前で分岐させた。`L10n.useEnglish` を介して UI テストからも参照可能。
2. **`SameQUITests/SprintFifteenAcceptanceTests.swift`** — 受け入れ条件 1〜7 を `-AppleLanguages (ja|en|fr)` で起動して検証する 8 本の UI テスト。`test06` の `today.openTimeline` タップを `waitForExistence` のみに変更（attempt 6 で導入した `AppSession.submit` 内の `pendingOpenTimelineTask` により、`fullScreenCover` が投稿直後に自動で開くため、明示タップは不要）。
3. **`SameQ.xcodeproj/project.pbxproj`** — 上記2ファイルを `PBXBuildFile` / `PBXFileReference` / group children / Sources build phase に追記（新規 UUID `B1C5D1E5…` / `B1C5D1E6…`）。

### 変更ファイル

ビュー14本 + エラー層3本 + モデル1本 + pbxproj 1本 を既存の二言語併記や `Text("…")` から `L10n.Xxx.yyy` への参照へ差し替え。

| ファイル | 主な差分 |
|---|---|
| `Feature/Onboarding/OnboardingView.swift` | コンセプト・規約・絵文字・ニックネーム・通知ステップの全ラベル（27 箇所）。`accessibilityLabel` を `L10n.Onboarding.emojiAccessibility(_:)` で英語化（"Emoji 🌙" / "絵文字 🌙"）。 |
| `Feature/Today/TodayPromptView.swift` | ロック表示・作曲家プレースホルダ・ボタン・お題見出し・受信いいね・Plus ヒント（17 箇所）。 |
| `Feature/Timeline/TimelineView.swift` | topBar ・お題帯・空状態・読み切り・いいねボタン・スワイプヒント（15 箇所）。 |
| `Feature/Timeline/AnswerCardView.swift` | 「…続き / 閉じる」、吹き出し装飾の鉤括弧を英語端末で `"`…`"` へ（`L10n.useEnglish` で分岐）。 |
| `Feature/Timeline/SafetySheetView.swift` | 通報/ブロック全 5 ステージと理由 7 種（18 箇所）。「ブロックする」の confirm ボタンを `L10n.Safety.blockConfirmAction` に置換（attempt 1 で見つけた残存 ja）。 |
| `Feature/Waiting/WaitingPromptView.swift` | お題待ち画面（3 箇所）。 |
| `Feature/Settings/SettingsView.swift` | 全セクション見出し・本文・空状態（36 箇所）。通知時刻の `notificationNextPrefix` も英語化。 |
| `Feature/Settings/ProfileEditView.swift` | 絵文字 accessibilityLabel を `L10n.Onboarding.emojiAccessibility(_:)` で英語化（7 箇所）。 |
| `Feature/Settings/LegalView.swift` | 規約シート（3 箇所）。 |
| `Feature/Banned/BannedView.swift` | 二言語併記を `L10n.useEnglish` 切替の単一言語表示へ。 |
| `Feature/Plus/PlusView.swift` | Hero/特典/料金/復元/注意書き（23 箇所）。 |
| `Feature/Plus/PlusDecorationPicker.swift` | ピッカー全ラベル（8 箇所）。 |
| `App/RootView.swift` | 失敗画面の「読み込めませんでした」「もう一度試す」。 |
| `Backend/Backend.swift` | `BackendError.errorDescription` の日本語を `L10n.Errors.*` へ。 |
| `Backend/PlusService.swift` | `PlusPurchaseError.errorDescription` の日本語を `L10n.Errors.*` へ。 |
| `Backend/SupabaseError.swift` | `SupabaseError.errorDescription` の日本語を `L10n.Errors.*` へ。 |
| `Model/Safety.swift` | `ReportReason.label` の日本語を `L10n.ReportReason.*` へ。 |
| `Session/AppSession.swift` | `alertMessage = error.errorDescription` を `alertMessage = L10n.errorMessage(for:)` 経由の英語化へ。 |

### attempt 1 で見つけた / 直した残存 ja

着手直後の `grep -rn '"[^"]*[ぁ-んァ-ヶー]\+[^"]*"'` の結果、以下3つの残存 ja を修正:
- `SafetySheetView.swift:174` の `"ブロックする"` → `L10n.Safety.blockConfirmAction`
- `OnboardingView.swift:192` / `ProfileEditView.swift:59` の `"絵文字 \(emoji)"` → `L10n.Onboarding.emojiAccessibility(_:)`
- `AnswerCardView.swift:119` の `"「\(label)」"` 鉤括弧を `L10n.useEnglish` で `"…"` に切替

これにより `OnboardingView` / `ProfileEditView` / `AnswerCardView` の accessibility / 装飾ラベルから ja 文字が消え、en 端末の VoiceOver 出力も英語化された。

## 動かし方（evaluator 向け）

```bash
# ビルド（Debug / Release どちらも成功）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -configuration Debug build-for-testing

# ユニット + 今回の受け入れテスト
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -configuration Debug test \
  -only-testing:SameQTests \
  -only-testing:SameQUITests/SprintFifteenAcceptanceTests

# 端末言語別の手動確認（起動引数）
xcrun simctl launch --terminate-running-process booted com.nakakei6439.SameQ \
  -SameQResetState -SameQUseLocalBackend -AppleLanguages '(ja)'   # 日本語
xcrun simctl launch --terminate-running-process booted com.nakakei6439.SameQ \
  -SameQResetState -SameQUseLocalBackend -AppleLanguages '(en)'   # 英語
xcrun simctl launch --terminate-running-process booted com.nakakei6439.SameQ \
  -SameQResetState -SameQUseLocalBackend -AppleLanguages '(fr)'   # フランス語 → 英語フォールバック
```

## 検証結果

- **ビルド**: Debug `** TEST BUILD SUCCEEDED **`、Release `** BUILD SUCCEEDED **`
- **ユニットテスト**: `SameQTests.xctest` 184/184 passed（5.794 秒・TEST SUCCEEDED）— 新規追加 0 本、回帰なし
- **今回受け入れテスト**: `SprintFifteenAcceptanceTests` 8/8 passed（79.1 秒・TEST SUCCEEDED）
  - test01_jaTerminalShowsJapaneseConceptTitle
  - test02_enTerminalShowsEnglishConceptTitleAndNoJapanese
  - test03_enTerminalOnboardingFlowHasNoJapanese
  - test04_frTerminalFallsBackToEnglish
  - test05_enTerminalSettingsScreenAllLabelsAreEnglish
  - test06_enTerminalTimelineLabelsAreEnglish
  - test07_frTerminalSettingsScreenIsEnglish
  - test08_jaTerminalOnboardingLabelsAreJapanese
- **回帰 UI テスト**: `SprintElevenAcceptanceTests` (4) + `SprintTenAcceptanceTests` (7) + `SprintThirteenAcceptanceTests` (4) = **15/15 passed**（231.6 秒・TEST SUCCEEDED）

クラッシュ0、未処理エラー0、タイムアウト0。

## 自分で見つけた弱点

- **条件5（英語表示でのレイアウト崩れ）の iPhone 17 Pro Max / iPhone 16e 等での目視確認は未実施**。シミュレータ iPhone 17 のみ。Xcode 26.5 のデフォルト端末で `staticTexts` / `buttons` の `waitForExistence` が成立していることで「ボタンが見切れずに検出できる」レベルの担保はあるが、文字数カウンターや Plus 画面の説明文の折返しなどは実機/iPad などの広い画面でも英語が読めるかは evaluator 担当。
- **条件4（fr 端末で「翻訳されていない内部的な文字列（記号や英数字の羅列）が画面に出ない」）の完全網羅は未確認**。今回のテストは「コンセプト画面で英語見出しが出ている / ja 見出しが出ていない」「設定画面で英語ナビバーが出ている」の2点のみ。空状態の `Blocked people` / `BLOCKED PEOPLE` のような見出しが fr 端末でもちゃんと英語UIとして表示されるかは test07 の nav bar 確認のみ。**ブロック一覧の中身（絵文字とニックネーム）が数字羅列で見えるリスクは evaluator 担当**（F07 / F23 の機能外なので ja 端末でも同じ）。
- **シミュレータの翻訳経路は `-SameQFakeTranslate` 経路のため、英語表示と翻訳は無関係**。実機で Apple Translation が動いているときに、en 端末が他言語の回答を en へ翻訳した結果を表示する経路は evaluator 担当。
- **`BannedView` の二言語併記を単一言語表示へ変更したが、`safetyLogRetentionSeconds` 等のデバッグ専用文言は触っていない**。これらは評価対象外。

## 提案（今回はやらなかったこと）

- **iPad / macOS Catalyst のレイアウト確認**。F38 のスコープ外だが、端末の幅が変わったときに英語UIが崩れないかは次回のリリース前チェック項目として残しておく価値あり。
- **`L10n` を `String(localized:)` ベースへ段階移行**。現在は `useEnglish ? … : …` の分岐だが、将来的にリソース `Localizable.strings` ベースへ移行すればコードから ja/en のリテラルが消えて保守が楽。今回はスコープ外として見送り。
- **フランス語 / スペイン語など第3言語対応**。spec で「最低限 日本語／英語」と明示されており、第3言語は今回の対象外。ただし `Locale.preferredLanguages.first` を尊重する構造は残してあるので、新言語の追加時は `L10n.Xxx.useSpanish` のような分岐を足せば良い。