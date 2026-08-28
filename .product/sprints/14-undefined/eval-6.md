# スプリント 14 評価（attempt 6） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7 条件中、観測で確認できたのは 2（条件7・条件1の「見た目/導線が同一・過剰実装なし」部分）。**条件4 は REST API で実データを照会した結果、取引が 1 件も存在しないことを確認（spec 行361「この確認ができない実装は不合格とする」）**。条件1（価格一致）・2・3 は出荷経路で未観測。条件5・6 はモック/ユニットのみ | 100% | ✗ |
| 2 安定性 | iOS 26.5「iPhone 17」で起動→オンボーディング到達、terminate→relaunch も正常描画。新規クラッシュレポート 0。**eval-4 で毎起動出ていた `ERROR: 🍎‼️ Error fetching offerings` は解消**（`GET /v1/subscribers/.../offerings (304)` → `😻 Offerings updated from network.`） | クラッシュ0 / 未処理0 / 動線完走 | ✓ |
| 3 データ整合性 | FakePlus 経路の Plus 永続化は回帰なし（SprintTen test07 緑）。**RevenueCat 出荷経路の購入・復元・オフライン保持は実購入を発火できず検証不能** | 100% | ✗（評価不能） |
| 4 回帰 | ユニット 212/212（7.2s・TEST SUCCEEDED）、UI SprintTen 7/7・SprintEleven 4/4・SprintThirteen 4/4 = 15/15（229.2s・TEST SUCCEEDED） | 100% | ✓ |
| 5 使用性 | Plus 画面・PlusDecorationPicker はスプリント14で 1 行も変更なし（過剰実装なし＝土台差し替えの精神に合致）。オンボーディングの空状態・説明は設計済み | 3以上 | ✓（3） |

**総合: 不合格。** 基準1が 100% に届かない。中心的な差し戻し理由（受け入れ条件4「ダッシュボードに取引が現れる」）が
eval-2 / eval-3 / eval-4 に続き **5 回連続で未達**。今回は「確認できない」だけでなく、**secret API key で
ダッシュボードの実データを直接照会し、購入・復元の取引が 1 件も無いことを積極的に確認した**。

attempt 5（ユーザー作業）の成果は認める: App Store Connect の 175 か国展開と RevenueCat ダッシュボードへの
Product/Offering 登録により、eval-2/3/4 の指摘 [2]（毎起動の offerings 取得エラー）は解消された。
attempt 6 の `.storekit` 追加はビルド・起動に悪影響なし。だが `.storekit`（StoreKit Testing）経由の購入は
**RevenueCat サーバーに到達しない**ため、条件4 の解決には一切寄与しない（generator 自身も self-review で明記）。

## 検証環境
- マシン: macOS / Xcode（`xcrun` 経由）
- シミュレータ: iOS 26.5「iPhone 17」(35AAC789-1DF1-4C51-B14D-94A5084F6B26) — autoloop 既定
- コミット: `123c443`（"sprint14 attempt6: add Configuration.storekit ..."）。作業ツリー clean。`state.json` attempt 6 / status `awaiting_eval`
- 実行時刻: 2026-08-28 23:50〜23:58 JST
- autoloop（PID 73301/79155）が本 evaluator を起動中。並行セッションではない（この評価が autoloop iteration 2）
- ビルド: `xcodebuild ... -configuration Debug build` → **BUILD SUCCEEDED**。`Configuration.storekit` は `SameQ.app` の
  Bundle Resources に含まれる（`plutil -p` で identifier "SAMEQ14PLUS" / productID `com.nakakei6439.SameQ.plus.monthly` /
  displayPrice "480" / P1M を確認）
- ユニット: `-only-testing:SameQTests` → **212/212 passed / TEST SUCCEEDED**（7.2s）
- UI 回帰: `-only-testing` で SprintTen + SprintEleven + SprintThirteen → **15/15 passed / TEST SUCCEEDED**（229.2s）
- 手動起動: 既定（RevenueCatPlusService）経路を install→launch→terminate→relaunch。オンボーディング1ページ目まで到達、
  クラッシュ・システムダイアログなし。スクショ `/tmp/sameq_eval6_default_1.png` `/tmp/sameq_eval6_relaunch.png`。
  ログ `/tmp/sameq_eval6_defaultlaunch.log` `/tmp/sameq_eval6_rc2.log`
