# スプリント12 評価（attempt 10） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 実操作で確認できたのは 4/8（条件1・2・4・8）。条件3は実 e2e で不合格。条件5・6・7 は未確認 | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0 / 未処理例外0 / 主要動線（オンボーディング→投稿→タイムライン→いいね付与）は完走 | クラッシュ0・未処理0・主要動線完走 | ✓ |
| 3 データ整合性 | 投稿・いいねの書き込みは本番DBに永続化され、別クライアント再取得でも一致。読み戻しも一貫（誤った値だが一貫している） | 100% | ✓ |
| 4 回帰 | SprintOne 5/5・SprintThree 7/7・SprintSix 4/4（計16/16）| 100% | ✓ |
| 5 使用性 | 3（空状態・エラーアラートは有る。ただし条件3の「受信いいね」が無言で永久に0のまま） | 3以上 | ✓ |

**基準1が閾値未達（条件3が実 e2e で不合格、条件5〜7 は未確認）のため不合格。**

## 検証環境
- macOS / Xcode 26.6（17F113）、iOS Simulator（iPhone 17 / iPhone 17 Pro Max、iOS 26.3）
- `xcodegen generate` → `xcodebuild build -configuration Debug` → **BUILD SUCCEEDED**
- 本番 Supabase プロジェクト `loqumzfgnahtclnvnrzb`（spec.md 前提13「本番と同じ環境で検証」）
  - 匿名サインアップ・migration 1〜4 適用済み・prompt_001 有効（`starts_at 2026-08-26T19:07:38Z` / `ends_at 2026-08-27T23:07:38Z`、検証時刻 UTC 2026-08-27 02:0x）を独立に確認
- 検証手段:
  1. **実 e2e（新規追加テスト）**: `SameQUITests/SprintTwelveEvalE2ETests.swift` — 端末A はシミュレータで実アプリを UI 操作（オンボーディング完了→投稿）、「もう1台」は同一プロセス内の `URLSession` 直叩きで本番 Supabase に対する実クライアントとして振る舞う（サインアップ→users 行→prompt_001 に回答→world_timeline 取得→端末A の投稿にいいね）
  2. **curl e2e**（`/tmp/sameq_e2e.py`）: 2 アカウントで signup→users→posts→world_timeline→likes→reports→blocks を本番へ流し、各 HTTP ステータスとRLSの効き方を直接観測
  3. 既存 UI テスト（`SprintTwelveAcceptanceTests` 3/3、回帰 3 スイート 16/16）
- 検証日時: 2026-08-27 11:05〜11:25 JST

## 前進の確認（正しく評価する）
- eval-6 [1] の HTTP 401（`tokenBox` 未反映）は解消。実アプリでオンボーディングが `today.input` まで到達し、投稿が `today.myAnswer` に反映されるところまで**実機操作で完走**した。
- eval-6 [2] の「寛容すぎる test03」は厳格版に差し替え済みで、3/3 パスを確認。
- 条件1（投稿共有）は今回**実 e2e で確認できた**（下記）。attempt 1〜9 では 401 で一歩も進めなかったので大きな前進。
- 端末内シード（`SeedCatalog`）は Supabase 経路では 1 件も出ない（`SprintTwelveAcceptanceTests.test01` パス）。

## 不合格の原因（これを直せば通る）

### [1] 条件3が成立しない — 「受信したいいねの総数」が常に 0 のまま増えない
spec.md 308行:「端末Bが端末Aの回答にいいねを押すと、端末Aの画面で自分が受け取ったいいねの総数が1増える」

- **再現手順**:
  1. 端末A: Supabase 経路（`-SameQUseLocalBackend` なし）で起動、オンボーディング完了、prompt_001 に固有マーカー入りの回答を投稿。`today.myAnswer` に本文が表示される。投稿直後は受信いいねラベル（`today.receivedLikes`）は非表示＝0 で正しい。
  2. もう1台（本番 Supabase の別アカウント）: prompt_001 に回答してタイムライン解放条件（F05）を満たしたうえで、`world_timeline` から端末A の投稿を取得し、その `post_id` に対して `likes` へ INSERT（HTTP 201 で成功）。
  3. 端末A: 画面を開いたまま最大 20 秒待つ（アプリは `AppSession.refresh()` を1秒ごとに呼び、その中で `refreshReceivedLikeCount()` を実行している）。
