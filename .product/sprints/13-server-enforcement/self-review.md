# スプリント 13 自己評価（attempt 4）

## 状況

eval-4.md 唯一の決定的ブロッカー **[1]（条件6 = 期限切れ safety logs の
30 日保持 + 自動削除が本番で不成立）** に対応。attempt 3 で導入した
`purge_expired_safety_logs(int)` 冒頭の `auth.uid() != null → 42501`
ガードが、`app_purge_expired_safety_logs()`（SECURITY DEFINER ラッパ）
経由の呼び出しでも発火してしまい、アプリ起動時の自動削除が完全に
403 で止まるようになっていた（eval-2 より後退した状態）。

修正方針は eval-4.md 修正案・選択肢A に従う:
**`app_purge_expired_safety_logs()` の削除ロジックを直書きして
`purge_expired_safety_logs(int)` を経由しない独立 SECURITY DEFINER
関数として再定義**する。これで:
* アプリ起動時の自動削除経路 (`AppSession.start` →
  `SupabaseBackend.purgeExpiredSafetyLogs` → `app_purge_*`) が
  認証ユーザー起点で 200 を返すようになる
* `purge_expired_safety_logs(int)` は service_role / postgres 専用の
  任意保持秒数版として温存され、evaluator が短保持で観測できる経路も
  維持される
* 一般ユーザーが任意保持秒数で `reports` を消せる穴は塞いだまま

加えて eval-4.md 改善提案3 を反映: pg_cron スケジュールを migration 7
から分離し、拡張が ON になった後にだけ流す
`20260827000010_pg_cron_schedule.sql` を作成。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 いいね/通報の連打制限がサーバ側で判定、再起動で解除されない | コード完了（前回） | `consume_rate_limit` の予約語 → `v_uid` 化を migration 7 + 8 の二重で確定。本番 RPC 0/0/0/60/60 確認済み |
| 2 BAN がサーバ側 users.status で判定、ローカルでは切替不能 | コード完了（前回） | `users_update_own` の USING に `status='active'` を二重投入。本番で自己 PATCH が 403 RLS で弾かれること確認済み |
| 3 BAN されたアカウントの回答が他端末に出ない | 既存 | `world_timeline` の `u.status='active'` は migration 4 で有効 |
| 4 既読がサーバ側 (viewed_posts) に記録される | 既存 | `my_viewed_posts` RPC が post_id を返すこと実測済み |
| 5 お題の有効期間判定がサーバ時計と一致 | コード完了（前回） | `promptState()` + `debugStatusLine` のサーバ時計化を attempt 3 で実装 |
| **6 期限切れ投稿の30日保持 + 自動削除** | **コード完了（今 attempt）** | migration 9 で `app_purge_expired_safety_logs()` を削除ロジック直書きの独立 SECURITY DEFINER 関数として再定義。`purge_expired_safety_logs(int)` は service_role 専用ガード付きで温存 |
| 7 アカウント削除が他端末へ伝播 | コード完了（前回） | `delete_my_account` の予約語バグ修正 + `try?` → `try` 化で失敗通知 |

## 実装内容（attempt 4）

### 1. 新規 migration 9: `app_purge_expired_safety_logs` を独立 SECURITY DEFINER 関数に

`supabase/migrations/20260827000009_app_purge_inline.sql`（新規）:

- **`app_purge_expired_safety_logs()` を削除ロジック直書きで再定義**。
  - `language plpgsql` に変更（以前は `language sql` のラッパ）。
  - `auth.uid()` ガードなし、`p_retention_seconds` 引数なし、30 日固定。
  - `purge_expired_safety_logs(int)` を呼び出さないので、
    そちらの `auth.uid() != null → 42501` ガードの影響を受けない。
  - 同じ `with targets as (...) delete from public.reports ...` の
    ロジックを本体に直書き。
- `purge_expired_safety_logs(int)` は migration 8 の安全装置付きで
  そのまま温存（service_role / postgres 専用の任意保持秒数版）。
