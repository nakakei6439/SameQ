# スプリント12 評価（attempt 5） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8（1条件は「Supabase経路の」限定で条件付き達成） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0だが、主要動線（アカウント作成）が1歩も完走できない | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | 検証不能（サーバー操作が1件も成功しない） | 100% | ✗ |
| 4 回帰（LocalBackend既定経路） | SprintOne 5/5・SprintFour 7/7・SprintFive 7/7・SprintNine 7/7、ユニット166/166 すべて成功 | 100% | ✓ |
| 5 使用性 | 1（完走できない。加えてエラー時に何の説明も出ない） | 3以上 | ✗ |

**5項目中4項目が閾値未達のため不合格。**

## 検証環境
- macOS / Xcode、iOS Simulator（iPhone 17 / iPhone 17 Pro、iOS 26.3）
- `xcodegen generate` → `xcodebuild ... build`（BUILD SUCCEEDED）
- 検証日時: 2026-08-26 21:00〜21:40 JST
- Supabase プロジェクト: `loqumzfgnahtclnvnrzb`（`.env.local` の publishable key で直接 curl 検証）
- `supabase` CLI（v2.103.0）が今回の評価環境ではログイン済み・プロジェクトへの `link` 済み状態だったため、self-review.md が「generator側では手段がない」としていた診断（`supabase migration list --linked`、DB スキーマの直接確認）を evaluator 側で独立に再実施できた

## 受け入れ条件（spec.md 305〜313行）の確認結果

| # | 条件 | 結果 |
|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに出る・再起動後も残る | **未達（検証不能）**。後述の理由でアカウント作成自体が失敗するため2台間の投稿共有を1ミリも試せない |
| 2 | 同じ時刻に同じお題・残り時間 | **未達（検証不能）** |
| 3 | いいねの総数が1増える | **未達（検証不能）** |
| 4 | 通報・ブロックで即時非表示・相手に何も出ない | **未達（検証不能）** |
| 5 | 期限切れ回答が非表示 | **未達（検証不能）** |
| 6 | オフライン時の説明表示・復帰後の自動復帰 | **未達（検証不能。かつ後述の新規発見により“オフラインでなくても”同種の症状が起きることを確認）** |
| 7 | 通信失敗時の画面表示・再試行可能（無言で成功したように見えない） | **未達**。後述の新規発見のとおり、アカウント作成の失敗は「無言で何も起きない」（成功したようにも見えないが、失敗したことも一切示されない） |
| 8 | 同梱シードが通常操作から1件も出ない | **条件付き達成のみ**。`-SameQUseSupabaseBackend` を明示指定したときだけシードを使わない設計。だが Release ビルドの既定は `SupabaseBackend`（`BackendProvider.swift` で確認）であり、実際の本番相当の起動経路ではシード云々以前にアカウント作成が失敗しアプリが機能しない |

**self-review.md 自身も「受け入れ条件1〜7は未達（検証不能）」「条件8は条件付き達成」と明記しており、evaluator の判定と一致する。**

## 実際に動かして確認したこと

### 1. Supabase 経路（`-SameQUseSupabaseBackend`）でオンボーディングを最後まで進めると、アカウント作成の時点で無言のまま永久に止まる（新規発見・最重要）

手順:
1. iPhone 17 Pro シミュレータに新規インストール、`-SameQResetState -SameQUseSupabaseBackend` で起動
2. コンセプト → 規約同意 → 絵文字選択 → ニックネームスキップ → 通知許可画面まで進む（ここまでは全画面正常に遷移）
3. 「あとで設定する」をタップ
4. 8秒後・23秒後にスクリーンショットとアクセシビリティツリーを取得

結果: **タップ後、23秒待っても画面が一切変化しない**。「通知を許可する」「あとで設定する」の両ボタンがそのまま存在し続け、次の画面（今日のお題画面）にも、エラー画面にも遷移しない。証拠: `evidence-attempt5-supabase-stuck-notification-screen.png`

原因をログで特定した（`xcrun simctl spawn ... log stream --predicate 'process == "SameQ"'` で該当プロセスのネットワークログを収集）:

```
Task <...>.<3> request https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup ...
received response, status 422
```

直接 curl でも再現:
```bash
$ curl -s -X POST "https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup" \
    -H "apikey: sb_publishable_..." -H "Content-Type: application/json" -d '{}'
{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}
```

**Supabase プロジェクト側で匿名サインインが無効化されている**。ダッシュボードの
Authentication → Sign In / Providers → Anonymous Sign-ins を有効化する必要がある
（ユーザー側の対応事項。generator 側のコード修正では直せない）。

しかしこれとは別に、**アプリ側にも独立したバグがある**ことをソースで確認した:

- `OnboardingView.complete(requestNotifications:)` は `await session.completeOnboarding(...)` を呼ぶ
- `AppSession.completeOnboarding` は失敗すると `alertMessage` に文字列をセットするだけ（`AppSession.swift:483`）
- `OnboardingView.swift` を全文検索したが `alertMessage` を購読する `.alert(...)` 修飾子が **どこにも存在しない**
- `alertMessage` を実際に表示しているのは `TodayPromptView.swift` と `TimelineView.swift` の2箇所のみ。どちらもオンボーディング後の画面であり、オンボーディング失敗時には到達しない
- 一方 `RootView.swift` には起動直後の `session.start()` 失敗用の綺麗な `failureView(message:)`（「読み込めませんでした」＋「もう一度試す」ボタン）が既に実装されている（`RootView.swift:156-175`）が、これは**既存ユーザーの再起動時**にしか使われず、**新規ユーザーのオンボーディング完了失敗**は素通りする設計になっている

→ **たとえ Supabase 側の匿名サインイン設定を直しても、通信が一時的に失敗した場合（オフライン・タイムアウト・5xxなど）に同じ「無言で永久に止まる」症状が再現する**。受け入れ条件7（「失敗したことが画面上に表示され、同じ操作をもう一度試せる」）は、アプリの一番最初の関門であるアカウント作成そのものに対して未実装。ボタンは再度押せる状態に戻る（`isCompleting` が `defer` でリセットされる）が、押しても同じ理由で毎回無言のまま止まるだけで、ユーザーには何が起きているか一切わからない。

### 2. Supabase プロジェクトのスキーマとデータの独立確認

`.env.local` の publishable key を使い、evaluator 側で直接 REST API を叩いて確認:

```bash
$ curl -s "https://loqumzfgnahtclnvnrzb.supabase.co/rest/v1/prompts?select=id&limit=5" -H "apikey: ..."
[]
$ curl -s ".../rest/v1/posts?select=id&limit=5" -H "apikey: ..."
[]
$ curl -s ".../rest/v1/users?select=id&limit=5" -H "apikey: ..."
[]
```
→ self-review.md の申告どおり **prompts / posts / users すべて0件**（アカウント作成が失敗する以上、これから先も増えようがない）。

`supabase migration list --linked` を evaluator 側で独立実行（self-review.md は access-token が無く実行不能と申告していたが、evaluator の環境では supabase CLI がログイン・プロジェクトlink済みだったため実行できた）:
```
Local          | Remote         | Time (UTC)
20260817000001 | 20260817000001 | 2026-08-17 00:00:01
20260817000002 | 20260817000002 | 2026-08-17 00:00:02
20260818000003 | 20260818000003 | 2026-08-18 00:00:03
20260819000004 |                | 2026-08-19 00:00:04
```
→ self-review.md の診断（migration 4 未適用）を独立に確認。

さらに evaluator が **`20260819000004_server_connection.sql` の内容を精読したところ、
このマイグレーション自体に欠陥がある**ことを新規発見した:
`world_timeline` ビューの定義で `p.decorations`（`posts.decorations`）を SELECT しているが、
`posts.decorations` という列は `20260817000001_init.sql` / `20260818000003_report_block.sql` /
`20260819000004_server_connection.sql` のいずれにも `ALTER TABLE ... ADD COLUMN` が無く、
**存在しない列を参照している**。このため、たとえ access-token を取得して
`supabase db push` を実行しても、このマイグレーションは
`column posts.decorations does not exist` で失敗する可能性が高い
（`create or replace view` の定義時点で列参照を評価するため）。
self-review.md 「提案（attempt6以降）」の1番目（migration適用してクライアント側を戻す）は、
このマイグレーション自体を先に直さない限り実行できない。

### 3. LocalBackend 既定経路（Debug、引数なし）の回帰確認

attempt 4 で evaluator が発見した regression（投稿後に他人の回答カードが1件も出ない）が
attempt 5 で解消しているかを、self-review.md の申告を鵜呑みにせず evaluator 自身で
テストスイートを実行して確認した:

```
SprintOneAcceptanceTests   : 5/5 成功
SprintFourAcceptanceTests  : 7/7 成功
SprintFiveAcceptanceTests  : 7/7 成功（抜き取り追加）
SprintNineAcceptanceTests  : 7/7 成功（抜き取り追加）
SameQTests（ユニット全体）  : 166/166 成功
```
計4スプリント分の回帰（要求最低3件を上回る）と全ユニットテストが成功。
attempt 4 の regression は解消していることを確認した。クラッシュ・アプリ由来の
Fault ログも `log show --predicate 'process == "SameQ"'` で検索し検出0件。

## 不合格の原因（これを直せば通る）

### [1]（最重要・ユーザー側対応必須）Supabase プロジェクトで匿名サインインが無効化されている
- **再現手順**: `curl -X POST https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup -H "apikey: <publishable key>" -d '{}'`
- **期待**: 匿名アカウントが作成されアクセストークンが返る
- **実際**: `{"code":422,"error_code":"anonymous_provider_disabled","msg":"Anonymous sign-ins are disabled"}`
- **根拠**: 上記 curl の実行結果、およびアプリ内 `log stream` での同一エンドポイントへの422応答
- **対応**: Supabase ダッシュボード → 該当プロジェクト → Authentication → Sign In / Providers →
  Anonymous Sign-ins を有効化する（generator 側のコード修正では直せない環境設定）

