# スプリント12 評価（attempt 9） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 0/8 が実操作で確認できた | 100% | ✗ |
| 2 安定性 | クラッシュ0・未処理例外0だが、主要動線（アカウント作成）が1歩も完走できない（HTTP 401 で毎回停止） | 主要動線が最後まで通る | ✗ |
| 3 データ整合性 | 検証不能（サーバーへの書き込みが1件も成功しない） | 100% | ✗ |
| 4 回帰（LocalBackend既定経路） | SprintOne 5/5・SprintFour 7/7・SprintNine 7/7（計19/19）、ユニット166/166 すべて成功 | 100% | ✓ |
| 5 使用性 | 2（エラー表示自体は出るが、原因不明のまま何度やっても同じ失敗を繰り返すだけで、ユーザー側に取れる対処が無い） | 3以上 | ✗ |

**5項目中4項目が閾値未達のため不合格。**

## 検証環境
- macOS / Xcode 26、iOS Simulator 2台（iPhone 17 Pro `07C68712-95E0-4180-87E8-360963E3B391` / iPhone 17 Pro Max `E33C6F86-0484-4209-8609-9624DC34C710`、iOS 26.5）
- `xcodegen generate` → `xcodebuild build -configuration Debug` / `-configuration Release` ともに BUILD SUCCEEDED
- Supabase プロジェクト `loqumzfgnahtclnvnrzb`：本 attempt で初めて到達性・匿名サインイン・migration適用のすべてが整った状態を確認（後述）
- 検証日時: 2026-08-27 10:00〜10:20 JST
- 詳細ログ: `evidence-eval6-401-on-signup.txt`

## まず確認できた前進（ユーザー対応の効果）
これまでの attempt 1〜6 は Supabase プロジェクト自体が到達不能（DNS未解決）または匿名サインインが
無効化されており、アプリの実装を試す以前の段階でブロックされていた。今回はユーザー対応（Anonymous
Sign-ins 有効化・`supabase db push`・seed投入）の効果で、**初めて環境要因のブロッカーが解消された**
ことを独立に確認した：

```
$ curl -X POST https://loqumzfgnahtclnvnrzb.supabase.co/auth/v1/signup -H "apikey: <publishable key>" -d '{}'
→ {"access_token":"...","user":{"is_anonymous":true, ...}}   # 200、匿名サインアップ成功

$ supabase migration list --linked
   Local          | Remote         | Time (UTC)
   20260817000001 | 20260817000001 | ...
   20260817000002 | 20260817000002 | ...
   20260818000003 | 20260818000003 | ...
   20260819000004 | 20260819000004 | ...   # migration4 も Remote 適用済み

$ curl .../rest/v1/prompts (認証済みトークンで)
→ [{"id":"prompt_001","text":"今日、思わず笑ってしまったことは何ですか？", "ends_at":"2026-08-27T23:07:38+00:00", ...}]  # お題データも存在
```

これは大きな前進であり、generatorのattempt1〜9のコード変更（BackendProvider切替・migration修正・
アラート追加等）を無駄にしないためにも、次項の指摘は最優先で対応する価値がある。

## 実際に動かして見つけたこと（新規・最重要）

### [1]（最重要・generator側で修正可能）匿名サインアップ直後の初回書き込みが必ず HTTP 401 で失敗し、アカウント作成が1件も完了しない

**再現手順**:
1. `xcodegen generate` → Debug ビルド → iPhone 17 Pro シミュレータに新規インストール
2. `-SameQResetState -SameQScenario live -SameQFakePlus -SameQTimeOffsetMinutes 0` で起動（`-SameQUseLocalBackend` を付けない = Debug既定のSupabase経路）
3. コンセプト → 規約同意 → 絵文字選択 → ニックネーム入力 → 「あとで設定する」まで進める
4. **2回、それぞれ新規アカウントで独立に再現**（10:07 JST・10:20 JST、いずれも同一結果）

**期待**（spec.md 受け入れ条件1〜5の前提、および「完了時にユーザーができること」）:
匿名アカウントが作成され、今日のお題の画面（`today.promptText`）まで進める。

**実際**:
「あとで設定する」を押した直後にアラート「うまくいきませんでした / Something went wrong」
「セッションが切れました。もう一度やり直してください。」が表示され、オンボーディングの
通知許可画面から一歩も先に進めない。OKを押して再試行しても同じ結果を繰り返す（無限ループ）。

