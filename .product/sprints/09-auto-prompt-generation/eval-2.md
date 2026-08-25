# スプリント 09 評価（attempt 2） — 不合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 5/6（条件1が本番相当の経路で未達。理由は下記） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理エラー0（検証した範囲） | 0 | ✓ |
| 3 データ整合性 | discarded件数・answers件数などは再起動をまたいで保持。schemaVersion据え置きで後方互換 | 100% | ✓ |
| 4 回帰 | 14/14（SprintOne 5件・SprintTwo 5件・SprintSix 4件） | 100% | ✓ |
| 5 使用性 | 4（オンボーディング〜今日の画面は迷わない。ただし致命的機能欠陥のため参考値） | 3以上 | ✓（参考） |

**総合判定: 不合格**（基準1が満たされていないため、他が良好でも不合格）

## 検証環境
- iPhone 17 シミュレータ（UDID `12050FBD-587B-4910-8812-696BB91BE051`, iOS 26.5）と Eval09（UDID `3CE33B6D-B369-4BC3-A029-87AC7B0619F4`）を使用
- ビルド: `xcodegen generate` 実行後、`xcodebuild build-for-testing` で新規ビルド（DerivedData `SameQ-gtdxwtlwcpwekjbksobzrscesrwg`）
- 検証時刻: 2026-08-25 16:20〜16:40 JST
- 検証内容:
  1. `PromptGenerationTests`（データ層ユニット、attempt2 で追加された2本を含む）単独実行、20/20 成功
  2. `SprintNineAcceptanceTests`（UI）単独実行、7/7 成功
  3. **本番相当の経路**（シードあり・`-SameQSkipSeed`/`-SameQSeedOnly` なし・`scenario=live`）で「同じインストールのまま日をまたいでアプリを開く」を、evaluator が一時 UI テスト `EvalTempSprintNineRealWorldTests.swift` を追加して 0h/24h/48h/60h/84h/115h/120h/144h/168h の9地点で検証（`/tmp/sq_eval2_realworld2.log`）
  4. 同じ offset（48h、dead zone 内）で2プロセスを独立起動し世界共通性を確認する一時テスト `EvalTempSprintNineWorldCommonDeadZoneTests.swift` を追加実行
  5. 回帰確認: `SprintOneAcceptanceTests`（5件）/ `SprintTwoAcceptanceTests`（5件）/ `SprintSixAcceptanceTests`（4件）を実行、14/14 成功
  6. 検証後、両方の一時テストファイルを削除し `xcodegen generate` を再実行。`git status --porcelain` でリポジトリに変更が残っていないことを確認済み（pbxproj の空白差分のみ発生したため `git checkout --` で復元）

## 受け入れ条件ごとの結果

1. **「1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される」→ ✗ 未達**（詳細は下記「不合格の原因」）
2. 「同じ時刻に別のアカウント／別の端末で開いても、表示されるお題は同一のもの」→ ✓ 達成。auto-gen 経路（`SprintNineAcceptanceTests.test05`）に加え、eval が発見した「dead zone」内（シード prompt_002 のみで運用されている期間）でも同一 offset の2プロセスが同じテキストを表示することを確認（`/tmp/sq_eval2_worldcommon_deadzone.log`）
3. 「生成が失敗した日でも必ず何らかのお題が有効になり…」→ ✓ 達成。今回の多地点検証（0h〜168h）を通じて一度も「お題待ち」画面に陥らなかった
4. 「安全条件に違反する候補は採用されず、破棄された記録が残る」→ ✓ 達成（機構）。attempt1 から変わらず、ユニットテストで担保。実運用での発火確認手段が無い点は attempt1 から変わらず（評価対象外として扱う）
5. 「短く答えられ、特定文化に依存せず、面白い形式」→ ✓ 達成。dead zone 通過後に実際に表示された自動生成お題（「もし一日だけ、どこか知らない街を歩けるとしたら何を持って歩きますか？」等）を目視確認、既存シードと同種の問いかけで妥当
6. 「有効期間24〜36時間、2つ同時に表示されない」→ ✓ 達成。9地点すべてで同時に2件表示される事象は観測されなかった

## 不合格の原因（これを直せば通る）

