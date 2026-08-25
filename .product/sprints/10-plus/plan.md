# スプリント 10: Plus（RevenueCat による課金）

## 受け入れ条件（spec.md 263〜269行）
- [ ] 無料ユーザーは140文字までしか入力できず、文字数カウンターが残り文字数を示し、超過しようとすると入力が止まる
- [ ] Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示される
- [ ] 購入完了後、140文字を超える入力ができるようになり、Plus 限定の絵文字と装飾が選択できる
- [ ] 長文の回答はタイムラインで一部だけ表示され、「続きを読む」で全文が開く
- [ ] 無料ユーザーでも他人の長文回答を「続きを読む」で全文読める（閲覧に課金制限がかからない）
- [ ] アプリを削除して入れ直しても「購入を復元」で Plus 状態が戻る
- [ ] Plus 未購入でも、お題への回答・世界タイムライン閲覧・スワイプ・いいねが一切制限されない

## 実装方針

**Plus課金レイヤ**: 仕様の「RevenueCat」指定に対し、本スプリントでは **StoreKit 2 ベース** の `PlusService` プロトコル+実装を作る。プロジェクトの「外部パッケージ依存ゼロ」方針を尊重し、StoreKit 2 を直接使う。RevenueCat SDK は将来 Supabase 接続時に差し替える想定（`PlusService` プロトコル境界で隔離）。

**追加ファイル**:
- `SameQ/Backend/PlusService.swift` — プロトコル定義（Entitlement / Product / 復元 / 購入）
- `SameQ/Backend/StoreKitPlusService.swift` — StoreKit 2 実装
- `SameQ/Backend/FakePlusService.swift` — Debug/テスト用実装
- `SameQ/Backend/PostDecoration.swift` — 装飾モデル（F30: 絵文字・文字装飾・吹き出し装飾）
- `SameQ/Feature/Plus/PlusView.swift` — 購入画面
- `SameQ/Feature/Plus/PlusPromptView.swift` — 投稿画面の装飾選択UI
- `SameQUITests/SprintTenAcceptanceTests.swift` — 受け入れ条件検証
- `SameQTests/PlusServiceTests.swift` — 単体テスト

**変更ファイル**:
- `Model/Post.swift` — `decorations: [PostDecoration]` と `previewBody` (先頭N文字) を追加
- `Backend/Backend.swift` — `submitPost` の文字数制限をPlus対応、`PlusService` 連携
- `Backend/LocalBackend.swift` — `bodyCharacterLimit(plus:)` 計算、永続化に `entitlements: [String: PlusEntitlement]` 追加（schemaVersion 6）
- `Backend/LocalStore.swift` — `PlusEntitlement` の永続化、後方互換
- `Session/AppSession.swift` — `plusService`, `isPlus` 公開、`openPlusView()`, 装飾選択後の本文構築
- `App/RootView.swift` — `.sheet(isPlusPresented:)` を追加
- `Feature/Today/TodayPromptView.swift` — Plus/無料モードでカウンタ上限切替、装飾選択UI、送信ボタン有効条件
- `Feature/Timeline/AnswerCardView.swift` — `decorations` を反映、長文は `...続き` で省略し「続きを読む」を開く
- `Feature/Settings/SettingsView.swift` — 「Plus」セクション（購入復元ボタン）
- `Backend/LaunchOptions.swift` — `-SameQFakePlus` 引数追加（デバッグ・UIテスト用）

## 影響範囲

- 文字数上限は `LocalBackend.bodyCharacterLimit` から `LocalBackend.bodyCharacterLimit(isPlus:)` へ変更。既存のユニットテストは呼び出しを変えるか、デフォルト引数で後方互換を保つ。
- `PersistedState` に `entitlements` を追加（schemaVersion 5 → 6）。`decodeIfPresent` で既存ユーザーの値を読み飛ばさず後方互換。
- `isPlus` の判定は `PlusService` の `currentEntitlements` を毎回見ず、`AppSession` でキャッシュ（`onChange` で再評価）。
- 装飾データはJSON配列として本文に直列化／逆直列化する（`Post.decorations`）— `body` には装飾を含めない。`bodyLanguage`/`body` には本文のみ。装飾は表示専用。

## 検証方針

- 単体テスト: `PlusService` の Fake 実装を通じた購入→復元→失効の遷移、長文投稿の永続化
- UIテスト: `SprintTenAcceptanceTests`（受け入れ条件7項目のうち主要4-5項目を実操作で）
- 回帰: スプリント01〜09の既存テストがすべて緑であること
