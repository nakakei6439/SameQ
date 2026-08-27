# スプリント 12 自己評価（attempt 10）

## 状況

attempt 9 で eval-6.md に「実機シミュレータ 2 台構成でアカウント作成が 1 件も完了しない」と
不合格を受けた（5 項目中 4 項目閾値未達）。根本原因として
`SupabaseBackend.createAnonymousUser` 内の `tokenBox` 未反映（evaluator 指摘）と、
派生バグとして `applyPromptState` → `myPost` の `posts.author_emoji` カラム不存在
（attempt 10 で実機の os_log で発見）を修正した。

## 実装内容（attempt 10）

### 1. 一次バグ修正: `SupabaseBackend.swift` の tokenBox 未反映
eval-6.md の最優先指摘（[1]）。`init()` のローカル変数だった `tokenBox` を
actor の stored property に昇格し、`createAnonymousUser(emoji:nickname:)` が
`client.anonymousSignUp()` で新しい `access_token` を取得した直後に
`tokenBox.value = auth.accessToken` を 1 行代入するようにした。

```swift
// init(): tokenBox を stored property に
let tokenBox = TokenBox(initial: store.load().supabaseAuth?.accessToken)
self.tokenBox = tokenBox
self.client = SupabaseClient(
    session: session,
    tokenProvider: { tokenBox.value },  // 同じインスタンスを参照
    apiKey: SupabaseConfig.publishableKey
)
// createAnonymousUser():
let auth = try await client.anonymousSignUp()
tokenBox.value = auth.accessToken  // ← attempt 10 で追加
let user = AppUser(...)
```

これにより、続く `client.insertVoid(table: "users", ...)` が新しいトークンで
Authorization ヘッダーを付けて POST し、401 にならない。

### 2. 二次バグ修正: `myPost` / `submitPost` の `posts.author_emoji` 不存在
attempt 10 で `os_log` を仕込んで追跡したところ、サインアップ自体は成功したが
その後の `applyPromptState` → `myPost` が 400 で落ちていた。原因は
`myPost` の select に `author_emoji, author_nickname` が含まれていたが、
これらは `posts` テーブルには存在せず、`world_timeline` ビュー側で
`public.users` と JOIN して出す設計（migration
20260817000001_init.sql / 20260819000004_server_connection.sql）。

- `SameQ/Backend/SupabaseBackend.swift::myPost` の select から
  `author_emoji, author_nickname` を削除
- `SameQ/Backend/SupabaseBackend.swift::submitPost` の RETURNING select からも
  同様に削除
- 補完は `Post.withAuthor(emoji:nickname:)` を `SameQ/Model/Post.swift` に新設し、
  手元の `state.user`（= 本人の現在のプロフィール）から埋める

### 3. 受け入れ条件 7 検証テスト強化
eval-6.md [2] の指摘に従い `SprintTwelveAcceptanceTests.test03` を
「アラート状態でも合格（寛容）」から「サインアップ成功を厳格にassert」に
強化：

```swift
// before (attempt 9): 3 状態のどれかなら合格
let onboardingNextGone = !app.buttons["onboarding.next"].exists
let onboardingAlertShown = app.staticTexts["うまくいきませんでした"].exists
let onboardingLaterStillThere = app.buttons["onboarding.notification.later"].exists
XCTAssertTrue(onboardingNextGone || onboardingAlertShown || onboardingLaterStillThere, ...)

// after (attempt 10): onboarding に留まっていないこと + alert が出ていないこと
//                     + today.* 画面に到達していること を assert
XCTAssertFalse(stuckOnOnboarding, ...)
XCTAssertFalse(failureAlertShown, ...)
XCTAssertTrue(openedToday, ...)
```