### [1] `SeedCatalog.startDates` の `.live` 分岐（attempt2 の修正）は、eval-1 で指摘された「本番経路で自動生成が一度も発火しない」バグを直したのではなく、発火開始を約4.7日後（`liveAnchor + 112h`）まで先送りしただけ。今日（検証時点の現在時刻）からその約4.7日間は、`PromptGenerator` による真の自動生成が一度も走らず、同梱シードの2件（`prompt_001`／`prompt_002`）を行ったり来たりするだけの状態になる

- **再現手順**:
  1. シミュレータへアプリを新規インストール
  2. `-SameQResetState -SameQDebugOverlay` のみで起動（本番相当）→ オンボーディング完了 → 今日のお題画面に到達
  3. アプリを terminate（同じインストールのまま）
  4. `-SameQResetState` を付けずに `-SameQDebugOverlay -SameQTimeOffsetMinutes <N>` で再起動し、お題文とデバッグオーバーレイの `prompt.id` を記録
  5. N を 1440（24h）→ 2880（48h）→ 3600（60h）→ 5040（84h）→ 6900（115h）→ 7200（120h）→ 8640（144h）→ 10080（168h）と進めながら手順3〜4を繰り返す
- **期待**: spec.md 246行「1日1回、新しいお題が自動で作られ、翌日にアプリを開くと前日と異なるお題が表示される」。F26の目的（「運用者が毎日手で用意しなくても、世界共通のお題が毎日1つ生まれる状態にする」）に照らせば、日々の切り替わりが `PromptGenerator`（真の自動生成）によって駆動されているはず。
- **実際**（`/tmp/sq_eval2_realworld2.log` の実測、`EVALLOG` 行そのまま）:
  ```
  day0(offset=0)      prompt_001  今日、思わず笑ってしまったことは何ですか？
  day1(offset=1440)   prompt_002  最近、誰かに言われてうれしかった一言は何ですか？
  day2(offset=2880)   prompt_002  最近、誰かに言われてうれしかった一言は何ですか？   ← day1と同一
  day3(offset=3600)   prompt_001  今日、思わず笑ってしまったことは何ですか？        ← day0と同一（再度prompt_001に「戻る」）
  day4(offset=5040)   prompt_002  最近、誰かに言われてうれしかった一言は何ですか？   ← day1/day2と同一
  day5(offset=6900)   prompt_20260830  もし一日だけ、どこか知らない街を…           ← ここで初めて真の自動生成
  day6(offset=7200)   prompt_20260830  （day5と同一UTC暦日なので正常）
  day7(offset=8640)   prompt_20260831  もし一日だけ、すべての音を…                ← 翌日、別の自動生成お題
  day8(offset=10080)  prompt_20260901  この一年で、はじめて名前を覚えた人は…        ← さらに翌日、別の自動生成お題
  ```
  - `prompt_001`/`prompt_002` の ID から `prompt_yyyyMMdd` の auto-gen ID に切り替わるのは offset 84h〜115h の間（`liveAnchor + 112h` ≒ 2026-08-29 18:14 UTC）。**検証時点（2026-08-25）から数えて約4.7日間は、実機で「1日おきに開く」を繰り返しても、真の自動生成は一度も観測できない。**
  - しかもその4.7日間の内部でも、day1(24h)とday2(48h)で**同一のお題**が連続表示される（`prompt_002` の 28h という有効期間の性質上、24h間隔の起動では時々同じお題が続くこと自体は F09 の設計（24〜36h、時差吸収）に由来し、Sprint02 で既に許容されている挙動と考えられるためこれ単体は指摘事項としない。ただしこの重複が「真の自動生成が起きていない期間」でのみ観測された点は、条件1の本質的な未達を補強する material）。
  - dead zone を抜けた後（offset ≥ 115h 相当）は、`prompt_20260830 → prompt_20260831 → prompt_20260901` と正しく毎日別の自動生成お題に切り替わっており、`PromptGenerator` 自体のロジックは機能している。**問題は `SeedCatalog` との統合部分に依然として残っている**。
