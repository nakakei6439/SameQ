# スプリント 05 評価（attempt 2） — 合格

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 6/6 | 100% | ✓ |
| 2 安定性 | クラッシュ0 / アプリ由来の Error・Fault ログ0 / 主要動線すべて完走 | 0 | ✓ |
| 3 データ整合性 | 拒否された投稿は永続層に一切残らない。成功した投稿は再起動後も一致。schemaVersion 4 | 100% | ✓ |
| 4 回帰 | スプリント01から3件・02から1件・03から3件・04から3件を抜き取り 10/10 | 100% | ✓ |
| 5 使用性 | 4（attempt 1 の 3 から改善。投稿できない理由が画面に出るようになった） | 3以上 | ✓ |

**attempt 1 の不合格理由（空白・改行のみの投稿で拒否メッセージが出ない）は解消を確認した。**

## 検証環境
- 実行日時: 2026-08-18 11:20 〜 12:00 JST
- シミュレータ: **iPhone 17 / iOS 26.3**（`12050FBD-587B-4910-8812-696BB91BE051`）
- ビルド: `xcodebuild -project SameQ.xcodeproj -scheme SameQ -configuration Debug -destination 'platform=iOS Simulator,id=12050FBD…' build-for-testing` → **TEST BUILD SUCCEEDED**
- 操作方法: **evaluator が独自に書いた XCUITest 13本**（`EvaluatorSprintFiveA2Tests` E01〜E08 / `EvaluatorRegressionA2Tests` R1〜R5）で実タップ・実入力。
  generator のテスト結果は判定に使っていない（参考として `SameQTests` 37本を別途実行し 0 failures を確認）。
  検証後に評価用テストファイルを削除し、`xcodegen generate` で `SameQ.xcodeproj` を元に戻し、
  `git status` がクリーン（未追跡の `.claude/` のみ）であることを確認済み。**本体コードは1行も変更していない**。
- データ確認: `xcrun simctl get_app_container 12050FBD… com.nakakei6439.SameQ data`
  → `Library/Application Support/SameQ/state.json` を操作直後に直接読み出し
- クラッシュ確認: `~/Library/Logs/DiagnosticReports` と
  `~/Library/Developer/CoreSimulator/Devices/12050FBD…/data/Library/Logs` を検証時刻以降で確認 → **新規0件**
  （既存の `SameQ-2026-08-18-070712.ips` は本評価の開始（11:20）より前・generator の作業時間帯のもので、本評価では再現しなかった）
- ログ確認: `xcrun simctl spawn … log show --predicate 'process == "SameQ"' --last 40m`
  → Error / Fault レベルでアプリ由来のものは0件
- 使用データ: 同梱シード（`prompt_001` 23件中1件がBAN投稿者）と `-SameQAnswerCount 0 / 3 / 4 / 5 / 8 / 12 / 20`、
  `-SameQScenario live / expiring / expired`、`-SameQRateLimitTestMode`、`-SameQBanned`、`-SameQResetViewed`、`-SameQDebugOverlay`

