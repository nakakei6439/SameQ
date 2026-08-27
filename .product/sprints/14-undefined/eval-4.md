# スプリント 14 評価（attempt 4） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 観測で確認できたのは 7 条件中 2.5（条件7・条件1の「見た目/導線が同一」部分・条件5 はモックテストで担保）。条件1 の「価格が App Store 設定額と一致」、条件2、条件3、条件4 は出荷経路で未検証。**条件4 は spec が「確認できない実装は不合格とする」と明記** | 100% | ✗ |
| 2 安定性 | クリーン起動（iOS 26.5 / 26.4）でクラッシュ0・主要動線（起動→オンボーディング）到達・新規クラッシュレポート0。ただし①既定 RevenueCat 経路は毎起動 `ERROR: 🍎‼️ Error fetching offerings` を1件出力、②**iOS 26.3 シミュレータでユニット全体が `RevenueCatPlusServiceTests.test03` でハング（`restorePurchases()` が「Apple Account にサインイン」システムモーダルを出して無限待ち）。2回再現** | クラッシュ0 / 未処理0 / 動線完走 | △ |
| 3 データ整合性 | FakePlus 経路の Plus 永続化は回帰なし（SprintTen test07 緑）。RevenueCat 経路の購入・復元・オフライン保持は本環境で検証不能（実購入を発火できない） | 100% | ✗（評価不能） |
| 4 回帰 | ユニット 184/184（iOS 26.5・6.8秒）、UI SprintTen 7/7・SprintEleven 4/4・SprintThirteen 4/4 = 15/15（229.7秒・TEST SUCCEEDED） | 100% | ✓ |
| 5 使用性 | Plus 画面は差し替え前と同一（`PlusView.swift` / `PlusDecorationPicker.swift` はスプリント14で1行も変更なし）。オンボーディングは空状態も説明も設計されている。既定経路で商品が取れないと「料金を読み込み中です…」から戻らない（既存挙動・本スプリントで悪化はしていない） | 3以上 | ✓（3） |

**総合: 不合格。** 基準1が 100% に届かない（特に受け入れ条件4）。基準3は評価不能。
eval-2 / eval-3 の中心的な差し戻し理由（[1] ダッシュボード目視不可・[2] ダッシュボードに商品未登録）が
**3回連続でそのまま残っている**。今回 generator が対応した eval-3 [3]（起動経路の nil 保護）は解消を確認した。

## 検証環境
- マシン: Xcode 26.6（Build 17F113）/ macOS
- シミュレータ:
  - iOS 26.5「iPhone 17」(35AAC789…) — autoloop 既定と同じ。ユニット・UI 回帰はここで実施
  - iOS 26.4「iPhone 17」(9B712B3E…) — `erase` 後のクリーン端末で手動起動確認
  - iOS 26.3「iPhone 17」(12050FBD…) — ユニットが test03 でハング（後述 [4]）
- コミット: `34dfe45`（autoloop のコミットメッセージは "sprint=14 attempt=3" だが、`state.json` は attempt 4、`self-review.md` も attempt 4 の内容。`AppSession.swift` の nil 保護と `RevenueCatPlusServiceTests` test11〜14 はこのコミットに含まれる）。作業ツリー clean。
- 実行時刻: 2026-08-27 18:09〜18:34 JST
- ユニット: `xcodebuild test -only-testing:SameQTests`（iOS 26.5）→ **184/184 passed / TEST SUCCEEDED**（6.8s）。test11〜14 も緑。
- UI 回帰: `-only-testing` で SprintTen + SprintEleven + SprintThirteen（iOS 26.5）→ **15/15 passed / TEST SUCCEEDED**（229.7s）
- ビルド: Debug（test ビルド）`BUILD SUCCEEDED`（`/tmp/sameq_eval4_dd265`）
- 手動起動: 既定＝RevenueCatPlusService 経路（起動引数なし）を iOS 26.4 クリーン端末に install→launch。オンボーディング1ページ目まで到達、クラッシュなし、システムダイアログなし。再起動でも同じ。スクショ `/tmp/sameq_clean_1.png` `/tmp/sameq_clean_relaunch.png`
- 秘密情報: `.env.local` の RevenueCat キーは公開 SDK キー（`appl_`）のみ。secret key（`sk_`）無し。`find . -name "*.storekit"` は 0 件。
- 認証: `app.revenuecat.com` / `appstoreconnect.apple.com` への評価者からのログイン手段なし。

