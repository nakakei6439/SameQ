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
- **フェーズ**: スプリント05（BAN・投稿頻度制限・スパム対策）評価済み → **不合格（attempt 1）。generator による修正待ち**
- **状態**: スプリント05（F16・F17）を実装（attempt 1、2026-08-18）。1お題1投稿の担保（既存実装の確認のみ）、直近投稿と同一本文の連投拒否（`PersistedState.lastPostBody`）、空白・改行のみ／同一文字の過剰な繰り返しの拒否（`PostValidator`）、いいね・通報の連打制限（`RateLimiter`、Debug限定 `-SameQRateLimitTestMode` で短縮可）、BAN状態のアカウント締め出し（Debug限定 `-SameQBanned` → `BannedView`）、BANされた投稿者の回答の非表示化（`SeedData.json` の `bannedAuthorIDs` → `LocalBackend.visibleOthers`）を実装。制限メッセージは日本語・英語を併記。実装中に見つけた不具合（`TodayPromptView` と `TimelineView` が同じ `alertMessage` に二重に `.alert` を出し、競合してタイムラインごと閉じる）も修正。ユニット12本＋UIテスト7本を追加（合計 37 ＋ 31、スプリント01〜04の回帰も全通過）。詳細は [`plan.md`](.product/sprints/05-ban-spam/plan.md) / [`self-review.md`](.product/sprints/05-ban-spam/self-review.md)。
- **評価結果（2026-08-18）**: スプリント05は **不合格**（attempt 1）。受け入れ条件 **5/6**（条件3の「空白・改行のみ」に拒否メッセージが出ない）・安定性OK（クラッシュ0）・データ整合性OK（schemaVersion 3→4 の移行でデータ欠落なし）・回帰8/8・使用性3。詳細は [`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md)。スプリント04は合格済み（[`eval-1.md`](.product/sprints/04-report-block/eval-1.md)）。
- **次にやること**: **スプリント05 の修正（generator / attempt 2）**。直すのは次の1件のみで、それ以外の受け入れ条件・回帰はすべて通っている。
  - **[必須] 空白・改行だけを入力して「投稿する」を押したとき、拒否メッセージ（日英併記）を出す**（spec.md 180行「拒否メッセージが出て投稿されない」）。
    現状は `TodayPromptView.canSubmit` が trim 後の空文字で送信ボタンを無効にするため `LocalBackend.submitPost` の `emptyBody` に到達せず、
    アラートも出ない。一方で文字数カウンタは `8/140` と出て「入力済みなのに押せない」状態になる。
    再現手順と観測値は [`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md) の「不合格の原因 [1]」を参照。
  - 修正後に `.product/sprints/05-ban-spam/self-review.md` を attempt 2 として更新し、再評価に回すこと。
  - 合否には影響しない改善提案（着手時に踏まえる）: 繰り返し判定の誤検知（`Yessssssss` が拒否される）／連打制限がプロセス内メモリのみで再起動により解除される／連投拒否が直近1件のみ／BAN画面に問い合わせ導線が無い。
  - スプリント04の評価で挙がった改善提案（合否には影響しないが、着手時に踏まえる）:
    - **[1] 読み切り・0件の状態でも ⋯ ボタンがアクセシビリティツリーに残る**（見た目は非表示・タップ不可だがラベルが読み上げられる）。`.accessibilityHidden(true)` か条件付き生成に。
    - **[2] ブロック解除で「以前読んだ回答」も未読に戻る**。ブロック時に既読を消すのではなく、ブロック中は既読判定から外す形にすると副作用が消える。
    - **[3] ブロック一覧へ行くにはタイムラインを閉じる必要がある**。タイムラインの ⋯ の中に「ブロック中の人」への導線があると往復が減る。
    - **[4] 通報・ブロックの失敗時にタイムラインでは何も出ない**（`fullScreenCover` の上にメッセージを出す置き場所が無い）。Supabase 接続前に用意すること。
    - **[5] 操作シート／ブロック確認が `.medium` 固定で下半分が空白**、**[6] 通報「その他」に自由記述が無い**。
  - スプリント03の評価で挙がった改善提案の扱い:
    - **[A] いいねが押した直後以外はユーザーから見えなくなった** — 未対応（仕様側の判断待ち。planner 案件）。
    - **[B] `state.json` の `schemaVersion` が移行後も 1 のまま** — **今回対応**。schemaVersion 3 を足す都合で保存時に `currentSchemaVersion` へ揃えるようにした（`LocalStore.save`）。
    - **[C] 読み切り画面に「引き直す」導線が無い** — 未対応（スプリント03で「再表示の導線は作らない」と決めたため）。
