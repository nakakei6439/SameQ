# スプリント 11 評価（attempt 1） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/6 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / ユニット158・UI30・evaluator独自UI2すべて成功 | 0 | ✓ |
| 3 データ整合性 | 問題なし（永続層を直接確認） | 100% | ✓ |
| 4 回帰 | Sprint01・04・09・10 の 26/26（4スイート、閾値3以上） | 100% | ✓ |
| 5 使用性 | 3（下限） | 3以上 | ✓ |

## 検証環境
- 端末: iPhone 17 Pro シミュレータ（iOS 26.3, UDID `4C9A260E-CC74-4DE6-AE65-509C6FC2F43E`）
- ビルド: `xcodegen generate` → `xcodebuild build/test`（Debug構成）
- 実行日時: 2026-08-25 23:28〜23:46 JST
- 起動引数: `-SameQResetState -SameQScenario live -SameQFakePlus`（self-review.md 記載の推奨経路）
- テスト内訳:
  - `xcodebuild test -only-testing:SameQTests` → 158/158 成功（self-review.md の「181/181」という記載とは件数が食い違うが、実測は158件ですべて成功。件数不一致は評価に影響しないが自己申告の精度として次項に記載）
  - `xcodebuild test -only-testing:SameQUITests/{SprintEleven,SprintOne,SprintFour,SprintNine,SprintTen}AcceptanceTests` → 30/30 成功（SprintEleven 4件 + 回帰26件）
  - evaluator が独自に追加した一時UIテスト2本（`SameQUITests/EvaluatorTempSprint11Tests.swift`、検証後に削除済み・`git status` clean）
    - `testAccountDeletionSurvivesRelaunch`: アカウント削除 → `app.terminate()` でプロセス完全終了 → 再起動しても初回設定のままであることを確認（self-reviewのテストはアプリを終了せずに確認していたため、より厳しい条件で独自に検証）
    - 確認ダイアログのスクリーンショットを添付・目視確認（下記「使用性」参照）
  - `state.json` を実機ファイルとして直接開き、通報記録の `postExpiresAt` が実在することを確認（下記「基準3」参照）

## 基準1: 受け入れ条件（6/6）
1. **利用規約・プライバシーポリシーが開いて読める**: `test01_legalDocumentsOpenFromSettings` 成功。`LegalText.swift` の内容も確認し、翻訳は端末内完結・安全ログ30日保持という記載が実装（`SafetyLogRetentionTests`）と矛盾しないことを確認（評価者への注記に対応）。ダミー本文であることは spec.md の「置いた前提12」で明示的に許容されている。
2. **絵文字・ニックネーム変更が過去の投稿にも反映**: `test02_profileEditingUpdatesDisplay` で設定画面の表示更新を確認。データ層は `ProfileAndAccountTests.testUpdateProfileRewritesOwnPost`（`myPosts` の `authorEmoji`/`authorNickname` 遡及更新）で担保。単一端末のローカルシミュレーションのため「他ユーザー端末での見え方」は直接検証できないが、他ユーザーへ配信される情報の元データ（`myPosts`）が更新されることを確認した。
3. **アカウント削除は確認ダイアログを挟み、初回設定に戻る**: `test03` 成功に加え、evaluator独自の `testAccountDeletionSurvivesRelaunch` で **アプリを完全終了して再起動しても** 初回設定のままであることを確認済み（プロセス内状態ではなくディスクの状態が変わっていることの証跡）。
4. **削除後、そのユーザーの回答は他ユーザーのタイムラインに表示されない**: `ProfileAndAccountTests.testDeleteAccountClearsUserAndPosts` で `myPosts` が空になることを確認。本アプリはローカル1台完結のシミュレーション（自分の投稿は自分の `state.json` にのみ存在し、他ユーザー役はバンドル済み `SeedCatalog` の静的データ）という設計上、自分の投稿を消せば「他ユーザーに見える経路」自体が存在しなくなる。実測でも削除後に `myPosts: []` になることを確認した。
5. **設定画面から購入復元が実行できる**: `test05` 成功。実際の購入→復元のend-to-endはスプリント10 `test07_purchaseThenRestoreAfterRelaunch_returnsPlusState`（回帰として再実行・成功）で担保。
6. **安全ログの30日保持と期限後自動削除**: `SafetyLogRetentionTests` 4件（1日後は残る／30日+1秒後は消える／旧スキーマのフォールバック／schemaVersion6）すべて成功。加えて evaluator が `SprintFourAcceptanceTests.test01`（通報操作を含む）実行直後の実機 `state.json` を直接開き、
   ```json
   "reports": [{"createdAt": "2026-08-25T14:46:05Z", "postExpiresAt": "2026-08-26T06:14:00Z", ...}]
   ```
   のように `postExpiresAt` が実データとして書き込まれていることを確認した（コードを読んだだけでなく実際にファイルを見た）。

