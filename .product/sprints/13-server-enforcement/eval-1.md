# スプリント 13 評価（attempt 1） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 2/7（条件3・4のみ充足） | 100% | ✗ |
| 2 動作の安定性 | ローカル suite はクラッシュ0。ただし本番(Supabase)バックエンドでは いいね/通報が毎回スロー、アカウント削除がサーバ無反映 | 未処理エラー0 / 主要動線完走 | ✗ |
| 3 データ整合性 | `rate_limit_events` が一切書かれない、アカウント削除がサーバに永続しない | 100% | ✗ |
| 4 回帰 | スプリント12 受け入れ条件3（受信いいね +1）が破損（Supabase 経由で like 不能） | 100% | ✗ |
| 5 使用性の最低線 | like/report 失敗は画面表示される。削除は成功したように見える | 3以上 | 3 |

**5基準中 4基準が閾値未達。スプリント不合格。**

## 検証環境
- 端末: iPhone 17 シミュレータ (iOS 26.5) / xcodebuild test（DerivedData `/tmp/SameQ_DD`）
- サーバ: 本番 Supabase `loqumzfgnahtclnvnrzb`（spec 前提のとおり運用と同一環境）
- **評価者が `supabase db push` で migration `20260827000006_server_enforcement.sql` を本番へ適用済み**（self-review の手順どおり。適用前は全 RPC が PGRST202）。
- 直叩き検証スクリプト: `/tmp/sameq_e2e/e2e.py` `/tmp/sameq_e2e/e2e2.py` `/tmp/sameq_e2e/inv.py`（匿名サインアップ2〜3アカウント＋DB プーラ直結 `psycopg2` で観測。使用後アカウントは `delete from auth.users` で消去済み）
- 実行時刻: 2026-08-27 04:24–04:35 UTC / 13:23–13:35 JST
- ローカルテスト: `SameQTests` 166/166、`SprintThirteenAcceptanceTests` 3/3、`SprintTwelveAcceptanceTests` 3/3、`SprintElevenAcceptanceTests` 4/4、`SprintFiveAcceptanceTests` 7/7、`SprintThreeAcceptanceTests` 7/7、全 24 UI テスト 0 失敗（650s）。
  ※ これらは全て `-SameQUseLocalBackend`。Supabase 経路の RPC は 1 件も踏まない。

## 受け入れ条件ごとの観測結果

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | 連打制限がサーバ側・再起動で解除されない | ✗ | `consume_rate_limit` RPC が毎回 SQL エラーで 404 |
| 2 | BAN はサーバ `users.status` 判定・ローカルで切替不能 | ✗ | 停止検知は動くが、**停止されたアカウントが REST 1発で自分の BAN を解除できる** |
| 3 | 停止アカウントの回答が他端末に出ない | ✓ | `world_timeline` が `u.status='active'` で除外。banned で消え、unban で復活を確認 |
| 4 | 既読がサーバ側 (`viewed_posts`) に記録 | ✓ | `viewed_posts` 行が入り、`my_viewed_posts()` がアカウント単位で返す |
| 5 | 端末時計をずらしても今日のお題と残り時間が同一 | ✗ | `SupabaseBackend.promptState()` が端末時計 (`clock.now`) で `prompts` を絞る |
| 6 | 期限切れ投稿の30日サーバ保持＋自動削除 | ✗ | 関数ロジックは正しいが、cron も app 呼び出しも無く**自動実行が存在しない** |
| 7 | アカウント削除が他端末へ伝播 | ✗ | `delete_my_account` RPC が毎回 SQL エラー。サーバ側は何も消えない |

充足: **2 / 7**

---

## 不合格の原因（これを直せば通る）

### [1] `consume_rate_limit` と `delete_my_account` が予約語 `current_user` の誤用で毎回 SQL エラー（最重要）

- **症状**: 本番の両 RPC を認証済みで呼ぶと必ず HTTP 404 / SQLSTATE 42883
  `operator does not exist: uuid = name`
