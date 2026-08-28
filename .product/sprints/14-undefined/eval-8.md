# スプリント 14 評価（attempt 8） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7/7。**条件4 を evaluator が RevenueCat REST API v2 で独立に確認（実サンドボックス取引が存在）**。条件1・2・3・6 は「土台差し替えで UI 無変更」＋自動テスト緑＋ユーザー実機検証＋条件4 と同一の課金経路が e2e で機能していることで確認。条件5・7 はテストで確認 | 100% | ✓ |
| 2 安定性 | iOS 26.x「iPhone 17」で既定（RevenueCat）経路を install→launch→terminate→relaunch、オンボーディング描画。新規クラッシュ 0（DiagnosticReports 最新は 8/25）。毎起動出ていた `ERROR: 🍎‼️ Error fetching offerings` は今回も出ず | クラッシュ0 / 未処理0 / 動線完走 | ✓ |
| 3 データ整合性 | REST API v2 で entitlement `plus` = active、subscription = active、3 つの匿名 app_user_id にまたがってエイリアスされ購入が保持されている（削除→再インストール→復元の痕跡）。SprintTen test07（購入→復元→再起動→Plus）緑。test08/11（restore/refresh の nil で既存 Plus を落とさない）緑 | 100% | ✓ |
| 4 回帰 | ユニット 212/212（7.3s・TEST SUCCEEDED）。UI 抜き取り SprintTen 7/7・SprintEleven 4/4・SprintThirteen 4/4 = 15/15（227s・TEST SUCCEEDED） | 100% | ✓ |
| 5 使用性 | Plus 画面・PlusDecorationPicker はスプリント14で 1 行も変更なし（土台差し替えの精神に合致・過剰実装なし）。オンボーディングの導入/空状態は設計済み。購入キャンセルで責めない（test06 緑）。設定に Plus セクション＋復元 | 3以上 | ✓（4） |

**総合: 合格。** eval-2 / eval-3 / eval-4 / eval-6 で 5 回連続の差し戻し理由だった
**受け入れ条件4（サンドボックスの購入・復元が運営側の課金ダッシュボードに取引として現れる）が、
今回 evaluator 自身の独立照会で確認できた**。eval-6 の時点では REST API v2 で全 customer の
subscriptions / purchases / entitlements が空＝取引 0 件だったが、attempt 8 でユーザーが実機
（iPhone 17 Pro Max / iOS 26.6）+ Sandbox Apple ID で購入・削除→再インストール→復元を実施した結果、
RevenueCat のプロジェクト `e444c0e4` に実データが記録されている。

## 検証環境
- マシン: macOS / Xcode（`xcrun` 経由）
- シミュレータ: iOS 26.x「iPhone 17」(35AAC789-1DF1-4C51-B14D-94A5084F6B26) — autoloop 既定・Booted
- コミット: `08e29f8`（"sprint14: 実機でのSandbox購入・復元をユーザーが検証、evaluatorへ引き渡し"）。作業ツリー clean。`state.json` attempt 8 / status `awaiting_eval`
- 実行時刻: 2026-08-29 05:19〜05:27 JST（= 2026-08-28 20:19〜20:27 UTC）
- autoloop（PID 80075）が本 evaluator を起動中。並行セッションではない
- ビルド: `xcodebuild build-for-testing -scheme SameQ -configuration Debug` → **TEST BUILD SUCCEEDED**。
  `SameQ.app` に `RevenueCat_RevenueCat.bundle` / `Configuration.storekit` が含まれる
- ユニット: `-only-testing:SameQTests` → **212/212 passed / TEST SUCCEEDED**（7.3s）
- UI 回帰: `SprintTenAcceptanceTests` + `SprintElevenAcceptanceTests` + `SprintThirteenAcceptanceTests`
  → **15/15 passed / TEST SUCCEEDED**（227s）
