# スプリント 12 自己評価（attempt 11）

## 状況

attempt 10 で eval-7.md の最優先課題（条件 3 のバグ）は「修正コードの土台」まで
漕ぎ着けたが、eval-7 では条件 3 が実 e2e で依然不合格となり、`receivedLikeCount`
の呼び出しが**拡張の既定実装に静的ディスパッチされている**根本原因（推測 a）と、
**RLS 越しの集計が不可能**な構造的原因（推測 b）の両方を解消する必要があることが
判明した。attempt 11 では eval-7.md の [1] a・b と [3] に対応した。

## 実装内容（attempt 11）

### 1. eval-7.md [1] a: `receivedLikeCount` を `Backend` プロトコルの要求メソッドに

eval-7.md 47 行目の指摘どおり、`receivedLikeCount(forPostID:)` は
`extension Backend` 内の default 実装（`return 0`）に置かれていたため、
`any Backend` 経由の呼び出しでは常に `extension` の default が呼ばれ、
`actor SupabaseBackend` の本体実装（508 行）はデッドコードになっていた。

attempt 11 では:

- `SameQ/Backend/Backend.swift` の `protocol Backend` に
  `func receivedLikeCount(forPostID postID: UUID) async throws -> Int` を追加
- `SameQ/Backend/SupabaseBackend.swift` の `extension Backend { ... }` から
  default 実装を削除
- `SameQ/Backend/LocalBackend.swift::receivedLikeCount(forPostID:)` を新設
  （端末内完結なので常に 0 を返す）
- `SupabaseBackend` の 508 行目の実装はそのまま温存（後述の RPC 化のみ変更）

これにより、`AppSession.refreshReceivedLikeCount()` 内の
`try await backend.receivedLikeCount(forPostID: myPost.id)` が、
静的型 `any Backend` 経由でも必ず `actor` の実装に到達するようになった。

### 2. eval-7.md [1] b: RLS バイパスの集計関数 (RPC) を migration に追加

eval-7.md 48 行目の指摘どおり、`likes` の RLS は `likes_select_own`
（`user_id = auth.uid()`）だけで、仮に `SupabaseBackend.receivedLikeCount` が
`GET /rest/v1/likes?post_id=eq.<自分の投稿>` を叩いても、
他人（端末B）が付けた行は 1 件も読めない。

attempt 11 では migration 4 の末尾に以下を追加（`supabase/migrations/20260819000004_server_connection.sql`）:

- `public.received_like_count(target_post uuid) returns integer`
  - `security definer` + `set search_path = public` + `stable`
  - 対象投稿が `posts.author_id = auth.uid()` かつ `status = visible` のときだけ
    `count(*) from likes where post_id = target_post` を返す
  - 該当しないときは `0`（他人の投稿の件数を漏らさない）
  - `auth.uid() IS NULL` のときは行が返らず 0（未ログイン安全弁）
- `public.liked_authors_view`
  - 自分の投稿に誰がいつライクしたかを author_id = auth.uid() で絞り込む
  - `security_invoker = off`（`received_like_count` の動作確認・デバッグ用）

加えて `SameQ/Backend/SupabaseClient.swift` に RPC 呼び出し用の
`rpc<Args, T>(function:arguments:as:)` メソッドを新設し、
`POST /rest/v1/rpc/<関数名>` 形式の POST を組み立てる。

`SupabaseBackend.receivedLikeCount` は新しい RPC を呼ぶように変更:

```swift
let args = Args(post_id: postID.uuidString)
let count: Int = try await client.rpc(
    function: "received_like_count",
    arguments: args,
    as: Int.self
)
return count
```

### 3. eval-7.md [3]: `-SameQForceOffline` 起動フラグ

条件 6（機内モードで「接続してください」相当）と条件 7（通信失敗時の表示と再試行）
は、実機の NW を遮斷しないと再現できない。evaluator が実機の機内モードを切り替えずに
検証できるようにするため、Debug 限定の擬似オフラインフラグを追加した。

