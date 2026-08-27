# スプリント 14 attempt 2: RevenueCat への差し替え実装

## 結論

**修正完了（`needs_fix` の修正）**。ユーザー回答（選択肢 A）で解消された
3 つのブロッカー（仕様矛盾・API key 不在・ダッシュボード目視不能）のうち、
generator 側で完結する 2 つ（仕様矛盾への library 例外明記＋ API key 取り込み）を
反映したうえで、Plus 課金基盤を RevenueCat SDK 経由へ差し替えた。
受け入れ条件4（ダッシュボード目視確認）は evaluator 担当で、明示した手順を
「動かし方」に記載。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が同一 | 達成 | `PlusProduct(displayName:, displayPrice:, periodDescription:)` の値を `StoreKitPlusService` / `FakePlusService` と完全一致で構築（`RevenueCatPlusService.swift` の `availableProducts()`）。`displayPrice` のみ App Store のローカライズ文字列（`localizedPriceString`）になり、StoreKit と完全に同じ "¥480" 等を返す。PlusView 側のレイアウト・ボタン文言は無変更 |
| 2. サンドボックス購入で Plus 状態が有効化 | 達成（コード） | `purchase(_:)` で `Purchases.purchase(product:)` を呼び、戻り値の `PurchaseResultData.userCancelled == false` を確認したうえで `CustomerInfo.entitlements["plus"]` を `PlusEntitlement` に詰めて返す。`isPlus` / `plusEntitlement` が更新され、140文字超・限定装飾が使えるようになる経路は既存 `AppSession` のロジックで担保 |
| 3. 端末削除→復元で Plus 状態が戻る | 達成（コード） | `restore()` で `Purchases.restorePurchases()` を呼び、エンタイトルメントを再取得。サンドボックス購入は RevenueCat サーバー側に記録されているため、アプリを削除して再インストールしても `currentEntitlement()` / `restore()` で復活する。設定画面の復元からも同じ経路（`restorePlus()` → `plusService.restore()`） |
| 4. **ダッシュボードに取引が現れる** | **evaluator 担当** | generator 環境から https://app.revenuecat.com/ へのログイン不可・トークン無し。コードでは条件1〜3が満たれば RevenueCat サーバーへの POST が走るため、evaluator がサンドボックス購入→ダッシュボード目視で確認する手順を「動かし方」に明示 |
| 5. 購入キャンセル時に責めない | 達成（コード） | `purchase(_:)` 内で `data.userCancelled == true` または `ErrorCode.purchaseCancelledError` を `PlusPurchaseError.userCancelled` にマップし、`AppSession.purchasePlus(_:)` 側で「ユーザーキャンセルは alertMessage を立てない」既存ガード（AppSession.swift 317行）に乗せる |
| 6. オフラインで Plus 状態が転落しない | 達成（コード） | `currentEntitlement()` は `Purchases.customerInfo()` を呼び、SDK 内部のキャッシュ（直近のエンタイトルメントを保存）を返す。通信不能でも SDK キャッシュから `PlusEntitlement` を組み立てるため、無料状態へ転落しない。RevenueCat 経由での復元経路は通信失敗を `.network` にマップしてエラー表示するが、`currentEntitlement()` の挙動は変えない（`availableProducts()` の空配列は UI 側で「読み込み中」相当の見た目になる） |
| 7. スプリント10の受け入れ条件7項目維持 | 達成 | スプリント10で合格した FakePlusService 経路（SprintTenAcceptanceTests）は `-SameQFakePlus` で動くため RevenueCat 経路と独立。SprintTenAcceptanceTests 7/7、SprintThirteenAcceptanceTests 4/4、回帰を実機シミュレータで実行し問題なし |

## 動かし方（evaluator 向け）

### 事前準備（既に対応済み）
- `.env.local` に `REVENUECAT_API_KEY=appl_...` がセットされている（spec.md 行23 / 行115 の RevenueCat プロジェクト "SameQ" で発行された公開 SDK キー）
- `scripts/generate-secrets.sh` が `SameQ/Secrets.swift` をビルド時に生成する（`.gitignore` 対象）
- `project.yml` の `preBuildScripts.GenerateSecrets` が `Compile Sources` の前にシェルを走らせる（outputFiles 指定で生成ファイルが依存解析にも反映）
- API キーが空のときは SDK が silent fail するだけなので、UI は「Plus の商品情報を読み込めませんでした」相当の文言を出す（受け入れ条件5の精神）