## 基準3: データ整合性（詳細）
- アカウント削除 → `app.terminate()` → 再起動 → `onboarding.next` ボタンが再度表示され、`today.promptText` は存在しない（`XCTAssertFalse`）ことを確認。ディスク上の `state.json` が正しく空アカウント状態で保存されていることの証跡。
- 通報操作後の `state.json` を直接読み、`reports[].postExpiresAt` が投稿の表示期限と一致した値で永続化されていることを確認。
- `schemaVersion: 6` が実ファイルにも反映されていることを確認。

## 基準4: 回帰（4スイート・26件）
- `SprintOneAcceptanceTests` 5/5（オンボーディング・アカウント永続化などコア動線）
- `SprintFourAcceptanceTests` 7/7（通報・ブロック・設定への導線 — 今回設定画面を大きく触ったため重点的に確認）
- `SprintNineAcceptanceTests` 7/7（お題自動生成）
- `SprintTenAcceptanceTests` 7/7（Plus・購入復元 — 今回のスプリントで再利用した機能）

## 基準5: 使用性（3/5・下限）
主要動線（設定→プロフィール編集→保存、設定→規約閲覧、設定→アカウント削除→初回設定）はすべて迷わず完走できた。空状態（ブロックしている人がいません 等）も表示されている。

一方で、**アカウント削除の確認ダイアログに「キャンセル」ボタンが画面上に見えない**ことを実機スクリーンショットで確認した。
- 再現手順: 1. 設定を開く 2. 「アカウントを削除」をタップ 3. 表示された確認シートを見る
- 期待: 「この操作は取り消せません」と警告される破壊的操作なので、明示的なキャンセル導線が見える
- 実際: シートには「アカウントを削除しますか？」というタイトルと本文、赤字の「削除する」ボタンのみが表示され、キャンセルボタンが画面上に存在しない（スクリーンショット: `.product/sprints/11-settings-account-delete/evidence-confirmation-dialog.png` に保存）
- 根拠/補足: `SettingsView.swift` のコードには `Button("キャンセル", role: .cancel) {}` が実装されているが、iOS 26 の `.confirmationDialog` は `role: .destructive` と `role: .cancel` を両方渡すと cancel ボタンをレンダリングしない仕様（generator自身がself-review.mdの「自分で見つけた弱点1」で既に把握し、次スプリント提案にも挙げている）。シートを下にスワイプすれば実質キャンセルになるが、画面上にその手がかりは無い。

この点は受け入れ条件の文言（「確認ダイアログを挟み」）自体には抵触せず、動線も完走できるため合否を下げる理由にはしないが、使用性のスコアは「主要動線は完走できるが、破壊的操作の明示的な取り消し手段が画面から読み取れない」という基準5の下限（3）に該当すると判断した。

## 改善提案（合否には影響しない）
1. **最優先**: `SettingsView` のアカウント削除確認を `.confirmationDialog` から `.alert` へ変更する、または明示的な「キャンセル」ボタンを別行で追加する。iOS 26 では `.confirmationDialog(role: .cancel)` が視覚的に消える既知の挙動のため、破壊的操作の確認としては forma上リスクがある。generator自身も次回提案として挙げている内容と一致。
2. self-review.md に「ユニット181/181」とあるが実測は158/158（全件成功なので問題はないが、次回の自己申告時は実測値を記載してほしい）。
3. プロフィール編集シートの絵文字選択の一覧が長い（generatorの自己申告どおり）。優先度は低い。

## 評価できなかったもの
- 「30日経過後に自動削除される」の実時間での確認（30日待てないため、`AppClock` オフセットによる決定的テストと実データ file の `postExpiresAt` 直書き確認で代替）。
- 実機（実デバイス）での確認は行わず、シミュレータのみで確認した（環境上、実機・実ディスプレイでの手動タップ操作ができなかったため、XCUITest による自動操作 + evaluator独自の追加テスト + 永続化ファイルの直接検査で代替した）。
