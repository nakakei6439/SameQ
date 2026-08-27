# スプリント 14 attempt 1: 着手前ブロッカーで blocked

## 結論

3 つのブロッカーのいずれも generator 単独で解消できないため、
**着手停止 (blocked)** 状態でユーザー判断を仰ぎます。
コード変更はゼロ（既存の `StoreKitPlusService` 経路をそのまま温存）。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が差し替え前と同一 | 未着手 | RevenueCat SDK 追加を前提とするスプリントのため、SDK 追加判断待ち |
| 2. サンドボックス購入で Plus 状態が有効化 | 未着手 | 同上 |
| 3. 端末削除→復元で Plus 状態が戻る | 未着手 | 同上 |
| 4. **ダッシュボードに取引が現れる** | **generator 環境から検証不能** | ブラウザ自動化なし・トークンなし。サンドボックス購入→ダッシュボード反映は evaluator（人間）必須 |
| 5. 購入キャンセル時の責めないダイアログ | 未着手 | SDK 追加判断待ち |
| 6. オフライン時に Plus 状態が転落しない | 未着手 | SDK 追加判断待ち |
| 7. スプリント10の受け入れ条件7項目維持 | 未着手 | 既存 `StoreKitPlusService` 実装が満たしており、SDK 移行判断待ち |

## ブロッカー詳細

### ブロッカー1: spec.md 内の構造的矛盾

**矛盾箇所**:
- `.product/spec.md` 行 23（前提条件表・ユーザー確定）: 「課金は RevenueCat」
- `.product/spec.md` 行 115（前提 17）: 「課金基盤は前提条件表どおり RevenueCat に戻す」
- `.product/spec.md` 行 352（スプリント14本文）: 「Plus の課金基盤を前提条件どおり RevenueCat に戻す」
- `.product/spec.md` 行 11（対象外）: 「外部パッケージ依存はゼロ（Swift標準 + Apple SDK のみ利用可）」

**分析**: RevenueCat SDK は GitHub 配布の Swift Package で、`https://github.com/RevenueCat/purchases-ios` を SPM 経由で取り込むサードパーティ外部パッケージ。rule 11 の「外部パッケージ依存はゼロ」と直接衝突する。

**過去事例**: スプリント10（行 280〜294）は同じ矛盾に直面し、generator が「外部依存ゼロの方針を維持するため StoreKit 2 を直接叩く実装に置き換えた」（PROGRESS.md 行 321 周辺 / sprint 10 self-review）としてユーザー承認で通過。attempt 1 で passed。

**判断が必要**: rule 11 を本スプリントに限って緩和するか、スプリント14を撤回するか。

### ブロッカー2: RevenueCat API key がプロジェクト内に存在しない

**確認済み事項**:
- `.env.local`（行 1〜24）に Supabase の `SUPABASE_PROJECT_REF` / `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_ANON_KEY_LEGACY` / `SUPABASE_DB_PASSWORD` / `SUPABASE_SECRET_KEY` はあるが RevenueCat の API key（`appl_***` または `rcat_***`）は無い
- `project.yml`（行 1〜85）に `dependencies:` フィールド自体が存在しない（SPM 依存ゼロ）
- `SameQ.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/` は空ディレクトリ
- `Purchases.configure(withAPIKey:)` の API key が無いと `RevenueCatPlusService` の全メソッドが `Error 状態` で失敗する

**必要な情報**:
- RevenueCat アカウントを作成済みか（https://app.revenuecat.com/）
- 作成済みの場合: iOS 用の公開 API key（`appl_***`）
- App Store Connect でアプリが登録済みか（RevenueCat 連携に Product ID の事前登録が必要なため）

### ブロッカー3: 受け入れ条件4（ダッシュボード取引確認）は generator 環境から検証不能

**条件4 の原文**（spec.md 行 361）:
> サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）

**generator 環境で不可能なこと**:
- RevenueCat ダッシュボード（https://app.revenuecat.com/）へのログイン・目視
- サンドボックス App Store アカウントでの実購入操作
- 取引発生後の RevenueCat レポート・チャートセクションでの該当取引確認

**evaluator に委ねられること**:
- 実機 / シミュレータでのサンドボックス購入操作（iPhone 17 / iPhone 17 Pro）
- ダッシュボードへのログインと該当取引の目視確認
- `xcrun simctl purchase` のようなシミュレータ完結の購入検証（App Store Sandbox アカウント必須）

**判断が必要**: evaluator がダッシュボード反映を確認できる手順（ログイン情報または RevenueCat アカウントのテスト用 read-only トークン等）を self-review.md に明記するかどうか。

