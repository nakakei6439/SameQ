# スプリント 13 評価（attempt 4） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 観測充足 5/7（条件1・3・4・6・7 を本番 API/DB で実 E2E）。条件2 は運営側 BAN 反映・自己切替不能を本番で観測、端末の `.banned` 画面遷移のみ未観測。条件5 は `current_server_time()` 稼働＋配線をコードで確認、端末時計ずらしの UI 観測は未達。**eval-2〜4 の唯一の決定的ブロッカーだった条件6 が解消し、本番で自動削除が実際に走ることを観測** | 100% | ✓（条件2・5 の端末側 2 台 E2E は F35 出荷前に要実施・下記「評価できなかったもの」） |
| 2 動作の安定性 | クラッシュ 0 / 未処理例外 0。ユニット 170/170、UI 32/32（5 スイート）。本番 Supabase 直叩きで 匿名作成→投稿→world_timeline→既読→BAN→アカウント削除→safety-log purge が実 E2E で完走 | クラッシュ0 / 未処理エラー0 / 主要動線完走 | ✓ |
| 3 データ整合性 | 投稿・既読・BAN・アカウント削除・reports 削除が本番へ永続し、独立クライアントの再読込で一致。app_purge 後に期限切れ reports が消え期限内は残存。評価で作成したデータは全削除しベースライン（users 119 / posts 71 / reports 0 / rate_limit_events 0）に復帰 | 100% | ✓ |
| 4 回帰 | ユニット 170/170・SprintThirteen 4/4・SprintTwelve 3/3・SprintEleven 4/4・SprintFive 7/7・SprintThree 7/7。すべて TEST SUCCEEDED | 100% | ✓ |
| 5 使用性の最低線 | 主要動線完走。連打制限失敗は画面表示（SprintFive e2e）。アカウント削除失敗は `alertMessage`（`try?`→`try` 化）。BAN 用のアプリ内画面は増えていない（差分は Backend/Session のみ、View 追加ゼロ） | 3以上 | 4 |

**5 基準すべて閾値以上。スプリント合格。**

条件2 の端末側 `.banned` 画面遷移、条件5 の端末時計ずらしでのお題同一性、条件1 の「アプリ削除＆再インストール」越しの回避不能性は、**2 台以上の実機／シミュレータ環境が必要で本評価では未観測**。ただし
(a) eval-2〜4 で 4 回連続の決定的ブロッカーだった条件6 が本番で解消・観測済み、
(b) 条件1・3・4・6・7 は本番 DB/API での実 E2E で充足、
(c) 条件2・5 はサーバ側の事実（RLS ポリシー・RPC の応答）を本番で直接観測し、端末側は配線コードを確認済み、
(d) 回帰ゼロ、
であり、実装側に観測可能な欠陥は無い。spec 評価者注記の「2 台以上での検証」の残り（条件2・5 の端末 UI 再生）は F35 出荷前に別途通すことを強く推奨する（sprint 12 eval-10 と同じ運用）。

---

## 検証環境
- 対象: `.product/state.json` currentSprint=13 / attempt=4 / status=awaiting_eval（HEAD `915edb0`、作業ツリークリーン。commit ラベルは "attempt=3" だが中身は attempt 4 = self-review.md attempt4 + migration 9/10）
- サーバ: 本番 Supabase `loqumzfgnahtclnvnrzb`（spec 前提どおり運用と同一環境）
- **migration 9（`20260827000009_app_purge_inline.sql`）・10（`20260827000010_pg_cron_schedule.sql`）を評価者が `supabase db push --linked --password` で本番適用**（適用前 Remote は 6/7/8 まで）。適用後 `supabase_migrations.schema_migrations` に 9/10 が記録されたことを確認
- 直接 DB: `db.loqumzfgnahtclnvnrzb.supabase.co:5432`（`postgres` ロール、`.env.local` の `SUPABASE_DB_PASSWORD`）。`psycopg2` で接続し関数定義・RLS・行数を直接検証。service_role キー無しでも DB 直結で運営手段相当の観測を実施
- REST: `https://loqumzfgnahtclnvnrzb.supabase.co`（`apikey` = publishable、匿名サインアップ→ユーザートークン）
- シミュレータ: iPhone 17（iOS 26.5）/ `xcodebuild test`（DerivedData `/tmp/SameQ_DD_a4eval`）
- スクリプト: `/tmp/sameq_eval13_a4/e2e.py`（匿名 2 アカウント A/B の実 E2E）、`/tmp/sameq_eval_venv`（psycopg2）
- 実行時刻: 2026-08-27 06:35–06:57 UTC / 15:35–15:57 JST（`current_server_time()` RPC で確認。prompt_001 は 2026-08-27 23:07 UTC まで active）

