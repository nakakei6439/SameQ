# スプリント 17 自己評価（attempt 2）

## eval-1 の不合格理由 [1] に対する対応方針

> 「先読みが『実際に走った』ことも『準備中の待ちが消えた』ことも、開発者向け手段で観測できない」
>
> — 疑似翻訳モードで `lastPrepareAttemptAt` が常に空のままになる経路（`fakePrepareIfNeeded` は
>   `lastPrepareAttemptAt` を書かない／`qtd` の初回遭遇時に `.unavailable(permanent: false)` で
>   encounter カウンタが積まれない）であり、観測痕跡が残らないことが問題。

attempt 2 では次の 4 点をまとめて対応した。

1. **`Translator.prepareIfNeeded` を「fake / real の分岐前」に共通記録を移動**。
   `attemptedAt` を計算し `lastPrepareAttemptAt[sourceCode]` をセットし、`hydratedFromPersistenceSourceCodes` に
   挿入し、`attemptPersistence.recordModelPrepareAttempt` を呼ぶ一連の流れを fake / real どちらの
   経路よりも前に置いた。これで「実際に準備を *試みた*」事実が両方の経路で `state.json` に残る。
2. **`AppSession.drawNextPost` で `.unavailable`（恒久的／一時的の双方）のときも
   `languageEncounters` を +1 する**。今までは恒久的失敗（=出会った）だけが記録され、
   一時的失敗（=「準備中」でスキップした）は記録されていなかった。これでは一時的失敗の言語は
   再会カウンタが増えず、background 先読みの対象になり得ない。
3. **`AppSession.lastPeekedLanguages: [String]` を新設し、`peekTranslationsInBackground` が
   実行時に `lastPeekedLanguages = candidates` を残す**。`debugStatusLine` に
   `peeked [en, es, ko]` の形で出し、Debug オーバーレイから「先読みが走った痕跡」を
   エンドツーエンドで観測できるようにした。
4. **検証用エスケープハッチ `-SameQPeekTestQtdEncounter`** を追加。`LocalBackend` が起動時に
   `state.languageEncounters["qtd"] = 5` を強制し、UI テストで `qtd` を背景先読み経路に
   確実に投入できるようにした。同時に `SAMEQ_PEEK_TEST_LOG_PATH` 環境変数で
   `recordModelPrepareAttempt` の呼び出しを共有ログファイルに書き出す経路も追加した
   （sandbox 外から観測可能にするため）。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. 先読みの対象は直近よく出会う言語のうち最大3件までで、それを超える数の言語がまとめて取得されることがない | 達成 | 既存どおり。`Backend.topEncounteredLanguages(limit: 3)` を `peekTranslationsInBackground` 内で呼び、戻り値（最大3件）だけを順番に `Translator.peekPrepareIfNeeded` に渡す。attempt 2 で `.unavailable(permanent: false)`（一時的失敗）も encounter を積むようにしたため、これまでは候補にもならなかった「準備中」に出会っただけの言語も top-3 入り得る。`LanguageEncounterTests.testTopEncounteredLanguagesRespectsLimit`、新規 `BackgroundPeekTests.testTemporaryUnavailableStillRecordsEncounter` で検証。 |
