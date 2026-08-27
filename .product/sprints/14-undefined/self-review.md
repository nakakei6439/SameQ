# スプリント 14 attempt 5: 3-strike rule 発動・blocked

## 結論

**3-strike rule 発動。autoloop を停止し、ユーザーの判断を仰ぐ。**

eval-2 → eval-3 → eval-4(前回) → eval-4(今回) と、4 回連続で同一の差し戻し
[1]「RevenueCat ダッシュボード目視不可」・[2]「ダッシュボードに商品未登録」
を受けた。evaluator 自身が eval-4.md 最終行で
「generator は eval-3 [3] を今回で解消しており、**コード側でのやり残しは無い**。
残っているのは全てユーザー側の課金基盤セットアップ作業と、autoloop 環境の検証手段の欠如」
と明示しており、generator 側では原理的に突破できない。

**コード変更ゼロ**（作業ツリー clean・前回 attempt 4 の `62d3330` を温存）。
spec 行361「サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として
現れる（**この確認ができない実装は不合格とする**）」が、autoloop 環境
（実機 / Sandbox Apple ID / `.storekit` 構成 / RevenueCat ダッシュボード認証 /
secret key のいずれも不在）と相いれないため。

status を `blocked` に更新し、autoloop の `case blocked` 分岐（exit 2）に
乗せて停止させる。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. Plus 画面の見た目・導線が同一 | 達成 | `PlusView` / `PlusDecorationPicker` は attempt 4 以降無変更。SprintTenAcceptanceTests test02/test06 緑 |
| 2. サンドボックス購入で Plus 状態が有効化 | 達成(コード) | `purchase(_:)` → `Purchases.purchase(product:)` 経路を維持。実機 Sandbox 購入はユーザー側検証（商品未登録のため現状未達） |
| 3. 削除→復元で Plus 状態が戻る | 達成(コード) | `restore()` → `Purchases.restorePurchases()` 経路を維持 |
| 4. ダッシュボードに取引が現れる | **3-strike・未達** | spec 仕様上「確認できない実装は不合格」と明記。autoloop 環境から原理的に検証不能 |
| 5. 購入キャンセル時に責めない | 達成(テスト) | attempt 3 の test06 で `PlusServiceStub.purchase(.failure(.userCancelled))` を担保済み |
| 6. 通信できない状態で起動しても Plus が転落しない | 達成(コード+テスト) | attempt 4 で `AppSession.refreshPlusEntitlement()` に nil 保護を追加、test11〜14 緑 |
| 7. スプリント10の受け入れ条件7項目維持 | 達成 | SprintTenAcceptanceTests 7/7 緑 |

## 3-strike rule の根拠

### 同一指摘の連続回数

- eval-2.md (attempt 2): [1] ダッシュボード目視不可 / [2] ダッシュボード商品未登録
- eval-3.md (attempt 3): [1] ダッシュボード目視不可 / [2] ダッシュボード商品未登録
- eval-4.md (前回・attempt 4): [1] ダッシュボード目視不可 / [2] ダッシュボード商品未登録 / [3] 起動経路の nil 保護欠落
- eval-4.md (今回・attempt 4 再評価): [1] ダッシュボード目視不可 / [2] ダッシュボード商品未登録 / [3] **解消確認**

→ [1] と [2] が **4 回連続で同指摘**。3-strike rule（generator.md 5 項）に
従い generator 作業を停止する。

### eval-4.md の最終行（generator 続行不可の宣言）

> generator は eval-3 [3]（起動経路の nil 保護）を今回で解消しており、
> **コード側でのやり残しは無い**。残っているのは全てユーザー側の課金基盤
> セットアップ作業と、autoloop 環境の検証手段の欠如。

### spec.md 行361（要件の絶対性）

> サンドボックスでの購入と復元が、運営側の課金ダッシュボードに取引として現れる
> （**この確認ができない実装は不合格とする。ダッシュボードに実績が残ることが
> 今回の差し替えの目的そのもの**）

`不合格` という単語が要件として明記されているため、条件4 を「未検証 = 棄却」
以外の形で扱うことは spec の読み替えになる。

### autoloop 環境の制約（解決不能）

| 必要なもの | autoloop の有無 | 取得元 |
|---|---|---|
| 実機 | なし | ユーザー |
| Sandbox Apple ID | なし | ユーザー（App Store Connect → Users and Access → Sandbox Testers） |
| `.storekit` 構成 | 0 件（`find . -name "*.storekit"` 確認済み） | ユーザーまたは generator（実装可能だが condition 4 は救えない） |
| RevenueCat ダッシュボード認証 | なし | ユーザー |
| RevenueCat secret key (`sk_`) | なし（公開キー `appl_` のみ） | ユーザー |
| App Store Connect 商品登録 | なし | ユーザー |
| RevenueCat ダッシュボード Product↔Entitlement 紐付け | なし | ユーザー |

