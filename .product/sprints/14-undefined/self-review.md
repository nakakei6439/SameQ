# スプリント 14 attempt 6: .storekit 構成追加でシミュレータ検証経路を確保

## 結論

attempt 5（`user_action`）でユーザー側ブロッカーが解消された:
- App Store Connect の Monthly Plus サブスクリプション（`com.nakakei6439.SameQ.plus.monthly`）
  の配信可否が 0 か国 → 175 か国に拡大
- RevenueCat ダッシュボードの SameQ (App Store) に同 Product ID を新規作成、
  entitlement `plus` にアタッチ、default Offering の Monthly パッケージに紐付け
- RevenueCat の secret API key（Customers/Subscriptions/Purchases のみ Read only）が
  `.env.local` の `REVENUECAT_SECRET_API_KEY` に保存され、evaluator から REST API v2
  で取引照会が可能になった

これにより、**実機 + Sandbox Apple ID** があれば条件 2・3・4 はすべて観測可能。
evaluator 環境には引き続き実機 / Sandbox Apple ID が無いため、シミュレータで
条件 2・3 を検証できる経路を generator 側で追加する。

self-review attempt 5 の提案 B「`.storekit` 構成を追加してシミュレータでも
条件 2・3（購入・復元）を検証できるようにする」を実装:
- 新規ファイル `SameQ/Configuration.storekit`（月額の `RecurringSubscription`）
- `project.yml` で StoreKit Testing を有効化し、Configuration.storekit をスキームに紐付け

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が同一 | 達成 | `PlusView` / `PlusDecorationPicker` は無変更。SprintTenAcceptanceTests 7/7 緑 |
| 2. サンドボックス購入で Plus 化 | 達成経路追加 | `.storekit` 構成でシミュレータ + `-SameQUseStoreKitPlus` 経路が StoreKit Testing の購入を実行可能。実機 Sandbox 購入も App Store Connect 175 か国展開済みで実行可能（evaluator 環境外） |
| 3. 削除→復元で Plus 状態が戻る | 達成経路追加 | 同上。`.storekit` 構成により `StoreKitPlusService.restore()` がシミュレータで動作可能 |
| 4. ダッシュボードに取引が現れる | ユーザー側解消済み | App Store Connect の 175 か国展開・RevenueCat ダッシュボードの Product 紐付け・secret key 提供済み。最終目視は人間 evaluator（実機 Sandbox 購入）が必要。evaluator は REST API v2 で部分検証可能 |
| 5. 購入キャンセル時に責めない | 達成 | attempt 3 の test06 で担保済み、テスト再実行でも緑 |
| 6. 通信できない状態で起動しても Plus が転落しない | 達成 | attempt 4 の `AppSession.refreshPlusEntitlement()` nil 保護 + test11〜14 で担保済み、テスト再実行でも緑 |
| 7. スプリント10の受け入れ条件7項目維持 | 達成 | SprintTenAcceptanceTests 7/7 緑（条件7 そのものを直接担保） |

## 変更内容

### 新規ファイル
- **`SameQ/Configuration.storekit`**: StoreKit Testing 用の構成ファイル
  - subscription group `SameQ Plus` 内に
    `com.nakakei6439.SameQ.plus.monthly`（`RecurringSubscription`, `P1M`, `displayPrice "480"`）を 1 件定義
  - locale `ja_JP` / storefront `JPN`（日本円表示のため）
  - Xcode スキームに `storeKitConfiguration` として登録すると、シミュレータではこの
    構成が StoreKit 2 に注入され、`Product.products(for:)` / `purchase()` が
    ローカルで完結する（App Store / RevenueCat サーバへの通信なし）

### 変更ファイル
- **`project.yml`**: 2 箇所のみ編集
  - `targets.SameQ.settings.base`: `ENABLE_STOREKIT_TESTING: YES` を追加
  - `schemes.SameQ.run` / `schemes.SameQ.test`: `storeKitConfiguration: SameQ/Configuration.storekit` を追加

### 既存コードへの影響
- なし。`RevenueCatPlusService` / `StoreKitPlusService` / `FakePlusService` の API は無変更
- 既定経路（`RevenueCatPlusService`）の挙動も無変更
  - ただし App Store Connect の 175 か国展開・RevenueCat ダッシュボードの Product
    紐付けが完了したため、起動時の `ERROR: 🍎‼️ Error fetching offerings` ログが
    出なくなる見込み（evaluator が手動起動で確認可能）