- **再現手順**:
  1. 匿名サインアップしてアクセストークンを得る（`POST /auth/v1/signup`）
  2. `POST /rest/v1/rpc/consume_rate_limit` body `{"p_action":"like","p_max":3,"p_window_seconds":60}`
  3. → `{"code":"42883","message":"operator does not exist: uuid = name","hint":"You might need to add explicit type casts."}`（6回連続で同じ）
  4. `POST /rest/v1/rpc/delete_my_account` body `{}` → 同じ 42883
- **原因（推測ではなく確定）**: 両関数が
  `declare current_user uuid := auth.uid();` と宣言している。`current_user` は
  PostgreSQL の**予約キーワード**で、`where user_id = current_user` /
  `insert into rate_limit_events (user_id, action) values (current_user, ...)` /
  `delete from public.users where id = current_user` の位置ではローカル変数では
  なく組み込みの `current_user`（現在ロール名、型 `name`）に束縛される。
  よって `uuid = name` の演算子が無く実行時エラー。
  関数定義を `pg_get_functiondef` で確認済み。
- **影響**:
  - 条件1 = 未達（サーバ側レート制限が 1 度も走らない。`rate_limit_events` は 0 行のまま）
  - 条件7 = 未達（`delete_my_account` が常に失敗。`auth.users`/`public.users`/`posts` が残り、他端末の `world_timeline` に削除したはずの投稿が出続ける）
  - **回帰**: `SupabaseBackend.setLike`（`liked==true`）と `reportPost` は
    先頭で `let retry = try await checkRateLimit(...)` を呼び、この RPC 例外を
    そのまま throw する（`checkRateLimit` に catch は無い）。
    → **Supabase バックエンドではいいね・通報が毎回失敗する**。
    スプリント12 受け入れ条件3（端末Bがいいね→端末Aの受信数 +1）が成立しない。
  - `SupabaseBackend.deleteAccount()` は `try? await client.rpcVoid(...)` で
    例外を握り潰し、ローカル state だけ消す。
    → アプリ上は「削除できた」ように見えるが**サーバは無反応**（無言の失敗）。
- **修正案**: 両関数のローカル変数 `current_user` を予約語でない名前
  （例 `v_uid` / `caller_id`）へ全置換する。migration を修正して push し直す。
- **根拠**: `/tmp/sameq_e2e/e2e2.py` 実行ログ（C1 / C7 セクション）、
  `pg_get_functiondef(oid)` の出力（本レポート冒頭の inv 実行）。

### [2] 停止されたアカウントが自分で BAN を解除できる

- **症状**: `users.status='banned'` にされたアカウントが、通常の REST PATCH 1 回で `active` に戻せる。
- **再現手順**:
  1. アカウント A を作成。運営操作相当で `update public.users set status='banned' where id=A`
  2. A のトークンで `current_user_status()` → `"banned"`（ここは正しい）
  3. A のトークンで `PATCH /rest/v1/users?id=eq.<A>` body `{"status":"active"}`
  4. → HTTP 204。`select status from public.users where id=A` → **`active`**
- **期待**: spec 条件2「アプリ側の起動オプションや設定操作だけでは、停止状態を
  作ることも**解除することもできない**」。解除できてはならない。
- **実際**: `users_update_own` ポリシーは
  `USING (id = auth.uid())` /
  `WITH CHECK (id = auth.uid() AND status = 'active')`。
  `WITH CHECK` は「status を active 以外にする更新」を弾くだけで、
  banned 行を active に戻す更新は CHECK を通過してしまう。
  USING 側に status 条件が無いため banned 行も更新対象になる。
- **修正案**: `USING (id = auth.uid() AND status = 'active')` にして、
  banned 行はオーナーからは一切 UPDATE 不能にする（emoji/nickname 変更も
  停止中は不可になるが、条件2 を満たすにはこれが素直）。
- **根拠**: `/tmp/sameq_e2e/e2e.py` 実行ログ 2e、`/tmp/sameq_e2e/e2e2.py` C2。

### [3] お題の有効期間判定が端末時計依存（条件5）