### [2]（generator 側で対応可能・新規発見）オンボーディング完了処理の失敗がユーザーに一切表示されない
- **再現手順**: 1. Supabase経路（またはアカウント作成が何らかの理由で失敗する状態）で新規インストール
  2. オンボーディングを最後まで進め、通知許可画面で「あとで設定する」または「通知を許可する」をタップ
  3. 23秒待っても画面が変化しないことを確認
- **期待**: spec.md 312行「投稿・いいね・通報・ブロックが通信の失敗で完了しなかった場合、失敗したことが
  画面上に表示され、同じ操作をもう一度試せる」の精神からすれば、アプリの最初のサーバー操作である
  アカウント作成についても同様に失敗が画面に表示されるべき
- **実際**: `OnboardingView` はどこにも `session.alertMessage` を購読していないため、
  `AppSession.completeOnboarding` がエラーを catch して `alertMessage` にセットしても、
  画面には一切反映されない。ボタンは再タップ可能な状態に戻るが、押しても同じ結果を無限に繰り返す
- **根拠**: `grep -rn "alertMessage" SameQ/` の結果、`AppSession.swift` / `TodayPromptView.swift` /
  `TimelineView.swift` の3ファイルにしか出現しない（`OnboardingView.swift` に無し）。
  `RootView.swift:156-175` の `failureView(message:)` は起動時の `session.start()` 失敗にしか
  使われておらず、オンボーディング完了失敗には使われていない
- **対応案**: `OnboardingView` にも `session.alertMessage` を購読する `.alert(...)` を追加するか、
  `RootView.failureView` と同様のリトライ可能なエラー表示をオンボーディングのフッターに出す

### [3]（ユーザー側対応必須、self-review.mdの申し送りと同じだが内容を訂正）保留中の migration 自体が壊れている
- **再現手順**: `supabase/migrations/20260819000004_server_connection.sql` を読む。
  `world_timeline` ビュー定義が `p.decorations` を参照するが、`posts.decorations` 列は
  `init` / `report_block` / `server_connection` のどのマイグレーションにも追加されていない
- **期待**: self-review.md の提案どおり access-token 取得後に `supabase db push` すれば
  スキーマが揃うはず
- **実際**: このマイグレーションのまま push すると `column posts.decorations does not exist`
  で失敗する見込みが高い（`grep -rn decorations supabase/migrations/` で該当列の
  `ALTER TABLE` が1件も無いことを確認）
- **対応**: `20260819000004_server_connection.sql`（または新規マイグレーション）に
  `alter table public.posts add column decorations jsonb;`（または実際の型）を追加してから push する

## データ整合性
サーバー操作が1件も成功しないため検証不能（該当なし）。LocalBackend既定経路については
既存スプリントで確認済みの内容が回帰で壊れていないことのみ今回追加確認した（項目4参照）。

## 回帰（抜き取り、要求最低3件 → 4件実施）
| スプリント | テスト | 結果 |
|---|---|---|
| 01 | SprintOneAcceptanceTests | 5/5 |
| 04 | SprintFourAcceptanceTests | 7/7 |
| 05 | SprintFiveAcceptanceTests | 7/7 |
| 09 | SprintNineAcceptanceTests | 7/7 |

## 使用性
1点（Supabase経路は1歩も完走できない）。加えて、失敗時に何が起きているか一切わからない
（[2]参照）ため、たとえ主要動線が通っても現状の設計のままでは大きく評価を下げる要因になる。

## 評価できなかったもの
- 2台端末間の実際のデータ共有（条件1〜5）：アカウント作成自体が失敗するため未着手
- オフライン（機内モード）表示（条件6の前半）：今回はオンライン状態での失敗（422）が
  先に発生したため未検証。ただしオンライン時点で症状[2]が既に致命的であるため、
  オフライン固有の検証を追加しても合否は変わらない
- 投稿・いいね・通報・ブロックの通信失敗時リトライ（条件7の本文が指す4操作）：
  アカウントが1つも作れないためこれらの画面に到達できず未検証

## 改善提案（合否には影響しないが、次attemptで踏まえておくと良い）
- [A] `checkConnectivity()` は `NWPathMonitor` の状態のみを見て `.offline` を判定しているため、
  「オンラインだがサーバー側が422/500を返す」ケースは別のエラーとして扱われる。
  症状[2]の修正時に、両方のケースを1つの分かりやすいUIパターンでカバーできると良い
- [B] `RootView.failureView` のパターン（メッセージ＋「もう一度試す」ボタン）は既にあるので、
  `OnboardingView` へ同じパターンを持ち込むのが最短の直し方
