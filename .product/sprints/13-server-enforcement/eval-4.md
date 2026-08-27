# スプリント 13 評価（attempt 3 / 再評価） — 不合格

> 注: 直前の evaluator 実行は eval-3.md を書き出した後に異常終了し（autoloop
> `SAFETY-NET commit before exit 5`）、`state.json` の `status` が
> `awaiting_eval` のまま残っていた。本 eval-4.md は attempt 3（commit b0652a1）を
> 改めて本番 Supabase 直叩き＋シミュレータ実機で検証し直した結果。結論は eval-3.md
> と一致する（条件6 が本番で不成立）。

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 観測充足 3/7（条件3・4・7）。条件1・2・5 は RPC 機構のみ稼働・配線済みで2台実機観測は未達。**条件6 は本番で不成立**（自動削除の経路が1つも動かず、唯一のフォールバックだった起動時 `app_purge_expired_safety_logs()` が attempt 3 の migration 8 で HTTP 403 化した） | 100% | ✗ |
| 2 動作の安定性 | クラッシュ 0 / 未処理例外 0。ユニット 170/170、UI 15/15。Supabase 経路で匿名作成〜投稿〜world_timeline〜既読〜アカウント削除が実 e2e で完走。ただしアプリは毎起動 `app_purge_expired_safety_logs` に対し本番から HTTP 403（`try?` で握られ UI 影響なし・fail-open） | クラッシュ0 / 未処理エラー0 / 主要動線完走 | ✓（注記あり） |
| 3 データ整合性 | 投稿・既読・アカウント削除が本番へ永続し、別クライアントの再読込で一致（world_timeline 70→69、`my_viewed_posts` が当該 post_id を返す、削除後 `posts`/`users` 行が消滅） | 100% | ✓ |
| 4 回帰 | ユニット 170/170・SprintThirteen 4/4・SprintFive 7/7（連打制限・BAN・連投拒否）・SprintEleven 4/4（アカウント削除・設定）。すべて TEST SUCCEEDED | 100% | ✓ |
| 5 使用性の最低線 | 主要動線完走。連打制限失敗は画面表示（Sprint5 e2e で確認）。アカウント削除失敗は alertMessage で通知（`try?`→`try` 化で無言成功なし）。BAN 用のアプリ内画面は増えていない | 3以上 | 4 |

**5基準中 基準1 が閾値未達（条件6 が本番で不成立）。スプリント不合格。**

---

## 検証環境
- 対象: `.product/state.json` currentSprint=13 / attempt=3 / status=awaiting_eval（commit `b0652a1`、作業ツリーはクリーン）
- サーバ: 本番 Supabase `loqumzfgnahtclnvnrzb`（spec 前提どおり運用と同一環境）
- Supabase CLI 2.103.0。`supabase migration list --linked` で **20260827000007・20260827000008 とも Remote に記録済み**（前回の eval-3 実行時に `db push` 済み）。eval-2 [1]（migration 7 の pg_cron 起因ロールバック）は解消済み。本評価では追加の `db push` は不要
- シミュレータ: iPhone 17（iOS 26.5）/ `xcodebuild test`（DerivedData `/tmp/SameQ_DD_eval13d`）
- 直叩き検証: `/tmp/sameq_eval13d/t.py`・`t2.py`（匿名サインアップ + `public.users` 行作成 + 各 RPC）、および 2 アカウント e2e（A/B 各自が prompt_001 に投稿 → world_timeline / viewed_posts / delete_my_account の伝播）
- 実行時刻: 2026-08-27 06:14–06:24 UTC / 15:14–15:24 JST（`current_server_time` RPC で確認。prompt_001 は 2026-08-27 23:07 UTC まで active）

---

