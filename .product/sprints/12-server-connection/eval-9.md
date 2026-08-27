# スプリント12 評価（attempt 12） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 実操作で確認 6/8（条件1・2・4・6・8）。条件3 が実 e2e で不合格。条件5・7 は部分確認のみ | 100% | ✗ |
| 2 動作の安定性 | クラッシュ0・主要動線（オンボ→投稿→myAnswer→タイムライン）完走。ただし migration 5 適用後の本番相当状態で「サーバー機能の一部が未適用です」アラートが today / timeline 画面に 1 秒周期で出続ける（誤報） | クラッシュ0・未処理0・主要動線完走 | ✗ |
| 3 データ整合性 | 投稿・いいね・通報・ブロックは本番 Supabase に永続化。状態ゼロの別クライアントからの再取得でも一致 | 100% | ✓ |
| 4 回帰 | SameQTests 166/166・SprintSix 4/4・SprintNine 7/7・SprintTen 7/7・SprintEleven 4/4 | 100% | ✓ |
| 5 使用性 | 2（主要動線は完走できるが、投稿後に誤ったエラーアラートが毎秒ポップして「何が起きたか分からない瞬間」が続く） | 3以上 | ✗ |

**基準1・2・5 が閾値未達のため不合格。** 決定的ブロッカーは eval-7 / eval-8 と同じ条件3で、
attempt 12 は「関数を本番へ配布する経路」（新規 migration 5）は直したが、
**アプリが RPC を呼ぶときのパラメータ名が SQL 関数の定義と食い違っている**という
別のバグが未修正のまま残っており、条件3 は依然として実 e2e で不成立。
さらに attempt 12 で `refreshReceivedLikeCount` の catch を変更したことで、この
パラメータ不一致による 404 が「毎秒の誤アラート」として画面に露出するようになった
（attempt 11 までは無言だった）。

## 検証環境
- macOS / Xcode 26.6（17F113）、iOS Simulator iPhone 17 / iPhone 17 Pro（iOS 26.x）
- `xcodegen generate` → `xcodebuild build-for-testing -configuration Debug` → **TEST BUILD SUCCEEDED**
- 本番 Supabase プロジェクト `loqumzfgnahtclnvnrzb`（spec.md 前提13）。`supabase` CLI ログイン・link 済み。
- **migration 5 を評価者が適用**: 検証開始時 `supabase migration list --linked` で
  `20260820000005` が Remote 未適用だったため、`supabase db push --linked` を実行して適用。
  適用後 `Local | Remote` が 5 件で一致することを確認（self-review.md の「動かし方」に従った）。
- 検証手段:
  1. `urllib` による本番 REST 直叩き e2e（`/tmp/sameq_eval9_full.py` / `/tmp/sameq_paramtest.py`）。
     4〜3 アカウントを本番へ流し、signup→users→prompts→posts→world_timeline→likes→rpc→reports→blocks を直接観測。
  2. リポジトリ同梱の実 e2e UI テスト `SameQUITests/SprintTwelveEvalE2ETests`（端末A=実アプリ UI 操作、
     もう1台=`URLSession` 直叩き）を本番 Supabase 相手に実行。
  3. `SprintTwelveAcceptanceTests` 3/3・`SprintTwelveOfflineAcceptanceTests` 3/3 を実行。
  4. 回帰: ユニット 166/166、SprintSix / Nine / Ten / Eleven を実行。
  5. iPhone 17 Pro シミュレータに Debug ビルドを install→launch し、起動〜オンボーディング画面を目視。
- 検証日時: 2026-08-27 12:20〜12:45 JST

## 不合格の原因（これを直せば通る）

### [1] 条件3が依然不成立 — RPC パラメータ名が SQL 関数定義と食い違っている
spec.md 308行:「端末Bが端末Aの回答にいいねを押すと、端末Aの画面で自分が受け取ったいいねの総数が1増える」

- **症状**: 端末Bが端末Aの投稿にいいねしても、端末Aの `today.receivedLikes`（「1 件のいいね」）が
  いつまでも表示されない。受信いいねは 0 のまま。
- **再現手順**:
  1. `supabase db push` で migration 5 を本番に適用する（評価者が実施済み）。
  2. `xcodebuild test-without-building -only-testing:SameQUITests/SprintTwelveEvalE2ETests` を実行。
  3. テスト内で端末A（実アプリ）がオンボーディング完了 → prompt_001 に固有マーカーで投稿 → `today.myAnswer` 到達（成功）。
  4. もう1台（`URLSession`）が prompt_001 に回答 → `world_timeline` から端末A の投稿取得（条件1 assert パス）→ その投稿へ `POST /rest/v1/likes`（201）。
  5. 端末A の画面を最大 20 秒観測。