## generator で可能な追加施策とその限界

### A. `.storekit` 構成の追加（条件2・3 をシミュレータで担保する案）
- **メリット**: simulator の StoreKit Testing で条件2・3（購入・復元）を検証可能になる
- **デメリット**: condition 4 は RevenueCat ダッシュボードへの実績送信が必要で、
  StoreKit Testing 経由の「擬似購入」では RevenueCat ダッシュボードに取引が
  残らない → **condition 4 は依然として検証不能**
- **判断**: condition 4 が突破不能なら .storekit 追加も合格への到達は不確実。
  ユーザー判断に委ねる

### B. Plus 画面の「料金を読み込み中です…」にタイムアウト導線（評価者提案1）
- **メリット**: 既定経路で商品が取得できないときの UX 改善
- **デメリット**: spec には無い（Plus 画面の UI 改修）。condition 4 とは無関係
- **判断**: スプリント範囲外（条件1 維持の制約も考慮）

### C. 起動時の `ERROR: Error fetching offerings` ログを抑制（評価者提案2）
- **メリット**: リリースビルドのユーザーログが ERROR レベルで汚れない
- **デメリット**: condition 4 とは無関係。根本原因（商品未登録）は解消されない
- **判断**: スプリント範囲外

## 動かし方（evaluator / ユーザー向け）

### autoloop の状態
- status: `blocked`
- attempt: 5
- autoloop は次の iteration で `case blocked` 分岐に入り exit 2 で停止する
- 手動で停止する場合は `pkill -f autoloop.sh`

### ユーザー判断が必要な選択肢

**(a)** **App Store Connect + RevenueCat ダッシュボードの商品登録を済ませ、
人間が実機 Sandbox 購入 → ダッシュボード目視で検証する運用へ切り替える**
- 条件: App Store Connect で Subscription Group + 商品 `com.nakakei6439.SameQ.plus.monthly` 登録、
  RevenueCat ダッシュボードで `Products` タブに同 Product を追加、
  `Entitlements` タブに `plus` を作って同 Product をアタッチ
- 検証: 実機で Sandbox Apple ID サインイン → PlusView で購入 → `app.revenuecat.com` の
  Customers / Transactions タブで購入実績を目視確認
- メリット: spec の本来意図（ダッシュボードに実績が残る）に沿った検証
- デメリット: ユーザー作業が必要

**(b)** **`.env.local` に RevenueCat secret key (`sk_`) を追加 + `.storekit` 構成を追加**
- 条件: `.env.local` に `REVENUECAT_SECRET_API_KEY=<sk_...>` を追加（gitignore 対象）、
  Xcode に Configuration.storekit を作成して月額商品を定義、
  `RevenueCatPlusService` の初期化を StoreKit Testing モードに対応
- 検証: evaluator が REST API v2 で当該 app_user_id の transactions を照会可能に
  （条件4 の一部を自動化）、シミュレータで条件1・2・3 を検証可能
- メリット: autoloop 環境で大部分を自動検証可能に
- デメリット: spec 条件4「ダッシュボードに実績が残る」の精神（実購入の実績）には
  直接応えない（シミュレータ購入は RevenueCat ダッシュボードには届かない）

**(c)** **spec の条件4 を autoloop で検証可能な形へ緩和する**
- 条件: spec.md 行361 を「実装が RevenueCat SDK を経由しており、ダッシュボードに
  登録する手順が明確である」程度に読み替える、または条件4 自体を削除
- メリット: generator 環境で突破可能になる
- デメリット: スプリント14 の本来の目的（ダッシュボードに実績が残る状態）を
  骨抜きにする。spec は『この確認ができない実装は不合格』と明記しており、
  planner の意図を越えた大きな変更になる

### 推奨
**(a)** が本来の目的に最も忠実だが、ユーザー側の作業負荷が大きい。
現実的には **(a) + (b)** の併用（実機検証は手動・CI/autoloop では (b) の
REST API + .storekit で部分自動化）が最も確実。

## 変更ファイル

なし。コード変更ゼロ（作業ツリー clean）。

前回 attempt 4 の成果物（commit `62d3330`）をそのまま温存:
- `SameQ/Session/AppSession.swift`: `refreshPlusEntitlement()` に nil 保護
- `SameQTests/RevenueCatPlusServiceTests.swift`: test11〜14 追加（起動経路の nil 保護）

## テスト実行結果（前回 attempt 4 を継承）

- ユニット 184/184（6.066秒・TEST SUCCEEDED）
- UI 回帰 SprintTen 7/7 + SprintEleven 4/4 + SprintThirteen 4/4 = 15/15（229.2秒・TEST SUCCEEDED）
- Debug / Release ビルドとも BUILD SUCCEEDED
- クラッシュ 0・未処理エラー 0・タイムアウト 0

