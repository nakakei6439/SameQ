# スプリント 15: アプリ自身の文言を端末の言語で表示する (attempt 2)

## 受け入れ条件（spec.md から転記）
- [ ] 1. en 初回起動で全画面英語
- [ ] 2. en のまま各画面を一巡して和文が出ない
- [ ] 3. ja に戻すと日本語
- [ ] 4. fr など ja/en 以外は英語
- [ ] 5. 英語で見切れ無し
- [ ] 6. 06/07 不変
- [ ] 7. 端末言語切替で前の言語残らない

## attempt 1 の不合格理由（eval-1.md [1]）

Plus 画面「PRICE」直下の `Text(product.periodDescription)` が `PlusProduct.periodDescription` をそのまま描画しており、その値が3つの Service (`RevenueCatPlusService.swift:67` / `StoreKitPlusService.swift:34` / `FakePlusService.swift:81`) で日本語リテラル固定（L10n 未経由）。

→ **en/fr 端末でも「月額 / いつでも解約できます」が出てしまう**。受け入れ条件2・4 に違反。

## 実装方針（attempt 2）

eval-1 の提案どおり最小修正:

1. **`SameQ/L10n.swift`** の `L10n.Plus` に `priceMonthlyNote` を追加
   - `useEnglish ? "Monthly / Cancel anytime" : "月額 / いつでも解約できます"`

2. **`SameQ/Feature/Plus/PlusView.swift:159`** を
   - `Text(product.periodDescription)` → `Text(L10n.Plus.priceMonthlyNote)`

これで `periodDescription` の値はビューから参照されなくなるので、3つの Service の日本語リテラルは画面に出なくなる（リスク除去のみ、表示に影響しないので空文字化は不要）。

## 影響範囲

- Plus 画面の PRICE 直下1行のみ
- 既存の Sprint15 acceptance test06/test07（en/fr で全画面英語チェック）には影響なし（en で英語 "Monthly / Cancel anytime" / fr で英語 "Monthly / Cancel anytime" / ja で日本語 "月額 / いつでも解約できます" — いずれも `periodDescription` の文字列ではないので全 green を維持）

## スコープ外（今回やらない）

- 3 Service の `periodDescription` 文字列自体は **残す**（値はビューから消えるので画面に出ない）
- `displayName: "Plus （月額）"` の L10n 化（現状 PlusView で未使用、eval-1 の改善提案「小」の範囲 → 今回は触らない）
- 利用規約本文の多言語化（spec で対象外）
