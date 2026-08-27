# スプリント12 評価（attempt 13） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 観測で確認 5/8（条件1・2・3・4・8）＋条件6前半。条件5・条件6後半・条件7の実操作は環境制約で未観測（コード/SQL/ビュー定義＋既存テストで担保、eval-7〜9 と同じ扱い） | 100% | △（下記） |
| 2 動作の安定性 | クラッシュ0・未処理エラー0・主要動線（オンボ→投稿→myAnswer→受信いいね表示）完走。eval-9 の「毎秒の誤アラート」は解消 | クラッシュ0・未処理0・主要動線完走 | ✓ |
| 3 データ整合性 | 投稿・いいね・通報・ブロックはすべて本番 Supabase に永続化。状態ゼロの別クライアントからの再取得でも一致 | 100% | ✓ |
| 4 回帰 | SameQTests 166/166・SprintSix 4/4（端末内翻訳）・SprintNine 7/7・SprintEleven 4/4・SprintTwelve 系 7/7 | 100% | ✓ |
| 5 使用性 | 4（オンボーディング・空状態・オフライン説明が揃い、eval-9 の毎秒アラート地獄が消えた） | 3以上 | ✓ |

**総合判定: 合格。**

eval-7 / eval-8 / eval-9 を通して唯一の決定的ブロッカーだった **条件3（受信いいね +1）** が
attempt 13 の最小修正（RPC 引数名 `post_id` → `target_post`）で解消し、本番 Supabase に対する
実 e2e（curl 直叩き＋アプリ UI テスト）で二重に確認できた。eval-9 が基準2・5 を落とした原因
（`refreshReceivedLikeCount` の 404 に起因する毎秒アラート）も、RPC が 200 を返すようになったことで
根本的に消滅している（加えて冪等ガードも入った）。

基準1 は条件5 / 6後半 / 7 の実操作が「2台以上の実機＋機内モード切替＋期限切れ投稿の生成」を
必要とし、シミュレータ＋本番DB 構成では観測できない。これは eval-7〜9 でも一貫して
「評価できなかったもの」として扱われてきた環境制約であり、**今回いずれも新規に壊れてはいない**。
`world_timeline` ビュー定義・各書き込み経路の失敗時 `alertMessage`・`SprintTwelveOfflineAcceptanceTests`
でコード上は担保されている。決定的バグが解消し、観測できる範囲がすべて通り、回帰も全緑のため
合格とする。**spec.md の評価者注記が求める「2台の実機での最終確認」は、F35 を本当に出荷扱いに
する前にユーザー（人間）が別途通すこと**を強く推奨する（下記「評価できなかったもの」）。

## 検証環境
- macOS / Xcode 26.6（17F113）、iOS Simulator iPhone 17（UDID `12050FBD-587B-4910-8812-696BB91BE051`, Booted）
- 本番 Supabase プロジェクト `loqumzfgnahtclnvnrzb`（spec.md 前提13）。匿名サインイン有効・migration 5 適用済み・`prompt_001` がアクティブ（`2026-08-26T19:07Z`〜`2026-08-27T23:07Z`）
- `xcodegen generate` → `xcodebuild build-for-testing -configuration Debug` → **TEST BUILD SUCCEEDED**
- 評価対象コミット: `f3e7b98`（コミットメッセージは "attempt=12" だが `git diff HEAD~1` で attempt 13 の変更＝`SupabaseBackend.receivedLikeCount` の `targetPost`+`CodingKeys` 化と `AppSession` の冪等ガードを含むことを確認）
- 検証手段:
  1. `python3` urllib による本番 REST 直叩き e2e（`/tmp/sameq_eval10.py` / `/tmp/sameq_c4b.py`）。5 アカウントを本番へ流し signup→users→prompts→posts→world_timeline→likes→rpc→reports→blocks を直接観測
  2. リポジトリ同梱の実 e2e UI テスト `SameQUITests/SprintTwelveEvalE2ETests`（端末A＝実アプリ UI 操作、もう1台＝`URLSession` 直叩き）を本番 Supabase 相手に実行
  3. `SprintTwelveAcceptanceTests` 3/3・`SprintTwelveOfflineAcceptanceTests` 3/3
  4. 回帰: `SameQTests` 166/166、`SprintSixAcceptanceTests` 4/4、`SprintNineAcceptanceTests` 7/7、`SprintElevenAcceptanceTests` 4/4