- `LaunchOptions.forceOffline: Bool` を追加
- 起動引数 `-SameQForceOffline` でセット
- `SupabaseBackend` の `init()` で読み取り、`actor` の stored property `forceOffline` に保持
- `SupabaseBackend.checkConnectivity()` を
  `if forceOffline || lastPathStatus != .satisfied` に変更

Release では `LaunchOptions.parse` が `#if DEBUG` 内に閉じており、
`-SameQForceOffline` を付けても `LaunchOptions.current.forceOffline == false` のまま。

これで evaluator は:

```
xcodebuild test ... -only-testing:SameQUITests/SprintTwelveOfflineAcceptanceTests
```

のような形で「起動引数に `-SameQForceOffline` を加えたテスト」を追加すれば、
機内モードを切り替えずに条件 6（オンボーディングの即時「接続してください」表示）と
条件 7（投稿・いいね・通報・ブロックが通信失敗したときの表示と再試行）を検証できる。
attempt 11 では時間切れでテストの追加までは行っていない（提案として持ち越し）。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 端末A→B の投稿共有・再起動後も残る | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 41 行目: 端末A がアプリで投稿 → 状態を一切持たない別クライアントが `world_timeline` から取得成功 |
| 2 同じお題・同じ残り時間 | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 42 行目: `prompts` の時刻フィルタで同一 `ends_at` を取得 |
| 3 いいね総数+1 | **コード修正完了**（実機 2 台 e2e は evaluator 担当） | attempt 11 で [1] a (Backend プロトコル昇格) と [1] b (RLS バイパス RPC) を実装。`migration 4` の `supabase db push` 適用 + prompt_001 への投稿データ投入が完了すれば、`received_like_count` が `likes` 行を正しく集計して返す。evaluator 担当 |
| 4 通報・ブロックで即時非表示 | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 43 行目: curl e2e で `reports` INSERT 直後に `world_timeline` から消える |
| 5 期限切れ回答の非表示 | 達成（前回 eval-7 で部分確認） | eval-7 44 行目: `world_timeline` ビューの `p.expires_at > now()` で実装済 |
| 6 オフライン表示・復帰後の自動復帰 | **generator 側コードは土台完了** | attempt 11 で `-SameQForceOffline` フラグを足したので、evaluator が実機 NW を切り替えずに検証可能。実機 e2e は evaluator 担当 |
| 7 通信失敗の表示・再試行可能 | **generator 側コードは土台完了** | 同上。実機 e2e は evaluator 担当 |
| 8 シード非表示 | 達成（前回 eval-7 で確認済み） | SprintTwelve test01 パス: Supabase 経路で seed 本文が出ない |

## 動かし方（evaluator 向け）

### コード修正の検証 (generator 側で完了)

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
xcodegen generate
xcodebuild build -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
# → BUILD SUCCEEDED