### 受け入れ条件4（ダッシュボード反映）の確認手順
1. **実機 / シミュレータでサンドボックス購入**:
   - 実機: App Store Connect で Sandbox テスターを作成し、その Apple ID でログインした状態で `PlusView` → 購入ボタンを押す
   - シミュレータ: `xcrun simctl purchase booted com.nakakei6439.SameQ 'com.nakakei6439.SameQ.plus.monthly'` で擬似的に購入を発火できる（ただし擬似購入は RevenueCat ダッシュボードには乗らないため、**条件4の検証は実機必須**）
2. **RevenueCat ダッシュボードで確認**:
   - https://app.revenuecat.com/projects/e444c0e4/overview にログイン
   - `Customers` タブでサンドボックス購入を行ったユーザーの `app_user_id` を検索
   - `Entitlements` が `plus` で active になっていること、購入時刻が記録されていることを確認
   - `Transactions` タブで購入履歴が残っていることを確認
3. **復元経路の検証**:
   - アプリを完全削除（`xcrun simctl uninstall booted com.nakakei6439.SameQ`、または実機の長押し→削除）
   - 再インストール → オンボーディング完了 → 設定画面 → 「購入を復元」を押す
   - `Plus` ラベル / 長文入力・装飾が再び使えるようになることを確認

### Debug 経路（シミュレータで Plus 画面を触りたいだけの場合）
- `-SameQFakePlus` を付ければ `FakePlusService` が動く（既存挙動と完全一致）。
- `-SameQUseStoreKitPlus` を付ければ旧 `StoreKitPlusService` 経路に戻る（escape hatch）。
- 上記どちらも付けない既定が `RevenueCatPlusService`（スプリント14のリリース形）。

## 変更ファイル

### 新規
- `SameQ/Backend/RevenueCatPlusService.swift` — `PlusService` プロトコル準拠の RevenueCat 実装
- `SameQTests/RevenueCatPlusServiceTests.swift` — プロトコル契約の担保（5本）
- `scripts/generate-secrets.sh` — `.env.local` → `SameQ/Secrets.swift` 生成
- `SameQ/Secrets.swift` — 自動生成（gitignore）

### 変更
- `project.yml` — `packages.RevenueCat` SPM 依存追加、`dependencies` 紐付け、`preBuildScripts.GenerateSecrets` 追加（`ENABLE_USER_SCRIPT_SANDBOXING: NO` で .env.local アクセスを許可）
- `SameQ.xcodeproj/project.pbxproj` — `xcodegen generate` で再生成（RevenueCat / Secrets.swift / 新テストが反映済み）
- `SameQ/Backend/LaunchOptions.swift` — `useStoreKitPlus: Bool = false` 追加（`-SameQUseStoreKitPlus` の escape hatch）
- `SameQ/Session/AppSession.swift` — 既定を `RevenueCatPlusService()` に切替（`LaunchOptions.current.useStoreKitPlus` で `StoreKitPlusService` へ戻せる）

### 触らなかったファイル
- `SameQ/Backend/PlusService.swift` — プロトコル定義はそのまま温存（`PlusService` / `PlusProduct` / `PlusEntitlement` / `PlusPurchaseError`）
- `SameQ/Backend/StoreKitPlusService.swift` — escape hatch として温存（コメントだけ更新予定）
- `SameQ/Backend/FakePlusService.swift` — Debug 経路として温存
- `SameQ/Feature/Plus/PlusView.swift` / `SameQ/Feature/Plus/PlusDecorationPicker.swift` — UI / 遷移の一切変更なし（受け入れ条件1「同じ見た目・同じ導線」）
- `SameQ/Backend/Backend.swift` / `SameQ/Backend/LocalBackend.swift` / `SameQ/Backend/SupabaseBackend.swift` — Plus 関連 API は無変更

## テスト実行結果（シミュレータ単独実行 / 他プロセス非併走）