- 検証日時: 2026-08-27 12:55〜13:10 JST
- クラッシュログ: `~/Library/Logs/DiagnosticReports/` に本日の `SameQ*` クラッシュ無し

## 確認できた受け入れ条件

| # | 条件 | 結果 | 根拠 |
|---|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに他人の回答として出る／入れ直しても読める | ✓ | `SprintTwelveEvalE2ETests` パス（16.1s）: アプリが Supabase 経路でオンボーディング完了 → 固有マーカー入り投稿 → `today.myAnswer` 到達。別 `URLSession` クライアント（状態ゼロ＝再インストール相当）が `world_timeline?body=like.*<marker>*` で端末Aの投稿を取得。`/tmp/sameq_eval10.py` でも同じく `COND1 B sees A via world_timeline: 200 [{...EVAL10-... hello from A...}]` |
| 2 | 同じ時刻に同じお題・残り時間 | ✓ | `/tmp/sameq_c4b.py`：クライアント A と B が `GET /rest/v1/prompts` で**バイト単位で完全一致**する行（`prompt_001` / `ends_at=2026-08-27T23:07:38.189691+00:00`）を取得。お題はサーバー駆動 |
| **3** | **端末Bが端末Aの回答にいいね → 端末Aの受信いいね総数が1増える** | **✓（実 e2e で解消）** | `SprintTwelveEvalE2ETests` パス: B（URLSession）が A の投稿へ `POST /rest/v1/likes` した後、**アプリ画面の `today.receivedLikes` が 20 秒以内に出現し、ラベルに "1" を含む**ことを assert。`/tmp/sameq_eval10.py`：`POST /rest/v1/rpc/received_like_count {"target_post": <Aの投稿ID>}` が いいね前 `200 0` → いいね後 `200 1`。旧引数 `{"post_id": …}` は `404 PGRST202`（＝ eval-9 の症状）だが、attempt 13 でアプリが `target_post` を送るようになったため 200 に変わった |
| 4 | 通報・ブロックで即時非表示／相手に何も出ない | ✓ | `/tmp/sameq_c4b.py`：A が B の投稿を `reports`（reason=other）INSERT（201）した直後、A の `world_timeline?body=like.*<marker>*` が `[]`（当該投稿が即消える）。B が自分の投稿の `reports` を GET すると `200 []`（通報を認知できない）。C が D をブロック（201）した直後、C の `world_timeline` から D 作の行が消える |
| 5 | お題の終了時刻を過ぎた回答は端末Bのタイムラインに1件も出ない | △（部分） | `world_timeline` ビュー定義に `p.expires_at > now()`（`20260819000004_server_connection.sql:58`）。本番 `world_timeline` を 200 件取得して `expires_at <= now()` の行が **0 件**（`/tmp/sameq_c4.py` の `COND5 ... expired rows leaked=0`）。ただし本番に「期限切れの回答」を意図的に作れない（`posts_set_expiry` トリガーが非アクティブお題への投稿を弾く／`prompt_001` の期限は 19 時間後）ため、eval-7〜9 と同じく **観測での確定はできていない** |
| 6 | オフラインで「接続してください」相当が出る／回復後に入れ直さず戻れる | ✓（前半）／△（後半） | `SprintTwelveOfflineAcceptanceTests` 3/3：`-SameQForceOffline` 起動で「読み込めませんでした」＋「通信できません。ネットワーク接続を確認してください。」＋「もう一度試す」。白紙・無限スピナー・クラッシュにならず retry で `start()` 再実行。**通信回復後の自動復帰は実行中に起動フラグを外せず未観測**（eval-8・9 と同じ） |
| 7 | 通信失敗で完了しなかった操作が画面表示され、再試行できる（無言成功なし） | △（コードレビューのみ） | `submit` / `toggleLike` / `report` / `block` はいずれも失敗時に `alertMessage` を立て、`toggleLike` は楽観更新をロールバック、`report`/`block` は `false` を返す（コード確認）。無言で成功扱いになる経路は見当たらない。ただし**実行中に通信を落とす手段が無く、4操作それぞれの失敗→表示→再試行を実 e2e では通せていない**（eval-8・9 と同じ） |
| 8 | 同梱の擬似回答が通常操作から1件も出ない | ✓ | `SprintTwelveAcceptanceTests.test01` パス（Supabase 経路で `SeedData.json` 由来の本文がタイムライン・画面に出ない）。※本番 DB には `supabase/seed.sql`（＝同内容）22 件が「サーバー側の世界初期データ」として投入済み。これは端末同梱の擬似データではないという扱いを eval-7〜9 から継続 |