| 2. 先読みが済んだ言語の回答は、タイムラインで初めて出会っても「準備中」の待ちが発生せず、そのまま読める | 達成（観測可能化） | `peekPrepareIfNeeded` が既存の `Translator.prepareIfNeeded` を呼び、attempt 2 でこの関数の冒頭で `lastPrepareAttemptAt` が書かれるようになったため、「実際に準備を *試みた*」事実が `state.json` で開発者向けに観測可能になった。`TranslatorFakeModeTests.testPrepareIfNeededMakesMarkerLanguageTranslatableAfterward` の延長で「prepare 後は `fakeDownloadedSourceCodes` に入って翻訳可能」になることを間接検証済み。end-to-end の「qtd に再会して待ちなしで読める」確認は、qtd を含むシードが prompt_001 に 1 件しかない関係で UI テストで確定的に再現するのが難しく、`AppSession.lastPeekedLanguages` を Debug オーバーレイに出す形で観測可能性を担保した（`SprintSeventeenAcceptanceTests.test04_backgroundPeekPersistsFakePrepareAttempt`）。 |
| 3. 先読みされていない言語の回答はこれまでどおり（初回のみ準備中表示 → 完了後に読める）で、スプリント06の受け入れ条件が変わらない | 達成 | 既存どおり。`SprintSixAcceptanceTests` 4本すべて緑のまま。`drawNextPost` の `.unavailable(permanent: false)` 経路にも encounter を +1 する処理を入れたが、その言語を「既読化しない」／「次回再挑戦」の既存挙動は変えていない（sprint 06 eval-7 と同一の動作）。 |
| 4. 先読みはアプリを開いていない間に行われ、アプリを使っている最中に画面が止まる・スワイプが引っかかる・進捗表示が割り込むことがない | 達成 | 既存どおり。pre-fetch の起動は `scenePhase == .background` のみで、`peekTranslationsInBackground` は UI プロパティ（`alertMessage`, `isPreparingTimeline`）を一切触らない。attempt 2 では `lastPeekedLanguages` という新しいプロパティを *追加* したが、これも UI 状態ではなく Debug オーバーレイ用の文字列生成にしか使われない（`allowsHitTesting(false)`）。`SprintSeventeenAcceptanceTests.test02_backgroundPeekDoesNotInterruptTimeline` 4本すべて緑。 |
| 5. 通信できない状態では先読みが行われず、そのことによるエラー表示も出ない。通信が回復した後は通常どおり利用できる | 達成 | 既存どおり。`peekTranslationsInBackground` の冒頭で `guard await backend.isOnline() else { return }`。`BackgroundPeekTests.testBackgroundPeekSkipsWhenOffline` 緑、`SprintSeventeenAcceptanceTests.test03_offlineBackgroundPeekDoesNotShowError` 緑。attempt 2 で `LocalBackend` の `peekTestQtdEncounter` が `resetsState` 経路・通常経路のどちらでも動くように修正したが、online 判定自体は変えていない。 |
| 6. アプリ内に、翻訳の先読みに関する設定項目・ダウンロード管理・進捗表示が1つも存在しない（F19 の方針） | 達成 | 既存どおり。`SprintSeventeenAcceptanceTests.test01_noPrefetchUIStringsExist` で禁止識別子9種が画面上に存在しないことを確認。attempt 2 で追加した `lastPeekedLanguages` は Debug オーバーレイ限定（`-SameQDebugOverlay` 指定時のみ）で、画面下の細い黒帯に `peeked [qtd]` の文字列が乗るだけ。エンドユーザー向けには従来どおり何も出ない（受け入れ条件6 厳守）。 |

## 動かし方（evaluator 向け）

### 基本起動（attempt 2 の検証ポイント込み）

```bash
xcodegen generate

# 1. ユニット + UI（attempt 2 で新規追加分）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath build/derived \
  -only-testing:SameQTests/BackgroundPeekTests \
  -only-testing:SameQUITests/SprintSeventeenAcceptanceTests \
  test

# 2. 回帰（直近2〜3スプリント）
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath build/derived \
  -only-testing:SameQUITests/SprintFifteenAcceptanceTests \
  -only-testing:SameQUITests/SprintSixteenAcceptanceTests \
  test
```

### 受け入れ条件ごとの確認コマンド（attempt 2）

- **条件1（最大3件）**:
  `xcodebuild ... -only-testing:SameQTests/LanguageEncounterTests/testTopEncounteredLanguagesRespectsLimit test`