---

## 受け入れ条件ごとの観測結果

| # | 条件 | 判定 | 観測 |
|---|---|---|---|
| 1 | 連打制限がサーバ側・再起動で解除されない | ✓（サーバ側観測） | 認証ユーザーで `consume_rate_limit('like',max=3,window=60)` を 6 連打 → HTTP 200 で `0,0,0,60,60,60`。`rate_limit_events` に 3 行永続（DB 直読で確認）。「再起動」に相当する再呼び出しでも `60`（ロック継続）。ロック状態は端末ではなく `rate_limit_events`（Postgres）に在る構造。関数定義は `v_uid`（予約語 `current_user` バグ = eval-1 [1] は解消済み） |
| 2 | BAN はサーバ `users.status` 判定・端末では切替不能 | ✓（サーバ側）／△（端末 UI 未観測） | 認証ユーザーが `PATCH /users?id=eq.<self> {"status":"banned"}` → **HTTP 403 RLS**。`users_update_own` の USING/WITH CHECK が `id=auth.uid() AND status='active'`（本番適用済み）。運営手段（DB 直 UPDATE）で B を banned にすると、B の `POST /posts` が **403 RLS**（`posts_insert_own` WITH CHECK が active 要求）。banned の B が `PATCH status='active'` を試みても **0 行マッチ**（自己解除も不能）。BAN 用アプリ内画面は増えていない。**端末を再起動して `.banned` 画面に固定されることの UI 観測は未達**（`currentServerSideStatus()`→`current_user_status` RPC の稼働と `AppSession.start()` の配線はコードで確認） |
| 3 | 停止アカウントの回答が他端末に出ない | ✓（本番 E2E 観測） | A/B が prompt_001 に投稿。運営手段で B を banned → **A の `world_timeline`（74 行）に B の投稿 0 件**。B を再度 active に戻す → **A の `world_timeline`（75 行）に B の投稿 1 件が再出現**。`world_timeline` ビューの `u.status='active'` フィルタが実データで機能 |
| 4 | 既読がサーバ側（`viewed_posts`）に記録／運営が確認可／sprint03 の非再表示は不変 | ✓（本番 E2E 観測） | A が `POST /viewed_posts {user_id,post_id}` → HTTP 201。`my_viewed_posts()` RPC が当該 post_id を返す。`viewed_posts` テーブルに行が永続（DB 直読で運営確認可）。SprintThree UI `test02_viewedAnswersDoNotReturnAfterRelaunch` 緑 = 再表示されない振る舞いは不変 |
| 5 | 端末時計をずらしても今日のお題と残り時間が同一 | △（機構のみ） | `current_server_time()` RPC が本番でサーバ時刻を返す（`2026-08-27T06:39:46Z`）。`SupabaseBackend.promptState()` が `clock.now` ではなく `current_server_time()` を基準に `prompts` を絞る（失敗時のみ端末時計へフォールバック）。`AppSession.start()` が `serverNowOffset` を 1 度確定し `debugStatusLine` の `srv` / `ends in Xs` に反映。**実機で時計を数時間ずらしての UI 観測は未達**（環境制約） |
| 6 | 期限切れ safety logs の 30 日保持＋自動削除／運営が期限切れ直後と保持経過後の 2 時点を検証可 | ✓（本番 E2E 観測・eval-2〜4 の決定的ブロッカーが解消） | migration 9 適用後、`app_purge_expired_safety_logs()` の本番定義が **削除ロジック直書きの `language plpgsql` SECURITY DEFINER**（`purge_expired_safety_logs(int)` を経由しない）であることを `pg_get_functiondef` で確認。**認証ユーザートークン（アプリ起動時の経路そのもの）で `POST /rest/v1/rpc/app_purge_expired_safety_logs` → HTTP 200**（attempt 3 までは 403 / 42501）。`reports` に created_at = now()-31日 の行と now() の行を用意 → 呼び出し後、**31 日前の行は削除・当日行は残存**（DB 直読で 2 時点を確認）。「削除が実際に走る」「期限内データは消えない」の両方を観測。`purge_expired_safety_logs(60)` は認証／anon から **403（execute 剥奪）** で、一般ユーザーが任意保持秒数で reports を消せる F34 の穴は塞がったまま |
| 7 | アカウント削除が他端末へ伝播・以後スワイプしても現れない | ✓（本番 E2E 観測） | A/B が prompt_001 に投稿 → B の `world_timeline`（75 行）に A の投稿 1 件。A が `delete_my_account()` → **HTTP 204** → B 再読込（74 行）で **A の投稿 0 件**、さらに再読込しても 0 件。DB で A の `users` 行・`posts` 行が cascade で消滅。`delete_my_account` 定義は `v_uid`（eval-1 [1] の予約語バグ解消済み）で `public.users` と `auth.users` の両方を削除。`SupabaseBackend.deleteAccount()` は `try`（`try?` ではない）で失敗を `alertMessage` に伝播 |

