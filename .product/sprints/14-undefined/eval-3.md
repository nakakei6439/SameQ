# スプリント 14 評価（attempt 3） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 観測で確認できたのは 2/7（条件1の一部・条件7）。条件5 はモックテストで担保。条件2・3・4 は出荷経路で未検証、条件6 は起動経路が未保護かつ未観測 | 100% | ✗ |
| 2 安定性 | クラッシュ0 / アプリ側未処理例外0 / 主要動線（起動→オンボーディング）到達。ただし既定（RevenueCat）経路で毎起動 `ERROR: 🍎‼️ Error fetching offerings` を1件出力 | クラッシュ0 / 未処理0 / 動線完走 | △ |
| 3 データ整合性 | FakePlus 経路の Plus 永続化は回帰なし（SprintTen test07 緑）。RevenueCat 経路の購入・復元・オフライン保持は本環境で検証不能 | 100% | ✗（評価不能） |
| 4 回帰 | ユニット 180/180、UI SprintTen 7/7・SprintEleven 4/4・SprintThirteen 4/4 | 100% | ✓ |
| 5 使用性 | Plus 画面は差し替え前と同一（PlusView 無変更）。空/読み込み状態あり。商品が取れないと「料金を読み込み中です…」から戻らない（既存挙動） | 3以上 | ✓（3） |

**総合: 不合格。** 基準1が 100% に届かない（特に受け入れ条件4）。基準3が評価不能。
attempt 2（eval-2）の中心的な差し戻し理由がそのまま残っている。

## 検証環境
- マシン: Xcode 26.6 / iPhone 17 Simulator（iOS 26.5, Build 23F77）/ autoloop 実行下の evaluator（Sonnet）
- 実行時刻: 2026-08-27 17:50〜17:58 JST
- コミット: `1027d62`（sprint 14 attempt 3）。作業ツリー clean。
- ユニット: `xcodebuild test -only-testing:SameQTests`（iPhone 17）→ **180/180 passed / TEST SUCCEEDED**（6.1s）
- 新規分のみ: `-only-testing:SameQTests/RevenueCatPlusServiceTests` → **10/10 passed**（test06〜10 を含む）
- UI 回帰: `SprintTenAcceptanceTests` + `SprintElevenAcceptanceTests` + `SprintThirteenAcceptanceTests`（iPhone 17）→ **15/15 passed / TEST SUCCEEDED**（227.6s）
- ビルド: Debug `BUILD SUCCEEDED`（`/tmp/sameq_eval_dd`）
- 手動起動: Debug ビルドを iPhone 17 に install→launch（**既定＝RevenueCatPlusService 経路**、起動引数なし）。オンボーディング画面まで到達、クラッシュなし。スクショ `/tmp/sameq_default_1.png`、ログ `/tmp/sameq_default_log.txt`
- 秘密情報: `.env.local` の RevenueCat キーは公開 SDK キー（`appl_` 接頭辞）のみ。secret key（`sk_`）無し。`.storekit` 構成ファイル無し。

## 不合格の原因（これを直せば通る）

### [1] 受け入れ条件4「ダッシュボードに取引が現れる」を本評価環境で確認できない（eval-2 [1] と同一・未解消）
- **spec.md 該当条件**: 「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）」
- **再現手順**:
  1. autoloop 上の評価者は https://app.revenuecat.com/ に認証手段が無い（`WebFetch` は認証必須 URL を扱えない）。
  2. `.env.local` に RevenueCat の secret key（`sk_` / REST API v2 用）が無いため、`curl` で当該 app_user_id の transactions を照会できない。
  3. 実機 + Sandbox Apple ID が無く、`.storekit` 構成も無いため、シミュレータ単独で RevenueCat サーバーへ到達する本物のサンドボックス購入を発火できない。