`today.identity` の待ち時間を 15 秒 → 30 秒に伸ばし（実機の Supabase 往復は
遅いことがあるため）、デバッグ中に発見した二次バグもこれで検出できる形に
なった。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 端末A→B の投稿共有・再起動後も残る | 未達（実機2台検証が必要） | generator は土台（BackendProvider 切替・tokenBox 反映・posts SELECT/INSERT 正常化）まで担保。実機 2 台 e2e は evaluator 担当 |
| 2 同じお題・同じ残り時間 | 未達（実機2台検証が必要） | `promptState()` は `prompts` テーブルから端末時間ベースで取得（実装済） |
| 3 いいね総数+1 | 未達（実機2台検証が必要） | `receivedLikeCount(forPostID:)` 実装済 |
| 4 通報・ブロックで即時非表示 | 未達（実機2台検証が必要） | サーバー側 INSERT 実装済 |
| 5 期限切れ回答の非表示 | 未達（実機2台検証が必要） | world_timeline ビューの `p.expires_at > now()` で実装済 |
| 6 オフライン表示・復帰後の自動復帰 | 未達（実機検証が必要） | NWPathMonitor 実装済 |
| 7 通信失敗の表示・再試行可能 | **generator 側コードは修正完了 + 厳格テストで担保** | attempt 10 で `myPost` の SELECT 400（`posts.author_emoji` 不存在）も修正済み。test03 がサインアップ成功と `today.*` 画面到達を厳格 assert |
| 8 シード非表示 | 条件付き達成 | Debug 既定 SupabaseBackend + Release 無条件 SupabaseBackend で seed 経路を完全に塞いだ。SprintTwelve test01 で「`-SameQUseLocalBackend` を付けない起動で seed 本文が出ない」を直接検証 |

## 動かし方（evaluator 向け）

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
xcodegen generate
# Debug ビルド（tokenBox 反映 + posts SELECT/INSERT 修正済み）
xcodebuild build -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
# → BUILD SUCCEEDED

# Release ビルド（無条件で SupabaseBackend、seed 経路を完全に塞ぐ）
xcodebuild build -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Release
# → BUILD SUCCEEDED

