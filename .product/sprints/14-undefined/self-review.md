# スプリント 14 attempt 4: 起動経路の nil 保護（条件6）と再評価

## 結論

eval-3 の **[3] 起動経路 `refreshPlusEntitlement()` の nil 保護欠落** を修正した。
`refreshPlusEntitlement()` が `currentEntitlement()` から `nil` を返されたときも、
既存 `plusEntitlement` が購読期間内（`isActive(at: clock.now)`）であれば
**上書きしない**保護を追加し、新規ユニットテスト 4 本（test11〜14）でこの挙動を
回帰防止付きで保証する。

[1]（ダッシュボード目視）と [2]（ダッシュボード商品未登録）はユーザー側ブロッカーの
ため、generator では対応不可（spec が「確認できない実装は不合格」と明記）— eval-3
から変更なし。`self-review.md` の「動かし方」節に詳しい手順を残し、
evaluator（人間）担当として明示する。

attempt 3 で `restorePlus()` に入れた保護を `refreshPlusEntitlement()` にも
広げ、条件6「通信できない状態で起動しても、すでに Plus のユーザーが無料状態に
転落せず」を**コード・自動テストの両方で担保**する。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が同一 | 達成 | `PlusView` / `PlusDecorationPicker` は attempt 3 から無変更（git diff 0 行）。SprintTenAcceptanceTests test02/test06（価格表示・導線）緑 |
| 2. サンドボックス購入で Plus 状態が有効化 | 達成（コード） | `purchase(_:)` → `Purchases.purchase(product:)` → 成功時に `CustomerInfo.entitlements["plus"]` を `PlusEntitlement` に詰める既存実装を維持。実機 Sandbox 購入はユーザー側検証（商品未登録のため現状未達） |
| 3. 端末削除→復元で Plus 状態が戻る | 達成（コード） | `restore()` → `Purchases.restorePurchases()` 経路を維持。サンドボックス購入は RevenueCat サーバー側に記録されるため再インストールでも復帰する経路 |
| 4. ダッシュボードに取引が現れる | **evaluator 担当** | autoloop から https://app.revenuecat.com/ へのログイン不可・トークン無し。実装側は条件1〜3 が満たれば RevenueCat サーバーへの POST が走る作り。「動かし方」節に手順を明記 |
| 5. 購入キャンセル時に責めない | 達成（テスト追加・attempt 3 で担保） | attempt 3 で `PlusServiceStub.purchase(.failure(.userCancelled))` を AppSession に注入する test06 を追加済み。test07 で `.network` のときは `alertMessage` が立つことも同時確認 |
| 6. **オフラインで Plus 状態が転落しない** | **達成（コード + テスト修正）** | **attempt 4** で ①`AppSession.refreshPlusEntitlement()` を「`currentEntitlement()` が `nil` を返し、既存 `plusEntitlement` が `isActive(at: clock.now)` のときは上書きしない」よう修正、②新規 test11 で「1回目 refresh で Plus 入り → オフライン化（`currentEntitlementResult = nil`） → 2回目 refresh でも Plus 維持」を直接確認、③test12 で「未購入ユーザーが nil を受けても新規 Plus 状態を起こさない」ことを確認、④test13 で「期限切れ + nil refresh で `nil` に戻る（保護は isActive 限定）」ことを確認、⑤test14 で「`currentEntitlement()` が non-nil の新しい entitlement を返すケースは従来どおり更新される」ことを確認 |
| 7. スプリント10の受け入れ条件7項目維持 | 達成 | SprintTenAcceptanceTests 7/7 緑（FakePlus 経路・RevenueCat と独立）。SprintEleven（設定・復元ボタン）4/4 緑 |

## eval-3 指摘への対応

### [3] 起動経路 `refreshPlusEntitlement()` の nil 保護欠落 — **今回修正**
- **修正内容**: `AppSession.refreshPlusEntitlement()` を「`currentEntitlement()` が `non-nil` を返すときは従来どおり上書き、`nil` を返しかつ既存 `plusEntitlement` が `isActive(at: clock.now)` のときは温存、それ以外（既存 nil / 既存期限切れ）は `nil` に置き換え」の 3 経路に分岐。
- **コード**: 11 行 → 17 行（コメント込み）。`plusService` が `nil` のときは従来どおり `nil` を入れる経路を温存。
- **テスト**: `test11`（メイン条件6保護）/ `test12`（未購入で温存しない）/ `test13`（期限切れは温存しない）/ `test14`（non-nil 更新は従来どおり）の 4 本を追加。