- **期待**: サンドボックス購入→復元を実施し、RevenueCat ダッシュボードの Customers / Transactions に実績が残ることを目視で確認できる状態。
- **実際**: 一度も観測できていない。attempt 3 の変更（`restorePlus()` の nil ガード＋ユニットテスト5本）は条件4 の検証可能性を変えていない。generator 自身も self-review で「条件4 は人間 evaluator 担当」と明記しており、autoloop の自動評価者では成立しない。
- **根拠**: self-review.md「動かし方」節、`.env.local`（secret key 不在）、`find . -name "*.storekit"` が 0 件。

### [2] RevenueCat ダッシュボードに商品／Offering が未登録 — 実機でも条件2・3が通らない見込み（eval-2 [2] と同一・未解消）
- **再現手順**:
  1. 既定（RevenueCatPlusService）で Debug ビルドを起動。
  2. `xcrun simctl spawn "iPhone 17" log stream --predicate 'process == "SameQ"'` を観測。
- **期待**: `plus` エンタイトルメントに紐づく商品がダッシュボードに登録され、offerings が取得できる。
- **実際**: 起動直後に SDK が次を出力（`/tmp/sameq_default_log.txt`）:
  ```
  DEBUG: ℹ️ Using a simulator. Ensure you have a StoreKit Config file set up before trying to fetch products or make purchases.
  DEBUG: ℹ️ API request completed: GET '/v1/subscribers/.../offerings' (304)
  ERROR: 🍎‼️ Error fetching offerings - The operation couldn’t be completed. (RevenueCat.OfferingsManager.Error error 1.)
  ```
  （SDK は `api.revenuecat.com` へ到達し `POST /v1/config/app` は 204、subscriber GET は 304。接続自体は成立している。商品／offering が空なのが原因。）
- **影響**: `RevenueCatPlusService.purchase(_:)` は購入成立後に `CustomerInfo.entitlements["plus"]` を確認し、無ければ `PlusPurchaseError.other("Plus のエンタイトルメントが付与されませんでした")` を投げる。Product↔Entitlement(`plus`) の紐付けがダッシュボードに無い現状では、実機でサンドボックス購入しても `plus` が active にならず、**受け入れ条件2・3 も実機で失敗する**見込み。
- **根拠**: 上記ログ、`RevenueCatPlusService.swift` の entitlement 未付与ガード。

### [3] 受け入れ条件6（オフライン起動で Plus 転落しない）の「起動経路」が未保護かつ未観測
- **症状**: attempt 3 の保護は `AppSession.restorePlus()`（設定画面の「購入を復元」ボタンを押したときだけ通る）に入った。しかし条件6 は「**通信できない状態で起動しても**」＝起動時の `refreshPlusEntitlement()` の経路。`refreshPlusEntitlement()` は今も `plusEntitlement = entitlement` と `currentEntitlement()` の戻り値を無条件で代入しており、`nil` が返れば `plusEntitlement = nil`（Plus 転落）になる。
- **再現手順（コード上）**: `AppSession.refreshPlusEntitlement()`（AppSession.swift 294〜301行）を読む。`nil` ガードは `restorePlus()` にしか無い。
- **期待**: 起動時にオフラインで `currentEntitlement()` が `nil` を返しても、既存の Plus 状態を落とさない（または「落とさないことを観測できるテスト」）。
- **実際**: 起動経路は無防備。generator の主張は「RevenueCat SDK 5.x が customerInfo をオフラインでもキャッシュから返すので `nil` にならない」だが、`test10_AppSessionRefreshAfterPurchaseReadsSameEntitlement` はスタブが常に同じ値を返すだけで、**実 SDK のオフラインキャッシュ挙動を何も検証していない**（同義反復テスト）。eval-2 [3] で指摘した「保証を確認できるテスト・観測が無い」状態が、起動経路については未解消。
- **根拠**: AppSession.swift `refreshPlusEntitlement()` / `restorePlus()`、RevenueCatPlusServiceTests.swift test10、eval-2.md [3]。

