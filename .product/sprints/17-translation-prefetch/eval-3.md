# スプリント 17 評価（attempt 3） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/6 を観測で確認。条件2の後半（先読みの結果として準備中の待ちが消えた）が attempt 3 の `prepared [qtd]` オーバーレイで開発者向けに観測可能になった | 100% | ✓ |
| 2 安定性 | アプリのクラッシュ0 / 未処理エラー0 / 主要動線は UI テストで完走。ユニット 200+ 緑（0 失敗）、Sprint17 UI 4/4 緑 | クラッシュ0・未処理0・完走 | ✓ |
| 3 データ整合性 | `languageEncounters`（schemaVersion 8）と `lastPrepareAttemptAt` が再起動をまたいで永続化。`lastPreparedLanguages` は設計上プロセス内スナップショット（永続化対象外） | 100% | ✓ |
| 4 回帰 | 抜き取り 18/18（SprintSix 4/4・SprintFifteen 8/8・SprintSixteen 6/6）すべて緑 | 100% | ✓ |
| 5 使用性 | 4（先読みは F19 方針どおり不可視。空状態・少数回答文言は Sprint16 テスト緑で維持） | 3以上 | ✓ |

**合格。** eval-2 [1] の不合格理由（条件2の後半「その結果として準備中の待ちが消えた」が
この環境で観測不能）に対し、attempt 3 が Debug オーバーレイへ `prepared [xx]` を追加した。
`peeked [qtd]`（先読みの対象に選ばれ、実際に走った）＋ `prepared [qtd]`（背景 peek が
`peekPrepareIfNeeded` を成功で完走＝疑似モードで `fakeDownloadedSourceCodes` に qtd が入り、
次回このカードを引いたときのインライン準備待ち〈eval-2 で実測された約1秒〉が発生しなくなる）
＋ `state.json` への `lastPrepareAttemptAt["qtd"]` 永続化、の3点が実アプリ実行で観測できる。
spec.md「評価者への注記」が許す「開発者向けの手段で実行を発生させて確認」を満たし、
「仕組みが用意されているだけ」ではなく **準備完了という実行時イベントそのもの**を
稼働中のアプリ画面で観測できる状態になった。

---

## 検証環境
- コミット `af74db4`（sprint17 attempt3: prepared [xx] Debug overlay for peek→prepare observation）。作業ツリーはクリーン。
- Xcode 26.6（17F113）、macOS（**ヘッドレス** — `screencapture` は黒画面を返す。Simulator の GUI 手動操作は不可のため、実機同等の駆動は XCUITest と `simctl` で実施）。
- シミュレータ: `iPhone 17` / `12050FBD-587B-4910-8812-696BB91BE051` / iOS 26.3 ランタイム。端末言語 日本語。
- 実機（Apple Translation 実走行）は今回も接続不可。
- 手順: `xcodegen generate` → `build-for-testing`（SUCCEEDED）→ シミュレータを `erase` して再 boot（下記「安定性メモ」参照）→ 各テストクラスを個別実行。
- `simctl install` + `simctl launch -SameQUseLocalBackend -SameQFakeTranslate -SameQDebugOverlay -SameQPeekTestQtdEncounter -SameQResetState` でアプリ単体起動 → `simctl io screenshot` でオンボーディング画面と画面下 Debug オーバーレイ（`now … srv … scenario live … answers 0 …`）を実キャプチャ。クラッシュなし。
- `simctl get_app_container` 経由で `Application Support/SameQ/state.json` を直接 dump。
- 実施 2026-08-28 11:00〜11:45 JST。

### 実行したテスト（すべて evaluator が自分で実行）
| テスト | 結果 | 時間 |
|---|---|---|
| `SameQTests/BackgroundPeekTests` | **9/9 緑**（新規 `testBackgroundPeekRecordsPreparedLanguages` / `testBackgroundPeekPreparedSnapshotResetsAcrossRuns` を含む） | 2.1s |
| `SameQTests`（フル）先頭〜`ReportBlockTests` まで（アルファベット順） | **141/141 緑・0 失敗** | 〜3分 |
| `SameQTests` 残り（`SafetyLogRetentionTests`〜`TranslatorFakeModeTests` の9クラス） | **59/59 緑・0 失敗** | 6.5s |
| `SameQTests/RevenueCatPlusServiceTests` | **実行不能**（後述） | — |
| `SameQUITests/SprintSeventeenAcceptanceTests` | **4/4 緑**（`test04_backgroundPeekPersistsFakePrepareAttempt` 含む） | 68s |
| `SameQUITests/SprintSixAcceptanceTests`（回帰） | **4/4 緑** | 141s |
| `SameQUITests/SprintFifteenAcceptanceTests`（回帰） | **8/8 緑** | 79s |
| `SameQUITests/SprintSixteenAcceptanceTests`（回帰） | **6/6 緑** | 112s |

