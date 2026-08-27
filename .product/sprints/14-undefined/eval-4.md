# スプリント 14 評価（attempt 4） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7 条件中、観測で確認できたのは 2（条件7・条件1の「見た目/導線が同一」部分）。条件5・6 はモック/ユニットテストで担保（実経路未観測）。**条件1（価格一致）・条件2・条件3・条件4 は出荷経路で未検証。条件4 は spec 行361 が「この確認ができない実装は不合格とする」と明記** | 100% | ✗ |
| 2 安定性 | iOS 26.5 クリーン端末で起動→オンボーディング到達、再起動も正常、新規クラッシュレポート0。ただし既定 RevenueCat 経路は**毎起動 `ERROR: 🍎‼️ Error fetching offerings` を1件出力**（本評価で2起動=2件） | クラッシュ0 / 未処理0 / 動線完走 | △ |
| 3 データ整合性 | FakePlus 経路の Plus 永続化は回帰なし（SprintTen test07・FakePlusService 永続化ユニット test10〜12 緑）。RevenueCat 経路の購入・復元・オフライン保持は実購入を発火できず検証不能 | 100% | ✗（評価不能） |
| 4 回帰 | ユニット 184/184（iOS 26.5・6.5秒）、UI SprintTen 7/7・SprintEleven 4/4・SprintThirteen 4/4 = 15/15（229.6秒・TEST SUCCEEDED） | 100% | ✓ |
| 5 使用性 | Plus 画面はスプリント14で1行も変更なし。オンボーディングは空状態・説明とも設計済み。既定経路で商品が取れないと「料金を読み込み中です…」から戻らない（既存挙動・本スプリントで悪化なし） | 3以上 | ✓（3） |

**総合: 不合格。** 基準1が 100% に届かない（特に受け入れ条件4）。基準3は評価不能。
eval-2 / eval-3 / 前回 eval-4 の中心的な差し戻し理由（[1] ダッシュボード目視不可・[2] ダッシュボードに商品未登録）が
**4回連続でそのまま残っている**。generator が今回対応した eval-3 [3]（起動経路の nil 保護）は解消を確認した。

## 検証環境
- マシン: macOS / Xcode（`xcrun` 経由）
- シミュレータ: iOS 26.5「iPhone 17」(35AAC789-1DF1-4C51-B14D-94A5084F6B26) — autoloop 既定と同じ
- コミット: `62d3330`（"SAFETY-NET commit before exit 5 (eval_exit=1, sprint=14, attempt=4)"）。`state.json` は attempt 4 / status `awaiting_eval`、`self-review.md` も attempt 4 の内容。作業ツリー clean。
- 実行時刻: 2026-08-27 20:13〜20:21 JST
- ユニット: `xcodebuild test -only-testing:SameQTests`（iOS 26.5, derivedData `/tmp/sameq_eval4b_dd`）→ **184/184 passed / TEST SUCCEEDED**（6.5s）。xcresult を解析し test06〜14（`RevenueCatPlusServiceTests`）も個別に Passed を確認。
- UI 回帰: `-only-testing` で SprintTen + SprintEleven + SprintThirteen（iOS 26.5）→ **15/15 passed / TEST SUCCEEDED**（229.6s、`/tmp/sameq_eval4b_ui.log`）
- ビルド: Debug `BUILD SUCCEEDED`（`/tmp/sameq_eval4b_dd`）
- 手動起動: 既定＝RevenueCatPlusService 経路（起動引数なし）を iOS 26.5 端末に install→launch→terminate→relaunch。オンボーディング1ページ目まで到達、クラッシュ・システムダイアログなし。スクショ `/tmp/sameq_eval4b_launch1.png` `/tmp/sameq_eval4b_relaunch.png`。`log stream --predicate 'process == "SameQ"'` を `/tmp/sameq_eval4b_applog.txt` に採取。
- 秘密情報: `.env.local` の `REVENUECAT_API_KEY` は公開 SDK キー（`appl_i…` / 32文字）のみ。secret key（`sk_`）無し。`find . -name "*.storekit"` は 0 件。
- 認証: `app.revenuecat.com` / `appstoreconnect.apple.com` への評価者からのログイン手段なし。実機 / Sandbox Apple ID なし。