- **再開に必要な情報**:
  - Xcodeプロジェクトは `SameQ.xcodeproj`（`project.yml` から XcodeGen で生成。生成物もコミット済みなので `open SameQ.xcodeproj` で即ビルドできる）。
  - 自動確認は `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' test`（`SameQTests` 37本 ＋ `SameQUITests` 31本）。
  - 初回設定からやり直すには、アプリを削除するか Debug ビルドに起動引数 `-SameQResetState` を付ける。
  - **お題の日程を切り替える起動引数（Debug 限定）**: `-SameQScenario live|expiring|expired|upcoming`、`-SameQExpirySeconds <秒>`、`-SameQGapSeconds <秒>`、`-SameQTimeOffsetMinutes <分>`、`-SameQDebugOverlay`。実時間で28時間待たずに切り替わりを確認するためのもの。
  - **タイムラインの取得ルールと既読を検証する起動引数（Debug 限定・スプリント03で追加）**: `-SameQAnswerCount <件数>`（自分以外の回答を 0 / 1 / 120 件などに固定）、`-SameQResetViewed`（既読の記録だけ消す）。詳細は README と 03 の self-review.md。
  - **Debug オーバーレイに `reported` / `blocked` を追加**（スプリント04）。`-SameQDebugOverlay` で通報数・ブロック中の人数が数字で追える。
  - **BAN・連打制限を検証する起動引数（Debug 限定・スプリント05で追加）**: `-SameQBanned`（自分のアカウントをBAN状態にして起動）、`-SameQRateLimitTestMode`（いいね・通報の連打制限の閾値を短時間で確認できる値に縮める）。詳細は 05 の self-review.md。
- **スプリント05で踏まえたこと**:
  1. タイムラインの候補の絞り込みは `LocalBackend.candidates(promptID:at:)`（ブロック・通報を適用）と `visibleOthers(promptID:at:)`（適用前）に分かれている。BAN外の条件は `visibleOthers` 側に足した（`.empty`/`.exhausted` の判定にも自動的に効く）。
  2. いいね・通報の連打制限はプロセス内メモリだけ（`PersistedState` に永続化していない）。再起動すればリセットされる。詳細と判断理由は 05 の self-review.md「自分で見つけた弱点」。
  3. `TodayPromptView` と `TimelineView` はどちらも同じ `session.alertMessage` を見ているが、`fullScreenCover` 使用時は両方が同時にマウントされているため、`isTimelinePresented` でどちらか一方だけがアラートを出すようにゲートしてある。今後アラートを追加する画面がある場合はこの点に注意すること（同じ `alertMessage` を複数の `.alert` で同時に `isPresented: true` にすると、片方の提示に巻き込まれてもう片方の `fullScreenCover`/`sheet` ごと閉じることがある）。
  4. BANの判定は起動引数 `-SameQBanned` のみで、実データには紐づいていない（置いた前提10のとおり、本来はサーバー側の状態）。Supabase接続時に `users.status` を見る形へ差し替えること。
  5. BANされた投稿者の同梱シード拠出は、既存の22件の**後ろ**に1件追加する形にした（`-SameQAnswerCount` を使う既存テストの件数に影響しないため）。大量件数の検証用に機械生成する回答（`SeedCatalog.resize`）にはBANを混ぜていない。
