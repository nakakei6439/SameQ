# スプリント 12 自己評価（attempt 12）

## 状況

attempt 11 で eval-7.md の [1] a・b と [3] には対応したが、eval-8.md で
「`received_like_count` 関数と `liked_authors_view` を **既に本番適用済み**
の migration 4 の末尾に追記した」ため `supabase db push` で再適用されず、
`POST /rest/v1/rpc/received_like_count` が本番で 404 PGRST202 を返して
条件 3 が依然不合格、という構造的欠陥が新規に判明した。

attempt 12 では eval-8.md の改善提案 1〜3 すべてに対応した:

1. 関数とビューを **新規マイグレーションファイル** `20260820000005_received_like_count.sql`
   に切り出し（eval-8 改善提案1）。`supabase db push` で初めて本番に適用される。
2. `AppSession.refreshReceivedLikeCount()` の catch ブロックを修正し、
   `SupabaseError.notFound`（PGRST202）のときだけ `alertMessage` を立てるように
   した（eval-8 改善提案3）。これで「関数が未適用 = 受信いいね 0」のまま
   永久に無言になる状態を解消。
3. 条件 6・7 を `-SameQForceOffline` で毎回自動回帰に組み込む
   `SprintTwelveOfflineAcceptanceTests` を新規追加（eval-8 改善提案3）。
   4 操作（オンボーディング・いいね・通報・ブロック）のうち起動時に
   即座に検証できる 2 件をカバー。

## 実装内容（attempt 12）

### 1. eval-8.md [1] の修正: 関数・ビューを新規 migration へ切り出し

`supabase/migrations/20260820000005_received_like_count.sql` を新規作成し、
`received_like_count(target_post uuid)` 関数と `liked_authors_view` を
そちらへ移動した。`create or replace` で冪等なので、適用済みか否かを
問わず動作する。

- `received_like_count`: `security definer` + `set search_path = public`
  + `stable` で `auth.uid()` が NULL のとき 0、対象投稿が本人の `status = visible`
  の範囲外のとき 0、それ以外は対象投稿の `likes` 行件数を返す。
- `liked_authors_view`: `security_invoker = off` で「誰がいつライクしたか」を
  `auth.uid()` 経由で本人の投稿に絞り込む。
- `revoke all ... from public` / `grant execute ... to authenticated` /
  `grant select ... to authenticated` も両方とも冪等。

migration 4 側の同じ定義は **そのまま温存**（`create or replace` なので
上書きで衝突しない。むしろ二重定義のほうが本番上で関数が確実に存在することを
二重に担保できる）。

これで evaluator は `supabase db push` を叩けば migration 5 が初めて
リモートへ適用され、`received_like_count` が本番に存在する状態になる。

### 2. eval-8.md [2] の強靭化: refreshReceivedLikeCount の無言フォールスルー解消

`SameQ/Session/AppSession.swift::refreshReceivedLikeCount()` の catch ブロックを
`catch let error as SupabaseError { ... }` に変更し、`case .notFound = error` の
ときだけ `alertMessage` を立ててユーザー（と Debug ログ）に「サーバー機能の
一部が未適用」であることを知らせる。

それ以外のエラー（offline / transport / server 等）は従来どおり静かに
`receivedLikeCount = 0` に戻す（バックエンドが古い・権限が無い等の状況でも
画面を止めない）。これで条件 7「無言で失敗しない」の趣旨を `receivedLikeCount`
の経路にも適用できる。

### 3. eval-8.md 改善提案3: SprintTwelveOfflineAcceptanceTests 新設

`SameQUITests/SprintTwelveOfflineAcceptanceTests.swift` を新規追加。
`#if DEBUG` の `LaunchOptions.forceOffline` / 起動引数 `-SameQForceOffline`
を使い、evaluator が実機の機内モードを切り替えなくても条件 6・7 を毎回
自動回帰に組み込めるようにした。

- test01_forceOfflineShowsFailureView:
  `-SameQForceOffline` 起動で `RootView.failureView` の 3 要素
  （タイトル「読み込めませんでした」/ メッセージ本文に「通信できません」を
  含む / リトライボタン「もう一度試す」）が出ることを assert。
  simctl 直叩き（PID 66771）と XCUITest 出力で確認済み。
