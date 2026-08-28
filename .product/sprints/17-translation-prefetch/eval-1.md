# スプリント 17 評価（attempt 1） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6件中 4件を観測で確認。条件1は「最大3件」のデータ層のみ確認（先読みが実際に走る様子は観測不能）。条件2は観測不能 | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線完走。ユニット208 + UIテスト33 すべて緑。手動走行でも alert 0・ハング0 | クラッシュ0・未処理0・完走 | ✓ |
| 3 データ整合性 | `languageEncounters` が state.json に正しく永続化（schemaVersion 7→8）。background/foreground・再取得後も保持 | 100% | ✓ |
| 4 回帰 | 抜き取り 24/24（Sprint06 4本・Sprint07 6本・Sprint15 8本・Sprint16 6本）すべて緑 | 100% | ✓ |
| 5 使用性 | 4（主要動線は完走。空状態・読み切り表示は既存どおり機能。F41 はユーザー可視要素をあえて足さない設計で、その意図どおり） | 3以上 | ✓ |

**不合格。** 基準1が閾値未達。スプリントの中核成果である受け入れ条件2
（「先読みが済んだ言語の回答は、タイムラインで初めて出会っても『準備中』の待ちが発生せず、そのまま読める」）
を、この環境では一切観測できない。spec.md の当該スプリント「評価者への注記」は
**「先読みが実際に走ったことと、その結果として準備中の待ちが消えたことの両方を確認すること（仕組みが用意されているだけでは合格にしない）」**
と明記しており、実装・ユニットテストが揃っているだけでは合格にできない。

---

## 検証環境
- コミット `001739e`（autoloop: generator sprint=17 attempt=1）。評価後、作業ツリーはクリーン（`.product/eval-logs/` のみ untracked。本体コード・`project.pbxproj` に差分なし）
- シミュレータ: iPhone 17 / `35AAC789-1DF1-4C51-B14D-94A5084F6B26` / iOS 26 系、Xcode 26.6（17F113）、macOS
- 端末言語: 日本語（`AppleLanguages = ["ja","en"]` / `AppleLocale = ja_JP`）
- 実機（iPhone 17 Pro Max `B7121EA8-...`）は今回 **オフラインで接続不可**。`xcrun devicectl list devices` / `xctrace list devices` の双方で unavailable / offline
- 実行したテスト
  - `SameQTests` 全208本 → 緑（6.4s）
  - `SameQUITests/SprintSeventeenAcceptanceTests` 3本 → 緑
  - 回帰: `SprintSixteenAcceptanceTests` 6本 / `SprintSixAcceptanceTests` 4本 / `SprintSevenAcceptanceTests` 6本 / `SprintFifteenAcceptanceTests` 8本 → すべて緑
  - evaluator 一時 UIテスト `EvalSeventeenTests` 2本（多言語シード読破 + background/foreground、オフライン + background/foreground）→ 緑。**評価後に削除し `xcodegen generate` で復元済み**
- state.json 直接確認: `~/Library/Developer/CoreSimulator/Devices/35AAC789-.../data/Containers/Data/Application/<UUID>/Library/Application Support/SameQ/state.json`
- 実施 2026-08-28 09:13〜09:36 JST

---

## 受け入れ条件ごとの確認結果

### 条件1「先読みの対象は直近よく出会う言語のうち最大3件まで、それを超えて取得されない」— △（部分確認）
- **確認できたこと**: 多言語シード（`-SameQAnswerCount` なし）で `-SameQUseLocalBackend -SameQFakeTranslate` 起動し、タイムラインを 32件読破。その後 state.json を直接確認すると
  `languageEncounters = {"ar":1,"de":1,"en":3,"es":2,"fr":1,"it":1,"ko":2,"nl":1,"pl":1,"pt":1,"qtd":1,"ru":1,"th":1,"tr":1,"zh":1,"zxx":1}`
  （16言語、同梱シード prompt_001 の内訳と一致）。
  実装の並べ替え規則（回数降順・タイは言語コード昇順）と `topEncounteredLanguages(limit: 3)` により、先読み対象は必ず `["en","es","ko"]` の3件に絞られる。ユニット `LanguageEncounterTests.testTopEncounteredLanguagesRespectsLimit`（6言語→3件）も緑。→ **「対象数が4件以上に膨らまない」ことはデータ層で確認**。