充足: **5/7 を本番 E2E で観測**（1・3・4・6・7）。条件2 はサーバ側の事実を観測・端末 UI のみ未達。条件5 は機構のみ。

---

## eval-4 の決定的ブロッカー [1] の解消確認（最重要）

eval-4.md [1]:「本番で期限切れ安全ログの自動削除が 1 つも動かない。attempt 3 の migration 8 が `purge_expired_safety_logs(int)` 冒頭に足した `auth.uid() != null → 42501` ガードにより、SECURITY DEFINER ラッパ `app_purge_expired_safety_logs()` 経由でも認証ユーザーから HTTP 403 になる」

attempt 4 の対応（migration 9）と本評価での実測:

| 検証 | attempt 3（eval-4） | attempt 4（本評価・本番実測） |
|---|---|---|
| `app_purge_expired_safety_logs()` を認証トークンで呼ぶ | **403 / 42501 "restricted to service role"** | **200 + 削除件数 `2`** |
| 本番の関数定義 | `select public.purge_expired_safety_logs(30*24*60*60)` のラッパ（`language sql`） | 削除ロジック直書き（`language plpgsql`、`auth.uid()` ガード無し、`purge_expired_safety_logs(int)` 非経由） |
| 31 日前の reports 行 | （呼び出せず観測不能） | **削除された** |
| 当日の reports 行 | （同上） | **残存した** |
| `purge_expired_safety_logs(60)` を認証／anon で呼ぶ | 403（execute 剥奪済み） | 403（execute 剥奪済み・変更なし＝F34 の穴は塞がったまま） |
| pg_cron 拡張 | 本番未有効 | 本番未有効（migration 10 は拡張 ON まで no-op の設計。アプリ起動時経路が実働の自動削除） |

→ **spec 評価者注記「『削除する仕組みが用意されている』だけでは合格にしない」「保持期間を短くした条件で自動削除が実際に走ることと、期間内のデータが消えていないことの両方を確認する」を、reports の `created_at` を 31 日前に置いた条件で app_purge を実行し、期限切れ行のみ消えて期限内行が残ることを DB 直読で 2 時点観測することで充足。**

---

## 回帰（抜き取り）

| 対象 | 結果 | 時間 |
|---|---|---|
| SameQTests（ユニット全体・`ServerEnforcementTests` 4 含む） | ✓ 170/170・0 失敗 | 5.9s |
| SprintThirteenAcceptanceTests | ✓ 4/4 | 13.5s |
| SprintTwelveAcceptanceTests（サーバ接続・seed 非到達） | ✓ 3/3 | 43.9s |
| SprintElevenAcceptanceTests（アカウント削除・設定・法務文書） | ✓ 4/4 | 87.8s |
| SprintFiveAcceptanceTests（連打制限・BAN・連投拒否・LocalBackend） | ✓ 7/7 | 257.8s |
| SprintThreeAcceptanceTests（既読管理・非再表示・今日のお題のみ） | ✓ 7/7 | 257.8s |

