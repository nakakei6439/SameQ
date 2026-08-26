# スプリント12 評価（attempt 6） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8 が実操作で確認できた（条件7・8は generator 側コードは修正済みだが、根本ブロッカーで実操作としての完全達成には至らない） | 100% | ✗ |
| 2 安定性 | クラッシュ0・未処理エラー0だが、主要動線（アカウント作成→今日のお題→タイムライン）が1歩も完走できない | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | 検証不能（サーバー操作が1件も成功しない。DB は attempt4〜6を通じ prompts/posts/users すべて0件のまま） | 100% | ✗ |
| 4 回帰（LocalBackend既定経路） | SprintOne 5/5・SprintFour 7/7・SprintFive 7/7・SprintNine 7/7・SprintEleven 4/4（計30/30）、ユニット166/166 すべて成功 | 100% | ✓ |
| 5 使用性 | 1（Supabase経路は依然1歩も完走できない。ただし失敗表示は改善した） | 3以上 | ✗ |

**5項目中4項目が閾値未達のため不合格。**

## 検証環境
- macOS / Xcode、iOS Simulator（iPhone 17 Pro, UDID `07C68712-95E0-4180-87E8-360963E3B391`, iOS 26.4.1）
- `xcodegen generate` → `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'id=...' build`（Debug/Release ともに BUILD SUCCEEDED）
- 検証日時: 2026-08-27 05:15〜05:47 JST
- Supabase プロジェクト: `loqumzfgnahtclnvnrzb`（`.env.local` の publishable key で直接 curl 検証、`supabase` CLI v2.103.0 でログイン・link 済み環境から独立に確認）
- 詳細ログ: `evidence-attempt6-verification.txt`、スクリーンショット `evidence-attempt6-*.png`

## 受け入れ条件（spec.md 305〜313行）の確認結果

| # | 条件 | 結果 |
|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに出る・再起動後も残る | **未達（検証不能）**。アカウント作成自体が失敗するため2台間の投稿共有を1ミリも試せない（attempt4/5と同じ） |
| 2 | 同じ時刻に同じお題・残り時間 | **未達（検証不能）** |
| 3 | いいねの総数が1増える | **未達（検証不能）** |
| 4 | 通報・ブロックで即時非表示・相手に何も出ない | **未達（検証不能）** |
| 5 | 期限切れ回答が非表示 | **未達（検証不能）** |
| 6 | オフライン時の説明表示・復帰後の自動復帰 | **未達（検証不能）** |
| 7 | 通信失敗時の画面表示・再試行可能（無言で成功したように見えない） | **部分的に改善・条件としては引き続き未達**。オンボーディング中のアカウント作成失敗は eval-4 の指摘どおり修正され、実機で動作確認できた（後述）。ただし条件7が名指しする「投稿・いいね・通報・ブロック」の4操作は、アカウントが1つも作れないためどれも到達できず未検証のまま |
| 8 | 同梱シードが通常操作から1件も出ない | **条件付き達成**。Release ビルドは無条件で `SupabaseBackend` を使うためシードは出ない（コード確認＋Releaseビルドで実機起動して確認）。ただしその Release ビルドはアカウント作成自体ができないため、そもそも「通常の操作」自体が完走しない |

## 実際に動かして確認したこと・attempt5からの差分

### 1.（新規発見・改善を確認）[2] オンボーディング完了失敗のアラート表示は実装され、実機で動作した

eval-4.md [2] の再現手順をそのまま再実行した（一時UIテストを追加して実行、評価後に削除・コミットなし）。

手順:
1. iPhone 17 Pro シミュレータに新規インストール、`-SameQResetState -SameQUseSupabaseBackend` で起動
2. コンセプト → 規約同意 → 絵文字選択 → ニックネームスキップ → 通知許可画面まで進む
3. 「あとで設定する」をタップ
4. アラートの出現を最大30秒待つ

結果（xcodebuildのテストログ抜粋）:
```
t =     8.62s Tap "onboarding.notification.later" Button
t =     8.99s Waiting 30.0s for Alert (First Match) to exist
t =    10.04s Find the Alert (First Match)
EVALUATOR_RESULT: alert appeared. label=うまくいきませんでした / Something went wrong
Test Case '...test_onboardingShowsAlertWhenSupabaseSignupFails' passed (10.304 seconds)
```