### evaluator 独自テスト（13本・全 passed）
| ID | 内容 | 結果 |
|---|---|---|
| E01 | 空白＋改行のみ（`"   \n \n  "`）→ 送信ボタンが押せる → 日英の拒否メッセージ → OKで閉じてお題画面に留まる → **同一セッションのまま**書き直して投稿できる | passed |
| E02 | 空白のバリエーション3種（半角スペース1個 / 改行のみ / **全角スペース**）すべてで日英の拒否メッセージ、いずれも未投稿のまま | passed |
| E03 | 同一文字の繰り返し（あ×14）→ 日英の拒否メッセージ → 設定を開閉できる → 開き直して通常投稿できる | passed |
| E04 | 1お題1投稿（投稿後は入力欄・送信ボタンが消える／再起動後も同じ） | passed |
| E05 | `expiring` でお題をまたぎ、同一本文で連投 → 日英の拒否メッセージ → 言葉を変えると投稿できる | passed |
| E06 | いいね連打（テストモード3回まで）→ 4回目で制限 → タイムラインは開いたまま次へ進める → 通報連打（2回まで）→ 3回目で制限 → 12秒後にいいねが復帰 | passed |
| E07 | 通常アカウント作成後に `-SameQBanned` で起動 → BAN画面のみ・**ボタン0個**・4方向スワイプとタップで抜け道なし → 引数を外すと元の回答ごと復帰 | passed |
| E08 | 引数なしの同梱シードで22件を読み切るまでBAN投稿者の目印文言が一度も出ない → `timeline.exhausted` | passed |
| R1 | 回帰（規約未同意・絵文字未選択で次へ進めない／未回答ロック／再起動で初回設定が再表示されず絵文字・ニックネームが残る） | passed |
| R2 | 回帰（投稿後にタイムラインが開く／自分の投稿が出ない／12件スワイプで重複0／読み切り表示／再起動後も既読が残る／既読リセット後もいいねの押下状態が残る） | passed |
| R3 | 回帰（`expired` でお題待ちへ／入力欄もタイムライン導線も無い／履歴導線が無い） | passed |
| R4 | 回帰（通報→完了表示→即時非表示／ブロック→確認→完了表示→設定のブロック一覧→解除で空表示／再起動後も通報した回答が再表示されない） | passed |
| R5 | 回帰（回答0件のときに `timeline.empty` の空状態が出る／カードは出ない／閉じられる） | passed |

## 受け入れ条件の確認結果（spec.md 177〜183行）

| # | 条件 | 判定 | 根拠（観測値） |
|---|---|---|---|
| 1 | 1つのお題に投稿できるのは1回だけで、投稿後にお題画面へ戻っても入力欄は再表示されず、自分の回答が表示される | ✓ | E04。投稿→タイムラインを閉じると `today.myAnswer` が出て `today.input` / `today.submit` は存在しない。再起動後も同じ。`state.json` の `myPosts` は1件 |
| 2 | 直近の自分の投稿と同一の本文を別のお題に投稿しようとすると、拒否メッセージが出て投稿されない | ✓ | E05。`prompt_001` に投稿 → 期限またぎ → 次のお題で同一本文を送信 → 「直前の自分の投稿と同じ内容です。／This is identical to your previous post.」。`today.myAnswer` は出ない。語を足すと投稿できる |
| 3 | 空白・改行のみの投稿、および同一文字の過剰な繰り返しは拒否メッセージが出て投稿されない | **✓（attempt 1 からの修正点）** | E01 / E02。空白・改行のみで送信ボタンが押せるようになり、「空白や改行だけの回答は投稿できません。／You can't post a reply that's only blank space or line breaks.」が表示される。半角スペース1個・改行のみ・全角スペースの3種すべてで同じ。繰り返しは E03 で「同じ文字を並べただけの投稿はできません。／A post made of the same character repeated isn't allowed.」 |
| 4 | 短時間にいいねまたは通報を規定回数以上繰り返すと一時的に制限され、その旨が画面に表示される | ✓ | E06。いいねは4回目、通報は3回目で「いいね（通報）が短時間に多すぎます。8秒待ってからもう一度お試しください。／Likes (Reports) too fast. Please wait 8s and try again.」。制限中もタイムラインは開いたまま、12秒後に復帰 |
| 5 | BAN状態のアカウントで起動すると、利用できない旨の画面が表示され、お題画面にもタイムラインにも入れない | ✓ | E07。`banned.root` のみ表示、`XCUIApplication().buttons.count == 0`。4方向スワイプ・画面タップのあとも `today.promptText` / `waiting.root` / `timeline.card.body` / `settings.open` はいずれも存在しない |
| 6 | BANされたユーザーの回答は、他ユーザーのタイムラインに1件も表示されない | ✓ | E08。同梱シード23件のうちBAN投稿者1件を除いた22件を読み切るまで、目印文言「BANされた投稿者のテスト投稿」も名前「BannedGhost」も一度も出ない。読み切り後は `timeline.exhausted` |

