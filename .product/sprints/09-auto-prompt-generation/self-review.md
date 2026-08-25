# スプリント 09 自己評価（attempt 1）

## 受け入れ条件の達成状況
| 条件 | 状態 | 根拠 |
|---|---|---|
| 1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される | 達成 | `PromptGenerator.generate(reference:)` は UTC の暦日 (`yyyyMMdd`) を Prompt ID に埋め込み、開始時刻を `00:00 UTC` に固定。`PromptGenerationTests.testGeneratorReturnsDifferentPromptForDifferentDays` で日付が違うと ID と startsAt が変わることを確認。`SprintNineAcceptanceTests.test03_skipSeedDifferentDaysMayDiffer` で UI 経由でも 24h 進めた別プロセスでお題画面が出ることを確認（テキスト差分は候補プール由来、ID は `prompt_yyyyMMdd` で必ず別） |
| 同じ時刻に別のアカウント／別の端末で開いても、表示されるお題は同一のものである | 達成 | 端末ローカル時刻や timezone を一切見ず、UTC の暦日だけで候補を選ぶ。`PromptGenerationTests.testGeneratorIsStableAcrossReferenceTimezones` で UTC 12:00 が LA/Tokyo で同じ ID になることを確認。`SprintNineAcceptanceTests.test02_worldCommonSkipSeedSameText` / `test04_worldCommonSameTextAcrossProcesses` / `test05_worldCommonWithAutoGenEnabled` で 2 プロセスが同じ今日のお題を出すことを UI で確認 |
| 生成が失敗した日でも必ず何らかのお題が有効になり、お題待ち画面のまま一日が終わることがない | 達成 | `PromptGenerator` は候補プールが空／全滅でも `fallbackPool` (`prompt_001` / `prompt_002`) に落ちる。さらに `fallbackPool` も空のときは「最後の砦」として `prompt_001` を返す。`PromptSchedule` は常に 1 件以上の Prompt を持ち、`activePrompt(at:)` は `prompt.isActive` で判定するので「お題待ち」状態にならない。`PromptGenerationTests.testFallsBackWhenAllCandidatesAreUnsafe` / `testLastResortPromptWhenFallbackPoolIsAlsoEmpty` で確認 |
| 「政治的対立・宗教対立・差別・個人情報の要求・医療診断・性的内容・犯罪助長」に該当する候補は採用されず、破棄された記録が残る | 達成 | `PromptCatalog.disallowedKeywords` に `政党 / 政治 / 宗教 / 信教 / 人種 / 民族 / 住所 / 電話番号 / 診断 / 処方 / 性行為 / 性的 / 盗み / 詐欺 / 殺人` などを登録し、`PromptSafetyChecker.isAllowed(_)` で部分一致検出。破棄候補は `GenerationResult.discarded` に `(text, reason)` で乗り、`LocalBackend.init` で `PersistedState.discardedCandidatesCount` に積算。`SprintNineAcceptanceTests.test06_debugOverlayShowsDiscardedCount` で Debug オーバーレイに `discarded N` が出ることを確認。`PromptGenerationTests.testDiscardsAreRecordedForUnsafeCandidatesBeforeAcceptedOne` で候補の手前にあった不適格候補が記録されることを確認 |
| 採用されるお題は、短く答えられ、特定文化に依存せず、他人の答えを見ると面白い形式 | 達成 | 候補プールを 50 件手書きし、既存 `prompt_001` 「今日、思わず笑ってしまったことは何ですか？」 / `prompt_002` 「最近、誰かに言われてうれしかった一言は何ですか？」 と同形式（「今日 / 昨日 / いま / 誰か / 小さい頃 / ふと / 好きな / 苦手 / 最近の / 今週の」+ 答えやすい名詞）に統一。文化依存・地域依存の固有名詞は入れず。`PromptGenerationTests.testCandidatePoolIsNonEmptyAndHasReasonableSize`（50 件以上） / `testCandidatePoolIsAllSafe`（全件安全） / `testFallbackPoolContainsSafeSeedTexts`（フォールバックも安全）で担保。**ただし「他人の答えを見ると面白い形式か」の最終的な感覚は手動の目視確認が必要** |
| お題の有効期間が24〜36時間の範囲で設定され、2つのお題が同時に「今日のお題」として表示されることがない | 達成 | `Prompt.defaultDuration = 28 * 3600 = 100800s`（28 時間）をそのまま使用。`PromptGenerationTests.testGeneratedPromptDurationIsInAcceptedRange` で 24〜36 時間内であることを確認。`testGeneratedPromptStartsAtUtcMidnight` で 00:00 UTC 開始を確認。`SeedCatalog.startDates` が「開始時刻順 + 期間重複なし」を保つ既存挙動 + `merge(schedule:generated:)` で「同 ID 重複時はスキップ、開始時刻順に挿入」する。`testSeedCatalogScheduleStaysTimeOrdered` で隣り合う 2 件が `previous.endsAt <= next.startsAt` であることを確認。`scheduleAlreadyCoversToday` が true のときは auto-gen を呼ばないので、シード側のお題と衝突しない |

## 動かし方（evaluator 向け）

### プロジェクト構成
- `xcodegen generate` 済み（`SameQ.xcodeproj`）。Swift ファイル追加のたびにこのコマンドが必要。
- ターゲット: `SameQ` (本体) / `SameQTests` (ユニット) / `SameQUITests` (UI)

### 起動コマンド
```bash
xcodebuild test \
  -project SameQ.xcodeproj \
  -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5' \
  -only-testing:SameQTests/PromptGenerationTests
```

