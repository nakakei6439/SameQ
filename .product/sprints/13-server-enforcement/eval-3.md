# スプリント 13 評価（attempt 3） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 条件3・4・7 は観測で充足。条件1・2・5 は RPC/機構は稼働・配線済みだが2台+再起動/時計ずらしの実観測は未達。**条件6 は不成立（本番で自動削除が1つも動かず、アプリ経由の清掃経路が attempt 3 の migration 8 で新たに壊れた）** | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0 / 未処理例外0。Supabase 経路で起動〜投稿〜タイムライン〜受信いいねが完走（実 e2e で確認）。`app_purge_expired_safety_logs()` が毎起動で HTTP 403 を返すが fail-open で握られUI影響なし | クラッシュ0 / 未処理エラー0 / 主要動線完走 | ✓ |
| 3 データ整合性 | 投稿・いいね・既読・アカウント削除が本番サーバに永続し、別クライアントからの再読込でも一致（world_timeline 69→68、my_viewed_posts に行が残る 等を観測） | 100% | ✓ |
| 4 回帰 | ユニット 170/170・SprintThirteen 4/4・SprintEleven 4/4・SprintFive 7/7・SprintTwelve 実 Supabase e2e 1/1。すべて TEST SUCCEEDED | 100% | ✓ |
| 5 使用性の最低線 | 主要動線完走。連打制限失敗は画面表示。アカウント削除失敗時は alertMessage で通知（無言成功なし）。BAN 用のアプリ内画面は増えていない | 3以上 | 4 |

**5基準中 基準1 が閾値未達（条件6 が不成立）。スプリント不合格。**

---

## 検証環境
- 対象: `.product/state.json` currentSprint=13 / attempt=3 / status=awaiting_eval（commit b0652a1）
- サーバ: 本番 Supabase `loqumzfgnahtclnvnrzb`（spec 前提どおり運用と同一環境）
- Supabase CLI 2.103.0。`supabase db push --linked --password …` で **migration 7・8 を本番へ適用**（eval-2 時点では両方リモート未記録 → 適用後 `supabase migration list` で 20260827000007・20260827000008 とも Remote に記録されたことを確認）。**eval-2 [1]（migration 7 の pg_cron 起因ロールバック）は解消**
- シミュレータ: iPhone 17（iOS 26.5）/ `xcodebuild test-without-building`（DerivedData `/tmp/SameQ_DD_eval13a`）
- 直叩き検証: `/tmp/sameq_eval13a/t.py`（匿名サインアップ + 各 RPC）、`/tmp/sameq_eval13a/t7.py`（A/B 2クライアントでの削除伝播・既読・timeline）
- 実行時刻: 2026-08-27 05:14–05:24 UTC / 14:14–14:24 JST（`current_server_time` RPC で確認、prompt_001 は 23:07 UTC まで active）

---

## eval-2 の 5 ブロッカーの検証結果

| eval-2 | 内容 | attempt 3 の状態 |
|---|---|---|
| [1] | migration 7 が pg_cron 起因で全ロールバック | **解消**。`comment on extension pg_cron` を do ブロック内 `execute format` に移動。`supabase db push` で 7・8 とも適用され、`consume_rate_limit`/`delete_my_account`/`users_update_own` の修正が初めて本番に乗った |
| [2] | `consume_rate_limit` が毎回 SQLSTATE 42883 | **解消**。`t.py` で `p_action=like,p_max=3,window=60` を5連打 → `0,0,0,60,60`（HTTP 200）。`rate_limit_events` に記録される構造 |
| [3] | `delete_my_account` が毎回 42883・アカウント消えない | **解消**。`t.py` で HTTP 204 → 直後 `current_user_status`=`"missing"`、`GET /users?id=eq.<uid>`=`[]`。`t7.py` で A 削除後に B の world_timeline から A の投稿が消える（69→68 行、marker 一致行 1→0） |
| [4] | 停止アカウントが自分で BAN 解除できる | **機構修正済み（部分観測）**。`users_update_own` を `USING (id=auth.uid() AND status='active')` に再作成。`t.py` で本人トークンから `PATCH /users {status:banned}` → HTTP 403 `42501 new row violates row-level security policy`。banned→active の完全再現は service_role で banned 行を作る必要があり未実施だが、USING に `status='active'` が入ったため banned 行は UPDATE 対象から外れる |
| [5] | 期限切れ安全ログの「自動削除」が不成立 | **未解消（悪化）**。下記 [1] を参照 |