## 観測できたこと（合格側の材料）
- **条件1（見た目・導線が同一）**: `PlusView.swift` / `PlusDecorationPicker.swift` は attempt 3 の diff に含まれず無変更（`git diff 3af84f7..1027d62 --stat`）。SprintTen test02/test06 緑。文言・導線の増減なし（過剰実装なし）。ただし「価格が App Store 設定額と一致」はシミュレータで商品が取れず未確認。
- **条件5（キャンセルで責めない）**: 新規 test06 が `PlusServiceStub.purchase(.failure(.userCancelled))` → `AppSession.purchasePlus()` が `alertMessage == nil` / `false` を返すことを確認。test07 が `.network` では `alertMessage` が立つことを確認（分岐の回帰）。`RevenueCatPlusService.purchase(_:)` は `data.userCancelled` と `ErrorCode.purchaseCancelledError` の両方を `.userCancelled` にマップしている（コードレビュー範囲）。モック経路での担保としては妥当。
- **条件7（スプリント10の7条件維持）**: SprintTenAcceptanceTests 7/7 passed。
- **回帰**: ユニット 180/180、SprintEleven 4/4、SprintThirteen 4/4。
- **安定性（クラッシュ）**: 既定の RevenueCat 経路でアプリ起動→オンボーディング表示、クラッシュ・アプリコード側の未処理例外なし。新規クラッシュログなし。RevenueCat SDK は `api.revenuecat.com` へ正常に接続している（購入が発生すればサーバーへ POST が走る配線自体は生きている）。

## 改善提案（合否には影響しない）
1. **[中]** 条件6 の保護を `refreshPlusEntitlement()` にも広げる（`currentEntitlement()` が `nil` かつ既存 `plusEntitlement` が `isActive` なら温存する等）。起動経路こそ条件6 の本丸。
2. **[中]** 商品が取得できないときの Plus 画面が「料金を読み込み中です…」から戻らない（既存挙動）。一定時間後に「Plus の商品情報を読み込めませんでした。時間をおいて再度お試しください」へ落とす導線があると条件5 の精神に沿う。
3. **[低]** `test10` を「実 SDK のオフラインキャッシュを観測する」テストに置き換えるか、少なくとも「同義反復であり条件6 の保証にはならない」旨をテスト名/コメントで正直に書く。

## 評価できなかったもの（差し戻しの中心）
- 受け入れ条件2: サンドボックス購入でその場 Plus 化 → **実機必須・未検証**
- 受け入れ条件3: 削除→再インストール→復元（アプリ内・設定画面の両方） → **実機必須・未検証**
- 受け入れ条件4: 購入・復元がダッシュボードに取引として出る → **ダッシュボードアクセス＋実機必須・未検証**（spec は「確認できない実装は不合格」と明記）
- 受け入れ条件6: オフライン起動で既存 Plus ユーザーが無料転落しない → **起動経路が未保護・未観測**

## ユーザー判断が必要（2 回連続で同じ所で止まっている）
本スプリントは、autoloop の自動評価者（ブラウザ認証なし・実機なし・secret key なし）の環境では
受け入れ条件2・3・4 を原理的に検証できない。eval-2 の差し戻し注記と同じ状況が続いている。
次のいずれかがないと合格判定は出せない:
- **(a)** ユーザーが手動で「RevenueCat ダッシュボードに商品／Offering／Entitlement(`plus`) を登録」→「実機で Sandbox 購入・復元」→「ダッシュボードで Customers / Transactions を目視」まで行い、その結果を eval / state.json に添付する運用へ切り替える。
- **(b)** `.env.local` に RevenueCat の secret key（`sk_`）を追加し、評価者が REST API v2 で当該 app_user_id の transactions を照会できるようにする。
- **(c)** スプリント14 の受け入れ条件を autoloop で検証可能な形へ緩める（spec 変更。ただし「ダッシュボードに実績が残る」がこの差し替えの目的そのものなので、緩めるとスプリントの意味が薄れる）。

いずれもユーザーの判断が要る。あわせて原因[2]（ダッシュボードに商品未登録）は実機検証の前に解消が必須。