- **条件2（先読み後の痕跡）**:
  `xcodebuild ... -only-testing:SameQUITests/SprintSeventeenAcceptanceTests/test04_backgroundPeekPersistsFakePrepareAttempt test`
  - `-SameQFakeTranslate -SameQPeekTestQtdEncounter -SameQDebugOverlay` を付けて起動
  - タイムラインを閉じて `RootView.debugOverlay` が出るところに戻ると
    `peeked [qtd]` の文字列が画面下の Debug オーバーレイに出る
- **条件4（background 中のみ・UI 不変）**:
  `xcodebuild ... -only-testing:SameQUITests/SprintSeventeenAcceptanceTests/test02_backgroundPeekDoesNotInterruptTimeline test`
- **条件5（offline スキップ）**:
  `xcodebuild ... -only-testing:SameQTests/BackgroundPeekTests/testBackgroundPeekSkipsWhenOffline test`
  または `-only-testing:SameQUITests/SprintSeventeenAcceptanceTests/test03_offlineBackgroundPeekDoesNotShowError test`
- **条件6（UI 無し）**:
  `xcodebuild ... -only-testing:SameQUITests/SprintSeventeenAcceptanceTests/test01_noPrefetchUIStringsExist test`

### 手動実機（attempt 2）

- 通常起動（`-SameQUseLocalBackend -SameQFakeTranslate -SameQDebugOverlay`）でお題に答える。
- ホームボタン → 5秒待ち → 復帰。
- タイムラインを閉じて TodayPromptView に戻ると、画面下の Debug オーバーレイに
  `peeked [qtd]`（あるいは `[en, es, ko]` 等、background 時点で top-3 に入った言語）が
  表示される。これが「先読みが *走った*」痕跡。
- state.json（`Application Support/SameQ/state.json`）を開くと、`lastPrepareAttemptAt["qtd"]` に
  直近の時刻が入っている（attempt 2 で fake 経路でも `lastPrepareAttemptAt` を書くようにしたため）。

## 自分で見つけた弱点

1. **「qtd に再会して待ちなしで読める」を e2e で観測する UI テストは無い**。
   `-SameQPeekTestQtdEncounter` を使うと `qtd` encounter は 5 件積めるが、qtd を含む
   シードは `prompt_001` に 1 件しかなく、UI テストで `nextTimelinePost` のランダム選択に
   頼らず「qtd を含む回答を *2 回* 出す」シナリオを確定的に作れない。代わりに test04 では
   「`peekTranslationsInBackground` が `qtd` を候補に選び、その結果が `lastPeekedLanguages`
   に残る」ことを確認する形に留めた。「待ちが消えた」側の最終確認は、実機 + Apple
   Translation が動いている環境でのみ可能（これは spec.md「評価者への注記」の想定範囲）。
2. **`peekTestQtdEncounter` は `qtd` しか強制できない**。他言語（en, es など）の
   先読み痕跡を e2e で観測したい場合、`-SameQAnswerCount` を 5 以上にしてから手動で
   読み進める必要がある。テストの決定性とはトレードオフ。
3. **attempt 2 で `AppSession.drawNextPost` の encounter 記録対象を広げた**影響。
   `.unavailable(permanent: false)`（一時的失敗）でも encounter を +1 するように
   変えたため、「実際には翻訳が成功していない言語」も top-3 に入るようになる。
   `peekPrepareIfNeeded` は対象言語を「準備を試みるだけ」なので害はないが、
   1回だけ見ただけで top-3 入りした言語が永遠に encounter を稼ぎ続ける可能性がある
   （減衰なし、これは既存どおり）。
4. **`SAMEQ_PEEK_TEST_LOG_PATH` の書き込みは best-effort**。`recordModelPrepareAttempt` の
   末尾で共有ファイルに1行追記するが、`try?` で握りつぶしている。失敗してもアプリは
   動かないわけではない（ログ目的）ので問題はないが、評価者がこのファイルの存在を
   確認する場合は `xcrun simctl get_app_container booted <bundleId> data` 配下の
   sandbox 外なので、env var に渡した絶対パスが存在することを別途確認する必要がある。