### 新規ユニットテスト（5本）
```
Test Suite 'RevenueCatPlusServiceTests' passed
  test01_RevenueCatPlusServiceInitializesWithCurrentAPIKey   (0.001s) ✓
  test02_RevenueCatPlusServiceInitializesGracefullyWithEmptyAPIKey (0.550s) ✓
  test03_RestoreThrowsTypedErrorWhenNoEntitlementExists      (0.539s) ✓
  test04_PlusEntitlementActiveAndExpirationSemantics          (0.000s) ✓
  test05_AppSessionDefaultPlusServiceIsRevenueCat             (0.005s) ✓
Executed 5 tests, with 0 failures (0 unexpected) in 1.094 (1.096) seconds
```

### 全ユニットテスト（175本 = 既存170本 + 新規5本）
```
Executed 175 tests, with 0 failures (0 unexpected) in 5.943 (5.988) seconds
** TEST SUCCEEDED **
```

### UI 回帰（直近2〜3スプリント分から最大3クラス = Sprint10 + Sprint13）
- `SprintTenAcceptanceTests` 7/7 (127.8s) — **Plus 画面の主要動線（FakePlusService 経路）**。RevenueCat 経路に切り替えても FakePlus 経由の UI テストは変わらずに動く
- `SprintThirteenAcceptanceTests` 4/4 (13.8s) — サーバー側 BAN / 連打制限の経路
- 合計 11/11 passed

### ビルド
- Debug: `BUILD SUCCEEDED`
- Release: `BUILD SUCCEEDED`（warning のみ・既存コード由来・今回追加分に由来する warning 無し）
- クラッシュ 0・未処理エラー 0・タイムアウト 0

## 実装メモ（詳細判断）

### API キーの埋め込み方
- **iOS 公開キー（`appl_` 接頭辞）は iOS バイナリに埋め込み前提**（RevenueCat の仕様）。
- `.env.local`（`.gitignore` 対象）を `scripts/generate-secrets.sh` が読み、`SameQ/Secrets.swift` を生成。
- `Secrets.swift` 自体は `.gitignore` の `Secrets.swift` 行で除外済み。
- ビルド時に Xcode が `preBuildScripts.GenerateSecrets` でシェルを起動（`ENABLE_USER_SCRIPT_SANDBOXING: NO` を project 全体で設定しないと sandbox が `.env.local` 読み込みを拒否する。これは .gitignore との二重防壁で担保）。

### 既定の切り替え
- `AppSession.init(plusService:)` が `nil` で呼ばれた場合、`LaunchOptions.current.fakePlus` / `LaunchOptions.current.useStoreKitPlus` の順に分岐：
  - `fakePlus == true` → `FakePlusService`（UI テスト用・既存挙動）
  - `useStoreKitPlus == true` → `StoreKitPlusService`（escape hatch）
  - **どちらも false → `RevenueCatPlusService`（スプリント14の既定）**

### `PlusEntitlement` への詰め替え
- `CustomerInfo.entitlements["plus"]` を取得 → `isActive` チェック → `expirationDate` を `expiresAt` に → `latestPurchaseDate ?? originalPurchaseDate ?? Date()` を `purchasedAt` に。
- グレース期間に入った `EntitlementInfo.isActive == false` は弾く（`expirationDate` だけでの判定だと猶予期間中の表示が残る副作用があるため）。
- `productID` は `info.productIdentifier`（ダッシュボードで紐付けた Product ID）をそのまま採用。

### エラーラッピング
- `RevenueCat.ErrorCode` の各ケースを `PlusPurchaseError` の対応する case にマップ。
- `.purchaseCancelledError` → `.userCancelled`（ダイアログ抑制・受け入れ条件5）。
- `.missingReceiptFileError` / `.receiptInUseByOtherSubscriberError`（restore 時）→ `nil` を返す（復元対象が無い状態は失敗ではない）。
- `NSURLErrorDomain` → `.network`（既存 `StoreKitPlusService` と同じ）。
- その他は `.other(localizedDescription)` で握り、UI に「Plus の商品情報を読み込めませんでした」相当の文言を返す。

### 触らなかった判断
- `Backend` プロトコル・`LocalBackend` / `SupabaseBackend` の `bodyCharacterLimit(isPlus:)` / 装飾の受理判定は **変更なし**。これらは `AppSession.isPlus` だけを見るので、`isPlus` の判定元が StoreKit → RevenueCat に変わっても UI / データ層には波及しない。
- `PlusView` の見た目・文言・ボタンの並びは **完全に温存**（受け入れ条件1「同じ見た目・同じ導線」を担保）。
- `FakePlusService` の永続化（attempt 2 / eval-1.md [1] の修正）は **温存**。UI テストや Debug 経路で引き続き使用される。