## 受け入れ条件ごとの観測結果

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | 連打制限がサーバ側・再起動で解除されない | △（機構のみ） | `public.users` 行を持つ認証ユーザーで `consume_rate_limit(like,max=3,window=60)` を5連打 → `0,0,0,60,60`（全て HTTP 200）。`rate_limit_events` に3行永続。サーバ記録ベースなのでアプリ再起動では消えない構造。**2台実機＋アプリ削除＆再インストール＋端末時計進めでの回避不能性は未観測**（評価環境に実機2台なし） |
| 2 | BAN はサーバ `users.status` 判定・ローカルで切替不能 | △（機構のみ） | 本人トークンで `PATCH /users?id=eq.<self> {"status":"banned"}` → **HTTP 403 `42501 new row violates row-level security policy`**。`users_update_own` の `USING (id=auth.uid() AND status='active')` が本番適用済み。BAN 用のアプリ内画面は増えていない（commit `b0652a1` の差分は Backend/Session のみ）。**banned→active の反転再現は service_role キーが必要で未実施**（`.env.local` は `__see_dashboard__`） |
| 3 | 停止アカウントの回答が他端末に出ない | ✓（機構） | `world_timeline` の `u.status='active'` 条件は migration 4 由来で attempt 3 の変更対象外。2 アカウント e2e で B が world_timeline を正常取得（70行、A の marker 1件）。フィルタ健在。停止アカウント実体での除外は service_role 不在で未実施だがビュー定義は不変 |
| 4 | 既読がサーバ側 (`viewed_posts`) に記録 | ✓ | B が `POST /viewed_posts {user_id,post_id}` → HTTP 201。`my_viewed_posts()` RPC が当該 post_id を返す（`[{"post_id":"0cbb5fff-…","viewed_at":"2026-08-27T06:23:28Z"}]`）。アカウント単位でサーバに既読が残る |
| 5 | 端末時計をずらしても今日のお題と残り時間が同一 | △（機構のみ） | `current_server_time()` が本番でサーバ時刻を返す（`2026-08-27T06:22:42Z`）。`AppSession.start()` が `serverNowOffset` を確定し `debugStatusLine` の `srv`/`ends in Xs` をサーバ時計基準に変更。**実機で時計を数時間ずらしての観測は未達** |
| 6 | 期限切れ投稿の30日保持＋自動削除 | ✗ | 下記 [1]。本番で自動削除が1つも動かず、短保持での観測経路も塞がれている |
| 7 | アカウント削除が他端末へ伝播 | ✓ | 2 アカウント e2e：A が投稿 → B の world_timeline に出現（70行 / marker 1件）→ A が `delete_my_account`（HTTP 204）→ B 再読込で消滅（69行 / marker 0件）。`posts` 行・`users` 行とも消滅。cascade 動作を実クライアント越しに確認 |

充足: **3 / 7 を観測で確認**（1・2・5 は機構のみ、6 は不成立）

---

## 不合格の原因（これを直せば通る）

### [1] 条件6: 本番で期限切れ安全ログの「自動削除」が1つも動かない。attempt 3 の migration 8 でアプリ経由の清掃経路が新たに壊れた — 最重要

- **症状**:
  1. `app_purge_expired_safety_logs()` を認証ユーザーのトークンで呼ぶと **HTTP 403 /
     `{"code":"42501","message":"purge_expired_safety_logs is restricted to service role"}`**。
     アプリは起動ごとにこの RPC を呼ぶ（`AppSession.start()` →
     `SupabaseBackend.purgeExpiredSafetyLogs()` 828 行付近 → RPC `app_purge_expired_safety_logs`）が、
     `try?` で握られ常に 0 件・no-op になる。**eval-2 が「自動経路は起動時
     `app_purge_expired_safety_logs()`（30日固定）だけは動く」と認めていた唯一の
     フォールバックが、今回で完全に死んだ。**
  2. `purge_expired_safety_logs(60)` / `purge_expired_safety_logs()` を認証トークンで呼ぶと
     HTTP 403 `42501 permission denied for function`（migration 8 で anon/authenticated から
     execute 剥奪済み）。
  3. pg_cron 拡張は本番で有効化されていない（generator 自身が self-review「弱点2」で明言）。
     migration 7 の cron 登録ブロックは `if exists (select 1 from pg_extension where
     extname='pg_cron')` の中にあり、拡張が無いので **スケジュールは登録されない**。
  4. 評価者は service_role キーを持たない（`.env.local` の `SUPABASE_SECRET_KEY` は
     `__see_dashboard__`）。よって `purge_expired_safety_logs` を service_role で
     叩いての「短保持での自動削除」観測もできない。
- **再現手順**:
  1. `cd /Users/nakagawakeita/Products/iOSApp/SameQ`
  2. `python3 /tmp/sameq_eval13d/t2.py` を実行（匿名サインアップ→`users` 行作成→各 RPC）
  3. 出力の `--- app_purge_expired_safety_logs (authed, app startup path) ---` 行
     → `(403, '{"code":"42501", ... "restricted to service role"}')`