- `PlusView` / `PlusDecorationPicker` も無変更（条件1維持）

## 動かし方（evaluator 向け）

### A. 既定（RevenueCat）経路の起動確認
```bash
xcrun simctl install <SIM_ID> .../SameQ.app
xcrun simctl launch <SIM_ID> com.nakakei6439.SameQ
# → 起動時の `ERROR: 🍎‼️ Error fetching offerings` が出ないこと
# → 「Plus」画面で月額価格（¥480 等、App Store 設定額）が表示されること（条件1）
```

### B. StoreKit Testing 経路での条件 2・3 検証
```bash
xcrun simctl launch <SIM_ID> com.nakakei6439.SameQ -SameQUseStoreKitPlus
# → 既定の RevenueCat 経路ではなく StoreKitPlusService が動く
# → StoreKit Testing のローカル商品 `com.nakakei6439.SameQ.plus.monthly` が引かれる
# → Plus 画面で「¥480」が表示される（条件1）
# → 購入ボタン押下 → StoreKit Testing のシートで購入確定 → Plus 化（条件2）
# → アプリ削除 → 再インストール → 復元ボタン押下 → Plus 状態に戻る（条件3）
```

### C. 条件 4 の REST API 部分検証
```bash
# .env.local から secret API key を読む（evaluator は同じマシンで実行可）
source .env.local  # REVENUECAT_SECRET_API_KEY=sk_... が export される
curl -H "Authorization: Bearer $REVENUECAT_SECRET_API_KEY" \
  https://api.revenuecat.com/v2/projects/<project_id>/customers
# → 実機で Sandbox 購入された app_user_id の取引が REST API 経由で照会可能
# → ダッシュボード目視（Customers / Transactions タブ）は引き続き人間 evaluator 必須
```

## 検証（自動実行結果）

### ユニットテスト
```
xcodebuild test -project SameQ.xcodeproj -scheme SameQ -only-testing:SameQTests \
  -destination 'platform=iOS Simulator,name=iPhone 17'
→ Executed 212 tests, with 0 failures (0 unexpected) in 7.262 seconds
→ ** TEST SUCCEEDED **
```

### UI 回帰（SprintTen + SprintEleven + SprintThirteen）
```
xcodebuild test ... -only-testing:SameQUITests/SprintTenAcceptanceTests \
  -only-testing:SameQUITests/SprintElevenAcceptanceTests \
  -only-testing:SameQUITests/SprintThirteenAcceptanceTests
→ Executed 15 tests, with 0 failures (0 unexpected) in 229.926 seconds
→ ** TEST SUCCEEDED **
  - SprintTenAcceptanceTests 7/7（条件7・スプリント10の受け入れ条件7項目維持）
  - SprintElevenAcceptanceTests 4/4（回帰）
  - SprintThirteenAcceptanceTests 4/4（回帰）
```

### ビルド
- Debug `BUILD SUCCEEDED`
- Release `BUILD SUCCEEDED`
- `Configuration.storekit` がアプリの Bundle Resources に含まれていることを
  `plutil -p` で確認:
  ```
  /Users/.../SameQ.app/Configuration.storekit
  → identifier "SAMEQ14PLUS"
  → subscriptionGroups[0].subscriptions[0]:
      productID "com.nakakei6439.SameQ.plus.monthly"
      displayPrice "480"
      recurringSubscriptionPeriod "P1M"
      type "RecurringSubscription"
  ```

### シミュレータ起動確認
- `xcrun simctl launch` で起動成功（クラッシュ 0）
- 起動ログに `StoreKit) [com.apple.storekit:Default] Received product response` /
  `Parsing 1 products in response` が出ており、`.storekit` の商品 1 件が
  StoreKit に読まれていることを確認

### 既知の警告（条件判定への影響なし）
- 起動時の Network 関連 `nw_connection_copy_connected_local_endpoint_block_invoke`
  ERROR ログは SupabaseBackend の接続試行由来で、本スプリント変更とは無関係

## 自分で見つけた弱点

1. **条件 2・3 のシミュレータ検証は StoreKitPlusService 経路のみ**:
   `RevenueCatPlusService` 経路はシミュレータの StoreKit Testing と完全互換ではない
   （RevenueCat SDK がローカルレシートを本番 backend と照合しようとする）。
   シミュレータで条件 2・3 を回すには `-SameQUseStoreKitPlus` を付ける必要がある。
   evaluator はこの経路で Plus 購入・復元を実行可能。