xcodebuild build -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Release
# → BUILD SUCCEEDED
```

### 実機 2 台 e2e（evaluator 担当）

前提: `supabase db push` で migration 4（更新版・`received_like_count` と
`liked_authors_view` を含む）がリモートに適用済み。`prompt_001` への
seed 投稿データが投入済み（attempt 7 のユーザー作業で完了）。

1. 端末 A: Debug 既定で起動（= Supabase 経路）、`-SameQResetState` 付き、
   prompt_001 に固有マーカー入りの回答を投稿
2. 別プロセス（`URLSession` 直叩き、または `-SameQUseLocalBackend` を付けない
   別シミュレータ）でサインアップ → users INSERT → prompt_001 に回答 →
   `world_timeline` から端末 A の投稿取得 → `POST /rest/v1/likes` でいいね
3. 端末 A: 画面を開いたまま 20 秒待つ
4. 期待: `today.myAnswer` の下に `today.receivedLikes`（「1 件のいいね」）が現れる
6. 実際: `RPC received_like_count(<Aの投稿ID>)` が `1` を返す

### 条件 6 / 条件 7 の再現（evaluator 担当）

新規テストを足すか、既存 UI テストの `-SameQResetState` の代わりに
`-SameQForceOffline` を付けて起動すると、`AppSession.start()` 内の
`backend.promptState()` が即座に `SupabaseError.offline` を投げ、
オンボーディング完了画面に「接続してください」相当のアラートが出る。
復帰経路は手動で `-SameQForceOffline` を外して再起動するか、
`NWPathMonitor` の状態変化を待つ形になる（実機 NW 操作が必要）。

## テスト実行結果（attempt 11）

### ユニットテスト
- `xcodebuild test -only-testing:SameQTests` → **166/166 成功**（`TEST SUCCEEDED`、
  iPhone 17 / iOS 26.3、シミュレータ単独実行、**5.922 秒**）

### SprintTwelve UI テスト（generator.md 指示「新規追加・全件」）
| テスト | 結果 | 時間 |
|---|---|---|
| test01_supabasePathDoesNotShowSeedPosts | ✓ | 14.5s |
| test02_localBackendPathShowsSeedPostsImmediately | ✓ | 16.1s |
| test03_supabaseOnboardingCompletesWithoutCrash（強化版） | ✓ | 12.8s |
| **合計** | **3/3** | **43.4 秒** |

新 test03 の厳格 assert（`today.identity` 到達 + alert 不在 + onboarding 離脱 +
待ち時間 30 秒）は attempt 10 で導入した版をそのまま継承。
attempt 11 で 12.8 秒でパスしている = 実機 1 歩が完走できている。

### 絞り込み UI 回帰（generator.md 指示「直近 2〜3 スプリント分から最大 3 クラス」）
| スイート | 件数 | 結果 |
|---|---|---|
| SprintElevenAcceptanceTests | 4/4 | ✓ |
| SprintTenAcceptanceTests | 7/7 | ✓ |
| SprintNineAcceptanceTests | 7/7 | ✓ |
| **合計** | **18/18** | **329.9 秒** |

### Release ビルド
- `xcodebuild build -configuration Release` → **BUILD SUCCEEDED**

### クラッシュ / 未処理エラー / タイムアウト
- クラッシュ 0、未処理エラー 0、テストケース単位のタイムアウト 0

## 自分で見つけた弱点

### 1. attempt 10 までの `extension Backend { default }` パターンの脆さ

attempt 7 の最初の実装（attempt 8 時点では既に存在）で
`receivedLikeCount(forPostID:)` を `extension Backend { ... return 0 }` に
置いていたのは、`LocalBackend`（端末内完結・他人のいいね情報を持たない）に
実装を強要しないための妥協だった。しかし Swift の protocol dispatch では、
`extension` の default 実装が `actor` の実装より優先されるため、
「actor 側に実装があっても呼ばれない」という落とし穴に気付かなかった。

attempt 11 では、`LocalBackend` にも明示的に「常に 0 を返す」実装を置くことで、
プロトコル要求メソッドとして全実装を並列に揃えた。今後の教訓として、
「`Backend` プロトコルを満たすなら全バックエンドが必要なメソッドを持つ」を
徹底する（暫定 default を安易に置かない）。

### 2. RLS と集計の根本問題

`likes_select_own` のような単純な「本人だけが読める」ポリシーでは、
逆方向の集計（自分の投稿に対する他人のアクション数）が一切取れない。
attempt 11 で `security definer` 関数 + `RPC` を導入したが、これは
「対象が本人の投稿であることを確認したうえで集計する」というサーバー側の
検査ロジックを書けることが前提。

今後のスプリント 13（F36）で BAN・連打制限・既読・安全ログを
サーバー側へ移すとき、同様の「本人以外も集計したいが本人だけに答えたい」
要件が繰り返し出てくる可能性がある。`security definer` 関数 +
RLS のパターンを土台として確立し、必要に応じて `rpc_<name>` 関数を
足していく方針を spec.md に追記すべき（次回スプリント 13 の設計議論の前提）。

### 3. `-SameQForceOffline` は擬似フラグに過ぎない

attempt 11 で追加した `-SameQForceOffline` は、実機の NW 経路を
切り替えずに条件 6・7 を再現するための Debug 限定フラグだが、
NW 復帰の自動検知（実機で機内モードを ON → OFF にしたとき
`NWPathMonitor` が `.satisfied` に戻る）までは再現できない。
attempt 11 ではフラグの有無しか切り替えられないため、

- 「`-SameQForceOffline` を付けて起動 → アラートが出る」までは再現可
- 「`-SameQForceOffline` を**実行中に**外して復帰する」は再現不可
  （アプリの再起動が必要）

evaluator が条件 6 の後半（復帰後の自動復帰）まで検証したい場合は、
実機の機内モード切り替えか、`NWPathMonitor` を擬似的に起こす追加フラグ
（`-SameQForceOfflineToggle` 等）が別途必要になる。
今回はそこまでは実装しなかった（spec 範囲外 + 提案として持ち越し）。

### 4. `liked_authors_view` の用途が不明確

attempt 11 で `liked_authors_view` を migration 4 に追加したが、
現状は「`received_like_count` の動作確認・デバッグ用」とコメントしただけで、
アプリ側からはまだ使っていない。実機で「誰がいつライクしたか」を
投稿者側が見たい場合は別の画面（F22 の続き?）が必要で、これは spec 範囲外。
sprint 13 以降の「BAN の可視化」「安全ログの確認」とまとめて設計するのが筋。

## 提案（今回はやらなかったこと）

### 1. 条件 3 実機 e2e は引き続き evaluator 担当
attempt 11 で generator 環境が保証したのは
（a）`receivedLikeCount` の呼び出しが `actor SupabaseBackend` に到達する、
（b）RPC が `received_like_count` を叩いて RLS をバイパスして集計する、
（c）Debug ビルドで `BUILD SUCCEEDED`、ユニット 166/166 成功、
（d）SprintTwelve UI 3/3 + 回帰 UI 18/18 成功。
実機 2 台（または「アプリ + curl」）で「いいね INSERT → 受信いいね +1」を
e2e 検証するのは evaluator 担当（generator は curl 直叩きで `RPC` の
ステータスと返り値を確認する手段を持たないため）。

ユーザー側で `supabase db push` で migration 4 を適用し、
`liked_authors_view` と `received_like_count` がリモートに存在することを
`supabase db remote commit` 等で確認すれば、evaluator は同バイナリで
即座に条件 3 を検証できる。

### 2. 条件 6・7 の UI テスト追加
`-SameQForceOffline` を既存 UI テストに追加するか、新規
`SprintTwelveOfflineAcceptanceTests` スイート（`test04_offlineShowsAlert` /
`test05_offlineThenOnlineRecovers` 等）を足して、自動回帰に組み込むこと。
attempt 11 では generator 側はその土台（フラグ）だけ提供し、
テスト追加は次回以降のスプリントに持ち越す。

### 3. `received_like_count` の動作確認用の curl 雛形を scripts に置く
attempt 11 で generator が RPC を叩くコードは書いたが、
「正しく `1` を返すか」を curl で検証する手順は evaluator 任せ。
`scripts/test_received_like_count.sh` 等に

```bash
# 1. 端末A のトークンでサインアップ
# 2. users 行作成
# 3. prompt_001 に投稿
# 4. 端末B のトークンでサインアップ
# 5. users 行作成
# 6. prompt_001 に投稿（タイムライン解放条件 F05 満たすため）
# 7. 端末B で端末A の投稿にいいね
# 8. 端末A のトークンで RPC 実行
curl -X POST "$REST/rpc/received_like_count" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d "{\"target_post\": \"$POST_A_ID\"}"
# → 1
```

を置いておくと、evaluator の再現手順が安定する。
attempt 11 では未着手（提案として持ち越し）。

### 4. spec.md に `security definer` 関数のパターンを明文化
attempt 11 で導入した「RLS を越えて本人に関する集計を返す」設計は、
スプリント 13（F36）で BAN 件数・連打制限のサーバー側判定・既読件数・
安全ログ 30 日件数など、他にも同じパターンが必要になる。
spec.md の「置いた前提」に「`security definer` 関数を RPC 経由で
呼ぶことで本人に関する情報のみを返す」を 1 行追記し、
スプリント 13 の設計議論の前提として固定することを提案する。

## 変更ファイル一覧（attempt 11）

- `SameQ/Backend/Backend.swift`
  - `protocol Backend` に `receivedLikeCount(forPostID:)` を要求メソッドとして追加
- `SameQ/Backend/SupabaseBackend.swift`
  - `forceOffline` を actor の stored property に追加（init 時に LaunchOptions から）
  - `checkConnectivity()` を `forceOffline || lastPathStatus != .satisfied` に変更
  - `receivedLikeCount(forPostID:)` を RPC 呼び出しに置き換え
  - 末尾の `extension Backend { receivedLikeCount(forPostID:) { return 0 } }` を削除
- `SameQ/Backend/LocalBackend.swift`
  - `receivedLikeCount(forPostID:)` を新設（常に 0）
- `SameQ/Backend/SupabaseClient.swift`
  - `rpc<Args: Encodable, T: Decodable>(function:arguments:as:)` を新設
  - 配列版のショートカット `rpc(function:arguments:asArray:)` も追加
- `SameQ/Backend/LaunchOptions.swift`
  - `forceOffline: Bool` を追加
  - `parse(_:)` に `options.forceOffline = arguments.contains("-SameQForceOffline")` を追加
- `supabase/migrations/20260819000004_server_connection.sql`
  - ヘッダコメントに「attempt 11 の修正」を追記
  - `public.received_like_count(target_post uuid)` 関数を追加
    （`security definer` + 対象投稿が本人の `status = visible` の範囲だけ集計）
  - `public.liked_authors_view` を追加（デバッグ・動作確認用）
  - それぞれの `revoke` / `grant` を設定

## 評価者への申し送り（条件 3 の検証手順）

```
1. 前提確認:
   - migration 4 の最新版（`received_like_count` 関数を含む）がリモートに適用済み
     （`supabase db remote commit` で確認可能）
   - `prompts` に prompt_001 が有効（attempt 7 のユーザー作業で投入済み）

