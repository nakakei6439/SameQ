# スプリント 14: Plus 課金基盤を RevenueCat へ差し替え

## 受け入れ条件（spec.md 行357〜364 から転記）
- [ ] Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示され、価格は App Store 側で設定した金額と一致する（差し替え前と同じ見た目・同じ導線であること）
- [ ] サンドボックスで購入を完了すると、その場で Plus 状態になり、140文字を超える入力と Plus 限定の絵文字・装飾が使えるようになる
- [ ] 購入した端末でアプリを削除して入れ直し「購入を復元」をすると Plus 状態が戻る。設定画面の復元からも同じ結果になる
- [ ] サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）
- [ ] 購入をキャンセルした場合、失敗を責めるようなダイアログを出さず、Plus 未購入のまま画面が操作可能な状態に戻る
- [ ] 通信できない状態で起動しても、すでに Plus のユーザーが無料状態に転落せず、長文入力と装飾が使えるままになる
- [ ] スプリント10の受け入れ条件7項目がすべて維持される

## 着手前調査の結果（ブロッカー3点）

### ブロッカー1: 仕様ルールの構造的矛盾
- spec.md 行23「課金は RevenueCat」・行115（前提17）「課金基盤は前提条件表どおり RevenueCat に戻す」・行352 のスプリント14本文 が RevenueCat SDK を明示指定
- 一方 spec.md 行11（対象外）は「外部パッケージ依存はゼロ（Swift標準 + Apple SDK のみ利用可）」
- RevenueCat SDK は SPM（Swift Package Manager）で配布されるサードパーティ外部パッケージで、行11 と直接衝突する
- スプリント10（行280〜294）の generator はこの矛盾を「PlusService プロトコル抽象 + StoreKit 2 実装」で回避し、ユーザー承認で合格済み（attempt 1 passed）
- **判断が必要**: ユーザー側で rule 11 を明示的に緩和するか、スプリント14を撤回するか

### ブロッカー2: RevenueCat API key がプロジェクト内に存在しない
- `.env.local` を確認済み（行1〜24）。Supabase の公開キー・DBパスワードはあるが RevenueCat の API key（`appl_***` または `rcat_***`）は無い
- `project.yml`（行1〜85）に RevenueCat SDK への SPM 依存は未登録
- `SameQ.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` 配下に package 定義なし
- **判断が必要**: ユーザーが RevenueCat アカウントを既に作成済みの場合は API key を `.env.local` へ追加する。未作成なら作成手順（https://app.revenuecat.com/）を案内する

### ブロッカー3: 受け入れ条件4（ダッシュボード取引確認）は generator 環境から検証不能
- spec.md 行361「**この確認ができない実装は不合格とする**」
- RevenueCat ダッシュボード（https://app.revenuecat.com/）へのアクセスは generator から不可（ブラウザ自動化なし・トークン無し）
- サンドボックス購入後の取引反映は **実機 + ユーザー側ダッシュボード目視**でしか検証できない
- **判断が必要**: evaluator（人間）がサンドボックス購入後にダッシュボードを直接目視する手順を self-review.md に明記する必要がある

## 実装方針（ブロッカー解消後に着手する場合）

### ファイル変更案
1. `project.yml`: `dependencies: [{package: RevenueCat/purchases-ios, from: 5.0.0}]` を追加
2. `xcodegen generate` で `.xcodeproj` 再生成
3. `SameQ/Backend/RevenueCatPlusService.swift`（新規）: `PlusService` プロトコル準拠の RevenueCat 実装
   - `Purchases.configure(withAPIKey:)` で初期化（API key は `.env.local` または `Info.plist` から読む）
   - `availableProducts()` は `Purchases.shared.getProducts(_:)` で App Store 商品を取得
   - `currentEntitlement()` は `Purchases.shared.getCustomerInfo()` の entitlements を反映
   - `purchase(_:)` は `Purchases.shared.purchase(product:)` を呼び、結果を `PlusEntitlement` に変換
   - `restore()` は `Purchases.shared.restorePurchases()` を呼ぶ
4. `SameQ/Session/AppSession.swift`（行191〜194）: Release 経路を `StoreKitPlusService()` から `RevenueCatPlusService()` へ切替。`-SameQFakePlus`（Debug）は FakePlusService のまま、起動引数 `-SameQUseStoreKitPlus` で旧 StoreKit 実装に戻せるよう escape hatch を残す
5. `SameQ/Backend/PlusService.swift`（行1〜10 のコメント）: RevenueCat が本実装になったことを反映
6. `SameQ/Backend/StoreKitPlusService.swift`（行1〜14 のコメント）: escape hatch 用途である旨を明記

### 影響範囲
- **既存テスト**: `PlusServiceTests`（行198〜273 の FakePlusService 永続化テスト）は FakePlusService を使うため影響なし。`SprintTenAcceptanceTests` は `-SameQFakePlus` で動くため影響なし（debug build 想定）
- **Release ビルド**: `RevenueCatPlusService` が動く。StoreKit 経路は `-SameQUseStoreKitPlus` 起動引数でのみ選択可
- **PROGRESS.md 行321 の記述**: 「スプリント10: Plus（RevenueCat による課金）」タイトルは実装実態と一致するようになる

### 検証計画（ブロッカー解消後）
- **ユニットテスト**: 既存の `PlusServiceTests`（166本+α）に RevenueCat 経路の薄い検証（API key 未設定時の挙動・商品取得失敗時のフォールバック等）を 1〜2 本追加
- **UI 回帰**: 直近 2〜3 スプリント分の UI テストを固定サンプル実行（SprintTen/SprintEleven/SprintThirteenAcceptanceTests）
- **Sandbox 検証**: evaluator が iPhone 17 / iPhone 17 Pro でサンドボックス購入 → ダッシュボード反映確認（条件4）
- **データ整合性**: 既存 `state.json` の schemaVersion 互換性（Plus 関連永続化フィールドの変更なし、影響なし想定）

## 影響範囲（ブロッカー未解消で本 sprint を完全に block する場合）
- コード変更: ゼロ（既存の `StoreKitPlusService` 経路をそのまま温存）
- state.json: `status: in_progress → blocked`、attempt 据え置き
- autoloop.sh: blocked ステータスで正常停止（exit 2）
- PROGRESS.md: 「現在の状態」節に本 blocker のサマリを追記する必要あり

## 引き継ぎサマリ
attempt 1 は「着手前調査 → 3 つのブロッカー発見 → blocked」で終わる。
コード変更は行わず、ユーザー判断を仰ぐ。次 attempt はユーザー回答後に着手。