## 自分で見つけた弱点

1. **条件4 が引き続き人間 evaluator 必須**（4 回連続・未解消）: autoloop 環境に
   RevenueCat ダッシュボード認証・secret key・実機 Sandbox Apple ID が無く、
   generator 環境から到達不能
2. **原因[2] ダッシュボード商品未登録**（4 回連続・未解消）: 起動時の
   `ERROR: 🍎‼️ Error fetching offerings` ログは、ユーザ側で App Store Connect +
   RevenueCat ダッシュボードに商品を登録すれば消える（generator 環境から到達不能）
3. **条件2・3 の実機サンドボックス購入も人間 evaluator 必須**: 商品未登録のため、
   現状サンドボックス購入で `plus` エンタイトルメントが付与されない可能性が高い
4. **attempt 4 で `currentEntitlement()` の保護を入れたが、SDK の挙動が変わると
   機能しなくなる**: test11〜14 は PlusServiceStub 経由のため、実 SDK のオフライン
   挙動を保証するテストではない

## 提案（今回はやらなかったこと）

### A. autoloop に「ユーザー側ブロッカー検出」フラグを追加する
- 3 回連続で同じユーザー側ブロッカーを検出したとき、generator は code-side
  work が無いことを明示して blocked に遷移する運用ルールを generator.md に明記。
  これにより autoloop が「次の attempt でも同じ失敗をするだけ」の空回りを避けられる

### B. eval と self-review の attempt 番号整合
- autoloop のコミットメッセージが attempt 番号と 1 ずれている事例があった
  （eval-4.md 改善提案4）。追跡性のため autoloop 側で修正

### C. .storekit を「条件4 が検証不能なとき」の一時しのぎとして導入
- 条件4 が (a) のダッシュボード目視で合格した後に、CI/autoloop 用の
  バックアップ経路として .storekit を追加するのは妥当な選択肢

## 申し送り

- **コード変更**: attempt 5 ではゼロ。前回 attempt 4 の成果物（commit `62d3330`）を温存
- **state.json**: status を `blocked`、attempt を 5 に更新済み
- **autoloop**: 次の iteration で `case blocked` 分岐に入り exit 2 で停止する
- **3-strike rule 経過**: eval-2/eval-3/eval-4(前回)/eval-4(今回) で [1][2] は同指摘
  4 回連続。[3] は前回 attempt 4 で潰した。コード面のやり残しは無し
- **再開条件**: 上記「ユーザー判断が必要な選択肢」(a)/(b)/(c) のいずれかを選択し、
  ユーザー側で必要な作業（ダッシュボード登録 / secret key 追加 / spec 緩和）が
  行われた後に、blocked を needs_fix に戻して autoloop を再開する
- **注意**: blocked 状態から in_progress に手動で戻すには state.json を直接編集する
  必要がある。autoloop は通常 blocked で停止するが、手動再開も可能

---

## 履歴（参考）

### attempt 4 (前回) — needs_fix
- AppSession.refreshPlusEntitlement() に nil 保護を追加
- 起動経路で currentEntitlement() が nil を返しても既存 Plus を維持
- test11〜14 を新規追加して 184/184 ユニット + 15/15 UI 回帰すべて緑
- evaluator は [3] の解消を確認、[1][2] は同指摘継続

### attempt 3 — needs_fix
- PlusServiceStub.swift を新規作成して AppSession に注入可能に
- RevenueCatPlusServiceTests に test06〜10 を追加（キャンセル時の alert なし・nil 復元）
- AppSession.restorePlus() に nil 保護を追加（条件6）
- ユニット 180/180 + UI 回帰 15/15 すべて緑
- evaluator は [1][2] を同指摘継続

### attempt 2 — needs_fix
- RevenueCat SDK を SPM 依存として導入（RevenueCat 5.87.0）
- RevenueCatPlusService.swift を新規作成（CustomerInfo.entitlements["plus"] → PlusEntitlement）
- scripts/generate-secrets.sh で .env.local の REVENUECAT_API_KEY を注入
- AppSession 既定を RevenueCatPlusService に切替
- 5 本ユニットテストを新規追加（175/175 緑）
- evaluator は [1] ダッシュボード目視不可・[2] ダッシュボード商品未登録を新規指摘

### attempt 1 — blocked → user_action → needs_fix (eval-1)
- 着手前調査でブロッカー3つ発見: spec 矛盾・API key 不在・condition 4 検証不能
- ユーザー判断で選択肢(A) 採用: spec 矛盾解消 + API key 取得 + ダッシュボード目視運用化
- evaluator は引き続き条件4 検証不能で不合格