- **原因（確定）**: migration 8 の `purge_expired_safety_logs(int)` 冒頭
  （`supabase/migrations/20260827000008_server_enforcement_critical_fixes.sql` 167–174 行）に
  `if caller_uid is not null then raise exception … using errcode='42501'` を追加した。
  `caller_uid := auth.uid()`。`app_purge_expired_safety_logs()` は SECURITY DEFINER だが、
  その内側でも `auth.uid()` は依然 **呼び出し元 JWT の sub** を返す（SECURITY DEFINER は
  実行ロールを変えるだけで `request.jwt.claims` GUC はクリアしない）。よってラッパ経由でも
  `caller_uid is not null` が真になり、必ず 42501 で弾かれる。ファイル冒頭コメント
  （20–21 行）は「`app_purge_expired_safety_logs()` 経由だけが authorized」と書いているが、
  実挙動はそうなっていない。
- **spec 評価者注記との齟齬**: 「『削除する仕組みが用意されている』だけでは合格に
  しない」「保持期間を短くした条件で自動削除が実際に走ることと、期間内のデータが
  消えていないことの両方を確認する」。attempt 3 は
  (a) 自動で走る経路をゼロにし、
  (b) `p_retention_seconds < 86400` を関数レベルで拒否、
  (c) 認証ユーザーからの呼び出しを一律拒否したため、「保持期間を短くした
  条件での自動削除」を運営手段で観測する経路そのものを消した。**条件6 は
  観測不能かつ不成立**。attempt 2 より後退している（attempt 2 は少なくとも
  認証ユーザーが `purge_expired_safety_logs` を呼べた）。
- **期待**: 保持期間を短くした状態で自動削除ジョブが実際に走り、期限内の通報は残り
  期限切れの通報だけが消えることを、運営手段で2時点観測できる。
- **修正案（いずれか）**:
  - `app_purge_expired_safety_logs()`（起動時オンデマンド清掃）を
    `auth.uid() is not null` ガードに触れない実装にする。削除ロジックを
    `app_purge_expired_safety_logs()` 本体へ直書きし（保持30日固定・引数なしなので
    `p_retention_seconds=0` 穴は元々存在しない）、`purge_expired_safety_logs(int)` は
    service_role 専用の運用関数として完全分離する。
  - 「自動で走る」経路を実際に用意する: pg_cron を有効化して schedule を
    別 migration（拡張 ON 後にだけ流す `20260827000009_pg_cron_schedule.sql`）で
    登録する手順を README + 申し送りに明記するか、Supabase Scheduled Edge Function を
    実装する。関数の存在だけでは spec を満たさない。
  - 検証用に「短い保持期間での自動削除」を運営手段で観測できる導線を残す
    （service_role 経由で保持秒数を指定でき、期限内データが残ることを2時点で
    確認できる形）。あわせて評価者が使える service_role キーの受け渡し方法を
    self-review に書く（現状 `.env.local` は `__see_dashboard__` で評価者が
    観測できない）。
- **根拠**: `/tmp/sameq_eval13d/t.py`・`t2.py` の `app_purge_*` / `purge_*` 各行、
  `supabase/migrations/20260827000008_server_enforcement_critical_fixes.sql` 156–201 行、
  `supabase/migrations/20260827000006_server_enforcement.sql` 281–290 行
  （`app_purge_expired_safety_logs` の定義）、
  `SameQ/Backend/SupabaseBackend.swift` 828 行付近、`SameQ/Session/AppSession.swift` の
  `start()`、self-review.md「自分で見つけた弱点 2」。

### [2] 条件1・2・5 は機構は本番に載ったが、spec 必須の「2台以上での観測」が未達

- **症状**: RPC（`consume_rate_limit` / `current_user_status` / `current_server_time`、
  および `users_update_own` の RLS）は本番で期待どおり動くことを直叩きで確認した。
  ただし spec 評価者注記が必須とする以下は本評価でも実施できていない:
  - 条件1「アプリを終了/削除して再起動しても、さらに端末時計を進めても連打制限が解除されない」
  - 条件2「運営手段で停止 → 端末が使えない画面／banned→active をアプリ操作で作れない」
  - 条件5「端末の時計を数時間ずらしても今日のお題と残り時間が同一」
- **期待**: spec が「2台以上での検証を必須」「アプリを削除して入れ直す・端末の時計を
  進めるでも回避できないことまで試す」と明記。
