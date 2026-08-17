# スプリント 02 自己評価（attempt 1）

対象: F08（お題待ち画面）/ F09（お題の有効期間）/ F10（投稿の寿命）
前提: お題の有効期間は28時間固定・常に1つだけ有効（`.product/spec.md` 置いた前提2・3）。投稿の表示期限はお題の終了時刻に揃える。

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 有効なお題が無い時間帯はお題待ち画面が表示され、回答入力欄もタイムラインへの導線も存在しない | 達成 | `-SameQScenario expired` / `upcoming` で起動 → `WaitingPromptView` が出る。この画面には入力欄・投稿ボタン・タイムラインを開くボタンが1つも無い（そもそも `AppSession.screen == .waiting` のとき `TodayPromptView` / `TimelineView` は生成されない）。UIテスト `SprintTwoAcceptanceTests.test01/test02` が `today.input` `today.submit` `today.openTimeline` `timeline.card.body` `today.promptText` の非存在を確認。シミュレータで実画面も目視確認済み |
| 有効期間中に未回答で起動すると今日のお題画面、回答済みで起動するとタイムラインが開く | 達成 | `-SameQScenario live` で起動 → 今日のお題画面＋入力欄。投稿後に再起動するとタイムラインが自動で開く。UIテスト `test03`（および スプリント01 の `test04`）で確認 |
| お題の終了時刻を過ぎると、そのお題の回答はタイムラインに1件も表示されなくなり、画面がお題待ちへ切り替わる | 達成 | `RootView` が1秒ごと（＋前面復帰時）に `AppSession.refresh()` を呼び、お題の状態が変わったらタイムラインを閉じて `.waiting` へ落とす。**タイムラインを開いたまま**期限をまたぐケースを UIテスト `test04` で実行（`-SameQExpirySeconds 75`）。切り替え後にカードが残っていないこと・自分の回答も消えることを確認 |
| 新しいお題が開始すると、前のお題に回答済みのアカウントでも再び未回答状態になり、今日のお題画面が表示される | 達成 | 同じ `test04` の後半。空白（`-SameQGapSeconds 30`）のあと prompt_002 が始まり、お題本文が変わり、入力欄とロック表示が復活し、`today.openTimeline` が消えることを確認。データ層は `PromptLifecycleTests.testNewPromptResetsAnsweredState` |
| アプリ内のどこにも、自分の過去の投稿・過去のお題・いいねした投稿を一覧する導線が無い | 達成 | 画面は Onboarding / Waiting / Today / Timeline の4つだけで、履歴系の画面も遷移も追加していない。期限切れの自分の回答といいねは端末の保存からも落とす（`LocalBackend.pruneExpired`）。UIテスト `test05` が3画面のボタン・テキストを走査して「履歴/過去/アーカイブ/一覧/いいねした/History/Archive/Liked/Past」を含む導線とタブバーが無いことを確認 |
| 期限切れの直前に投稿した回答も、お題の終了時刻を過ぎれば他ユーザーから見えなくなる | 達成（検証は主にデータ層） | 投稿時に `expiresAt = prompt.endsAt` を必ず入れる（クライアントの都合で延ばせない）。ユニットテスト `PromptLifecycleTests.testPostSubmittedJustBeforeExpiryDisappearsForOthers` が、終了30秒前の投稿が終了後は `timelinePosts` に出ないことを確認。UI だけでは別アカウント視点を作れないため、ここはユニットテストで担保している |

自動テスト結果（`xcodebuild ... test`、iPhone 17 / iOS 26.x シミュレータ）:
- `SameQTests` 6本すべて成功
- `SameQUITests` 10本すべて成功（スプリント01の5本を含む。既存の合格挙動は壊していない）

## 動かし方（evaluator 向け）

```bash
open SameQ.xcodeproj   # 依存パッケージなし。iPhone 17 シミュレータで Run
# もしくは
xcodebuild -project SameQ.xcodeproj -scheme SameQ \
  -destination 'platform=iOS Simulator,name=iPhone 17' test        # 全テスト（約4分）
```

### 起動引数で日程を切り替える（Debug ビルドのみ有効）

Xcode の Scheme > Run > Arguments、または
`xcrun simctl launch booted com.nakakei6439.SameQ <引数...>` で渡す。

