# スプリント 13 評価（attempt 2） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 2/7（条件3・4のみ充足。条件5は機構のみ・未観測） | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0 / 未処理例外0。ただしアカウント削除が本番サーバに無反映のまま「成功」表示（無言の失敗） | クラッシュ0 / 未処理エラー0 / 主要動線完走 | ✗ |
| 3 データ整合性 | `delete_my_account` が本番で毎回 42883 → 削除がサーバに永続しない。`rate_limit_events` は 0 行のまま。BAN 行を本人が REST で `active` に戻せる | 100% | ✗ |
| 4 回帰 | ローカル: SameQTests 166/166・SprintThirteen 4/4・SprintFive 7/7・SprintEleven 4/4（全緑・TEST SUCCEEDED）。スプリント12「受信いいね +1」は `checkRateLimit` fail-open 化でクライアント側の throw が解消 | 100% | ✓ |
| 5 使用性の最低線 | like/report 失敗は画面表示。アカウント削除は成功したように見えるがサーバ未反映 | 3以上 | 3 |

**5基準中 3基準（1・2・3）が閾値未達。スプリント不合格。**

---

## 検証環境
- 対象: `.product/state.json` currentSprint=13 / attempt=2 / status=awaiting_eval（autoloop iteration 15 で生成）
- サーバ: 本番 Supabase `loqumzfgnahtclnvnrzb`（spec 前提どおり運用と同一環境）
- Supabase CLI 2.103.0（`supabase` ログイン済み・SameQ プロジェクト link 済み）
- シミュレータ: iPhone 17（iOS 26.5） / `xcodebuild test`（DerivedData `/tmp/SameQ_DD_eval13`）
- 直叩き検証: `/tmp/sameq_eval13/t.py` `t2.py` `t3.py`（匿名サインアップ + service_role で RLS バイパスの読み書き。使用アカウントは `DELETE /auth/v1/admin/users/<id>` で消去済み）
- 実行時刻: 2026-08-27 04:48–05:00 UTC / 13:48–14:00 JST
- Swift 単体デコード確認: `/tmp/sameq_eval13/dt.swift`

---

## 不合格の原因（これを直せば通る）

### [1] migration 7 が本番に一切適用されない（`comment on extension pg_cron` が無条件実行）— 最重要・全ての元凶

- **症状**: `supabase db push --linked` が migration 7 の適用中にエラーで停止し、
  ファイル全体がロールバックされる。
  ```
  Applying migration 20260827000007_server_enforcement_fixes.sql...
  ERROR: extension "pg_cron" does not exist (SQLSTATE 42704)
  At statement: 7
  comment on extension pg_cron is
      'sprint13 fix: pg_cron が有効なら、毎日 03:00 UTC に期限切れ safety logs を …'
  ```
- **再現手順**:
  1. `cd /Users/nakagawakeita/Products/iOSApp/SameQ`
  2. `supabase db push --linked --yes`
  3. → 上記 42704 で中断。`supabase migration list` で
     `20260827000007 | (空欄) ` のまま＝リモート未記録（ロールバック済み）
- **原因（確定）**: migration 7 セクション4 で、pg_cron の有無を判定する
  `do $$ … if exists(select 1 from pg_extension where extname='pg_cron') … $$;`
  ブロックは正しいが、その**直後の `comment on extension pg_cron is '…';`
  がガードの外**にある。本番プロジェクトに pg_cron 拡張が入っていないため
  この 1 文が SQLSTATE 42704 で失敗し、migration ファイル 1 本＝1 トランザクション
  ごと全部ロールバックされる。
- **影響**: migration 7 に入っている**修正が 3 つとも本番に乗らない**。
  - `consume_rate_limit` の予約語 `current_user` 修正（eval-1 [1]）が乗らない → 条件1 未達 + 副作用
  - `delete_my_account` の予約語修正（eval-1 [1]）が乗らない → 条件7 未達
  - `users_update_own` の USING に `status='active'` を足す修正（eval-1 [2]）が乗らない → 条件2 未達
  - migration 6 のファイルも generator が同じ修正で書き換えているが、
    migration 6 は eval-1 時点で**旧（バグ入り）定義のまま本番適用済み**であり、
    `supabase db push` は適用済み migration を再流さないため、ファイルを直しても
    本番の関数は旧定義のまま。
- **修正案**: `comment on extension pg_cron is …` を `do $$ … $$` ブロックの
  `if exists(...)` の中へ移す（`execute format('comment on extension pg_cron is %L', '…')`）、
  または単に削除する。加えて `perform cron.unschedule('purge-safety-logs-daily')`
  はジョブ未登録時に例外を投げるので `exception when others then null` で包むか
  `where exists(select 1 from cron.job where jobname=...)` にする。