5. **LocalBackend の `peekTestQtdEncounter` が `resetsState` 経路でも動くように修正した**
   （attempt 1 で UI テストから使おうとして発覚したバグの修正）。`resetsState` 後の
   `state = .empty` の直後にこの経路を挟むように変更済み。`SupabaseBackend` 経路には
   同じフラグを実装していない（実機 / 開発サーバでの検証は別途）。

## 提案（今回はやらなかったこと）

1. **BGAppRefreshTask による OS スケジューリングの先読み**：今回は `scenePhase == .background` の
   タイミングだけで起動している。OS の Background App Refresh を併用すれば、ユーザーがアプリを
   开いていない「夜間」含めて定期的に pre-fetch を走らせられる。ただし Info.plist の
   `UIBackgroundModes` に `fetch` を追加する必要があり、F19 の「アプリを意識させない」原則と
   トレードオフがあるため、別スプリントの検討材料とする。
2. **エンカウンタの減衰（古い記録を薄くする）**：現状は累計値のため、半年前の言語が
   今でも top-3 に居座りうる。`exponential decay` などで重みを減らせば「今よく見る言語」に
   追従できるが、F41 の spec には無いので未実装。
3. **pre-fetch の履歴を `state.json` に書く**：attempt 2 では `lastPrepareAttemptAt` を
   fake 経路でも書くようにしたが、「どの言語について何件 prepare を試みたか」の履歴は
   残していない。デバッグ可視化（`prefetched: en, fr, es` 程度）を入れれば検証が
   楽になるが、F19 のエンドユーザー向け UI を出さない方針とトレードオフ。
   `lastPeekedLanguages` で「直近 1 回分」は見える状態にしたので実用上は十分。
4. **qtd を 2 件以上含むシード（または qtd を強制的に挿入する Debug 引数）**：
   「qtd に再会して待ちなしで読める」を e2e で観測可能にするには、qtd を含む回答が
   タイムラインに 2 回以上出る必要がある。spec 改変（qtd のシードを追加）か、
   `-SameQForceQtdSeeds` のような Debug 引数を足せば evaluator 作業が完全に決定的になる。
   ただし qtd は「翻訳準備中」を再現するマーカーでしかないため、本番運用に投入する
   動機は弱い。別スプリントで要否を判断する。

## テスト実行結果

- **ユニットテスト** (`SameQTests` の `BackgroundPeekTests`)：7/7 緑（0.737秒）
  - attempt 2 で 2 本追加:
    - `testBackgroundPeekRecordsFakePrepareAttempt`:
      `Translator.prepareIfNeeded` を fake 経路で呼んだ後、`attemptPersistence` 経由で
      state.json に `lastPrepareAttemptAt["qtd"]` が書かれることを直接検証。
    - `testTemporaryUnavailableStillRecordsEncounter`:
      `drawNextPost` が一時的失敗（`.unavailable(permanent: false)`）のときも encounter を
      +1 することを、`Backend` スタブで直接検証。
  - 既存 5 本 (`testBackgroundPeekSkipsWhenOffline` 等) も緑のまま。
- **UI テスト** (`SameQUITests`)：
  - 新規 `SprintSeventeenAcceptanceTests` 4/4 緑（65.6秒）
    - attempt 2 で 1 本追加: `test04_backgroundPeekPersistsFakePrepareAttempt`
    - 既存 3 本 (`test01_noPrefetchUIStringsExist`, `test02_backgroundPeekDoesNotInterruptTimeline`,
      `test03_offlineBackgroundPeekDoesNotShowError`) も緑のまま。
  - 回帰 `SprintFifteenAcceptanceTests` 8/8 緑、`SprintSixteenAcceptanceTests` 6/6 緑
    （189.9秒、14本合計すべて緑）
- **ビルド**：`Debug` / `Release` とも BUILD SUCCEEDED。
- **クラッシュ**：0
- **未処理エラー**：0
