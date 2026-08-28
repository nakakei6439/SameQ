# スプリント 14 attempt 7: 3-strike rule 発動 — blocked

## 結論

attempt 6 の eval-6.md を受け、**generator 側で実施可能な対応はすべて完了したと判断し、
status を `blocked` に変更**する。

`generator.md` の行動規範に「**同じ指摘で 3 回落ちたら止まる。** 自力で抜けられないので、
ユーザーに『何が起きていて、何を試して、何が分からないか』を報告して判断を仰ぐ」とある。
condition 4（サンドボックスでの購入・復元が運営側の課金ダッシュボードに取引として現れる）
に関する同一の差し戻しは **eval-2 / eval-3 / eval-4 / eval-4 / eval-6 の 5 回連続**で、
閾値を大きく超えた。

attempt 7（=blocked にする今回の判断）のもととなる generator コード:
- **`commit 123c443` (sprint14 attempt6: add Configuration.storekit for simulator purchase/restore verification)**
  - シミュレータ・StoreKit Testing 経路で条件 2・3 を回せるようにした。
  - **しかし条件 4 は StoreKit Testing では RevenueCat サーバに到達しないので、このコミットでは解消しない**
    （eval-6.md が明示:「attempt 6 で追加した `.storekit`（StoreKit Testing）はシミュレータ内で
    ローカル完結し、RevenueCat サーバーへレシートを送らないので、この経路をいくら回しても
    ダッシュボードには反映されない」）。
- 上流: attempt 4 / attempt 5 / attempt 6 で `PlusServiceStub` 注入経路（条件 5・6）と
  `AppSession.refreshPlusEntitlement()` の nil 保護（条件 6）、
  `Configuration.storekit` 追加（条件 2・3 の代替経路確保）までは実装済み。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が同一、価格は App Store 側と一致 | コード達成・出荷未観測 | `PlusView` / `PlusDecorationPicker` は 1 行も変更なし（条件 1 前半）。App Store Connect の商品価格は ¥480 / Monthly Plus で登録済み（条件 1 後半）。**実機 or StoreKit Testing 経路で画面表示を目視する手段が無い**ため、autoloop 環境では観測不能 |
| 2. サンドボックス購入でその場 Plus 化 | 経路追加済み・出荷未観測 | `Configuration.storekit` 追加によりシミュレータ StoreKit Testing で検証可能化（attempt 6）。**実機 + Sandbox Apple ID での実購入はその手段なし** |
| 3. 削除→復元で Plus 状態が戻る | 経路追加済み・出荷未観測 | 同上 |
| 4. ダッシュボードに取引が現れる | **未達・generator 環境で検証不能** | eval-6.md が REST API v2 (secret key + project `e444c0e4`) で customer 8 件の `subscriptions` / `purchases` / `active_entitlements` を照会し**取引 0 件を確認**。spec.md 行 361「この確認ができない実装は不合格とする」を満たすには実機 + Sandbox Apple ID が必須で、autoloop 環境には存在しない |
| 5. 購入キャンセル時に責めない | 達成 | attempt 3 の `RevenueCatPlusServiceTests.test06` で `restore/refresh` のモック経路を担保 |
| 6. 通信できない状態で起動しても Plus が転落しない | 達成 | attempt 4 の `AppSession.refreshPlusEntitlement()` nil 保護 + `test11〜14` |
| 7. スプリント10受け入れ条件7項目維持 | 達成 | SprintTenAcceptanceTests 7/7 緑 |

## blocked に至った経緯

generator の 5 回連続の need_fix / blocked はすべて **条件 4 が同一かつ autoloop 環境に閉じた問題**。

- **attempt 2 (needs_fix)**: RevenueCat SDK 導入 + 既定経路化。UI 側の土台は整ったが「ダッシュボード目視不可」を [1] として指摘。
- **attempt 3 (needs_fix)**: `PlusServiceStub` 注入経路で条件 5・6 をモック経由担保。同 [1] 継続。
- **attempt 4 (needs_fix)**: `AppSession.refreshPlusEntitlement()` に nil 保護追加。起動経路の防御を完成。**コード側の役割は完了**（evaluator も「generator 側のコードに明確なバグは見つかっていない」と明言）。
- **attempt 5 (user_action)** : ユーザーが (a)App Store Connect 175 か国展開 (b)Product/Offering/Entitlement 紐付け (c)secret key 提供 を実行 → 環境側のブロッカーは解消済み。
- **attempt 6 (needs_fix)**: `.storekit` 構成追加で StoreKit Testing 経路で条件 2・3 をシミュレータ検証可能化。**しかし条件 4 は StoreKit Testing だけでは RevenueCat に到達しないため依然未達**。evaluator が REST API v2 で取引 0 件を能動的に確認し「5 回連続で同一の差し戻し」と記述。

attempt 6 の self-review で挙げた「提案」3 件（A: PlusView に StoreKit Testing インジケータ、B: free trial 追加、C: RevenueCat 経路への .storekit フォールバック、D: autoloop attempt 番号補正）は
**条件 4 には寄与しない**ため実装しない。**D だけはユーザー手作業**。

## 動かし方（evaluator / ユーザー向け）

### A. 自動評価者で観測可能な範囲（再確認）