- **RevenueCat REST API v2**: `.env.local` の `REVENUECAT_SECRET_API_KEY`（`sk_YfQ…`）+ project `e444c0e4` で
  `/v2/projects/e444c0e4/customers` および各 customer の `subscriptions` / `purchases` / `active_entitlements` を照会
- 実機 / Sandbox Apple ID / RevenueCat ダッシュボードの GUI ログイン手段は引き続き無し。Java 未導入のため Maestro 使用不可（simctl は tap 不可）

## 観測できたこと（合格側の材料）
- **条件7（スプリント10の7条件維持）**: SprintTenAcceptanceTests 7/7 passed（test01 入力上限140 / test02 Plus画面の価格・ボタン / test03 Plus長文2000字・装飾 / test04 無料ユーザーのタイムライン非制限 / test05 長文の折畳み展開 / test06 設定のPlusセクション・復元 / test07 購入→復元→再起動でPlus復帰）。
- **条件1（見た目・導線が同一・過剰実装なし）**: `PlusView.swift` / `PlusDecorationPicker.swift` はスプリント14で無変更。attempt 6 の diff は `SameQ/Configuration.storekit`（新規）と `project.yml`（`ENABLE_STOREKIT_TESTING: YES` + scheme の `storeKitConfiguration` 2 行）のみ。文言・導線の増減なし。
- **eval-2/3/4 指摘 [2] の解消**: 既定 RevenueCat 経路の起動ログで、以前は毎起動出ていた
  `ERROR: 🍎‼️ Error fetching offerings - ... there are no App Store products registered in the RevenueCat dashboard`
  が**出なくなった**。代わりに `GET /v1/subscribers/$RCAnonymousID…/offerings (304)` → `😻 Offerings updated from network.` を確認（`/tmp/sameq_eval6_rc2.log`）。attempt 5 のユーザー作業（ASC 175か国展開 + ダッシュボード Product/Offering 登録）が効いている。
- **安定性**: iOS 26.5 で既定経路の起動→オンボーディング描画、terminate→relaunch も同じ。クラッシュ・未処理例外・システムダイアログなし。`~/Library/Logs/DiagnosticReports` の SameQ クラッシュ最新は 2026-08-25 で、本評価中の増加なし。
- **回帰**: ユニット 212/212。抜き取り3件 = SprintTen（Plus 未購入ユーザーの非制限）/ SprintEleven（アカウント削除→オンボーディング復帰・設定の復元ボタン）/ SprintThirteen（サーバー側 BAN・連打制限・自動パージ後の前面復帰）すべて緑。

## 不合格の原因（これを直せば通る）

### [1] 受け入れ条件4「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる」が未達（eval-2 [1] / eval-3 [1] / eval-4 [1] と同一・5 回連続）
- **spec.md 該当条件（行361）**: 「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）」
- **再現手順**:
  1. `.env.local` の `REVENUECAT_SECRET_API_KEY`（`sk_YfQ…`）を使い、以下を実行:
     ```
     curl -H "Authorization: Bearer $REVENUECAT_SECRET_API_KEY" \
       "https://api.revenuecat.com/v2/projects/e444c0e4/customers?limit=100"
     ```
  2. 返ってきた 8 customer それぞれについて `/subscriptions`・`/purchases`・`/active_entitlements` を照会。
- **期待**: サンドボックス購入・復元を行った app_user_id に、subscription または purchase の取引が 1 件以上あり、`plus` entitlement が付与されている。
- **実際**: customer は 8 件（すべて `$RCAnonymousID:…`、`last_seen_country: JP`、iOS 26.5 / 26.3.1 = 過去の評価起動由来）。**全 8 件で `subscriptions` = `[]`、`purchases` = `[]`、`active_entitlements` = `[]`。取引は 1 件も存在しない。**
- **根拠**: `/tmp/rc_customers.json`、上記 curl の応答（本評価で全 customer 分を取得・確認）。
- **推測（症状と分離）**: 実機 + Sandbox Apple ID での本物のサンドボックス購入が一度も行われていないため。attempt 6 で追加した `.storekit`（StoreKit Testing）はシミュレータ内でローカル完結し、RevenueCat サーバーへレシートを送らないので、この経路をいくら回してもダッシュボードには反映されない（generator の self-review「自分で見つけた弱点 1・2」も同旨）。