- **症状**: `SupabaseBackend.promptState()` が
  `let now = clock.now` を使って
  `prompts?starts_at=lte.<端末時刻>&ends_at=gt.<端末時刻>` で今日のお題を絞る。
  サーバの `now()` は使わない。
- **再現手順（REST でクライアントの挙動を再現）**:
  - `starts_at<=T & ends_at>T` を満たす prompt を問い合わせる
  - T = サーバ現在時刻 → `["prompt_001"]`
  - T = サーバ現在 +26h → `[]`（＝アプリは「お題なし」→ `.waiting` 画面へ）
  - T = サーバ現在 −26h → `[]`
  - 現行 prompt_001 の窓は 2026-08-26 19:07 〜 2026-08-27 23:07 UTC（約28時間）と
    広いので「数時間」のズレでは境界を跨がないが、通常の約24時間運用のお題では
    数時間のズレで境界を跨ぎ、表示されるお題が変わる／消える。
- **期待**: 条件5「端末の時計を数時間ずらしても、表示される今日のお題とその
  残り時間は、時計が正しい端末と同一」。
- **実際**: お題の解決に端末時計を使うため、境界を跨ぐズレで別のお題／お題なしに
  なる。`AppSession` の残り時間算出（`prompt.endsAt.timeIntervalSince(now)` /
  `now = clock.now`）も端末時計基準。
  ※ 「期限切れの回答が読める」「未開始のお題に答えられる」の危険側は
  `world_timeline.expires_at > now()` と `posts_insert_own` /
  トリガの `starts_at<=now() and ends_at>now()` でサーバ担保されているため
  そこは破れていない。破れているのは「表示されるお題と残り時間の同一性」。
- **修正案**: 今日のお題の解決をサーバ側へ寄せる（`now()` で絞る view か RPC を
  用意して `promptState()` はそれを読むだけにする）、もしくは
  `current_server_time()` を起点に `AppClock` を駆動して残り時間もサーバ時刻基準にする。
  `current_server_time()` RPC は用意済みだが解決経路で使われていない。
- **根拠**: `SameQ/Backend/SupabaseBackend.swift` `promptState()`（`let now = clock.now`）、
  `/tmp/sameq_e2e/e2e2.py` C5 出力。

### [4] 期限切れ安全ログの自動削除が存在しない（条件6）

- **症状**: `purge_expired_safety_logs(retention)` 関数のロジックは正しい
  （ロールバック付きトランザクションで検証: 40日前の通報は消え、3日前は残る。
  retention=1秒にすると両方消える）。しかし**これを自動で叩くものが無い**。
  - `pg_extension` に `pg_cron` 無し、`cron.job` テーブル無し
  - `SupabaseBackend` に purge 呼び出し無し（grep で 0 件）。
    `app_purge_expired_safety_logs()` は authenticated に grant 済みだが誰も呼ばない
- **期待**: 条件6「期間を過ぎると自動で消える（…期限切れ直後と保持期間経過後の
  2時点を検証できる）」。spec 評価者注記「『削除する仕組みが用意されている』
  だけでは合格にしない」。
- **修正案**: pg_cron を有効化して
  `select cron.schedule('purge-safety-logs-daily','0 3 * * *',$$select public.purge_expired_safety_logs(30*24*60*60)$$);`
  を1回流す（Supabase ダッシュボードでの拡張有効化が要る）。または
  Supabase Scheduled Function / Edge Function cron。加えて（保険として）
  アプリ起動時に `app_purge_expired_safety_logs()` を呼ぶ。
  「短い保持期間で自動削除が実際に走る」ことを観測できる状態にする。
- **根拠**: `/tmp/sameq_e2e/e2e2.py` C6、`/tmp/sameq_e2e/inv.py`。

---

## 回帰（抜き取り3件以上）

