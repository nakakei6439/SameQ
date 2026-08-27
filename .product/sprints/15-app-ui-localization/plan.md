# スプリント 15: アプリ自身の文言を端末の言語で表示する

## 受け入れ条件（spec.md から転記）
- [ ] 端末言語を英語にして初回起動すると、コンセプト説明・利用規約同意・絵文字選択・ニックネーム入力・通知許可の各画面の文言とボタンがすべて英語で表示され、日本語が1文字も残らない
- [ ] 端末言語を英語にしたまま、今日のお題／世界タイムライン／お題待ち／利用停止／設定／Plus の各画面を一巡しても、アプリが出す日本語の文言が現れない（確認ダイアログのボタン、投稿の拒否メッセージ、連打制限のメッセージ、空状態の説明文を含む）
- [ ] 端末言語を日本語に戻すと、同じ画面がすべて日本語で表示される
- [ ] 日本語でも英語でもない端末言語（例：フランス語）では英語で表示され、翻訳されていない内部的な文字列（記号や英数字の羅列）が画面に出ることがない
- [ ] 英語表示でも、文字の見切れ・ボタンからのはみ出し・要素の重なりが無い（特にボタンのラベル、文字数カウンター、設定画面の項目名）
- [ ] ニックネーム・回答本文・お題本文の表示はこれまでどおりで、スプリント06（本文とお題の翻訳）とスプリント07（ニックネームの音写）の受け入れ条件が変わらない
- [ ] 端末の言語設定を変えて起動し直したとき、一部の画面だけ前の言語のまま残ることがない

## 実装方針

### アプローチ: `L10n` ヘルパで言語ごとに文字列を切替
- `SameQ/L10n.swift` を新規作成
- `Locale.preferredLanguages.first` を起動時に1回だけ読む（既存の `Translator` と同じ方式）
- 言語判定: `ja` 始まり → 日本語、それ以外 → 英語
- すべての UI 文言を `L10n.Xxx.yyy` 形式で参照
- 既存の `errorDescription`（`BackendError` / `PlusPurchaseError` / `SupabaseError`）は現状維持しつつ、`AppSession` 経由で alert に出す直前に L10n で再翻訳

### 変更対象ファイル（ビュー）
1. `SameQ/Feature/Onboarding/OnboardingView.swift` — コンセプト/規約/絵文字/ニックネーム/通知の各ステップ
2. `SameQ/Feature/Today/TodayPromptView.swift` — お題見出し、composer、ロック表示、Plus ヒント、受信いいね
3. `SameQ/Feature/Timeline/TimelineView.swift` — topBar、お題帯、空状態、ラーメン、いいねボタン
4. `SameQ/Feature/Timeline/AnswerCardView.swift` — …続き/閉じる
5. `SameQ/Feature/Timeline/SafetySheetView.swift` — 通報・ブロックの全ステージ
6. `SameQ/Feature/Waiting/WaitingPromptView.swift` — お題待ち
7. `SameQ/Feature/Settings/SettingsView.swift` — 全セクション（プロフィール/規約/通知/Plus/ブロック/削除）
8. `SameQ/Feature/Settings/ProfileEditView.swift` — プロフィール編集シート
9. `SameQ/Feature/Settings/LegalView.swift` — 規約シート
10. `SameQ/Feature/Banned/BannedView.swift` — BAN画面（既存の二言語併記を L10n 化）
11. `SameQ/Feature/Plus/PlusView.swift` — Hero/特典/料金/復元/注意書き
12. `SameQ/Feature/Plus/PlusDecorationPicker.swift` — 装飾ピッカー
13. `SameQ/App/RootView.swift` — 失敗画面の「読み込めませんでした」「もう一度試す」
14. `SameQ/Model/Safety.swift` — `ReportReason.label` を L10n 化

### 変更対象ファイル（エラー）
- `SameQ/Session/AppSession.swift` — `alertMessage = error.errorDescription` を `alertMessage = L10n.errorMessage(for: error)` に置換
- `SameQ/Backend/PlusService.swift` — `errorDescription` を L10n 化
- `SameQ/Backend/Backend.swift` — `BackendError.errorDescription` を L10n 化（言語非依存のケースを保持）
- `SameQ/Backend/SupabaseError.swift` — `errorDescription` を L10n 化

### 影響範囲（壊しうる箇所）
- 既存の `errorDescription` テスト（`BackendErrorTests` 等）をパスし続ける必要がある → L10n の出力でもテスト期待値を更新
- UI テストの accessibilityIdentifier 文字列（ボタン名）は変更しない
- `BannedView` の二言語併記表示を「端末言語で1言語のみ」表示に変更

## 影響範囲外（明示的に対象外）
- 利用規約本文・プライバシーポリシー本文（spec で対象外）
- お題本文・回答本文・ニックネーム表示（既存の翻訳ロジックを維持）
- アプリ内言語切替（端末の言語設定を変える方式のまま）