- 手動起動: 既定（RevenueCatPlusService）経路を uninstall→install→launch→terminate→relaunch。
  オンボーディング1ページ目まで描画、クラッシュ・システムダイアログなし。
  スクショ `/tmp/sameq_eval8_launch.png` `/tmp/sameq_eval8_relaunch.png`、
  ログ `/tmp/sameq_eval8_launch.log` `/tmp/sameq_eval8_syslog.txt`
- **RevenueCat REST API v2**: `.env.local` の `REVENUECAT_SECRET_API_KEY`（`sk_…`・Read only）+ project `e444c0e4`
  で `/customers`、`/customers/{id}/subscriptions`・`/purchases`・`/active_entitlements`・`/aliases` を照会

## 条件4 の独立確認（差し戻しの中心・今回で解消）

`GET /v2/projects/e444c0e4/customers/$RCAnonymousID:35a3fc02c6ea441b805bb29cc62f1c6e`
（＝ユーザーの申告した元購入者 app_user_id）を照会すると、エイリアス統合済みの customer
`$RCAnonymousID:4543de61fd754bd1be511107530cb025` が返り、その `subscriptions` に実取引が 1 件:

| 項目 | 値 |
|---|---|
| subscription id | `subAapb437aed73559eb9a20d23283de92923d` |
| environment | **sandbox** |
| store | **app_store** |
| status / gives_access | **active** / true |
| ownership | purchased |
| product_id | `prod35f1b37ab1`（= `com.nakakei6439.SameQ.plus.monthly`） |
| entitlement | `plus`（lookup_key `plus` / id `entlf2a97fe4c4` / state **active**） |
| store_subscription_identifier | `2000001228522808`（実 Apple 取引 ID・サンドボックス自動更新のたびに採番） |
| original_customer_id | `$RCAnonymousID:35a3fc02c6ea441b805bb29cc62f1c6e`（ユーザー申告と一致） |
| total_revenue_in_usd | gross 9.41 / proceeds 6.32（複数回の sandbox 更新分が累積） |
| starts_at / current_period_ends_at | 2026-08-28 20:06:41 UTC / 20:21:41 UTC（本評価の数分前・LIVE） |

- **購入が取引として現れている**: 上記 subscription（store=app_store・environment=sandbox）。
  StoreKit Testing 経由ならこのデータは生まれない（RC サーバに到達しないため）＝
  実機の RevenueCat SDK 経路で購入されたことの証拠。
- **復元が取引として現れている**: `/aliases` に 3 つの匿名 ID —
  `35a3fc02…`（元購入・created 20:02:20 UTC）→ `0a89dc69…`（20:12:35）→ `4543de61…`（20:13:32）。
  元購入より後に別の匿名 ID が同一 subscription にエイリアスされている＝
  レシートを新規インストール上で復元し RC が購入者へ紐付け直した痕跡（条件3 相当）。
- eval-6 で「全 customer で subscriptions/purchases/entitlements が空」だった状態から、
  取引が実在する状態へ変わったことを確認。**spec.md 行361 の「この確認ができない実装は不合格とする」
  を今回は満たす。**

## 各受け入れ条件

1. **Plus 画面の見た目・導線が同一、価格は App Store 側と一致** — ✓
   `PlusView.swift` / `PlusDecorationPicker.swift` はスプリント14 のコミット（`c26b4a9` / `123c443`）で
   1 行も変更なし（sprint 15 の L10n 化は別スプリントで評価済み）。文言・導線の増減なし＝過剰実装なし。
   SprintTen test02（価格・購入ボタン・復元ボタンの表示）緑、test06（設定の Plus セクション＋復元）緑。
   実機での金額目視はユーザー実施（ダッシュボードに `SameQ Plus (Monthly) … for JPY 500` の履歴）。
   evaluator 環境に実機/Sandbox Apple ID が無いため App Store の金額そのものは直接視認していない（後述）。
2. **サンドボックス購入でその場 Plus 化＋140字超・装飾解放** — ✓
   ユーザー実機で `[Environment: Sandbox]` 付き購入完了ダイアログ→Plus 化を確認。
   REST で entitlement `plus` = active。SprintTen test03（Plus の長文入力・装飾）緑（Fake 経路）。
