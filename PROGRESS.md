# PROGRESS

## 再開手順（新しいセッションで戻ってきた場合）
1. このファイルをまず読む。調査・仕様の読み直しはしない。
2. 下の「作業単位チェックリスト」で **最初の未完了項目（[ ]）** を探す。
3. 「現在の状態」の該当行にある関連ファイル・IDを見て、そこから続ける。
4. 各作業単位が完了したら、このファイルの該当チェックボックスと「現在の状態」を**即座に**更新してコミットする。

## メタ情報
| 項目 | 値 |
|---|---|
| アプリ名 | SameQ |
| ローカルリポジトリ | `/Users/nakagawakeita/Products/iOSApp/SameQ` |
| GitHubリポジトリ | `nakakei6439/SameQ`（Private） |
| 製品仕様書 | [`.product/spec.md`](.product/spec.md)（機能一覧34件、スプリント11本） |
| 開発ハーネス | planner → generator → evaluator |

## バックログ（新規スコープ、未着手）

### アプリ自体のUIローカライズ（2026-08-18、ユーザー確定）
現状、Apple Translation Frameworkで翻訳しているのは**投稿本文とお題（content）のみ**（F18〜F22）。
アプリ自体のUI文言（ボタン・見出し・オンボーディングの文章・設定画面など、`SameQ/Feature/` 配下の
SwiftUI Viewにハードコードされた日本語文字列）は一切ローカライズされておらず、端末言語を変えても
常に日本語のまま表示される。ユーザーが実機検証中にこれを確認し、「世界中の誰かとつながるアプリ」
というコンセプト上、UI自体も端末言語に対応させたいとの意向。

- **方針**: 対応する（推奨案として採用）。ただし今すぐではなく、**新規スコープとして後で対応**する
- **未確定**: どのスプリントに割り当てるか（既存11スプリントの後、新しいスプリント12として追加するか、
  スプリント07以降のどこかに差し込むか）はplannerの判断が必要。対応方針（String Catalog / 
  `Localizable.strings` の導入、対応言語の範囲）も未検討
- **影響範囲の見立て**: `SameQ/Feature/Onboarding`, `Today`, `Timeline`, `Waiting`, `Banned`, 
  `Settings` 配下の全Viewが対象になる見込み。`Translator.targetLanguage`（起動時に読む端末言語）は
  既にあるので、UI文字列の切り替えにも同じ言語判定を使い回せる可能性がある

## 現在の状態
- **フェーズ**: スプリント06（投稿本文とお題の自動翻訳）**attempt 3 実装完了・シミュレータ全件成功 → 実機での最終確認が保留中**（2026-08-19、ユーザーが外出中で実機のロックを解除できないため。詳細は「スプリント06 attempt 3」節）
- **並行タスク**: ユーザー確定済みのUI変更3点（お題を世界タイムラインでも常時表示／✕ボタン削除・操作はスワイプ＋いいねのみ／いいねボタンの位置・見た目の調整）。スプリント06とは独立したタイムライン画面の変更（詳細は「並行タスク: タイムラインUI調整」節）。2026-08-19、evaluator 検証で合格・完了（受け入れ条件3/3、クラッシュ0、データ整合性OK、回帰90/90＋抜き取り6件、使用性4）。合否に影響しない改善提案4件は [`eval-1.md`](.product/sprints/timeline-ui-adjustment/eval-1.md) に記載。**同日、優先度高の改善提案[A][C]をスプリント外の小さな修正として対応済み**（カード外の余白でもスワイプが効くよう `.contentShape(Rectangle())` を追加、`SprintFiveAcceptanceTests` の検証漏れ2箇所を修正）。フルテスト90/90成功。**同日、evaluator の再確認でも合格**（前回の無反応座標 y=0.25 / y=0.68 が両方とも反応、余白スワイプのみで読み切り到達、いいね誤爆0、回帰90/90＋抜き取り4件、使用性4）。残った改善提案は [`eval-2.md`](.product/sprints/timeline-ui-adjustment/eval-2.md) に記載。**本タスクは完了**。
- **スプリント06 attempt 1 の実装内容（generator、2026-08-18）**: Apple Translation Framework のみを使い（外部翻訳API・フォールバックは無し、サーバーへ本文を送らない）投稿本文とお題本文を端末言語へ変換して表示。`TranslationSession` は `.translationTask` からしか作れないため、`RootView` の背景に常駐させた不可視の `TranslationHostView` がセッションを供給し、`Translator`（`SameQ/Backend/Translator.swift`）が要求をさばく。お題・投稿とも翻訳が確定するまで表示せず「準備中…」を出すことで「ちらつき」を防止（F21）。同梱シードに `promptLanguage` を追加し、多言語投稿での翻訳確認ができるようにした。この attempt 1 は evaluator の検証で受け入れ条件3/7の不合格となり（詳細下記）、attempt 2 で4点を修正した。
- **スプリント06 attempt 2 の修正内容（generator、2026-08-18）**: evaluatorの指摘4点すべてに対応。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 2」を参照。
  1. **[最重要] 翻訳キューの固着を解消**。待ち行列ロジックを `SessionRequestQueue<Session>`（新規、Translation非依存のジェネリック型）に切り出し、一度取得できたセッションは言語ペアごとにキャッシュして2回目以降は新規要求を出さない設計に変更。同じ値の `Configuration` を再代入する経路自体を無くした。保険として `invalidate()` の呼び出しと45秒タイムアウト（一時的失敗として扱う）も追加。ユニット5本（`SessionRequestQueueTests`）で `TranslationSession` を使わずロジックを直接検証。
  2. **シミュレータでの検証手段としてDebug限定の疑似翻訳モード `-SameQFakeTranslate` を追加**。有効時は `Translator.translate` が実際の `TranslationSession` を使わず `[<言語コード>] <原文>` の決定的な変換を返す。本番経路（実際の `TranslationSession`）はそのまま残り、疑似モードは`translate()`冒頭で分岐するのみ。ユニット9本（`TranslatorFakeModeTests` 6・`AppSessionTranslationTests` 3）＋UIテスト2本（`SprintSixAcceptanceTests`）で、キューが固着しないこと・非対応言語がスキップされること・お題が確定表示に変わることを確認。
  3. **お題が日本語以外の端末言語で原文のままだった件**: attempt 1での症状は主にバグ2（シミュレータでApple Translationが全ペア失敗）が直接原因。バグ1の修正でその経路は解消。設計判断として、翻訳できない場合は引き続き原文へフォールバック（お題は常に1つだけ有効でスキップの代替が無いため。理由はself-review.md参照）。
  4. **翻訳スキップ時に恒久的に既読化される件を解消**。`Translator.translate` の戻り値を `TranslationOutcome`（`.text` / `.unavailable(permanent:)`）に変更し、恒久的な非対応と一時的な失敗を区別。`Backend.nextTimelinePost` に `excluding`（巡回内だけの一時除外）と `autoMarkViewed` を追加し、一時的失敗は既読にせず次回・次の巡回で再挑戦できるようにした。ユニット5本（`TranslationSkipTests`）で確認。既存呼び出し元向けに後方互換のデフォルト引数版も用意。
  - **フルテスト実行結果（他プロセス非併走の単独実行で確認済み）**: ユニット56本＋UIテスト33本、**合計89件すべて成功**。
  - **正直な弱点（self-review.mdより）**: **実機検証は今回一切できていない**（ユーザーが外出中のためスコープ外）。`SessionRequestQueue` のロジック自体はフレームワーク非依存でテスト済みだが、実際の `TranslationSession.translate(_:)` がこの待ち行列と正しく協調するかは実機でしか確認できない。次回evaluatorが実機で確認できる際に、①同一言語ペア連続でも固まらないか、②翻訳モデル未取得時の初回表示、③機内モードでの翻訳表示、④お題が実際の翻訳で表示されるか、を改めて確認すること。
- **スプリント06 attempt 2 の評価結果（evaluator、2026-08-18）**: **不合格**。受け入れ条件 3/7。詳細は [`eval-2.md`](.product/sprints/06-translation/eval-2.md)。
  - **実機（iPhone 17 Pro Max / ja-JP）で本物の Apple Translation が動くこと自体は確認できた**（お題も投稿も実際に翻訳された文章で表示される）。シミュレータでは `-SameQFakeTranslate` により ja/en/ko の3言語で30件を通し完走・ちらつき0・`zxx` は0回表示・翻訳関連UIは1つも無い、を確認。
  - **[最重要・要修正] 実機ではタイムラインが2〜3件目で無言のまま固まり、二度と進まない**（3回中3回再現）。原因は attempt 2 で入れた「言語ペアごとに `TranslationSession` をキャッシュして使い回す」設計そのもの。`configuration` を別の言語ペアへ差し替えた時点で前の `.translationTask` は畳まれ、そこで得たセッションは無効になる。無効なセッションで `translate(_:)` を呼ぶとフレームワークが `Attempted to use TranslationSession after the view it was attached to has disappeared` の致命的エラーを出す（実機プローブで直接確認）。アプリ上では `translate(_:)` が返らず `timelineContent` が `.loading` のまま止まり、タイムライン画面自体が消える。`SessionRequestQueue` の45秒タイムアウトは**セッション取得にしか掛かっていない**ため保険にならない。
  - **[要修正] `invalidate()` の保険が効いていない**。`configuration?.invalidate()` の直後に同値の `Configuration` で上書きしているため `.translationTask` は再実行されず、一度タイムアウトした言語はそのプロセスの間ずっと復帰できない（`fireCount` で実測）。
  - attempt 1 の指摘のうち、**2（シミュレータでの検証手段）・3（お題が原文のまま）・4（スキップした回答の既読化）は解消を確認**。一時的な失敗が既読にならないことは `state.json` を直接読んで検証済み。回帰5/5、データ整合性OK（schemaVersion 4、翻訳結果は永続化されない）。使用性2。