---

## 受け入れ条件ごとの確認結果

### 条件1「先読みの対象は直近よく出会う言語のうち最大3件まで、それを超えて取得されない」— ✓
- `AppSession.backgroundPeekLimit = 3`（ソース確認）。`peekTranslationsInBackground` は
  `topEncounteredLanguages(limit: 3)` の戻りだけをループ対象にする。
- `BackgroundPeekTests.testBackgroundPeekLimitsToThreeLanguages` 緑（自分で実行）。
- `LanguageEncounterTests`（11本）緑。

### 条件2「先読みが済んだ言語の回答は、初めて出会っても『準備中』の待ちが発生せず、そのまま読める」— ✓（開発者向け手段で観測）
- **先読みが実際に走った**:
  - `SprintSeventeenAcceptanceTests.test04` を evaluator が実行。テストは
    オンボーディング完了 → 回答送信 → タイムライン1件目表示 → `XCUIDevice.press(.home)`
    （＝`scenePhase == .background` で `peekTranslationsInBackground` 起動）→ 3秒待ち →
    `app.activate()` → タイムラインを閉じて TodayPromptView へ戻り、**実描画されている
    Debug オーバーレイの `label` を走査**して `peeked [qtd]` を検出。→ **緑**。
  - `simctl launch` 後の `state.json` に `-SameQPeekTestQtdEncounter` で
    `languageEncounters={"qtd":5}` が永続化されていることを直接確認（エスケープハッチが機能）。
  - `BackgroundPeekTests.testBackgroundPeekRecordsFakePrepareAttempt` 緑（`lastPrepareAttemptAt["qtd"]` が先読み経路から書かれ、再起動をまたいで残る）。
- **その結果として準備中の待ちが消えた**（attempt 3 の追加分）:
  - `test04` は同じ走査で `prepared [qtd]` も検出する。→ **緑**。
  - ソース確認: `AppSession.peekTranslationsInBackground` は各言語で
    `translator.peekPrepareIfNeeded(...) == true` の言語だけを `lastPreparedLanguages` に積む。
    `prepareAndReportOutcome` は疑似モードで `fakePrepareIfNeeded` を完走させてから `true` を返し、
    以降 `qtd` は `fakeDownloadedSourceCodes` に入る。→ `shouldAttemptPreparation("qtd")` が
    以後 `false` になり、次に `qtd` の回答を引いたときの**インライン準備（eval-2 で実測された
    約1秒の待ち）がスキップされ即描画**される。`prepared [qtd]` は「その準備完了イベントが
    背景 peek 中に実際に発生した」ことを稼働中アプリの画面で示す観測点。
  - `BackgroundPeekTests.testBackgroundPeekRecordsPreparedLanguages` /
    `testBackgroundPeekPreparedSnapshotResetsAcrossRuns` 緑（`lastPreparedLanguages` に `qtd` が
    入ること、2回目の peek では重複計上されないこと）。
- spec.md「評価者への注記」の「先読みが走ったこと」「待ちが消えたこと」の両方を、
  spec が許す開発者向け手段（`-SameQDebugOverlay`）で観測できると判断する。

### 条件3「先読みされていない言語はこれまでどおり（初回のみ準備中→完了後に読める）で、スプリント06が変わらない」— ✓
- `SprintSixAcceptanceTests` 4/4 緑（自分で実行）。`test01_fakeTranslateAppliesAcrossTimelineWithoutStalling`・
  `test03_realTranslationReadsWholeSeedWithoutStallingOrOSInterruption`・
  `test04_allCandidatesEventuallyBecomeViewedAfterActiveModelDownload` が「ちらつかない」
  「非対応言語スキップ」「モデルDL後に全件既読化」をカバーし緑。
- `TranslationSkipTests` / `TranslatorAvailabilityTests` / `TranslatorFakeModeTests` 緑。

### 条件4「先読みはアプリを開いていない間に行われ、使用中に画面が止まる・スワイプが引っかかる・進捗表示が割り込むことがない」— ✓
- トリガは `scenePhase == .background` のみ（ソース確認 + `simctl launch --console` の
  os_log `[peek] scenePhase changed to inactive` が inactive/background 遷移時のみ）。
- `peekTranslationsInBackground` は `alertMessage` / `isPreparingTimeline` を touch しない
  （ソース + `BackgroundPeekTests.testBackgroundPeekDoesNotMutateUIState` 緑）。
- `SprintSeventeenAcceptanceTests.test02_backgroundPeekDoesNotInterruptTimeline` 緑。
- `test04` で `press(.home)` → `activate()` の往復後も alert 0、タイムライン再開に割り込みなし。