attempt5では23秒待っても無反応だった同一手順が、attempt6では**約1.4秒でアラートが表示される**ことを実機（シミュレータ）で確認した。ソースも確認: `OnboardingView.swift` に `session.alertMessage` を購読する `.alert(...)` が追加されている。`isCompleting` は `defer` でリセットされるためボタンは再タップ可能。generator の申告どおりの修正が実装され、動作することを独立に確認した。

**ただしこれは受け入れ条件7が名指しする「投稿・いいね・通報・ブロック」の失敗表示ではなく、その手前のアカウント作成の失敗表示である。** アカウント作成そのものが常に失敗する現状では、この4操作の画面には一度も到達できないため、条件7自体は依然「未達（検証不能）」のまま。

### 2.（変わらず）[1] Supabase プロジェクトの匿名サインインは依然無効化されている

```
$ curl -s -X POST "https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup" \
    -H "apikey: sb_publishable_..." -H "Content-Type: application/json" -d '{}'
{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}
```
eval-4 で確認した状態から一切変化がない。self-review.md 自身も「ユーザー側でSupabaseダッシュボードのAuthentication → Sign In / Providers → Anonymous Sign-insを有効化する必要がある」と明記しており、generator 側のコード修正では解決できない環境設定である。**attempt 1・2・4・5・6のいずれでもこの1点が変わらず主要動線を完全にブロックしている。**

### 3.（新規発見）[3] migration ファイル自体の修正は内容として自己完結していることを確認したが、適用（`db push`）は依然できていない

`supabase/migrations/20260819000004_server_connection.sql` の冒頭に
`alter table public.posts add column if not exists decorations jsonb not null default '[]'::jsonb;`
が追加されていることを確認した。`world_timeline` ビューが参照する残りの列
（`body_language` / `created_at` / `expires_at` / `status`）はすべて
`20260817000001_init.sql` で既に定義済みであることも突き合わせて確認した。
ファイル単体としては自己完結しており、eval-4 [3] が指摘した
`column posts.decorations does not exist` は解消される見込みが高い。

```
$ supabase migration list --linked
Local          | Remote         | Time (UTC)
20260817000001 | 20260817000001 | 2026-08-17 00:00:01
20260817000002 | 20260817000002 | 2026-08-17 00:00:02
20260818000003 | 20260818000003 | 2026-08-18 00:00:03
20260819000004 |                | 2026-08-19 00:00:04
```
migration 4 は依然リモートに未適用のまま（eval-4 と同じ）。evaluator は本番 Supabase
プロジェクトへの `db push` を実行していない（本番スキーマの変更は evaluator の
役割を超えるユーザー側の意思決定と判断したため。過去の attempt でも evaluator は
一貫してこの種の本番環境操作を行っていない）。`prompts` / `posts` / `users` は
引き続きすべて0件。

### 4. LocalBackend 既定経路（Debug、引数なし）の回帰確認（要求最低3件 → 5件実施）

```
SprintOneAcceptanceTests    : 5/5 成功
SprintFourAcceptanceTests   : 7/7 成功
SprintFiveAcceptanceTests   : 7/7 成功
SprintNineAcceptanceTests   : 7/7 成功
SprintElevenAcceptanceTests : 4/4 成功
SameQTests（ユニット全体）   : 166/166 成功
```
計5スプリント分の回帰（要求最低3件を上回る）と全ユニットテストが成功。クラッシュ・
アプリ由来のFaultログも `log show --predicate 'process == "SameQ"'` で検索し検出0件。

### 5. Release ビルドでの BackendProvider 確認（受け入れ条件8関連）

`BackendProvider.swift` の Release 分岐は `-SameQUseSupabaseBackend` の指定に関わらず
無条件で `SupabaseBackend()` を返すことをソースで確認。実際に Release configuration で
ビルドし、`-SameQUseSupabaseBackend` を付けずに起動しても Supabase 経路（サインアップ待ち）
に入ることをスクリーンショットで確認した（`evidence-attempt6-release-onboarding.png`）。
LocalBackend/SeedCatalog を経由しないため、Release の通常操作からシードが漏れることはない。

## データ整合性
サーバー操作が1件も成功しないため検証不能（該当なし）。LocalBackend既定経路については
既存スプリントで確認済みの内容が回帰で壊れていないことのみ確認した（項目4参照）。