- **スプリント06 attempt 3 の修正内容（generator、2026-08-18）**: eval-2.mdの指摘[1][2]に対応。①`SessionRequestQueue` からセッションキャッシュを撤去し、取得したセッションは `.translationTask` のクロージャが生きているスコープの中で `session.translate(_:)` まで完結させる設計に変更（セッションを外へ持ち出す経路を型的に廃止）。`Configuration` の差し替えも「新規インスタンス」ではなく「既存インスタンスへの `invalidate()` + `source`/`target` 書き換え」に修正（新規インスタンス差し替えだとSwiftUIが再実行を検知できないことがattempt 2の直接原因だった）。②`session.translate(_:)` 自体にもタイムアウトを追加（`withTaskGroup` で競走、タイムアウト時は `session.cancel()` で中断）。シミュレータでのフルテストスイート（`SameQTests` + `SameQUITests`）**90/90 全件成功**。実機向けビルド・インストールも成功。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 3」。
- **次にやること**: **スプリント06 attempt 3 の実機での最終確認（evaluator）**。`-SameQFakeTranslate` を付けずに実機（iPhone 17 Pro Max、UDID `B7121EA8-8AED-5E66-B696-511BFFC729E2`）でタイムラインを読み切りまで通し、attempt 2で見つかった「2〜3件目で固まる」不具合が再発しないことを確認する。**2026-08-19時点で、ユーザーが仕事に出かけておりスマホを使えないため保留中。** ユーザーが戻り実機のロックを解除できるようになったら再開すること。それまでの間は「並行タスク: タイムラインUI調整」を進める。
- **スプリント05（BAN・投稿頻度制限・スパム対策）は合格済み（attempt 2、2026-08-18）**。1お題1投稿の担保、直近投稿と同一本文の連投拒否、空白・改行のみ／同一文字の過剰な繰り返しの拒否、いいね・通報の連打制限、BAN状態のアカウント締め出し、BANされた投稿者の非表示化を実装。受け入れ条件6/6・回帰10/10。詳細は [`self-review.md`](.product/sprints/05-ban-spam/self-review.md) / [`eval-2.md`](.product/sprints/05-ban-spam/eval-2.md)。
  - スプリント05の評価で挙がった改善提案（合否には影響しないが、着手時に踏まえる）:
    - **[A] 空白だけを入力しているとき、文字数カウンタが「8/140」と出る**（拒否メッセージは出るようになったので実害は消えたが、押す前は空欄に見えるのに入力済みに見える矛盾が残る）。trim 後の文字数を数える等。
    - **[B] `Yessssssss` のような正常な英語表現が繰り返し判定に引っかかる**（`PostValidator` の閾値が伸ばし表現を弾く）。文字種で閾値を変える／連続同一文字の最大ラン長で判定する等。
    - **[C] 連打制限がプロセス内メモリのみで、アプリを再起動すると解除される**（Supabase 接続時にサーバー側へ移す前提）。
    - **[D] 同一文面の連投拒否が「直近1件」との比較のみ**（2つ前の投稿と同じ文面は通る）。
  - スプリント04の評価で挙がった改善提案（合否には影響しないが、着手時に踏まえる）:
    - **[1] 読み切り・0件の状態でも ⋯ ボタンがアクセシビリティツリーに残る**（見た目は非表示・タップ不可だがラベルが読み上げられる）。`.accessibilityHidden(true)` か条件付き生成に。
    - **[2] ブロック解除で「以前読んだ回答」も未読に戻る**。ブロック時に既読を消すのではなく、ブロック中は既読判定から外す形にすると副作用が消える。
    - **[3] ブロック一覧へ行くにはタイムラインを閉じる必要がある**。タイムラインの ⋯ の中に「ブロック中の人」への導線があると往復が減る。
    - **[4] 通報・ブロックの失敗時にタイムラインでは何も出ない**（`fullScreenCover` の上にメッセージを出す置き場所が無い）。Supabase 接続前に用意すること。
    - **[5] 操作シート／ブロック確認が `.medium` 固定で下半分が空白**、**[6] 通報「その他」に自由記述が無い**。
  - スプリント03の評価で挙がった改善提案の扱い:
    - **[A] いいねが押した直後以外はユーザーから見えなくなった** — 未対応（仕様側の判断待ち。planner 案件）。
    - **[B] `state.json` の `schemaVersion` が移行後も 1 のまま** — **今回対応**。schemaVersion 3 を足す都合で保存時に `currentSchemaVersion` へ揃えるようにした（`LocalStore.save`）。
    - **[C] 読み切り画面に「引き直す」導線が無い** — 未対応（スプリント03で「再表示の導線は作らない」と決めたため）。
- **再開に必要な情報**:
  - Xcodeプロジェクトは `SameQ.xcodeproj`（`project.yml` から XcodeGen で生成。生成物もコミット済みなので `open SameQ.xcodeproj` で即ビルドできる）。
  - 自動確認は `xcodebuild -project SameQ.xcodeproj -scheme SameQ -destination 'platform=iOS Simulator,name=iPhone 17' test`（`SameQTests` 56本 ＋ `SameQUITests` 33本）。
  - 初回設定からやり直すには、アプリを削除するか Debug ビルドに起動引数 `-SameQResetState` を付ける。
  - **お題の日程を切り替える起動引数（Debug 限定）**: `-SameQScenario live|expiring|expired|upcoming`、`-SameQExpirySeconds <秒>`、`-SameQGapSeconds <秒>`、`-SameQTimeOffsetMinutes <分>`、`-SameQDebugOverlay`。実時間で28時間待たずに切り替わりを確認するためのもの。
  - **タイムラインの取得ルールと既読を検証する起動引数（Debug 限定・スプリント03で追加）**: `-SameQAnswerCount <件数>`（自分以外の回答を 0 / 1 / 120 件などに固定）、`-SameQResetViewed`（既読の記録だけ消す）。詳細は README と 03 の self-review.md。
  - **Debug オーバーレイに `reported` / `blocked` を追加**（スプリント04）。`-SameQDebugOverlay` で通報数・ブロック中の人数が数字で追える。
  - **BAN・連打制限を検証する起動引数（Debug 限定・スプリント05で追加）**: `-SameQBanned`（自分のアカウントをBAN状態にして起動）、`-SameQRateLimitTestMode`（いいね・通報の連打制限の閾値を短時間で確認できる値に縮める）。詳細は 05 の self-review.md。
- **スプリント05で踏まえたこと**:
  1. タイムラインの候補の絞り込みは `LocalBackend.candidates(promptID:at:)`（ブロック・通報を適用）と `visibleOthers(promptID:at:)`（適用前）に分かれている。BAN外の条件は `visibleOthers` 側に足した（`.empty`/`.exhausted` の判定にも自動的に効く）。
  2. いいね・通報の連打制限はプロセス内メモリだけ（`PersistedState` に永続化していない）。再起動すればリセットされる。詳細と判断理由は 05 の self-review.md「自分で見つけた弱点」。
  3. `TodayPromptView` と `TimelineView` はどちらも同じ `session.alertMessage` を見ているが、`fullScreenCover` 使用時は両方が同時にマウントされているため、`isTimelinePresented` でどちらか一方だけがアラートを出すようにゲートしてある。今後アラートを追加する画面がある場合はこの点に注意すること（同じ `alertMessage` を複数の `.alert` で同時に `isPresented: true` にすると、片方の提示に巻き込まれてもう片方の `fullScreenCover`/`sheet` ごと閉じることがある）。
  4. BANの判定は起動引数 `-SameQBanned` のみで、実データには紐づいていない（置いた前提10のとおり、本来はサーバー側の状態）。Supabase接続時に `users.status` を見る形へ差し替えること。
  5. BANされた投稿者の同梱シード拠出は、既存の22件の**後ろ**に1件追加する形にした（`-SameQAnswerCount` を使う既存テストの件数に影響しないため）。大量件数の検証用に機械生成する回答（`SeedCatalog.resize`）にはBANを混ぜていない。
- **スプリント04 で踏まえたこと（引き続き有効）**:
  1. タイムラインの候補の絞り込みは `LocalBackend.candidates(promptID:at:)` に集約してある。スプリント04の「ブロック外／通報済み以外」はここに条件を足した。
  2. スプリント03で **スプリント01の受け入れ条件8（いいねの押下状態が開き直しても残る）の検証手順を変更した**。F12（既読）を入れると一度出した回答は再表示されないため、`-SameQResetViewed` を挟んで同じ回答を出し直す手順にしている。いいねの永続そのものは維持（ユニットテスト `testLikesSurviveRelaunchIndependentlyOfViewedRecords` でも担保）。
  3. 既読は「画面に出した瞬間」に記録する（読み終えてからではない）。閉じて開き直すと必ず別の回答が出る。
  4. スプリント01評価の改善提案3件（キーボードが「投稿する」を半分隠す／投稿ボタンが押せない理由が出ない／`state.json` 破損時にアカウントが黙って消える）は**まだ未対応**。詳細は 01 の eval-1.md。
  5. スプリント02評価の改善提案は [C]（`-SameQDebugOverlay` が最下部のテキストに重なる）のみスプリント03で解消（`safeAreaInset` に変更）。[A] 期限切れの瞬間にタイムラインが無言で閉じる／[B] 入力中に期限が切れると書きかけが消える、は**未対応**。
  6. お題の切り替え判定は端末時計 ＋ 1秒間隔のポーリング。サーバー時刻に合わせるのは Supabase 接続時の課題。
  7. 期限切れ投稿が「他ユーザーから見えない」ことは、`LocalBackend`（単一端末）のため UI では確認できていない。データ層とユニットテストで代替確認済み。Supabase 接続時に実端末2台で再確認すること。
  8. 既読はローカルの `state.json`（`viewedPostIDs`）にしか無い。端末を替えると引き継がれない（サーバー側 `viewed_posts` テーブルは定義済み・未使用）。

