# スプリント12 評価（attempt 11） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 実操作で確認できたのは 5/8（条件1・2・4・6・8）。条件3は実 e2e で不合格。条件5・7 は部分確認のみ | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0 / 未処理例外0 / 主要動線（オンボーディング→投稿→myAnswer→タイムライン）完走。ただし条件3の RPC 404 が無言で握り潰される | クラッシュ0・未処理0・主要動線完走 | ✓ |
| 3 データ整合性 | 投稿・いいね・通報・ブロックは本番 Supabase に永続化され、状態ゼロの別クライアントからの再取得でも一致 | 100% | ✓ |
| 4 回帰 | SprintNine 7/7・SprintTen 7/7・SprintEleven 4/4（計18/18）＋ ユニット 166/166 | 100% | ✓ |
| 5 使用性 | 3（オンボーディング・お題待ち・オフライン説明・エラーアラートは有る。受信いいねが無言で永久に0のまま） | 3以上 | ✓ |

**基準1が閾値未達（条件3が実 e2e で不合格）のため不合格。** eval-7 と同じ条件3のブロッカーが解消されておらず、
さらに「attempt 11 で入れた修正は本番へ適用できない構造」であることを新たに確認した。

## 検証環境
- macOS / Xcode 26.6（17F113）、iOS Simulator iPhone 17（iOS 26.3）
- `xcodegen generate` → `xcodebuild build -configuration Debug` → **BUILD SUCCEEDED**
- 本番 Supabase プロジェクト `loqumzfgnahtclnvnrzb`（spec.md 前提13）。`supabase` CLI はログイン・link 済み。
  匿名サインアップは現在**有効**（eval-5 時点の 422 "Anonymous sign-ins are disabled" は解消済み）。
- 検証手段:
  1. 実 e2e UI テスト `SameQUITests/SprintTwelveEvalE2ETests`（リポジトリに既存・eval-7 で追加されたもの）を再実行。
     端末A はシミュレータで実アプリを UI 操作（オンボーディング完了→投稿）、「もう1台」は `URLSession` 直叩きの実クライアント。
  2. `curl`/`urllib` e2e（`/tmp/sameq_e2e.py` / `/tmp/sameq_e2e2.py`）で 4 アカウントを本番へ流し、
     signup→users→posts→world_timeline→likes→rpc→reports→blocks の各ステータスと RLS/RPC の効き方を直接観測。
  3. `-SameQForceOffline` を付けた一時 UI テストでオフライン起動画面を確認（実行後に削除、`git status` クリーン確認済み）。
  4. ユニット 166/166、SprintTwelve UI 3/3、回帰 UI 18/18 を自分で再実行。
- 検証日時: 2026-08-27 11:40〜11:56 JST

## 前進の確認（正しく評価する）
- 条件6（オフライン起動）は今回**確認できた**。`-SameQForceOffline` を付けて起動すると
  「読み込めませんでした」＋「通信できません。ネットワーク接続を確認してください。」＋「もう一度試す」ボタンが出る。
  白紙・無限スピナー・クラッシュのいずれにもならない。retry ボタンは `start()` を再実行するので、
  接続回復後はアプリを入れ直さずに通常画面へ戻れる。
- 条件1（投稿共有）・条件2（同一お題）・条件4（通報/ブロックで即時非表示）・条件8（シード非表示）は
  eval-7 に続き今回も実 e2e / curl / UI テストで確認できた（詳細は後述）。
- `OnboardingView` に `session.alertMessage` を購読する `.alert` が入り、eval-5 で指摘した
  「オンボーディング完了ボタンで通信失敗すると無言で永久停止」は解消されている。
- ユニット 166/166・SprintTwelve UI 3/3・回帰 18/18 を自分で再実行し、すべて成功を確認。クラッシュ 0。

## 不合格の原因（これを直せば通る）

### [1] 条件3が依然不成立 — 「受信したいいねの総数」が常に 0 のまま増えない（eval-7 [1] の再発）
spec.md 308行:「端末Bが端末Aの回答にいいねを押すと、端末Aの画面で自分が受け取ったいいねの総数が1増える」

- **再現手順**:
  1. `xcodebuild test -only-testing:SameQUITests/SprintTwelveEvalE2ETests` を実行（本番 Supabase 相手）。
  2. テスト内で端末A（実アプリ）がオンボーディング完了→prompt_001 に固有マーカー入りで投稿。`today.myAnswer` 表示まで到達（ここまでは成功）。
  3. 「もう1台」（`URLSession` の実クライアント）が prompt_001 に回答し、`world_timeline` から端末A の投稿を取得、その `post_id` に `POST /rest/v1/likes`（201）。
  4. 端末A の画面を最大 20 秒観測。