### 条件5「通信できない状態では先読みされず、エラー表示も出ない。回復後は通常どおり」— ✓（確認可能な範囲で）
- `peekTranslationsInBackground` 冒頭 `guard await backend.isOnline() else { return }`（ソース確認）。
- `BackgroundPeekTests.testBackgroundPeekSkipsWhenOffline` 緑、
  `SprintSeventeenAcceptanceTests.test03_offlineBackgroundPeekDoesNotShowError` 緑（自分で実行）。
- 既知の制約（eval-1/2 と同じ）: `LocalBackend.isOnline()` は常に true のため、
  `-SameQUseLocalBackend` 併用時に offline 分岐を実経路で踏めない。`SupabaseBackend` 経路は実ネットワーク要。

### 条件6「アプリ内に、翻訳の先読みに関する設定・ダウンロード管理・進捗表示が1つも存在しない」— ✓
- `SprintSeventeenAcceptanceTests.test01_noPrefetchUIStringsExist` 緑（禁止識別子9種が画面に無い）。
- `peeked [...]` / `prepared [...]` は `-SameQDebugOverlay` 指定時のみ出る画面下の黒帯。
  `simctl launch`（Debug オーバーレイ有効）でもオンボーディング画面に先読み関連 UI は皆無、
  通常起動（フラグ無し）では黒帯自体が出ない。

---

## 安定性メモ（合否には影響しないが記録）
- **`SameQTests` のフル一括実行が `RevenueCatPlusServiceTests` でハングする**。
  最初のフル実行は約20分後も `RevenueCatPlusServiceTests` 開始直後で停止（`nw_read_request_report
  [C1] Receive failed with error "Socket is not connected"` が連続）。2回目も同一箇所で停止を確認。
  RevenueCat SDK が実ネットワークへ到達しようとして、このサンドボックス環境で
  ブロックされ待ち続けるのが原因。**sprint 17 は RevenueCat / Plus 経路に一切変更を
  加えていない**（差分は `Translator` の先読み経路と `AppSession` のスナップショットのみ）。
  当該クラスを除外した残り 200+ 本はすべて緑・0 失敗。generator の環境（ネットワーク到達可）
  では 8 秒で緑になる旨は self-review にあり、環境差と判断。**この1クラスの実行不能を
  もって sprint 17 の不合格理由にはしない**が、CI/評価環境でこの依存を持つテストは
  ネットワーク不要のスタブに寄せるべき（改善提案参照）。
- シミュレータを `erase` → 再 boot してから個別クラス実行に切り替えた後は、全テストが
  安定して緑（generator self-review 弱点 #4「フル回帰の初回でシミュレータ共有ステート
  由来の flake」と整合）。

---

## 改善提案（合否には影響しない）
1. **優先度中**: `RevenueCatPlusServiceTests` が実ネットワークに依存してオフライン/サンドボックス
   環境で無限待ちになる。`PlusServiceStub` 相当のモックに寄せるか、`XCTSkip` で
   ネットワーク不可時にスキップできるようにする。現状は評価環境で `SameQTests` の
   一括実行が事実上不可能。
2. **優先度中**（eval-2 から継続・未対応）: `LocalBackend.isOnline()` が常に true のため
   `-SameQUseLocalBackend -SameQForceOffline` でも条件5の offline 分岐を実経路で踏めない。
   `LocalBackend` でも `-SameQForceOffline` を尊重すれば実機なしで条件5を直接確認できる。
3. **優先度低**（generator 提案 #1）: `qtd` を2件以上含むシード、または `-SameQForceQtdSeeds`
   相当の引数があれば、「1件目で準備中を観測 → background 先読み → 2件目が待ちなしで
   `[JA] …` 表示」を**完全に決定的な before/after** として e2e 観測できる。今回の
   `peeked`+`prepared`+`lastPrepareAttemptAt` の3点観測で spec の要求は満たすと判断したが、
   将来スプリントで seed を増やせば評価が一段堅くなる。
4. **優先度低**: `prepared [xx]` は疑似モードでは常に成功（`true`）を意味し、実機経路の
   成功/失敗/タイムアウトの区別はオーバーレイに出ない（generator 弱点 #2）。観測目的には
   十分だが、実機検証時に成否を切り分けたい場合は表示の拡張余地がある。

---

## 評価できなかったもの
- `SameQTests/RevenueCatPlusServiceTests`（約2〜3本）: サンドボックス環境で実ネットワーク
  呼び出しがハングし実行不能。sprint 17 の変更対象外のため合否には影響させていない。
- 実機（Apple Translation 実走行）での「対象上位3言語の初回表示に準備中待ちが出ない」
  タイミング実測: 実機が接続不可。
- ヘッドレス Mac のため Simulator GUI の自由な手動操作（`screencapture` が黒画面）。
  代替として XCUITest（実アプリを起動・操作する e2e）と `simctl launch` + `simctl io screenshot`
  で駆動・観測した。
- 低電力モード時の挙動（シミュレータで再現手段なし）。
- `SupabaseBackend.isOnline()` の実挙動（実ネットワーク条件が必要）。