---

## 不合格の原因（これを直せば通る）

### [1] 条件6: 本番で期限切れ安全ログの「自動削除」が1つも動かない。attempt 3 の migration 8 でアプリ経由の清掃経路が新たに壊れた — 最重要

- **症状**:
  1. `app_purge_expired_safety_logs()` を認証ユーザーのトークンで呼ぶと **HTTP 403 /
     `{"code":"42501","message":"purge_expired_safety_logs is restricted to service role"}`**。
     アプリは起動ごとにこの RPC を呼ぶ（`AppSession.start()` 232 行 →
     `SupabaseBackend.purgeExpiredSafetyLogs()` 828 行 → RPC `app_purge_expired_safety_logs`）が、
     `try?` で握られ常に 0 件・no-op になる。**eval-2 が「自動経路は起動時
     `app_purge_expired_safety_logs()`（30日固定）のみで動く」と認めていた唯一の
     フォールバックが、今回で完全に死んだ。**
  2. `purge_expired_safety_logs(60)` / `purge_expired_safety_logs()` を認証トークンで呼ぶと
     HTTP 403 `42501 permission denied for function`（migration 8 で anon/authenticated から
     execute 剥奪済み）。
  3. pg_cron 拡張は本番で有効化されていない（self-review「弱点2」で generator 自身が明言）。
     migration 7 の cron 登録ブロックは `if exists (select 1 from pg_extension where
     extname='pg_cron')` の中にあり、拡張が無いので **スケジュールは登録されない**。
- **再現手順**:
  1. `cd /Users/nakagawakeita/Products/iOSApp/SameQ`
  2. `supabase db push --linked --password '<SUPABASE_DB_PASSWORD>' --yes`（migration 7・8 適用）
  3. `python3 /tmp/sameq_eval13a/t.py` の `--- app_purge_expired_safety_logs (authed) ---` 行
     → `HTTP 403 -> {"code":"42501", ... "restricted to service role"}`
- **原因（確定）**: migration 8 の `purge_expired_safety_logs(int)` 冒頭に
  `if auth.uid() is not null then raise exception … using errcode='42501'` を追加した。
  `app_purge_expired_safety_logs()` は SECURITY DEFINER だが、その内側で
  `auth.uid()` は依然 **呼び出し元 JWT の sub** を返す（SECURITY DEFINER は実行ロールを
  変えるだけで `request.jwt.claims` GUC はクリアしない）。よってラッパ経由でも
  `auth.uid() is not null` が真になり、必ず 42501 で弾かれる。
- **spec 評価者注記との齟齬**: 「『削除する仕組みが用意されている』だけでは合格に
  しない」「保持期間を短くした条件で自動削除が実際に走ることと、期間内のデータが
  消えていないことの両方を確認する」。attempt 3 は
  (a) 自動で走る経路をゼロにし、
  (b) `p_retention_seconds < 86400` を関数レベルで拒否したため「保持期間を短くした
  条件」の観測手段も奪った。**条件6 は観測不能かつ不成立**。
- **期待**: 保持期間を短くした状態で自動削除ジョブが走り、期限内の通報は残り
  期限切れの通報だけが消えることを、運営手段で2時点観測できる。
- **修正案**:
  - `app_purge_expired_safety_logs()`（またはそれに相当する起動時オンデマンド清掃）は
    `auth.uid() is not null` ガードに触れない実装にする。例えば削除ロジックを
    `app_purge_expired_safety_logs()` 本体に直書きし（保持30日固定・引数なしなので
    `p_retention_seconds=0` 穴は元々存在しない）、`purge_expired_safety_logs(int)` は
    service_role 専用の運用関数として分離する。
  - 「自動で走る」経路を実際に用意する: pg_cron を有効化して schedule を別 migration
    （拡張 ON 後にだけ流す）で登録する手順を README + 申し送りに明記するか、
    Supabase Scheduled Edge Function を実装する。関数の存在だけでは spec を満たさない。
  - 検証用に「短い保持期間での自動削除」を運営手段で観測できる導線を残す
    （service_role 経由で保持秒数を指定でき、ロールバック可能なトランザクション内で
    確認できる形など）。