## 回帰（抜き取り、要求最低3件 → 5件実施）
| スプリント | テスト | 結果 |
|---|---|---|
| 01 | SprintOneAcceptanceTests | 5/5 |
| 04 | SprintFourAcceptanceTests | 7/7 |
| 05 | SprintFiveAcceptanceTests | 7/7 |
| 09 | SprintNineAcceptanceTests | 7/7 |
| 11 | SprintElevenAcceptanceTests | 4/4 |

## 使用性
1点。Supabase経路（＝Releaseビルドの通常経路）は依然1歩も完走できない。オンボーディング中の
アカウント作成失敗にアラートが出るようになった点は明確な改善（[2]の修正は評価する）だが、
それでもボタンを押すたびに同じ理由で毎回失敗し続けるだけで、主要動線自体が完走できないという
根本状況は変わっていない。

## 不合格の原因（これを直せば通る）

### [1]（最重要・ユーザー側対応必須・attempt 1から6まで変わらず未解決）Supabase プロジェクトで匿名サインインが無効化されている
- **再現手順**: `curl -X POST https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup -H "apikey: <publishable key>" -d '{}'`
- **期待**: 匿名アカウントが作成されアクセストークンが返る
- **実際**: `{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}`
- **根拠**: 上記 curl の実行結果（eval-4 時点と完全に同一）
- **対応**: Supabase ダッシュボード（https://supabase.com/dashboard/project/loqumzfgnahtclnvnrzb ）→
  Authentication → Sign In / Providers → Anonymous Sign-ins を有効化する。
  **generator 側のコード修正では直せない環境設定であり、6回連続でこの1点のみが
  主要動線を完全にブロックし続けている。ユーザー側の対応がない限り、このスプリントは
  今後何回generatorが試行しても合格し得ない。**

### [2]（ユーザー側対応必須・[1]と対）migration 4 が依然リモートDBに未適用
- **再現手順**: `supabase migration list --linked` を実行する
- **期待**: `20260819000004` がRemote側にも反映されている
- **実際**: Remote列が空欄のまま（`supabase db push` が未実施）
- **根拠**: `evidence-attempt6-verification.txt` の `migration list` 出力
- **対応**: `supabase login --token <token>` → `supabase db push` を実行し、`supabase/seed.sql` を投入する。
  ファイル自体の欠陥（attempt5時点のeval-4 [3]）は attempt6のALTER TABLE追加で解消済みであることを
  evaluatorが読み合わせで確認済みなので、[1]と併せて対応すれば単体でpushが通る見込みが高い

## 改善として認めた点（合否には影響しないが、正しく評価する）
- eval-4.md [2]（オンボーディング完了失敗が画面に一切表示されない）は完全に解消された。
  実機のXCUITestで、失敗から約1.4秒でアラートが表示され、ボタンが再タップ可能な状態に戻ることを確認した
- eval-4.md [3]（migrationファイル自体がposts.decorations未定義で壊れていた）はSQLの読み合わせで解消を確認した
- LocalBackend既定経路の回帰は5スプリント・166ユニットテストすべて成功しており、既存機能への副作用は無い

## 評価できなかったもの
- 2台端末間の実際のデータ共有（条件1〜5）：アカウント作成自体が失敗するため未着手（[1]がユーザー側で解消され次第、着手可能）
- オフライン（機内モード）表示（条件6の前半）：オンライン状態での失敗（422）が先に発生するため未検証
- 投稿・いいね・通報・ブロックの通信失敗時リトライ（条件7が名指しする4操作）：アカウントが1つも作れないためこれらの画面に到達できず未検証
- migration 4 の実際の `supabase db push` 成功可否：evaluator は本番Supabaseプロジェクトへのスキーマ変更を
  自身の権限で実施しないと判断し、ファイルの読み合わせ確認に留めた（[1]の解消と同時にユーザー側で実施が必要）

## 次にすべきこと（提案）
**このスプリントは同一の環境要因（Supabaseダッシュボードでの匿名サインイン有効化）により
6回連続で不合格になっている。generator 側は既に対応可能な範囲（[2]オンボーディングalert、
[3]migrationファイルの欠陥修正）を完了しており、これ以上generator側の作業だけを繰り返しても
状況は変わらない。** ユーザー側で以下を実施した上で次attemptに進むことを推奨する:
1. Supabaseダッシュボード → Authentication → Sign In / Providers → Anonymous Sign-ins を有効化
2. `supabase login --token <token>` → `supabase db push`（migration 4 適用）→ `supabase/seed.sql` 投入
3. 上記完了後、次attemptで初めて受け入れ条件1〜7の実機2台検証が着手可能になる
