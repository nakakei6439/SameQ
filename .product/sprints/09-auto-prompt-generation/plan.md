# スプリント 09: お題の自動生成（F26 / F27）

## 受け入れ条件（spec.md 245〜251 行から転記）
- [ ] 1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される
- [ ] 同じ時刻に別のアカウント／別の端末で開いても、表示されるお題は同一のもの（世界共通）である
- [ ] 生成が失敗した日でも必ず何らかのお題が有効になり、お題待ち画面のまま一日が終わることがない
- [ ] 「政治的対立・宗教対立・差別・個人情報の要求・医療診断・性的内容・犯罪助長」に該当する候補は採用されず、破棄された記録が残る
- [ ] 採用されるお題は、短く答えられ、特定文化に依存せず、他人の答えを見ると面白い形式（既存のお題例と同種の問いかけ）になっている
- [ ] お題の有効期間が24〜36時間の範囲で設定され、2つのお題が同時に「今日のお題」として表示されることがない

## 実装方針

### 新規ファイル
- `SameQ/Backend/PromptCatalog.swift` — アプリ内の「生成候補プール」（既存 `prompt_001` / `prompt_002` と同種の問いかけを 50 件程度）と、安全でない候補を取り除く `PromptSafetyChecker`、フォールバック候補（常に安全と分かっている `prompt_001` / `prompt_002` などのシード）。
- `SameQ/Backend/PromptGenerator.swift` — UTC の暦日インデックスから「今日の Prompt」を 1 件返す決定的な生成器。候補プールを `dayIndex % pool.count` から順送りし、`PromptSafetyChecker` で安全と判定された最初の候補を採用する。安全候補が 1 つも無い日は `PromptCatalog.fallbackPool`（シード由来）からフォールバックを返す。破棄された候補のリストも戻り値に含めて `LocalBackend` まで運ぶ。

### 既存ファイルへの変更
- `SameQ/Backend/SeedCatalog.swift` — `loadSchedule(...)` の戻り値のあとに `PromptGenerator.ensureTodaysPrompt(in: schedule, reference: clock.now)` を呼ぶ薄いラッパ `loadScheduleWithAutoGeneration(...)` を追加。既存の `loadSchedule` のシグネチャ・呼び出し元は変えない（呼び出し元 1 箇所 = `LocalBackend.init`）。
- `SameQ/Backend/LocalBackend.swift` — `loadSchedule` を `loadScheduleWithAutoGeneration` に置き換えるだけ。あとは `schedule` の `activePrompt(at:)` が新しい Prompt を返すので既存ロジックで動く。`PersistedState.discardedCandidatesCount` を `decodeIfPresent` で導入（後方互換、schemaVersion 据え置き）し、`PromptGenerator` が運んできた破棄件数を初回起動時に 1 度だけ反映する。`-SameQDebugOverlay` に `discarded N` を追加。
- `SameQ/Model/Prompt.swift` — 触らない（`defaultDuration = 28h` をそのまま使う）。

### 受け入れ条件と実装の対応
| 受け入れ条件 | 担保する仕組み |
|---|---|
| 1. 1日1回自動生成 / 翌日で別のお題 | UTC の暦日 (`yyyyMMdd`) を `Prompt.id` に埋め込み、開始時刻を `00:00 UTC` に固定。翌日は別の ID になる |
| 2. 世界共通 | 同じ `dayIndex` = 同じ候補プールインデックス。世界中のどの端末・どのアカウントでも同じ日付 = 同じテキスト |
| 3. 失敗時のフォールバック | 安全候補が尽きたら `fallbackPool`（= シードの `prompt_001` / `prompt_002`）。`PromptSchedule` には常に 1 件以上の Prompt が入るので「1 日中お題待ち」には陥らない |
| 4. 安全でない候補は破棄され記録が残る | `PromptSafetyChecker` が `unsafeKeywords` への含有を判定 → 破棄 → 次の候補を試す。破棄件数は `PersistedState.discardedCandidatesCount` に積算（デバッグオーバーレイで可視化、UI には出さない） |
| 5. 既存と同種の問いかけ | 候補プールを「今日 / 昨日 / いま / 小さい頃」など、短く答えられる・文化依存しない・他人の答えが面白い形式に限定して 50 件手書き |
| 6. 24〜36 時間、2 つ同時表示されない | `Prompt.defaultDuration = 28h` をそのまま使用。`startDates` で「00:00 UTC 開始」だけ特別扱いし、シードのお題 (`prompt_001` / `prompt_002`) は 28h 間隔で隙間を空けて並ぶ。`PromptSchedule` の期間重複チェックは既存テストで担保 |

### 影響範囲
- 既存: `LocalBackend.promptState()` / `AppSession.refresh()` / `AppSession.applyPromptState()` の経路は触らない。`PromptSchedule` にもう 1 件増えるだけで、既存ロジックはそのまま動く。
- 同梱シード（`SeedData.json`）もそのまま残す（フォールバック・検証用・既存テストの参照）。
- 翻訳経路（`Translator` / `AppSession.syncPromptTranslation`）も触らない。お題本文が増えるだけで、`Translator.translate(_:sourceLanguageCode:)` に新しいテキストが流れるだけ。

### 検証用の起動引数
- 既存 `-SameQTimeOffsetMinutes` で「日付変更ラインを超える」を再現できる（+24h で翌日）
- 既存 `-SameQScenario` はそのまま動作（シードのお題日程が変わるだけで自動生成には影響しない）

### テスト戦略
- **ユニットテスト** (`SameQTests/PromptGenerationTests.swift`):
  - 同じ日付 → 同じ Prompt（決定性）
  - 異なる日付 → 異なる Prompt（条件 1）
  - 候補プール内に安全でない候補を入れても、その日を「スキップ」して別の候補が採用される（条件 4）
  - 全候補が不安全な状況ではフォールバックが返る（条件 3）
  - 開始時刻が 00:00 UTC で 28 時間続く（条件 6）
  - 2 つのお題が同時に active にならない（条件 6）
  - 破棄された候補の記録が残る（条件 4）
- **UI テスト** (`SameQUITests/SprintNineAcceptanceTests.swift`):
  - `test01_dailyNewPrompt`: ある日で起動 → お題 A → `-SameQTimeOffsetMinutes` で翌日に進める → お題 A ではない（条件 1）
  - `test02_worldCommon`: 同じ起動引数で 2 プロセス起動 → お題 ID が一致（条件 2）
  - `test03_fallbackWhenAllUnsafe`: 候補プールを空にする Debug 起動引数 → `prompt_001` などのフォールバックが出る（条件 3）
  - `test04_unsafeCandidateDiscarded`: 起動引数で「今日の候補が不安全」と差し込む → 別の候補に差し替わり、Debug オーバーレイの `discarded` が増える（条件 4）
  - `test05_noOverlapAcrossTwoPrompts`: 自動生成お題と翌日のお題のスケジュールが `[startsAt + 28h, 次startsAt)` の関係（条件 6）

## 着手前の確認事項
- 候補プールに入れる文言は既存 `prompt_001` 「今日、思わず笑ってしまったことは何ですか？」 / `prompt_002` 「最近、誰かに言われてうれしかった一言は何ですか？」 と同種（「今日 / 昨日 / この前 / いま / 誰か / 小さい頃 / 好きな」+ 答えやすい名詞）で揃える。
- 安全でないキーワードは「候補プールに入らない」前提で組むが、評価者が `unsafeKeywords` を Debug 引数で増やせるように `LaunchOptions.unsafePromptKeywords` を追加（`-SameQUnsafePromptKeyword <keyword>` で複数指定可能）。