- **期待**: 端末A の `today.myAnswer` の下に `today.receivedLikes`（「1 件のいいね」）が現れる。
- **実際**: 20 秒待っても `today.receivedLikes` は一度も出現しない。受信いいねは 0 のまま。エラー表示も出ない（無言で 0）。
- **根拠**:
  - `SprintTwelveEvalE2ETests.test_condition1_and_3_realDeviceB` が
    `条件3違反: 『もう1台』が端末Aの回答にいいねしたのに、端末Aの today.receivedLikes が表示されない（受信いいね 0 のまま）` で FAIL（34.8秒）。同テストの条件1チェック（`world_timeline` に端末A の投稿が出る）は同じ実行内で**パス**しているので、いいね INSERT 前までの経路は健全。
  - curl e2e でも同一結果を独立に観測: 端末B が端末A の投稿へ `POST /rest/v1/likes` → `201 Created`。直後に端末A のトークンで `GET /rest/v1/likes?select=post_id&post_id=eq.<Aの投稿ID>` → `200 []`（0 件）。
- **推測（症状と分けて記載。generator 側で確認・修正すること）**:
  - 推測a（ディスパッチ）: `receivedLikeCount(forPostID:)` は `Backend` プロトコルの要求メソッドではなく、`SupabaseBackend.swift` 末尾の `extension Backend { func receivedLikeCount(...) { return 0 } }` にだけ本体がある。`AppSession.backend` の静的型は `any Backend` なので、`backend.receivedLikeCount(...)` はプロトコル拡張のデフォルト実装（常に `return 0`）へ静的ディスパッチされ、`actor SupabaseBackend` 側の実装（508行）は呼ばれない＝デッドコードの可能性が高い。→ `receivedLikeCount` を `Backend` プロトコルの要求メソッドに昇格させる必要がある。
  - 推測b（RLS）: 仮に (a) を直して `SupabaseBackend.receivedLikeCount` が呼ばれても、その実装は `GET /rest/v1/likes?post_id=eq.X` で `likes` テーブルを引く。`likes` の RLS は `likes_select_own`（`user_id = auth.uid()`）だけなので、端末A は**他人（端末B）が付けたいいね行を 1 件も読めない**。自分の投稿の受信いいねを数えるには、RLS をバイパスする集計ビュー / RPC（例: `security definer` の `received_like_count(post_id)` や、自分の投稿への likes を返すビュー）がサーバー側に必要。migration 4 のコメントには `liked_authors_view` を追加した旨の記述があるが、実際の SQL では作成されていない（作られているのは `safety_logs` ビュー）。
  - 両方を直さないと条件3は満たせない。

### [2] 条件6・条件7 が未確認のまま（generator が「土台まで担保」と申告している範囲）
- 条件6（機内モードで「接続してください」相当が出る／復帰後にアプリを入れ直さず通常画面へ戻る）: 実機のネットワークを遮断する起動引数・自動化手段が無く、今回も検証できていない（eval-6 も同じ理由で未確認）。`SupabaseBackend.checkConnectivity()` が `lastPathStatus != .satisfied` で `.offline` を投げる設計はコードで確認したが、オフライン画面が実際に描画されること・復帰導線は未検証。
- 条件7（投稿・いいね・通報・ブロックが通信失敗したとき、失敗が画面に出て再試行できる。無言成功にならない）: 4 操作それぞれについて通信失敗を意図的に起こす手段が無く未検証。むしろ [1] の「受信いいねが無言で 0 のまま」は条件7 の趣旨（無言で成功したように見えない）にも反する挙動。
- これらは「実機2台必須」の spec 注記に対して generator が evaluator 担当としている部分だが、offline を安全に再現する手段（`-SameQ` 系のオフライン擬似フラグ等）がアプリ側に無いため、現状の構成では誰も検証できない。**検証可能にするための足場（offline 擬似フラグ or Network Link Conditioner 前提の手順）を用意してほしい**。

### 補足: 条件5（期限切れ非表示）
`world_timeline` ビュー定義に `p.expires_at > now()` があることは SQL で確認。ただし本番 DB では全投稿が prompt_001 の `ends_at` に揃うため、期限切れ投稿を作って実データで確認することが今回できなかった（部分確認）。