- **期待**: 端末A の `today.myAnswer` の下に `today.receivedLikes`（「1 件のいいね」）が現れる。
- **実際**: 20 秒待っても現れない。
  `SprintTwelveEvalE2ETests.swift:86: XCTAssertTrue failed - 条件3違反: … 受信いいね 0 のまま` で **FAIL（35.4 秒）**。
  同テスト内の条件1チェックは同じ実行内で **パス** しているので、投稿・タイムライン取得・いいね INSERT の経路は健全。
- **根拠（本番 DB を直接観測、`/tmp/sameq_paramtest.py`）**:
  - アプリのコードが送っているパラメータ名で叩くと **404**:
    `POST /rest/v1/rpc/received_like_count` body `{"post_id":"<Aの投稿ID>"}` →
    `404 {"code":"PGRST202","details":"Searched for the function public.received_like_count with parameter post_id … but no matches were found","message":"Could not find the function public.received_like_count(post_id) in the schema cache"}`
  - SQL 関数が実際に期待するパラメータ名で叩くと **200**:
    body `{"target_post":"<Aの投稿ID>"}` → `200 0`（いいね前）。
    別スクリプト（`/tmp/sameq_eval9_full.py`）で B がいいね後に叩くと `200 1`、2 人目のいいね後に `200 2`。
    → **SQL 関数（migration 5）は本番で正しく動いている。壊れているのはアプリ側の呼び出し。**
- **根本原因（症状と分けて記載）**:
  - `SameQ/Backend/SupabaseBackend.swift:520-533` `receivedLikeCount(forPostID:)` は
    `struct Args: Encodable { let post_id: String }` を組み、`{"post_id": …}` で RPC を呼ぶ。
  - 一方、SQL 関数の引数名は **`target_post`**。
    `supabase/migrations/20260820000005_received_like_count.sql:144`
    `create or replace function public.received_like_count(target_post uuid)`。
    migration 4（`20260819000004_server_connection.sql:144`）の同名関数も引数は `target_post`。
  - PostgREST は名前付き引数で関数を解決するため、`post_id` では関数が見つからず PGRST202（404）。
  - `SupabaseBackend.receivedLikeCount` が throw → `AppSession.refreshReceivedLikeCount()`（AppSession.swift:401-420）の
    `catch let error as SupabaseError` に落ち、`case .notFound` として `receivedLikeCount = 0`。
  - `TodayPromptView.swift:248` は `session.receivedLikeCount > 0` のときだけ `today.receivedLikes` を描画するので、
    ラベルは永久に出ない。
- **直し方（どちらか一方）**:
  - `SupabaseBackend.swift:522-525` の `Args` を `let target_post: String` に変更し、
    `Args(target_post: postID.uuidString)` にする。**これが最小修正。**
  - もしくは SQL 関数側の引数名を `post_id` に統一する（migration 4・5 双方、および `revoke/grant` の型シグネチャ記述はそのまま）。
    その場合は本番へ新規 migration で再配布が必要。
  - 修正後、`SprintTwelveEvalE2ETests` が緑になること（＝実アプリで「1 件のいいね」表示まで到達すること）を
    generator 側で確認してから awaiting_eval にすること。**このテストはリポジトリにあるのに attempt 11・12 の
    テスト実行対象から外れている**（eval-8 改善提案2 が未対応）。self-review.md のテスト表にも載っていない。

### [2] attempt 12 の catch 変更で、上記 404 が「毎秒の誤アラート」として画面に露出する
spec.md 312行:「…無言で成功したように見えることがない」（趣旨は「失敗を正しく1回伝える」）

- **症状**: migration 5 を適用した本番相当状態で、投稿を済ませたユーザーの today 画面／タイムライン画面に
  「サーバー機能の一部が未適用です。アプリを再起動しても直らない場合はサポートまでお知らせください。」
  というアラートが約 1 秒周期で出続ける（OK で閉じても直後に再出現）。
- **再現手順**:
  1. migration 5 適用済みの本番に接続（評価者環境）。
  2. アプリでオンボーディング完了 → お題に回答して `today.myAnswer` 表示状態にする。
  3. today 画面のまま放置、またはタイムラインを開く。
