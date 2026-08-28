# スプリント 17 評価（attempt 2） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6件中5件を観測で確認。条件2は「先読みが実際に走った」半分のみ観測可能になった。「準備中の待ちが消えた」半分はこの環境で依然として観測不能 | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0 / 主要動線完走。ユニット210 + BackgroundPeek7 + LanguageEncounter11、UI Sprint17 4本すべて緑。手動走行3シナリオで alert 0・ハング0 | クラッシュ0・未処理0・完走 | ✓ |
| 3 データ整合性 | `languageEncounters`（16言語）が state.json に schemaVersion 8 で永続化。background/foreground・アプリ再起動後も保持。`lastPrepareAttemptAt["qtd"]` も先読み経路から永続化される | 100% | ✓ |
| 4 回帰 | 抜き取り 18/18（Sprint06 4本・Sprint15 8本・Sprint16 6本）すべて緑。手動でも「ちらつき」「非対応言語スキップ」の回帰なし | 100% | ✓ |
| 5 使用性 | 4（主要動線完走。空状態「今は新しい回答がありません／すべて読みました」・少数回答の前向き文言が機能。先読みはF19の方針どおり不可視で、その意図は正しい） | 3以上 | ✓ |

**不合格。** 基準1が閾値未達。eval-1 [1] の指摘のうち **「先読みが実際に走った」半分は
attempt 2 で観測可能になった**（`peeked [en, es, ko]` が Debug オーバーレイに出る／
`lastPrepareAttemptAt["qtd"]` が先読み経路から state.json に書かれる）が、
**「その結果として準備中の待ちが消えた」半分は依然として観測できない**。
spec.md「評価者への注記」は **「先読みが実際に走ったことと、その結果として準備中の待ちが
消えたことの両方を確認すること（仕組みが用意されているだけでは合格にしない）」** と明記
しており、片方が確認できない以上は合格にできない。generator 自身も self-review の
「自分で見つけた弱点 #1」で「『qtd に再会して待ちなしで読める』を e2e で観測する UI テストは
無い」「最終確認は実機でのみ可能」と認めている。

---

## 検証環境
- コミット `3a15a4f`（autoloop: generator sprint=17 attempt=2）。作業ツリーはクリーン。
- シミュレータ: iPhone 17 / `35AAC789-1DF1-4C51-B14D-94A5084F6B26` / iOS 26.5、Xcode 26.6（17F113）、macOS。端末言語 日本語。
- 実機: `iPhone 17 Pro Max`（`B7121EA8-…`）は unavailable/offline。`Hano iphoneXSmax`（iOS 18.7.9）は devicectl で paired だが xctrace では offline。実機での Apple Translation 実走行は今回も不可。
- `xcodegen generate` 後にビルド。バイナリ再ビルド時刻 10:06（コミット 10:02 より後、= attempt 2 の変更を反映済み）。
- 実行したテスト（すべて緑）:
  - `SameQTests` 全210本（6.8s）
  - `SameQTests/BackgroundPeekTests` 7本 + `SameQTests/LanguageEncounterTests` 11本
  - `SameQUITests/SprintSeventeenAcceptanceTests` 4本（65s、`test04_backgroundPeekPersistsFakePrepareAttempt` 含む）
  - 回帰: `SprintSixAcceptanceTests` 4本 / `SprintFifteenAcceptanceTests` 8本 / `SprintSixteenAcceptanceTests` 6本
- 手動走行（Maestro で駆動、`-SameQUseLocalBackend -SameQFakeTranslate -SameQDebugOverlay -SameQResetState`）:
  1. `-SameQAnswerCount 8` + `-SameQPeekTestQtdEncounter`: オンボ→回答→タイムライン8件→background→foreground。
  2. 多言語シード（AnswerCount なし）: オンボ→回答→タイムライン32件読破→background→foreground。
  3. `-SameQPeekTestQtdEncounter` + 多言語シード: オンボ→回答→タイムライン全読破→background→foreground。
- state.json 直接確認: `…/Application Support/SameQ/state.json` を各手動走行の前後で dump。
- 実施 2026-08-28 10:05〜10:24 JST。

---

## 受け入れ条件ごとの確認結果

### 条件1「先読みの対象は直近よく出会う言語のうち最大3件まで、それを超えて取得されない」— ✓（attempt 2 で観測可能になった）
- 手動走行2で多言語シードのタイムラインを32件読破。state.json の
  `languageEncounters = {ar:1, de:1, en:3, es:2, fr:1, it:1, ko:2, nl:1, pl:1, pt:1, qtd:1, ru:1, th:1, tr:1, zh:1, zxx:1}`（16言語）。
- home でバックグラウンドへ → 復帰。Debug オーバーレイに **`peeked [en, es, ko]`** が出た（スクショ `/tmp/eval_ml_peek.png`）。
  出会い回数上位3件（en:3, es:2, ko:2、タイは言語コード昇順）とちょうど一致。**16言語をまとめて取りに行っていない／4件以上に膨らんでいない**ことを画面で確認。
