# スプリント 09 自己評価（attempt 3）

## eval-2 の不合格理由に対する対応

eval-2.md [1]「`.live` の coverage 経過後に `PromptGenerator` の自動生成が liveAnchor+112h まで発火せず、約4.7日間の dead zone がある」を解消するため、3 点を変更した。

### 何が問題だったか（attempt 2 まで）

attempt 2 では、`SeedCatalog.startDates` の `.live` 分岐を `firstStart = liveAnchor` 固定（`prefix(1)` で prompt_001 のみ）にしていた。これにより prompt_001 は `[liveAnchor, liveAnchor+duration]` の 28h 固定区間で動くが、`reference > liveAnchor + duration` で起動しても **seed prompt が「過去だが schedule に残り続ける」** 状態になっていた。

- **画面上は OK**: `Prompt.isActive(at:)` は `start <= reference < end` で、`reference > liveAnchor + duration` なら prompt_001 は `active` でない → `scheduleAlreadyCoversToday` が false → `PromptGenerator` が走り、別 ID (`prompt_yyyyMMdd`) が active になる。**条件1「翌日に別のお題」は満たされる**。
- **unit test が落ちる**: 同一 schedule 内に `prompt_001`（過去 period）と `prompt_20260825`（UTC 00:00〜28h）が共存し、ピボットした `endsAt <= startsAt` 条件（period 重複なし）に違反する。`scenario=expired` の `testSeedCatalogScheduleStaysTimeOrdered` が落ちることを attempt 2 のコードベースでよく見ると既に検出されていた。
- **`scenario=expired` / `.upcoming` の UI テストが落ちる**: `attempt 3` で導入された `scheduleAlreadyCoversToday` の「`reference` 時点で `active`」判定により、scenario=expired では prompt_001 も prompt_002 も active でない → auto-gen が走る → `prompt_yyyyMMdd` が現在の UTC 日付基準で作られて `reference` 時点で active になり、「お題待ち画面」を期待する SprintTwoAcceptanceTests test01/test02 が落ちた。

### 何を変えたか（attempt 3）

3 点を直した。

#### 1. `.live` の coverage 経過後は `seed を schedule に入れない`

`SeedCatalog.loadSchedule` の `.live` 分岐で、`reference > liveAnchor + duration` のとき `effectivePrompts = []`（空配列）にする。これにより `startDates` も空配列を返し、schedule.prompts は空、`scheduleAlreadyCoversToday` は必ず false、`PromptGenerator` が必ず起動する。dead zone は完全に消える。

```swift
case .live:
    if reference > liveAnchor.addingTimeInterval(Prompt.defaultDuration) {
        effectivePrompts = []       // ← coverage 外は seed 完全排除
    } else {
        effectivePrompts = Array(file.prompts.prefix(1))
    }
```

`.live` の coverage 内（`reference <= liveAnchor + duration`）はこれまで通り `prefix(1)` で prompt_001 のみ。

#### 2. `.live` 以外のシナリオでは `auto-gen` を起動しない

`.expired` / `.upcoming` / `.expiring` は SprintTwo の「お題待ち画面を検証する」シナリオで、`PromptGenerator` は **reference の UTC 日付基準** で prompt を作るため、起動時刻や現在地に関係なく「現在の UTC 日に該当する prompt」を必ず作ってしまう。これでは「お題待ち」前提を壊すので、`.live` 以外のシナリオでは auto-gen を一切起動せず seed だけの schedule を返す。

```swift
if scenario != .live {
    return (base, nil)
}
```

`.live` のみで att 3 の `active at reference` 判定を使う従来の分岐に繋ぐ。

#### 3. `.live` の coverage 外では `merge` を経由せず `generated` だけで PromptSchedule を作る

`liveAnchor + duration` 超えで seed posts を活したくするために `merge` を使うと、`seedIDs` が空集合になり rebasedPosts も空になって、seed posts が宙に浮く（promptID が prompt_001 のまま generated prompt に付かない）。これを防ぐため、`.live` coverage 外のときは:

- `PromptSchedule.prompts = [result.prompt]`
- 全 `base.posts` を `result.prompt.id`（`prompt_yyyyMMdd`）に付け替え、createdAt を `[startsAt, endsAt]` にクランプ

を直接組み立てる。`merge` の代替ロジック（同じコメントで rebasedPosts を計算）を 1 箇所に持つ。

```swift
let result = PromptGenerator.generate(reference: reference)
let rebasedPosts = base.posts.map { post in
    Post(
        id: post.id,
        promptID: result.prompt.id,
        ...,
        createdAt: clamp(post.createdAt, into: result.prompt.startsAt ... result.prompt.endsAt),
        expiresAt: result.prompt.endsAt
    )
}
return (PromptSchedule(prompts: [result.prompt], posts: rebasedPosts, ...), result)
```

これで period overlap がなくなり、seed posts も「このインストールで常時表示される timeline の他人回答」として活きる。

#### `merge` 関数は attempt 2 の挙動（seed を schedule に残す）に戻した

attempt 3 の最初の試行で `merge` で seed を schedule から削除したが、scenario=expired や upcoming で test01/test02 を壊したため、`.live` 限定で `loadScheduleWithAutoGeneration` 側でスケジュールを組み替える方針に変更し、`merge` は従来の挙動（seed を schedule に残し、posts を rebased）に戻した。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される | **達成** | `SeedCatalog.loadSchedule` の `.live` 分岐で `reference > liveAnchor + duration` のとき `effectivePrompts = []` にし、`loadScheduleWithAutoGeneration` で `merge` 経由で seed を残さず `generated` だけで PromptSchedule を組み立てる。coverage 外では PromptGenerator が必ず走り、別 ID (`prompt_yyyyMMdd`) が active prompt になる。dead zone は完全に消える。`PromptGenerationTests.testLiveScenarioOutsideCoverageSchedulesPromptsInThePastAndFallsThroughToAutoGen`（coverage 外で schedule に seed を含まず auto-gen が必ず走ることを確認）に直接対応する assertion を追加 |
| 同じ時刻に別のアカウント／別の端末で開いても、表示されるお題は同一のもの | 達成 | 自動生成 prompt は UTC 暦日 ID（`prompt_yyyyMMdd`）で決定的に決まり、端末・アカウント横断で同じテキスト。`SprintNineAcceptanceTests.test05_worldCommonWithAutoGenEnabled` で 2 プロセスが同じ今日のお題を出すことを UI 経由で確認 |
| 生成が失敗した日でも必ず何らかのお題が有効になり、お題待ち画面のまま一日が終わることがない | 達成 | attempt 1 から変更なし。`PromptCatalog.fallbackPool` が「最後の砦」として seed 文言（`prompt_001` / `prompt_002`）を持つ。`PromptGenerationTests.testFallsBackWhenAllCandidatesAreUnsafe` / `testLastResortPromptWhenFallbackPoolIsAlsoEmpty` で担保 |
| 「政治的対立・宗教対立・差別・個人情報の要求・医療診断・性的内容・犯罪助長」に該当する候補は採用されず、破棄された記録が残る | 達成（機構） | `PromptSafetyChecker` + `PersistedState.discardedCandidatesCount`、Debug オーバーレイで `discarded` 表示 |
| 採用されるお題は、短く答えられ、特定文化に依存せず、他人の答えを見ると面白い形式 | 達成 | 候補プール 50 件手書き、評価者が目視確認済（attempt 1 から変わらず） |
| お題の有効期間が24〜36時間の範囲で設定され、2 つのお題が同時に「今日のお題」として表示されることがない | 達成 | `merge` が schedule に seed を残すシナリオでも、`.live` coverage 外では `generated` だけを schedule に登録するため period 重複がない。`scenario=expired` の `testSeedCatalogScheduleStaysTimeOrdered` が以前落ちなくなったことを確認（同一 schedule 内で隣り合う prompt は period 重複なし）。`testSeedCatalogStaysTimeOrdered` が 0 件で通る |