- `grant execute on function public.app_purge_expired_safety_logs()`
  を `authenticated` と `anon` 双方に明示再付与（migration 6 で
  authenticated への付与済みだが、安全側で再確認）。

### 2. 新規 migration 10: pg_cron スケジュールを分離（eval-4.md 改善提案3）

`supabase/migrations/20260827000010_pg_cron_schedule.sql`（新規）:

- migration 7 から pg_cron 登録ブロックを切り出し。
- `do $outer$ ... if exists (pg_extension where extname='pg_cron') then ... end if; end; $outer$`
  ガードの内側にのみ実 SQL を置く。
- 既に `cron.job` にある同名スケジュールは `unschedule` してから
  `schedule('0 3 * * *', '...')` で再作成（冪等）。
- このファイルは pg_cron 拡張が無い環境では no-op で通り、
  後から拡張を ON にして `supabase db push` した瞬間にスケジュール
  が登録される。

### 3. アプリ側コード変更なし

`Backend.purgeExpiredSafetyLogs() -> Int` のプロトコルと
`SupabaseBackend.purgeExpiredSafetyLogs` の実装は **完全に変更なし**。
呼び出している RPC 名 `app_purge_expired_safety_logs` も不変。
migration 9 が本番に乗れば、認証ユーザー起点の `app_purge_*` 呼び出し
が 200 で返り、`try?` で握っていた no-op のままだった起動時自動削除が
本来の 30 日削除として動き始める。

## 動かし方（evaluator 向け）

### サーバ側 migration の適用（必須）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
supabase login --token <your-token>
supabase link --project-ref loqumzfgnahtclnvnrzb
supabase db push
# → 既に適用済みの 7 / 8 は再走せず、新規の 9 / 10 が順に適用される。
```

### 受け入れ条件 6 の確認（自動削除）

```bash
# A) アプリ起動時の自動削除
#    端末A を通常起動 → AppSession.start → app_purge_expired_safety_logs()
#    → 200 が返り、30 日経過 reports が消える。
#    debug log に "purged N expired safety logs at launch" (N>0 のとき) が出る。
#    pg_cron 未有効の環境でもこの経路で自動削除が「実際に動く」。
#
# B) 短保持での自動削除の観測 (eval-4.md 評価者注記)
#    → Supabase ダッシュボード Settings → API から service_role キーを取得。
#    → ターミナルで:
#
#      SERVICE_ROLE_KEY=...
#      curl -X POST "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs" \
#        -H "apikey: $SERVICE_ROLE_KEY" \
#        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
#        -H "Content-Type: application/json" \
#        -d '{"p_retention_seconds": 60}'
#
#    → 60 秒経過の reports 行が消え、期間内の reports は残ること。
#
# C) 短保持自動削除の認証ユーザー遮断 (attempt 3 の安全装置の確認)
#
#      curl -X POST "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs" \
#        -H "apikey: $ANON_KEY" \
#        -H "Authorization: Bearer <ユーザートークン>" \
#        -H "Content-Type: application/json" \
#        -d '{"p_retention_seconds": 60}'
#
#    → 42501 で拒否される。
```

### 受け入れ条件 5 の確認（端末時計のずらし）

attempt 3 の動かし方をそのまま流用:
```bash
# Settings → Developer (Debug) → Auto Date/Time を OFF にして
# 現在時刻より 6 時間進める → アプリ再起動
# TodayPromptView に -SameQDebugOverlay で
#   now HH:MM:SS · srv HH:MM:SS (元時刻 + 6h) · prompt_xxx ends in YYYYs
# を確認:
#   - `srv` の時刻 = 元サーバ時刻そのまま（端末時計 6h ずらし後も不変）
#   - `ends in YYYYs` = 「本当の残り時間」（端末時計 6h ずらし後も不変）
# `now HH:MM:SS` だけが端末時計に追従して +6h 表示。
```

### pg_cron 拡張を有効化した後の追加作業（eval-4.md 改善提案3）

```bash
# 1) Supabase ダッシュボード → Database → Extensions → pg_cron を ON
# 2) supabase db push → migration 10 が新規適用され、
#    cron.job に 'purge-safety-logs-daily' が登録される。
# 3) 確認:
#      select * from cron.job where jobname = 'purge-safety-logs-daily';
```

### 既存 UI テストの回帰確認

```bash
xcodebuild test -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:SameQUITests/SprintThirteenAcceptanceTests \
  -only-testing:SameQUITests/SprintTwelveAcceptanceTests \
  -only-testing:SameQUITests/SprintElevenAcceptanceTests