- test02_forceOfflineRetryStaysOnFailureView:
  `-SameQForceOffline` 起動 → 「もう一度試す」をタップ → 同じ `forceOffline`
  で再実行されるので再び同じ failure 画面が出る（retry が効かない /
  クラッシュする / 別画面に遷移する状態に **陥っていないこと** を確認）。
- test03_normalSupabaseLaunchIsNotAffectedByForceOffline:
  `-SameQForceOffline` を**付けない**通常起動で 30 秒以内に
  onboarding（`onboarding.next` ボタン）に到達し、`failure.root` には
  着地しないことを確認。フラグの付け忘れ検知の回帰。

実装でハマった点（参考まで）: 最初の実装では `app.staticTexts["failure.title"]`
のように `accessibilityIdentifier` で要素を取得していたが、iOS 26 + Xcode 26
の XCUITest では `Text` に付けた `accessibilityIdentifier` が XCUI ツリーで
空文字列として観測される（`Text` の modifier 順序と `.font` /
`.foregroundStyle` の影響を受ける SwiftUI 内部実装の問題と推測）。
`HStack` や `Button` に対する `accessibilityIdentifier` は問題なく拾えるので、
最終的にはラベル文字列（「読み込めませんでした」「もう一度試す」）と
「通信できません」の部分一致で assert する形に変更した。これは
attempt 12 の修正であって、実装側のバグではない。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1 端末A→B の投稿共有・再起動後も残る | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 41 行目: 端末A がアプリで投稿 → 状態を一切持たない別クライアントが `world_timeline` から取得成功 |
| 2 同じお題・同じ残り時間 | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 42 行目: `prompts` の時刻フィルタで同一 `ends_at` を取得 |
| 3 いいね総数+1 | **コード修正完了 + DB 配布経路を修正**（実機 2 台 e2e は evaluator 担当） | attempt 11 で `receivedLikeCount` を Backend プロトコル要求に昇格、attempt 12 で関数・ビューを **新規マイグレーション 5** に切り出し。evaluator が `supabase db push` で migration 5 をリモートに適用すれば `POST /rest/v1/rpc/received_like_count` が 200 を返す |
| 4 通報・ブロックで即時非表示 | 達成（前回 eval-7 で実 e2e 確認済み） | eval-7 43 行目: curl e2e で `reports` INSERT 直後に `world_timeline` から消える |
| 5 期限切れ回答の非表示 | 達成（前回 eval-7 で部分確認） | eval-7 44 行目: `world_timeline` ビューの `p.expires_at > now()` で実装済 |
| 6 オフライン表示・復帰後の自動復帰 | **自動回帰テスト追加** | `SprintTwelveOfflineAcceptanceTests.test01_forceOfflineShowsFailureView` で `-SameQForceOffline` 起動時の failure 画面を assert（3/3 で 18.2 秒、TEST SUCCEEDED） |
| 7 通信失敗の表示・再試行可能 | **自動回帰テスト追加 + `receivedLikeCount` の無言フォールスルー解消** | `SprintTwelveOfflineAcceptanceTests.test02_forceOfflineRetryStaysOnFailureView` で retry の挙動を assert。`refreshReceivedLikeCount()` で `SupabaseError.notFound` のとき `alertMessage` を出すように変更 |
| 8 シード非表示 | 達成（前回 eval-7 で確認済み） | SprintTwelve test01 パス: Supabase 経路で seed 本文が出ない |

## 動かし方（evaluator 向け）

### コード修正の検証 (generator 側で完了)

```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
xcodegen generate
xcodebuild build -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug
# → BUILD SUCCEEDED
```

### 実機 2 台 e2e（条件 3 の検証手順）

前提:
- Supabase ダッシュボードで匿名サインインが有効（eval-5 で確認済み）
- `supabase db push` で migration **5**（`20260820000005_received_like_count.sql`）
  がリモートに適用済み（attempt 12 で新規追加）

1. 端末 A: Debug 既定で起動、`-SameQResetState` 付き、prompt_001 に固有マーカー入りの
   回答を投稿
2. 別プロセス（`URLSession` 直叩き、または別シミュレータ）でサインアップ →
   users INSERT → prompt_001 に回答 → `world_timeline` から端末 A の投稿取得 →
   `POST /rest/v1/likes` でいいね
3. 端末 A: 画面を開いたまま 20 秒待つ（`AppSession.refresh()` が 1 秒ごとに
   `refreshReceivedLikeCount()` を呼ぶため）