**根拠**:
- os_log (CFNetwork) で `response_status=401` を直接観測（`evidence-eval6-401-on-signup.txt`）
- XCUITestのaccessibility tree dumpでアラート文言を直接観測
- 2回の独立実行で100%再現（フレーク性なし）

**原因（ソース読み合わせで特定・generator側で完結して直せる）**:
`SameQ/Backend/SupabaseBackend.swift` の `init()` で、`SupabaseClient` に渡す
`tokenProvider` は `{ tokenBox.value }` というクロージャで、`tokenBox`（`TokenBox`
クラスの共有インスタンス）の値を都度読む設計になっている（コメント曰く「401後にトークンを
更新しても次のリクエストから新しい値が届くように」という意図）。しかし
**`tokenBox.value` への代入はファイル全体で2箇所のみで、どちらも `nil` を代入するリセット
処理**（`options.resetsState` のときと、期限切れの古いトークンを捨てるとき）。
`createAnonymousUser(emoji:nickname:)` が `client.anonymousSignUp()` で新しい
`access_token` を取得したあと、**その値を `tokenBox` に反映するコードがどこにも無い**。
そのため直後に呼ばれる `client.insertVoid(table: "users", ...)`（`public.users` 行の作成）
は古い値（新規アカウントでは `nil`）のままリクエストされ、`Authorization` ヘッダーが
欠落した状態で PostgREST に届き 401 になる。`SupabaseClient.validate(response:data:)` は
401 を無条件で `.unauthorized`（「セッションが切れました」）に変換するだけで、リフレッシュや
再試行は行わない。`state.user` は `insertVoid` 成功後にしかセットされないため
（`SupabaseBackend.swift` 134行目以降）、このエラーが起きるとアカウント作成は一切完了しない。
再試行のたびに `anonymousSignUp()` から新しいUUIDでやり直すだけなので、**何度リトライしても
同じ理由で失敗し続ける**。

**影響範囲**: 受け入れ条件1〜5・7はすべてこの1点でブロックされる（アカウント作成という
最初の一歩が成功しないため、投稿・いいね・通報・ブロック・タイムライン閲覧のいずれにも到達できない）。
条件8（シード非表示）はコード上は達成しているように見えるが、そもそも「通常の操作」自体が
1歩も完走しないため実質的に検証不能。

**対応方針の提案**（合否判定には影響しないが参考として）: `client.anonymousSignUp()` の
戻り値を受け取った直後に `tokenBox.value = auth.accessToken` を代入する1行が抜けている
可能性が高い。`updateProfile` / `deleteAccount` など他の認証必須操作も同じ `tokenBox` を
参照しているため、初回サインアップ後のこの1点を直せば芋づる式に解消する見込みが高い。

### [2] 自己評価（self-review.md）のテストが、この問題を検出できない設計になっていた

`SprintTwelveAcceptanceTests.test01` は `today.promptText` と `today.input` が両方存在する
場合だけ投稿を試みる分岐になっており、存在しなければ黙ってスキップされる（アカウント作成の
成否そのものは assert していない）。`test03_supabaseOnboardingCompletesWithoutCrash` に
至っては `onboardingNextGone || onboardingAlertShown || onboardingLaterStillThere` の
いずれかが真であれば合格とする設計で、まさに今回観測した「アラートが出て
`onboarding.notification.later` が画面に残ったまま」という状態そのものが合格条件に
含まれている。self-review.md 自身がこの設計を「寛容な合否判定」として明記しており
（「自分で見つけた弱点」1）、attempt 9 が「21/21成功」と申告した内容と、evaluatorが
実機操作で見た「アカウント作成が1件も完了しない」という実態は、テストの検出力の違いに
起因するもので矛盾ではない。**次attempt以降は、少なくとも1本は「サインアップが成功し
today.promptTextまたはtoday.lockedに実際に到達すること」を厳格にassertするテストに
差し替えることを推奨する**（[1]の修正が済めばこの強化自体は容易なはず）。