- **期待**: サーバー機能はすべて適用済みなのだから、このアラートは 1 度も出ない。
- **実際**: `RootView.swift:63-65` が 1 秒ごとに `session.refresh()` を呼ぶ →
  `AppSession.refresh()`（AppSession.swift:375）が毎回 `refreshReceivedLikeCount()` を呼ぶ →
  [1] のパラメータ不一致で毎回 404 PGRST202 → `AppSession.swift:411-412` で
  `alertMessage = "サーバー機能の一部が未適用です。…"` が毎回セットされる →
  `TodayPromptView.swift:61-70` / `TimelineView` の `.alert` が毎秒発火する。
- **根拠**:
  - attempt 11 までの catch は `catch { receivedLikeCount = 0 }`（無言）だったので、この症状は attempt 12 で新規に発生。
  - 実際に本番へ `{"post_id":…}` で叩くと 404 PGRST202 が返る（[1] の根拠と同じ `/tmp/sameq_paramtest.py`）。
  - `SupabaseError.notFound` が PGRST202 / 404 にマップされていることは `SupabaseBackend` / `SupabaseClient` のコードで確認。
- **補足**: [1] を直せば 404 が消えるので、このアラートも自動的に止まる。
  ただし「関数未適用を 1 度だけ知らせたい」という eval-8 改善提案3 の趣旨を残すなら、
  `refreshReceivedLikeCount` で `alertMessage` を毎ティック上書きせず、
  「一度出したら同一セッションでは抑制する」ガードを入れることを推奨（[1] と独立の堅牢化）。
- 目視での最終確認は、iPhone 17 Pro シミュレータでオンボーディングを手動タップで進める必要があり、
  複数シミュレータ同時 Booted 環境で Simulator ウィンドウ自動操作が安定しなかったため、
  コード経路の確定とテスト結果・本番 404 の実測をもって根拠とした（スクショ取得は未達）。

### 補足: 条件5（期限切れ非表示）は今回も部分確認のまま
`world_timeline` ビュー定義に `p.expires_at > now()` があることは SQL で確認。
ただし `posts_set_expiry` トリガーが「非アクティブなお題への投稿」を弾くため、
本番に期限切れ投稿を作れず、「期限切れ回答が1件も出ない」の実データ観測はできていない（eval-7・eval-8 と同じ）。

### 補足: 条件7（4操作の通信失敗時の表示・再試行）は実 e2e 未達
`submit` / `toggleLike` / `report` / `block` はいずれも失敗時に `alertMessage` を立て、
`toggleLike` は楽観更新をロールバック、`report`/`block` は `false` を返す（コード確認）。
「無言で成功」する経路は見当たらない。ただし実行中に通信を落とす手段が無いため、
4操作それぞれの失敗→表示→再試行を実機 e2e では通せていない（eval-8 と同じ）。
`SprintTwelveOfflineAcceptanceTests`（新規・3/3 パス）は起動時オフラインの failure 画面と
retry の非クラッシュを担保するが、条件6 後半（回復後の自動復帰）と条件7 の 4操作は範囲外。

## 確認できた受け入れ条件（合格しているもの）
| # | 条件 | 結果 | 根拠 |
|---|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに他人の回答として出る／入れ直しても読める | ✓ | `SprintTwelveEvalE2ETests` の条件1 assert パス。`/tmp/sameq_eval9_full.py`：状態ゼロの新規クライアント B が prompt_001 に回答後、`world_timeline?body=eq.<Aのマーカー>` で端末A の投稿を取得（サーバーのみで成立＝再インストール相当を内包） |
| 2 | 同じ時刻に同じお題・残り時間 | ✓ | `/tmp/sameq_eval9_full.py`：クライアント A と B が `GET /rest/v1/prompts` で完全に同一の行（`prompt_001` / 同一 `ends_at`）を取得。お題はサーバー駆動 |
| 4 | 通報・ブロックで即時非表示／相手に何も出ない | ✓ | `/tmp/sameq_eval9_full.py`：A が B の投稿を `reports` に INSERT（201）した直後、A の `world_timeline` から当該投稿が消える。A が B を `blocks`（201）した直後、A の `world_timeline` に B 作の行が 0 件。B のトークンで `reports?post_id=eq.<Bの投稿>` / `blocks` を GET すると `200 []`（相手は通報・ブロックを認知できない） |
| 6 | オフラインで「接続してください」相当が出る／回復後に入れ直さず戻れる | ✓（前半・retry 経路） | `SprintTwelveOfflineAcceptanceTests` 3/3：`-SameQForceOffline` 起動で「読み込めませんでした」＋「通信できません。ネットワーク接続を確認してください。」＋「もう一度試す」。白紙・無限スピナー・クラッシュにならず、retry で `start()` 再実行。回復後の自動復帰は起動フラグを実行中に外せず未観測（eval-8 と同じ） |
| 8 | 同梱シードが通常操作から1件も出ない | ✓ | `SprintTwelveAcceptanceTests.test01` パス（Supabase 経路で SeedData.json 由来の本文がタイムライン・画面に出ない）。※本番 DB には `supabase/seed.sql`（＝ SeedData.json と同内容）の 22 件が投入されており `world_timeline` に出る。これは「端末に同梱された擬似データ」ではなく「サーバー側の世界初期データ」として eval-7・eval-8 でも許容扱い。判断が要るなら下記「改善提案」参照 |