- **根拠**: `supabase db push` 出力（本レポート冒頭）、`supabase migration list`
  の 000007 空欄、migration 7 ファイル 133–170 行。

### [2] `consume_rate_limit` が本番で毎回 SQLSTATE 42883（条件1・未達）

- **症状**: 認証済みで RPC を呼ぶと必ず HTTP 404 / `{"code":"42883",
  "message":"operator does not exist: uuid = name"}`。
- **再現手順**（`/tmp/sameq_eval13/t.py`）:
  1. `POST /auth/v1/signup`（anon key）でアクセストークン取得
  2. `POST /rest/v1/rpc/consume_rate_limit` body `{"p_action":"like","p_max":3,"p_window_seconds":60}`
  3. → 4 回連続で `42883 operator does not exist: uuid = name`
- **期待**: 条件1「連打制限がサーバー側の記録で判定され、再起動しても解除されない」。
  正常時は 0（通過）か 正の秒数（待機）を返し、`rate_limit_events` に行が増える。
- **実際**: [1] で migration 7 が乗らないため本番の関数は旧定義
  （`declare current_user uuid := auth.uid();`）のまま。`where user_id = current_user`
  が組み込み `current_user`（型 `name`）に束縛され `uuid = name` 演算子なしで失敗。
  `rate_limit_events` は 0 行のまま（サーバ側レート制限が 1 度も動かない）。
- **さらに**: attempt 2 で `SupabaseBackend.checkRateLimit` を fail-open 化
  （`SupabaseError.notFound` を握って 0 を返す・`async -> Int` で throw しない）
  したため、**アプリからの経路ではレート制限が完全に無効**になる。
  連打し放題（クラッシュはしないが条件1 の趣旨に真っ向から反する）。
- **修正案**: [1] を直して migration 7 を適用する。適用後に
  `consume_rate_limit` が 0 / 正の秒数を返し `rate_limit_events` に行が増えること、
  かつアプリ再起動を跨いで制限が継続することを 2 台で確認する。
- **根拠**: `/tmp/sameq_eval13/t.py` セクション1。

### [3] `delete_my_account` が本番で毎回 42883、アカウントが消えない（条件7・未達）

- **症状**: `POST /rest/v1/rpc/delete_my_account` body `{}` → HTTP 404 /
  `42883 operator does not exist: uuid = name`。
- **再現手順**（`/tmp/sameq_eval13/t.py` セクション2）:
  1. 匿名サインアップ（uid=X）
  2. `POST /rest/v1/rpc/delete_my_account`（X のトークン）→ 42883
  3. `GET /auth/v1/admin/users/X`（service_role）→ HTTP 200（ユーザーは**残っている**）
- **期待**: 条件7「アカウント削除を実行すると、他の端末のタイムラインから
  その人の回答が消え、削除後にスワイプを続けても 1 件も現れない」。
- **実際**: [1] と同じ予約語バグ。`SupabaseBackend.deleteAccount()` は
  `try? await client.rpcVoid(function:"delete_my_account")` で例外を握り潰し、
  ローカル state だけ消してオンボーディングに戻る。
  **アプリ上は「削除できた」ように見えるがサーバは無反応**（無言の失敗）。
  他端末の `world_timeline` には削除したはずの投稿が残り続ける。
- **修正案**: [1] を直して migration 7 を適用。適用後、端末Aで削除 → 端末Bの
  タイムラインから A の固有文面が消え、読み切りまで 1 件も出ないことを確認する。
- **根拠**: `/tmp/sameq_eval13/t.py` セクション2。

### [4] 停止アカウントが自分で BAN を解除できる（条件2・未達）

- **症状**: `users.status='banned'` にされたアカウントが、REST PATCH 1 回で
  `active` に戻せる。
- **再現手順**（`/tmp/sameq_eval13/t2.py`）:
  1. 匿名サインアップ + `public.users` 行作成（uid=X）
  2. service_role で `PATCH /rest/v1/users?id=eq.X` body `{"status":"banned"}` → 204
  3. X のトークンで `POST /rest/v1/rpc/current_user_status` → `"banned"`（ここは正しい）
  4. X のトークンで `PATCH /rest/v1/users?id=eq.X` body `{"status":"active"}`
     → **HTTP 200 / レスポンス body の status が `active`**
  5. service_role で読み直し → `status = "active"`（**復活してしまった**）
- **期待**: 条件2「アプリ側の起動オプションや設定操作だけでは、停止状態を
  作ることも解除することもできない」。
- **実際**: [1] で migration 7 が乗らないため `users_update_own` ポリシーは旧定義
  `USING (id = auth.uid())` / `WITH CHECK (id = auth.uid() AND status = 'active')`。
  WITH CHECK は「status を active 以外にする更新」だけを弾き、banned 行を
  active に戻す更新は CHECK を通過する。USING に status 条件が無いため
  banned 行も更新対象になる。