## 自分で見つけた弱点

1. **購入の二重発火防止は Purchases SDK の内部ロック任せ**: `Purchases.purchase(product:)` は同一 Product で連続呼び出しすると `operationAlreadyInProgressForProductError` を返す経路がある。UI 側で「購入ボタンを連打したら `error == .operationAlreadyInProgressForProductError` が出ても責めないダイアログを出す」コードは未実装（既存 `StoreKitPlusService` も同等の問題を抱えていた）。`PlusView` の `.disabled(isPurchasing)` で防ぐ既存ガードで十分か、evaluator に確認いただきたい
2. **`useStoreKitPlus` の escape hatch はドキュメントコメント程度しかガードが無い**: Release ビルドでは `LaunchOptions.parse` が `if #if DEBUG` で囲われているので `useStoreKitPlus` は常に false のはず（PROGRESS.md の Sprint10 attempt 1 経路と同じガード）。ただし、明示的に Release でも false 固定であることを確認する自動テストは未追加
3. **ダッシュボード反映の目視確認は evaluator 必須**: generator 環境に RevenueCat ダッシュボードのアクセス手段が無い。サンドボックス購入後に `https://app.revenuecat.com/projects/e444c0e4/overview` の `Customers` / `Transactions` を確認する手順を上に明記したが、これは人間にしかできない
4. **シミュレータでのサンドボックス購入は擬似的にしか動かない**: `xcrun simctl purchase` は Apple のサンドボックスで動くが、RevenueCat サーバーへの POST がシミュレータ固有の経路を通るため、本番と完全一致する保証は無い。受け入れ条件4の厳密な検証は実機 + Sandbox Apple ID で行うのが望ましい
5. **`purchasesAsync` などの内部メソッドは internal**: 最初の実装で `Purchases.shared.productsAsync(ids)` を呼んだが内部スコープでコンパイルエラー。公開 API `products(_:)` / `purchase(product:)` / `restorePurchases()` / `customerInfo()` を使う形に書き換えた（既にコミット状態）

## 提案（今回はやらなかったこと）

### A. evaluator 側の確認を楽にする小さな計測フック
- `PlusView.purchaseButton` の `isPurchasing` 状態を Release / Debug 共通で維持し、連打しても二重発火しないことを Acceptance テストで担保する 1 本を追加。
- ただし本スプリントは「既存の購入体験を変えずに土台を差し替える」が目的なので、過剰な改変は避ける方が安全。

### B. 購入復元が nil の時の文言を `PlusView` 側で明示
- 現状は「Plus の購入がありません」相当のメッセージが無いため、復元しても何も起こらないように見える。
- `PlusView` に "復元できる購入が見つかりませんでした" のトースト / ヒントを追加するのは次スプリント（スコープ外）。

### C. App Store のサブスクリプションステータスを `AppStore.sync()` で定期ポーリング
- 仕様外（subscription の auto-renew 状態が変わるたびにアプリ内へ反映する要件は spec には無い）ため未実装。
- RevenueCat の webhook 連携はサーバ側で吸収する想定。

### D. Product ID が `com.nakakei6439.SameQ.plus.monthly` 固定（spec.md 23行は "Monthly Plus"）
- spec.md 23行では "Entitlement は `plus`、Product ID は `Monthly Plus`" という命名規則が書かれているが、既存の `StoreKitPlusService` が `com.nakakei6439.SameQ.plus.monthly` を使っており、App Store Connect / RevenueCat 側の Product ID も同じ値を登録してある。命名規則と実装の不一致は将来リファクタ候補（今回は受け入れ条件7「スプリント10受け入れ条件7項目維持」を優先してそのまま温存）。

## 申し送り

- **コード変更**: 完了（前述の差分一覧）
- **テスト**: 175/175 unit + 11/11 UI 回帰、すべて TEST SUCCEEDED
- **ビルド**: Debug / Release とも BUILD SUCCEEDED
- **evaluator の手順**: 「動かし方」節の手順でサンドボックス購入→ダッシュボード目視（条件4）を実施
- **autoloop**: status を `awaiting_eval` に更新すれば自動継続可能（`needs_fix` の修正なので attempt 2 として記録される）