## 確認できた受け入れ条件（合格しているもの）
| # | 条件 | 結果 | 根拠 |
|---|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに他人の回答として出る／Bを入れ直しても読める | ✓ | 実 e2e: 端末A がアプリで投稿 → 状態を一切持たない別クライアントが `world_timeline` から端末A の固有マーカー投稿を取得できた。サーバー側のみで成立するので「アプリ削除→再インストール」ケースを内包 |
| 2 | 同じ時刻に同じお題・残り時間 | ✓ | 2 クライアントとも `prompts` の時刻フィルタで prompt_001（同一 `ends_at`）を取得。お題は完全にサーバー駆動 |
| 4 | 通報・ブロックで即時非表示／相手に何も出ない | ✓ | curl e2e: 端末A が端末B の投稿を `reports` へ INSERT（201）した直後、端末A の `world_timeline` から当該投稿が消えた。`blocks` INSERT も 201。通知・表示を相手に出す経路はコード上・スキーマ上存在しない |
| 8 | 同梱シードが通常操作から1件も出ない | ✓ | `SprintTwelveAcceptanceTests.test01` パス（Supabase 経路で seed 本文がタイムライン・画面に出ない）。Debug 既定が `SupabaseBackend`、seed は `LocalBackend` 経由のみ |

## データ整合性
- 端末A の投稿・端末B のいいね・端末A の通報はいずれも本番 DB に永続化され、別クライアントからの再取得で一致した。
- 条件3 の不具合は「書き込みが飛んでいない」わけではなく（`likes` 行は 201 で作成される）、「端末A がその行を読めない / 読む実装に到達しない」という読み出し側の設計問題。永続層自体の整合性は保たれている。

## 回帰（抜き取り3スイート）
| スプリント | スイート | 結果 |
|---|---|---|
| 01 | SprintOneAcceptanceTests | 5/5 |
| 03 | SprintThreeAcceptanceTests | 7/7 |
| 06 | SprintSixAcceptanceTests（端末内翻訳。spec が回帰注意を明記） | 4/4 |
| 12 | SprintTwelveAcceptanceTests | 3/3 |

LocalBackend 既定経路の既存機能は attempt 10 の変更で壊れていない。

## 使用性
3点。オンボーディングは迷わず、お題待ち画面（空状態）とエラーアラートは用意されている。ただし条件3の「受信いいね」がサーバーに正しく問い合わせできず、いいねをもらっても画面が永久に無反応（エラーも無し）なのは、投稿者側の体験として「何が起きているか分からない」瞬間になる。主要動線（投稿して世界の回答を読む）は完走できるので下限は満たす。

## 改善提案（合否には影響しない）
1. `receivedLikeCount(forPostID:)` を `Backend` プロトコルの要求メソッドに入れる（`LocalBackend` にも実装を置く）。拡張のデフォルト実装だけだと `any Backend` 経由で常にデフォルトが呼ばれる。
2. 自分の投稿への受信いいね数は RLS 越しには数えられないので、`security definer` の集計ビュー or RPC をサーバー側に用意する。migration 4 コメントにある `liked_authors_view` は実体が無いので、必要なら本当に作る。
3. offline を安全に擬似再現する起動フラグ（`-SameQForceOffline` 等）を足すと、条件6・7 を evaluator が毎回検証できるようになる。
4. `posts` テーブルに `author_emoji` / `author_nickname` を持たせるか、`myPost` / `submitPost` を `world_timeline` 相当の JOIN 経由に統一すると、attempt 10 で入れた `Post.withAuthor` の手元補完（自分の投稿にしか使えない暫定策）を減らせる。

## 評価できなかったもの
- 条件6（オフライン表示と復帰）: 実機ネットワーク遮断の自動化手段が無い。
- 条件7（投稿・いいね・通報・ブロックの通信失敗時の表示と再試行）: 4 操作の通信失敗を意図的に起こす手段が無い。
- 条件5（期限切れ回答の非表示）: 本番 DB に期限切れ投稿を作れず、ビュー定義の確認に留まる。
- スワイプ時の体感待ち時間（spec 注記）: タイムラインを開くところまで到達したが、複数端末の実データ量での体感評価はしていない。