## 観測できたこと（合格側の材料）
- **条件1（見た目・導線が同一 / 過剰実装なし）**: `git diff a5f786f..HEAD` の対象は `LaunchOptions.swift`(+12) / `RevenueCatPlusService.swift`(新規165行) / `AppSession.swift`(+48) / テスト2ファイル / ビルド設定（`project.yml`・`generate-secrets.sh`）のみ。**`PlusView.swift` と `PlusDecorationPicker.swift` はスプリント14で無変更**。文言・導線の増減なし。SprintTen test02（価格表示・ボタン）/ test06 緑。
- **条件5（キャンセルで責めない）**: `RevenueCatPlusServiceTests` の test06（`.userCancelled` → `alertMessage == nil` かつ `plusEntitlement` 不変）/ test07（`.network` → `alertMessage` あり）緑。`RevenueCatPlusService.purchase(_:)` は `data.userCancelled` と `ErrorCode.purchaseCancelledError` の両方を `.userCancelled` にマップ（コードレビュー）。
- **条件6（オフライン起動で Plus 転落しない）— コード面は前進**: attempt 4 で `AppSession.refreshPlusEntitlement()`（`start()` から呼ばれる起動経路の本丸）に nil 保護が入った。`git diff` で確認 —「`currentEntitlement()` が `nil` を返し、既存 `plusEntitlement` が `isActive(at: clock.now)` なら上書きしない。`isActive` が false（期限切れ）なら従来どおり `nil`」の3分岐。test11（既存 Plus を確立→スタブを nil に切替→再 refresh でも温存）/ test12（未購入 + nil → Plus を作らない）/ test13（期限切れ + nil → nil に戻る）/ test14（non-nil → 従来どおり更新）緑。test11 は同義反復ではなく、スタブの戻り値を実際に nil へ切り替えて温存を確認している。**eval-3 [3] は解消**。
- **条件7（スプリント10の7条件維持）**: SprintTenAcceptanceTests 7/7 passed。
- **回帰**: ユニット 184/184、SprintEleven 4/4、SprintThirteen 4/4。抜き取り3件 = SprintTen（Plus 未購入ユーザーのタイムライン能力に制限が無いこと）/ SprintEleven（アカウント削除→オンボーディング復帰・設定画面の復元ボタン）/ SprintThirteen（サーバー側 BAN・いいね/通報の連打制限）すべて緑。
- **クリーン起動の安定性**: iOS 26.5 で既定 RevenueCat 経路の起動→オンボーディング表示、クラッシュ・アプリコード側の未処理例外・システムダイアログなし。terminate→relaunch も同じ。新規クラッシュレポート 0（`~/Library/Logs/DiagnosticReports` の最新 SameQ クラッシュは 2026-08-25、本評価中の増加なし）。

## 不合格の原因（これを直せば通る）

### [1] 受け入れ条件4「ダッシュボードに取引が現れる」を本評価環境で確認できない（eval-2 [1] / eval-3 [1] / 前回 eval-4 [1] と同一・4回連続・未解消）
- **spec.md 該当条件（行361）**: 「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）」
- **再現手順**:
  1. 評価者は `https://app.revenuecat.com/` に認証手段がない（`WebFetch` は認証必須 URL を扱えない）。
  2. `.env.local` に RevenueCat の secret key（`sk_` / REST API v2 用）が無く、`curl` で当該 app_user_id の transactions を照会できない（あるのは公開 SDK キー `appl_i…` のみ）。
  3. 実機 + Sandbox Apple ID が無く `.storekit` 構成も無いため、シミュレータ単独で RevenueCat サーバーへ届く本物のサンドボックス購入を発火できない。
- **期待**: サンドボックス購入→復元を実施し、RevenueCat ダッシュボードの Customers / Transactions に実績が残ることを目視確認できる状態。
- **実際**: 一度も観測できていない。attempt 4 の変更（起動経路の nil 保護 + test11〜14）は条件4 の検証可能性を変えていない。generator も self-review「動かし方」節で条件4 を人間 evaluator 担当と明記している。
- **根拠**: self-review.md「動かし方」節、`.env.local`（`REVENUECAT_API_KEY` は `appl_` の公開キー）、`find . -name "*.storekit"` 0 件。

### [2] RevenueCat ダッシュボードに商品／Offering が未登録 — 実機でも条件1（価格）・2・3 が通らない見込み（eval-2 [2] / eval-3 [2] / 前回 eval-4 [2] と同一・4回連続・未解消）
- **再現手順**: 既定（RevenueCatPlusService）で Debug ビルドを iOS 26.5 クリーン端末で起動し、`log stream --predicate 'process == "SameQ"'` を観測。
- **期待**: `plus` エンタイトルメントに紐づく商品がダッシュボードに登録され、offerings / products が取得できる。
- **実際**: 毎起動、SDK が次を出力する（本評価で2起動=2件）:
  ```
  ERROR: 🍎‼️ Error fetching offerings - The operation couldn't be completed.
  (RevenueCat.OfferingsManager.Error error 1.)
  You have configured the SDK with an App Store API key, but there are no App Store
  products registered in the RevenueCat dashboard for your offerings.
  ```
- **影響**:
  - **条件1（価格一致）**: 既定経路で `Purchases.shared.products([...])` が空配列を返すため `PlusView` に App Store 設定額（¥480 等）が表示されず、一致を確認できない。SprintTen test02 が緑なのは FakePlus 経路（ダミー価格）での確認で、出荷経路の価格一致は担保しない。
  - **条件2・3**: `RevenueCatPlusService.purchase(_:)` は購入成立後に `CustomerInfo.entitlements["plus"]` を確認し、無ければ `PlusPurchaseError.other("Plus のエンタイトルメントが付与されませんでした")` を投げる。Product↔Entitlement(`plus`) の紐付けがダッシュボードに無い現状では、実機でサンドボックス購入しても `plus` が active にならず、条件2・3 も実機で失敗する見込み。