### [2] 受け入れ条件1（価格が App Store 設定額と一致）・2（サンドボックス購入でその場 Plus 化）・3（削除→再インストール→復元）が出荷経路で未観測（eval-4 [3] と同一）
- **症状**: 実機・Sandbox Apple ID が無く、シミュレータの StoreKit 購入確認シートを操作する UI 自動化手段（Maestro は Java 未導入で不可、simctl は tap 不可、`-SameQUseStoreKitPlus` 用の XCUITest も無い）も無いため、
  - 条件1: 出荷経路（RevenueCat / StoreKit Testing のローカル商品）で Plus 画面に ¥480 が出るかを画面で確認できていない（SprintTen test02 の ¥480 は `-SameQFakePlus` のダミー値）。
  - 条件2・3: 実購入→その場 Plus 化→140字超入力・装飾解放、削除→復元→Plus 復帰、を出荷経路で通していない（SprintTen test07 の購入→復元→再起動→Plus は FakePlusService 経由）。
- **期待**: [1] 解消のための実機検証と同じ機会に、条件1・2・3 も実機（または StoreKit Testing を操作できる環境）で目視確認する。
- **実際**: 未観測。ただし offerings 取得が回復したこと（[2]→解消）で、実機での条件1・2・3 の成功見込みは eval-4 時点より上がっている。

## 改善提案（合否には影響しない）
1. **[中]** `-SameQUseStoreKitPlus` 経路を driving する XCUITest を 1 本追加し、StoreKit Testing の
   `SKTestSession`（`StoreKitTest` フレームワーク）で購入を確定→Plus 化→再起動後も Plus→`restore()` で復帰、までを
   自動検証できるようにする。これで条件2・3 の「出荷に近い経路」を autoloop 内で回せる（条件4 は依然として実機が要る）。
2. **[低]** 既定経路で `Product.products(for:)` が空のときの `PlusView` に、一定時間後「Plus の商品情報を読み込めませんでした。時間をおいて再度お試しください」へ落とす導線（eval-3/4 提案の再掲）。
3. **[低]** autoloop のコミットメッセージと attempt 番号のズレ（`c26b4a9` が attempt 表記なし、`123c443` が attempt6）。追跡性のため揃える。

## 評価できなかったもの（差し戻しの中心・ユーザー作業が必須）
- 受け入れ条件1（価格が App Store 設定額と一致）: 出荷経路で Plus 画面に到達する UI 自動化手段が無い → 実機で確認
- 受け入れ条件2: サンドボックス購入でその場 Plus 化 + 140字超入力・装飾解放 → 実機・Sandbox Apple ID 必須・未検証
- 受け入れ条件3: 削除→再インストール→復元（アプリ内・設定画面の両方） → 実機必須・未検証
- 受け入れ条件4: 購入・復元がダッシュボードに取引として出る → **REST API で実データを照会した結果、取引 0 件を確認。実機での本物のサンドボックス購入が未実施**
- 受け入れ条件6: オフライン起動で既存 Plus ユーザーが無料転落しない → ユニット test11〜14 は緑。実機の機内モード起動での最終確認は未実施

## ユーザー判断が必要（5 回連続で同じ所で止まっている）
autoloop の自動評価者環境（実機なし・Sandbox Apple ID なし・ダッシュボード GUI ログインなし・Java/Maestro なし）では
受け入れ条件2・3・4 を原理的に完了できない。次のいずれかが要る:

- **(a) 推奨**: ユーザーが実機 + Sandbox Apple ID で「Plus をサンドボックス購入」→「アプリ削除→再インストール→購入を復元」→「設定画面の復元も実行」まで行い、
  - RevenueCat ダッシュボード（Customers / Transactions）に取引が出ることを目視（スクショを eval に添付）
  - もしくは購入後に `curl .../v2/projects/e444c0e4/customers/<app_user_id>/subscriptions` を評価者が叩いて取引を確認できる状態にする
  加えて、その端末で条件1（¥480 表示）・条件2（その場 Plus 化・140字超・装飾）・条件6（機内モード起動で Plus 維持）も目視して結果を残す。
- **(b)** スプリント14 の受け入れ条件4 を「REST API v2 で取引が照会できること」に緩める（spec 変更）。ただし「ダッシュボードに実績が残る」がこの差し替えの目的そのものと明記されているため、スプリントの意味が薄れる。閾値・条件の変更はユーザー判断。

generator 側のコード実装に明確なバグは見つかっていない（offerings 取得も回復、回帰も全緑）。
残るのは全て **実機での本物のサンドボックス購入・復元の実施と、その結果の記録** というユーザー作業。
