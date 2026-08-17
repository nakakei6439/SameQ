# スプリント 03: タイムラインの取得ルールと既読管理（F11 / F12）

## 受け入れ条件（spec.md 143〜149行から転記）
- [ ] 表示されるのは今日のお題への回答だけで、別のお題への回答は1件も出ない
- [ ] 20件の回答があるとき、20回スワイプする間に同じ回答が2回出ない（未読が優先される）
- [ ] 未読を全て読み切った後もスワイプ操作が壊れず、「今は新しい回答がありません」等の明示された状態表示になる
- [ ] 同じ条件でタイムラインを2回開くと、1件目に出る回答が毎回同一とは限らない
- [ ] 回答が自分の1件しか無い場合、空状態の説明文が表示され、自分の投稿が他人の回答として出ることはない
- [ ] スワイプは次へ進むのみで、前の回答へ戻る操作は提供されない

## 実装方針
1. `PersistedState` に `viewedPostIDs` を追加（schemaVersion 2・旧ファイルは欠損キーを空で読む）。
2. `Backend` に `nextTimelinePost(promptID:) -> TimelineDraw`（`.post` / `.empty` / `.exhausted`）と
   `viewedPostIDs()` を追加。`LocalBackend` は「同一お題／自分以外／期限内」の候補から
   **未読だけを対象に `randomElement()` で1件選び、返す時点で既読に記録して保存**する。
3. `AppSession` は配列 `timelinePosts` を捨て、`timelineContent`（loading/post/empty/exhausted）1件だけを持つ。
   `openTimeline()` と `advanceTimeline()` がどちらも `nextTimelinePost` を1回呼ぶ。
4. `TimelineView` は index を捨てて `session.timelineContent` を描画。空状態と読み切り状態で文言を出し分ける
   （identifier は既存の `timeline.end` を維持）。前へ戻る操作は追加しない。
5. 検証手段: 起動引数 `-SameQAnswerCount <n>`（自分以外の回答件数を 0/1/120 などに固定）と
   `-SameQResetViewed`（既読だけ消す）を `LaunchOptions` に追加。Debug オーバーレイに未読/既読/いいね件数を出す。
   同梱シードの prompt_001 を 14 → 22 件に増やし、引数なしでも20スワイプ検証ができるようにする。

## 影響範囲
- `AppSession.timelinePosts` を参照する `TimelineView` を全面的に書き換える（他に参照は無い）。
- スプリント01の UI テスト `test03_likePersistsAcrossReopeningTimeline` は
  「既読の回答を再表示して押下状態を見る」手順のため、F12 の導入と両立しない。
  いいねの永続そのものは維持したうえで、`-SameQResetViewed` で既読を消してから
  同じ回答を探す手順に差し替える（データ層のユニットテストでも二重に担保する）。
- `pruneExpired` に既読の掃除を足す。期限切れと確認できた投稿の既読だけ落とす
  （シナリオ切り替えで未知になった ID は消さない＝再起動で既読が飛ばないように）。
