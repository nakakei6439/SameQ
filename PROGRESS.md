# PROGRESS

## 再開手順（新しいセッションで戻ってきた場合）
1. このファイルをまず読む。調査・仕様の読み直しはしない。
2. 下の「作業単位チェックリスト」で **最初の未完了項目（[ ]）** を探す。
3. 「現在の状態」の該当行にある関連ファイル・IDを見て、そこから続ける。
4. 各作業単位が完了したら、このファイルの該当チェックボックスと「現在の状態」を**即座に**更新してコミットする。

## メタ情報
| 項目 | 値 |
|---|---|
| アプリ名 | SameQ |
| ローカルリポジトリ | `/Users/nakagawakeita/Products/iOSApp/SameQ` |
| GitHubリポジトリ | `nakakei6439/SameQ`（Private） |
| 製品仕様書 | [`.product/spec.md`](.product/spec.md)（機能一覧34件、スプリント11本） |
| 開発ハーネス | planner → generator → evaluator |

## 現在の状態
- **フェーズ**: スプリント03 **合格** → **スプリント04（通報とブロック）実装待ち**
- **状態**: スプリント03（タイムラインの取得ルールと既読管理 / F11・F12）は **evaluator の実機検証で合格**（attempt 1、2026-08-18）。iPhone 17 シミュレータ2台で、evaluator 独自の XCUITest 10本 ＋ `simctl launch` による素の起動・`state.json` の直接確認を実施。受け入れ条件6/6、0件・1件・120件の3ケース、再起動後の既読残存、いいねの永続（既読と独立）まで確認済み。クラッシュ0。詳細は [`eval-1.md`](.product/sprints/03-timeline-rules/eval-1.md)。
- **次にやること**: **スプリント04（通報とブロック / F13・F14・F15）の実装**（generator）。受け入れ条件は `.product/spec.md` 160〜166行、評価者への注記は168行。通報導線と理由選択・通報後の即時非表示・ブロックと永続化・設定内のブロック一覧と解除を作る。取得条件の追加先は `LocalBackend.candidates(promptID:at:)`。
  - 評価で挙がった改善提案（合否には影響しないが、着手前に planner が判断すること）:
    - **[A] いいねが押した直後以外はユーザーから見えなくなった**（F12 で既読の回答は再表示されないため）。スプリント01の受け入れ条件8は通常操作では検証不能。仕様側で「いいねは誰にも見えない」ことを明記するか、いいねの意味づけを決める。
    - **[B] `state.json` の `schemaVersion` が移行後も 1 のまま**（保存時に `currentSchemaVersion` へ揃えていない）。将来の移行分岐で誤判定する。
    - **[C] 読み切り画面に「引き直す」導線が無い**（閉じて開き直せば引けるが説明が無い）。
- **再開に必要な情報**:
  - Xcodeプロジェクトは `SameQ.xcodeproj`（`project.yml` から XcodeGen で生成。生成物もコミット済みなので `open SameQ.xcodeproj` で即ビルドできる）。
  - 自動確認は `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' test`（`SameQTests` 16本 ＋ `SameQUITests` 17本）。
  - 初回設定からやり直すには、アプリを削除するか Debug ビルドに起動引数 `-SameQResetState` を付ける。
  - **お題の日程を切り替える起動引数（Debug 限定）**: `-SameQScenario live|expiring|expired|upcoming`、`-SameQExpirySeconds <秒>`、`-SameQGapSeconds <秒>`、`-SameQTimeOffsetMinutes <分>`、`-SameQDebugOverlay`。実時間で28時間待たずに切り替わりを確認するためのもの。
  - **タイムラインの取得ルールと既読を検証する起動引数（Debug 限定・スプリント03で追加）**: `-SameQAnswerCount <件数>`（自分以外の回答を 0 / 1 / 120 件などに固定）、`-SameQResetViewed`（既読の記録だけ消す）。詳細は README と 03 の self-review.md。