- **根拠（コード、推測として記載）**:
  - `SameQ/Backend/SeedCatalog.swift` の `startDates(...)`（325〜375行）の `.live` 分岐は、`elapsed = reference.timeIntervalSince(liveAnchor)` が `coverage`（56h = 28h×2）を超えたときに `firstStart = liveAnchor.addingTimeInterval(coverage)` という**固定の絶対日時**を設定する。これは self-review.md が「seed prompt 2件を全て reference より前に置く」と説明している設計だが、実際には `firstStart` が `reference` に追従しない固定値であるため、`elapsed` が `coverage` をわずかに超えた直後（例: 60h、84h時点）では、`firstStart`（= `liveAnchor+56h`）から始まる新しい28h×2区間（合計112h分）にまだ `reference` が収まってしまい、**シードの2件が「再アンカー」されて再度 active になる**。真に両方とも過去になる（＝`PromptGenerator` へフォールスルーする）のは `reference > liveAnchor + coverage + coverage`（= `liveAnchor + 112h`）を満たしたときのみ。
  - self-review.md 121行の「弱点1」は「coverage(56h)経過後（≒2026-08-27 10:14 UTC）には必ず auto-gen 経路に切り替わる」と説明しているが、この記述は実測と food違う。実際に auto-gen 経路に切り替わるのは `coverage` の**2倍**（112h ≒ 2026-08-29 18:14 UTC）経過後であり、self-review 自身の見積もりより更に2.3日遅い。
  - self-review.md の「手動実機検証」（35行目）は Day1（+0分）と Day2（+1440分=24h）の2点だけを確認して「prompt_001→prompt_002 に変わった」ことを合格の根拠にしているが、**Day3（+48h）でも同じ prompt_002 のままである**ことや、**dead zoneが約4.7日続く**ことには気づいていない（気づいていれば「自分で見つけた弱点」に記載されたはずだが、記載が無い）。

### 影響

`PromptGenerator` 自体（決定性・破棄記録・フォールバック・重複なし・dead zone通過後の日次切り替え）は正しく実装されている（day5〜day8 の結果より確認）。問題は attempt1 から一貫して **`SeedCatalog` と `PromptGenerator` の統合部分**にあり、attempt2 の修正は「起動のたびに動的再構築されて永久に発火しない」バグを「約4.7日間は発火せず、その後は正しく毎日発火する」バグに変えただけである。検証時点（2026-08-25）を基準にすると、この4.7日間は**まさに現在から近い将来のすべての利用期間**を覆っており、実運用上「毎日運用の手を介さずに新しいお題を受け取れる」というスプリント09の目的（未完了時にユーザーができること）を満たさない。

## 回帰確認（3件以上の抜き取り、実施14件）
- `SprintOneAcceptanceTests`（コア体験）5件 — 全件成功
- `SprintTwoAcceptanceTests`（お題ライフサイクル）5件 — 全件成功
- `SprintSixAcceptanceTests`（翻訳）4件 — 全件成功

いずれも今回のスプリントが触った `SeedCatalog`/`LocalBackend`/`PersistedState` に近い領域、または前回 attempt1 の評価で選んだのと同じ領域を優先して選定した。回帰は問題なし。

## 改善提案（合否には影響しない）
- `SeedCatalog.startDates` の `.live` 分岐で、`coverage` を超えた場合に「シードを1周だけ再アンカーする」のではなく、即座に `activePrompt(at:)` が nil になるよう `firstStart` の設計を見直す（例: シードは常に `liveAnchor` を起点とした最初の56hのみに固定し、それ以降は一切シードを配置しない）。
- `liveAnchor` のようなハードコードされた絶対日時に依存せず、`PersistedState` に「このインストールの初回起動時刻」を保存し、そこからの相対時間でシードのカバレッジを判定する設計にすると、いつリリースしても再現性のある挙動になる（self-review 自身も同じ提案を「提案（今回はやらなかったこと）」に記載済み）。
- self-review.md の「手動実機検証」は最低3〜4地点（0h/24h/48h/72h程度）を確認する運用にすると、今回のような「2点だけ確認して見落とす」パターンを防げる。

## 評価できなかったもの
- 受け入れ条件4（破棄記録）の実機での発火確認: 候補プールが全件安全なため、UIから発火させる手段が無く、ユニットテストの結果を根拠にするに留めた（attempt1から変わらず）。
- dead zone を抜けた後（offset > 168h）、自動生成が「毎日」切り替わり続けることの長期的な確認（day7→day8の1日分の切り替わりのみ確認。数週間分は未検証）。