- **根拠**: 上記ログ（`/tmp/sameq_eval4b_applog.txt`）、`RevenueCatPlusService.swift` の entitlement 未付与ガード（91〜98行）。

### [3] 受け入れ条件2・3 が実機なしでは観測できない（環境制約・未解消）
- **症状**: サンドボックス購入でその場 Plus 化・140字超入力・装飾解放（条件2）、削除→再インストール→アプリ内復元／設定画面復元（条件3）を、実機・Sandbox Apple ID なしで発火できない。`.storekit` 構成も無いためシミュレータの StoreKit Testing でも代替できない。
- **期待**: 上記 [2] 解消後、実機で条件2・3 を通し、購入直後 Plus → 再起動後も Plus、復元が二重に走らない、を目視確認。
- **実際**: 未観測。条件5・6 のモックテスト（PlusServiceStub 経由）はあるが、実 SDK・実購入経路の end-to-end は一度も通していない。
- **根拠**: 環境（実機なし）、`find . -name "*.storekit"` 0 件、self-review「動かし方」節の人間手順。

## 改善提案（合否には影響しない）
1. **[中]** 既定経路で商品が取得できないときの `PlusView` に、一定時間後「Plus の商品情報を読み込めませんでした。時間をおいて再度お試しください」へ落とす導線（条件5 の精神・eval-3 提案2 の再掲）。現状は「料金を読み込み中です…」から戻らない。
2. **[低]** 毎起動の `ERROR: 🍎‼️ Error fetching offerings` は商品登録前の暫定ログだが、リリースビルドでユーザーのデバイスコンソールに ERROR レベルで出続けるのは望ましくない。商品登録が済むまでは offerings 取得をスキップする、もしくはログレベルを下げる。
3. **[低]** `RevenueCatPlusServiceTests` の一部（`restore()` / `purchase()` を実 SDK で叩く系。前回 eval-4 が iOS 26.3 で `test03` のハングを報告）を `PlusServiceStub` 経由へ寄せるか `XCTSkipUnless` で環境ガードを付ける。本評価は iOS 26.5 のみで実行し、26.3 は未再検証だが、CI/autoloop が別ランタイムに当たると評価が固まるリスクがある。
4. **[低]** autoloop のコミットメッセージが attempt 番号と 1 ずれている（`34dfe45` が "attempt=3" だが実体は attempt 4）。追跡性のため合わせる。

## 評価できなかったもの（差し戻しの中心・ユーザー作業が必須）
- 受け入れ条件1（価格が App Store 設定額と一致）: 商品未登録のため既定経路で価格が出ない → **[2] 解消後に実機で確認**
- 受け入れ条件2: サンドボックス購入でその場 Plus 化 + 140字超入力・装飾解放 → **実機・Sandbox Apple ID 必須・未検証**
- 受け入れ条件3: 削除→再インストール→復元（アプリ内・設定画面の両方） → **実機必須・未検証**
- 受け入れ条件4: 購入・復元がダッシュボードに取引として出る → **ダッシュボードアクセス + 実機必須・未検証**（spec は「確認できない実装は不合格」と明記）
- 受け入れ条件6: オフライン起動で既存 Plus ユーザーが無料転落しない → **コード + ユニットは前進（test11 緑）。実機での機内モード起動での最終確認は未実施**

## ユーザー判断が必要（4 回連続で同じ所で止まっている）
autoloop の自動評価者（ブラウザ認証なし・実機なし・secret key なし）の環境では受け入れ条件1（価格）・2・3・4 を
原理的に検証できない。eval-2 / eval-3 / 前回 eval-4 と同じ状況。次のいずれかがないと合格判定を出せない:

- **(a)** ユーザーが手動で「App Store Connect にサブスク商品 `com.nakakei6439.SameQ.plus.monthly` を登録」→「RevenueCat ダッシュボードで Product ↔ Entitlement(`plus`) を紐付け」→「実機で Sandbox 購入・復元」→「ダッシュボードで Customers / Transactions を目視」まで行い、その結果（スクショ等）を eval / state.json に添付する運用へ切り替える。
- **(b)** `.env.local` に RevenueCat の secret key（`sk_`）を追加し、評価者が REST API v2 で当該 app_user_id の transactions を照会できるようにする（条件4 の一部を自動化）。加えて `.storekit` 構成ファイルを追加すれば条件1・2・3 をシミュレータで検証できる（ただし条件4 の「ダッシュボード」目的は (a) が要る）。
- **(c)** スプリント14 の受け入れ条件を autoloop で検証可能な形へ緩める（spec 変更。「ダッシュボードに実績が残る」がこの差し替えの目的そのものなので、緩めるとスプリントの意味が薄れる）。

いずれもユーザーの判断が要る。原因[2]（ダッシュボードに商品未登録）は条件1・2・3 の実機検証の前提として先に解消が必須。
generator は eval-3 [3]（起動経路の nil 保護）を今回で解消しており、**コード側でのやり残しは無い**。
残っているのは全てユーザー側の課金基盤セットアップ作業と、autoloop 環境の検証手段の欠如。