- **期待**: 端末A の `today.myAnswer` の下に `today.receivedLikes`（「1 件のいいね」）が現れる。
- **実際**: 20 秒待っても `today.receivedLikes` は出現しない。受信いいねは 0 のまま。エラー表示も無い。
  `SprintTwelveEvalE2ETests.test_condition1_and_3_realDeviceB` が
  `SprintTwelveEvalE2ETests.swift:86: XCTAssertTrue failed - 条件3違反: … 受信いいね 0 のまま` で FAIL（34.5秒）。
  同テスト内の条件1チェック（`world_timeline` に端末A の投稿が出る）は同じ実行内で**パス**しているので、いいね INSERT までの経路は健全。
- **根拠（本番DBを直接観測）**:
  - 端末A のトークンで `POST /rest/v1/rpc/received_like_count`（`{"target_post": "<Aの投稿ID>"}`）→
    **`404 {"code":"PGRST202","message":"Could not find the function public.received_like_count(target_post) in the schema cache"}`**。
    関数が本番に存在しない。（`evidence-eval8-condition3-rpc-missing.txt`）
  - 端末A のトークンで `GET /rest/v1/likes?post_id=eq.<Aの投稿ID>` → `200 []`（RLS `likes_select_own` で他人のいいね行は読めない。eval-7 [1]b と同じ）。
  - `SupabaseBackend.receivedLikeCount` は上記 RPC を呼ぶが 404 で throw → `AppSession.refreshReceivedLikeCount()` の
    `catch { receivedLikeCount = 0 }` に落ちる（`AppSession.swift:403-405`）。無言で 0。

- **なぜ本番に関数が無いか（症状と分けて記載。ここが今回の新規発見）**:
  attempt 11 は `received_like_count` 関数と `liked_authors_view` を
  **既に本番へ適用済みのマイグレーション `supabase/migrations/20260819000004_server_connection.sql` の末尾に追記**した。
  Supabase のマイグレーションは適用済みのものが不変で、`supabase db push` は
  「`20260819000004` は適用済み」と判断して**再実行しない**。実際に evaluator 環境で確認:
  - `supabase migration list --linked` → Local/Remote とも `20260817000001 / 20260817000002 / 20260818000003 / 20260819000004`（4件で一致）。
  - `supabase db push --linked` / `--dry-run` → いずれも **`Remote database is up to date.`**（何も流れない）。
  つまり self-review.md が前提にしている「`supabase db push` で migration 4 の更新版がリモートに適用される」は
  この構成では成立しない。ユーザーが `supabase db push` をどれだけ叩いても関数は作られない。
- **直し方（どちらか）**:
  - `received_like_count` / `liked_authors_view` を **新しいマイグレーションファイル**
    （例 `supabase/migrations/20260820000005_received_like_count.sql`）に切り出す。これなら `supabase db push` で適用される。
  - もしくは、この eval で使った手段（本番 DB へ直接 SQL 実行）で関数を先に作ってから再評価する運用を self-review に明記する。
  - 関数を本番に置いたうえで、`SprintTwelveEvalE2ETests` が緑になることを generator 側で確認してから awaiting_eval にすること
    （現状このテストはリポジトリにあるのに attempt 11 のテスト実行対象から外れている）。
- 補足: 仮に関数を本番へ適用しても、`SupabaseClient.rpc` の戻り値デコード（関数が 0 行返す＝他人の投稿指定時に `null`）で
  `Int` デコードが失敗して `catch` に落ちる可能性がある。自分の投稿ケースは `count(*)` の 1 行が返るので問題ないはずだが、
  関数適用後に必ず実 e2e で「1 件のいいね」表示まで通すこと。

### [2] 条件7 は実 e2e 未確認（コード上は妥当）
spec.md 312行:「投稿・いいね・通報・ブロックが通信の失敗で完了しなかった場合、失敗が画面に表示され、同じ操作をもう一度試せる」

- コード確認では 4 操作とも失敗時に `alertMessage` を立て、`toggleLike` は楽観更新をロールバックし、
  `report`/`block` は `false` を返す。`TodayPromptView` / `TimelineView` は `alertMessage` を `.alert` で提示する。
  「無言で成功したように見える」経路は見当たらない。
- ただし `-SameQForceOffline` は起動時にしか効かず、**オンボーディング済みアカウントで各操作の瞬間だけ通信を落とす**手段が無いため、
  4 操作それぞれの失敗→表示→再試行を実機 e2e で通せていない。
- また [1] の「受信いいねが RPC 404 で無言で 0 のまま」は、条件7 の趣旨（無言で失敗しない）にも反する挙動。
- **足場の要望**: `-SameQForceOfflineToggle`（実行中に on/off できる Debug フラグ）か、
  「N 回目の書き込みだけ失敗させる」擬似フラグを足すと、条件6 後半（回復）と条件7 を毎回自動回帰にできる。
  self-review.md の提案3（`SprintTwelveOfflineAcceptanceTests` 新設）を実際にコミットまで持っていってほしい。