- **根拠**: `/tmp/sameq_eval13a/t.py` の app_purge_* / purge_* 各行、
  `supabase/migrations/20260827000008_server_enforcement_critical_fixes.sql` 130–165 行、
  `SameQ/Backend/SupabaseBackend.swift` 828–848 行、`SameQ/Session/AppSession.swift` 232 行、
  self-review.md「自分で見つけた弱点 2」。

### [2] 条件1・2・5 は機構は載ったが、spec 必須の「2台以上での観測」が未達

- **症状**: RPC（`consume_rate_limit` / `current_user_status` / `current_server_time`）は
  本番で HTTP 200 を返し、`SupabaseBackend` に配線済み。ただし
  - 条件1「アプリを終了/削除して再起動しても連打制限が解除されない」
  - 条件2「運営手段で停止 → 端末が使えない画面／アプリ操作では停止も解除もできない」
  - 条件5「端末の時計を数時間ずらしても今日のお題と残り時間が同一」
  の **実機2台・アプリ再起動・端末時計ずらしでの観測** は本評価でも実施できていない
  （評価環境に実機2台と設定アプリ操作系が無い）。
- **期待**: spec 評価者注記が「2台以上での検証を必須」「アプリを削除して入れ直す・
  端末の時計を進めるでも回避できないことまで試す」と明記。
- **実際**: サーバ側の事実（`rate_limit_events` 永続・RLS ポリシー定義・
  `current_server_time` 稼働）は確認済みだが、UI を伴う端末跨ぎの回避不能性は
  未観測。条件6 が確定不合格のため本スプリントの合否はこれを待たずに決まるが、
  次 attempt が合格するには 2台実機での観測が必要。
- **根拠**: `/tmp/sameq_eval13a/t.py`（RPC 稼働）、`SameQ/Backend/SupabaseBackend.swift`
  505/598/749/790/805 行（配線）、eval-2「評価できなかったもの」と同じ環境制約。

---

## 受け入れ条件ごとの観測結果

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | 連打制限がサーバ側・再起動で解除されない | △（機構のみ） | `consume_rate_limit` が本番で `0,0,0,60,60`（HTTP 200）。`rate_limit_events` にイベントが積まれる構造。アプリは `checkRateLimit` 経由で呼ぶ。2台+アプリ削除+時計進めの実観測は未達 |
| 2 | BAN はサーバ `users.status` 判定・ローカルで切替不能 | △（機構のみ） | `users_update_own` を `USING (…AND status='active')` に再作成（本番適用済み）。本人トークンからの `PATCH {status:banned}` は 403 で拒否。service_role で banned 行を作っての banned→active 完全再現は未実施。BAN 用アプリ内画面は増えていない（確認済み） |
| 3 | 停止アカウントの回答が他端末に出ない | ✓ | `world_timeline` の `u.status='active'` は migration 4 由来で本 attempt の変更対象外。`t7.py` で B が world_timeline を正常に読めることを確認、フィルタ健在 |
| 4 | 既読がサーバ側 (`viewed_posts`) に記録 | ✓ | `t7.py` で B が `POST /viewed_posts` → `my_viewed_posts()` RPC が当該 post_id を返す。サーバ側にアカウント単位で既読が残る |
| 5 | 端末時計をずらしても今日のお題と残り時間が同一 | △（機構のみ） | `current_server_time()` が本番でサーバ時刻を返す。`AppSession.start()` が `serverNowOffset` を確定し `debugStatusLine` の `srv`/`ends in Xs` をサーバ時計基準に変更。実機で時計を数時間ずらしての観測は未達 |
| 6 | 期限切れ投稿の30日保持＋自動削除 | ✗ | pg_cron 無効・cron 登録されず。起動時 `app_purge_expired_safety_logs()` は認証ユーザーに 42501 を返し常に no-op（attempt 3 の migration 8 が導入した `auth.uid() is not null` ガードがラッパ経由でも発火）。短保持での自動削除も観測不能（[1]） |
| 7 | アカウント削除が他端末へ伝播 | ✓ | `t7.py`: A 投稿 → B の world_timeline に出現（69行, marker一致1）→ A が `delete_my_account`（204）→ B 再読込で消滅（68行, marker一致0）。`current_user_status`→`missing`、`users` 行も消滅。cascade 動作を確認。アプリの削除UI経路（`try` 化で無言失敗なし）は data 層で担保、UI e2e は未実施 |