2. **条件 4 の最終目視は引き続き人間 evaluator 必須**:
   spec.md 行361「ダッシュボードに実績が残ることが今回の差し替えの目的そのもの」が
   残っており、REST API 経由の検証は「取引が存在すること」までは保証するが
   「ダッシュボードの目視」とは別。attempt 5 の user_action により環境は整ったため、
   実機 + Sandbox Apple ID さえ揃えば完了できる。

3. **Configuration.storekit の商品価格は `displayPrice: "480"` でハードコード**:
   App Store Connect 側の実際の表示価格は Release ビルドが本番 App Store から
   取得するため影響なし。シミュレータ/StoreKitPlusService 経路では固定値で表示される
   （条件1「価格は App Store 側で設定した金額と一致する」の精神は、実機経路で担保される）。

4. **Release ビルドでは `Configuration.storekit` は無視される**:
   StoreKit Testing は Debug / Simulator 限定の機能。実機 Release では App Store Connect
   の本物の `com.nakakei6439.SameQ.plus.monthly` が解決される。
   スキームで `storeKitConfiguration` を指定していても、リリースアーカイブでは
   ビルド設定側で切り離される（Xcode の挙動）。

## 提案（今回はやらなかったこと）

### A. `PlusView` に「StoreKit Testing 経路である」インジケータを出す
- `-SameQUseStoreKitPlus` 起動時のみ「これはテスト用の購入です」ラベルを表示
- 実機/本番ビルドでは出さない
- メリット: 条件 2・3 の simulator 検証で「本物の課金をしていない」ことが一目で分かる
- デメリット: UI 改修は条件1「同じ見た目・同じ導線」の精神と競合する可能性

### B. `Configuration.storekit` に free trial / introductory offer を追加
- App Store Connect 側で設定した無料トライアルをシミュレータでも再現
- 現状は無償期間なしなので省略

### C. `RevenueCatPlusService` の `availableProducts()` がネットワーク失敗時に
`Configuration.storekit` の商品定義へフォールバックする
- メリット: シミュレータ + RevenueCat 経路でも StoreKit Testing を併用できる
- デメリット: コードの分岐が複雑になり、回帰リスクが高い
- 判断: 既存の `-SameQUseStoreKitPlus` escape hatch で十分

### D. autoloop に「attempt 番号がコミットメッセージと 1 ずれている」自動補正
- eval-4 改善提案4 の再掲
- 追跡性のため attempt 番号とコミットメッセージを一致させる autoloop 側の改善
- 影響範囲: autoloop のシェルスクリプトのみ
- 判断: 本スプリントのスコープ外

---

## 履歴（参考）

### attempt 6（本実装）
- `.storekit` 構成を新規追加（シミュレータでの条件 2・3 検証経路確保）
- `project.yml` に `ENABLE_STOREKIT_TESTING: YES` と `storeKitConfiguration` を追加
- 212 ユニット + 15 UI 回帰すべて緑、Debug/Release ビルド SUCCEEDED

### attempt 5（user_action）
- ユーザー側で実施:
  1. App Store Connect 175 か国展開
  2. RevenueCat ダッシュボードに Product 登録 + Entitlement/紐付け
  3. secret API key を `.env.local` に追加
- generator は blocked 状態で実装変更なし

### attempt 4（前回・needs_fix 解消）
- AppSession.refreshPlusEntitlement() に nil 保護を追加
- test11〜14 を新規追加して 184/184 ユニット + 15/15 UI 回帰すべて緑
- evaluator は [3] 起動経路の nil 保護は解消確認、[1][2] は同指摘継続

### attempt 3（needs_fix）
- PlusServiceStub.swift を新規作成して AppSession に注入可能に
- RevenueCatPlusServiceTests に test06〜10 を追加
- AppSession.restorePlus() に nil 保護を追加（条件6）
- 180/180 ユニット + 15/15 UI 回帰すべて緑

### attempt 2（needs_fix）
- RevenueCat SDK を SPM 依存として導入（RevenueCat 5.87.0）
- RevenueCatPlusService.swift を新規作成
- AppSession 既定を RevenueCatPlusService に切替
- 175/175 ユニット + 15/15 UI 回帰すべて緑
- evaluator は [1] ダッシュボード目視不可・[2] ダッシュボード商品未登録 を新規指摘

### attempt 1（blocked → user_action）
- 着手前調査でブロッカー3つ発見
- ユーザー判断で選択肢(A) 採用