3. **削除→再インストール→復元で Plus 復帰（アプリ内・設定の両方）** — ✓
   ユーザー実機で削除→再インストール後、復元ボタンを押す前から ✨Plus バッジ表示を確認。
   REST の 3 段エイリアスが復元の痕跡。SprintTen test07（購入→復元→再起動→Plus）緑、
   test06（設定画面の復元ボタン）緑。
4. **サンドボックスの購入・復元がダッシュボードに取引として現れる** — ✓（上記「条件4 の独立確認」）
5. **購入キャンセル時に責めない** — ✓ `RevenueCatPlusServiceTests` test06（キャンセル→alert なし）緑、
   test07（ネットワークエラー時のみ alert）緑。
6. **通信できない状態で起動しても Plus が転落しない** — ✓ test08/09/11/12/13/14 緑
   （restore/refresh が nil を返しても既存の有効 entitlement を落とさない・期限切れのみ nil に戻す）。
7. **スプリント10の受け入れ条件7項目維持** — ✓ SprintTenAcceptanceTests 7/7 緑
   （特に test04「Plus 未購入でもタイムライン閲覧・スワイプ・いいねが無制限」）。

## 安定性・回帰・データ整合性
- クラッシュ 0 / 未処理エラー 0。`~/Library/Logs/DiagnosticReports` の SameQ 最新は 2026-08-25 で本評価中の増加なし。
- 既定 RevenueCat 経路の起動ログに `Error fetching offerings` / `no App Store products registered` は無し（eval-6 での解消が継続）。
- ユニット 212/212、UI 抜き取り 15/15（Sprint10/11/13）すべて TEST SUCCEEDED。
- 課金状態の永続: REST で entitlement active、SprintTen test07（再起動後も Plus）緑。

## 改善提案（合否には影響しない）
1. **[中] `SameQ/Configuration.storekit` の `displayPrice: "480"` が実際の設定額（JPY 500）とズレている。**
   StoreKit Testing（`-SameQUseStoreKitPlus`）限定でエンドユーザーには届かないが、
   `-SameQUseStoreKitPlus` 経路の目視検証や将来の UI テストで誤った金額を見せる。App Store Connect の
   実額に合わせる。generator も self-review「弱点1」で認識済み。
2. **[中] 出荷経路（RevenueCat 実 SDK）で Plus 画面に到達し金額・購入・復元を通す XCUITest が無い。**
   eval-6 提案1 の再掲。`SKTestSession`（`StoreKitTest`）で購入確定→Plus→再起動→restore まで
   autoloop 内で自動化できると、条件1・2・3 を毎回テストで担保できる（条件4 は引き続き実機が要る）。
3. **[低] 既定経路で `Product.products(for:)` が空のときの `PlusView` フォールバック導線（時間経過で
   「商品情報を読み込めませんでした」へ）。今は offerings 取得が回復しているため実害なし。**
4. **[低] autoloop のコミットメッセージと attempt 番号のズレ（`c26b4a9` に attempt 表記なし）。**

## 評価できなかったもの（環境制約・合否は他手段で確認済み）
- 受け入れ条件1 の「App Store で設定した金額そのもの」の目視: evaluator 環境に実機・Sandbox Apple ID・
  App Store Connect GUI が無い。ユーザーが実機で購入フローを完走し、ダッシュボードに
  `SameQ Plus (Monthly) … for JPY 500` の履歴が残っていることまでは確認済み。
  UI 構造の不変（＝差し替え前と同じ見た目・導線）は git diff とテストで確認済み。
- 実機の機内モード起動で Plus 維持（条件6 の実機確認）: ユニット test11〜14 で担保。実機の最終目視は未実施。
- BAN / アカウント削除後の再作成 × Plus の組み合わせで他人の購入が引き継がれないか:
  RevenueCat は install ごとの匿名 app_user_id・レシート（Apple ID）ベースで、SprintEleven test03
  （削除→オンボーディング復帰）緑。本スプリントで新たな引き継ぎ経路は増えていないが、
  この組み合わせの実機シナリオは未実施。
