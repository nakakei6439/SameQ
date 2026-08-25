# スプリント 09 評価（attempt 3） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/6 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理エラー0（ユニット135件・UI28件・手動多地点検証すべて含む） | 0 | ✓ |
| 3 データ整合性 | state.json 直接確認。schemaVersion 5、discardedCandidatesCount 等すべて期待どおり | 100% | ✓ |
| 4 回帰 | 21/21（SprintOne 5・SprintTwo 5・SprintThree 7・SprintSix 4） | 100% | ✓ |
| 5 使用性 | 4（オンボーディング〜今日の画面まで迷わない。空状態・エラー表示の観点は既存踏襲） | 3以上 | ✓ |

**総合判定: 合格**

## 検証環境
- iPhone 17 シミュレータ（UDID `12050FBD-587B-4910-8812-696BB91BE051`, iOS 26.3）をメインに、世界共通性の確認用に Eval09（UDID `3CE33B6D-B369-4BC3-A029-87AC7B0619F4`, iOS 26.5）を追加使用
- ビルド: `xcodegen generate`（差分なしを確認）後、`xcodebuild build-for-testing` で新規ビルド（DerivedData `SameQ-gtdxwtlwcpwekjbksobzrscesrwg`）。`** TEST BUILD SUCCEEDED **`
- 検証時刻: 2026-08-25 19:20〜19:41 JST（実機起点の現在時刻はテスト内で 2026-08-25 10:25 UTC 前後）
- 検証内容:
  1. `SameQTests`（ユニット全件）を自分でビルド・実行: **135/135 成功**（self-review の申告と一致）
  2. `SameQUITests` のうち `SprintNineAcceptanceTests`（当該スプリント）+ `SprintOneAcceptanceTests` / `SprintTwoAcceptanceTests` / `SprintThreeAcceptanceTests` / `SprintSixAcceptanceTests`（回帰）を1コマンドで実行: **28/28 成功**（`SprintNine` 7/7、`SprintOne` 5/5、`SprintTwo` 5/5、`SprintThree` 7/7、`SprintSix` 4/4）
  3. **eval-1・eval-2 で繰り返し落ちた「本番相当の経路（シードあり・`-SameQSkipSeed`/`-SameQSeedOnly` なし・`scenario=live`）で日をまたいだときに dead zone が起きないか」を、evaluator 自身が実機で多地点検証**（詳細は下記「受け入れ条件ごとの結果」条件1）
  4. 同一 offset（+93h40m）で2プロセス（別シミュレータへ新規インストール）を独立起動し、世界共通性を確認
  5. アプリコンテナ内の `state.json`（`Library/Application Support/SameQ/state.json`）を直接読み、永続化の中身を確認
  6. `PromptCatalog.swift` のソースを直接読み、候補プール50件の文面と `disallowedKeywords` が仕様の7観点（政治・宗教・差別・個人情報・医療診断・性的内容・犯罪助長）を過不足なく網羅していることを確認
  7. 検証後、`git status --porcelain` でリポジトリに変更が残っていないことを確認（作業前から一貫してクリーン、一時ファイルも作成していない）

## 受け入れ条件ごとの結果

### 1. 「1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される」→ ✓ 達成

eval-1・eval-2 で2回連続不合格になった箇所。今回は evaluator 自身が**本番相当の経路**（`-SameQResetState -SameQDebugOverlay -SameQScenario live`、`-SameQSkipSeed`/`-SameQSeedOnly` 付与なし）で、同一インストールのまま `terminate` → 異なる `-SameQTimeOffsetMinutes` で再 `launch` を繰り返し、デバッグオーバーレイの `prompt.id` と `ends in` を都度スクリーンショットで確認した。

| offset | prompt id | 備考 |
|---|---|---|
| 0（起動直後、liveAnchor+8h11m相当） | `prompt_001` | ends in 71291s（coverage内） |
| +21h40m（liveAnchor+28h超過直後） | `prompt_20260826` | シード完全排除→即座に自動生成へフォールスルー（dead zone 無し） |
| +45h40m | `prompt_20260827` | 前日と異なるIDに切り替わり |
| +69h40m | `prompt_20260828` | さらに翌日、別のIDに切り替わり |
| +93h40m | `prompt_20260829` | さらに翌日、別のIDに切り替わり |

eval-2 で発見された「liveAnchor+112h まで自動生成が一度も発火しない約4.7日間の dead zone」は再現しなかった。coverage（28h）を超えた直後（+21h40m時点）に即座に `prompt_yyyyMMdd` 形式へ切り替わり、以降は UTC 暦日ごとに単調に別IDへ切り替わることを4日連続で確認した。スクリーンショットは `/tmp/eval09/step0_onboarding.png`, `step1_offset1300.png`, `step_offset_2740.png`, `step_offset_4180.png`, `step_offset_5620.png` に保存。

### 2. 「同じ時刻に別のアカウント／別の端末で開いても、表示されるお題は同一のもの（世界共通）」→ ✓ 達成