- `-SameQPeekTestQtdEncounter` 併用時は `peeked [qtd]` が出る（手動走行1・3、UI test04 と一致）。
- ユニット `LanguageEncounterTests.testTopEncounteredLanguagesRespectsLimit` も緑。

### 条件2「先読みが済んだ言語の回答は、初めて出会っても『準備中』の待ちが発生せず、そのまま読める」— ✗（前半のみ確認、後半が観測不能）
- **前半「先読みが実際に走った」= 確認できた（eval-1 [1] の修正が効いている）**:
  - `peeked [en, es, ko]` / `peeked [qtd]` が background 後に Debug オーバーレイへ出る（上記）。
  - `-SameQPeekTestQtdEncounter` 付きの手動走行1で background → 復帰後、state.json の
    `lastPrepareAttemptAt` に `{"qtd": "2026-08-28T01:10:17Z"}` が書かれた（attempt 1 では `{}` のままだった）。
    先読み経路（`peekTranslationsInBackground` → `Translator.prepareIfNeeded`）が「準備を試みた」痕跡を残すようになった。
- **後半「準備中の待ちが消えた」= 依然として観測できない**:
  - 疑似翻訳モードで先読み対象になる言語（en/es/ko）は、そもそも「準備中」待ちが発生しない（`shouldAttemptPreparation` が false で `prepareIfNeeded` は即 return、`lastPrepareAttemptAt` も en/es/ko には書かれない）。よって「待ちが消えた」contrast が作れない。
  - 唯一「準備中」を再現するマーカー `qtd` は、通常のタイムライン閲覧中に **前景のインライン準備（`fakePrepareIfNeeded` の約1秒）で解決してカード表示され、`viewedPostIDs` に入る**（手動走行3で確認: qtd post `2A454F55-…` は viewed 済み）。先読みの有無で「待ちが出る／消える」の差を UI で切り分ける手段が無い。qtd を含むシードは1件のみで、「先読み前は読めない → 先読み後に待ちなしで読める」を確定的に再現できない。
  - 実機（Apple Translation 実走行）も今回使用不可。
- spec.md「評価者への注記」により、この後半が確認できない以上は合格にできない。

### 条件3「先読みされていない言語はこれまでどおり（初回のみ準備中→完了後に読める）で、スプリント06が変わらない」— ✓
- 回帰: `SprintSixAcceptanceTests` 4本すべて緑。
- 手動走行2で多言語タイムラインを32件スワイプ。各カード約1.5秒で安定、原文が一瞬見えて差し替わる「ちらつき」なし、`zxx`（翻訳不可マーカー）はカードとして一度も表示されず、alert 0。空状態「このお題の回答はすべて読みました」まで到達。

### 条件4「先読みはアプリを開いていない間に行われ、使用中に画面が止まる・スワイプが引っかかる・進捗表示が割り込むことがない」— ✓
- トリガは `RootView` の `scenePhase == .background` のみ（コード確認 + `peekTranslationsInBackground: start` os_log が background 時のみ出る）。
- `peekTranslationsInBackground` は `alertMessage` / `isPreparingTimeline` を触らない（コード + ユニット `BackgroundPeekTests`）。
- 手動走行1〜3で home → 3〜5秒待機 → 復帰。復帰後もカード表示が残り、スワイプ・いいねが従来どおり、進捗表示の割り込み 0、alert 0。
- `SprintSeventeenAcceptanceTests.test02_backgroundPeekDoesNotInterruptTimeline` 緑。

### 条件5「通信できない状態では先読みされず、エラー表示も出ない。回復後は通常どおり」— ✓（確認可能な範囲で）
- コード: `peekTranslationsInBackground` 冒頭 `guard await backend.isOnline() else { return }`。os_log `peekTranslationsInBackground: offline, skip` を `BackgroundPeekTests.testBackgroundPeekSkipsWhenOffline` の実行ログで確認。
- `SprintSeventeenAcceptanceTests.test03_offlineBackgroundPeekDoesNotShowError` 緑。
- 注（eval-1 と同じ）: `LocalBackend.isOnline()` は常に true のため、`-SameQUseLocalBackend` 併用時は offline 分岐を実機経路で踏めない。`SupabaseBackend` 経路の実確認は未（実ネットワーク条件が必要）。

### 条件6「アプリ内に、翻訳の先読みに関する設定・ダウンロード管理・進捗表示が1つも存在しない」— ✓
- `SprintSeventeenAcceptanceTests.test01_noPrefetchUIStringsExist` 緑（禁止識別子9種が画面上に無い）。
- `peeked [...]` の文字列は `-SameQDebugOverlay` 指定時のみ出る画面下の黒帯。エンドユーザー向けには従来どおり何も出ない。手動走行でも通常起動時に先読み関連の UI は皆無。