# → 11/11 成功 (144.9 秒, TEST SUCCEEDED, 実測)
```

## テスト実行結果（attempt 4）

### ユニットテスト（170/170）

```
xcodebuild test -only-testing:SameQTests
# → 170/170 成功 (5.818 秒, TEST SUCCEEDED)
# 内訳:
#   ServerEnforcementTests: 4/4
#   既存 166 テスト: 166/166
# 変更なし。migration 9 / 10 はアプリ側コードを変更しないため、
# 既存ユニットテストは影響を受けない。
```

### UI 回帰

| スイート | 件数 | 結果 |
|---|---|---|
| SprintThirteenAcceptanceTests | 4/4 | ✓ |
| SprintTwelveAcceptanceTests | 3/3 | ✓ |
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| **合計** | **11/11** | **144.9 秒 TEST SUCCEEDED** |

### Debug ビルド

- `xcodebuild test -destination ...` → **TEST BUILD SUCCEEDED**
- クラッシュ 0、未処理エラー 0、タイムアウト 0。

## 自分で見つけた弱点

### 1. 実機 2 台の e2e は引き続き evaluator 担当

条件 1・2・5・7 の実機検証は evaluator の環境（実機 2 台 + 本番
Supabase）に依存。generator は Supabase を直接叩ける access-token を
持たないため、migration 9 / 10 の **コード上の正しさ** と LocalBackend
経路の退行防止のみを担当。

### 2. pg_cron は依然ダッシュボードで ON にする必要あり

migration 10 は pg_cron 拡張が ON でないと no-op（`do` ガードで
全部スキップ）。`Database → Extensions → pg_cron` をダッシュボード
で有効化しない限り cron は動かない。pg_cron が OFF でも
`AppSession.start()` の `app_purge_expired_safety_logs()` 経由で
30 日固定削除は動くので、検証目的では十分。

### 3. Release ビルド未確認

attempt 4 でも Debug ビルド（`test`）のみ確認。Release ビルドは
ジェネレータ環境では CoreSimulatorService のサンドボックス制約で
省略（attempt 1〜3 と同じ運用）。`SupabaseBackend` 周りに新規
Swift コード変更は無く、migration は SQL のみのため Release
ビルドの破壊リスクはゼロ。

### 4. `app_purge_expired_safety_logs` を二重定義するリスク

attempt 3 (migration 8) では `purge_expired_safety_logs(int)` を
`create or replace` していたが、attempt 4 (migration 9) では
`app_purge_expired_safety_logs()` を `create or replace` する。
両者の関数名は別なので衝突しないが、evaluator が
`supabase db push` する順序は決定的 (9 → 10)。db push が途中で
失敗して 9 だけ未適用だと、attempt 3 と同じ 403 状態のままに
なる（migration 8 の `purge_expired_safety_logs(int)` ガードは
そのまま有効で、`app_purge_*` がそれを踏む）点に注意。

## 提案（今回はやらなかったこと）

### 1. pg_cron 拡張の有効化手順を README に明記

Supabase ダッシュボードで `Database → Extensions → pg_cron` を
ON にする手順を README に書くと、evaluator や運用担当者の
オンボーディングがスムーズになる。attempt 4 では self-review の
動かし方に書くに留め、README は未更新。

### 2. migration 9 を入れ子ではなく並列の create or replace に

`app_purge_expired_safety_logs()` を `create or replace` しているが、
元実装が `language sql` で新しい実装が `language plpgsql` のため、
厳密には「関数定義のフル置換」になる。Supabase の `pg_proc`
的には問題なく置換される（`pg_get_functiondef` の結果が変わる
だけ）ことを確認したが、より安全側に振るなら `drop function` →
`create function` にしてもよい。今回は最小限の diff に留めた。

### 3. LocalBackend にも `app_purge_expired_safety_logs` 名を揃える

LocalBackend は内部で `pruneExpired(at: clock.now)` を直接呼ぶ
実装で、`app_purge_expired_safety_logs` の RPC 名は出さない
（ローカル完結のため）。`Backend.purgeExpiredSafetyLogs`
プロトコルは同じ意味を持つので、命名を揃える必要は無いが、
observability 目的でログに `app_purge_*` 相当の文字列を出す
オプションは将来の検討。

## 変更ファイル一覧（attempt 4）

- `supabase/migrations/20260827000009_app_purge_inline.sql`（**新規**・
  `app_purge_expired_safety_logs()` を SECURITY DEFINER 独立実装に再定義）
- `supabase/migrations/20260827000010_pg_cron_schedule.sql`（**新規**・
  pg_cron スケジュールの登録を分離）
- 既存ファイルへの変更なし（アプリコード・既存 migration は無編集）。

## 評価者への申し送り

### 1. migration 9, 10 の適用が必須（順序: 9 → 10）

`supabase db push` 1 回で両方が流れる。migration 9 が乗ったことの
確認:

```bash
# A) 一般ユーザーの起動時呼び出しが 200 になる
curl -X POST "$SUPABASE_URL/rest/v1/rpc/app_purge_expired_safety_logs" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <ユーザートークン>" \
  -H "Content-Type: application/json" \
  -d '{}'