### [1] ダッシュボード目視 — ユーザー側ブロッカー（変化なし）
- 3 回連続で同一指摘。autoloop 環境では原理的に検証不能。
- self-review.md 「動かし方」節の手順で人間がダッシュボード目視するしかない。

### [2] ダッシュボード商品未登録 — ユーザー側ブロッカー（変化なし）
- 起動時の `ERROR: 🍎‼️ Error fetching offerings` ログは、商品未登録の直接の結果（仕様上「商品が 0 件」状態）。
- ユーザー側で App Store Connect + RevenueCat ダッシュボードに商品を登録すれば消える。

## 動かし方（evaluator 向け）

### 受け入れ条件4（ダッシュボード反映）の確認手順 — 人間が実行
1. **App Store Connect 側で商品登録**:
   - https://appstoreconnect.apple.com/apps/6443888883/subscriptions （App ID `com.nakakei6439.SameQ`）
   - Subscription Group に月額 Subscription を追加（Product ID: `com.nakakei6439.SameQ.plus.monthly`、期間: 1 month、価格: ¥480）
   - Status を "Ready to Submit" 以上に
2. **RevenueCat ダッシュボードで Product ↔ Entitlement を紐付け**:
   - https://app.revenuecat.com/projects/e444c0e4/overview
   - `Products` タブ: `com.nakakei6439.SameQ.plus.monthly` が登録され、App Store Connect と紐付いていること
   - `Entitlements` タブ: `plus` が作成され、上記 Product がアタッチされていること
3. **実機でサンドボックス購入**:
   - App Store Connect → Users and Access → Sandbox Testers でテスター作成
   - 実機 iPhone で Sandbox Apple ID としてサインイン（設定 → App Store → サインアウト → Sandbox アカウントで再サインイン）
   - `PlusView` を開き、購入ボタンを押す → 購入完了
4. **RevenueCat ダッシュボードで目視確認**:
   - `Customers` タブで sandbox 購入を行ったユーザーの `app_user_id` を検索
   - `Entitlements` が `plus` で active になっていること、購入時刻が記録されていることを確認
   - `Transactions` タブで購入履歴が残る
5. **復元経路の検証**:
   - アプリを完全削除 → 再インストール → オンボーディング完了 → 設定画面 → 「購入を復元」を押す
   - Plus ラベル / 長文入力・装飾が再び使えるようになることを確認

### 受け入れ条件6（起動経路のオフライン保護）の確認手順
1. **実機/シミュレータで実検証**: 上記手順で Plus 状態にしたあと、
   - **実機**: 機内モード ON → アプリ完全終了 → 機内モードのまま起動 → Plus 状態が温存されていること（`debugStatusLine` に `plus` と表示されること）
   - **コード上**: attempt 4 で `refreshPlusEntitlement()` に `isActive` 限定の nil 保護が入っていること、`test11` で実証済み

### Debug 経路（シミュレータで Plus 画面を触りたい場合）
- `-SameQFakePlus`: `FakePlusService`（既存挙動と完全一致）
- `-SameQUseStoreKitPlus`: 旧 `StoreKitPlusService` 経路（escape hatch）
- 上記どちらも付けない既定: `RevenueCatPlusService`（スプリント14のリリース形）

### 自動テストの実行
```bash
# ユニット全件（184本）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:SameQTests

# 新規追加分のみ（attempt 4 で追加した 4 本）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:SameQTests/RevenueCatPlusServiceTests/test11_AppSessionRefreshWithNilDoesNotDropExistingPlus
```

## 変更ファイル

### 修正
- **`SameQ/Session/AppSession.swift`** (`refreshPlusEntitlement()`): nil 保護を
  追加（6 行）。既存 `plusEntitlement` が `isActive` のときに限り、
  `currentEntitlement()` が `nil` を返しても `plusEntitlement` を上書きしない
  （eval-3.md [3] への対応・条件6 起動経路の保護）。コメントで
  attempt 4 (eval-3.md [3] への対応・条件6 保護) と理由を明記。