- **修正案**: [1] を直して migration 7（`USING (id = auth.uid() AND status = 'active')`）
  を適用。適用後、banned 行への PATCH が 0 件マッチ（または 403）になることを確認。
- **根拠**: `/tmp/sameq_eval13/t2.py` COND 2 セクション。

### [5] 期限切れ安全ログの「自動削除」が成立していない（条件6・未達）

- **症状**:
  - pg_cron 拡張が本番に無く（[1] のエラーがその証拠）、`purge-safety-logs-daily`
    スケジュールは登録されない。migration 7 の cron 登録ブロックはそもそも
    migration ごとロールバックされて未適用。
  - 残る自動経路は `AppSession.start()` の
    `try? await backend.purgeExpiredSafetyLogs()` のみ。これは
    `app_purge_expired_safety_logs()`（保持期間 30 日固定）を呼ぶだけで、
    **保持期間を短くして自動削除が走る様子を観測する手段が自動経路に無い**。
  - spec 評価者注記「『削除する仕組みが用意されている』だけでは合格にしない」
    「保持期間を短くした条件で自動削除が実際に走ることと、期間内のデータが
    消えていないことの両方を確認する」を満たせない。
- **参考**: `purge_expired_safety_logs(p_retention_seconds)` は
  `revoke all … from public` の記述に反し **authenticated から呼べてしまう**
  （`/tmp/sameq_eval13/t3.py` で `p_retention_seconds=60` を呼び HTTP 200 /
  戻り値 4＝本番 `reports` を 4 行削除）。手動なら短保持の削除は観測できるが、
  「自動」ではないうえ、任意ユーザーが `p_retention_seconds=0` で
  `reports` 全消しできてしまう別の欠陥でもある（F34 の趣旨に反する）。
- **期待**: 条件6「表示期限を過ぎた投稿は目安30日サーバー側に残り、期間を
  過ぎると自動で消える。運営側の確認手段で、期限切れ直後と保持期間経過後の
  2時点を検証できる」。
- **修正案**:
  1. [1] を直して migration 7 を適用可能にする（cron ブロックが走る前提を作る）。
  2. pg_cron を Supabase ダッシュボードで有効化し、`purge-safety-logs-daily` を
     登録する（ユーザー作業。generator/evaluator では拡張を有効化できない）。
  3. `purge_expired_safety_logs(int)` の grant を本当に service_role / postgres
     限定にする（現状 authenticated から実行可）。
  4. 検証用に「保持期間を短くした自動実行」を観測できる導線
     （例: 短保持のワンショット cron、または Debug 起動オプション経由の
     `app_purge_expired_safety_logs` に保持秒数を渡せる版）を用意する。
- **根拠**: `supabase db push` の 42704、`/tmp/sameq_eval13/t3.py`、
  `SameQ/Session/AppSession.swift` 222–231 行、
  `SameQ/Backend/SupabaseBackend.swift` 803 行付近。

---

## 受け入れ条件ごとの観測結果

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | 連打制限がサーバー側・再起動で解除されない | ✗ | `consume_rate_limit` が本番で毎回 42883。`rate_limit_events` 0 行。アプリ経路は fail-open で制限ゼロ（[2]） |
| 2 | BAN はサーバー `users.status` 判定・ローカルで切替不能 | ✗ | 停止検知（`current_user_status`）は動くが、banned 行を本人が REST PATCH で `active` に戻せた（HTTP 200・[4]） |
| 3 | 停止アカウントの回答が他端末に出ない | ✓ | `world_timeline` の `u.status='active'` は migration 4 由来で attempt 2 の変更対象外。eval-1 で banned→消える/unban→復活を確認済み。回帰なし |
| 4 | 既読がサーバー側 (`viewed_posts`) に記録 | ✓ | `my_viewed_posts()` RPC が HTTP 200 で自分の既読を返す（`/tmp/sameq_eval13/t.py`）。INSERT 経路は既存温存 |
| 5 | 端末時計をずらしても今日のお題と残り時間が同一 | △（機構のみ・未観測） | `SupabaseBackend.promptState()` が `clock.now` → `currentServerTime()`（RPC `current_server_time`）基準のフィルタに変更。RPC は本番で HTTP 200・サーバ時刻を返す。Swift の `.iso8601` デコードは小数秒付き `2026-…+00:00` を許容（`dt.swift` で確認、秒に丸め）。ただし2台+時計ずらしの実観測は未実施。debug overlay の「ends in Xs」は依然 `clock.now` 基準 |
| 6 | 期限切れ投稿の30日サーバー保持＋自動削除 | ✗ | pg_cron 無し・migration 7 の cron 登録は未適用。自動経路は起動時 `app_purge_expired_safety_logs()`（30日固定）のみで、短保持での自動削除を観測できない（[5]） |
| 7 | アカウント削除が他端末へ伝播 | ✗ | `delete_my_account` が本番で毎回 42883。削除後も `auth.users` にレコードが残る（[3]） |

