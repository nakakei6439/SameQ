# スプリント12 attempt 11 計画

## 状況
attempt 10 で eval-7.md [1] 一次バグ（tokenBox.value 未反映）と二次バグ
（myPost / submitPost の `posts.author_emoji` 不存在）は修正済み。
attempt 11 では eval-7.md の残課題に対応:

- [1] 条件 3「いいね +1」が実 e2e で不合格:
  - 推測 a: `receivedLikeCount(forPostID:)` が `Backend` プロトコル要求メソッドで
    なく、`extension Backend` の default 実装 (`return 0`) に静的ディスパッチ
    されている → `actor SupabaseBackend` の実装が呼ばれない
  - 推測 b: `likes` の RLS は `likes_select_own` (`user_id = auth.uid()`) だけなので、
    仮に実装が呼ばれても自分の投稿の受信いいね (他人の `likes` 行) が 1 件も読めない
- [3] 条件 6・7 (オフライン表示 / 通信失敗時の再試行) の検証手段が無い

## 受け入れ条件（spec.md 305〜313行、attempt 11 で扱う範囲）
- [x] Backend プロトコル: `receivedLikeCount(forPostID:)` を required に昇格
- [x] migration 4: `received_like_count(target_post uuid)` 関数 + `liked_authors_view`
- [x] SupabaseClient: `rpc(function:arguments:as:)` を新設
- [x] SupabaseBackend.receivedLikeCount: RPC で呼ぶよう変更
- [x] LocalBackend.receivedLikeCount: 明示的に 0 を返す実装を追加
- [x] LaunchOptions.forceOffline + 起動引数 `-SameQForceOffline` + SupabaseBackend.checkConnectivity に組み込み

## attempt 11 でやること
1. コード変更: 上記 6 項目（前述のとおり）
2. Debug / Release ビルドで `BUILD SUCCEEDED` を確認
3. ユニットテスト 166/166 を実行
4. UI テストを実行:
   - SprintTwelveAcceptanceTests (3/3) — 新規追加分・必須
   - 直近スプリント 3 クラス: SprintEleven / SprintTen / SprintNine (18/18)
5. self-review.md を書き、state.json を awaiting_eval に更新

## 影響範囲
- Backend プロトコルの変更は `extension Backend { default }` の削除のみ。
  `LocalBackend` と `SupabaseBackend` の両方に実装があるため両者で満たされる。
- migration 4 の追加分は `db push` で反映する必要あり（ユーザー側継続課題）。
  generator 側はコード変更のみ実施。
- `-SameQForceOffline` は Debug 限定。Release では常に false。