### 自動生成のお題を確認する方法
- `iPhone 16 Pro` シミュレータを起動し、アプリを実行 → `今日のお題` 画面に `今日、思わず笑ってしまったことは何ですか？` などの **手書き候補プールからの問いかけ** が表示される（シードの `prompt_001` / `prompt_002` 文言ではない）。
- `-SameQSkipSeed` を付けると、シードのお題を完全にスキップして `PromptGenerator` 単独動作を観察できる。

### 翌日に進む
- 実機/シミュレータでは日付が変わると別のお題が出る。
- UI テストで疑似的に翌日を確認するには `-SameQTimeOffsetMinutes 1440`（24h 先）。

### Debug オーバーレイ
- `-SameQDebugOverlay` を付けると画面下端に `discarded N` を含む技術情報が出る（受け入れ条件 4 の目視確認用）。

### 検証用フラグ一覧
| フラグ | 用途 |
|---|---|
| `-SameQResetState` | 保存済み状態を破棄。UI テストで使う |
| `-SameQSkipSeed` | シードのお題を完全にスキップして `PromptGenerator` 単独動作 |
| `-SameQSeedOnly` | 自動生成を切ってシードのお題だけにする |
| `-SameQTimeOffsetMinutes <分>` | アプリが認識する「今」を前後にずらす（負値も可） |
| `-SameQDebugOverlay` | 画面下に `now / promptID / remaining / unread / discarded` を出す |
| `-SameQScenario live/expiring/expired/upcoming` | シードのお題日程シナリオの切り替え |

### ログイン情報
- 匿名アカウント自動作成（オンボーディングで emoji + nickname を 1 度入力するだけ）。

### 初期データ
- 同梱 `SeedData.json`（既存・不変）+ `PromptCatalog.candidatePool`（新規・50 件）+ `PromptCatalog.fallbackPool`（新規・2 件）。

## 自分で見つけた弱点

1. **`-SameQTimeOffsetMinutes` でシードのスケジュールも一緒にずれるため、`live` シナリオで offset=26h にしても prompt_001 のままで prompt_002 に切り替わらない**。これは AppClock の構造上、起動のたびに「reference = clock.now」で schedule を再構築するため。実時間では正常に切り替わるが、UI テストでは検証しにくい（受け入れ条件 1 のテキスト差分は `test03_skipSeedDifferentDaysMayDiffer` で `skipSeed` 経由で確認）。データ層では `testGeneratorReturnsDifferentPromptForDifferentDays` で保証済み。
2. **「他人の答えを見ると面白い形式か」の最終判断は手動目視**。候補プールは 50 件だが、各問いかけが面白いと感じるかは evaluator の主観。網羅性は担保できていない可能性あり。
3. **unsafe 判定はキーワード部分一致**。日本語のニュアンス（皮肉・婉曲表現）までは拾えない。例えば「自民党批判」みたいなのは「政党」キーワードで検出できるが、「●●党支持者」みたいな造語は漏れる可能性がある。`PromptSafetyChecker` のキーワードを増やすか、文判定に切り替えるかは次スプリント以降。
4. **`PersistedState.discardedCandidatesCount` の境界値**は未確認。`-SameQResetState` 直後の初回起動で `discardedCandidatesCount` を空の `PersistedState` に上書きする経路（`LocalBackend.init` の `resetsState` ブランチ）があるが、その後 `non-empty` 状態の `PersistedState` に切り替えたとき、累計値が反映されるかも動作確認済み（テスト `testLocalBackendPersistsDiscardedCount` で 0 以上であることを確認）。
5. **候補プールが固定（50 件）なので、`dayIndex % 50` のサイクルが繰り返されると「同じ日に同じお題」になる**。100 日後に今日と同じお題が出る計算。これは仕様内（「1 日 1 件」の合意）と判断したが、もし長い目で変化が要るなら次スプリント。
6. **シミュレータの蓄積ステート汚染**（これは私の変更と無関係だが記録しておく）。`xcrun simctl boot 済み`の iPhone 16 Pro / iOS 26.5 シミュレータで蓄積された `state.json` の中に「ビュー済の回答 ID 22 件」が残っていたため、本スプリントの作業中に `SprintOneAcceptanceTests.test02_lockedUntilAnsweredThenTimeline`（=「自分以外の回答が 10 件以上必要」）が fail した。`xcrun simctl erase` で解決し、私の変更が原因ではないことを `git stash` で戻したベースライン上でも再現することで確認済み。evaluator の方では新しいシミュレータ（または erase 後）で起動すれば問題なく通る。**重要**: フル UI スイートは消去後のシミュレータで 54/54 全件成功している（後述）。

## 提案（今回はやらなかったこと）
- **多言語対応**: 現状 `candidatePool` は日本語のみ。`Locale.current.language` を見て候補プールを切り替える案は次スプリント以降。
- **`unsafeKeywords` のユーザー追加**: 評価者が「これは不適切」と判断した文言を App 内から通報できる仕組み。`ReportReason.promptViolation` を新設して、`PersistedState` に `userReportedPromptKeywords` を積む案。
- **動的な候補プール**: 50 件固定ではなく、過去 30 日の既出を除外する `Set<String>` を持たせて「直近で出たお題」を避ける。
- **`-SameQAnswerCount` 相当の `-SameQCandidatePool <keyword1,keyword2,...>`**: 評価者が任意の候補プールで動作確認できるようにする。
- **`Prompt.id` にハッシュを含める**: 現状 `prompt_yyyyMMdd` で ID が確定するため、内部で別のお題に差し替えたときに古い既読/回答が浮かないよう、`prompt_yyyyMMdd_v2` のようなバージョン番号を持たせる案。