## 観測できたこと（合格側の材料）
- **条件1（見た目・導線が同一 / 過剰実装なし）**: `git diff a5f786f..HEAD` の対象は `LaunchOptions.swift`(+12) / `RevenueCatPlusService.swift`(新規) / `AppSession.swift`(+48) / テスト2ファイルのみ。**`PlusView.swift` と `PlusDecorationPicker.swift` はスプリント14で無変更**（最終更新はスプリント10）。文言・導線の増減なし。SprintTen test02（価格表示・ボタン）/ test06 緑。
- **条件5（キャンセルで責めない）**: `RevenueCatPlusServiceTests` の test06（`.userCancelled` → `alertMessage == nil`）/ test07（`.network` → `alertMessage` あり）緑。`RevenueCatPlusService.purchase(_:)` は `data.userCancelled` と `ErrorCode.purchaseCancelledError` の両方を `.userCancelled` にマップ（コードレビュー）。
- **条件6（オフライン起動で Plus 転落しない）— コード面は前進**: attempt 4 で `AppSession.refreshPlusEntitlement()`（起動経路 `start()` から呼ばれる本丸）に nil 保護が入った。`currentEntitlement()` が `nil` を返し、既存 `plusEntitlement` が `isActive(at: clock.now)` なら上書きしない。`isActive` が false（期限切れ）なら従来どおり `nil` に落とす。test11（既存 Plus + nil refresh → 温存）/ test12（未購入 + nil → Plus 状態を作らない）/ test13（期限切れ + nil → nil に戻る）/ test14（non-nil → 従来どおり更新）緑。eval-3 [3] は解消。
- **条件7（スプリント10の7条件維持）**: SprintTenAcceptanceTests 7/7 passed。
- **回帰**: ユニット 184/184、SprintEleven 4/4、SprintThirteen 4/4。抜き取り確認 = SprintTen test04（無料ユーザーのタイムライン能力）/ SprintEleven test03（アカウント削除→オンボーディング）/ SprintThirteen（サーバー側 BAN・連打制限）すべて緑。
- **クリーン起動の安定性**: iOS 26.4/26.5 で既定 RevenueCat 経路の起動→オンボーディング表示、クラッシュ・アプリコード側の未処理例外・システムダイアログなし。新規クラッシュレポート 0（`~/Library/Logs/DiagnosticReports` の最新 SameQ クラッシュは 2026-08-25、本評価中の増加なし）。

## 不合格の原因（これを直せば通る）

### [1] 受け入れ条件4「ダッシュボードに取引が現れる」を本評価環境で確認できない（eval-2 [1] / eval-3 [1] と同一・3回連続・未解消）
- **spec.md 該当条件（行361）**: 「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）」
- **再現手順**:
  1. 評価者は `https://app.revenuecat.com/` に認証手段がない（`WebFetch` は認証必須 URL を扱えない）。
  2. `.env.local` に RevenueCat の secret key（`sk_` / REST API v2 用）が無く、`curl` で当該 app_user_id の transactions を照会できない。
  3. 実機 + Sandbox Apple ID が無く `.storekit` 構成も無いため、シミュレータ単独で RevenueCat サーバーへ届く本物のサンドボックス購入を発火できない。
- **期待**: サンドボックス購入→復元を実施し、RevenueCat ダッシュボードの Customers / Transactions に実績が残ることを目視確認できる状態。
- **実際**: 一度も観測できていない。attempt 4 の変更（起動経路の nil 保護 + test11〜14）は条件4 の検証可能性を変えていない。generator も self-review「動かし方」節で条件4 を人間 evaluator 担当と明記している。
- **根拠**: self-review.md「動かし方」節、`.env.local`（secret key 不在）、`find . -name "*.storekit"` 0 件。