| 引数 | 効果 |
|---|---|
| `-SameQScenario live` | 既定。prompt_001 が有効期間の途中（2時間前に開始、残り26時間） |
| `-SameQScenario expiring` | prompt_001 がまもなく終了 → 空白（お題待ち）→ prompt_002 が開始 |
| `-SameQScenario expired` | prompt_001 は1時間前に終了済み。次は20時間後（ずっとお題待ち） |
| `-SameQScenario upcoming` | prompt_001 はまだ開始していない（2時間後）。ずっとお題待ち |
| `-SameQExpirySeconds 120` | `expiring` で「終了までの秒数」。既定 180 |
| `-SameQGapSeconds 60` | `expiring` で「終了から次の開始までの秒数」。既定 180 |
| `-SameQTimeOffsetMinutes 90` | アプリが認識する「今」を分単位でずらす（負値可）。待たずに期限後の状態を見たいときに使う |
| `-SameQDebugOverlay` | 画面下に `now / scenario / お題ID / 残り秒数 / 回答済みか` を表示 |
| `-SameQResetState` | 保存済みのアカウント・回答・いいねを消して初回設定からやり直す |

### 推奨の確認手順

1. **お題待ち画面**: `-SameQResetState -SameQScenario expired -SameQDebugOverlay` で起動 → 初回設定を済ませる → お題待ち画面。入力欄・タイムライン導線が無いこと、アプリを終了して同じ引数（`-SameQResetState` は外す）で再起動しても同じ状態であることを確認。`upcoming` でも同様。
2. **有効期間中**: `-SameQResetState -SameQScenario live` → 今日のお題画面 → 回答 → タイムライン → アプリ終了 → 引数なしで再起動するとタイムラインが直接開く。
3. **期限またぎ（本命）**: `-SameQResetState -SameQScenario expiring -SameQExpirySeconds 180 -SameQGapSeconds 120 -SameQDebugOverlay` で起動 → 初回設定 → 回答 → **タイムラインを開いたまま**待つ。オーバーレイの残り秒数が0になるとタイムラインが自動で閉じ、お題待ち画面へ切り替わる（クラッシュ・古いカードの残留が無いこと）。さらに120秒待つと prompt_002 が始まり、回答済みだったのに入力欄が戻る。
4. **期限切れ直前の投稿**: 上の3で、残り20秒くらいのタイミングで回答して同じ挙動になることを確認（自分の回答も終了と同時に消える）。
5. **履歴導線が無いこと**: 全画面を回って、過去のお題・自分の投稿一覧・いいね一覧へ行ける導線が無いことを確認。

補足: 日程は**起動時の時刻を基準に組み立てる**ので、アプリを再起動するとシナリオの残り時間もリセットされる（例: `expiring` は毎回「起動から180秒後に終了」）。期限切れ**後**の状態を再起動込みで見たい場合は `-SameQScenario expired` か `-SameQTimeOffsetMinutes` を使う。

## 自分で見つけた弱点

- **お題の日程はサーバーではなく端末で組み立てている**。Supabase 未接続のため（ブロッカー B01）、「世界共通の同じお題が同時に切り替わる」ことは実機2台では確認できない。`prompts.starts_at / ends_at` に沿った実装にはしてあり、切り替え先は `BackendProvider.make()` の1か所。
- **判定の間隔は1秒**。厳密に終了時刻ちょうどではなく、最大1秒遅れて切り替わる。
- **タイムラインを開いたまま期限が切れると、モーダルが自動で閉じる**（操作中でも問答無用）。「読んでいる最中に消える」体験としては仕様どおりだが、ユーザーには唐突に見える可能性がある。切り替えの説明表示（トースト等）は仕様に無いので入れていない。
- **`-SameQDebugOverlay` は画面最下部に重なる**。ボタンのタップは通過する（`allowsHitTesting(false)`）が、下端のボタン文字が読みにくくなる。検証用なので既定はオフ。
- スプリント01評価で挙がった改善提案3件（キーボードが投稿ボタンを隠す／投稿ボタンが押せない理由が出ない／`state.json` 破損時に黙ってアカウントが消える）は**今回も未対応**。スプリント02の範囲外のため意図的に触っていない。

## 提案（今回はやらなかったこと）

- タイムラインの既読管理と未読優先の取得（スプリント03の範囲。いまは開き直すと先頭から出る）。
- お題切り替えを「サーバー時刻」に合わせる仕組み（端末時計を変えられると日程がずれる）。Supabase 接続時に一緒にやるのが自然。
- `supabase/migrations/20260817000002_prompt_lifecycle.sql`（有効期間の重複禁止、有効なお題だけ読める RLS、`expires_at` を自動設定するトリガー）を書いたが**未適用・未検証**。適用の担当スプリントは未定。