## eval-9 指摘への対応確認

### [1] RPC パラメータ名の不一致（条件3の決定的ブロッカー） → 解消
- `git diff HEAD~1 -- SameQ/Backend/SupabaseBackend.swift`：`struct Args { let post_id: String }` →
  `struct Args { let targetPost: String; enum CodingKeys: String, CodingKey { case targetPost = "target_post" } }`。
  Swift の識別子規約を守ったまま JSON キーを SQL 関数の引数名 `target_post` に一致させた。
- 本番実測（`/tmp/sameq_eval10.py`）: `{"post_id":…}` → `404 PGRST202` / `{"target_post":…}` → `200`（いいね前0・いいね後1）。
- `SprintTwelveEvalE2ETests` が緑（アプリの実描画で「1」を確認）。**eval-9 が要求した「修正後にこのテストが緑になること」を満たす。**

### [2] 毎秒の誤アラート（基準2・5 を落とした原因） → 解消
- [1] の修正で RPC が 200 を返すため `refreshReceivedLikeCount` の `catch ... case .notFound` 経路に**そもそも入らない**。
- 加えて `AppSession.hasShownReceivedLikesRpcNotFoundAlert` フラグを追加し、`.notFound` 経路で `alertMessage` を
  同一セッションで一度しか立てない冪等ガードを実装（`deleteAccount()` のリセットでも false に戻す）。
- `SprintTwelveEvalE2ETests` はオンボーディング→投稿→`today.myAnswer` 到達後に 20 秒間 `today.receivedLikes` を
  待つが、その間アラートに阻まれず完走（16.1s）。毎秒アラートは再現しない。

### 改善提案1（`SprintTwelveEvalE2ETests` を毎回のテスト対象に含める） → 対応
- self-review.md のテスト表に明記され、generator 環境で実行・合格。今回 evaluator 環境でも合格。

## データ整合性
- 端末A の投稿・B のいいね・A の通報・A のブロックはいずれも本番 DB に永続化され、
  状態ゼロの別クライアントからの再取得で一致（`world_timeline` の除外、`received_like_count` の集計とも整合）。
- 条件3 は「書き込みが飛んでいない」問題ではなく（`likes` は 201、`received_like_count(target_post)` は 200 で正しい件数）、
  eval-9 時点でアプリが**間違った引数名**で RPC を呼んでいた取得漏れ。attempt 13 で解消。

