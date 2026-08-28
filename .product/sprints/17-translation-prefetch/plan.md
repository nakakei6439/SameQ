# スプリント 17: 翻訳準備の先読み（F41）

## 受け入れ条件（spec.md から転記）

- [ ] 先読みの対象になるのは、直近よく出会う言語のうち最大3件までで、それを超える数の言語がまとめて取得されることがない
- [ ] 先読みが済んだ言語の回答は、タイムラインで初めて出会っても「準備中」の待ちが発生せず、そのまま読める
- [ ] 先読みされていない言語の回答はこれまでどおり（初回のみ準備中表示 → 完了後に読める）で、スプリント06の受け入れ条件が変わらない
- [ ] 先読みはアプリを開いていない間に行われ、アプリを使っている最中に画面が止まる・スワイプが引っかかる・進捗表示が割り込むことがない
- [ ] 通信できない状態では先読みが行われず、そのことによるエラー表示も出ない。通信が回復した後は通常どおり利用できる
- [ ] アプリ内に、翻訳の先読みに関する設定項目・ダウンロード管理・進捗表示が1つも存在しない（翻訳の存在を意識させないという F19 の方針を守る）

## 実装方針

### 設計の要点

「直近よく出会う言語」は **タイムラインで実際に表示した回答の言語** の累計回数（端末内のみ）。
言語別の出会いは `AppSession.drawNextPost` で確定表示時にバックエンド経由で永続化。
pre-fetch は **scenePhase == .background** のタイミングでのみ起動し、
最大3言語まで並列ではなく **直列に短時間予算（合計30秒）** で `Translator.prepareIfNeeded`
を呼ぶ（既存のクールダウン / `.installed` / `.unsupported` 判定を再利用）。
pre-fetch 用の UI・進捗・設定は追加しない（F19）。
通信不能は既存の `Backend.isOnline()` を見て**呼ばない**ことでスキップする（タスク自体を起動しない）。

### 変更ファイル

1. **`SameQ/Backend/LocalStore.swift`** — `PersistedState` に
   `languageEncounters: [String: Int]` を追加（schemaVersion 7 → 8）。
   `decodeIfPresent` でフォールバック（既存ユーザーの `state.json` は空辞書）。
2. **`SameQ/Backend/Backend.swift`** — `Backend` プロトコルに
   `recordLanguageEncounter(languageCode:) async throws`、
   `topEncounteredLanguages(limit:) async throws -> [String]`、
   `isOnline() async -> Bool` を追加（pre-fetch の offline 判定用）。
3. **`SameQ/Backend/LocalBackend.swift`** — 上記3メソッドを実装。
   `deleteAccount()` で `languageEncounters` を空に戻す。
4. **`SameQ/Backend/SupabaseBackend.swift`** — 上記3メソッドを実装。
   `languageEncounters` は端末内のみ（サーバー同期しない、F19 の方針に従い翻訳を意識させない）。
   `isOnline()` は `forceOffline || lastPathStatus != .satisfied` を反転。
   `deleteAccount()` で空に戻す。
5. **`SameQ/Session/AppSession.swift`** —
   - `drawNextPost` の表示確定時に `recordLanguageEncounter` を呼ぶ（1回答 = 1カウント）。
   - 新規 `peekTranslationsInBackground()`：online 判定 → top-3 取得 →
     短時間予算内で `translator.prepareIfNeeded` を直列に呼ぶ。エラーを投げない。
6. **`SameQ/App/RootView.swift`** — `scenePhase == .background` で
   `peekTranslationsInBackground()` を起動（Task.detached、デバッグログは出さない）。
7. **新規ユニットテスト** — `SameQTests/LanguageEncounterTests.swift`、
   `SameQTests/BackgroundPeekTests.swift`。
8. **新規 UI テスト** — `SameQUITests/SprintSeventeenAcceptanceTests.swift`。
   - シナリオ：複数回答を見たあと `scenePhase` を background にして再起動 → 次に同言語の回答を引いたときの待ち時間を検証。

### pre-fetch のトリガ条件

- `scenePhase == .background`（アプリを裏に回した瞬間）
- `user != nil`（オンボーディング済み）
- `isOnline() == true`
- 上位3言語が1件以上ある

### pre-fetch の予算

- 合計予算 30 秒（既存 `prepareTimelineLanguagesIfNeeded` の90秒より短く：ユーザーが
  戻ってきたときに裏で残っていても影響しないよう軽量に）
- 既存 `Translator.modelPrepareJobTimeoutSeconds`（既定60秒）の予算内に収まらない
  言語は途中で打ち切り、次回 background 時にクールダウン経過後リトライ（既存クールダウン5分）

## 影響範囲

- `PersistedState` の schemaVersion を 7 → 8 にバンプ。`decodeIfPresent` で
  既存 state.json は自動的に新スキーマへマイグレートされる。
- `AppSession.drawNextPost` に1行追加（カウンタ呼び出し）。翻訳結果には影響しない。
- RootView の scenePhase ハンドラに background 時の新 Task を1つ追加。
  既存 foreground 時の refresh タスクには触らない。
- `Backend` プロトコル拡張：既存実装（LocalBackend / SupabaseBackend）に追加。
  既存呼び出しには影響なし。
