# スプリント 14 評価（attempt 2） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 2/7 を観測で確認（条件1・7）。条件2・3・4・6 は出荷経路（RevenueCat）で未検証、条件5 はコード上のみ | 100% | ✗ |
| 2 安定性 | クラッシュ0 / アプリ内未処理エラー0 / 主要動線（FakePlus）完走。ただし起動時に RevenueCat SDK が ERROR ログを1件出す（ダッシュボードに商品未登録） | クラッシュ0 / 未処理0 / 動線完走 | △（クラッシュ面は可） |
| 3 データ整合性 | FakePlus 経路の Plus 永続化は回帰なし（SprintTen test07 緑）。RevenueCat 経路の永続化・オフライン保持は検証不能 | 100% | ✗（評価不能） |
| 4 回帰 | ユニット 175/175、SprintTen 7/7、SprintEleven 4/4 | 100% | ✓ |
| 5 使用性 | Plus 画面は差し替え前と同一（PlusView 無変更）。空/読み込み状態あり。ただし商品が取れないと「料金を読み込み中です…」から永久に戻らない（既存仕様） | 3以上 | ✓（3） |

**総合: 不合格。** 基準1が 100% に届かない（特に受け入れ条件4）。基準3が評価不能。

## 検証環境
- マシン: Xcode 26.6 (17F113) / iOS 26.5 Simulator
- 実行時刻: 2026-08-27 17:29〜17:36 JST
- コミット: `3af84f7`（sprint14 attempt2）。作業ツリー clean。
- ユニット: `xcodebuild test -scheme SameQ -only-testing:SameQTests`（iPhone 17）→ **175/175 passed / TEST SUCCEEDED**（6.7s）
- UI 回帰: `-only-testing:SameQUITests/SprintTenAcceptanceTests -only-testing:SameQUITests/SprintElevenAcceptanceTests`（iPhone 17）→ **11/11 passed / TEST SUCCEEDED**（215s）
- 手動起動: Debug ビルドを iPhone 17 Pro に install→launch（**既定＝RevenueCatPlusService 経路**、起動引数なし）。オンボーディング画面まで到達、クラッシュなし。スクショ `/tmp/sameq_default_screen.png`
- 秘密情報: `SameQ/Secrets.swift` は `.gitignore` 済み・未トラッキング。キーは公開 SDK キー（`appl_` 接頭辞）のみ。漏洩なし。

## 不合格の原因（これを直せば通る）

### [1] 受け入れ条件4「ダッシュボードに取引が現れる」を、この評価環境では確認できない
- **spec.md 行361**: 「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする**）」
- **再現手順**:
  1. 評価者（autoloop 上の Sonnet）は https://app.revenuecat.com/ に認証手段を持たない（`WebFetch` は認証必須 URL を扱えない、`.env.local` に RevenueCat の secret key（`sk_` / REST API v2 用）が無い）。
  2. 実機 + Sandbox Apple ID が無く、シミュレータ単独では RevenueCat サーバーへ到達する本物のサンドボックス購入を発火できない（`.storekit` 構成ファイルも無い）。
  3. よって「購入・復元がダッシュボードに取引として残る」ことを一度も観測できない。
- **期待**: サンドボックス購入→復元を実施し、RevenueCat ダッシュボードの Customers / Transactions に実績が残ることを目視で確認できる状態。generator の self-review はこの確認を「evaluator（人間）担当」に委譲しているが、autoloop の自動評価者はダッシュボードにも実機にもアクセスできないため、この委譲は成立しない。
- **実際**: 未検証。
- **根拠**: self-review.md 行9・19・136、plan.md 行27〜31。`curl` で公開キー（`appl_`）から叩けるのは `/v1/subscribers/{id}` の作成/取得のみ（HTTP 201 を確認）で、取引一覧やダッシュボード相当の情報は取得不能。

### [2] RevenueCat ダッシュボードに App Store 商品が未登録 — 実機でも条件2・3が通らない状態
- **再現手順**:
  1. 既定（RevenueCatPlusService）でアプリを起動。
  2. `xcrun simctl spawn "iPhone 17 Pro" log show --predicate 'process == "SameQ"'` を見る。
- **期待**: RevenueCat の設定が完了しており、`plus` エンタイトルメントに紐づく商品がダッシュボードに登録されている。
- **実際**: 起動直後に SDK が次の ERROR を出力する（全文）:
  ```
  ERROR: 🍎‼️ Error fetching offerings - The operation couldn't be completed.
  (RevenueCat.OfferingsManager.Error error 1.)
  You have configured the SDK with an App Store API key, but there are no App Store
  products registered in the RevenueCat dashboard for your offerings. If you don't
  want to use the offerings system, you can safely ignore this message.
  To configure offerings and their products, follow the instructions in
  https://rev.cat/how-to-configure-offerings.
  ```
- **影響**: `RevenueCatPlusService.purchase(_:)` は購入成立後に `CustomerInfo.entitlements["plus"]` を確認し、付いていなければ `PlusPurchaseError.other("Plus のエンタイトルメントが付与されませんでした")` を投げる実装（RevenueCatPlusService.swift 該当ブロック）。ダッシュボードで Product↔Entitlement(`plus`) の紐付けが無い現状では、実機でサンドボックス購入しても `plus` が active にならず、**受け入れ条件2（購入でその場で Plus 化）・条件3（復元で Plus 復帰）も実機で失敗する**見込み。
- **根拠**: 上記ログ（`/tmp/sameq_run_default.log` 相当・`log show` 出力）。RevenueCatPlusService.swift の entitlement 未付与ガード。