### 新規
- **`SameQTests/RevenueCatPlusServiceTests.swift` (追記・test11〜14 を追加)**:
  - test11: refresh に nil を渡しても既存 Plus が落ちない（条件6 起動経路の保護・主軸）
  - test12: 未購入ユーザーが refresh で nil を受けても新規 Plus 状態を起こさない
  - test13: 既存 Plus が購読期間外（期限切れ）のとき refresh で nil を受ければ `nil` に戻る（保護は isActive 限定）
  - test14: refresh が non-nil の新しい entitlement を返すときは従来どおり更新される

## テスト実行結果

### 新規ユニットテスト（4本）
```
Test Suite 'RevenueCatPlusServiceTests' passed
  test11_AppSessionRefreshWithNilDoesNotDropExistingPlus   (0.002s) ✓
  test12_AppSessionRefreshWithNilWhenNoExistingPlusKeepsPlusStateNil (0.001s) ✓
  test13_AppSessionRefreshWithNilWhenExistingIsExpiredClearsPlusState (0.003s) ✓
  test14_AppSessionRefreshWithNewEntitlementUpdatesPlusState (0.001s) ✓
Executed 14 tests, with 0 failures (0 unexpected) in 0.064 seconds
```

### 全ユニットテスト（184本 = 既存180本 + 新規4本）
```
Executed 184 tests, with 0 failures (0 unexpected) in 6.066 seconds
** TEST SUCCEEDED **
```

### UI 回帰（直近2〜3スプリント分から最大3クラス）
- SprintTenAcceptanceTests 7/7（Plus 画面の FakePlus 経路・回帰確認）
- SprintElevenAcceptanceTests 4/4（設定・復元ボタン）
- SprintThirteenAcceptanceTests 4/4（サーバー側 BAN / 連打制限）
- **合計 15/15 passed**（229.2秒・TEST SUCCEEDED）

### ビルド
- Debug: BUILD SUCCEEDED（test BUILD）
- Release: BUILD SUCCEEDED（warning のみ・既存コード由来・今回追加分に由来する warning 無し）
- クラッシュ 0・未処理エラー 0・タイムアウト 0

## 実装メモ

### 条件6 保護の設計判断（起動経路・attempt 4）
attempt 3 の `restorePlus()` は設定画面の「購入を復元」ボタンを押したときしか
通らない経路だった。条件6 は「**通信できない状態で起動しても**」の文面で、
`start()` 内の `await refreshPlusEntitlement()`（行 262）が経路の本丸。
attempt 3 ではここに nil 保護が無かったため、起動時にオフライン +
SDK キャッシュ喪失で `currentEntitlement()` が `nil` を返すと
既存 Plus ユーザーが無料状態に転落するリスクがあった。

attempt 4 では 3 経路に分岐:
1. **`non-nil` を取得**: 従来どおり上書き（購読期間更新を反映）
2. **`nil` を取得 + 既存 `plusEntitlement` が `isActive`**: 温存（条件6 保護）
3. **`nil` を取得 + 既存が無い or 期限切れ**: `nil` に置き換え

`isActive` 限定にすることで、**期限切れの偽 Plus 状態**を持たないようにしている
(test13 で回帰確認)。`plusService` 自体が `nil` のとき（Plus 機能無効）は
従来どおり `plusEntitlement = nil`（行 305）。

### test10（attempt 3 既存）との関係
attempt 3 で追加した `test10_AppSessionRefreshAfterPurchaseReadsSameEntitlement` は
「同じ Plus を繰り返し読める」回帰確認。attempt 4 で `refreshPlusEntitlement()` を
変更したが、test10 は引き続き成功する（スタブが常に同じ Plus を返すため、
attempt 4 のロジックは ①経路の「non-nil を取得 → 上書き」を通る）。
attempt 4 で nil 保護を入れた経路は test11 が直接カバー。

### 触らなかった判断
- `PlusView` / `PlusDecorationPicker`: 無変更（条件1 維持）。
- `RevenueCatPlusService` 本体: 無変更（attempt 2 の実装が条件5・6 を満たすことを確認）。
- `FakePlusService` / `StoreKitPlusService`: 無変更（既存経路として温存）。
- `Backend` プロトコル: 無変更（Plus 関連 API は無変更）。
- `PlusService` プロトコル: 無変更（既存 `currentEntitlement()` の戻り値だけを見る）。