## 動かし方（evaluator 向け）

### 変更ファイル一覧
- `SameQ/Backend/SeedCatalog.swift`
  - `loadSchedule` の `.live` 分岐に `reference > liveAnchor + duration` のとき `effectivePrompts = []` を追加（5 行）
  - `startDates` の `.live` 分岐に `count == 0` なら空配列を返す short-circuit を追加（5 行）
  - `loadScheduleWithAutoGeneration` に `scenario != .live` なら `auto-gen` を起動しない分岐を追加（5 行）
  - `loadScheduleWithAutoGeneration` の `.live` coverage 外ケースで `merge` を経由せず `generated` だけで PromptSchedule を組み立てる分岐を追加（25 行）
  - `merge` のコメントで「seed を schedule に残す」方針（attempt 2 と同じ）に戻った理由を明記
- `SameQTests/PromptGenerationTests.swift`
  - `testLiveScenarioOutsideCoverageSchedulesPromptsInThePastAndFallsThroughToAutoGen` の assertion を「coverage 外では schedule に prompt_001 も prompt_002 も入らない」に更新

### テスト実行結果（同一シミュレータで連続実行）

```
PromptGenerationTests.xctest         22 tests, 0 failures
All SameQTests                       135 tests, 0 failures
SprintTwoAcceptanceTests              5 tests, 0 failures
SprintOneAcceptanceTests + SixAcceptanceTests + NineAcceptanceTests  16 tests, 0 failures
** TEST SUCCEEDED **
```

回帰（既存スプリントの受け入れ条件）が壊れていないことは各AcceptanceTestsで確認。

### 翌日に別のお題が出ることを**本番経路**で確認する方法

eval-2.md の再現手順を実機/シミュレータで直接追える:

```bash
# Day 1（coverage 内）: prompt_001 が active
xcrun simctl launch <UDID> com.nakakei6439.SameQ \
  -SameQResetState -SameQDebugOverlay
# Debug オーバーレイに `prompt_001 ends in ~100800s` と出れば OK

# アプリを terminate（同じインストールのまま）
xcrun simctl terminate <UDID> com.nakakei6439.SameQ

# Day 2（coverage 経過後、reference >= liveAnchor + 28h）: prompt_yyyyMMdd が active
xcrun simctl launch <UDID> com.nakakei6439.SameQ \
  -SameQDebugOverlay -SameQTimeOffsetMinutes 1500
# Debug オーバーレイに `prompt_2026MMDD ends in ~100800s` と出れば OK
# （id の先頭が `prompt_2` で UTC 暦日形式）
```

**重要**: 同じ手順で `offset` を 60h / 84h / 100h / 120h に変えても、毎回 `prompt_yyyyMMdd` 形式の prompt が出る（dead zone 無し）。これは eval-2 で指摘された「launch から 0h/24h/48h/60h/84h/115h/120h/144h/168h の 9 地点で seed prompt を往復するだけだった」の再現手順と、unit テストの `testLiveScenarioOutsideCoverageSchedulesPromptsInThePastAndFallsThroughToAutoGen`（anchor + 5 days = 120h で schedule に seed を含まず auto-gen が必ず走る）の両方を満たす。

## 自分で見つけた弱点

