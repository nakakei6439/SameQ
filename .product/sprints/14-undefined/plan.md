# スプリント 14 attempt 4: 起動経路の nil 保護（条件6）と再評価

## 結論

eval-3 の **[3] 起動経路 `refreshPlusEntitlement()` の nil 保護欠落** に対応する。
[1]（ダッシュボード目視）と [2]（ダッシュボード商品未登録）はユーザー側ブロッカーのため、
generator では対応不可（spec が「確認できない実装は不合格」と明記）— 評価者判断に委ねる。

attempt 3 で `restorePlus()` に入れた保護と同じものを `refreshPlusEntitlement()` にも
適用し、起動経路（および Plus 画面を開いたとき・購入直後）で
「オフラインで `currentEntitlement()` が nil を返しても既存 Plus を落とさない」ことを
コードと自動テストの両方で担保する。

## 受け入れ条件（spec.md 行357〜364 から転記）
- [ ] Plus 画面に月額価格・提供内容・購入ボタン・購入復元が表示される（条件1）
- [ ] サンドボックス購入で Plus 化（条件2 — 実機必須）
- [ ] 削除→復元で Plus 状態が戻る（条件3 — 実機必須）
- [ ] ダッシュボードに取引が現れる（条件4 — ユーザー側ブロッカー）
- [ ] 購入キャンセル時に責めないダイアログ（条件5 — attempt 3 で自動担保済み）
- [ ] **通信できない状態で起動しても既存 Plus が無料転落しない（条件6）** ← **今回主軸**
- [ ] スプリント10の受け入れ条件7項目が維持される（条件7）

## 実装方針

### コード変更（最小・既存パターン踏襲）
- **`SameQ/Session/AppSession.swift` `refreshPlusEntitlement()`**:
  - `plusService.currentEntitlement()` の戻り値が `nil` で、
    既存 `plusEntitlement` が `isActive(at: clock.now)` のときは上書きしない。
  - `non-nil` のときは従来どおり最新の値で置き換える（購読期間更新を反映）。
  - attempt 3 の `restorePlus()` と同じコメントブロックで意図と eval-3 への対応理由を明記。

### テスト追加
- **`SameQTests/RevenueCatPlusServiceTests.swift` (追記)**:
  - `test11_AppSessionRefreshWithNilDoesNotDropExistingPlus`:
    `currentEntitlement()` が `nil` を返すスタブを AppSession に注入 →
    事前に `plusEntitlement` を `isActive` な値で埋める →
    `refreshPlusEntitlement()` 後も `plusEntitlement` が落ちないことを確認。
  - `test12_AppSessionRefreshWithNewEntitlementUpdatesPlusState`:
    `currentEntitlement()` が新しい entitlement を返すケースで
    `plusEntitlement` が置き換わることを確認（nil 保護の副作用なし）。

### 影響範囲
- 既存テストには影響なし（追加のみ）。
- 既存 SprintTenAcceptanceTests は FakePlus 経路で動くので変わらない。
- Release / Debug とも RevenueCat 経路が既定なので挙動は変わらない。
- 起動経路の挙動が変化: オフライン + 既存 Plus ユーザーが、ネットワーク不通で
  `currentEntitlement()` が nil を返す状況でも、Plus 状態を維持する（条件6）。

## ユーザー判断が必要なもの（self-review に明記）
1. **条件4**: RevenueCat ダッシュボードへの App Store 商品登録 + サンドボックス購入の目視 → 引き続き人間が評価するしかなく、generator だけでは検証不能（3回連続・eval-2/eval-3 と同一）。
2. **原因[2] ダッシュボード商品未登録**: ユーザー側で App Store Connect + RevenueCat ダッシュボードの登録が必要。generator 環境から到達不可。
3. **条件2・3の実機検証**: サンドボックス購入で plus エンタイトルメントが付与されるかは dashboard 設定完了後の実機でしか確認できない。

## 3-strike rule 確認
- eval-2 (needs_fix) → eval-3 (needs_fix) → **eval-4 で [3] を潰しきれなかった場合、stop**
- 今回 [3] は generator 側で完結するため、対応可能と判断

## 検証
- ユニット全件（180本 + 新規2本 = 182本）
- UI 回帰: SprintTenAcceptanceTests + SprintElevenAcceptanceTests + SprintThirteenAcceptanceTests
- ビルド: Debug / Release とも BUILD SUCCEEDED

## 仕様逸脱・過剰実装を避ける
- PlusView / PlusDecorationPicker は無変更（条件1 維持）。
- 既存の `FakePlusService` / `StoreKitPlusService` 経路も温存（escape hatch 維持）。
- PlusService プロトコルへの新メソッド追加なし（既存 `currentEntitlement()` の戻り値だけを見る）。