充足: **2 / 7**（条件5 は機構実装のみで観測未達のため不充足扱い）

---

## 回帰（抜き取り4件）

| 対象 | 結果 |
|---|---|
| SameQTests（ユニット全体） | ✓ 166/166・0 失敗（5.9s） |
| SprintThirteenAcceptanceTests | ✓ 4/4（新規 test04 含む・87s） |
| SprintFiveAcceptanceTests（連打制限・BAN 挙動・ローカル） | ✓ 7/7（234s） |
| SprintElevenAcceptanceTests（アカウント削除・設定・ローカル） | ✓ 4/4（13.6s） |
| スプリント12 条件3（端末Bのいいね→端末Aの受信いいね +1・Supabase 経由） | ✓（コード/RPC レベル）`checkRateLimit` を `async -> Int` の完全 catch（fail-open）に変更。本番 `consume_rate_limit` が返す 404/PGRST202 は `SupabaseError.notFound` として握られ 0 を返す → `setLike(liked:true)`/`reportPost` が throw しなくなった。eval-1 で破損していた throw 経路は解消。※2台実機 UI E2E は未実施 |

`xcodebuild test` 総合 **TEST SUCCEEDED**（362 テストケース・0 失敗）。ローカル経路の回帰は無し。

---

## 改善提案（合否には影響しない）

1. **`purge_expired_safety_logs(int)` の実行権限**: `revoke all … from public` を
   書いているのに authenticated から実行できている（Supabase の関数自動公開が
   revoke を上書きしている疑い）。`security definer` かつ引数で保持期間 0 を
   渡せる関数を一般ユーザーが叩けるのは F34（安全ログ保持）に対する明確な穴。
   `alter default privileges` や明示的な `revoke execute … from authenticated, anon` で確実に閉じる。
2. **`delete_my_account` の無言失敗**: `SupabaseBackend.deleteAccount()` が
   `try?` で RPC 例外を捨てている。サーバ削除に失敗したらユーザーに
   「サーバ側の削除に失敗した。時間をおいて再実行」を出すべき（スプリント12
   条件7「無言で成功したように見えることがない」にも抵触）。
3. **migration の pg_cron 依存部を別ファイルへ**: generator 自身が self-review
   「提案3」で書いているとおり。cron 登録は `20260827000008_pg_cron_schedule.sql`
   に分離し、拡張有効化後にだけ流す。今回の全ロールバック事故を構造的に防げる。
4. **debug overlay の残り時間**: `debugStatusLine` の `prompt.endsAt.timeIntervalSince(now)`
   が `now = clock.now`。評価者が条件5 を overlay で確認する運用なら、ここも
   サーバ時刻基準（`serverNow + 経過`）にしないと「時計をずらすと残り秒数が動く」
   ように見える。

---

## 評価できなかったもの

- **2 台以上の実機/シミュレータでの UI E2E**（BAN 反転の画面遷移、連打制限の
  アプリ削除＆再インストール越し・端末時計進め、削除伝播の読み切り、
  時計ずらしでのお題同一性）は環境未整備のため未実施。
  ただし条件 1・2・6・7 は **本番サーバの事実**（RPC が 42883・RLS ポリシー定義・
  pg_cron 不在・migration 7 未適用）で決定的に不合格が確定しており、
  実機確認を待たず差し戻して問題ない。
- 条件5 は client 側の実装（`promptState` のサーバ時刻化）と RPC 稼働までは
  確認したが、「時計を数時間ずらした端末と正しい端末で今日のお題・残り時間が
  一致」の実観測は未実施。

---

## 評価者による本番への副作用（申し送り）

- `supabase db push --linked` を 1 回実行したが、migration 7 は 42704 で
  **全ロールバック**され本番スキーマは不変更（`supabase migration list` の
  000007 は空欄のまま）。
- 直叩き検証で作成した匿名アカウント（計 4 件程度）は
  `DELETE /auth/v1/admin/users/<id>`（service_role）で消去済み。
- `EVAL13-BANNED-VISIBILITY-PROBE` という本文の投稿を 1 件作成したが、
  作成者アカウントごと admin 削除したため cascade で消えている。
- **注意**: 条件6 の確認過程で `purge_expired_safety_logs(60)` を認証ユーザー
  トークンで 1 回呼び、本番 `public.reports` を **4 行削除**した
  （作成から 60 秒以上経過した通報記録）。これは意図せぬ破壊的副作用。
  今後の評価では service_role でロールバック付きトランザクション内でのみ
  この関数を検証すること。運用上、削除された 4 件は本来 30 日保持対象だった
  可能性がある点をユーザーに共有する。