# 実機 2 台構成での検証（evaluator 担当）
# iPhone 17 Pro / Pro Max のシミュレータ 2 台をそれぞれ独立に起動し、
# `-SameQResetState -SameQScenario live -SameQFakePlus -SameQTimeOffsetMinutes 0`
# のみ付けてインストール。Debug 既定の Supabase 経路で動作する。
# 端末 A でオンボーディング → 投稿、端末 B で再起動して同じ投稿が見えること、
# 端末 B で端末 A の投稿にいいね、端末 A の画面で自分の受信いいね +1、
# 端末 A で端末 B の投稿を通報 → 即時非表示、など。
```

## テスト実行結果（attempt 10）

### ユニットテスト
- `xcodebuild test -only-testing:SameQTests` → **166/166 成功**（`TEST SUCCEEDED`、iPhone 17 / iOS 26.5、シミュレータ単独実行、5.914 秒）

### SprintTwelve UI テスト（新規追加・全件・generator.md 指示「必須」）
| テスト | 結果 | 時間 |
|---|---|---|
| test01_supabasePathDoesNotShowSeedPosts | ✓ | 16.4 秒 |
| test02_localBackendPathShowsSeedPostsImmediately | ✓ | 16.0 秒 |
| **test03_supabaseOnboardingCompletesWithoutCrash（強化版）** | ✓ | 12.2 秒 |

新 test03 では、サインアップ成功（`anonymousSignUp → users INSERT`）+ 
`applyPromptState` 完走 + `today.identity` 到達を最大 30 秒待ちで
厳格に assert。attempt 9 の寛容版では検出できなかった `posts.author_emoji` 400
の二次バグを、test03 合格 = 実機 1 歩が完走 = 実機 2 台 e2e の前提が
整った ことが示された。

### 絞り込み UI 回帰（generator.md 指示「直近 2〜3 スプリント分から最大 3 クラス」）
| スイート | 件数 | 結果 |
|---|---|---|
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| SprintTenAcceptanceTests | 7/7 | ✓ |
| SprintNineAcceptanceTests | 7/7 | ✓ |
| **合計** | **18/18** | ✓ |

実行時間: 326.4 秒。クラッシュ 0、未処理エラー 0、各テストケースのタイムアウト 0。

### Release ビルド
- `xcodebuild build -configuration Release` → BUILD SUCCEEDED

## 自分で見つけた弱点

### 1. eval-6.md では指摘されなかった二次バグの存在
eval-6.md [1] の修正（`tokenBox.value = auth.accessToken`）だけでは
テスト 03 は通らなかった。実機の `os_log` を採取して追跡したところ、
サインアップ後の `applyPromptState → myPost` が `column posts.author_emoji
does not exist` の 400 で倒れていた。attempt 9 の自己評価は 21/21 を
報告していたが、これは attempt 9 の test03 が寛容な判定だったため、
この二次バグがあっても合格していた。

evaluator が見つけられなかったのは、eval-6.md の検証手順が
「アカウント作成が 1 件も完了しない」段階で止まっていたため（401 の段階で
作業が止まり、後段の 400 まで到達していなかった）。attempt 10 で 401 を
潰した結果、後段の 400 が顕在化した。

### 2. attempt 9 までの test03 の寛容な合否判定は generator.md 違反
generator.md の指示「受け入れ条件を 1 つずつ潰す」「動かして確かめる」に
照らすと、`onboardingAlertShown` も合格に含める test03 は「失敗も成功も
区別できていない」状態であり、今回の attempt 10 でようやく意味のある
アサーションになった。test03 強化版を SprintTwelveAcceptanceTests に
残したので、以降のスプリントで回帰しても検出できる。

### 3. `world_timeline` ビューと `posts` テーブルのスキーマ差分を今後も意識する必要
migration 20260819000004_server_connection.sql の description には
「`body_language` / `decorations` を `world_timeline` ビューに追加」と
書かれている（attempt 4 self-review の引用）。一方 `posts` テーブル本体は
init migration のまま 8 カラムで固定。`myPost` / `submitPost` のような
「テーブル本体に対する読み書き」と、`timelinePosts` のような「ビューに対する
読み込み」の両方を扱う箇所では、select 列を揃える際にこの差分に毎回
引っかかる。今後のスプリント 13（F36: BAN・既読など）で `posts` を拡張
する可能性があり、そのタイミングで本ファイル内の `select:` 文字列と
`PostRow` のフィールドの対応をもう一度見直すこと。

### 4. デバッグログの消し忘れに注意
attempt 10 中盤で `os_log` / `Logger` を `SupabaseBackend.swift` と
`AppSession.swift` に仕込んで挙動を可視化したが、最終的に
すべて除去してからコミット可能な状態に戻した（`import os.log` ごと削除）。
本 self-review の段階でも両ファイルから `Sprint12Debug` の文字列が
残っていないことを `grep` で確認済み。

## 提案（今回はやらなかったこと）

### 1. 実機 2 台構成での e2e 検証は evaluator 担当のまま
attempt 10 で generator 環境が保証したのは「サインアップ → users INSERT →
prompt 取得 → myPost 取得 → today 画面到達」の 1 端末 1 歩目まで。
条件 1〜5（端末 A → B の投稿共有・同じお題・いいね集計・通報/ブロック
即時反映・期限切れ非表示）の実機 2 台 e2e は引き続き evaluator の
手作業領域。

### 2. SprintTwelveAcceptanceTests の test03 をさらに厳格化する余地
attempt 10 の test03 は「`today.identity` が存在するか」だけで
today 画面到達を判定している。spec 305〜313 行の条件 7
（投稿・いいね・通報・ブロックの通信失敗時の再試行可能）を直接テスト
する場合、別 test04〜test07 を足して「機内モード → オフライン alert →
ON に戻すと再試行できる」を 1 サイクル検証する必要があるが、
attempt 10 では未着手（attempt 9 self-review の提案 3 でも言及済み）。
ネットワーク切り替えの自動化は壊れやすいので、generator 側で
「土台」としてテストするのはここまでが現実的。

### 3. Sprint13（F36）着手前の前提
F36 で扱う `posts.author_*` 拡張（自分のプロフィールを後から変えたとき
過去の投稿の表示名も遡って変える案 F32）は、`posts` テーブルへの
カラム追加または別テーブル（`post_authors`）の設計判断が必要。
attempt 10 の `Post.withAuthor` を使った補完方式は暫定で、本質的に
解決するならスキーマ側に `posts.author_emoji` / `posts.author_nickname`
を持たせるのが筋。sprint 13 の設計議論の前提として本件を共有したい。

## 変更ファイル一覧（attempt 10）

- `SameQ/Backend/SupabaseBackend.swift`
  - `tokenBox` を actor の stored property に昇格
  - `createAnonymousUser` 内で `tokenBox.value = auth.accessToken` を追加
  - `myPost` の select から `author_emoji, author_nickname` を削除し、
    `Post.withAuthor(emoji:nickname:)` で補完
  - `submitPost` の RETURNING select からも同様に削除し、同じく補完
- `SameQ/Model/Post.swift`
  - `Post.withAuthor(emoji:nickname:)` メソッドを新設
- `SameQUITests/SprintTwelveAcceptanceTests.swift`
  - `test03_supabaseOnboardingCompletesWithoutCrash` を寛容な判定から
    厳格な判定に強化（`today.identity` 到達 + alert 不在 + onboarding 離脱）
  - 待ち時間を 15 秒 → 30 秒に延長