---

## 作業単位チェックリスト

### 0. リポジトリ初期化
- [x] `git init` / `.gitignore`・`README.md` 作成
- [x] 初回コミット（`.product/spec.md`, `PROGRESS.md`, `README.md`, `.gitignore`）— commit `52c93f2`
- [x] GitHub Private リポジトリ `nakakei6439/SameQ` 作成・push — https://github.com/nakakei6439/SameQ

### スプリント01: コア体験（設定→お題→投稿→世界タイムライン→いいね）
含む機能: F01, F02, F03, F04, F05, F06, F07
- [x] 実装（generator）— 2026-08-17
- [x] 評価（evaluator）— 2026-08-17 **合格**（attempt 1）。受け入れ条件8/8・クラッシュ0・データ整合性OK。[`eval-1.md`](.product/sprints/01-core-experience/eval-1.md)

### スプリント02: お題のライフサイクルと投稿の寿命
含む機能: F08, F09, F10
- [x] 実装（generator）— 2026-08-17。お題待ち画面、開始/終了時刻による画面切り替え、投稿の表示期限、期限切れ回答の除外、履歴導線を作らないことの担保。[`plan.md`](.product/sprints/02-prompt-lifecycle/plan.md) / [`self-review.md`](.product/sprints/02-prompt-lifecycle/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・クラッシュ0・データ整合性OK・回帰5/5・使用性4。[`eval-1.md`](.product/sprints/02-prompt-lifecycle/eval-1.md)

### スプリント03: タイムラインの取得ルールと既読管理
含む機能: F11, F12
- [x] 実装（generator）— 2026-08-18。未読優先のランダム1件取得、既読の記録と永続、読み切り／0件の明示表示、前へ戻る操作を持たないことの担保、検証用の起動引数（`-SameQAnswerCount` / `-SameQResetViewed`）。[`plan.md`](.product/sprints/03-timeline-rules/plan.md) / [`self-review.md`](.product/sprints/03-timeline-rules/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・0件/1件/120件の3ケース確認・再起動後も既読が残る・クラッシュ0・データ整合性OK（旧 schemaVersion 1 からの移行も確認）・回帰8/8・使用性4。[`eval-1.md`](.product/sprints/03-timeline-rules/eval-1.md)

### スプリント04: 通報とブロック
含む機能: F13, F14, F15
- [x] 実装（generator）— 2026-08-18。タイムライン ⋯ からの通報（理由7種→送信→完了表示）とブロック（確認→完了表示）、通報後の即時非表示と永続、ブロックの永続とお題をまたいだ持続、設定画面のブロック一覧と解除、`candidates()` への条件追加、schemaVersion 3、Debug オーバーレイに `reported` / `blocked` を追加。ユニット9本＋UIテスト7本を追加（合計 25 ＋ 24）。[`plan.md`](.product/sprints/04-report-block/plan.md) / [`self-review.md`](.product/sprints/04-report-block/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 1）。受け入れ条件6/6・注記2件（ブロック一覧の情報漏れ無し／最後の1件をブロックしても `timeline.exhausted` へ正しく落ちる）・お題をまたいだブロックの持続・クラッシュ0・データ整合性OK（`reports` / `blockedAuthors` を直接確認）・回帰5/5・使用性4。[`eval-1.md`](.product/sprints/04-report-block/eval-1.md)

### スプリント05: BAN・投稿頻度制限・スパム対策
含む機能: F16, F17
- [x] 実装（generator）— 2026-08-18。1お題1投稿の担保確認、直近投稿と同一本文の連投拒否、空白・改行のみ／同一文字の過剰な繰り返しの拒否、いいね・通報の連打制限、BAN状態のアカウント締め出し（Debug限定 `-SameQBanned`）、BANされた投稿者の回答の非表示化。制限メッセージは日英併記。[`plan.md`](.product/sprints/05-ban-spam/plan.md) / [`self-review.md`](.product/sprints/05-ban-spam/self-review.md)
- [x] 修正（generator / attempt 2）— 2026-08-18。`TodayPromptView.canSubmit` を `!draft.isEmpty` に変更し、空白・改行のみの投稿でも `submitPost` の `emptyBody`（日英併記の拒否メッセージ）まで届くようにした。[`self-review.md`](.product/sprints/05-ban-spam/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **合格**（attempt 2）。受け入れ条件 **6/6**・安定性OK（クラッシュ0・独自 XCUITest 13本）・データ整合性OK（拒否された投稿は `state.json` に残らない／schemaVersion 4）・回帰10/10・使用性4。空白のみ3種（半角スペース・改行のみ・全角スペース）で日英の拒否メッセージ、拒否後に同一セッションのまま書き直して投稿できることも確認。[`eval-2.md`](.product/sprints/05-ban-spam/eval-2.md)（attempt 1 は [`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md)）

### スプリント06: 投稿本文とお題の自動翻訳
含む機能: F18, F19, F20, F21, F22
- [x] 実装（generator、仕上げはcoordinatorが引き継ぎ）— 2026-08-18。Apple Translation Framework による投稿本文・お題の端末内翻訳、非対応言語ペアのスキップ（F20）、翻訳確定までの「ちらつき」防止（F21）。[`self-review.md`](.product/sprints/06-translation/self-review.md)
- [x] 評価（evaluator）— 2026-08-18 **不合格**（attempt 1）。受け入れ条件 3/7（2件は評価不能、2件は未達）。同じ言語ペアの2件目の翻訳要求で `Translator` の待ち行列が永久に詰まる／シミュレータでは Apple Translation が機能せず翻訳経路が1度も実行されない／英語・韓国語端末でお題が日本語原文のまま／スキップした回答が恒久的に既読になる。クラッシュ0・データ整合性OK・回帰6/6・使用性3。[`eval-1.md`](.product/sprints/06-translation/eval-1.md)
- [x] 修正（generator / attempt 2）— 2026-08-18。evaluator 指摘4点すべてに対応。翻訳キューを `SessionRequestQueue<Session>`（言語ペアごとにセッションをキャッシュし2回目以降は新規要求を出さない設計）に切り出して固着を解消、Debug限定の疑似翻訳モード `-SameQFakeTranslate` を追加、お題の翻訳フォールバック方針を検討のうえ維持、`TranslationOutcome`（`.text`/`.unavailable(permanent:)`）で恒久的失敗と一時的失敗を区別し一時的失敗は既読にしないよう修正。ユニット19本＋UIテスト2本を追加（合計 `SameQTests` 56本 ＋ `SameQUITests` 33本）。他プロセス非併走の単独実行でフルテスト全件成功。実機検証は今回未実施（ユーザー外出中のためスコープ外）。[`self-review.md`](.product/sprints/06-translation/self-review.md) の attempt 2
- [x] 評価（evaluator、attempt 2）— 2026-08-18 **不合格**。受け入れ条件 3/7（2件は評価不能、2件は未達）。iPhone 17 / iOS 26.5 シミュレータ（日本語・英語・韓国語）＋ **iPhone 17 Pro Max 実機**で実操作検証。実機では本物の翻訳が表示されることを確認できた一方、**タイムラインが2〜3件目で固まり主要動線が完走しない（3/3再現）**。原因は言語ペアごとに `TranslationSession` をキャッシュする設計（`.translationTask` の外へ持ち出したセッションは configuration 差し替えで無効になる）。`invalidate()` の保険も効いていない。attempt 1 の指摘2・3・4は解消、回帰5/5、データ整合性OK、使用性2。[`eval-2.md`](.product/sprints/06-translation/eval-2.md)
- [x] 修正（generator / attempt 3）— 2026-08-18。**修正済み・再評価待ち（実機での最終確認はユーザーの端末ロック解除待ち）**。[`eval-2.md`](.product/sprints/06-translation/eval-2.md) の[1][2]に対応。(1) `SessionRequestQueue` からセッションのキャッシュを完全に撤去し、`perform(key:body:onJobTimeout:)` が**毎回**新しいセッションを要求、取得したセッションは `resolve(session:)` の中（＝そのセッションを供給した `.translationTask` のクロージャがまだ生きているスコープの中）で `session.translate(_:)` まで完結させてから結果だけを返す設計に変更（セッションを外へ持ち出す経路を型的に無くした）。`Translator` の `configuration` 差し替えも「新しいインスタンスへ丸ごと差し替え」から「いま割り当てているインスタンスへ `invalidate()` してから `source`/`target` を書き換え」に変更（SDKの `.swiftinterface` で `source`/`target` が `var`・`invalidate()` が `mutating func` であることを確認したうえで対応。新しいインスタンスへの差し替えだと SwiftUI が次のレンダーで見る最終値が無効化前と等価に戻ってしまい `.translationTask` が再実行されないことが attempt 2 の不具合の直接原因だった）。(2) `SessionRequestQueue.perform` 内で `session.translate(_:)` の実行を `withTaskGroup` でタイムアウト（既定30秒）と競走させ、タイムアウトが勝ったら `session.cancel()`（iOS 26+）を呼んでから諦める設計を追加（使い捨てスクリプトで `withTaskGroup` が cancellation に応答しない子タスクの完了を待ち続けることを確認したうえで、`cancelAll()` より先に `cancel()` を呼ぶ順序にした）。`SessionRequestQueueTests` を新しい契約に合わせて書き直し（6本）。シミュレータでのフルテストスイート（`SameQTests` + `SameQUITests`）を単独実行し **90/90 全件成功**。実機向けビルド（`-destination 'id=...'`）・`devicectl device install app` も成功（署名・プロビジョニングは問題なし）。**しかし実機（iPhone 17 Pro Max）が施錠されており `devicectl device process launch` が `Unable to launch ... because the device was not, or could not be, unlocked` で失敗、アプリを起動できず「タイムラインを実機で読み切りまで操作して確認する」という最重要の確認が完了していない**。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 3」。
- [ ] 評価（evaluator、attempt 3）— 受け入れ条件は `.product/spec.md` 194〜201行。**ユーザーが実機のロックを解除したあと**、`-SameQFakeTranslate` を付けずに実機でタイムラインを読み切りまで確認すること

### 並行タスク: タイムラインUI調整（スプリント外、ユーザー確定・2026-08-18/19）
仕様書のスプリント計画には無い、ユーザーからの直接フィードバックに基づく変更。スプリント06の
実機最終確認待ち（保留中）の間に並行して着手する。対象は `SameQ/Feature/Timeline/` および
`SameQ/Feature/Today/` 周辺。
- [x] 世界タイムライン閲覧中も、今日のお題の文章を常に見える状態にする（現状はタイムラインに
      入るとお題が見えなくなる）— 2026-08-19。`TimelineView` に `promptStrip` を追加し、
      `topBar` の直下・カード表示より上に常設。`session.promptDisplayText` をそのまま参照し、
      翻訳未確定時は `TodayPromptView.promptCard` と同じ作法（ProgressView＋「準備中…」）を
      踏襲。識別子は `timeline.promptText` / `timeline.promptLoading`。
- [x] ✕（次へ）ボタンを削除する。操作はスワイプといいねの2つだけにする。理由: ✕はスワイプと
      機能重複しており、ユーザーが用途を理解できないとの指摘（ユーザーへの回答: ✕は「次へ」＝
      スワイプと同じ動作）— 2026-08-19。`actionBar` から `xmark` ボタンを撤去し、次へ進む手段を
      `cardStack` の `DragGesture`（スワイプ）のみに一本化。影響を受けた既存UIテスト
      （`SprintOneAcceptanceTests` / `SprintThreeAcceptanceTests` / `SprintFourAcceptanceTests` /
      `SprintFiveAcceptanceTests` / `SprintSixAcceptanceTests` の計7ファイル中5ファイル）で
      `app.buttons["timeline.next"].tap()` を使っていた箇所は全て `app.swipeLeft()` に書き換え済み。
- [x] いいねボタンの位置・見た目を分かりやすく調整する（現状の配置が分かりにくいとの
      フィードバック。具体的なデザイン方向は未指定、generatorの裁量）— 2026-08-19。✕ボタンが
      無くなった分の余白を使い、カード直下の中央に単独配置。直径82ptの円形ボタンに拡大
      （旧62pt）、押下時は`Theme.like`で塗り潰し＋白いハート、未押下時は白背景＋`Theme.like`の
      縁取りで押せる場所を明示。ボタン直下に「いいね」／「いいねしました」の文字ラベルも添えた。
      アクセシビリティ識別子 `timeline.like` ・`isSelected` トレイトは変更していない。
- [x] 実装後のフルテスト（generator、2026-08-19）— 他プロセス非併走の単独実行で
      `SameQTests` 57件 ＋ `SameQUITests` 33件、**計90件すべて成功**。詳細は
      [`self-review.md`](.product/sprints/timeline-ui-adjustment/self-review.md)。
- [x] 評価（evaluator）— 2026-08-19 **合格**。iPhone 17 / iOS 26.5 と iPhone 16e / iOS 26.5 の2機種、
      端末言語は日本語・英語の2種で、evaluator 独自の XCUITest 13本（E01〜E13）＋ `simctl launch` 単独起動
      ＋ `state.json` の直接確認により実操作検証し、**スクリーンショットをすべて目視確認**した
      （generator が唯一できなかった部分）。受け入れ条件3/3、クラッシュ0、アプリ由来の未処理エラー0、
      データ整合性OK（schemaVersion 4・いいね/既読/自分の投稿がすべて操作どおり）、
      回帰は既存フルスイート90/90＋抜き取り6件（スプリント01/03/04/05/06）すべてOK、使用性4。
      お題はカード表示中・スワイプ後・読み切り・0件の空状態のすべてで出続け、重なり・はみ出し・
      スクロールの発生は無し。`timeline.next` は存在せず、スワイプだけで20件を読み切れる。
      いいねボタンは実測82×82pt・水平中央で、押下状態は色/塗り/影/文字ラベルの4重で明示される。
      **合否に影響しない改善提案4件**（最優先: カード外の余白約1/3画面でスワイプが効かない件）は
      [`eval-1.md`](.product/sprints/timeline-ui-adjustment/eval-1.md) を参照。
- [x] 改善提案 [A] の手当て（スプリント外の小さな修正、2026-08-19）— `cardStack` の `ZStack` に
      `.frame(maxWidth: .infinity, maxHeight: .infinity)` の後段で `.contentShape(Rectangle())` を
      付け、`DragGesture` を `AnswerCardView` 本体から `ZStack`（お題表示〜いいねボタンに挟まれた
      領域全体）へ移した。カードの上下にあった約138pt幅の余白でのスワイプ空振りを解消。
      一時的な座標指定UIテストで余白2か所（お題下〜カード上／カード下〜いいねボタン上）での
      スワイプが実際に次の回答へ進むことを確認済み（確認用テストはコミットせず削除）。
- [x] 改善提案 [C] の手当て（スプリント外の小さな修正、2026-08-19）— `SprintFiveAcceptanceTests` の
      `test04_likeRateLimitBlocksThenRecovers` と `test05_reportRateLimitBlocksThenShowsMessage` の
      2箇所で、`app.swipeLeft()` のあと `timeline.card.body` の**存在**しか見ていなかった検証に、
      スワイプ前後で本文が変わったことを確かめる `waitForBodyToChange`（既存の
      `SprintOneAcceptanceTests` / `SprintThreeAcceptanceTests` と同じ実装）を追加した。
- [x] 修正後のフルテスト（generator、2026-08-19）— 他プロセス非併走の単独実行で
      `SameQTests` 57件 ＋ `SameQUITests` 33件、**計90件すべて成功**。詳細は
      [`self-review.md`](.product/sprints/timeline-ui-adjustment/self-review.md) の追記分を参照。
- [x] 評価（evaluator、2026-08-19）**合格** — iPhone 17 / iOS 26.3 と iPhone 16e / iOS 26.3 の2機種で、
      ウィンドウ絶対座標を指定してスワイプする独自 XCUITest 13本（E01〜E13）により実測。
      [A]: 余白(上)163.7pt・余白(下)188.0pt の中点、および前回の無反応座標（正規化 y=0.25 / y=0.68）の
      すべてでスワイプが次の回答へ進んだ。カード本体に一度も触れず余白スワイプだけで12件を読み切りまで送れた。
      反応領域は画面の約27%（カードのみ）から約59%（y 163〜676）へ拡大。
      [C]: 追加された `waitForBodyToChange` が「進まなかったとき」に false を返すことを変異テストで確認（実効性あり）。
      いいねボタン・⋯・閉じるのタップは奪われておらず、スワイプでいいねが誤爆する事象は5通りの座標で0回。
      クラッシュ0、アプリ由来の未処理エラー0、`state.json` 整合（schemaVersion 4・再起動後も既読/いいね保持）、
      回帰は既存フルスイート90/90＋抜き取り4件、使用性4。
      残った改善提案は [E] 案内文「スワイプすると、次の知らない誰かへ」自身が無反応帯にある（優先度中）、
      [F] いいねボタン上の横引きが無反応（優先度低）。詳細は [`eval-2.md`](.product/sprints/timeline-ui-adjustment/eval-2.md)。
- [ ] （任意）改善提案 [E] の手当て — `actionBar` にも同じ `DragGesture` を付けるか、案内文を `cardStack` の内側へ移す。
      無反応帯は `y 0〜163`（上部バー＋お題）と `y 676〜874`（操作エリア）の2つで、後者には
      「スワイプすると、次の知らない誰かへ」の案内文が含まれる（実測 frame `(105.5, 797.7, 191.0, 14.3)`）。

### スプリント07: ニックネームの自動ローカライズ
含む機能: F23
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 212〜217行

### スプリント08: ランダム通知
含む機能: F24, F25
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 228〜234行

### スプリント09: お題の自動生成
含む機能: F26, F27
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 245〜251行

### スプリント10: Plus（RevenueCatによる課金）
含む機能: F28, F29, F30, F31
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 263〜269行

### スプリント11: 設定・アカウント削除・安全ログ
含む機能: F32, F33, F34
- [ ] 実装（generator）
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 281〜286行

---

## 置いた前提（ユーザー確定済み・2026-08-17）
`.product/spec.md` の「置いた前提」12件のうち、事前確認した4件はユーザー承認済み。変更しない。
1. 1お題1投稿・編集削除不可
2. お題有効期間28時間固定・常に1つだけ有効
3. いいね数は自分の受信数のみ自分だけに表示
4. 音写できないニックネームは絵文字のみ表示

## ブロッカー

### B01: Supabase クラウドプロジェクト（2026-08-17 解消）
- プロジェクト作成・マイグレーション適用は完了。認証情報は `.env.local`（gitignore対象）に保存済み
- 未実施: アプリからの実際のSupabase接続（LocalBackend → SupabaseBackend への切り替え）。担当スプリント未定。次にこのタスクに着手する際は、まず `.env.local` の内容とdashboardを確認すること
- 追記（2026-08-18）: スプリント04の `20260818000003_report_block.sql`（reports / blocks / world_timeline 更新 / blocked_authors ビュー）も `supabase db push` で適用済み。アプリからは未使用（LocalBackend のまま）。
- 追記（2026-08-17）: `20260817000002_prompt_lifecycle.sql` も `supabase db push` で適用済み（`prompts_no_overlap` 制約と `posts_set_expiry_trigger` は移行前のテーブルに無かったため `NOTICE ... skipping` が出たが、CREATE文自体は成功しており実害なし）。更新版 `supabase/seed.sql` は**まだ流し込んでいない**（アプリがまだLocalBackendで動いているため急ぎではない。SupabaseBackend実装時に一緒に流すこと）。

## 今回の判断（generator が自分で決めたこと）
仕様に書かれておらず、ユーザーに確認できなかったため自分で決めた事項。覆してよい。
1. **技術構成**: XcodeGen（`project.yml`）でプロジェクトを生成。外部パッケージ依存はゼロ。iOS 18.0 Deployment Target。
2. **回答の文字数上限は140文字**（F04のカウンター表示に上限が必要なため。スプリント10の無料ユーザー上限に合わせた）。
3. **お題は `prompt_001` 固定**、本文「今日、思わず笑ってしまったことは何ですか？」。世界の回答は14件（10言語、うち5件はニックネーム未設定）を同梱。
4. **アカウントは初回設定の最終ステップで一括作成**。途中終了しても何も保存しない（中途半端なアカウントを作らないため）。
5. **オンボーディングに「戻る」を用意**。規約や絵文字を選び直せるようにするため。
6. **Debug限定の起動引数 `-SameQResetState`** を用意。UIテストと再検証で初期状態に戻すため（Releaseビルドには含まれない）。
7. **デザイン**: 参考モックアップのトーン（白い角丸カード／緑のプライマリボタン／丸ゴシック）に寄せつつ、要望どおり装飾は控えめ（背景は淡いグラデーションのみ）。タイムラインの操作は ✕（次へ）と ♥（いいね）の2つ。モックアップにあった「いいね一覧」「他人の投稿のいいね数」「タブバー」は仕様と矛盾するため実装していない。

### スプリント02で決めたこと
8. **お題の日程は起動時に組み立てる**。Supabase 未接続のため、同梱シードのお題2件（`prompt_001` / `prompt_002`）に、シナリオごとの開始・終了時刻を起動時刻を基準に割り当てる（`SameQ/Backend/PromptSchedule.swift`）。有効期間は常に28時間・重なりなし。
9. **検証用の起動引数はすべて Debug 限定**（`LaunchOptions`）。`-SameQScenario` / `-SameQExpirySeconds` / `-SameQGapSeconds` / `-SameQTimeOffsetMinutes` / `-SameQDebugOverlay`。Release ビルドでは既定値に固定される。
10. **お題待ち画面に次のお題の開始時刻を出さない**。「いつ来るか分からない」というリズム（spec.md の中心体験）を壊さないため。時刻の確認は Debug オーバーレイでのみ可能。
11. **有効期間の判定は1秒間隔のポーリング＋前面復帰時**。画面を開いたまま期限をまたいでも切り替わる。期限が切れたらタイムラインは自動で閉じる。
12. **期限切れの自分の回答といいねは端末の保存から落とす**（`LocalBackend.pruneExpired`）。履歴を持たない方針（対象外「履歴」）をデータ側でも守るため。
13. **有効期間外のお題には投稿できない**（`BackendError.promptNotActive`）。投稿直前に期限が切れた場合はお題待ちへ落とす。

### スプリント03で決めたこと
14. **既読にするタイミングは「画面に出した瞬間」**。「読み終えてから」にすると、閉じて開き直したときに同じ回答が再び出てしまい、受け入れ条件「1件目に出る回答が毎回同一とは限らない」と噛み合わないため。
15. **読み切ったら既読の回答を出し直さない**。仕様が「明示された状態表示になる」としか言っていないので、再表示（読み直し）の導線は作らない。
16. **`empty`（回答が1件も無い）と `exhausted`（全部読んだ）を別の文言で出す**。利用者にとって意味が違うため。識別子は `timeline.empty` / `timeline.exhausted`（どちらも入れ物は `timeline.end`）。
17. **スプリント01の受け入れ条件8の検証手順を変更した**。既読の導入で「開き直して同じ回答を探す」が成立しないため、`-SameQResetViewed`（既読だけ消す起動引数）を挟む手順に差し替え、いいねの永続はユニットテストでも担保する。
18. **既読の掃除は「期限切れと確認できた投稿」に限る**。`-SameQAnswerCount` で回答の顔ぶれが変わっても既読が黙って消えないようにするため。
19. **同梱シードの `prompt_001` を14件→22件に増やした**（`supabase/seed.sql` も同期）。「20件あるとき20回スワイプして重複しない」を引数なしでも確認できるようにするため。
20. **Debug オーバーレイを `overlay` から `safeAreaInset` に変えた**。スプリント02評価の指摘[C]（最下部のテキストに重なる）を解消。今回オーバーレイが検証の主要な手段になるため。

### スプリント04で決めたこと
21. **通報の理由は7種**（政治的な対立／宗教的な対立／差別・ヘイト／性的な内容／犯罪をすすめている／個人情報／その他）。spec.md 6節（お題の安全条件）に挙がっている観点に揃えた。自由記述欄は作らない。
22. **通報・ブロックの導線はタイムライン上部の ⋯**（`timeline.more`）。カード下の操作は「次へ」と「いいね」の2つのままにして、指が届く位置に破壊的な操作を置かないため。
23. **完了表示はシートの中の1ステップにする**（トーストにしない）。「完了表示が出て」という受け入れ条件を、見逃せない形で満たすため。送信・ブロックの確定と同時に裏で次の1件を引くので、閉じた時点では次の回答になっている。
24. **ブロックした相手の回答は既読から外す**。解除したときに「再び表示対象に戻る」（受け入れ条件4）を成立させるため。読んだのではなくブロックした、という扱い。
25. **ブロック・通報で候補が尽きた場合は `.empty` ではなく `.exhausted`**（「今は新しい回答がありません」）に落とす。誰も答えていないわけではないので、「まだ誰も答えていません」は嘘になる。判定は `nextTimelinePost` 冒頭の `visibleOthers`（ブロック・通報を適用する前の集合）で行う。
26. **ブロック一覧に出すのは絵文字とニックネームだけ**。`BlockedAuthor` は国・言語・本文・投稿時刻を持たない。`blockedAt` は並び順にだけ使い、画面には出さない。
27. **設定画面は今回ブロック管理のみ**。本格的な設定（絵文字・ニックネーム変更／規約／購入復元）はスプリント11。入り口は今日のお題とお題待ちの右上の歯車。
28. **通報の記録はお題の終了で端末から落とす**（既読と同じ扱い・履歴を持たない方針）。ブロックは相手に対するものなので解除するまで残す。サーバー側の安全ログ30日保持は F34（スプリント11）。
29. **`-SameQAnswerCount` で機械生成する回答の投稿者を、お題をまたいで同一人物にした**（1お題1投稿は維持）。「ブロックした人が次のお題にも出てこない」を検証できるようにするため。
30. **`LocalStore.save` で `schemaVersion` を現在値に揃えるようにした**（スプリント03評価の改善提案[B]）。schemaVersion 3 を足すにあたり、揃えないと移行判定を誤るため今回対応した。

### スプリント05で決めたこと
31. **BANは Debug限定の起動引数 `-SameQBanned` で模擬する**。「置いた前提10」（BANは運営がサーバー側で切り替える運用・アプリ内に運営用画面は作らない）のとおり、アプリ内にBAN切り替えUIは作らない。`AppSession.start()` の冒頭でこの引数を見て `.banned` 画面に固定するので、今日のお題・タイムラインへ到達する経路は存在しない。
32. **BANされた投稿者の非表示は同梱シードに1件焼き込んで検証する**。`SeedData.json` に `bannedAuthorIDs`（トップレベル配列）を追加し、`PromptSchedule.bannedAuthorIDs` として保持、`LocalBackend.visibleOthers` で除外する。既存の22件（prompt_001）の**後ろ**に追加したので、`-SameQAnswerCount` を使う既存テスト（スプリント03・04）の件数には影響しない。
33. **同一文面の連投拒否は「直近の1投稿」とのみ比較する**。`PersistedState.lastPostBody` を新設し、`myPosts`（期限切れで掃除される）とは別に、お題をまたいで残す。比較は前後の空白・改行を除いたうえでの完全一致。
34. **無意味な文字列の判定は「最頻出1文字が70%以上・対象文字数4文字以上」の単純な閾値にした**。多言語の短い正常回答（「はい」「OK」など）を誤って弾かないための下限と、実際に「あああ」のような繰り返しを確実に拾うための上限を両立させる値として決めた。
35. **いいね・通報の連打制限は `PersistedState` に永続化しない**（プロセス内メモリのみ、再起動でリセット）。「短時間の連打」を防ぐのが目的であり、悪質ユーザーの継続対策はBAN（サーバー側）が担う想定のため。
36. **制限メッセージは日本語行＋英語行を同じ文字列に入れて常時両方表示する**（`BackendError.errorDescription` の該当ケースと `BannedView`）。アプリ全体の多言語対応の基盤（Localizable.strings 等）がまだ無いため、範囲をスプリント05で追加・変更したメッセージ（`emptyBody` / `bodyTooLong` / `duplicateBody` / `meaninglessBody` / `rateLimited` / BAN画面）に絞った。
37. **`TimelineView` に `.alert` を新設した**（スプリント04の改善提案[4]の一部を解消）。いいね・通報の制限メッセージがタイムライン上で発生するため、表示先が必要になった。実装したところ、裏で生き続ける `TodayPromptView` の `.alert` と同時に `isPresented` になり `fullScreenCover` ごと閉じる不具合が見つかったため、`isTimelinePresented` でどちらか一方だけが有効になるようゲートした。

### スプリント06で決めたこと
38. **`TranslationSession` の供給元をアプリルート常駐の不可視ビュー（`TranslationHostView`）にした**。SwiftUI では `.translationTask` からしかセッションを作れず、個々の画面に置くと画面遷移のたびにセッションが作り直されて待たされるため、`RootView` の背景に1つだけ置いて画面を横断させた。
39. **翻訳要求は `Translator` 内で1件ずつ順番にさばく**（`pending` キュー＋`isSessionInFlight`）。同時に複数の翻訳を投げると `.translationTask` のセッション解決を取り違える恐れがあるため。
40. **端末言語は `Locale.preferredLanguages.first` を起動時に1回だけ読む**。`Locale.current.language` は本アプリがローカライズリソース（Localizable.strings等）を持たないため、実機・シミュレータで開発言語（既定 "en"）に丸められる挙動を確認しており、それを避けるため。受け入れ条件「言語設定を変えて起動し直すとその言語になる」に合わせ、アプリ内切り替えは実装していない。
41. **お題の翻訳失敗時は原文へフォールバックする**。投稿は「スキップして次を引く」が使えるが、お題は常に1つだけ有効（置いた前提2）でスキップの代わりが無いため。
42. **翻訳結果と対応可否判定はプロセス内キャッシュのみ**（`Translator.textCache` / `statusCache` / `unsupportedSourceCodes`）。アプリ再起動をまたいだキャッシュは持たない（OS側のモデル自体は端末に永続されるため、モデルの再ダウンロードは発生しない設計だが、セッション生成コストは再起動後に再度発生しうる）。
43. **`-SameQAnswerCount` を使うと翻訳を挟まない検証モードになる**（機械生成の回答は常に端末言語と同じ "ja" で作る）。F11〜F17の検証と、F18〜F22（翻訳）の検証は役割を分離し、翻訳の検証には同梱シード（多言語）をそのまま使う設計にした。
44. **スプリント01の受け入れ条件8関連のテストの待ち時間を伸ばした**（`SprintOneAcceptanceTests.test02_lockedUntilAnsweredThenTimeline`）。翻訳の非同期スキップが挟まったことで1件あたりの表示・終端判定に実時間がかかるようになり、既存の5秒タイムアウトでは不安定になったための対処。プロダクションコードの挙動は変えていない。

### スプリント06 attempt 2 で決めたこと（evaluatorの不合格を受けた修正）
39の設計（`pending`キュー＋`isSessionInFlight`で1件ずつさばく）は、同じ言語ペアが連続すると
`.translationTask` が再発火せず固まることが判明したため、以下に置き換えた。
45. **`SessionRequestQueue<Session>`（`SameQ/Backend/SessionRequestQueue.swift`）に切り出し、取得済みセッションを言語ペアごとにキャッシュして使い回す設計にした**。「同じ値のConfigurationを再代入する」経路自体を無くすことで、SwiftUIの`.translationTask`が値の変化を検知できず再実行されない問題を構造的に解消した。保険として`invalidate()`の呼び出しと45秒タイムアウトも追加（タイムアウトは恒久的非対応ではなく一時的失敗として扱う）。
46. **Debug限定の疑似翻訳モード `-SameQFakeTranslate` を追加した**。シミュレータでは実際のApple Translationが機能しない（既知の制約の可能性）ため、実処理経路を通さずにF18/F20/F21のロジック（表示差し替え・スキップ・キャッシュ）をシミュレータで確定的に検証できるようにした。本番の`TranslationSession`経路はそのまま残し、疑似モードは`translate()`冒頭で分岐するだけ。Releaseビルドには含めない。
47. **翻訳結果を`TranslationOutcome`（`.text` / `.unavailable(permanent:)`）で返すように変更した**。恒久的な非対応（言語ペア自体が非対応）と一時的な失敗（セッション取得のタイムアウトや翻訳時の一時エラー）を区別し、後者だけは既読にせず次回・次の巡回で再挑戦できるようにするため。`Backend.nextTimelinePost`に`excluding`（巡回内だけの一時除外）と`autoMarkViewed`を追加。既存呼び出し元向けに後方互換のデフォルト引数版を用意した。
48. **実機検証は今回のスコープ外とした**。ユーザーが外出中で実機（iPhone 17 Pro Max）に実際にインストールして確認できないため。`SessionRequestQueue`のロジック自体はTranslationフレームワーク非依存でテスト済みだが、実際の`TranslationSession.translate(_:)`がこの待ち行列と正しく協調するかは実機でしか確認できない、という限界がある。

## 変更履歴
- 2026-08-17: `.product/spec.md` 作成（planner）。PROGRESS.md 初版作成。
- 2026-08-17: スプリント01 実装（generator）。SwiftUI雛形＋F01〜F07、Supabaseスキーマ、UIテスト5本。
- 2026-08-17: スプリント01 評価（evaluator）。iPhone 17 / iOS 26.5 シミュレータで実操作検証し **合格**。次はスプリント02の実装。
- 2026-08-17: スプリント02 実装（generator）。F08・F09・F10。お題待ち画面、有効期間による画面切り替え、投稿の表示期限、検証用の起動引数、ユニットテスト6本＋UIテスト5本を追加。
- 2026-08-17: ブロッカー B01 解消（Supabase プロジェクト作成・初期マイグレーション適用）。アプリからの接続切り替えは未着手。
- 2026-08-17: スプリント02のマイグレーション `20260817000002_prompt_lifecycle.sql` を Supabase に適用済み。次はスプリント02の evaluator 検証。
- 2026-08-18: スプリント02 評価（evaluator）。iPhone 17 Pro / iOS 26.3 シミュレータで独自 XCUITest 9本＋`simctl` 単体起動により実操作検証し **合格**。次はスプリント03の実装。
- 2026-08-18: スプリント03 実装（generator）。F11・F12。未読優先のランダム1件取得、既読の永続（`viewedPostIDs` / schemaVersion 2）、読み切り／0件の明示表示、検証用の起動引数 `-SameQAnswerCount` / `-SameQResetViewed`、同梱シードを22件へ増量。ユニットテスト10本＋UIテスト7本を追加（合計 16 ＋ 17）。次はスプリント03の evaluator 検証。
- 2026-08-18: スプリント04 実装（generator）。F13・F14・F15。通報（理由7種・完了表示・即時非表示・永続）、ブロック（確認・完了表示・お題をまたいだ持続）、設定画面のブロック一覧と解除、`state.json` schemaVersion 3、Supabase マイグレーション `20260818000003_report_block.sql` を作成・**適用済み**（reports / blocks テーブル、world_timeline の絞り込み追加、blocked_authors ビュー）。ユニット9本＋UIテスト7本を追加。次はスプリント04の evaluator 検証。
- 2026-08-18: スプリント04 評価（evaluator）。iPhone 17（iOS 26.5 / 26.3）シミュレータ2台で独自 XCUITest 10本＋`simctl` 単体起動により実操作検証し **合格**。通報・ブロック・ブロック一覧と解除・お題をまたいだ持続・最後の1件をブロックしたときの空状態を確認。次はスプリント05の実装。
- 2026-08-18: スプリント05 実装（generator）。F16・F17。1お題1投稿の担保確認、直近投稿と同一本文の連投拒否（`lastPostBody`）、空白・改行のみ／同一文字の過剰な繰り返しの拒否（`PostValidator`）、いいね・通報の連打制限（`RateLimiter`、Debug限定 `-SameQRateLimitTestMode`）、BAN状態のアカウント締め出し（Debug限定 `-SameQBanned` → `BannedView`）、BANされた投稿者の回答の非表示化（`SeedData.json` の `bannedAuthorIDs`）、制限メッセージの日英併記、`state.json` schemaVersion 4。実装中に `TodayPromptView`/`TimelineView` の二重アラート競合でタイムラインが閉じる不具合を発見・修正。ユニット12本＋UIテスト7本を追加（合計 37 ＋ 31、スプリント01〜04の回帰も全通過）。次はスプリント05の evaluator 検証。
- 2026-08-18: スプリント05 評価（evaluator）。iPhone 17（iOS 26.3 / 26.5）シミュレータ2台で独自 XCUITest 12本（E01〜E12）＋`simctl` 単体起動により実操作検証し **不合格**。BAN画面から抜ける裏道なし・BAN投稿者の回答が22件の読み切りまで一度も出ない・連投拒否・繰り返し拒否・いいね/通報の連打制限・制限後の復帰・schemaVersion 3→4 の移行はいずれもOK。**空白・改行のみの投稿に拒否メッセージが出ない**点だけが受け入れ条件を満たさず（5/6）。次はスプリント05の修正（generator / attempt 2）。[`eval-1.md`](.product/sprints/05-ban-spam/eval-1.md)
- 2026-08-18: スプリント05 修正（generator / attempt 2）。`TodayPromptView.canSubmit` の送信ボタン有効条件を trim 後の空文字判定から `!draft.isEmpty` に変更し、空白・改行のみの投稿でも `LocalBackend.submitPost` の `emptyBody`（日英併記の拒否メッセージ）まで届くようにした。指摘された1点のみ修正。`SprintFiveAcceptanceTests.test02_blankAndRepeatedCharacterBodiesAreRejected` を拒否メッセージの表示まで検証するよう更新。ユニット37本は全通過を確認、UIテストはコーディネーター側で別途確認中。次はスプリント05の evaluator 再検証。
- 2026-08-18: スプリント05 評価（evaluator / attempt 2）。iPhone 17 / iOS 26.3 シミュレータで独自 XCUITest 13本（E01〜E08 / R1〜R5）＋ `state.json` の直接確認により実操作検証し **合格**。空白・改行のみの投稿（半角スペース1個・改行のみ・全角スペースの3種）で送信ボタンが押せ、日英併記の拒否メッセージが出て投稿されないこと、OKで閉じたあと同一セッションのまま書き直して投稿できることを確認。連投拒否・繰り返し拒否・いいね/通報の連打制限・BAN画面の締め出し（ボタン0個）・BAN投稿者の非表示（22件読み切りまで0件）も再確認。回帰10/10（スプリント01の初回設定ゲートと未回答ロック／02の期限切れ→お題待ち／03の重複なし・既読の再起動後の残存・0件の空状態／04の通報の即時非表示・ブロック一覧と解除）。クラッシュ0、拒否された投稿は永続層に一切残らない。使用性4。次はスプリント06（投稿本文とお題の自動翻訳）の実装。[`eval-2.md`](.product/sprints/05-ban-spam/eval-2.md)
- 2026-08-18: スプリント06 実装（generator）。F18〜F22。Apple Translation Framework のみで投稿本文・お題を端末内翻訳。`TranslationHostView`（常駐・不可視）が `.translationTask` からセッションを供給し、`Translator` が翻訳・対応可否判定を1件ずつさばく。非対応言語ペア・翻訳失敗はスキップして次を引き直す（F20）。翻訳確定まで表示せず「準備中…」を出しちらつきを防止（F21）。端末言語は起動時に `Locale.preferredLanguages.first` を1回だけ読む。同梱シードに `promptLanguage` を追加。実装途中でセッション上限に達したため、ビルド確認・フルテスト実行（他プロセス非併走・単独実行、37+31件**全件成功**）・`self-review.md` 作成・本エントリを含む `PROGRESS.md` 更新は coordinator が引き継いで完了。次はスプリント06の evaluator 検証（モデル未取得時の表示・機内モードは実機/シミュレータでの目視確認が必要）。
- 2026-08-18: スプリント06 評価（evaluator / attempt 1）。iPhone 17 / iOS 26.5 シミュレータで端末言語を日本語・英語・韓国語の3種に切り替え（`.GlobalPreferences` を書き換えて端末ごと再起動）、独自 XCUITest 9本＋Translation Framework の直接プローブ4本で実操作検証し **不合格**。受け入れ条件 3/7。最大の問題は `Translator` の待ち行列が「直前と同じ言語ペアの2件目の要求」で永久に詰まること（同値の `TranslationSession.Configuration` を代入し直しても `.translationTask` が再実行されないことを発火回数で実測）。加えて、シミュレータでは Apple Translation が全ペアで `unsupportedLanguagePairing` を返すため翻訳経路が1度も実行されず、受け入れ条件 4（モデル未取得時）と 7（機内モード）は評価不能。英語・韓国語端末ではお題が日本語原文のまま表示され、翻訳できずスキップした回答は `viewedPostIDs` に焼き付いて二度と出ない。翻訳関連UIの不在・非対応言語のスキップ・エラーダイアログを出さないこと・回帰6/6・クラッシュ0は確認。次はスプリント06 attempt 2（generator の修正）。[`eval-1.md`](.product/sprints/06-translation/eval-1.md)
- 2026-08-18: coordinatorがユーザーに実機検証（iPhone 17 Pro Max）を今進めるか確認したところ、外出中のため不可・他に進められる範囲を優先してほしいとの回答を得た（ユーザーとのやり取りはcoordinatorのセッションのみで発生し、generator/evaluatorには直接見えないため、事実確認としてここに記録する）。これを受けて実機検証は後日に先送りし、シミュレータで対応できる修正を優先する方針で generator に修正を依頼した。
- 2026-08-18: スプリント06 修正（generator / attempt 2）。evaluator の指摘4点すべてに対応。(1) 翻訳キューの固着: 待ち行列ロジックを `SessionRequestQueue<Session>`（新規・`SameQ/Backend/SessionRequestQueue.swift`。Translation非依存のジェネリック型）に切り出し、一度取得できたセッションは言語ペアごとにキャッシュして2回目以降は新規要求を出さない設計にした（同じ値の `Configuration` を再代入する経路自体を無くす）。保険として `invalidate()` と45秒タイムアウトも追加。(2) シミュレータでの検証手段としてDebug限定の疑似翻訳モード `-SameQFakeTranslate` を追加（`Translator.translate` が `TranslationSession` を使わず `[<言語コード>] <原文>` を返す）。(3) お題の翻訳フォールバック方針を検討し、原文へのフォールバックを維持する判断（理由は self-review.md）。(4) `Translator.translate` の戻り値を `TranslationOutcome`（`.text`/`.unavailable(permanent:)`）に変更し、恒久的な非対応と一時的な失敗を区別。`Backend.nextTimelinePost` に `excluding`／`autoMarkViewed`、新規 `markPostViewed(_:)` を追加し、一時的な失敗は既読にしないようにした（既存呼び出し元は後方互換のデフォルト引数で無変更）。ユニット19本（`SessionRequestQueueTests` 5・`TranslatorFakeModeTests` 6・`TranslationSkipTests` 5・`AppSessionTranslationTests` 3）＋UIテスト2本（`SprintSixAcceptanceTests`）を追加。フルテストスイート（他プロセス非併走の単独実行、`SameQTests` 56本 ＋ `SameQUITests` 33本）**全件成功**。実機検証は今回未実施（ユーザーが外出中のため、当初の依頼どおりスコープ外とした）。次はスプリント06 attempt 2 の evaluator 再検証。[`self-review.md`](.product/sprints/06-translation/self-review.md)
- 2026-08-18: スプリント06 評価（evaluator / attempt 2）。iPhone 17 / iOS 26.5 シミュレータ（端末言語 日本語・英語・韓国語）と **iPhone 17 Pro Max 実機**（`-AppleLanguages` でプロセス単位の言語切り替え）で、独自 XCUITest 12本＋Translation Framework の直接プローブ6本により実操作検証し **不合格**。受け入れ条件 3/7。**実機で本物の Apple Translation が動くこと自体は初めて確認できた**（お題・投稿とも実際に翻訳された文章で表示。`status(en→ja)` などは `installed`）。しかし実機ではタイムラインが2〜3件目で無言のまま固着し、3回中3回とも読み切りに到達しない。原因は attempt 2 で導入した「言語ペアごとに `TranslationSession` をキャッシュして使い回す」設計で、`configuration` を別ペアへ差し替えると前の `.translationTask` が畳まれ、そのセッションが無効になるため（プローブでフレームワークの `Attempted to use TranslationSession after the view it was attached to has disappeared` を直接観測）。`session.translate(_:)` には時間制限が無く、45秒タイムアウトはセッション取得にしか掛からないので保険にならない。`invalidate()` の保険も、直後に同値の `Configuration` で上書きしているため `.translationTask` が再実行されず効いていない（`fireCount` で実測）。一方、attempt 1 の指摘2（シミュレータでの検証手段＝`-SameQFakeTranslate`）・3（お題が原文のまま）・4（スキップした回答の既読化）は解消を確認。シミュレータでは3言語とも30件を通し完走・ちらつき0・`zxx` 0回表示・翻訳関連UIは1つも無い。回帰5/5、データ整合性OK（schemaVersion 4、翻訳結果は永続化されず、固着時も既読は増えない）、使用性2。受け入れ条件4（モデル未取得時）と7（機内モード）は評価不能（実機はモデル取得済み／機内モードは端末設定の変更にあたるためユーザーの操作が必要）。次はスプリント06 attempt 3（generator の修正）。[`eval-2.md`](.product/sprints/06-translation/eval-2.md)
- 2026-08-18: スプリント06 修正（generator / attempt 3）。eval-2.md の指摘[1][2]に対応。(1) `SessionRequestQueue` からセッションのキャッシュを完全に撤去し、`perform(key:body:onJobTimeout:)` が**毎回**新しいセッションを要求、取得したセッションは `.translationTask` のクロージャがまだ生きているスコープの中で `session.translate(_:)` まで完結させてから結果だけを返す設計に変更（セッションを外へ持ち出す経路を型的に無くした）。`Translator` の `configuration` 差し替えも、SDKの `.swiftinterface` を直接確認したうえで「新しいインスタンスへ丸ごと差し替え」から「いま割り当てているインスタンスへ `invalidate()` してから `source`/`target` を書き換え」に変更（新しいインスタンスへの差し替えだと SwiftUI が次のレンダーで見る最終値が無効化前と等価に戻り `.translationTask` が再実行されないことが attempt 2 の不具合の直接原因だった）。(2) `session.translate(_:)` の実行を `withTaskGroup` でタイムアウト（既定30秒）と競走させ、タイムアウトが勝ったら `session.cancel()`（iOS 26+）を呼んでから諦める設計を追加（`withTaskGroup` が cancellation に応答しない子タスクの完了を待ち続けることを使い捨てスクリプトで確認したうえで、`cancelAll()` より先に `cancel()` を呼ぶ順序にした）。`SessionRequestQueueTests` を新しい契約に合わせて全面的に書き直し。シミュレータでのフルテストスイート（`SameQTests` + `SameQUITests`）を単独実行し **90/90 全件成功**。実機向けビルド・`devicectl device install app` も成功（署名・プロビジョニングは問題なし）。**しかし実機（iPhone 17 Pro Max）が施錠されており `devicectl device process launch` がロック解除待ちで失敗、アプリを起動できず実機でのタイムライン読み切り確認ができなかった**。ユーザーに端末のロック解除を依頼し、解除後に改めて実機確認を行う。[`self-review.md`](.product/sprints/06-translation/self-review.md) の attempt 3
- 2026-08-19: 並行タスク「タイムラインUI調整」実装（generator）。スプリント06の実機確認待ちの間に着手した、スプリント計画外・ユーザー直接フィードバックによる変更。`SameQ/Feature/Timeline/TimelineView.swift` のみを変更（スプリント06関連ファイルには触れていない）。(1) `promptStrip` を新設し、今日のお題（`session.promptDisplayText`）を `topBar` の直下・カード表示の上に常設表示。翻訳未確定時は `TodayPromptView.promptCard` と同じ「準備中…」の作法を踏襲（識別子は `timeline.promptText` / `timeline.promptLoading`）。(2) ✕（次へ）ボタンを撤去し、次へ進む操作を `cardStack` のスワイプのみに一本化。旧 `circleButton` ヘルパーは使用箇所がいいねボタンのみになったため削除し専用実装に置き換えた。(3) いいねボタンを直径82ptの円形ボタンに拡大し、カード直下の中央へ単独配置。押下時は `Theme.like` で塗り潰し＋白いハート、未押下時は白背景＋縁取りで押下可能な場所を明示、直下に状態を表す文字ラベル（「いいね」／「いいねしました」）を追加。識別子 `timeline.like` と `isSelected` トレイトは変更していない。✕ボタン撤去の影響で `app.buttons["timeline.next"].tap()` を使っていた既存UIテスト5ファイル（`SprintOneAcceptanceTests` / `SprintThreeAcceptanceTests` / `SprintFourAcceptanceTests` / `SprintFiveAcceptanceTests` / `SprintSixAcceptanceTests`）を `app.swipeLeft()` へ書き換え、失われた「操作不能にならないことの確認」の意図は `SprintFiveAcceptanceTests` の2箇所で実際にスワイプして次の回答が出ることを確認する形に置き換えた。ビルド確認後、他プロセス非併走の単独実行でフルテストスイート（`SameQTests` 57本 ＋ `SameQUITests` 33本）**計90件すべて成功**。Simulator.app のGUI自動操作に必要な Accessibility 権限が取得できず（`computer-use` もこの環境では iOS Simulator が明示的に unsupported）、タイムライン画面そのものの目視スクリーンショットは取得できていない（詳細・弱点は self-review.md 参照）。次は本タスクの evaluator 検証。[`self-review.md`](.product/sprints/timeline-ui-adjustment/self-review.md)
- 2026-08-19: 並行タスク「タイムラインUI調整」評価（evaluator）**合格**。iPhone 17 / iOS 26.5 と iPhone 16e / iOS 26.5 の2機種、端末言語 日本語・英語で、独自 XCUITest 13本（E01〜E13）＋ `simctl launch` 単独起動＋`log stream`＋アプリコンテナ `state.json` の直接読み出しにより実操作検証。**generator が取得できていなかったタイムライン画面のスクリーンショットを XCTAttachment 経由で取り出し、すべて目視確認した**。受け入れ条件3/3（お題の常設表示はカード表示中・スワイプ後・読み切り・0件の空状態のすべてで維持、重なり/はみ出し/スクロール無し。`timeline.next` は不在でボタンは閉じる・⋯・いいねの3つのみ、スワイプだけで20件を読み切り。いいねボタンは実測82×82pt・水平中央、押下状態は色/塗り/影/文字ラベルで明示）。クラッシュ0、アプリ由来の未処理エラー0（ログのエラーはシミュレータの絵文字フォント欠落・ハプティクス資産欠落等の環境ノイズのみ。SwiftUI の `Invalid frame dimension` はオンボーディング/キーボード経路の既存事象で、タイムライン単独起動では出ないことを確認）。データ整合性OK（schemaVersion 4、いいねのON/OFF/ONが1件、既読8件、自分の投稿1件と一致）。回帰は既存フルスイート **90/90 全件成功**（generator の申告どおり）＋抜き取り6件（通報・ブロックの⋯導線、既読管理と再起動後の残存、連打制限からの復帰、翻訳関連UIの不在、未回答時のロック、いいねの永続）すべてOK。使用性4。**合否に影響しない改善提案4件**を記録: [A] ✕撤去でスワイプが唯一の前進手段になったが、カードの上下にある約138pt幅の余白ではスワイプが効かず画面の約1/3が無反応（実測。`cardStack` の `ZStack` に `.contentShape(Rectangle())` を付ける提案）、[B] お題とカードの間の空白が大きい、[C] 書き換えた `SprintFiveAcceptanceTests` の2箇所が「次へ進んだこと」まで検証していない、[D] 長文お題での2行省略。「準備中…」の実物は表示時間が100ms未満で50枚以上の連写でも捉えられず未確認（固着しないことは確認済み）。[`eval-1.md`](.product/sprints/timeline-ui-adjustment/eval-1.md)
- 2026-08-19: 並行タスク「タイムラインUI調整」の合否に影響しない指摘[A][C]をスプリント外の小さな修正として対応（generator）。対象は `SameQ/Feature/Timeline/TimelineView.swift` と `SameQUITests/SprintFiveAcceptanceTests.swift` のみ（スプリント06関連ファイルには触れていない）。(1) [A] `cardStack` の `DragGesture` を `AnswerCardView` 本体から `ZStack` 側（`.frame(maxWidth: .infinity, maxHeight: .infinity)` の後段に `.contentShape(Rectangle())` を追加）へ移し、お題表示〜いいねボタンに挟まれた領域全体（カード上下の余白を含む）でスワイプが効くようにした。座標指定でスワイプする一時的なUIテストを書いて余白2か所（お題下〜カード上／カード下〜いいねボタン上）で実際に次の回答へ進むことを確認したうえで、そのテストは削除した（`project.pbxproj` も検証後に元へ復元し、diffには残していない）。(2) [C] `SprintFiveAcceptanceTests` の `test04_likeRateLimitBlocksThenRecovers` と `test05_reportRateLimitBlocksThenShowsMessage` で `app.swipeLeft()` 後に本文の**存在**しか見ていなかった検証に、`SprintOneAcceptanceTests` 等と同じ `waitForBodyToChange` を追加し、実際に次の回答へ進んだことまで確認するようにした。他プロセス非併走の単独実行でフルテストスイート（`SameQTests` 57本 ＋ `SameQUITests` 33本）**計90件すべて成功**。次はこの2点についての evaluator 再確認。[`self-review.md`](.product/sprints/timeline-ui-adjustment/self-review.md) の追記分

- 2026-08-19: 並行タスク「タイムラインUI調整」の指摘[A][C]修正を再評価（evaluator）**合格**。iPhone 17 / iOS 26.3（402×874）と iPhone 16e / iOS 26.3（390×844）の2機種で、`XCUICoordinate.press(forDuration:thenDragTo:)` によりウィンドウ絶対座標を指定してスワイプする独自 XCUITest 13本（E01〜E13）＋ `log stream` ＋ アプリコンテナ `state.json` の直接読み出し ＋ スクリーンショットの目視確認により実操作検証。**[A] 解消**: 実測レイアウトは prompt 下端 y=163.0 / カード上端 y=326.7 / カード本文下端 y=488.0 / いいね上端 y=676.0 で、余白(上)163.7pt・余白(下)188.0pt の中点、および前回の無反応座標（正規化 y=0.25=218.5pt / y=0.68=594.3pt）の**すべてでスワイプが次へ進んだ**。カード本体に一度も触れずに上下の余白だけで12件を送り切り読み切り（`timeline.exhausted`）へ到達。画面左端 x=8 からのスワイプも有効。反応領域は約27%（カードのみ）から約59%（y 163〜676、画面幅いっぱい）へ拡大。iPhone 16e でも同13本が全件成功。**[C] 解消かつ実効性を確認**: 追加された `waitForBodyToChange` が、しきい値未満（30pt）のドラッグでは false を返すことを変異テストで直接確認したため、空振りしても通ってしまうアサーションではない。**誤操作なし**: いいねボタン真上8pt・ボタン上・⋯・閉じるの各座標で、スワイプによるいいねの誤爆は0回、ボタンのタップは従来どおり機能。⋯ のシート（`safety.report`/`safety.block`/`safety.cancel`）を開いて閉じたあとも余白スワイプが効く。**前回合格の3点も維持**（お題の常設表示・`timeline.next` 不在でボタン3つのみ・いいね82×82pt水平中央と押下ラベル）。クラッシュ0、アプリ由来の未処理エラー0（ログのError/Fault 953件はハプティクス資産欠落918件とシミュレータのTranslation非対応33件などの環境ノイズのみ）。データ整合性OK（schemaVersion 4、いいね1件、再起動をまたいで既読の回答が再登場しない＝重複0件、`viewedPostIDs` 31件はシード32件のうち日本語12件表示＋翻訳不能19件スキップの既知内訳と一致）。回帰は既存フルスイート **90/90 全件成功** ＋ 抜き取り4件（既読管理・再起動後の永続・通報ブロックの⋯導線・いいねの押下状態）。使用性4。**残る改善提案2件**: [E] 案内文「スワイプすると、次の知らない誰かへ」自身（y=804.8）を含む下部 `y 676〜874` が無反応帯のまま（優先度中）、[F] いいねボタン上の横引きが無反応（優先度低）。[`eval-2.md`](.product/sprints/timeline-ui-adjustment/eval-2.md)