上記 +93h40m の offset で、別シミュレータ（Eval09）へ新規インストールし `-SameQResetState` で同じ offset 起動したところ、両方とも `prompt_20260829`（ends in 71608s と 71587s、起動タイミングの数秒差のみ）で一致した。`/tmp/eval09/step_worldcommon_device2.png` に保存。

### 3. 「生成が失敗した日でも必ず何らかのお題が有効になり、お題待ち画面のまま一日が終わることがない」→ ✓ 達成（機構）

`PromptGenerationTests.testFallsBackWhenAllCandidatesAreUnsafe` / `testLastResortPromptWhenFallbackPoolIsAlsoEmpty` が成功。UI 側は `SprintNineAcceptanceTests.test07_autoGenFallbackStillShowsTodayScreen` で「auto-gen 経路でも今日のお題画面まで到達する（白画面で落ちない）」ことを確認。手動検証でも5段階すべての offset で「お題待ち」画面に陥ることは一度もなかった。

### 4. 「政治的対立・宗教対立・差別・個人情報の要求・医療診断・性的内容・犯罪助長に該当する候補は採用されず、破棄された記録が残る」→ ✓ 達成（機構）

`PromptCatalog.swift` の `disallowedKeywords` を直接読み、7観点すべて（`.politics` / `.religion` / `.discrimination` / `.privacy` / `.medical` / `.sexual` / `.crime`）に対応するキーワード判定が実装されていることを確認。`testDiscardsAreRecordedForUnsafeCandidatesBeforeAcceptedOne` で discard 記録が実際に残ることを確認。アプリコンテナの `state.json` に `discardedCandidatesCount` フィールドが実在し、デバッグオーバーレイにも `discarded N` として表示されることを画面で確認済み（候補プールが全件安全なため実測値は 0）。

### 5. 「短く答えられ、特定文化に依存せず、他人の答えを見ると面白い形式」→ ✓ 達成

`PromptCatalog.candidatePool`（50件）を直接読み、既存シード文言と同種の短い問いかけ（「今日、思わず笑ってしまったことは何ですか？」等）であることを確認。特定の国・宗教・文化に依存する語彙は含まれない。

### 6. 「お題の有効期間が24〜36時間の範囲で設定され、2つのお題が同時に「今日のお題」として表示されることがない」→ ✓ 達成

`Prompt.defaultDuration = 28 * 60 * 60`（28時間、24〜36hの範囲内）を確認。`testGeneratedPromptDurationIsInAcceptedRange` で担保。`testSeedCatalogScheduleStaysTimeOrdered`（schedule 内で隣接する prompt の period が重複しないことを確認するテスト）が成功していることを自分で実行して確認した。手動検証の5地点でも、画面上に2件のお題が同時に表示される事象は一度も観測されなかった。

## 回帰確認（3件以上の抜き取り、実施21件）
- `SprintOneAcceptanceTests`（コア体験）5件 — 全件成功
- `SprintTwoAcceptanceTests`（お題ライフサイクル。今回 `SeedCatalog` の `.expired`/`.upcoming`/`.expiring` 分岐が変更されたため優先選定）5件 — 全件成功
- `SprintThreeAcceptanceTests`（タイムライン取得ルール。`merge`/rebased posts のロジックが変更されたため優先選定）7件 — 全件成功
- `SprintSixAcceptanceTests`（翻訳。`PersistedState` の schemaVersion に触れる領域として選定）4件 — 全件成功

いずれも今回変更された `SeedCatalog.swift` の直接の影響範囲（お題待ち画面の前提・タイムラインの posts 組み立て）を優先して選定した。回帰は問題なし。

## データ整合性の直接確認
アプリコンテナの `Library/Application Support/SameQ/state.json` を直接読み取り、以下を確認した:
- `schemaVersion: 5`（self-review の申告と一致）
- `discardedCandidatesCount: 0`（フィールドが実在）
- `myPosts[0].expiresAt: "2026-08-26T06:14:00Z"` — これは `liveAnchor(2026-08-25 02:14 UTC) + 28h` と正確に一致しており、`.live` の固定アンカー方式が実際に動いていることをファイルレベルでも裏付けている
- `user` / `viewedPostIDs` / `likedPostIDs` / `reports` / `blockedAuthors` の各フィールドが揃っている

## 改善提案（合否には影響しない）
- self-review.md 自身が指摘している通り、`liveAnchor` がハードコードされた絶対日時（2026-08-25 02:14 UTC）である点は、将来的なリリース時期のズレに弱い。`PersistedState` に初回起動時刻を焼き付けて相対判定にする案（self-review 提案済み）を将来検討するとよい。
- `viewedPostIDs` が日をまたぐごとに際限なく積もっていく点（self-review「自分で見つけた弱点2」）も、長期運用では対応を検討する価値がある。

## 評価できなかったもの
- 受け入れ条件4（破棄記録）の実機での発火確認: 候補プールが全件安全なため、UIから実際に discard が1件以上発生する場面を再現する手段が無く、コード読解とユニットテストの結果を根拠にした（attempt1から変わらず）。
- dead zone 通過後、自動生成が数週間単位で継続して毎日切り替わり続けることの長期確認（4日連続の切り替わりまでは直接確認した。5日目以降は `PromptGenerator` 自体のロジック健全性からの推定）。