### 補足: 条件5（期限切れ非表示）は部分確認のまま
本番の `world_timeline` ビュー定義に `p.expires_at > now()` があることは SQL で確認。
ただし本番の全投稿が prompt_001 の `ends_at`（2026-08-27T23:07:38Z）に揃っており、`posts_one_per_prompt` 制約で
過去 `expires_at` の投稿を作れず、実データでの「期限切れ回答が1件も出ない」の観測は今回もできていない（eval-7 と同じ）。

## 確認できた受け入れ条件（合格しているもの）
| # | 条件 | 結果 | 根拠 |
|---|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに他人の回答として出る／入れ直しても読める | ✓ | `SprintTwelveEvalE2ETests` の条件1 assert がパス。curl e2e でも状態ゼロの新規クライアント C が端末A の固有マーカー投稿を `world_timeline` から取得（サーバーのみで成立＝再インストール相当を内包） |
| 2 | 同じ時刻に同じお題・残り時間 | ✓ | 全クライアントが `prompts` の時刻フィルタで `prompt_001`（同一 `ends_at`）を取得。お題は完全にサーバー駆動 |
| 4 | 通報・ブロックで即時非表示／相手に何も出ない | ✓ | curl e2e: 端末A が端末B の投稿を `reports` に INSERT（201, reason=other）した直後、端末A の `world_timeline` から当該投稿が消えた（`body=eq.<marker>` で 0 件）。端末A が端末D をブロック（`blocks` 201）した直後も端末D の投稿が端末A の `world_timeline` から消えた。相手へ通知・表示を出す経路はスキーマ・コードに無い |
| 6 | オフラインで「接続してください」相当が出る／回復後に入れ直さず戻れる | ✓ | `-SameQForceOffline` 起動で「読み込めませんでした」「通信できません。ネットワーク接続を確認してください。」＋「もう一度試す」を表示。白紙・無限スピナー・クラッシュにならず、retry で `start()` 再実行 |
| 8 | 同梱シードが通常操作から1件も出ない | ✓ | `SprintTwelveAcceptanceTests.test01` パス（Supabase 経路で seed 本文がタイムライン・画面に出ない）。Debug 既定が `SupabaseBackend`、seed は `LocalBackend` 経由のみ |

## データ整合性
- 端末A の投稿・端末B のいいね・端末A の通報・端末A のブロックはいずれも本番 DB に永続化され、
  別クライアントからの再取得で一致した。
- 条件3 の不具合は「書き込みが飛んでいない」わけではなく（`likes` 行は 201 で作成される）、
  「端末A がその行を数える経路（RPC 関数）が本番に存在しない」という配布漏れ。永続層自体の整合性は保たれている。

## 回帰（抜き取り）
| スプリント | スイート | 結果 |
|---|---|---|
| 09 | SprintNineAcceptanceTests | 7/7 |
| 10 | SprintTenAcceptanceTests | 7/7 |
| 11 | SprintElevenAcceptanceTests | 4/4 |
| 12 | SprintTwelveAcceptanceTests | 3/3 |
| — | SameQTests（ユニット） | 166/166 |

直近スプリントの受け入れ条件は attempt 11 の変更で壊れていない。

## 使用性
3点。オンボーディングは迷わず、お題待ち（空状態）・オフライン説明・各操作のエラーアラートは用意されている。
ただし条件3の「受信いいね」がサーバーに問い合わせできず（RPC 404）、いいねをもらっても画面が永久に無反応・エラーも無し、
という投稿者側の体験欠落が残る。主要動線（投稿して世界の回答を読む）は完走できるので下限は満たす。

## 改善提案（合否には影響しない）
1. マイグレーションの追記は「新規ファイル」で行う運用をルール化（適用済みファイルの改変は `db push` で無視される）。
2. `SprintTwelveEvalE2ETests` を CI 対象（generator の毎回のテスト実行対象）に含める。今リポジトリにあるのに attempt 11 では回されていない。
3. `refreshReceivedLikeCount()` の `catch` で、`SupabaseError.notFound` / PGRST202 のときだけ 1 度だけ `alertMessage` か
   Debug ログを出すと、「関数未適用」を無言にしない（条件7 の趣旨に沿う）。
4. `-SameQForceOfflineToggle`（実行中トグル）を足して条件6 の回復と条件7 の 4 操作を自動回帰に組み込む。
5. `liked_authors_view` は用途未定のまま。sprint 13 の「安全ログ可視化」とまとめて設計。

## 評価できなかったもの
- 条件3の「関数を本番へ適用した状態」での受信いいね +1 表示（関数が本番に無いため、修正の正否そのものを検証できない）。
- 条件7（4 操作の通信失敗時の表示と再試行）: 実行中に通信を落とす手段が無く実 e2e 未達。コードレビューのみ。
- 条件5（期限切れ回答の非表示）: 本番に期限切れ投稿を作れず、ビュー定義の確認に留まる（eval-7 と同じ）。
- スワイプ時の体感待ち時間（spec 注記）: 複数端末の実データ量での体感評価はしていない。