### 評価者への注記（spec.md 185行）への確認
| 注記 | 判定 | 根拠 |
|---|---|---|
| 制限メッセージが日本語・英語どちらの端末でも読めるか | ✓ | 今回対象の5種すべて（`emptyBody` / `meaninglessBody` / `duplicateBody` / `rateLimited`×2）で、**同一アラート内に日本語行と英語行の両方**が出ることを実測。attempt 1 で「死んだ文言」だった `emptyBody` も画面に到達するようになった（スクリーンショット `E01-blank-rejection-alert`） |
| 制限メッセージのあとアプリが操作不能にならないこと | ✓ | E01（OKで閉じる→お題画面に留まる→**再起動せずに**書き直して投稿できる）、E03（設定を開閉できる）、E05（言葉を変えれば投稿できる）、E06（タイムラインは閉じず次へ進め、クールダウン後に復帰） |

## データ整合性の確認（`state.json` を直接確認）
| 操作 | 期待 | 実測 |
|---|---|---|
| 空白のみの投稿を3回拒否させたあと（E02 直後） | 何も保存されない | `schemaVersion: 4` / `myPosts: []` / `lastPostBody` キーなし / `user` は `{emoji: 🌙, nickname: EvalUser}` のまま / `likedPostIDs: []` / `viewedPostIDs: 0件` |
| 空白拒否 → 書き直して投稿（E01 直後） | 成功した1件だけが残る | `myPosts` 1件（`body: "Recovered after the blank rejection." / promptID: prompt_001`）、`lastPostBody` も同一文字列。**拒否された空白文字列は残っていない** |
| 再起動後 | 投稿が保たれる | E04 / R2 で再起動後も `today.myAnswer` が同じ本文。既読（`viewedPostIDs`）も保たれ、`-SameQResetViewed` で既読だけ消してもいいねの押下状態は残る |

## 使用性（4/5）
- 空状態: 回答0件で `timeline.empty`、読み切りで `timeline.exhausted`、ブロック一覧が空で `settings.blocked.empty` と、3種類の空状態がすべて明示されている
- エラー時: 5種類の拒否・制限がすべて日英併記のアラートで理由まで説明される（attempt 1 で唯一無言だった空白のみのケースが解消）
- 主要動線: 初回設定→投稿→タイムラインは最短経路で到達でき、拒否されても同じ画面から書き直せる
- 破壊的操作: ブロックは確認ステップ（`safety.blockConfirm`）を挟む
- 4 に留めた理由は下の改善提案[A]（残り1点で満点にはならない細かい引っかかり）

## 改善提案（合否には影響しない）
### [A]（優先度: 中）空白だけを入力しているとき、文字数カウンタが「8/140」と出て入力があるように見える
拒否メッセージが出るようになったので実害は消えたが、押す前の画面では「8文字入力済み」に見えて空欄に見える矛盾は残っている。
trim 後の文字数を数える、あるいは空白のみのときにカウンタをグレーにする等で、押す前に気づける。

### [B]（優先度: 中・attempt 1 から継続）`Yessssssss` のような正常な英語表現が繰り返し判定に引っかかる
`PostValidator` の閾値（最頻出1文字が70%以上）が、伸ばし表現を弾く。ラテン文字では母音・子音の偏りが大きいため、
文字種で閾値を変える／連続同一文字の最大ラン長で判定する等が考えられる。

### [C]（優先度: 低・attempt 1 から継続）連打制限はプロセス内メモリのみで、アプリを再起動すると解除される
「制限されたら再起動する」で迂回できる。スコープ（一時的な連打抑止）としては妥当だが、Supabase 接続時に
サーバー側へ移すことを前提に記録しておく。

### [D]（優先度: 低）同一文面の連投拒否は「直近1件」のみとの比較
generator が self-review.md で自認しているとおり。2つ前の投稿と同じ文面は通る。

## 評価できなかったもの
- なし（受け入れ条件6件・注記2件をすべて実操作で確認した）
- ただしBAN状態の判定は Debug 限定の起動引数 `-SameQBanned` に依存しており、サーバー側の実データに基づくBANは
  Supabase 接続後にあらためて確認する必要がある（置いた前提10・generator も自認済み）