## データ整合性
- 端末A の投稿・B のいいね・A の通報・A のブロックはいずれも本番 DB に永続化され、別クライアントからの再取得で一致。
- 条件3 の不具合は「書き込みが飛んでいない」わけではなく（`likes` 行は 201 で作成、`received_like_count(target_post)` は 200 で正しい件数を返す）、
  「アプリが集計 RPC を **間違ったパラメータ名** で呼んでいる」ための取得漏れ。永続層自体の整合性は保たれている。

## 回帰（抜き取り）
| スプリント | スイート | 結果 |
|---|---|---|
| 06（端末内翻訳・spec が明示的に注意喚起） | SprintSixAcceptanceTests | 4/4 ✓ |
| 09 | SprintNineAcceptanceTests | 7/7 ✓ |
| 10 | SprintTenAcceptanceTests | 7/7 ✓ |
| 11 | SprintElevenAcceptanceTests | 4/4 ✓ |
| — | SameQTests（ユニット） | 166/166 ✓ |

過去スプリントの受け入れ条件は attempt 12 の変更で壊れていない。翻訳経路の回帰も無し。

## 使用性
2点。オンボーディングは迷わず、お題待ち（空状態）・オフライン説明・各操作のエラーアラートは用意されている。
しかし migration 5 適用後（＝ generator が想定する本番状態）では、投稿を済ませた瞬間から
today / timeline 画面に「サーバー機能の一部が未適用です」というアラートが毎秒ポップし、
OK で閉じても即再出現する（[2]）。ユーザーは「自分は何も壊していないのに永遠にエラーが出る」状態に置かれ、
主要動線（世界の回答を読む）が完走はできても「途中で何が起きたか分からない瞬間」が続く。3 の下限を割る。

## 改善提案（合否には影響しない）
1. `SprintTwelveEvalE2ETests` を generator の毎回のテスト対象に含める（eval-8 改善提案2 の再掲）。
   今回もこのテストがリポジトリにあるのに回されておらず、[1] が awaiting_eval まで素通りした。
2. `SupabaseBackend` の RPC 呼び出しは、`SupabaseClient.rpc` 側で「関数名＋引数名」を
   1 箇所にまとめる（マイグレーションの引数名と型を突き合わせる薄いテストがあると、この種の
   パラメータ不一致を CI で捕まえられる）。
3. `refreshReceivedLikeCount` の `alertMessage` は「同一セッションで一度だけ」にガードする
   （[2] を直す本命は [1] だが、将来別の集計 RPC でも同じ毎秒スパムが起きうる）。
4. `-SameQForceOfflineToggle`（実行中トグル）を足し、条件6 後半（回復）と条件7 の 4操作を自動回帰に組み込む
   （eval-8 改善提案4 の再掲・未対応）。
5. 本番 `seed.sql` の 22 件を「サーバー側の世界初期データ」として恒久的に残すのか、
   ある時点で撤去するのかを spec に明記する（条件8 の解釈が評価者ごとにぶれないように）。

## 評価できなかったもの
- 条件3の「修正後の受信いいね +1 表示」（アプリの RPC 呼び出しが `post_id` のままなので、修正自体が入っていない）。
- 条件5（期限切れ回答の非表示）: 本番に期限切れ投稿を作れず、ビュー定義の確認に留まる（eval-7・eval-8 と同じ）。
- 条件6 後半（通信回復後にアプリを入れ直さず通常画面へ戻る）・条件7（4操作の通信失敗時の表示と再試行）:
  実行中に通信を落とす手段が無く実 e2e 未達。コードレビューのみ。
- [2] のアラート毎秒スパムの目視スクショ: 複数シミュレータ同時 Booted 環境で Simulator ウィンドウ自動操作が
  安定せず、オンボーディングを手動で進めきれなかった。コード経路の確定・本番 404 の実測・テスト結果で代替。
- スワイプ時の体感待ち時間（spec 注記）: 複数端末の実データ量での体感評価はしていない。