- **確認できなかったこと**: 「先読みが実際に走って、その3件について翻訳準備が試みられた」こと。`peekTranslationsInBackground` → `translator.peekPrepareIfNeeded` を経ても、state.json の `lastPrepareAttemptAt` は `{}` のまま（下記 [1]）。実行の痕跡が観測できないため、「まとめて取得されることがない」を動作として確認できていない。

### 条件2「先読みが済んだ言語の回答は、初めて出会っても『準備中』の待ちが発生せず、そのまま読める」— ✗（観測不能）
- このシミュレータは Apple Translation が全言語ペアで `unsupportedLanguagePairing` を返す（generator 自身が `Translator.swift` のコメントに明記、過去の evaluator も実測済み）。よって実翻訳の「準備中」待ちも、その解消も、シミュレータ上に存在しない。
- 疑似翻訳モード（`-SameQFakeTranslate`）は「準備中」を再現できる仕組みだが、その唯一のマーカー言語 `qtd` は **background 先読み経路の対象にならない**（下記 [1] 参照）。
- 実機が使えないため、実 DL 完了後に「初回でも待ちが無い」ことを確認する手段が今回は無い。
- spec.md「評価者への注記」により、ここが確認できない以上は合格にできない。

### 条件3「先読みされていない言語はこれまでどおり（初回のみ準備中→完了後に読める）で、スプリント06が変わらない」— ✓
- 回帰: `SprintSixAcceptanceTests` 4本すべて緑（`test01_fakeTranslateAppliesAcrossTimelineWithoutStalling`、`test03_realTranslationReadsWholeSeedWithoutStallingOrOSInterruption` を含む）。
- 手動走行でも、多言語シードのタイムラインを 30回スワイプして各回 1.5秒前後で安定、原文が一瞬見えてから差し替わる「ちらつき」なし、`zxx`（翻訳不可マーカー）はカードとして一度も表示されず、alert 0。

### 条件4「先読みはアプリを開いていない間に行われ、使用中に画面が止まる・スワイプが引っかかる・進捗表示が割り込むことがない」— △（UI 非干渉は確認、先読み実行そのものは観測不能）
- トリガは `RootView` の `scenePhase == .background` のみ（コード確認）。`peekTranslationsInBackground` は `alertMessage` も `isPreparingTimeline` も触らない（コード + ユニット `BackgroundPeekTests.testBackgroundPeekDoesNotMutateUIState`）。
- 手動走行: タイムライン閲覧中に home → 15秒待機 → 復帰、を実施。復帰後もカード表示が残り、スワイプ・いいねが従来どおり、進捗表示の割り込み 0、alert 0。スワイプ latency は background 前後で変化なし（約1.5秒で一定）。
- ただし「アプリを開いていない間に先読みが実際に行われた」ことの実行痕跡は観測できていない（[1]）。

### 条件5「通信できない状態では先読みされず、エラー表示も出ない。回復後は通常どおり」— ✓（確認可能な範囲で）
- コード: `peekTranslationsInBackground` 冒頭 `guard await backend.isOnline() else { return }`。`SupabaseBackend.isOnline()` は `forceOffline || lastPathStatus != .satisfied` で false。
- ユニット `BackgroundPeekTests.testBackgroundPeekSkipsWhenOffline`（`ForceOfflineBackend` スタブ）緑。
- 手動走行: `-SameQForceOffline` 起動 → タイムライン到達 → home → 復帰。alert 0、クラッシュ 0。
- 注: `LocalBackend.isOnline()` は常に true のため、`-SameQUseLocalBackend` 併用時は offline 分岐自体を実機で踏めない（generator も weakness #1 として認識済み）。SupabaseBackend 経路の実確認は未。

### 条件6「アプリ内に、翻訳の先読みに関する設定・ダウンロード管理・進捗表示が1つも存在しない」— ✓
- `SprintSeventeenAcceptanceTests.test01_noPrefetchUIStringsExist` 緑（禁止識別子9種が画面上に存在しないことを確認）。
- 差分レビュー: ユーザー可視の文字列・画面・設定項目の追加なし。

---

## 不合格の原因（これを直せば通る）