## 受け入れ条件（spec.md 305〜313行）の確認結果
| # | 条件 | 結果 |
|---|---|---|
| 1 | 端末Aの投稿が端末Bのタイムラインに出る・再起動後も残る | **未達（検証不能）**。アカウント作成自体が失敗するため2台間の投稿共有を1ミリも試せない |
| 2 | 同じ時刻に同じお題・残り時間 | **未達（検証不能）** |
| 3 | いいねの総数が1増える | **未達（検証不能）** |
| 4 | 通報・ブロックで即時非表示・相手に何も出ない | **未達（検証不能）** |
| 5 | 期限切れ回答が非表示 | **未達（検証不能）**（`world_timeline` のSQL定義に `p.expires_at > now()` があることはソースで確認したが、実データでの実機確認はアカウント未作成のためできず） |
| 6 | オフライン時の説明表示・復帰後の自動復帰 | **未達（検証不能）**。オンライン状態での401エラーが先に発生し、機内モード相当の検証まで到達できなかった |
| 7 | 通信失敗時の画面表示・再試行可能 | **部分的に該当するが実質未達**。「うまくいきませんでした」アラート自体は表示され再試行も可能だが、再試行しても毎回同じ理由で失敗するため「もう一度試せる」の実効性が無い。条件が名指しする「投稿・いいね・通報・ブロック」の4操作にはそもそも到達できない |
| 8 | 同梱シードが通常操作から1件も出ない | **条件付き達成（実質検証不能）**。Releaseビルドは無条件でSupabaseBackendを使うためコード上シードは出ないが、Releaseビルドでも同じ401でアカウント作成が完了しないため「通常の操作」自体が完走しない |

## データ整合性
サーバーへの書き込みが1件も成功しないため検証不能（該当なし）。LocalBackend既定経路については
既存スプリントで確認済みの内容が回帰で壊れていないことのみ確認した（回帰の項参照）。

## 回帰（抜き取り、要求最低3件）
| スプリント | テスト | 結果 |
|---|---|---|
| 01 | SprintOneAcceptanceTests | 5/5 |
| 04 | SprintFourAcceptanceTests | 7/7（1回目実行時に test04 が偶発的に失敗したが、原因は evaluator 自身が同一シミュレータに対してユニットテストを同時実行してしまったことによる競合と判明。単体で再実行し 27秒で成功を確認、再現性なし） |
| 09 | SprintNineAcceptanceTests | 7/7 |
| ユニット全体 | SameQTests | 166/166 |

回帰は問題なし。LocalBackend既定経路（既存スプリント01〜11の機能）はattempt 9のコード変更で
壊れていない。

## 使用性
2点。「うまくいきませんでした」というアラート自体は出るため完全な無言失敗ではないが（改善は
認める）、原因が「セッション切れ」という誤った文言で示され、実際には初回サインアップの実装
バグであることがユーザーには一切分からない。OKを押して同じボタンを押し直しても必ず同じ結果に
なるため、ユーザーが取れる有効な対処が存在せず、事実上ここで完全に詰む。

## 改善として認めた点（合否には影響しないが、正しく評価する）
- attempt 1〜6の間ブロッカーだった「Supabaseプロジェクトへの到達性・匿名サインイン無効化」は
  ユーザー対応により解消され、migration・seedデータも整った状態を独立に確認した。これは
  スプリント12にとって大きな前進である
- Release/Debugのbuildはいずれも問題なくBUILD SUCCEEDED
- LocalBackend既定経路（スプリント01〜11相当）の回帰は全て健全

## 評価できなかったもの
- 2台端末間の実際のデータ共有（条件1〜5）：[1]のバグでアカウント作成自体ができないため未着手
- オフライン（機内モード）表示（条件6）：オンライン状態での401エラーが先に発生するため未検証
- 投稿・いいね・通報・ブロックの通信失敗時リトライ（条件7が名指しする4操作）：同上の理由で未検証

## 次にすべきこと（提案）
1. **最優先**: `SupabaseBackend.createAnonymousUser` が `client.anonymousSignUp()` で
   取得した `access_token` を、その後の `client.insertVoid(table: "users", ...)` より前に
   `tokenBox` へ反映する（1行の代入漏れの可能性が高い）。修正後、実機でオンボーディングが
   `today.promptText` または `today.locked` まで到達することを確認する
2. [1]の修正後、`SprintTwelveAcceptanceTests` に「サインアップ成功を厳格にassertする」テストを
   追加し、寛容な判定（アラート状態でも合格とする設計）を見直す
3. [1]解消後、2台のシミュレータで受け入れ条件1〜8を実際に実機操作し直す（今回evaluatorが
   用意した検証手順・アクセシビリティ識別子の対応表は次回そのまま使える：
   `today.input`/`today.submit`/`today.myAnswer`/`today.receivedLikes`/`today.openTimeline`/
   `timeline.card.body`/`timeline.like`/`timeline.more`/`safety.report`/`safety.reason.other`/
   `safety.reportSubmit`/`safety.block`/`safety.blockConfirm`）