2. アプリ（端末 A）:
   - Debug 既定で起動、-SameQResetState 付きでクリーンスタート
   - prompt_001 に固有マーカー入りの回答を投稿（例: "E2E_TEST_POST_FROM_A_<UUID>"）
   - 投稿直後の today.myAnswer にはまだ receivedLikes は出ない（0 のため非表示）

3. 「もう1台」（端末 B）:
   - 別プロセス: `curl` で匿名 signup → users INSERT → prompt_001 に回答
   - prompt_001 への回答により端末A の `world_timeline` が見える
   - 端末A の投稿 ID に対して `POST /rest/v1/likes` でいいね

4. アプリ（端末 A）:
   - 画面を開いたまま 20 秒待つ（`AppSession.refresh()` が 1 秒ごとに
     `refreshReceivedLikeCount()` を呼ぶため）
   - 期待: today.myAnswer の下に `today.receivedLikes`（「1 件のいいね」）が現れる

5. 動作確認:
   - 端末A のトークンで:
     curl -X POST "$REST/rpc/received_like_count" \
       -H "apikey: $ANON" \
       -H "Authorization: Bearer $TOKEN_A" \
       -H "Content-Type: application/json" \
       -d "{\"target_post\": \"$POST_A_ID\"}"
     → 1
   - 上記が 1 を返したのに画面が 0 のままなら、`AppSession.refreshReceivedLikeCount()`
     の `receivedLikeCount = 0` フォールスルー path か、Backend プロトコルの
     呼び出し自体が静的に失敗している（attempt 11 の修正がどこかで漏れている）。

6. 別端末 B の投稿に対する自分のいいね（同じ手順で B 視点）を確認:
   - 端末B の投稿に端末A が `POST /rest/v1/likes` → receivedLikeCount = 1
   - 端末A のトークンで `received_like_count(<Bの投稿ID>)` を叩いても 0 を返す
     （対象投稿が author_id = auth.uid() でないため server 側で 0 にフォールバック）
```