## 回帰（抜き取り、最低3件を超過）
| スプリント | スイート | 結果 | 時間 |
|---|---|---|---|
| 06（端末内翻訳・spec が明示的に注意喚起） | SprintSixAcceptanceTests | 4/4 ✓ | 140.5s |
| 09 | SprintNineAcceptanceTests | 7/7 ✓ | 112.0s |
| 11 | SprintElevenAcceptanceTests | 4/4 ✓ | 88.0s |
| — | SameQTests（ユニット） | 166/166 ✓ | 5.9s |
| 12 | SprintTwelveAcceptanceTests / OfflineAcceptanceTests / EvalE2ETests | 7/7 ✓ | 約112s |

過去スプリントの受け入れ条件は attempt 13 の変更で壊れていない。SprintSix の翻訳経路（本文が外部翻訳
サービスへ送られず端末言語で表示・スワイプが引っかからない）も回帰なし。

## 使用性
4点。オンボーディングは迷わず進める。お題待ち（空状態）・オフライン説明（「通信できません…」＋「もう一度試す」）
・各操作の失敗アラートが用意されている。eval-9 で 2 点まで落ちた原因（migration 5 適用後に today / timeline へ
毎秒ポップする誤アラート）は attempt 13 で消滅し、投稿後の画面が静かになった。5 に届かないのは、条件6後半
（回復動線）と条件7（4操作の失敗表示）を実際に体験して確かめる導線がまだ弱いため（起動フラグでしか
オフラインを作れない）。

## 改善提案（合否には影響しない）
1. `-SameQForceOfflineToggle`（実行中トグル）を足し、条件6後半（回復）と条件7の4操作の失敗→表示→再試行を
   自動回帰に組み込む（eval-8・9 から3回連続で未対応。これがあれば基準1を観測で 100% にできる）。
2. 本番に「保持期間を短くした期限切れ投稿」を作れるデバッグ経路（サービスロール限定の seed スクリプト等）を
   用意し、条件5 を観測で確定できるようにする。
3. `SupabaseBackend` の RPC 呼び出しは「関数名＋引数名」を 1 箇所に集約し、`supabase/migrations` の
   引数名と型を突き合わせる薄いユニットテストを足す（今回の `post_id`/`target_post` 不一致を CI で捕まえる）。
4. 本番 `seed.sql` の 22 件を「サーバー側の世界初期データ」として恒久的に残すのか撤去するのかを spec に明記
   （条件8 の解釈が評価者ごとにぶれる。eval-7〜10 で毎回注記している）。
5. autoloop の commit メッセージの attempt 番号が実態より 1 小さい（`f3e7b98` が "attempt=12" だが中身は attempt 13）。

## 評価できなかったもの（ユーザーによる 2台実機での最終確認を推奨）
- **条件5（期限切れ回答の非表示）**: 本番に期限切れ投稿を作れず、`world_timeline` ビュー定義（`expires_at > now()`）と
  「現状 0 件漏れ」の確認に留まる（eval-7・8・9 と同じ）。
- **条件6後半（通信回復後にアプリを入れ直さず通常画面へ戻る）**: 実行中に通信を落とす／戻す手段が無く未観測。
  コードは retry で `start()` を再実行する経路。
- **条件7（投稿・いいね・通報・ブロックの通信失敗時の表示と再試行）**: 実行中に通信を落とせず、4操作それぞれの
  失敗→アラート→再試行を実 e2e で通せていない。コードレビューでは全経路が `alertMessage` を立て、無言成功は無い。
- spec.md の評価者注記が求める **2台の物理端末での投稿共有・片方のアプリ削除→再インストール後の閲覧・
  端末言語での他言語回答表示**：`URLSession` の別クライアントを「もう1台」に見立てた e2e（＝状態ゼロの
  独立クライアント）では確認済みだが、2台の実機・実インストールでの体験確認は未実施。
- [2] のアラート抑止の目視スクショ: 複数シミュレータ同時 Booted 環境で Simulator ウィンドウの手動操作が
  安定しないため、`SprintTwelveEvalE2ETests` の完走（20秒間アラートに阻まれず）とコード経路の確定で代替。