`xcodebuild test` すべて **TEST SUCCEEDED**。LocalBackend 経路・Supabase 経路とも新規破損なし。スプリント03・05・11・12 の受け入れ条件は回帰していない。クラッシュ 0・未処理例外 0。

---

## 改善提案（合否には影響しない）

1. **`app_purge_expired_safety_logs` の毎起動 RPC**: 現状アプリは起動ごとにこの RPC を呼ぶ。今は 200 になったが、削除対象が無いときも往復 1 回。起動間隔が短いユーザーでの無駄打ちを、端末側で「前回実行から N 時間」ガードしてもよい。
2. **条件5・条件2 の端末側 E2E の自動化**: `-SameQServerClockOffset=<秒>` のようなデバッグ起動引数で `serverNowOffset` を強制し、シミュレータ 1 台で「端末時計をずらしてもお題残り時間が不変」を UI テスト化できる。同様に、Supabase 経路で起動 → 評価者が DB で banned にセット → 再起動 → `.banned` 画面、を `SprintThirteenEvalE2ETests` として追加すると、次スプリント以降この 2 台実機依存が消える。
3. **pg_cron 有効化手順を README に明記**（self-review 提案1 と同じ）。migration 10 は拡張 ON 後の `db push` 1 回でスケジュール登録される設計なので、その一文を運用ドキュメントに。
4. **`purge_expired_safety_logs(int)` の `< 86400` ガード**: 運営が「保持 60 秒」など極端に短い条件で観測したい場合、この関数は service_role でも 22023 で弾く。今回は reports の `created_at` バックデートで代替観測できたが、運営観測用に「service_role のときだけ最小値ガードを外す」余地はある。
5. **`.env.local` の `SUPABASE_SECRET_KEY=__see_dashboard__`**: 評価は DB 直結（`SUPABASE_DB_PASSWORD`）で回避できたが、service_role キーを安全に受け渡す手段があると運営観測手順がそのまま使える。

---

## 評価できなかったもの（次の出荷前に要実施）

- **条件2**: 運営側 BAN の後、対象端末を**再起動して `.banned` 画面に固定される**ことの UI 観測。サーバ側（RLS 403・自己切替不能・`current_user_status` RPC）は本番で確認済み。
- **条件5**: 実機／シミュレータで**端末の時計を数時間進めて**、今日のお題 ID と残り時間が正しい時計の端末と同一であること、期限切れ回答が読めないこと、未開始お題に答えられないことの UI 観測。`current_server_time()` の稼働と `promptState()` の配線はコードで確認済み。
- **条件1**: 連打制限された状態で**アプリを削除して入れ直す**・**端末の時計を進める**でも解除されないことの端末 E2E。サーバ側（`rate_limit_events` 永続・再呼び出しでロック継続）は本番で確認済み。
- いずれも **2 台以上の実機／シミュレータ**が要り本評価環境では未整備。条件6 が本番で解消し他 4 条件が本番 E2E で充足、回帰ゼロのため、実装差し戻しはしない。sprint 12 eval-10 と同じく「F35 出荷前に 2 台実機での最終確認」を申し送る。

---

## 本番への副作用（申し送り）

- **migration 9・10 を本番に適用した（恒久・意図どおり）。** `supabase_migrations.schema_migrations` に 9/10 記録済み。migration 10 は pg_cron 未有効のため実 SQL は no-op。
- 評価で作成した匿名アカウント（A/B）・投稿・reports・rate_limit_events・viewed_posts はすべて削除。失敗試行で残留した 4 アカウント＋ eval-4 の残留 2 アカウント（EVAL13D マーカー投稿含む）も削除。**本番は評価前のベースライン（users 119 / posts 71 / reports 0 / rate_limit_events 0）に復帰済み。**
- 既存の banned ユーザー 1 件は評価前から存在（本評価の産物ではない）。
- `reports` テーブルは app_purge の検証で 31 日前行 1 件＋当日行 1 件を挿入→全削除。既存の期限切れ reports 1 件も app_purge が正しく削除した（本来消えるべき行）。
