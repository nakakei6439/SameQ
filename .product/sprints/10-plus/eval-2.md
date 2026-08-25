# スプリント 10 評価（attempt 2） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 7/7 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線が最後まで通る | 0 | ✓ |
| 3 データ整合性 | Plus エンタイトルメントが `UserDefaults` に永続化され、再起動・復元後も一致 | 100% | ✓ |
| 4 回帰 | 19/19（Sprint01/04/09 抜き取り） | 100% | ✓ |
| 5 使用性 | 4 | 3以上 | ✓ |

**全基準が閾値を満たしたため、スプリント10 attempt 2 を合格とする。**

## 検証環境
- `xcodebuild`（`SameQ.xcodeproj` / scheme `SameQ`）、iPhone 17 Pro シミュレータ（UDID `07C68712-95E0-4180-87E8-360963E3B391`）
- 起動引数: `-SameQFakePlus`（Debug 用 Fake StoreKit）、`-SameQResetState`、`-SameQScenario live`
- 検証時刻: 2026-08-25 22:07〜22:28 JST
- 自動テスト（generator 提供）に加え、evaluator 独自の一時テストを2本追加して実行後に削除（`EvalTenReadMoreTests.swift` / `EvalTenScreenshotTests.swift`。最終的に `git status` はクリーン）

## 受け入れ条件ごとの確認内容（実際に動かした結果）

1. **140文字制限・カウンタ・入力停止**: `SprintTenAcceptanceTests.test01` を実行し合格。150文字入力→カウンタが `140/140` で停止することを自動UIテストで確認。
2. **Plus画面の価格・提供内容・購入・復元**: `test02` 合格に加え、evaluator が別途スクリーンショットを取得し目視確認。`¥480/月額`、長文投稿・Plus限定スタンプ・文字装飾・吹き出し装飾の4項目、「Plus に登録する」ボタンを確認。
3. **購入後の長文入力・装飾選択**: `test03` 合格（200文字入力・カウンタ `200/2,000`・装飾ピッカー表示）。
4. **長文の折り畳みと「続きを読む」展開**: 同梱シードデータには140文字超の投稿が無かったため（`SameQ/Resources/SeedData.json` 全45件の本文最大長は115文字）、evaluator が一時的に1件の本文を147文字へ書き換えて再ビルドし、独自の一時UIテスト（`EvalTenReadMoreTests`）で確認：無料ユーザーのタイムラインでその投稿が140文字に折り畳まれ「…続き」ボタンが表示され、タップすると147文字全文が展開し「閉じる」に変わることを確認した。確認後、シードデータは `git diff` が空になることを確認しつつ完全に元へ戻した。
5. **無料ユーザーでも他人の長文を全文読める（閲覧に課金制限なし）**: 上記と同じテストで、テスト実行中のアプリは終始「無料ユーザー」（`-SameQFakePlus` のみ、Plus未購入）のまま展開できることを確認。折り畳み判定コード（`AnswerCardView.isLongForm`）は `session.isPlus` を一切参照しないことをソースでも確認済み。
6. **アプリ再起動後も「購入を復元」でPlus状態が戻る（attempt1で不合格だった条件）**: eval-1.md の再現手順をそのまま自動化した `test07_purchaseThenRestoreAfterRelaunch_returnsPlusState` を実行し合格（35秒）。加えて evaluator が独自に `UserDefaults` の実ファイル（`.../Library/Preferences/com.nakakei6439.SameQ.plist`）を直接開き、`FakePlusService.lastEntitlement.v1` キーに実際の JSON（`purchasedAt` / `expiresAt` / `productID`）が書き込まれていることをバイナリレベルで確認した。attempt1で報告した不具合は解消している。
7. **Plus未購入でも回答・タイムライン閲覧・スワイプ・いいねが無制限**: `test04` 合格（いいね押下→ボタン残存、スワイプ→カード切替を確認）。

## 動作の安定性・データ整合性の補足
- ビルド（Debug/iphonesimulator）は問題なく成功。
- ユニットテスト `SameQTests` 147/147 成功（回帰含む）。
- UIテスト `SprintTenAcceptanceTests` 7/7 成功。
- クラッシュ・アプリ強制終了は確認作業全体を通じて一度も発生しなかった。
- Plus購入状態は `UserDefaults` への永続化により、アプリ終了→再起動→「購入を復元」の一連を経ても正しく一致することを自動テストとディスク直接確認の両方で確認した。

## 回帰確認（3件超の抜き取り）
| スプリント | テストスイート | 結果 |
|---|---|---|
| 01 コア体験 | `SprintOneAcceptanceTests` | 5/5 pass |
| 04 通報とブロック | `SprintFourAcceptanceTests` | 7/7 pass |
| 09 （直近スプリント） | `SprintNineAcceptanceTests` | 7/7 pass |

3スイート合計 19/19 全件成功（1回のテスト実行にまとめて実行、失敗0件）。

## 使用性の評価（5点満点で4点）
- Plus画面：見出し・提供内容4項目・料金・CTAの構成が明快で、迷わず購入導線に進める。
- 設定画面：「Plus を使うと、もっと書ける」の案内文とともに「Plus を見る」「購入を復元」がスクロール不要で画面内に収まっており、attempt1のマイナー指摘（要スクロール）は実質解消していた。
- 「ブロックしている人はいません」の空状態は説明文つきで意図を持って設計されている。
- 主要動線（オンボーディング→回答→タイムライン→Plus購入→再起動→復元）を一貫して完走でき、迷う瞬間は無かった。

## 評価できなかったもの
- 実際のStoreKit（Apple ID Sandboxアカウント経由）での購入・復元は、この評価環境にSandboxテスターのサインインが無く引き続き未検証（attempt1から変わらない制約）。`FakePlusService`永続化はDebug限定の経路であり、`StoreKitPlusService`（Release）はOS側の`Transaction.currentEntitlements`に依存する別実装のため、この部分は別途Sandbox環境での検証が必要。
- 本スプリントのタイトルは「Plus（RevenueCatによる課金）」だが、実装はRevenueCat SDKではなくStoreKit 2を直接使用している（`plan.md`に明記のうえでの設計判断）。受け入れ条件7項目はいずれも技術選定に依存しない振る舞いベースの記述であり、全て満たされているため合否には影響しない。将来RevenueCatへの移行が必要であれば別途検討事項として残る（合否に影響しないため改善提案とする）。

## 改善提案（合否には影響しない）
1. 同梱シードデータ（`SameQ/Resources/SeedData.json`）に140文字を超える投稿を最低1件含めておくと、「続きを読む」の折り畳み・展開が標準状態でも目視・自動テストの両方で確認しやすくなる（attempt1・attempt2とも evaluator が一時的にシードデータを書き換える対応を取った）。
2. `SprintTenAcceptanceTests.test05_longPostIsCollapsedAndExpandable` は実装コメントで「今回の自動テスト範囲では省略する」と明記されているとおり、実質的に折り畳み・展開そのものは検証していない。改善案1（シードデータに長文を1件追加）とあわせて、`test05`を実際に`timeline.card.toggleReadMore`をタップして展開を確認するテストへ強化すると、次回以降は evaluator の一時テスト無しで自動回帰できる。
3. Sandboxアカウントが用意できる環境がいずれ確保できたら、`StoreKitPlusService`側の実地購入・復元も一度は確認しておきたい（P0ではないが、リリース前には必要）。