---

## 不合格の原因（これを直せば通る）

### [1] 「先読みが済んだ言語は初回でも待ちなしで読める」を開発者向け手段で観測できない（eval-1 [1] の後半が未対応）
- **症状**:
  1. `-SameQUseLocalBackend -SameQFakeTranslate -SameQDebugOverlay -SameQResetState -SameQPeekTestQtdEncounter` で起動し、オンボーディング〜回答〜タイムラインへ。
  2. タイムラインを全件スワイプすると、`qtd` の回答（作者 Quilo 📡 / 本文 "Sennoreth abd calvi …— sameQ_download_pending_test_marker."）は **前景のインライン準備で解決してそのまま表示される**（`viewedPostIDs` に入る）。
  3. home → 3秒 → 復帰。Debug オーバーレイに `peeked [qtd]` は出る（＝先読みは走った）。しかし「先読みをしたから待ちが消えた」ことを示す差分は、UI にもログにも state.json にも無い。
  4. en/es/ko については `lastPrepareAttemptAt` すら書かれない（疑似モードで `shouldAttemptPreparation` が false のため）。
- **期待**: spec.md「評価者への注記」——「先読みが実際に走ったことと、**その結果として準備中の待ちが消えたこと**の両方」を、開発者向けの手段で発生させて確認できること。
- **通すために必要なこと（いずれか。eval-1 [1] 案(a) と同趣旨）**:
  - (a) 「先読み前は準備中でスキップ／表示できない → background → 復帰 → 同じ言語の回答が待ちなしで読める」を **確定的に再現できる Debug 導線**を用意する。例:
    - `qtd` を2件以上含むシード、または `-SameQForceQtdSeeds` 相当の引数（generator の「提案 #4」に既出）。1件目でスキップ/準備中を観測 → background 先読み → 2件目が `[JA] …` で待ちなし表示、を UI テスト＋手動で確認できる形にする。
    - あるいは、先読み対象言語の翻訳準備状態（`fakeDownloadedSourceCodes` / `statusCache`）の遷移を Debug オーバーレイに出す（`prepared [qtd]` 等）。`peeked` が「試みた」で `prepared` が「完了した」を表せば、background 前後の差分が画面で観測できる。
  - (b) `-SameQFakeTranslate` の先読み経路を en/es/ko でも「準備中→完了」を1回踏むようにする（現状は即 return で痕跡ゼロ）。少なくとも `lastPrepareAttemptAt` を対象3言語で埋め、「先読みで準備を試みた言語」と「まだの言語」が state.json で区別できるようにする。
  - (c) 実機（Apple Translation 実走行）で、background 先読み後に対象上位3言語の初回表示に「準備中」待ちが出ないことをタイミング実測し、証跡（state.json + 計測ログ）を添付する。
- **根拠**: スクショ `/tmp/eval_ml_peek.png`（`peeked [en, es, ko]`）、`/tmp/eval_qtd_before.png`（qtd 含め全件読破済みの空状態）、手動走行1の state.json dump（`lastPrepareAttemptAt = {"qtd": …}`、en/es/ko は無し）、self-review「自分で見つけた弱点 #1」。

---

## 改善提案（合否には影響しない）
1. **優先度中**: `SameQTests/BackgroundPeekTests.swift` の既存テスト（129行目付近、`testBackgroundPeekDoesNotMutateUIState` 相当）で絵文字リテラルが文字化けしている（`"🐢"` → U+FFFD `"�"`。UTF-8 バイト `ef bf bd`）。ビルド・テストは通るが、attempt 2 の差分で混入した意図しない改変。元の `🐢` に戻すこと。
2. **優先度中**（eval-1 から継続）: `LocalBackend.isOnline()` が常に true のため、`-SameQUseLocalBackend -SameQForceOffline` 併用でも offline 分岐を実機経路で踏めない。`LocalBackend` でも `-SameQForceOffline` を尊重すれば条件5を実機なしで確認できる。
3. **優先度低**: `AppSession.drawNextPost` で `.unavailable(permanent: false)` でも `recordLanguageEncounter` を積むようにした結果、1回見ただけの一時失敗言語が減衰なしで top-3 に居座り得る（self-review 弱点 #3）。F41 の spec には無いので今回は不要だが、長期利用時の実効性に関わる。

---

## 評価できなかったもの
- 受け入れ条件2 の後半（先読み済み言語が初回でも待ちなしで読める）。疑似モードで先読み対象言語に「準備中」待ちが発生しない・`qtd` はインライン準備で先に解決する・`qtd` シードが1件のみ・実機が接続不可、の4点が重なり、観測手段が無かった。→ 上記 [1] の Debug 導線があれば次回確認できる。
- `SupabaseBackend` 経路の `isOnline()` 実挙動（実機／実ネットワーク条件が必要）。
- 低電力モード時の挙動（シミュレータで再現手段が無い）。