充足: **3 / 7 を観測で確認**（1・2・5 は機構のみ、6 は不成立）

---

## 回帰（抜き取り）

| 対象 | 結果 |
|---|---|
| SameQTests（ユニット全体・`ServerEnforcementTests` 4 新規含む） | ✓ 170/170・0 失敗（5.9s） |
| SprintThirteenAcceptanceTests | ✓ 4/4（13.6s） |
| SprintElevenAcceptanceTests（アカウント削除・設定・ローカル） | ✓ 4/4（87s） |
| SprintFiveAcceptanceTests（連打制限・BAN・連投拒否・ローカル） | ✓ 7/7（234s） |
| SprintTwelveEvalE2ETests（実 Supabase：アプリ端末A投稿→URLSession端末Bいいね→端末Aの受信いいね+1） | ✓ 1/1（15.7s） |

`xcodebuild test` すべて **TEST EXECUTE SUCCEEDED**。LocalBackend 経路・Supabase 経路とも回帰なし。
スプリント05・11 の受け入れ条件は回帰していない。

---

## 改善提案（合否には影響しない）

1. **`app_purge_expired_safety_logs` の 42501**: [1] の修正に合わせ、アプリ起動ごとに
   本番へ 403 を投げ続ける現状（`try?` で握られるがサーバログは汚れる）を止める。
2. **migration 8 のコメントと実挙動の乖離**: ファイル冒頭コメントは
   「`app_purge_expired_safety_logs()` 経由だけは authorized」と書いているが、
   実際は authorized になっていない。コメントを実挙動に合わせる。
3. **pg_cron スケジュールを別ファイルに分離**（eval-2 改善提案3 / self-review 提案2 と同じ）。
   拡張有効化後にだけ流す `20260827000009_pg_cron_schedule.sql` にする。
4. **`SUPABASE_DB_PASSWORD` での `supabase db push`**: access-token が無くても
   `--password` で push できる（本評価で実証）。generator も同じ手順で migration を
   本番適用して RPC を直接検証できるはず。self-review が「generator は Supabase を
   直接叩けない」としているが、`.env.local` の DB パスワードで migration list / push は可能。

---

## 評価できなかったもの

- **実機2台での UI E2E**（連打制限のアプリ削除＆時計進め越しの回避不能性、BAN 反転の
  画面遷移、時計ずらしでのお題同一性、アカウント削除UIからの他端末伝播の読み切り確認）は
  環境未整備で未実施。条件6 が本番サーバの事実（`app_purge_*` が 42501・pg_cron 不在）で
  決定的に不合格のため、実機確認を待たず差し戻して問題ない。
- 条件2 の banned→active 完全再現は service_role キー（`.env.local` は `__see_dashboard__`）が
  無く未実施。RLS ポリシー定義の適用は確認済み。

---

## 本番への副作用（申し送り）

- `supabase db push` で migration 7・8 を本番へ適用した（eval-2 時点は未適用）。以後は
  リモートに記録済みで再走しない。**この適用自体は sprint 13 の意図どおり**。
- 直叩き検証で作成した匿名アカウントは `delete_my_account` で都度削除済み
  （`t.py` の1件、`t7.py` の A/B 2件）。DB 直の service_role 削除は使っていない。
- `t7.py` が prompt_001 に `Aの声 EVAL13A-PROP-…` / `Bの声 …` を各1件 POST したが、
  両アカウントを `delete_my_account` したため cascade で消えている。
- **eval-2 と違い、`purge_expired_safety_logs` を認証トークンで叩いての `reports` 破壊は
  発生していない**（今回は 403 で拒否されるため）。