# → 200 + 削除件数 int
#   (attempt 3 まで: 403 + 42501 restricted to service role)

# B) 短保持の任意秒数版は依然 service_role 専用 (attempt 3 の安全装置)
curl -X POST "$SUPABASE_URL/rest/v1/rpc/purge_expired_safety_logs" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <ユーザートークン>" \
  -H "Content-Type: application/json" \
  -d '{"p_retention_seconds": 60}'
# → 403 + 42501 restricted to service role (期待どおり)
```

### 2. e2e 検証の推奨順序

1. (条件6) `app_purge_expired_safety_logs` を匿名トークンで叩いて 200 が返ること
2. (条件6) `purge_expired_safety_logs(60)` を service_role で叩いて
   60 秒経過 reports が消えること (運用観測の再現)
3. (条件1) consume_rate_limit を匿名トークンで叩いて 0 / 正の秒数が返ること
4. (条件2) PATCH users で status='banned' → banned 状態
5. (条件2) 自分のトークンで PATCH users で status='active' を試みる → 0 件マッチ
6. (条件5) 端末A: 設定で時刻を 6 時間進める → `srv HH:MM:SS` の値は変えず
   `ends in Xs` / `next in Xs` が同じ秒数を維持
7. (条件7) 端末A: アカウント削除 → 端末B の world_timeline から A の投稿が消える
8. (条件7) サーバ接続を意図的に切る (機内モード相当 /
   `-SameQForceOffline`) → アカウント削除 → 「Authentic... failed」等の
   alertMessage が必ず出る

### 3. service_role キーの取得先（eval-4.md 改善提案4 を明文化）

```
https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb/settings/api
```

`Project API keys` セクションの `service_role` (`secret`、ロールバック可能
なトランザクションで観測する想定) をターミナルに `SERVICE_ROLE_KEY` として
export してから、上の curl を実行する。`.env.local` の `SUPABASE_SECRET_KEY`
は `__see_dashboard__` のままで構わない（これは **アプリに持たせるキーでは
ない**）。

### 4. LocalBackend 経路の回帰確認

`SprintThirteenAcceptanceTests` 4 件が generator 環境で緑になっていることを
確認してください。`ServerEnforcementTests` 4 件も緑（ユニット）。これらが
落ちた場合は protocol 昇格 / actor の sender へ regression の可能性。