### [2] RevenueCat ダッシュボードに商品／Offering が未登録 — 実機でも条件2・3 が通らない見込み（eval-2 [2] / eval-3 [2] と同一・3回連続・未解消）
- **再現手順**: 既定（RevenueCatPlusService）で Debug ビルドを iOS 26.4/26.5 クリーン端末で起動し、`log show --predicate 'process == "SameQ"'` を観測。
- **期待**: `plus` エンタイトルメントに紐づく商品がダッシュボードに登録され、offerings / products が取得できる。
- **実際**: 毎起動、SDK が次を出力する:
  ```
  ERROR: 🍎‼️ Error fetching offerings - The operation couldn't be completed.
  (RevenueCat.OfferingsManager.Error error 1.)
  You have configured the SDK with an App Store API key, but there are no App Store
  products registered in the RevenueCat dashboard for your offerings.
  ```
- **影響**: `RevenueCatPlusService.purchase(_:)` は購入成立後に `CustomerInfo.entitlements["plus"]` を確認し、無ければ `PlusPurchaseError.other("Plus のエンタイトルメントが付与されませんでした")` を投げる。Product↔Entitlement(`plus`) の紐付けがダッシュボードに無い現状では、実機でサンドボックス購入しても `plus` が active にならず、**受け入れ条件2・3 も実機で失敗する**見込み。
- **根拠**: 上記ログ（本評価で2端末で再現）、`RevenueCatPlusService.swift` の entitlement 未付与ガード。

### [3] 受け入れ条件1「価格は App Store 側で設定した金額と一致する」が既定経路で観測できない
- **症状**: 既定 RevenueCat 経路では `Purchases.shared.products([...])` が空配列を返す（[2] のとおり商品未登録）。そのため `PlusView` は「料金を読み込み中です…」から進まず、実価格（¥480 等）が表示されるところを確認できない。SprintTen test02 が緑なのは FakePlus 経路（ダミー価格）での確認であり、出荷経路の価格一致は担保しない。
- **期待**: 既定経路で Plus 画面を開くと App Store Connect 設定額と同じ価格文字列が出る。
- **実際**: 商品未登録のため価格が出ない。[2] が解消すれば連動して確認可能になる見込み。
- **根拠**: `RevenueCatPlusService.availableProducts()`、起動ログ、`PlusView.swift`（商品ロード中の表示分岐）。

### [4] iOS 26.3 シミュレータでユニットテストがハングする（新規・非決定的テストの hermeticity 欠陥）
- **症状**: `xcodebuild test -only-testing:SameQTests` を iOS 26.3「iPhone 17」で実行すると、`RevenueCatPlusServiceTests.test03_RestoreThrowsTypedErrorWhenNoEntitlementExists` で停止し、以後 8〜10 分進捗ゼロ（`xcodebuild` は CPU 0%）。同テストは `RevenueCatPlusService.restore()` → `Purchases.shared.restorePurchases()` を実 SDK で呼ぶ。26.3 端末では `restorePurchases()` が「Apple Account にサインイン」システムモーダルを表示して無限待ちになる（スクショ `/tmp/sameq_launch_263.png`）。
- **再現手順**:
  1. iOS 26.3「iPhone 17」シミュレータを起動。
  2. `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,id=<26.3 UDID>' test -only-testing:SameQTests`
  3. `RevenueCatPlusServiceTests` の 3 本目（test03）で停止。ログ最終行が `test03 ... started` のまま更新されない。
  4. 2回実行して 2回とも再現。
- **期待**: ユニットテストはネットワーク／StoreKit の実挙動に依存せず、どの対応ランタイムでも数秒で完了する（test01・test02 は即完了している）。
- **実際**: `test03` 以降が実 SDK の `restorePurchases()` に依存しており、ランタイムによってはシステムモーダルでブロックする。iOS 26.5 では同テストが 0.02 秒で完了する（=環境依存で結果が変わる）。
- **根拠**: `/tmp/sameq_eval4_unit.log`（26.3・test03 started で停止、120 tests passed で打ち切り）、`/tmp/sameq_eval4_unit265.log`（26.5・184/184 in 6.8s）、`/tmp/sameq_launch_263.png`（サインインモーダル）、`RevenueCatPlusServiceTests.swift` の test03〜05、`RevenueCatPlusService.restore()`。
- **補足**: 出荷アプリ自体のクラッシュではない（クリーン起動は 26.3 以外でも 26.4 でも正常）。ただし CI／autoloop が 26.5 以外のランタイムに当たると評価が丸ごと固まるリスクがある。