| 対象 | 結果 |
|---|---|
| スプリント12 条件3（端末Bのいいね→端末Aの受信いいね +1） | ✗ **破損**。Supabase 経由の `setLike(liked:true)` が `checkRateLimit` の 404 例外を throw。いいねが1件も打てない |
| スプリント11 条件（アカウント削除後、他ユーザーの TL にその人の回答が出ない） | ✗ 未達のまま。スプリント13 で `delete_my_account` により解消を狙ったが RPC が壊れており、サーバは削除しない（TL に残り続ける） |
| スプリント05（いいね・通報の連打制限、BAN 挙動） | △ LocalBackend 経路は温存され `SprintFiveAcceptanceTests` 7/7 緑。Supabase 経路は `reportPost` が [1] で毎回 throw |
| スプリント03（既読の回答が再表示されない） | ✓ `SprintThreeAcceptanceTests` 7/7 緑 |
| スプリント12 受け入れ（オンボーディング/オフライン表示など） | ✓ `SprintTwelveAcceptanceTests` 3/3、`SprintThirteenAcceptanceTests` 3/3 緑 |

新規機能のためにスプリント12 のいいね動線が壊れている。回帰基準は未達。

---

## 改善提案（合否には影響しない）

1. `checkRateLimit` の doc コメントは「通信失敗時は fail-open で 0 を返す」と
   書いているが、実装に catch が無く throw する。コメントか実装のどちらかを
   合わせる。RPC 障害時にいいねが全滅する現状は fail-open にすべき。
2. `delete_my_account` は `security definer` で `auth.users` を消すが、
   `reports.post_id` は `on delete cascade`、`reports.reporter_id` も cascade。
   削除ユーザーの投稿に対する**他人の通報**は post 削除で連鎖消滅する。
   F34（安全ログ保持）と衝突しないか一度整理を（削除ユーザー分の通報を
   30日残す要件があるなら cascade を見直す）。
3. `current_server_time()` の戻りは PostgREST がマイクロ秒付き ISO8601 を返す。
   `SupabaseClient.decode` は `.iso8601`（小数秒非対応）なので、この RPC を
   実経路で使うならデコード戦略を小数秒対応にする必要がある。
4. `SprintThirteenAcceptanceTests` は 3 本とも LocalBackend で、
   サーバ RPC を 1 つも検証しない。最低限、CI で本番 or ローカル Supabase に
   対して `consume_rate_limit` / `delete_my_account` / `current_user_status` を
   叩く smoke を足すと、今回の 42883 は generator 段階で捕まる。

## 評価できなかったもの

- 物理2台実機での UI E2E（BAN 反転の画面遷移、連打制限のアプリ削除＆再インストール
  越し、削除伝播の読み切り）は環境未整備のため未実施。ただし上記 [1][2][4] と条件5・7 は
  サーバ側の事実（RPC 実行結果・RLS・スケジューラ有無）で決定的に不合格が確定するため、
  実機確認を待たず差し戻して問題ない。
- 「アプリ削除→再インストールで連打制限が回避できないか」は、
  セッション（access/refresh トークン）が Keychain ではなく
  Application Support の `state.json` に保存される実装のため、再インストールで
  新しい匿名アカウントになり制限はリセットされる。条件1本文（再起動）の範囲外だが、
  spec 評価者注記が求める「アプリを削除して入れ直す」でも回避不可、は
  現アーキテクチャでは満たせない。まず [1] を直してから別途方針を要検討。

## 評価者による本番への副作用（申し送り）

- 評価の過程で migration `20260827000006_server_enforcement.sql` を
  **本番 Supabase へ適用済み**（`supabase db push`）。追加専用・冪等で
  現行出荷ビルド（スプリント12）はこれらの RPC を呼ばないため即時の影響は無い。
  ただし壊れた関数（`consume_rate_limit` / `delete_my_account`）が本番に存在する
  状態なので、[1] の修正 migration を早めに push すること。
- 検証用に作成した匿名アカウント・投稿・いいね・既読・`rate_limit_events` は
  スクリプト終了時に `delete from auth.users`（cascade）で消去済み。
  `reports` への書き込みはロールバック付きトランザクション内のみで本番行は不変更。