4. 期待: `today.myAnswer` の下に `today.receivedLikes`（「1 件のいいね」）が現れる
5. 動作確認: 端末A のトークンで `POST /rest/v1/rpc/received_like_count` を叩くと 1 を返す

### 条件 6・条件 7 の自動回帰（generator 側で完了）

```bash
# SprintTwelveOfflineAcceptanceTests: 3/3 で 18.2 秒
xcodebuild test -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SameQUITests/SprintTwelveOfflineAcceptanceTests
# → TEST SUCCEEDED
```

実機の機内モードを切り替えずに:
- 条件 6（オフライン表示）: test01 で「読み込めませんでした」+
  「通信できません。ネットワーク接続を確認してください。」+
  「もう一度試す」が画面に出ることを担保
- 条件 7（再試行可能）: test02 で「もう一度試す」をタップしても
  クラッシュ・別画面遷移しないことを担保

## テスト実行結果（attempt 12）

### ユニットテスト
- `xcodebuild test -only-testing:SameQTests` → **166/166 成功**（`TEST SUCCEEDED`、
  iPhone 17 / iOS 26.3、シミュレータ単独実行、**5.935 秒**）

### SprintTwelve UI テスト（generator.md 指示「新規追加・全件」）
| スイート | テスト | 結果 | 時間 |
|---|---|---|---|
| SprintTwelveAcceptanceTests | test01 / test02 / test03 | 3/3 ✓ | 44.5s |
| SprintTwelveOfflineAcceptanceTests | test01 / test02 / test03（新規） | 3/3 ✓ | 18.2s |
| **合計** | | **6/6** | **62.7 秒** |

### 絞り込み UI 回帰（generator.md 指示「直近 2〜3 スプリント分から最大 3 クラス」）
| スイート | 件数 | 結果 | 時間 |
|---|---|---|---|
| SprintElevenAcceptanceTests | 4/4 | ✓ | (合計) |
| SprintTenAcceptanceTests | 7/7 | ✓ | (合計) |
| SprintNineAcceptanceTests | 7/7 | ✓ | (合計) |
| **合計** | **18/18** | ✓ | **329.6 秒** |

### Release ビルド
- `xcodebuild build -configuration Release` → **BUILD SUCCEEDED**

### クラッシュ / 未処理エラー / タイムアウト
- クラッシュ 0、未処理エラー 0、テストケース単位のタイムアウト 0

## 自分で見つけた弱点

### 1. SwiftUI `Text` への `.accessibilityIdentifier` が XCUITest から取得できない

attempt 12 で `SprintTwelveOfflineAcceptanceTests` を新規追加したとき、
最初の実装では `app.staticTexts["failure.title"]` のように `accessibilityIdentifier`
で要素を取得していたが、XCUITest のデバッグ出力で:

```
staticTexts labels=["読み込めませんでした", "通信できません。ネットワーク接続を確認してください。"]
buttons=["もう一度試す"]
ids=["", "failure.root"]
```

となった。`Text("読み込めませんでした").accessibilityIdentifier("failure.title")`
の **ラベルは取得できるが identifier が空**で、`HStack` や `Button` に対する
`accessibilityIdentifier` だけが機能している。これは iOS 26 + Xcode 26 の
SwiftUI 内部実装の問題と思われ、`Text` 側の `.font` / `.foregroundStyle` の
modifier 順序や `.accessibilityElement(children:)` の有無に影響される
既知の落とし穴。

今回はラベル文字列（「読み込めませんでした」「もう一度試す」）と
「通信できません」の部分一致で assert するように変更したが、他の場所でも
同じ罠がある可能性がある（既存の `today.identity` は `HStack` の identifier
なので問題なく拾えているが、もし誰かが `Text` に identifier を移すと
急にテストが落ちる）。

これは今後の改善提案（次スプリントの材料）として記録する。

### 2. `receivedLikeCount` の alertMessage は条件 7 を満たす反面、ノイズにもなる

attempt 12 で `SupabaseError.notFound` のとき `alertMessage` を出すように
したが、migration 5 が本番に**未適用**の間はこのアラートが出続ける。
eval-8.md の改善提案3 の趣旨（無言にしない）には沿うが、
ユーザー視点では「1 件もいいねが付いていないのにエラーが出る」状態になる。

本来は（a）migration 5 を適用すれば解決、（b）適用が属人化しているので
README か spec.md に運用手順を書くべき。attempt 12 では README までは
触らず、self-review の申し送り + migration 5 のコメントで対応する。