## 自分で見つけた弱点

1. **条件4 は引き続き人間 evaluator 必須**（3 回連続で同じ指摘・未解消）:
   `app.revenuecat.com` へのブラウザ認証・secret key・実機 Sandbox Apple ID が
   autoloop には揃わず、generator 環境から到達不能。
2. **原因[2] ダッシュボード商品未登録**（3 回連続で同じ指摘・未解消）:
   起動時の `ERROR: 🍎‼️ Error fetching offerings` ログは、ユーザ側で
   App Store Connect + RevenueCat ダッシュボードに商品を登録すれば消える
   （generator 環境から到達不能）。
3. **条件2・3 の実機サンドボックス購入も人間 evaluator 必須**:
   商品未登録のため、現状サンドボックス購入で `plus` エンタイトルメントが
   付与されない可能性が高い（条件2・3 も実機では未達見込み）。
4. **SDK 起動時の "Error fetching offerings" ERROR ログ**: attempt 2 で観測、
   attempt 4 でも継続。商品登録前の暫定挙動として app_product が空のままでも
   UI クラッシュは起こさない既存実装を維持（`availableProducts()` は空配列を
   返すだけ、`currentEntitlement()` は `nil` を返すだけ）。
5. **Purchases.configure の冪等性**: テストで複数回 `RevenueCatPlusService` を
   作ると SDK が「already configured. Ignoring duplicate call.」の INFO を出す。
   機能上は無害だが、ログがうるさい場合は Purchases SDK のテスト用リセット API
   （v5.x にはない）を待つしかない。
6. **attempt 4 で `currentEntitlement()` の保護を入れたが、SDK の挙動が変わると
   機能しなくなる**: test11〜14 は PlusServiceStub 経由のため、
   **実 SDK のオフライン挙動を保証するテストではない**。これは test10 と同じ
   限界（attempt 3 self-review の弱点5 に既記載）。

## 提案（今回はやらなかったこと）

### A. 人間 evaluator の確認結果を state.json / eval に添付する運用
- 条件4 は原理的に autoloop では検証不能なので、「ユーザーがダッシュボードで
  取引を確認した」という事実を明示的に残せる形（添付ファイル・JSON など）を
  用意するのは次回以降の運用改善候補。

### B. Plus 画面の「料金を読み込み中です…」にタイムアウト導線
- attempt 2 評価の改善提案2で挙がった、商品取得失敗時のユーザー案内。スプリント
  範囲外（Plus 画面の UI 改修）のため未実装。

### C. SDK のキャッシュ喪失を強制する統合テスト
- `URLProtocol` モック + SDK の内部キャッシュクリア API 呼び出しで
  「実 SDK で offline → cache empty → nil → 既存 Plus 維持」を再現できれば
  より直接的な保証になるが、SDK のバージョン依存と内部実装依存が強い。
  attempt 4 は AppSession 側の挙動を保証する方に振り切っている（保守性重視）。

## 申し送り

- **コード変更**: attempt 4 で完了（AppSession.refreshPlusEntitlement の 1 関数のみ）。
  PlusService 本体（`RevenueCatPlusService` / `FakePlusService` /
  `StoreKitPlusService`）は無変更。
- **テスト**: 184/184 unit + 15/15 UI 回帰、すべて TEST SUCCEEDED
- **ビルド**: Debug / Release とも BUILD SUCCEEDED
- **evaluator 手順**: 「動かし方」節の「受け入れ条件4（ダッシュボード反映）の
  確認手順」で人間がダッシュボード目視（条件4）+ 実機 Sandbox 購入（条件2・3）を
  実施。条件6 は attempt 4 で自動担保済み（test11 が起動経路の nil 保護を直接確認）。
- **3-strike rule 経過**: eval-2 / eval-3 / 今回 eval-4 で [1][2] は同指摘継続
  だが、[3] は今回で潰した。**autoloop が継続するかどうかは evaluator の判定次第**。
  次の評価で [3] が解消している前提で autoloop は sprint 15 へ進む想定だが、
  ユーザー判断が必要なら evaluator がハンドオフする。
- **autoloop**: status を `awaiting_eval` に更新すれば自動継続可能。
  attempt 4 として記録される。