- **スプリント04 で踏まえたこと（引き続き有効）**:
  1. タイムラインの候補の絞り込みは `LocalBackend.candidates(promptID:at:)` に集約してある。スプリント04の「ブロック外／通報済み以外」はここに条件を足した。
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
- [x] 実装（generator）— 2026-08-18。タイムライン ⋯ からの通報（理由7種→送信→完了表示）とブロック（確認→完了表示）、通報後の即時非表示と永続、ブロックの永続とお題をまたいだ持続、設定画面のブロック一覧と解除、`candidates()` への条件追加、schemaVersion 3、Debug オーバーレイに `reported` / `blocked` を追加。ユニット9本＋UIテスト7本を追加（合計 25 ＋ 24）。[`plan.md`](.product/sprints/04-report-block/plan.md) / [`self-review.md`](.product/sprints/04-report-block/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・注記2件（ブロック一覧の情報漏れ無し／最後の1件をブロックしても `timeline.exhausted` へ正しく落ちる）・お題をまたいだブロックの持続・クラッシュ0・データ整合性OK（`reports` / `blockedAuthors` を直接確認）・回帰5/5・使用性4。[`eval-1.md`](.product/sprints/04-report-block/eval-1.md)

### スプリント05: BAN・投稿頻度制限・スパム対策
含む機能: F16, F17
- [x] 実装（generator）— 2026-08-18。1お題1投稿の担保確認、直近投稿と同一本文の連投拒否、空白・改行のみ／同一文字の過剰な繰り返しの拒否、いいね・通報の連打制限、BAN状態のアカウント締め出し（Debug限定 `-SameQBanned`）、BANされた投稿者の回答の非表示化。制限メッセージは日英併記。[`plan.md`](.product/sprints/05-ban-spam/plan.md) / [`self-review.md`](.product/sprints/05-ban-spam/self-review.md)
- [ ] 評価（evaluator）— 2026-08-18 **不合格**（attempt 1）。受け入れ条件 **5/6**（空白・改行のみの投稿に拒否メッセージが出ない）。安定性OK（クラッシュ0・独自 XCUITest 12本）・データ整合性OK（schemaVersion 3→4 移行でデータ欠落なし）・回帰8/8・使用性3。BAN画面の締め出し／BAN投稿者の非表示／連投拒否／繰り返し拒否／いいね・通報の連打制限は確認済み。[`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md)

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
- 追記（2026-08-18）: スプリント04の `20260818000003_report_block.sql`（reports / blocks / world_timeline 更新 / blocked_authors ビュー）も `supabase db push` で適用済み。アプリからは未使用（LocalBackend のまま）。
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

### スプリント04で決めたこと
21. **通報の理由は7種**（政治的な対立／宗教的な対立／差別・ヘイト／性的な内容／犯罪をすすめている／個人情報／その他）。spec.md 6節（お題の安全条件）に挙がっている観点に揃えた。自由記述欄は作らない。
22. **通報・ブロックの導線はタイムライン上部の ⋯**（`timeline.more`）。カード下の操作は「次へ」と「いいね」の2つのままにして、指が届く位置に破壊的な操作を置かないため。
23. **完了表示はシートの中の1ステップにする**（トーストにしない）。「完了表示が出て」という受け入れ条件を、見逃せない形で満たすため。送信・ブロックの確定と同時に裏で次の1件を引くので、閉じた時点では次の回答になっている。
24. **ブロックした相手の回答は既読から外す**。解除したときに「再び表示対象に戻る」（受け入れ条件4）を成立させるため。読んだのではなくブロックした、という扱い。
25. **ブロック・通報で候補が尽きた場合は `.empty` ではなく `.exhausted`**（「今は新しい回答がありません」）に落とす。誰も答えていないわけではないので、「まだ誰も答えていません」は嘘になる。判定は `nextTimelinePost` 冒頭の `visibleOthers`（ブロック・通報を適用する前の集合）で行う。
26. **ブロック一覧に出すのは絵文字とニックネームだけ**。`BlockedAuthor` は国・言語・本文・投稿時刻を持たない。`blockedAt` は並び順にだけ使い、画面には出さない。
27. **設定画面は今回ブロック管理のみ**。本格的な設定（絵文字・ニックネーム変更／規約／購入復元）はスプリント11。入り口は今日のお題とお題待ちの右上の歯車。
28. **通報の記録はお題の終了で端末から落とす**（既読と同じ扱い・履歴を持たない方針）。ブロックは相手に対するものなので解除するまで残す。サーバー側の安全ログ30日保持は F34（スプリント11）。
29. **`-SameQAnswerCount` で機械生成する回答の投稿者を、お題をまたいで同一人物にした**（1お題1投稿は維持）。「ブロックした人が次のお題にも出てこない」を検証できるようにするため。
30. **`LocalStore.save` で `schemaVersion` を現在値に揃えるようにした**（スプリント03評価の改善提案[B]）。schemaVersion 3 を足すにあたり、揃えないと移行判定を誤るため今回対応した。

### スプリント05で決めたこと
31. **BANは Debug限定の起動引数 `-SameQBanned` で模擬する**。「置いた前提10」（BANは運営がサーバー側で切り替える運用・アプリ内に運営用画面は作らない）のとおり、アプリ内にBAN切り替えUIは作らない。`AppSession.start()` の冒頭でこの引数を見て `.banned` 画面に固定するので、今日のお題・タイムラインへ到達する経路は存在しない。
32. **BANされた投稿者の非表示は同梱シードに1件焼き込んで検証する**。`SeedData.json` に `bannedAuthorIDs`（トップレベル配列）を追加し、`PromptSchedule.bannedAuthorIDs` として保持、`LocalBackend.visibleOthers` で除外する。既存の22件（prompt_001）の**後ろ**に追加したので、`-SameQAnswerCount` を使う既存テスト（スプリント03・04）の件数には影響しない。
33. **同一文面の連投拒否は「直近の1投稿」とのみ比較する**。`PersistedState.lastPostBody` を新設し、`myPosts`（期限切れで掃除される）とは別に、お題をまたいで残す。比較は前後の空白・改行を除いたうえでの完全一致。
34. **無意味な文字列の判定は「最頻出1文字が70%以上・対象文字数4文字以上」の単純な閾値にした**。多言語の短い正常回答（「はい」「OK」など）を誤って弾かないための下限と、実際に「あああ」のような繰り返しを確実に拾うための上限を両立させる値として決めた。
35. **いいね・通報の連打制限は `PersistedState` に永続化しない**（プロセス内メモリのみ、再起動でリセット）。「短時間の連打」を防ぐのが目的であり、悪質ユーザーの継続対策はBAN（サーバー側）が担う想定のため。
36. **制限メッセージは日本語行＋英語行を同じ文字列に入れて常時両方表示する**（`BackendError.errorDescription` の該当ケースと `BannedView`）。アプリ全体の多言語対応の基盤（Localizable.strings 等）がまだ無いため、範囲をスプリント05で追加・変更したメッセージ（`emptyBody` / `bodyTooLong` / `duplicateBody` / `meaninglessBody` / `rateLimited` / BAN画面）に絞った。
37. **`TimelineView` に `.alert` を新設した**（スプリント04の改善提案[4]の一部を解消）。いいね・通報の制限メッセージがタイムライン上で発生するため、表示先が必要になった。実装したところ、裏で生き続ける `TodayPromptView` の `.alert` と同時に `isPresented` になり `fullScreenCover` ごと閉じる不具合が見つかったため、`isTimelinePresented` でどちらか一方だけが有効になるようゲートした。

## 変更履歴
- 2026-08-17: `.product/spec.md` 作成（planner）。PROGRESS.md 初版作成。
- 2026-08-17: スプリント01 実装（generator）。SwiftUI雛形＋F01〜F07、Supabaseスキーマ、UIテスト5本。
- 2026-08-17: スプリント01 評価（evaluator）。iPhone 17 / iOS 26.5 シミュレータで実操作検証し **合格**。次はスプリント02の実装。
- 2026-08-17: スプリント02 実装（generator）。F08・F09・F10。お題待ち画面、有効期間による画面切り替え、投稿の表示期限、検証用の起動引数、ユニットテスト6本＋UIテスト5本を追加。
- 2026-08-17: ブロッカー B01 解消（Supabase プロジェクト作成・初期マイグレーション適用）。アプリからの接続切り替えは未着手。
- 2026-08-17: スプリント02のマイグレーション `20260817000002_prompt_lifecycle.sql` を Supabase に適用済み。次はスプリント02の evaluator 検証。
- 2026-08-18: スプリント02 評価（evaluator）。iPhone 17 Pro / iOS 26.3 シミュレータで独自 XCUITest 9本＋`simctl` 単体起動により実操作検証し **合格**。次はスプリント03の実装。
- 2026-08-18: スプリント03 実装（generator）。F11・F12。未読優先のランダム1件取得、既読の永続（`viewedPostIDs` / schemaVersion 2）、読み切り／0件の明示表示、検証用の起動引数 `-SameQAnswerCount` / `-SameQResetViewed`、同梱シードを22件へ増量。ユニットテスト10本＋UIテスト7本を追加（合計 16 ＋ 17）。次はスプリント03の evaluator 検証。
- 2026-08-18: スプリント04 実装（generator）。F13・F14・F15。通報（理由7種・完了表示・即時非表示・永続）、ブロック（確認・完了表示・お題をまたいだ持続）、設定画面のブロック一覧と解除、`state.json` schemaVersion 3、Supabase マイグレーション `20260818000003_report_block.sql` を作成・**適用済み**（reports / blocks テーブル、world_timeline の絞り込み追加、blocked_authors ビュー）。ユニット9本＋UIテスト7本を追加。次はスプリント04の evaluator 検証。
- 2026-08-18: スプリント04 評価（evaluator）。iPhone 17（iOS 26.5 / 26.3）シミュレータ2台で独自 XCUITest 10本＋`simctl` 単体起動により実操作検証し **合格**。通報・ブロック・ブロック一覧と解除・お題をまたいだ持続・最後の1件をブロックしたときの空状態を確認。次はスプリント05の実装。
- 2026-08-18: スプリント05 実装（generator）。F16・F17。1お題1投稿の担保確認、直近投稿と同一本文の連投拒否（`lastPostBody`）、空白・改行のみ／同一文字の過剰な繰り返しの拒否（`PostValidator`）、いいね・通報の連打制限（`RateLimiter`、Debug限定 `-SameQRateLimitTestMode`）、BAN状態のアカウント締め出し（Debug限定 `-SameQBanned` → `BannedView`）、BANされた投稿者の回答の非表示化（`SeedData.json` の `bannedAuthorIDs`）、制限メッセージの日英併記、`state.json` schemaVersion 4。実装中に `TodayPromptView`/`TimelineView` の二重アラート競合でタイムラインが閉じる不具合を発見・修正。ユニット12本＋UIテスト7本を追加（合計 37 ＋ 31、スプリント01〜04の回帰も全通過）。次はスプリント05の evaluator 検証。
- 2026-08-18: スプリント05 評価（evaluator）。iPhone 17（iOS 26.3 / 26.5）シミュレータ2台で独自 XCUITest 12本（E01〜E12）＋`simctl` 単体起動により実操作検証し **不合格**。BAN画面から抜ける裏道なし・BAN投稿者の回答が22件の読み切りまで一度も出ない・連投拒否・繰り返し拒否・いいね/通報の連打制限・制限後の復帰・schemaVersion 3→4 の移行はいずれもOK。**空白・改行のみの投稿に拒否メッセージが出ない**点だけが受け入れ条件を満たさず（5/6）。次はスプリント05の修正（generator / attempt 2）。[`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md)