```bash
# 既定 RevenueCat 経路で起動
xcrun simctl install <SIM_ID> .../SameQ.app
xcrun simctl launch <SIM_ID> com.nakakei6439.SameQ
#   → 起動時の "ERROR: ... Error fetching offerings" が出ないこと
#   → オンボーディングが完走しクラッシュしないこと

# StoreKit Testing 経路で条件 2・3 のシミュレータ検証
xcrun simctl launch <SIM_ID> com.nakakei6439.SameQ -SameQUseStoreKitPlus
#   → Configuration.storekit のローカル商品が "¥480" で表示されること
#   → 購入ボタン押下 → StoreKit Testing シートで購入確定 → Plus 化すること

# REST API v2 で customer 取引照会（条件 4 の部分検証）
source .env.local   # REVENUECAT_SECRET_API_KEY が export される
curl -H "Authorization: Bearer $REVENUECAT_SECRET_API_KEY" \
  https://api.revenuecat.com/v2/projects/<project_id>/customers
#   → 実機で Sandbox 購入された app_user_id の取引が REST API 経由で照会可能
#   → ダッシュボードの目視は引き続き人間必須
```

### B. 条件 4 を満たすには（人間作業が必要）

以下のいずれかを **人間** が実施することで本スプリントの合格判定が可能になる:

1. **推奨**: ユーザーが実機（iPhone 17 Pro Max 等）+ Sandbox Apple ID で「Plus をサンドボックス購入 →
   アプリ削除 → 再インストール → 購入を復元」を実行し、RevenueCat ダッシュボードの
   Customers/Transactions に取引が出ることをスクショで記録（または購入後に evaluator が
   `curl .../v2/projects/e444c0e4/customers/<app_user_id>/subscriptions` を実行して取引を確認）。
   同時にその端末で条件 1（¥480 表示）・条件 2・条件 6（機内モード起動で Plus 維持）も目視する。
2. **条件緩和**: spec.md 受け入れ条件 4 の文言を「REST API v2 で取引照会できる」レベルまで
   緩める（本差し替えの主旨「ダッシュボードに実績が残る」が薄まるため、ユーザーの判断が必要）。

## 3-strike / 5-strike rule の確認

- **同一条件での差し戻し 5 回連続**: 条件 4 (eval-2 [1] / eval-3 [1] / eval-4 [1] / eval-4 [1] / eval-6 [1])
- generator.md の閾値「3 回」を超過
- 原因の大半は **autoloop 環境と外部サービス要件のミスマッチ**で、generator コードの改善余地は尽きている
- 残りは全て **人間ユーザー側の作業**（実機での購入・復元、または spec 緩和）

## 自分で見つけた弱点

1. **`.storekit` の `displayPrice: "480"` ハードコード**: シミュレータ/StoreKit Testing 限定なので本番には影響しないが、App Store Connect 側の実際の表示額を変更すると追随が必要。
2. **Release ビルドでは `.storekit` は無視される**: Xcode の挙動で、スキームに登録していても実機 Release では App Store Connect から本物の `Product` が解決される。意図通り。
3. **autoloop コミットメッセージと attempt 番号のズレ**: eval-4 の改善提案 D だが、autoloop.sh のスクリプト側の対応が必要で、本スプリントの範囲外。

## 提案（今回はやらなかったこと）

1. **`PlusService` の `.storekit` 経路を実機ビルドでも使えるようにする**:
   自動評価者には実機が無いため効果は限定的。ユーザーの要望があれば別スプリントで。
2. **`Configuration.storekit` に複数 Subscription Group / Free Trial を追加する**:
   本スプリントの差し替え主旨ではないので省略。

---

## 履歴（参考、attempt 7 = blocked のみ追加）

### attempt 7 (blocked, 本書)
- eval-6.md の条件 4 同一差し戻し 5 回連続を受け、generator.md の「3-strike rule」に従い blocked に遷移
- コード変更なし（attempt 6 の `.storekit` 追加が最終形）
- 次のアクションはユーザー判断待ち

### attempt 6 (needs_fix, 前回)
- `.storekit` 構成を新規追加（シミュレータでの条件 2・3 検証経路確保）
- `project.yml` に `ENABLE_STOREKIT_TESTING: YES` と `storeKitConfiguration` を追加
- 212 ユニット + 15 UI 回帰すべて緑、Debug/Release ビルド SUCCEEDED

### attempt 5 (user_action)
- ユーザー側で実施: App Store Connect 175 か国展開 / Product 登録 / secret key 提供

### attempt 4 (前回・needs_fix 解消)
- AppSession.refreshPlusEntitlement() に nil 保護を追加
- test11〜14 を新規追加して 184/184 ユニット + 15/15 UI 回帰すべて緑

### attempt 3 (needs_fix)
- PlusServiceStub.swift を新規作成して AppSession に注入可能に
- RevenueCatPlusServiceTests に test06〜10 を追加
- AppSession.restorePlus() に nil 保護を追加（条件6）
- 180/180 ユニット + 15/15 UI 回帰すべて緑

### attempt 2 (needs_fix)
- RevenueCat SDK を SPM 依存として導入（RevenueCat 5.87.0）
- RevenueCatPlusService.swift を新規作成
- AppSession 既定を RevenueCatPlusService に切替
- 175/175 ユニット + 15/15 UI 回帰すべて緑
- evaluator は [1] ダッシュボード目視不可・[2] ダッシュボード商品未登録 を新規指摘

### attempt 1 (blocked → user_action)
- 着手前調査でブロッカー3つ発見
- ユーザー判断で選択肢(A) 採用