## 動かし方（evaluator 向け）

### 現状
- コード変更ゼロ。既存の `StoreKitPlusService` 経路（Release）+ `FakePlusService` 経路（Debug / `-SameQFakePlus`）がそのまま動く
- spec.md の更新（2026-08-27）でスプリント14が定義されたが、generator は着手前ブロッカーで停止中

### ブロッカー解消後に evaluator が検証する手順（参考）
1. RevenueCat アカウントが作成され、iOS 用 API key が `.env.local`（または `Info.plist` の `REVENUECAT_API_KEY` フィールド）に設定されていることを確認
2. App Store Connect で `com.nakakei6439.SameQ.plus.monthly` が登録されていることを確認
3. RevenueCat ダッシュボードの Products 設定で同じ Product ID が紐付いていることを確認
4. 実機 / シミュレータでサンドボックス購入を実行
5. RevenueCat ダッシュボード（https://app.revenuecat.com/）の Customers / Transactions セクションで取引が現れることを目視確認
6. アプリ削除→復元で Plus 状態が戻ることを確認
7. 受け入れ条件 5〜7 を既存テスト経路（FakePlusService）で確認

## 自分で見つけた弱点

1. **spec.md の矛盾は planner/ユーザー側の修正が必要**。generator 側で「rule 11 を本スプリントに限り無視する」判断はプロジェクトガバナンス上行うべきではない
2. **`scripts/autoloop.sh` の `LAST_SPRINT="17"`**（行 26）は既に正しい値へ更新済み（state.json history の user_action ノートで確認）。本ブロッカーで autoloop は exit 2 で正常停止する想定
3. **RevenueCat の Entitlement ID / Product ID** が spec.md で `plus` / `Monthly Plus`（行 23）と書かれているが、既存の `StoreKitPlusService.swift` 行 19 の Product ID は `com.nakakei6439.SameQ.plus.monthly`。RevenueCat 側でも同じ文字列を使うか、`Monthly Plus` の命名規則に合わせるかは要ユーザー確認

## 提案（今回はやらなかったこと）

### A. 推奨案: ユーザー側で API key 提供 + rule 11 を明示緩和
- `.env.local` に `REVENUECAT_API_KEY=appl_*****` を追記
- spec.md 行 11 に「（ただし F37 RevenueCat SDK のみ例外として認める）」を追記
- 次 attempt で `project.yml` に SPM 依存追加 → `RevenueCatPlusService.swift` 新規 → `AppSession.swift` のデフォルト切替
- evaluator がサンドボックス購入→ダッシュボード目視で条件4 を検証

### B. 最小案: spec.md をスプリント10の状態へ戻す
- spec.md からスプリント14〜17 を削除
- `scripts/autoloop.sh` の `LAST_SPRINT` を `"11"` へ戻す（または現状の `"17"` を維持して autoloop を終わらせる）
- F37 を「将来検討」バックログへ降ろす

### C. 妥協案: 「RevenueCat 経由」を「StoreKit 2 を RevenueCat SDK 風に抽象化」と再解釈
- 既存の `StoreKitPlusService` をそのまま温存
- `PlusService` プロトコルのメソッド名・戻り値を RevenueCat Purchases API（`getProducts` / `getCustomerInfo` / `purchase(product:)` / `restorePurchases`）と互換の形に揃える
- 将来 SDK 移行時に呼び出し側を無変更で `RevenueCatPlusService` へ差し替え可能にする
- **ただし条件4 は満たせない**（「ダッシュボードに取引が現れる」のは RevenueCat SDK があってこそ）ため evaluator は不合格判定する可能性が高い

## 申し送り（次セッション / ユーザー宛）

- 状態: `.product/state.json` を `current_sprint="14"`, `status="blocked"`, `attempt=1` に更新予定
- コード変更: ゼロ
- ブロッカー: 上記 3 点
- 推奨アクション: **A**（rule 11 緩和 + API key 提供）
- 比較表:

| 案 | rule 11 整合 | 条件4 達成 | generator 単独完走 | ユーザー作業 |
|---|---|---|---|---|
| A | ✕（緩和）| ◯（dashboard 検証） | ✕（要 API key） | API key 提供 + rule 11 緩和宣言 |
| B | ◯ | ✕（sprint 撤回） | ◯（そのまま終了）| spec.md 修正 |
| C | ◯ | ✕（dashboard 不可） | ◯（抽象化のみ）| なし |

- autoloop.sh は blocked ステータスを見て exit 2 で停止する想定。次回 autoloop 起動はユーザー回答後