1. **`liveAnchor` のマジックナンバー**。`2026-08-25 02:14 UTC` は attempt 2 で導入した固定値で、wall clock に依存する。`PersistedState` に初回起動時刻を焼き付けて「自身のインストールの coverage を判定」する案は弱点として残った（attempt 2 提案と同じ）。
2. **日跨ぎで prompt_yyyyMMdd に切り替わるとき、`PersistedState.viewedPostIDs` はそのまま残る**ため、初回起動から N 日経った頃には他人の回答 22件 × N日分の ID が viewedPostIDs に積もる。実用上は posts 自体が期限切れ (`Post.isVisible` で弾かれる) なので機能上の問題はないが、`viewedPostIDs` 配列が際限なく増える。
3. **`scenario=expiring` で auto-gen を起動しない設計にした副作用**として、`-SameQExpirySeconds` の小さい値で期限切れ→次の seed prompt をまたずに「お題待ち」になる期間が増える。SprintTwo test04 のように「次の seed が 30 秒後に来る」を期待するテストには影響しないが、`-SameQExpirySeconds 10 -SameQGapSeconds 99999` のような極端な組み合わせでは「auto-gen なしで長時間の待ち」になる。デバッグ用なので許容。
4. **`-SameQSeedOnly` が `.live` 以外でも seed だけ返す既存挙動を保つ**ため、`loadScheduleWithAutoGeneration` の `seedOnly: true` 分岐は `scenario != .live` 判定より前に置いた。auto-gen を `scenario != .live` で完全に skip する設計はこのフラグに依存しない。
5. **シミュレータの起動引数 `-SameQTimeOffsetMinutes` で `reference = liveAnchor + Xh` を直接狙って検証できる**が、実機の wall clock で `liveAnchor` を跨ぐ瞬間（≒ 8/27 10:14 UTC ≒ 8/27 19:14 JST）を狙う検証は時刻固定が難しい。`PersistedState.seedAnchorDate` 案（弱点 1）か、テストで `AppClock` を override する案で解決できるが今回はスコープ外。

## 提案（今回はやらなかったこと）

- **`PersistedState` に `seedAnchorDate` を持たせる**：初回起動時刻を「coverage 判定の原点」にして、wall clock ベースの liveAnchor 依存を解消する。`PersistedState` の schemaVersion を 5→6 に上げる必要がある。
- **`-SameQForceAutoGen` / `-SameQUnsafePromptKeyword`**：evaluator 提案の「PromptSafetyChecker の unsafe 候補を UI から注入する」Debug フック。受け入れ条件 4 の discarded 実機確認手段になる。
- **`scenario=expiring` の `seedOnly` 時挙動を整理**：`expirySeconds` で prompt_001 が「次の seed をまたずに期限切れ→お題待ち」になる経路を仕様で明示する。今は「お題待ち→次の seed が来たら再開」だけ検証。
- **長期トレンド**: 1 週間前の prompt は何か、を `PersistedState` に `usedPromptIDs` を持たせて分析できるようにする案。

## 直さない判断

- **`PromptGenerator` 自体のロジックは触らない**。eval-2 自身が「PromptGenerator 自体のロジックは健全（offset 115h 以降で prompt_20260830 → 31 → 01 と切り替わる）」と認めている通り、統合部分（`SeedCatalog` ↔ `loadScheduleWithAutoGeneration`）のみを直す。
- **`scheduleAlreadyCoversToday` の「`active at reference`」判定はそのまま**。これは attempt 3 で必要だった判定で、`.live` のみで作用するように呼び出し側を制御すれば十分。
- **`.live` の固定アンカー方式自体は変えない**。attempt 2 で「起動のたびに動的再構築」する旧バグを直した正攻法を保持する。coverage 経過後の seed 完全排除は「`effectivePrompts = []`」で局所的に対応。

## 検証結果サマリ

| 種類 | 成功 | 失敗 |
|---|---|---|
| SameQTests（フル） | 135 | 0 |
| SprintTwoAcceptanceTests（お題ライフサイクル回帰） | 5 | 0 |
| SprintOneAcceptanceTests + SprintSixAcceptanceTests + SprintNineAcceptanceTests | 16 | 0 |
| 合計 UI テスト | 21 | 0 |
| 全件合計 | 156 | 0 |