- **実際**: サーバ側の事実（`rate_limit_events` 永続・RLS ポリシー定義・
  `current_server_time` 稼働・自己 BAN の 403）は確認済みだが、UI を伴う端末跨ぎの
  回避不能性は未観測。条件6 が確定不合格のため本スプリントの合否はこれを待たずに
  決まるが、次 attempt の合格には 2台実機での観測が必要。
- **根拠**: `/tmp/sameq_eval13d/t2.py`（RPC 稼働・自己 BAN 403）、eval-1〜3 と同じ環境制約。

---

## 回帰（抜き取り）

| 対象 | 結果 |
|---|---|
| SameQTests（ユニット全体・`ServerEnforcementTests` 4 新規含む） | ✓ 170/170・0 失敗（5.8s） |
| SprintThirteenAcceptanceTests | ✓ 4/4（13.5s） |
| SprintFiveAcceptanceTests（連打制限・BAN・連投拒否・LocalBackend） | ✓ 7/7（233.6s） |
| SprintElevenAcceptanceTests（アカウント削除・設定・ローカル） | ✓ 4/4（88.0s） |

`xcodebuild test` すべて **TEST SUCCEEDED**。LocalBackend 経路・Supabase 経路とも新規破損なし。
スプリント05・11 の受け入れ条件は回帰していない。クラッシュ 0・未処理例外 0。

---

## 改善提案（合否には影響しない）

1. **`app_purge_expired_safety_logs` の毎起動 403**: [1] の修正に合わせ、アプリ起動ごとに
   本番へ 403 を投げ続ける現状（`try?` で握られるがサーバログは汚れる）を止める。
2. **migration 8 のコメントと実挙動の乖離**: ファイル冒頭コメント（20–21 行）・関数
   コメント（203–212 行）は「`app_purge_expired_safety_logs()` 経由だけは authorized」と
   書いているが、実際は authorized になっていない。コメントを実挙動に合わせるか、
   実挙動をコメントに合わせる。
3. **pg_cron スケジュールを別ファイルへ分離**（eval-2 改善提案3 / self-review 提案2 と同じ）。
   拡張有効化後にだけ流す `20260827000009_pg_cron_schedule.sql` にする。
4. **評価者向けの service_role キー受け渡し**: 条件6 の「短保持での自動削除の2時点観測」は
   service_role 権限が要る。self-review の「動かし方」に、評価者がダッシュボードから
   secret キーを取得して直叩きする手順（またはロールバック可能なトランザクションで
   観測する SQL）を具体的に書く。
5. **`SUPABASE_DB_PASSWORD` での `supabase db push` / `migration list`**: access-token が
   無くても `--linked --password` で操作できる（本評価で実証）。generator も同手順で
   migration を本番適用して RPC を直接検証できるはず。

---

## 評価できなかったもの

- **実機2台での UI E2E**（連打制限のアプリ削除＆時計進め越しの回避不能性、BAN 反転の
  画面遷移、時計ずらしでのお題同一性、アカウント削除UIからの他端末伝播の読み切り）は
  評価環境未整備で未実施。条件6 が本番サーバの事実（`app_purge_*` が 42501・pg_cron
  不在・評価者に service_role 無し）で決定的に不合格のため、実機確認を待たず差し戻して
  問題ない。
- 条件2 の banned→active 反転の完全再現は service_role キー無しで未実施。RLS ポリシー
  適用（自己 BAN の 403）は確認済み。
- 条件6 の「短保持での自動削除が走り、期限内データが残る」2時点観測は、自動経路が
  全滅かつ service_role 無しのため観測不能。

---

## 本番への副作用（申し送り）

- 本評価では `supabase db push` は実行していない（migration 7・8 は前回 eval-3 実行時に
  適用済みで Remote 記録あり）。
- 直叩き検証で作成した匿名アカウントは `delete_my_account` で都度削除済み。
  2 アカウント e2e の A/B も両方 `delete_my_account` 済み（cascade で投稿も消滅）。
- `t2.py` が prompt_001 に `Aの声 EVAL13D-…` / `Bの声 EVAL13D2-…` を各1件 POST したが、
  両アカウントを削除したため cascade で消えている。`reports` テーブルへの破壊操作は
  一切していない（`purge_expired_safety_logs` は今回 403 で拒否されるため）。
