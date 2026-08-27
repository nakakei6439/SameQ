# スプリント 14 attempt 3: 条件5・6の自動検証整備

## 受け入れ条件（spec.md 行357〜364 から転記）
- [ ] Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示され、価格は App Store 側で設定した金額と一致する（差し替え前と同じ見た目・同じ導線であること）
- [ ] サンドボックスで購入を完了すると、その場で Plus 状態になり、140文字を超える入力と Plus 限定の絵文字・装飾が使えるようになる
- [ ] 購入した端末でアプリを削除して入れ直し「購入を復元」をすると Plus 状態が戻る。設定画面の復元からも同じ結果になる
- [ ] サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる（**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが今回の差し替えの目的そのもの**）
- [ ] 購入をキャンセルした場合、失敗を責めるようなダイアログを出さず、Plus 未購入のまま画面が操作可能な状態に戻る
- [ ] 通信できない状態で起動しても、すでに Plus のユーザーが無料状態に転落せず、長文入力と装飾が使えるままになる
- [ ] スプリント10の受け入れ条件7項目がすべて維持される

## eval-2 指摘の分解
- [1] 条件4（ダッシュボード目視）は autoloop では原理的に検証不能 → ユーザー判断案件。spec が「確認できない実装は不合格」と明記しているため、generator だけでは解決できない。
- [2] RevenueCat ダッシュボードに App Store 商品未登録 → ユーザー側作業（App Store Connect + RevenueCat ダッシュボード）。
- [3] 条件5（キャンセル）・条件6（オフライン）の RevenueCat 経路テストが皆無 → **generator 側で完結する**.

## attempt 3 の作業範囲
eval-2 指摘 [3] への対応に集中。条件5 と 条件6 を SDK モック経路で自動検証できるようにする。

### コード変更（最小）
- **`SameQ/Session/AppSession.swift` `restorePlus()`**: `plusService.restore()` が `nil` を返したときに既存の `plusEntitlement` を上書きしないように修正（条件6 保護）。これで「Plus ユーザーがオフライン時に誤って復元ボタンを押しても無料状態に転落しない」ことを保証する。
  - `plusEntitlement != nil && result == nil` のケースで `plusEntitlement` を保持し、戻り値だけ false を返す。

### テスト追加
- **`SameQTests/PlusServiceStub.swift` (新規)**: `PlusService` を満たすテスト用スタブ。`currentEntitlement` / `availableProducts` / `purchase` / `restore` の戻り値を注入できる。
- **`SameQTests/RevenueCatPlusServiceTests.swift` (追記)**:
  - `test06_AppSessionPurchaseCancellationDoesNotRaiseAlert`: `purchase(_:)` が `.userCancelled` を投げるスタブを AppSession に注入 → `purchasePlus()` を呼ぶ → `alertMessage == nil` を確認（条件5）。
  - `test07_AppSessionRestoreWithNilDoesNotDropExistingPlus`: `restore()` が nil を返すスタブ → 既存の plusEntitlement を持つ AppSession で `restorePlus()` → plusEntitlement が nil にならないことを確認（条件6）。

### 影響範囲
- 既存テストには影響なし（追加のみ）。
- 既存 SprintTenAcceptanceTests は FakePlus 経路で動くので変わらない。
- Release / Debug とも RevenueCat 経路が既定なので挙動は変わらない。

### 検証
- ユニット全件（180本 = 既存175 + 新規2本 + 既存条件変更確認）
- UI 回帰: SprintTenAcceptanceTests + SprintElevenAcceptanceTests + SprintThirteenAcceptanceTests
- ビルド: Debug / Release とも BUILD SUCCEEDED

## ユーザー判断が必要なもの（self-review に明記）
1. **条件4**: RevenueCat ダッシュボードへの App Store 商品登録 + サンドボックス購入の目視 → 引き続き人間が評価するしかなく、generator だけでは検証不能。self-review.md に詳しい手順を残す。
2. **条件2・3の実機検証**: サンドボックス購入で plus エンタイトルメントが付与されるかは dashboard 設定完了後の実機でしか確認できない。

## 仕様逸脱・過剰実装を避ける
- PlusView / PlusDecorationPicker は無変更（条件1 維持）。
- 既存の `FakePlusService` / `StoreKitPlusService` 経路も温存（escape hatch 維持）。