### [1] 先読みが「実際に走った」ことも「準備中の待ちが消えた」ことも、開発者向け手段で観測できない
- **症状**:
  1. 多言語シードでタイムラインを 32件読み、`languageEncounters` に16言語（en3 / ko2 / es2 / 他1）が積まれた状態にする。
  2. home ボタンでアプリを background へ（`scenePhase == .background` → `Task { await session.peekTranslationsInBackground() }` が起動）。
  3. 15秒待って foreground へ復帰。
  4. state.json を直接確認 → `lastPrepareAttemptAt` は `{}` のまま。`languageEncounters` 以外に先読みの実行を示すフィールド・ログ・UI の変化が一切ない。
- **なぜ観測できないか（推測。症状とは分けて記載）**:
  - 実翻訳モード: このシミュレータは全ペア `.unsupported` を返すため、`Translator.prepareIfNeeded` 内の `shouldAttemptPreparation` が false になり、`recordModelPrepareAttempt`（= `lastPrepareAttemptAt` への書き込み）まで到達しない。
  - 疑似翻訳モード: `shouldAttemptPreparation` が true を返すのは `fakeNeedsDownloadSourceCodes = ["qtd"]` だけ。`qtd` は「準備中」を再現できる唯一のマーカーだが、`qtd` の回答は初回 `.unavailable(permanent:false)`（一時失敗）で `languageEncounters` に記録されず、`topEncounteredLanguages` の上位に来ないため `peekTranslationsInBackground` の対象にならない。さらに疑似経路 `fakePrepareIfNeeded` は `lastPrepareAttemptAt` を書かない。
  - 結果として、「background 先読み経路が翻訳準備を実際に試みた」ことを示す痕跡が、実機なしでは 1つも残らない。
- **期待**: spec.md「評価者への注記」——「先読みが実際に走ったことと、その結果として準備中の待ちが消えたことの両方を確認」できること。開発者向けの手段（起動引数・疑似モード等）で発生させて確認してよい、とされている。
- **通すために必要なこと（いずれか）**:
  - (a) 疑似翻訳インフラを background 先読み経路に対応させる。例:
    - `peekTranslationsInBackground` の対象言語（`topEncounteredLanguages` の上位3件）について、疑似モードでも `peekPrepareIfNeeded` が「準備完了」を記録する（`fakeDownloadedSourceCodes` に入れる等）ようにする。
    - 先読みが試みた言語を state.json に残す（疑似モードでも `lastPrepareAttemptAt` を書く、または `peekedLanguages` のようなフィールドを追加する）。これで state.json 直接確認だけで「実際に走った」ことを第三者が確認できる。
    - UIテストを1本追加: あるマーカー言語に初回出会って「準備中」/スキップになる → background → foreground → 同じ言語に再度出会うと **待ちなしで読める** ことを end-to-end で確認する。
  - (b) 実機（Apple Translation が実際に動く端末）で検証し、証跡を添付する。sprint 06 eval-7 と同様に、background 先読み後の実機 state.json に `lastPrepareAttemptAt` が上位3言語で埋まること、および対象言語の初回表示に「準備中」待ちが出ないことのタイミング実測を残す。

---

## 改善提案（合否には影響しない）
1. **優先度中**: `LocalBackend.isOnline()` が常に true のため、`-SameQUseLocalBackend -SameQForceOffline` 併用でも offline 分岐を踏めない。検証用に `LocalBackend` でも `-SameQForceOffline` を尊重する経路があると、条件5 を実機なしで確認できる。
2. **優先度低**: エンカウンタに減衰・上限が無いため、長期利用で半年前によく見た言語が top-3 に居座り続ける。F41 の spec には無いので今回は不要だが、体験の実効性に関わる。
3. **優先度低**: 先読みの実行結果をデバッグオーバーレイに出す（`prefetched: en, es, ko` 程度）と、以後の評価が大幅に楽になる。F19 の「UI を出さない」はエンドユーザー向けの話であり、Debug オーバーレイは対象外と解釈できる。

---

## 評価できなかったもの
- 受け入れ条件2 の全体（先読み済み言語が待ちなしで読める）。実機が接続不可・シミュレータで Apple Translation が動かない・疑似モードが background 先読み経路に非対応、の3点が重なり、観測手段が無かった。
- 条件1・4 のうち「先読みが実際に実行される」部分。同上の理由で実行痕跡が残らない。
- SupabaseBackend 経路の `isOnline()` 実挙動（実機／実ネットワーク条件が必要）。
