# スプリント 14 attempt 6: .storekit 構成追加でシミュレータ検証を可能に

## 結論

attempt 5（`user_action`）でユーザーが次の作業を実施済み:
1. App Store Connect の Monthly Plus サブスクリプション（`com.nakakei6439.SameQ.plus.monthly`）
   の配信可否を 0 か国 → 175 か国に拡大
2. RevenueCat ダッシュボードの SameQ (App Store) に同じ商品 ID の Product を新規作成、
   entitlement `plus` にアタッチ
3. 同 Product を default Offering の Monthly パッケージに紐付け
4. RevenueCat の secret API key（Customers/Subscriptions/Purchases のみ Read only）を発行し、
   `.env.local` の `REVENUECAT_SECRET_API_KEY` に保存

これで **実機 + Sandbox Apple ID があれば** 条件 2・3・4 は観測可能になった。
ただし evaluator 環境には実機 / Sandbox Apple ID / RevenueCat ダッシュボード認証が
引き続き無いため、シミュレータで条件 2・3 を検証できる経路を追加するのが今回の主軸。

self-review attempt 5 の提案 B「`.storekit` を追加してシミュレータでも条件 2・3 を
検証できるようにする」を実装する。`StoreKitPlusService`（`-SameQUseStoreKitPlus`）経路を
シミュレータで動かすための StoreKit Testing 構成を定義する。

## 受け入れ条件（spec.md 行357〜364 から転記）
- [ ] 条件1: Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示される
- [ ] 条件2: サンドボックス購入で Plus 化（シミュレータ + StoreKit Testing で代替検証可能化）
- [ ] 条件3: 削除→復元で Plus 状態が戻る（シミュレータ + StoreKit Testing で代替検証可能化）
- [ ] 条件4: ダッシュボードに取引が現れる（ユーザー側ブロッカー・最終目視は人間）
- [ ] 条件5: 購入キャンセル時に責めないダイアログ
- [ ] 条件6: 通信できない状態で起動しても既存 Plus が無料転落しない
- [ ] 条件7: スプリント10の受け入れ条件7項目維持

## 実装方針

### 1. StoreKit Testing 構成ファイル新規作成
**`SameQ/Configuration.storekit`**（Xcode スキームの StoreKit Testing に登録）:
- `identifier`: 任意の UUID
- `subscriptionGroups`: 1 つだけ
- その中に `com.nakakei6439.SameQ.plus.monthly` を `RecurringSubscription` として定義
- `displayPrice`: `"480"`（実機の App Store で表示される金額と一致させる前提。
  StoreKit Testing は ja_JP ロケールで `¥480` と表示）
- `recurringSubscriptionPeriod`: `"P1M"`（月単位）
- `settings._locale`: `"ja_JP"`（テスト環境の既定ロケール）
- `version`: `{ major: 3, minor: 0 }`（StoreKit 2 / iOS 18+）

### 2. project.yml に StoreKit Testing 設定を追加
- `SameQ` ターゲットの `settings.base` に `ENABLE_STOREKIT_TESTING: YES` を追加
- `schemes.SameQ` の `run.storeKitConfiguration` に `path: SameQ/Configuration.storekit` を指定
- 同様に `test.storeKitConfiguration` も指定（UI テストでも StoreKit Testing を使えるように）

### 3. README への影響（最小限）
- `.storekit` 構成の存在を README に追記（既存の RevenueCat セットアップ手順の延長）。
  - ただし、本スプリントの自動評価者は実装コードとビルドを確認する側なので、
    README への記載は最小に留める（spec の制約: スプリント範囲外・過剰実装を避ける）

### 4. 影響範囲
- 新規ファイル追加のみ（既存コードへの変更は最小限）
- `RevenueCatPlusService` / `StoreKitPlusService` / `FakePlusService` の API は無変更
- `PlusView` / `PlusDecorationPicker` は無変更（条件1維持）
- ビルド時に `.storekit` がスキームに紐付くので、`-SameQUseStoreKitPlus` 経路で
  シミュレータを起動すると、StoreKit Testing の商品が `availableProducts()` に反映される
- 既定の `RevenueCatPlusService` 経路は引き続き実 API キー経由で RevenueCat サーバと通信
  （App Store Connect の登録が完了しているため、`Error fetching offerings` は出ないはず）

## 動かし方（evaluator 向け）

### シミュレータで StoreKit Testing 経由の条件 2・3 検証
```bash
# 1. プロジェクト生成
xcodegen generate

# 2. Debug ビルド（`Configuration.storekit` がスキームに紐付くこと）
xcodebuild -project SameQ.xcodeproj -scheme SameQ -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 3. シミュレータ起動（StoreKitPlusService 経路）
xcrun simctl install booted build/Debug-iphonesimulator/SameQ.app
xcrun simctl launch booted com.nakakei6439.SameQ -SameQUseStoreKitPlus
```

### 実機 / RevenueCat ダッシュボードの検証
引き続き人間 evaluator が実機 + Sandbox Apple ID で実施。
条件 4 は REST API v2 + secret key で部分検証可能:
```bash
curl -H "Authorization: Bearer $REVENUECAT_SECRET_API_KEY" \
  https://api.revenuecat.com/v2/projects/<project_id>/customers
```

## 3-strike rule 確認
- eval-2 → eval-3 → eval-4(前回) → eval-4(今回) → attempt 5 user_action 実施
- ユーザー側ブロッカー（dashboard 設定 / secret key 追加）は解消済み
- generator 側で実施可能な追加施策は .storekit 構成のみ
- これが通れば条件 2・3 の自動検証が可能になる

## 検証
- ユニット: `xcodebuild test -only-testing:SameQTests`（既存 184/184 を維持 + 新規追加）
- UI 回帰: `SprintTenAcceptanceTests` + `SprintElevenAcceptanceTests` + `SprintThirteenAcceptanceTests`
- ビルド: Debug / Release とも BUILD SUCCEEDED
- .storekit の妥当性: Xcode が `Configuration.storekit` を読み込めることを確認

## 仕様逸脱・過剰実装を避ける
- PlusView / PlusDecorationPicker は無変更（条件1維持）
- `RevenueCatPlusService` の挙動は無変更（App Store Connect 側の登録が完了したため、
  起動時の `Error fetching offerings` ログは出なくなる見込み）
- `StoreKitPlusService` の挙動も無変更（既存 escape hatch を活かすだけ）
- 新規 API / 新規メソッド追加なし