### 3. `liked_authors_view` は用途未定のまま

attempt 11 で追加、attempt 12 で migration 5 に移したが、
アプリ側からは依然使っていない（デバッグ / サポート用途を想定）。
sprint 13 以降の「BAN の可視化」「安全ログの確認」と合わせて設計する。

## 提案（今回はやらなかったこと）

### 1. README.md に migration 適用手順を明記

attempt 12 で初めて知った「Supabase のマイグレーションは **適用済みファイル**
を再 push しても無視される」という仕様は、generator だけでは気付きにくい。
README.md の Supabase セクションに「新しい関数 / ビューを追加するときは
**必ず新規ファイル**で `db push` する」運用ルールを 1 行書いておくと、
将来 evaluator / ユーザーが同じ落とし穴にハマらずに済む。

attempt 12 ではスコープ外として未実施。

### 2. `refreshReceivedLikeCount` 以外の経路も PGRST202 を可視化するか

attempt 12 では `receivedLikeCount` の PGRST202 だけ可視化した。
今後 `liked_authors_view` を実アプリが参照するようになったとき、
同様のパターンが他の集計関数でも出てくる可能性がある。
共通化は可能だが、現状は 1 箇所だけなので今回は行わない。

### 3. `-SameQForceOfflineToggle`（実行中トグル）

attempt 12 では `-SameQForceOffline` を **起動時のみ**読み取る実装のままだ。
「起動中に offline に切り替える → 復帰させる」を再現するには、
アプリ再起動か実機の機内モード切り替えが必要。
sprint 13 以降で `-SameQForceOfflineToggle` を足すと、条件 6 の
後半（復帰後の自動復帰）まで完全自動回帰に組み込める。

今回は実装せず提案として持ち越し。

## 変更ファイル一覧（attempt 12）

- `supabase/migrations/20260820000005_received_like_count.sql` （新規）
  - `received_like_count(target_post uuid)` 関数を `security definer` で定義
  - `liked_authors_view` を `security_invoker = off` で定義
  - `revoke` / `grant` を設定
- `SameQ/Session/AppSession.swift`
  - `refreshReceivedLikeCount()` の catch を `catch let error as SupabaseError`
    に変更し、`case .notFound = error` のときだけ `alertMessage` を立てる
  - Debug ログに「migration 20260820000005_received_like_count.sql is not applied」
    を出力（条件7 の無言失敗回避）
- `SameQUITests/SprintTwelveOfflineAcceptanceTests.swift` （新規）
  - test01: `-SameQForceOffline` 起動で failure 画面が出る
  - test02: retry ボタンで再実行してもクラッシュ / 別画面遷移しない
  - test03: フラグ無しで通常起動できる（フラグの付け忘れ検知）

## 評価者への申し送り（attempt 12 固有）

### 条件 3 を実 e2e で検証する手順（再掲）

```
1. 前提:
   - Supabase ダッシュボードで匿名サインインが有効（eval-5 で確認済み）
   - supabase db push で migration 5 (20260820000005) がリモートに適用済み

2. supabase CLI でリモート状態を確認:
   supabase migration list --linked
   # 5 件並んでいることを確認

3. (もし適用前なら) supabase db push を実行:
   supabase db push
   # → 20260820000005_received_like_count.sql が新規適用される

4. 関数の存在確認 (本番で):
   curl -X POST "$REST/rpc/received_like_count" \
     -H "apikey: $ANON" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"target_post\": \"$SOME_UUID\"}"
   # → 0 (誰の投稿でも該当しない)

5. アプリ（端末 A）で投稿 → 別プロセスでいいね → 20 秒待つ
   → today.receivedLikes に「1 件のいいね」が表示されることを確認

6. 確認できなかったとき:
   - xcrun simctl spawn ... log stream --predicate 'eventMessage CONTAINS "SameQ"' | grep migration
   - migration 未適用なら alertMessage「サーバー機能の一部が未適用です。」が出ているはず
     （attempt 12 で追加した alertMessage）
```

### 条件 6・7 を自動回帰で検証する手順

```
xcodebuild test -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SameQUITests/SprintTwelveOfflineAcceptanceTests

# → TEST SUCCEEDED（3/3 成功・18.2 秒）
```

実機の機内モードを切り替えずに条件 6（オフライン表示）と
条件 7（retry での再実行・クラッシュなし）が検証できる。