- **スプリント04 に入るときに踏まえること**:
  1. タイムラインの候補の絞り込みは `LocalBackend.candidates(promptID:at:)` に集約してある。スプリント04の「ブロック外／通報済み以外」はここに条件を足す。
  2. スプリント03で **スプリント01の受け入れ条件8（いいねの押下状態が開き直しても残る）の検証手順を変更した**。F12（既読）を入れると一度出した回答は再表示されないため、`-SameQResetViewed` を挟んで同じ回答を出し直す手順にしている。いいねの永続そのものは維持（ユニットテスト `testLikesSurviveRelaunchIndependentlyOfViewedRecords` でも担保）。
  3. 既読は「画面に出した瞬間」に記録する（読み終えてからではない）。閉じて開き直すと必ず別の回答が出る。
  4. スプリント01評価の改善提案3件（キーボードが「投稿する」を半分隠す／投稿ボタンが押せない理由が出ない／`state.json` 破損時にアカウントが黙って消える）は**まだ未対応**。詳細は 01 の eval-1.md。
  5. スプリント02評価の改善提案は [C]（`-SameQDebugOverlay` が最下部のテキストに重なる）のみスプリント03で解消（`safeAreaInset` に変更）。[A] 期限切れの瞬間にタイムラインが無言で閉じる／[B] 入力中に期限が切れると書きかけが消える、は**未対応**。
  6. お題の切り替え判定は端末時計 ＋ 1秒間隔のポーリング。サーバー時刻に合わせるのは Supabase 接続時の課題。
  7. 期限切れ投稿が「他ユーザーから見えない」ことは、`LocalBackend`（単一端末）のため UI では確認できていない。データ層とユニットテストで代替確認済み。Supabase 接続時に実端末2台で再確認すること。
  8. 既読はローカルの `state.json`（`viewedPostIDs`）にしか無い。端末を替えると引き継がれない（サーバー側 `viewed_posts` テーブルは定義済み・未使用）。

---

## 作業単位チェックリスト

### 0. リポジトリ初期化
- [x] `git init` / `.gitignore`・`README.md` 作成
- [x] 初回コミット（`.product/spec.md`, `PROGRESS.md`, `README.md`, `.gitignore`）— commit `52c93f2`
- [x] GitHub Private リポジトリ `nakakei6439/SameQ` 作成・push — https://github.com/nakakei6439/SameQ

### スプリント01: コア体験（設定→お題→投稿→世界タイムライン→いいね）
含む機能: F01, F02, F03, F04, F05, F06, F07
- [x] 実装（generator）— 2026-08-17
- [x] 評価（evaluator）— 2026-08-17 **合格**（attempt 1）。受け入れ条件8/8・クラッシュ0・データ整合性OK。[`eval-1.md`](.product/sprints/01-core-experience/eval-1.md)