### [3] 出荷経路（RevenueCatPlusService）を通す自動テストが1本も無い
- **症状**: Plus 関連の UI テスト（SprintTenAcceptanceTests 7本、SprintElevenAcceptanceTests test05）はすべて `-SameQFakePlus`（FakePlusService）で動く。新規ユニット `RevenueCatPlusServiceTests` 5本は「初期化が落ちない」「配列を返す」「例外型が PlusPurchaseError」等の smoke check のみで、購入成立・エンタイトルメント反映・オフライン保持（条件6）・キャンセル抑制（条件5）といった振る舞いを1つも観測していない。
- **期待**: 少なくとも条件5（キャンセル時に alertMessage を立てない）・条件6（オフラインで `plusEntitlement` が nil に転落しない）を、RevenueCat 経路またはそれをモックした経路で観測するテスト。
- **実際**: `refreshPlusEntitlement()` は `plusService.currentEntitlement()` の戻り値をそのまま `plusEntitlement` に代入。RevenueCat 実装の `currentEntitlement()` は `try? await Purchases.shared.customerInfo()` で、失敗時は nil を返し `plusEntitlement = nil`（＝Plus 転落）になる。RevenueCat SDK のキャッシュが効けば nil にならないが、その保証を確認できるテスト・観測が無い。
- **根拠**: RevenueCatPlusService.swift `currentEntitlement()`、AppSession.swift `refreshPlusEntitlement()`、RevenueCatPlusServiceTests.swift 全体。

## 観測できたこと（合格側の材料）
- **受け入れ条件1（見た目・導線が同一）**: `PlusView.swift` / `PlusDecorationPicker.swift` は今回の diff に含まれず無変更。SprintTenAcceptanceTests `test02_plusViewShowsPriceAndButtons` / `test06` 緑。文言・導線の増減なし（過剰実装なし）。ただし「価格が App Store 設定額と一致」はシミュレータで商品が取れず未確認。
- **受け入れ条件7（スプリント10の7条件維持）**: SprintTenAcceptanceTests 7/7 passed。
- **回帰**: ユニット 175/175、SprintEleven（設定・アカウント削除・設定からの復元ボタン）4/4 passed。
- **安定性（クラッシュ）**: 既定の RevenueCat 経路でアプリ起動→オンボーディング表示、クラッシュ・アプリコード側の未処理例外なし。新規クラッシュログなし。
- Release ビルド構成の切替は `#if DEBUG` 内（LaunchOptions.parse 全体が DEBUG ガード）なので、Release では常に `RevenueCatPlusService`。escape hatch（`-SameQUseStoreKitPlus` / `-SameQFakePlus`）は Debug のみ。

## 改善提案（合否には影響しないが対応推奨）
1. **[中] `ENABLE_USER_SCRIPT_SANDBOXING: NO` が project の `settings.base`** に置かれ全ターゲットに効いている。GenerateSecrets スクリプトのためだけなら SameQ ターゲット限定にするか、スクリプトの入力を `.env.local` 固定パスにして sandbox 例外（`inputFiles` 指定）で通せないか検討。
2. **[中] 商品が取得できないときの Plus 画面が「料金を読み込み中です…」から永久に戻らない**（既存挙動）。RevenueCat 経路は実機の App Store 状態次第で頻繁にこの状態になりうるので、一定時間後に「Plus の商品情報を読み込めませんでした。時間をおいて再度お試しください」へ落とす導線があると条件5の精神に沿う。
3. **[低] `RevenueCatPlusServiceTests` を「落ちない」確認から一歩進め**、`PlusService` をモックした AppSession レベルで条件5（キャンセル→alert 無し）・条件6（オフライン→Plus 維持）を観測するテストを追加。

## 評価できなかったもの（差し戻しの中心）
- 受け入れ条件2: サンドボックス購入でその場 Plus 化 → **実機必須・未検証**
- 受け入れ条件3: 削除→再インストール→復元（アプリ内・設定画面の両方） → **実機必須・未検証**
- 受け入れ条件4: 購入・復元がダッシュボードに取引として出る → **ダッシュボードアクセス＋実機必須・未検証**（spec は「確認できない実装は不合格」と明記）
- 受け入れ条件5: 購入キャンセルで責めるダイアログを出さない（RevenueCat 経路） → コード上はマップ済みだが実挙動は未観測
- 受け入れ条件6: オフライン起動で既存 Plus ユーザーが無料転落しない → **未観測**（RevenueCat SDK キャッシュ依存、テストなし）

### 差し戻しにあたっての注記
本スプリントは、自動評価者（ブラウザ認証なし・実機なし）の環境では受け入れ条件4を原理的に検証できない。
generator の「条件4は人間の evaluator が担当」という前提が autoloop では満たせないため、
次のいずれかがないと合格判定は出せない:
- (a) ユーザーが手動で実機サンドボックス購入＋RevenueCat ダッシュボード目視を行い、その結果を state.json / eval に添付する運用に切り替える、または
- (b) `.env.local` に RevenueCat の secret key を追加し、評価者が REST API v2 で当該 app_user_id の transactions を照会できるようにする、または
- (c) スプリント14 の受け入れ条件4を、autoloop で検証可能な形（例: SDK モックでサーバー POST が発火することの確認）に緩める。

いずれもユーザー判断が必要。あわせて原因[2]（RevenueCat ダッシュボードに商品未登録）は実機検証の前に解消が必要。