## 改善提案（合否には影響しない）
1. **[中]** [4] のテスト群（test03〜05, および restore/purchase を実 SDK で叩く系）を `PlusServiceStub` 経由に寄せるか、`XCTSkipUnless` でランタイム／環境ガードを付ける。実 SDK の `restorePurchases()` はユニットテストで呼ばない。
2. **[中]** 既定経路で商品が取得できないときの `PlusView` に、一定時間後「Plus の商品情報を読み込めませんでした。時間をおいて再度お試しください」へ落とす導線（条件5 の精神・eval-3 提案2 の再掲）。
3. **[低]** 毎起動の `ERROR: 🍎‼️ Error fetching offerings` は商品登録前の暫定ログだが、リリースビルドでユーザーのデバイスコンソールに ERROR レベルで出続けるのは望ましくない。商品登録が済むまでは offerings 取得をスキップする、もしくはログレベルを下げる。
4. **[低]** autoloop のコミットメッセージが attempt 番号と 1 ずれている（`34dfe45` が "attempt=3" だが実体は attempt 4）。追跡性のため合わせる。

## 評価できなかったもの（差し戻しの中心・ユーザー作業が必須）
- 受け入れ条件1（価格が App Store 設定額と一致）: 商品未登録のため既定経路で価格が出ない → **[2] 解消後に実機で確認**
- 受け入れ条件2: サンドボックス購入でその場 Plus 化 + 140字超入力・装飾解放 → **実機・Sandbox Apple ID 必須・未検証**
- 受け入れ条件3: 削除→再インストール→復元（アプリ内・設定画面の両方） → **実機必須・未検証**
- 受け入れ条件4: 購入・復元がダッシュボードに取引として出る → **ダッシュボードアクセス + 実機必須・未検証**（spec は「確認できない実装は不合格」と明記）
- 受け入れ条件6: オフライン起動で既存 Plus ユーザーが無料転落しない → **コード + ユニットは前進（test11）。実機での機内モード起動での最終確認は未実施**

## ユーザー判断が必要（3 回連続で同じ所で止まっている）
autoloop の自動評価者（ブラウザ認証なし・実機なし・secret key なし）の環境では受け入れ条件1（価格）・2・3・4 を
原理的に検証できない。eval-2 / eval-3 と同じ状況。次のいずれかがないと合格判定を出せない:

- **(a)** ユーザーが手動で「App Store Connect にサブスク商品 `com.nakakei6439.SameQ.plus.monthly` を登録」→「RevenueCat ダッシュボードで Product ↔ Entitlement(`plus`) を紐付け」→「実機で Sandbox 購入・復元」→「ダッシュボードで Customers / Transactions を目視」まで行い、その結果（スクショ等）を eval / state.json に添付する運用へ切り替える。
- **(b)** `.env.local` に RevenueCat の secret key（`sk_`）を追加し、評価者が REST API v2 で当該 app_user_id の transactions を照会できるようにする（条件4 の一部を自動化）。加えて `.storekit` 構成ファイルを追加すれば条件2・3・1 をシミュレータで検証できる（ただし条件4 の「ダッシュボード」目的は (a) が要る）。
- **(c)** スプリント14 の受け入れ条件を autoloop で検証可能な形へ緩める（spec 変更。「ダッシュボードに実績が残る」がこの差し替えの目的そのものなので、緩めるとスプリントの意味が薄れる）。

いずれもユーザーの判断が要る。原因[2]（ダッシュボードに商品未登録）は条件1・2・3 の実機検証の前提として先に解消が必須。
なお generator は eval-3 [3]（起動経路の nil 保護）を今回で解消しており、コード側でやり残しているのは
[3]（条件1 の価格表示。ただし [2] 解消に依存）と [4]（テストの hermeticity）。