### スプリント02: お題のライフサイクルと投稿の寿命
含む機能: F08, F09, F10
- [x] 実装（generator）— 2026-08-17。お題待ち画面、開始/終了時刻による画面切り替え、投稿の表示期限、期限切れ回答の除外、履歴導線を作らないことの担保。[`plan.md`](.product/sprints/02-prompt-lifecycle/plan.md) / [`self-review.md`](.product/sprints/02-prompt-lifecycle/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・クラッシュ0・データ整合性OK・回帰5/5・使用性4。[`eval-1.md`](.product/sprints/02-prompt-lifecycle/eval-1.md)

### スプリント03: タイムラインの取得ルールと既読管理
含む機能: F11, F12
- [x] 実装（generator）— 2026-08-18。未読優先のランダム1件取得、既読の記録と永続、読み切り／0件の明示表示、前へ戻る操作を持たないことの担保、検証用の起動引数（`-SameQAnswerCount` / `-SameQResetViewed`）。[`plan.md`](.product/sprints/03-timeline-rules/plan.md) / [`self-review.md`](.product/sprints/03-timeline-rules/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・0件/1件/120件の3ケース確認・再起動後も既読が残る・クラッシュ0・データ整合性OK（旧 schemaVersion 1 からの移行も確認）・回帰8/8・使用性4。[`eval-1.md`](.product/sprints/03-timeline-rules/eval-1.md)

### スプリント04: 通報とブロック
含む機能: F13, F14, F15
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 160〜166行

### スプリント05: BAN・投稿頻度制限・スパム対策
含む機能: F16, F17
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 177〜183行

### スプリント06: 投稿本文とお題の自動翻訳
含む機能: F18, F19, F20, F21, F22
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 194〜201行

### スプリント07: ニックネームの自動ローカライズ
含む機能: F23
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 212〜217行

### スプリント08: ランダム通知
含む機能: F24, F25
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 228〜234行

### スプリント09: お題の自動生成
含む機能: F26, F27
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 245〜251行

### スプリント10: Plus（RevenueCatによる課金）
含む機能: F28, F29, F30, F31
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 263〜269行

### スプリント11: 設定・アカウント削除・安全ログ
含む機能: F32, F33, F34
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 281〜286行

---

## 置いた前提（ユーザー確定済み・2026-08-17）
`.product/spec.md` の「置いた前提」12件のうち、事前確認した4件はユーザー承認済み。変更しない。
1. 1お題1投稿・編集削除不可
2. お題有効期間28時間固定・常に1つだけ有効
3. いいね数は自分の受信数のみ自分だけに表示
4. 音写できないニックネームは絵文字のみ表示

## ブロッカー

### B01: Supabase クラウドプロジェクト（2026-08-17 解消）
- プロジェクト作成・マイグレーション適用は完了。認証情報は `.env.local`（gitignore対象）に保存済み
- 未実施: アプリからの実際のSupabase接続（LocalBackend → SupabaseBackend への切り替え）。担当スプリント未定。次にこのタスクに着手する際は、まず `.env.local` の内容とdashboardを確認すること
- 追記（2026-08-17）: `20260817000002_prompt_lifecycle.sql` も `supabase db push` で適用済み（`prompts_no_overlap` 制約と `posts_set_expiry_trigger` は移行前のテーブルに無かったため `NOTICE ... skipping` が出たが、CREATE文自体は成功しており実害なし）。更新版 `supabase/seed.sql` は**まだ流し込んでいない**（アプリがまだLocalBackendで動いているため急ぎではない。SupabaseBackend実装時に一緒に流すこと）。

## 今回の判断（generator が自分で決めたこと）
仕様に書かれておらず、ユーザーに確認できなかったため自分で決めた事項。覆してよい。
1. **技術構成**: XcodeGen（`project.yml`）でプロジェクトを生成。外部パッケージ依存はゼロ。iOS 18.0 Deployment Target。
2. **回答の文字数上限は140文字**（F04のカウンター表示に上限が必要なため。スプリント10の無料ユーザー上限に合わせた）。
3. **お題は `prompt_001` 固定**、本文「今日、思わず笑ってしまったことは何ですか？」。世界の回答は14件（10言語、うち5件はニックネーム未設定）を同梱。
4. **アカウントは初回設定の最終ステップで一括作成**。途中終了しても何も保存しない（中途半端なアカウントを作らないため）。
5. **オンボーディングに「戻る」を用意**。規約や絵文字を選び直せるようにするため。
6. **Debug限定の起動引数 `-SameQResetState`** を用意。UIテストと再検証で初期状態に戻すため（Releaseビルドには含まれない）。
7. **デザイン**: 参考モックアップのトーン（白い角丸カード／緑のプライマリボタン／丸ゴシック）に寄せつつ、要望どおり装飾は控えめ（背景は淡いグラデーションのみ）。タイムラインの操作は ✕（次へ）と ♥（いいね）の2つ。モックアップにあった「いいね一覧」「他人の投稿のいいね数」「タブバー」は仕様と矛盾するため実装していない。

### スプリント02で決めたこと
8. **お題の日程は起動時に組み立てる**。Supabase 未接続のため、同梱シードのお題2件（`prompt_001` / `prompt_002`）に、シナリオごとの開始・終了時刻を起動時刻を基準に割り当てる（`SameQ/Backend/PromptSchedule.swift`）。有効期間は常に28時間・重なりなし。
9. **検証用の起動引数はすべて Debug 限定**（`LaunchOptions`）。`-SameQScenario` / `-SameQExpirySeconds` / `-SameQGapSeconds` / `-SameQTimeOffsetMinutes` / `-SameQDebugOverlay`。Release ビルドでは既定値に固定される。
10. **お題待ち画面に次のお題の開始時刻を出さない**。「いつ来るか分からない」というリズム（spec.md の中心体験）を壊さないため。時刻の確認は Debug オーバーレイでのみ可能。
11. **有効期間の判定は1秒間隔のポーリング＋前面復帰時**。画面を開いたまま期限をまたいでも切り替わる。期限が切れたらタイムラインは自動で閉じる。
12. **期限切れの自分の回答といいねは端末の保存から落とす**（`LocalBackend.pruneExpired`）。履歴を持たない方針（対象外「履歴」）をデータ側でも守るため。
13. **有効期間外のお題には投稿できない**（`BackendError.promptNotActive`）。投稿直前に期限が切れた場合はお題待ちへ落とす。

### スプリント03で決めたこと
14. **既読にするタイミングは「画面に出した瞬間」**。「読み終えてから」にすると、閉じて開き直したときに同じ回答が再び出てしまい、受け入れ条件「1件目に出る回答が毎回同一とは限らない」と噛み合わないため。
15. **読み切ったら既読の回答を出し直さない**。仕様が「明示された状態表示になる」としか言っていないので、再表示（読み直し）の導線は作らない。
16. **`empty`（回答が1件も無い）と `exhausted`（全部読んだ）を別の文言で出す**。利用者にとって意味が違うため。識別子は `timeline.empty` / `timeline.exhausted`（どちらも入れ物は `timeline.end`）。
17. **スプリント01の受け入れ条件8の検証手順を変更した**。既読の導入で「開き直して同じ回答を探す」が成立しないため、`-SameQResetViewed`（既読だけ消す起動引数）を挟む手順に差し替え、いいねの永続はユニットテストでも担保する。
18. **既読の掃除は「期限切れと確認できた投稿」に限る**。`-SameQAnswerCount` で回答の顔ぶれが変わっても既読が黙って消えないようにするため。
19. **同梱シードの `prompt_001` を14件→22件に増やした**（`supabase/seed.sql` も同期）。「20件あるとき20回スワイプして重複しない」を引数なしでも確認できるようにするため。
20. **Debug オーバーレイを `overlay` から `safeAreaInset` に変えた**。スプリント02評価の指摘[C]（最下部のテキストに重なる）を解消。今回オーバーレイが検証の主要な手段になるため。

## 変更履歴
- 2026-08-17: `.product/spec.md` 作成（planner）。PROGRESS.md 初版作成。
- 2026-08-17: スプリント01 実装（generator）。SwiftUI雛形＋F01〜F07、Supabaseスキーマ、UIテスト5本。
- 2026-08-17: スプリント01 評価（evaluator）。iPhone 17 / iOS 26.5 シミュレータで実操作検証し **合格**。次はスプリント02の実装。
- 2026-08-17: スプリント02 実装（generator）。F08・F09・F10。お題待ち画面、有効期間による画面切り替え、投稿の表示期限、検証用の起動引数、ユニットテスト6本＋UIテスト5本を追加。
- 2026-08-17: ブロッカー B01 解消（Supabase プロジェクト作成・初期マイグレーション適用）。アプリからの接続切り替えは未着手。
- 2026-08-17: スプリント02のマイグレーション `20260817000002_prompt_lifecycle.sql` を Supabase に適用済み。次はスプリント02の evaluator 検証。
- 2026-08-18: スプリント02 評価（evaluator）。iPhone 17 Pro / iOS 26.3 シミュレータで独自 XCUITest 9本＋`simctl` 単体起動により実操作検証し **合格**。次はスプリント03の実装。
- 2026-08-18: スプリント03 実装（generator）。F11・F12。未読優先のランダム1件取得、既読の永続（`viewedPostIDs` / schemaVersion 2）、読み切り／0件の明示表示、検証用の起動引数 `-SameQAnswerCount` / `-SameQResetViewed`、同梱シードを22件へ増量。ユニットテスト10本＋UIテスト7本を追加（合計 16 ＋ 17）。次はスプリント03の evaluator 検証。
