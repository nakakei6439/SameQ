- 2026-09-09/10: App Store 3度目リジェクト対応 = スプリント20（コーディネーターが直接実装）。
  Apple が `1.0.2 (7)` を **Guideline 1.2（ユーザー生成コンテンツ）と 3.1.2（サブスクリプション）**
  の2件でリジェクト（Submission ID `8e7b3e06-9aa8-4eee-adc9-3756a7f69468`）。1.2 は匿名投稿がある
  アプリ向けの定型8項目で "all of the following" と明記されているため、8項目すべてを1ビルドで揃えた。
  **ユーザー指示によりハーネス（generator/evaluator）は使わず、コーディネーターが直接実装**。
  **実装（F48-F54 / spec.md 前提1・19 を改訂、前提37-43 を新設）**: 禁止語フィルタ（本文＋ニックネーム、
  日本語は部分一致・英語は語境界一致、端末側とサーバー側の二重）／自分の回答の削除（`status='removed'` の
  論理削除。削除後は同じお題に再回答不可）／通報3件（禁止語一致なら1件）で自動非表示・非表示3件で自動BAN
  （運営名義は対象外）／設定とBAN画面のお問い合わせ／規約の日英化とゼロトレランス条項（第2条）／
  規約同意の版つき記録と再同意／Plus 購入画面の規約リンク（3.1.2）。
  **実装中に見つけて直した危険な穴3件**: (a) `updateProfile` が Post を作り直す際に `status` が落ちて
  削除済みの回答が復活、(b) `pruneExpired` が「削除」を「期限切れ」と誤判定して通報記録を早期削除
  （F34 の30日保持が壊れる）、(c) 運営回答の自動投入がフィルタで失敗すると当日のタイムラインが空になる
  （2回目のリジェクト 2.1(a) の再発）→ 運営名義をフィルタ対象外に。
  **RLS ではなく RPC を選んだ理由**: RLS の `with check` は「どの列を更新したか」を制限できないため、
  `posts` に UPDATE を許すと同じ UPDATE で `body` を書き換えられる（＝通報された投稿者が本文を
  差し替えて逃げられる）。`remove_my_post()` を `security definer` にして posts への直接 UPDATE は許さない。
  **検証**: ユニット263件・スプリント20受け入れUI 8件すべて green。本番DBへ適用し、誤検知が無いこと
  （`I passed the class and the analysis was fine.` / `Scunthorpe` が検出されない）を SQL で実証。
  **スプリント19も同時に解決**: 未コミットで残っていたお題プール999件化を、`verify.py` で Swift↔SQL の
  byte-exact 一致を確認のうえコミット。**migration の配列末尾に余分なカンマがあり適用できない状態だった**
  （未適用のまま残っていたため誰も踏んでいなかった）のを修正して本番へ適用。
  **リリース**: `1.0.2 (7)` → `1.0.3 (8)`（TestFlight に 1.0.2 (7) が配信済みで、同じ版数で中身が違うと
  運営お知らせとずれるため版数ごと上げた）。README 更新 → commit（`c84482a` / `bae2a18`）→ push →
  `announcements` に日英2行を投入 → `xcodebuild archive`（ARCHIVE SUCCEEDED）→ `-exportArchive`
  （EXPORT SUCCEEDED）→ `altool --validate-app`（VERIFY SUCCEEDED）→ `--upload-app`
  （**UPLOAD SUCCEEDED、Delivery UUID `78353976-7223-45a9-abfa-7a976b90ef5f`**）まで完了。
  ASC API キーは `AuthKey_BR882VJ4P8.p8` / Issuer `4a7eba90-53ca-4945-ae45-78facdf6f085`。Web版規約（`nakakei6439.github.io`、commit `83f85a3`）も
  アプリと同じ14条構成に日英で同期し、公開反映を実URLで確認済み。
  **残り（ASC の GUI 手作業）**: 年齢レーティングを 18+ に／「App情報 → 使用許諾契約」にカスタム EULA を登録／
  説明文（ja / en-US）に規約・プライバシーのリンクを追記（**API は `GET_COLLECTION` 不可で
  ローカライズ ID を列挙できず自動化できない**）／**ASC 上のバージョン文字列を 1.0.2 → 1.0.3 に変更**
  （しないと build 8 を選択できない）／App Review Notes の貼り付け（**通報・ブロックへのタップ手順を
  必ず含める**。2回目のリジェクトはここに到達できなかったのが原因）／Resolution Center への返信。
  文面とチェックリストは `docs/app-review-notes-1.2-ugc.md`、日次の通報対応手順は
  `docs/moderation-runbook.md`。
  **既知の未解決**: 既存UIテスト4件が失敗（3件はスプリント18のヘッダー改修＝前提22 に追随していない
  古いアサーション、1件は本番サーバー依存のE2E）。今回の変更が原因ではないため範囲外として未修正。
  スプリント19の evaluator 検証も未実施のまま。
- 2026-09-04: App Store 用マーケティングスクショ 合成デッキ作成（コーディネーター、
  `/app-store-screenshots` + `/ios-screenshot-shoot` スキル）。既存の App Store スクショが
  端末素のUIキャプチャだったため、広告的な合成デッキを新規作成。
  - **撮影**: 現ビルド（HEAD 相当）で ja / en 各5カット（today / timeline / menu /
    notifications / plus）を撮り直し。`tools/screenshot-shoot/flows/capture-full.yaml`
    （maestro、オンボーディング〜回答〜5カット一気通し）＋ 起動フラグ
    `-SameQUseLocalBackend -SameQScenario expiring -SameQFakePlus -SameQFakePlusTrial`。
    生キャプチャは `~/Desktop/SameQ-screenshots-2026-09-04/raw/{ja,en}/`。
  - **シード英語化**（commit `8b51128`、generator=MiniMax-M3 → evaluator 検証済み）:
    en 端末でも LocalBackend のお題文・お知らせが日本語固定だった問題を修正。
    `SeedData.json` prompt_001 に `textEn`、`SeedCatalog` が `!L10n.isJapanese` で英語採用、
    `LocalBackend.announcements(locale:)` が `en` で "Welcome to SameQ"。ユニット 230/230。
  - **合成エディタ**: `tools/app-store-screenshots/`（Next.js、`/app-store-screenshots`
    スキルの template）。テーマ `sameq-editorial`（クリーム地 `#F4EBDD` ＋グリーン
    `#3F7D57`、`src/lib/constants.ts` に追加）、5スライド device-bottom、見出し日英2行。
    `EXPORT_SIZES.iphone` は 6.9"（1320×2868）のみに絞ってある（書き出し高速化。ASC は
    この1サイズで全 iPhone 枠に適用可）。**このディレクトリは未コミット**（`node_modules`
    含む・約22MB。デッキ確定後にコミット判断）。
  - **書き出し済み**: `~/Downloads/sameq-ios-iphone-20260904-1921.zip`
    （`ios/iphone/1320x2868/{ja,en}/01〜05-device-bottom.png`、計10枚）。
  - **⚠️ 申し送り（重要）**: この合成スクショは **build 6 が App Store 承認されるまで
    アップロードしない**。審査待ち／審査中はスクショが編集ロックされ、差し替えるには
    審査を取り下げ→再提出（順番待ちやり直し）になるため。build 6 承認後に、ライブ版の
    スクショをこの zip の中身で差し替える（メタデータのみ更新・バイナリ再提出不要）。
    現状 attach 済みの素キャプチャは審査を通る品質なので急がない。
- 2026-09-04: App Store 初回審査リジェクト（2.1a）対応（コーディネーター）。Apple が
  `1.0 (1)` を Guideline 2.1(a) でリジェクト。理由はレビュー中のオンボーディング通知許可画面で
  「セッションが切れました」（HTTP 401）が出て審査続行不能。調査（Explore ×3）の結論:
  審査対象の `1.0 (1)` は `edb8f25`（tokenBox 反映漏れ修正・2026-08-27）の**前日 2026-08-26 に
  アーカイブされた古いバイナリ**（版数を 1.0 に上げた `cb87531`・唯一の App Store 準備コミット
  `3ee1837` がどちらも 8-26）。修正チェーン（`edb8f25` → `8ad321a` ensureFreshSession →
  `59ffdd9` 50分ごと更新）は現行 HEAD に全て健在。**evaluator が新規インストールからの
  オンボーディング完走を iPhone（iPhone 17 Pro Max / iOS 26.5）と iPad（iPad Air 11・iPhone 互換
  モード）の両方・通知許可の許可/あとで両分岐で再確認、全ログ横断 4xx/5xx = 0**
  （`.product/sprints/12-server-connection/eval-appstore-resubmit.md`）。**対応方針（ユーザー確定）**:
  コード無変更で `CFBundleVersion` を 5→6 のみバンプ（内容は TestFlight 承認済み build 5 と同一）、
  版数は 1.0.2 据え置き。README 更新・commit・push（`ebcbd98`、コーディネーターが直接 =
  ドキュメント＋メタデータのみ）。運営お知らせは build 5 と機能差ゼロのため新規行を投入せず
  （CLAUDE.md の「黙って省略しない」に従い明示）。`xcodebuild archive` → `-exportArchive`
  （ExportOptions method=app-store-connect, ASC API キー `AuthKey_BR882VJ4P8.p8`）→
  `xcrun altool --validate-app`（VERIFY SUCCEEDED）→ `--upload-app`（UPLOAD SUCCEEDED、
  Delivery UUID `fab86ebf-a147-43a1-9386-ca95a6f5a7d5`）。**残り（ASC GUI 手作業）**:
  build 6 の処理完了待ち → リジェクト済みバージョン `1.0` の版数を `1.0.2` に変更して build 6 を
  選択・審査へ再提出 → Resolution Center に返信（下書き
  `scratchpad/apple-reply.md`：原因＝既知バグ・審査対象ビルドの翌日修正済み・iPhone/iPad で
  クリーンインストール完走確認・再審査依頼）。memory `testflight_stale_session_expired_bug.md` に
  「『セッションが切れました』が出たら、まず提出/配信済みビルドが修正より古くないかを最優先で
  疑う」を追記。
- 2026-08-31: TestFlight外部テスト仕上げ（コーディネーター）。ローカルの`Info.plist`/`project.yml`が
  未コミットのまま`CFBundleVersion: 3→4`になっていた誤りを、実際にアップロード済みの最終ビルド
  `5`（Englishローカライゼーション込み・承認済み）に合わせて修正・commit・push（`e6ed1f9`、
  generator=MiniMax-M3へ委任）。TestFlight外部グループ「SameQ Beta」を確認したところbuild 5/3とも
  承認済み・公開リンク`https://testflight.apple.com/join/xv7kJFRm`有効・利用実績3セッション、と
  既に完了済みだった。「テスト情報」に英語が入力できない不具合を調査 — 原因は
  Info.plistのEnglishローカライゼーション宣言とTestFlightの「ベータ版アプリ情報」言語追加が
  無関係の別ステップだったこと（「英語（アメリカ）を追加」を誰もクリックしていなかった）。
  英語ロケールを追加し説明文を英訳して保存。Devpost `submission-statement.md`のTestFlightリンクを
  ログイン必須の内部URLから公開リンクに修正（generator委任）。v1.0（build 1）はまだ
  `WAITING_FOR_REVIEW`のままで、App Store Connectの仕様上、審査待ち中は次バージョンを提出できない
  ためv1.0.2のApp Store提出は保留（技術的制約）。サポートサイト
  （別リポジトリ`nakakei6439/nakakei6439.github.io`の`sameq/index.html`）に
  TestFlightベータ参加への導線セクションを追加。
  **⚠️申し送り: このベータ告知セクションは、ベータテスト終了・App Store正式公開後に
  削除して元に戻すこと**（`sameq/index.html`内にTODOコメントあり）。
- 2026-08-30: 緊急対応 3 件同時（generator / attempt 1）。TestFlight フィードバック 3 件（feedback ① 通知→「いまはお題がありません」 / ② 「セッションが切れました」 / ③ 「お題が違う/書けない」）を調査し、根本原因を 2 段階で特定。**第一段階**（Swift 修正）: ① `NotificationTimePicker.pickNextDate` に `earliestFireDate` 引数追加で 28h 有効 / 24h 周期の 4h オーバーラップを避けた通知発火 / ② `AppSession.refresh()` に 50 分間隔の `ensureFreshSession()` ガード追加で access_token 失効対策 / ③ `TodayPromptView.answeredSection` に「次のお題は新しい一日に届きます」ヒントカード追加。**第二段階（真の根本原因）**: App Store Connect API (`/v1/apps/6805425491/betaFeedbackScreenshotSubmissions`) で 3 件を取得・スクショをダウンロードし内容を直接確認、19:27 JST の実機検証で「いまはお題がありません」固定を再現。`prompts` テーブルを直接 SELECT すると day 30 prompt が入っていない → `supabase db query` で `select public.ensure_todays_prompt()` を実行すると `23P01 conflicting key value violates exclusion constraint "prompts_no_overlap"` で失敗していることを発見。`prompts_no_overlap` EXCLUDE 制約と 28h 有効プロンプトの 4h オーバーラップ設計が両立していなかった。**修正**: `supabase/migrations/20260830000014_fix_ensure_todays_prompt_overlap.sql` で `ensure_todays_prompt()` を再定義、INSERT 直前に「直前プロンプトの `ends_at` を新プロンプトの `starts_at` に切り詰める」前処理を入れて overlap を解消。マイグレーション 14 を `supabase db push --linked` でリモートに適用後、関数を直接実行して `prompt_20260830` が active で入ることを確認。`update public.prompts set ends_at = v_starts_at where ends_at > v_starts_at and starts_at < v_starts_at` で 1 行 truncate されて day 29 は 28h → 24h に短くなった。**テスト追加**: `SameQTests/NotificationSchedulingTests.swift` に 4 件の境界値テスト（ギャップ回避 / 23:30 翌日 / earliestFireDate = now 互換性 / ウィンドウ外強制翌日）。`AnnouncementTests.test03_localBackendAnnouncementsReturnsSample` の pre-existing ビルドエラー（`announcements(locale:)` 引数渡し忘れ）もついでに修正。**実機検証**: iPhone 17 Pro Max (UDID `00008150-000854443E03401C`、iOS 26.6.1) に `xcrun devicectl device install app` でデバッグビルドをインストール・起動、`-SameQDebugOverlay` 付きで動作確認。**提出準備**: Info.plist を 1.0.1/2 → 1.0.2/3 にバンプ、README に v1.0.2 セクション追加、`announcements` テーブルに v1.0.2 を ja/en 別行で投入。**TestFlight アップロード**: `xcodebuild archive` で Release アーカイブ → `xcodebuild -exportArchive` + App Store Connect API キー (`AuthKey_BR882VJ4P8.p8`) で 2 回アップロード成功。build 3 (v1.0.2) と build 4 (v1.0.2 + CFBundleLocalizations=[ja,en] + DEVELOPMENT_LANGUAGE=ja) を App Store Connect に登録、build 4 は 21:21 JST に ExportArchive Succeeded。**xcodegen で project.yml を更新**: `DEVELOPMENT_LANGUAGE: ja` 設定 + `CFBundleLocalizations: [ja, en]` を Info.plist に注入。`project.yml` を `info.properties` のソース・オブ・トゥルースとして再生成し `.xcodeproj/project.pbxproj` の `knownRegions = (Base, en,)` に反映。**Shipaton 準備**: RevenueCat Shipaton 2026 (締切 9/30) に向けて `.product/shipaton-2026/submission-statement.md`（Devpost 説明文ドラフト、約 800 words、子の言葉 "AI には愛がない" / "AI が作ったってわかる" を What I learned に引用）と `.product/shipaton-2026/prep-checklist.md`（9/1〜9/29 週次タスク）を作成。**最終検証**: フルユニットテストスイート実行 228/228 PASS（7.7 秒、SameQUITests は別工程）。**思想メモ**: `.product/ideas/like-ranking-question-curation.md`（sprint19 相当の「いいねランキング → お題投稿権」機能、子の言葉の冒頭引用、思想 7 つの懸念）。[`.tmp/HANDOFF-2026-08-30-to-2026-08-31.md`](.tmp/HANDOFF-2026-08-30-to-2026-08-31.md), [`docs/debug-runbook-testflight-20260830.md`](docs/debug-runbook-testflight-20260830.md)
# PROGRESS

## 再開手順（新しいセッションで戻ってきた場合）
1. このファイルをまず読む。調査・仕様の読み直しはしない。
2. 下の「作業単位チェックリスト」で **最初の未完了項目（[ ]）** を探す。
3. 「現在の状態」の該当行にある関連ファイル・IDを見て、そこから続ける。
4. 各作業単位が完了したら、このファイルの該当チェックボックスと「現在の状態」を**即座に**更新してコミットする。

### ⚠️ generator の起動方法（重要）
generator（MiniMax-M3）は **Agent ツール経由の自動呼び出しでは MiniMax-M3 に接続できません**
（サブエージェントは同一プロセスで動き、Claude Code にはサブエージェント単位で
エンドポイント／認証を差し替える仕組みが無い。親が OAuth なら `api.anthropic.com` に
`MiniMax-M3` を投げて 404）。

**最も簡単な起動方法（推奨）:**
```bash
gen
```
`~/.local/bin/gen` が env 変数をすべて自動で設定する。**このスクリプトが正典。**
フルコマンドを手で書くときも `~/.local/bin/gen` の中身と一字一致させること
（過去に `[im]` サフィックスや窓2変数の欠落でハマった）:
```bash
env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_AUTH_TOKEN \
  ANTHROPIC_BASE_URL='https://api.minimax.io/anthropic' \
  ANTHROPIC_AUTH_TOKEN="$MINIMAX_API_KEY" \
  ANTHROPIC_MODEL="MiniMax-M3" \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000 \
  CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1 \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000 \
  claude --agent generator
```
- `ANTHROPIC_MODEL` にサフィックス（` [im]` 等）を付けない。`-p` モードで `--agent` の
  システムプロンプトが読まれず、実作業ゼロで exit 0 になる。
- 窓2変数（`CLAUDE_CODE_MAX_CONTEXT_TOKENS` / `CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT`）
  は CC 2.1.259+ の未知モデル 200k 窓強制を外すため必須。
- コーディネーターセッションから 1 回だけ回すときは、上記に
  `-p "<指示>" --permission-mode bypassPermissions --output-format text` を足し、
  `Bash` ツールの `run_in_background: true` で起動する（`&` や `nohup` は使わない）。

理由の詳細は `~/.claude/agents/generator.md` の冒頭と `~/.claude/plans/planner-calm-quiche.md` §3。

### 🌙 夜間無人実行（残りスプリントの全自動ループ）
`scripts/autoloop.sh` が `.product/state.json` の `status` を見て、generator（MiniMax-M3・非対話）と
evaluator（Sonnet・非対話）を自動で交互に起動し、スプリント11まで自動で進める。合格したら次の
スプリントへ自動で進み（`currentSprint`/`attempt`/`status` を更新）、各ステップ後にローカル
git commit（push はしない）。`blocked`（generatorが同じ指摘で複数回失敗）や全スプリント完了で自動停止。

**起動:**
```bash
cd /Users/nakagawakeita/Products/iOSApp/SameQ
nohup caffeinate -i ./scripts/autoloop.sh > .product/autoloop-logs/main.log 2>&1 &
```

**停止:**
```bash
pkill -f autoloop.sh
```

**ログ確認:** `.product/autoloop-logs/`（`main.log` が全体ログ、`generator_*.log` / `evaluator_*.log` が個別ログ）

詳細は `scripts/autoloop.sh` 内のコメントを参照。**初回は少数回だけ様子見で走らせ、`state.json` の
遷移とログが期待通りか確認してから本格的な夜間実行に委ねること。**

**⚠️ autoloop.sh 実行中は、このディレクトリで別セッション（スクリーンショット撮影・手動デバッグ等）を
同時に開かないこと。** 理由: (1) 未コミットの変更が混ざり generator/evaluator の diff が汚染される、
(2) 同じシミュレータに対して同時に `xcodebuild test` を実行すると両方が不安定化・遅延する
（2026-08-27 の sprint12 タイムアウトインシデントで実際に発生し、作業ツリーへの他セッション由来
ファイルの混入も確認された）。手動作業をしたい場合は `git worktree add ../SameQ-adhoc <branch>` で
別ディレクトリに作業ツリーを作ってそちらで行い、シミュレータも autoloop 既定（"iPhone 17"）とは
別の名前・destinationを使うこと。

**2026-08-24時点の申し送り**: スプリント06 attempt 7 完了・evaluator 引き渡し待ち（詳細下記・[`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 7」）。eval-6.mdの指摘[1]（`lastPrepareAttemptAt` がプロセス内メモリのみでアプリ再起動をまたがない）に対応し、`PersistedState`（`state.json`、schemaVersion 4→5）へ永続化した。ユニット77件・シミュレータUI35件・実機のSprintSixAcceptanceTests 4件すべて成功。実機で一時テストを使いeval-6.mdの再現手順そのものを確認し、修正前67.41秒→修正後2.83秒への改善を直接確認済み（詳細は下記「スプリント06 attempt 7」節）。
- スプリント06は既に6回不合格になっている（attempt 1〜6、詳細は下の該当節）。同じ轍を踏まないよう、各attemptの不合格理由には必ず目を通すこと
- 実機で`SprintSixAcceptanceTests.test04`が32件中30件しか既読にならず一度失敗したが、attempt 7の変更を`git stash`で完全に除去したbaseline（`92bc0f2`）でも同じく30/32で失敗することを確認済み。**attempt 7の変更とは無関係の既存の脆さ**なので今回は手を加えていない（次スプリントの材料として持ち越し）

## メタ情報
| 項目 | 値 |
|---|---|
| アプリ名 | SameQ |
| ローカルリポジトリ | `/Users/nakagawakeita/Products/iOSApp/SameQ` |
| GitHubリポジトリ | `nakakei6439/SameQ`（Private） |
| 製品仕様書 | [`.product/spec.md`](.product/spec.md)（機能一覧34件、スプリント11本） |
| 開発ハーネス | planner（Opus）→ generator（MiniMax-M3）→ evaluator（Sonnet） |
| generator 起動方法 | **ターミナルから env 変数付きで起動**（Agent ツール経由では MiniMax-M3 に接続不可。下記参照） |

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
- **フェーズ**: スプリント08（ランダム通知）**合格・完了**（attempt 2、2026-08-25）。F24/F25（8:00〜22:00のランダム通知予約、通知タップでの画面遷移、拒否時の通常利用）を実装。attempt 1はevaluatorが「通知タップの実経路が常に`.today`固定で`.timeline`ケースが到達不能」と指摘し不合格（[`eval-1.md`](.product/sprints/08-random-notifications/eval-1.md)）。attempt 2で`RootView`に`pendingNotificationTap`を追加し`session.user`/`screen`/`myPost`の準備が整ってから遷移先を決める設計に修正。evaluatorが`xcrun simctl push`による本物の通知配信とバナーへの実タップ（アプリを終了させずバックグラウンドのまま）で、未回答→今日のお題画面／回答済み→タイムライン直接オープンの両方を直接確認し合格（受け入れ条件6/6、クラッシュ0、回帰18/18＋ユニット113/113、使用性4）。詳細は [`eval-2.md`](.product/sprints/08-random-notifications/eval-2.md)。
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
- **次にやること**: **スプリント09（お題の自動生成、F26/F27）の実装（generator）**。
  スプリント08は2026-08-25にevaluatorの検証で合格し完了した。受け入れ条件は
  `.product/spec.md` 245〜251行を参照（1日1回の自動生成、生成条件を満たさない
  候補の破棄、生成失敗時のフォールバック、世界共通であることの担保）。
- **スプリント06 attempt 5 の修正内容（generator、2026-08-20）**: eval-4.md の指摘[1]
  （受け入れ条件4の未実装）に対応。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 5」を参照。
  1. **`AppSession.openTimeline()` が、世界タイムライン（`fullScreenCover`）を開く前に、
     まだ読んでいない候補の言語のうち `.supported`（モデル未ダウンロード）のものを
     `Translator.prepareIfNeeded(sourceLanguageCode:)` で能動的にダウンロードする**設計に
     変更（`prepareTimelineLanguagesIfNeeded`、予算90秒）。この時点ではまだ今日のお題画面
     （非モーダル）にいるため、OSの確認シートが出ても閉じて困る `fullScreenCover` が無い
     （attempt 3 の致命的症状の再発防止）。ダウンロード中は「世界の回答を読む」ボタンを
     「準備中…」にする（`AppSession.isPreparingTimeline`）。ダウンロードが間に合わなかった
     言語は従来どおり一時的な失敗として読み飛ばし、既読にしない（次回また挑戦できる）。
  2. **【最重要】実機で `SessionRequestQueue` の致命的な欠陥を発見・修正**。
     `session.prepareTranslation()` を呼ぶ経路を実機で試したところ、`perform` の呼び出しが
     15分待っても一度も返らない現象に遭遇。原因は `runWithJobTimeout` が `withTaskGroup`
     （構造化並行性。キャンセル済みでも子タスクの完了を必ず待つ）を使っていたため、
     `session.translate(_:)` と違い `cancel()` に応答しない `prepareTranslation()` では
     `jobTimeoutSeconds` が名目だけになっていたこと（attempt 3 から存在した潜在バグ。
     `translate()` では実害が無かったため今回まで見つからなかった）。`body` を独立した
     非構造化 `Task` として起動し、タイムアウト用の別 `Task` と「どちらが先に解決するか」
     だけで競走させる設計に変更し、呼び出し元が確実に解放されるようにした。
     `SessionRequestQueueTests` に新規1本追加（計7本）、既存6本も全通過。
  3. Apple Developer Forums（スレッド783311）を調査し、`prepareTranslation()` も
     モデル未取得ならOSの確認シートを出しうることを確認（「シートを完全に無くす方法」は
     無いという attempt 4 の判断は正しかった）。そのため「シートを出させない」のではなく
     「シートが出ても実害の無い場所・タイミングで出す」方針にした。
  - **フルテスト実行結果（他プロセス非併走の単独実行、シミュレータ）**: ユニット72本＋UIテスト35本（新規: `SessionRequestQueueTests` 1本、`TranslatorAvailabilityTests` 3本、`TranslatorFakeModeTests` 2本、`AppSessionTranslationTests` 3本、`SprintSixAcceptanceTests` 1本）、**合計107件すべて成功**。
  - **実機での確認（部分的）**: XCUITest の automation mode が2回とも `Timed out while
    enabling automation mode.` で有効化できず（eval-3.md・eval-4.md と同じ既知の問題）、
    指でのタップ操作の自動確認はできなかった。代わりにホストアプリのプロセス内で本物の
    `TranslationHostView` を実ウインドウに載せ `AppSession` でタイムラインを読み切る手法
    （一時テスト・確認後削除）で2回検証。`SessionRequestQueue` の修正前は15分・10分待っても
    応答が無く、修正後は2回とも63〜75秒で `openTimeline()` が完了し10秒程度で28件を
    固着0で読み切った。この実機で `.supported` だった `pl`/`th`/`id` のうち、**`id` は
    2回ともダウンロードに成功し実際に読めるようになった**（受け入れ条件4が機能した実例）。
    **`pl`/`th` は2回とも90秒の予算内で完了せず未読のまま残った**（既読にはしていないので
    次回再挑戦できる設計どおり）。OSの確認シートが実際に画面に出たかどうか、出た場合に
    シートが残ったまま `fullScreenCover` を開こうとしたときの挙動は、自動化ツールでは
    画面を見る手段が無く**確認できていない**（`devicectl` は実機のスクリーンショット取得
    に非対応）。この最後の1点は人による実機操作でしか確認できない。
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
- [x] 評価（evaluator、attempt 3）— 2026-08-19 **不合格**。受け入れ条件 2/7（1件は評価不能、4件は未達）。iPhone 17 Pro Max 実機で `-SameQFakeTranslate` を付けずに検証（独自 XCUITest D01〜D06 ＋ `LanguageAvailability` の直接プローブ2本）。**実機で翻訳そのものは正しく動く**（ja端末で独語・伊語の回答が自然な日本語に、en端末で21件すべて自然な英語に。原文のまま出た回答は0件、ちらつき0件、`zxx` は0回表示、お題も端末言語に追従）。attempt 2 の致命的エラー `Attempted to use TranslationSession after the view…` は1度も観測せず、セッションのキャッシュ撤去は効いている。**しかしタイムラインは4回中4回とも途中で固着し読み切りに到達しない**（ja: 5件/6件/7件で停止、en: 21件で停止。90秒待っても復帰しない）。原因は `Translator.isSupported` が `.supported`（モデル未ダウンロード）を `.installed` と同じ扱いにしていること。実機の実測では ar/pl/ru/th が ja/en いずれ向けも未ダウンロードで、同梱シードにこの4言語が各1件ずつ入っているため必ず踏む。踏むとOSの「翻訳／必要なダウンロード」シートが出てタイムラインが閉じ、投稿の言語名（「ポーランド語」）まで画面に出る。クラッシュ0、データ整合性OK（実機の `state.json` を直接確認。schemaVersion 4、翻訳結果は永続化されない）、回帰は実機5/5＋シミュレータ90/90、使用性2。[`eval-3.md`](.product/sprints/06-translation/eval-3.md) / スクリーンショット [`eval-3-stall.png`](.product/sprints/06-translation/eval-3-stall.png)
- [x] 修正（generator / attempt 4）— 2026-08-19。**修正済み・再評価待ち**。eval-3.md の[1][2]に対応。(1) `Translator.isSupported(sourceCode:)`（`Bool` 1軸）を廃止し、`LanguageAvailability.Status` を3値のまま扱う `availabilityStatus(sourceCode:)` に変更。`translate()` は `.installed` のときだけ `sessionQueue.perform`（実際の `session.translate(_:)`）へ進み、`.supported`（モデル未ダウンロード）のときは `session.translate(_:)` はおろか `prepareTranslation()` も一切呼ばず `.unavailable(permanent: false)`（一時的な失敗。既読にしない）として読み飛ばす。`prepareTranslation()` を明示的に呼ぶ案（eval-3.md のもう1つの提案）は、それもモデル未取得ならOSシートを表示する点は同じで、シートを正しい階層（`fullScreenCover` の中）から出すには `TranslationHostView` の常駐位置の設計変更が要り実機でしか検証できないリスクがあるため見送った（判断理由は self-review.md 参照）。これにより受け入れ条件4の前半（アプリが能動的にダウンロードして見せる）は未実装のまま。(2) `LanguageAvailability.status` を差し替え可能にする `LanguageAvailabilityProviding` プロトコルを追加し、`TranslatorAvailabilityTests`（新規4本）で `.supported` のとき `translator.configuration` が一度も更新されない（＝セッションを一切要求しない）ことを直接確認。`-SameQFakeTranslate` にも疑似言語コード `qtd`（`sameQ_download_pending_test_marker`）を追加し同梱シードに1件追加。ユニット6本・UIテスト1本を新規追加（`SameQTests` 63本 ＋ `SameQUITests` 34本）。シミュレータのフルテストスイート **97/97 全件成功**。実機（iPhone 17 Pro Max）向けビルド・インストール成功、ロック解除済みを確認したうえで、`-SameQFakeTranslate` を付けない `SprintSixAcceptanceTests`（3本、うち新規の実機ストール再現テスト含む）を実機で実行し **3/3 全件成功**（本物の Apple Translation Framework で32件の同梱シードを82秒で読み切り、`timeline.close` が押せる状態のままでタイムラインが閉じることは一度も起きなかった）。実機でユニット63本、コア/BAN回帰（`SprintOneAcceptanceTests`・`SprintFiveAcceptanceTests`）12本も実行し全件成功。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 4」。
- [x] 評価（evaluator、attempt 4）— 2026-08-19 **不合格**。受け入れ条件 5/7（1件未達・1件評価不能）。iPhone 17 Pro Max 実機（iOS 26.6）で `-SameQFakeTranslate` を付けずに本物の Apple Translation Framework を実行し、`TranslationHostView` を実ウインドウに載せて `AppSession` でタイムラインを読み切る独自テスト（実機が施錠されXCUITestが起動できなかったため、タッチ操作の代わりにホストアプリ内でアプリの実処理を実行）＋ `LanguageAvailability` の直接プローブ4本、シミュレータで画面操作テスト8本とフルスイート97/97で検証。**attempt 3 の不合格理由は解消**（OSの「翻訳／必要なダウンロード」シートは1度も出ず、実機で ja 28件・en 26件を固着0で読み切り。1件あたり0.41〜1.57秒、ちらつき0、`zxx`/`qtd`/BAN投稿0回表示、アラート0、`Attempted to use TranslationSession after the view…` 0回）。**残る不合格理由は受け入れ条件4（spec.md 197行「翻訳モデルが端末に無い場合は初回のみ準備中の表示が出て完了後に読め」）が未実装であること1点**。モデル未ダウンロードの言語（この実機では ja端末で pl/th、en端末で ar/pl/ru/th）の回答は準備中表示もダウンロードも無いまま毎回スキップされ、実機の `state.json` でも未読のまま残る（＝永久に読めない）。spec.md は条件3（恒久的に翻訳できない）と条件4（モデルが無いだけ）を書き分けているため、「スキップ」を条件4の充足とは解釈しない判断。モデルが1つも入っていない端末では外国語の回答がほぼ全滅する点も理由。クラッシュ0、データ整合性OK（恒久スキップは既読・一時スキップは未読、翻訳結果は非永続、schemaVersion 4）、回帰は抜き取り8件＋フルスイート97/97、使用性3。受け入れ条件7（機内モード）は端末設定の変更のため評価不能。[`eval-4.md`](.product/sprints/06-translation/eval-4.md)
- [x] 修正（generator / attempt 5）— 2026-08-20。**修正済み・再評価待ち**。eval-4.md の指摘[1]（受け入れ条件4の未実装）に対応。`AppSession.openTimeline()` が世界タイムラインを開く前に `.supported`（モデル未ダウンロード）の言語を能動的に `session.prepareTranslation()` でダウンロードする設計に変更（開く前＝まだ非モーダルなお題画面にいるため、OSの確認シートが出ても閉じて困る `fullScreenCover` が無い）。実機で `SessionRequestQueue` の致命的な欠陥（`withTaskGroup` のタイムアウトが `prepareTranslation()` には実効を持たない）を発見・修正。フルテスト107本（ユニット72＋UI35）全件成功。実機での確認は部分的（1言語のダウンロード成功を確認できたが、他2言語は90秒予算内で未完了。XCUITest automation mode不調のため指でのOS確認シート応答は未確認）。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 5」。
- [x] 評価（evaluator、attempt 5）— 2026-08-20 **不合格**。受け入れ条件 5/7（1件未達・1件評価不能）。実機で `openTimeline()` を2回計測すると round1 62.1秒・round2 61.3秒とも同じだけ待たされ、しかも待った先で新しく読める回答は0件（`pl`/`th` は2回とも `.supported` のまま）。generator が唯一の肯定的証拠として挙げた `id`（インドネシア語）のダウンロード成功は、`id` が有効なお題の候補32件に含まれないため成立しないと判明。原因は「試して駄目だった」を覚える場所が一切無く、モデル未ダウンロード言語が残る限りタイムラインを開くたびに毎回ゼロから同じ待ちを繰り返すこと。基準5（使用性）も2点（`submit()` が内部で `openTimeline()` を待つため投稿ボタンが最大約120秒「送信中…」のまま）。回帰は抜き取り5件＋フルスイート107/107。[`eval-5.md`](.product/sprints/06-translation/eval-5.md)
- [x] 修正（generator / attempt 6）— 2026-08-21。**不合格**。eval-5.md の指摘[1][3]に対応。`Translator` に言語別の最終準備試行時刻と5分の再試行クールダウンを追加し、`.supported` のままダウンロードが完了しなかった言語はクールダウン中は再試行せず即座に返る設計に変更（`lastPrepareAttemptAt` / `needsPreparation(sourceLanguageCode:)`）。`AppSession.submit(body:)` が `openTimeline()` の完了を待たずバックグラウンドTaskへ分離（`pendingOpenTimelineTask` / `waitForPendingTimelineOpen()`）し、投稿ボタンが翻訳準備の待ちを背負わなくなった。generatorのCodex sandboxではCoreSimulatorServiceへ接続できずビルド・テストが未実行だったため、coordinatorがsandbox外で改めて実行し確認: 指定ビルド **BUILD SUCCEEDED**、シミュレータのフルスイート（単独実行）で **ユニット75件+UI35件=110件全件成功**。詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 6」。
- [x] 評価（evaluator、attempt 6）— 2026-08-21 **不合格**。今回初めて実機の画面ロックが解除されXCUITestのautomation modeが機能した。投稿ボタンの応答性（eval-5指摘[3]）は解決を確認（投稿から「あなたの回答」表示まで約2秒）。同一プロセス内での2回目以降のタイムライン起動も解決（61.33秒→1.62秒→1.63秒）。**しかしアプリを終了して数秒後に開き直すと、実時間ではクールダウン期間内（5分未満）にもかかわらず67.41秒の待ちが再発**することを実機で実測・再現。原因は `Translator.lastPrepareAttemptAt`（クールダウンの記録）がアプリプロセス内メモリのみに保持され `state.json` へ永続化されておらず、アプリ再起動のたびに `Translator` が作り直されて記録が失われるため。安定性（クラッシュ0）・データ整合性・回帰（実機2件＋シミュレータ5件）は合格基準を満たす。使用性は2点（閾値3未満）。[`eval-6.md`](.product/sprints/06-translation/eval-6.md)
- [x] 修正（generator / attempt 7）— 2026-08-24。eval-6.md の指摘[1]に対応: `lastPrepareAttemptAt`（言語コードごとの最終ダウンロード試行時刻）を `PersistedState`（`state.json`、schemaVersion 4→5、`decodeIfPresent ... ?? [:]` の移行パターンを踏襲）へ永続化した。新しいプロトコル `TranslationAttemptPersisting`（`Backend` が継承）を介して、書き込みは常に単一のアクター（`LocalBackend`）へ集約し、`Translator` が独自に `LocalStore` へ直接読み書きして競合する事態を避けた。`AppSession.init` はデフォルトで自分が使う `backend` インスタンスを `Translator(attemptPersistence:)` へそのまま渡す。`-SameQResetState` は既存の全状態リセットの仕組みに乗るので確実にリセットされる。ビルド・テスト結果: シミュレータ `xcodebuild build` **BUILD SUCCEEDED**、ユニット77件（うち2件新規: アプリ再起動をシミュレートする `AppSessionTranslationTests.testPreparationCooldownSurvivesSimulatedAppRelaunch` / `testPreparationRetriesAfterCooldownElapsesAcrossSimulatedAppRelaunch`）・シミュレータUI35件、すべて成功（他プロセス非併走の単独実行）。実機（iPhone 17 Pro Max、ロック解除・automation mode有効）でも `build` 成功、`SprintSixAcceptanceTests` 4件すべて成功。実機の一時テストでeval-6.mdの再現手順そのものを確認し、初回62.97秒→アプリ終了後2秒で再起動して2.83秒、という直接的な改善を実測（詳細は [`self-review.md`](.product/sprints/06-translation/self-review.md) の「attempt 7」）。`SprintSixAcceptanceTests.test04`が実機で32件中30件既読という既存の脆さを発見したが、attempt 7の変更を除去したbaselineでも再現するため無関係と判断し対応せず。

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
- [x] 実装（generator）— attempt 1、unit 9本 + UI 6本、フルスイート 0 failures、self-review.md 済み
- [x] 修正（generator / attempt 2）— 2026-08-25。eval-1.mdの指摘（通知タップの実経路が常に`.today`固定で`.timeline`ケースが到達不能）に対応。`RootView`に`pendingNotificationTap`を追加し、`session.user`/`screen`/`myPost`の準備が整ってから`attemptDispatchPendingNotificationTap()`が遷移先を決める設計に変更。Debug限定`-SameQSimulateNotificationTap`を追加。[`self-review.md`](.product/sprints/08-random-notifications/self-review.md)
- [x] 評価（evaluator）— 2026-08-25 **合格**（attempt 2）。受け入れ条件6/6。条件4は、evaluatorが`xcrun simctl push`による本物の通知配信＋通知バナーへの実タップ（アプリはバックグラウンドのまま終了させない）で、未回答→今日のお題画面／回答済み→タイムライン直接オープンの両方を実際に確認。クラッシュ0・データ整合性OK（schemaVersion 5）・回帰18/18＋ユニット113/113・使用性4。[`eval-2.md`](.product/sprints/08-random-notifications/eval-2.md)（attempt 1 不合格の詳細は [`eval-1.md`](.product/sprints/08-random-notifications/eval-1.md)）

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

### スプリント13: サーバー側で担保する制限・停止・保持
含む機能: F36
- [x] 実装（generator）— 2026-08-27。新規マイグレーション `supabase/migrations/20260827000006_server_enforcement.sql`（`rate_limit_events` テーブル、`consume_rate_limit()` / `current_user_status()` / `current_server_time()` / `my_viewed_posts()` / `app_purge_expired_safety_logs()` / `delete_my_account()` RPC・関数群）。`Backend.currentServerSideStatus()` をプロトコル要求に追加し `LocalBackend` は `"active"` 固定・`SupabaseBackend` は `current_user_status` RPC を呼ぶ。`SupabaseBackend.setLike` / `reportPost` から process-local の `RateLimiter` を撤去し `consume_rate_limit(action, max, window_seconds)` RPC を呼ぶ `checkRateLimit(action:settings:)` に置換。`SupabaseBackend.deleteAccount()` から `client.rpcVoid(function: "delete_my_account")` を呼ぶように変更（`auth.users` + `public.users` の cascade 削除）。`AppSession.start()` 冒頭で `backend.currentServerSideStatus()` を呼び、`"banned"` のとき `.banned` 画面に固定（`-SameQBanned` Debug 経路は温存・通信失敗時は fail-open）。`SprintThirteenAcceptanceTests` を新規追加（3本）。ユニット 166/166 + UI SprintThirteen 3/3 + SprintTwelve 3/3 + SprintEleven 4/4 = 10/10 全件成功（142.8 秒・TEST SUCCEEDED）。Debug ビルド SUCCEEDED。実機 2 台での e2e（条件 1〜7 の `SupabaseBackend` 経由）は evaluator 担当。[`plan.md`](.product/sprints/13-server-enforcement/plan.md) / [`self-review.md`](.product/sprints/13-server-enforcement/self-review.md)
- [ ] 評価（evaluator）— 受け入れ条件は `.product/spec.md` 320〜331行

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
   **例外（2026-08-27・スプリント14）**: spec.mdの前提条件（変更しない、23行目）が元々「課金はRevenueCat」を明記していたにもかかわらず、スプリント10で外部依存ゼロ方針を優先しStoreKit 2直接実装を選んだ。ユーザー確認の結果、RevenueCatハッカソンへのエントリー要件（SDK経由の課金実績をダッシュボードに反映）を満たす必要があるため、**F37（Plus課金基盤をRevenueCatへ差し替え）に限り、RevenueCat SDK（Swift Package）の追加を認める**。他の機能（翻訳・DB接続等）には引き続き外部パッケージ依存ゼロの方針を適用する。RevenueCat SDK用の公開APIキーは`.env.local`の`REVENUECAT_API_KEY`を参照。
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
- 2026-08-20: スプリント06 評価（evaluator / attempt 5）**不合格**。受け入れ条件 5/7（条件4が未達、条件7は評価不能）、基準5（使用性）も2点で閾値割れ。実機 iPhone 17 Pro Max / iOS 26.6（端末言語 ja）で本物の Apple Translation を実行。**実機が施錠されており XCUITest の automation mode を有効化できなかった**（`Timed out while enabling automation mode.` の直接原因は xcodebuild ログの `The device is passcode protected.`。デベロッパモードは `enabled`、信頼関係も生きており、原因は画面ロックのみ）ため、今回もっとも見てほしかった「OSの確認シートを指でタップして進めたときに `fullScreenCover` が正しく開くか」は**確認できていない**。代わりにホストアプリのプロセス内で本物の `TranslationHostView` を実ウインドウに載せて `openTimeline()` を2回計測した。**不合格の理由は2点**: (1) モデル未ダウンロードの言語（この実機で `pl`/`th`）が未読で残っているあいだ、タイムラインを開くたびに毎回60〜120秒待たされる。実測 round1 62.1s / round2 61.3s（2回目は61秒待った先が「今は新しい回答がありません」）。`prepareTimelineLanguagesIfNeeded` にも `prepareIfNeeded` にも「もう試して駄目だった」を覚える場所が無く、`.supported` は意図的にキャッシュしないため無期限に繰り返す（タイムアウトを縮めた確定的ユニット検証でも3回とも同じだけ待つことを確認）。spec.md 197行「2回目以降は待ちが発生しない」に反する。(2) 条件4の前半（準備中→完了後に読める）が実機で一度も成立していない。60秒待っても `pl`/`th` は `.supported` のままで読めない。**generator の唯一の肯定的証拠だった `id` の実例は成立しない**（`id` の回答は `prompt_002` にしか無く、いま有効な `prompt_001` の候補32件に含まれない。`id` は評価時点でも `.supported` のままで一度もインストールされていない）。さらに `submit()` が内部で `openTimeline()` を待つため、**「投稿する」を押した直後にボタンが約60秒「送信中…」のまま**動かない（進捗表示も中断手段も無い）→ 使用性2点。翻訳そのものは良好（27件すべて自然な日本語・原文のまま表示0件・アラート0・クラッシュ0）。データ整合性OK（恒久スキップ＝既読 / 一時スキップ＝未読、再起動後も保持）、回帰は抜き取り5件（未投稿ロック・空白拒否の日英ダイアログ・BAN画面ボタン0・カード外余白スワイプ/✕不在/いいね82×82・お題常設帯）＋シミュレータのフルスイート **107/107**。ただし `SprintSixAcceptanceTests.test04` はシミュレータの `LanguageAvailability` が全18言語 `.unsupported` を返すため**自明に通っており、条件4を何も保証していない**（evaluator が実測）。次は実機のロックを解除・自動ロックを「なし」にしたうえでの再検証と、待ちの構造の見直し。[`eval-5.md`](.product/sprints/06-translation/eval-5.md)
- 2026-08-19: スプリント06 評価（evaluator / attempt 4）**不合格**。受け入れ条件 5/7（条件4が未達、条件7は評価不能）。実機 iPhone 17 Pro Max / iOS 26.6 で `-SameQFakeTranslate` なしの本物の Apple Translation を実行。**実機が23:00以降ずっと施錠され XCUITest が `The device is passcode protected.` で起動できなかった**ため（計6回試行）、代わりにホストアプリのプロセス内で本物の `TranslationHostView` を実ウインドウに載せ、`AppSession` でタイムラインを読み切る方法で検証した（翻訳・スキップ・既読の実処理は本番と同じ経路。指の操作だけがシミュレータ側）。**attempt 3 の不合格理由（OSのダウンロード確認シートの割り込みでタイムラインが固着・自動で閉じる）は解消**を確認: ja端末28件・en端末26件を固着0で読み切り、シート0回、アラート0、ちらつき0、1件あたり0.41〜1.57秒、お題も端末言語（ja 0.11s / en 1.23s）。`LanguageAvailability` の実測（P4）で `.supported`（未DL）はセッションを一切要求しないことも直接確認した。**不合格の理由は受け入れ条件4の未実装1点**: モデル未ダウンロードの言語（ja端末で pl/th、en端末で ar/pl/ru/th）は準備中表示もダウンロードもなく毎回スキップされ、実機の `state.json` でも未読のまま残る（永久に読めない）。モデルが1つも入っていない端末では外国語の回答がほぼ全滅し、スプリント06の目的が成立しない。データ整合性OK（恒久スキップ＝既読 / 一時スキップ＝未読、翻訳結果は非永続、schemaVersion 4）、回帰は抜き取り8件（未投稿ロック・空白拒否の日英メッセージ・お題常設帯・✕ボタン不在・いいね82×82・余白スワイプ・ブロック一覧・BAN画面ボタン0）＋シミュレータのフルスイート97/97、使用性3。次はスプリント06 attempt 5（受け入れ条件4への対応か、条件そのものの見直し）。[`eval-4.md`](.product/sprints/06-translation/eval-4.md)
- 2026-08-19: スプリント06 修正（generator / attempt 4）。eval-3.md の[1][2]に対応。**修正済み・evaluator の再評価待ち**。(1)【最重要】`Translator.isSupported(sourceCode:)`（`status != .unsupported` の1軸判定）を廃止し、`LanguageAvailability.Status` を3値のまま扱う `availabilityStatus(sourceCode:)` に変更。`translate()` は `.installed` のときだけ従来どおり `sessionQueue.perform`（実際の `session.translate(_:)`）へ進み、`.supported`（この端末ではモデル未ダウンロード）のときは `session.translate(_:)` はおろか `prepareTranslation()` も一切呼ばず `.unavailable(permanent: false)`（一時的な失敗・既読にしない）として読み飛ばす設計にした。eval-3.md が提示したもう1案（`prepareTranslation()` を明示的に呼んでダウンロードする）は、`prepareTranslation()` もモデル未取得ならOSの確認シートを表示する点は同じで、シートを正しい階層（`fullScreenCover` の中）から出すには `TranslationHostView`（`RootView` 背景に常駐）の設計変更が要り実機でしか検証できないリスクがあるため見送った（判断理由は self-review.md の attempt 4 に詳述）。この結果、受け入れ条件4の前半（アプリが能動的にダウンロードして見せる）は未実装のまま。(2) `LanguageAvailability.status` を差し替え可能にする `LanguageAvailabilityProviding` プロトコルを新設し、実際の `Translation.LanguageAvailability` をこれに準拠させた。`TranslatorAvailabilityTests`（新規4本）で `.supported` を注入し、`translator.configuration` が一度も更新されない（＝セッションを一切要求しない）ことを直接確認。`-SameQFakeTranslate` にも疑似言語コード `qtd`（`sameQ_download_pending_test_marker`）を追加し同梱シードに1件追加、`SprintSixAcceptanceTests` の既存アサーションにも組み込んだ。ユニット6本・UIテスト1本を新規追加（`SameQTests` 63本 ＋ `SameQUITests` 34本）。シミュレータでのフルテストスイートを単独実行し **97/97 全件成功**。実機（iPhone 17 Pro Max）向けビルド・`devicectl device install app` 成功。実機の画面ロック状態を `devicectl device process launch` で確認してから（ロック解除済み・自動ロック無効のまま）進め、`-SameQFakeTranslate` を付けない `SprintSixAcceptanceTests`（3本、うち新規の実機ストール再現テスト `test03_realTranslationReadsWholeSeedWithoutStallingOrOSInterruption` を含む）を実機で実行し **3/3 全件成功**。本物の Apple Translation Framework で32件の同梱シード（`ar`/`pl`/`ru`/`th` を含む）を82秒で読み切り、`timeline.close` が押せる状態のままでタイムラインが一度も閉じなかったことを確認した。実機で `SameQTests`（ユニット63本）と、コア/BAN回帰として `SprintOneAcceptanceTests`（5本）・`SprintFiveAcceptanceTests`（7本）も実行し全件成功（計78本を実機で確認。翻訳に無関係な残りのスイートはシミュレータの97/97で確認済み、かつ今回の変更は `Translator.swift`／`SeedData.json`（投稿1件追加）／テストファイルのみでそれらのロジックには触れていない）。次はスプリント06 attempt 4 の evaluator 再評価。[`self-review.md`](.product/sprints/06-translation/self-review.md) の attempt 4
- 2026-08-19: スプリント06 評価（evaluator / attempt 3）**不合格**。受け入れ条件 2/7。iPhone 17 Pro Max 実機（端末言語 ja、英語は `-AppleLanguages` で上書き）で `-SameQFakeTranslate` を付けずに実操作検証。翻訳自体は実機で正しく動き（原文のまま表示0件・ちらつき0件・`zxx` 0回表示・お題も端末言語に追従・1件あたり最大2.5秒）、attempt 2 の `Attempted to use TranslationSession after the view…` も1度も観測しなかった（セッションのキャッシュ撤去は有効）。**しかしタイムラインは4回中4回とも途中で固着**（ja: 5/6/7件、en: 21件で停止、90秒待っても復帰なし）。原因は `Translator.isSupported` が `status != .unsupported` で判定しており、`.supported`（この端末ではモデル未ダウンロード）を `.installed` と同じ扱いで `session.translate(_:)` に渡していること。実機プローブの実測で ar/pl/ru/th が ja/en いずれ向けも `supported(未ダウンロード)`、同梱シードにこの4言語が各1件ずつ入っている。踏むとOSの「翻訳／必要なダウンロード」シートが出て**タイムラインが勝手に閉じ**（あるいは空白のまま残り）、投稿の言語名（「ポーランド語」）まで画面に出る。30秒のジョブタイムアウト＋`session.cancel()` はこの状況を救えていない。クラッシュ0、データ整合性OK（実機の `state.json` を直接確認）、回帰は実機5/5＋シミュレータ90/90、使用性2。受け入れ条件7（機内モード）は端末設定の変更にあたるため評価不能。次はスプリント06 attempt 4（generator の修正）。[`eval-3.md`](.product/sprints/06-translation/eval-3.md)
- 2026-08-19: スプリント06 評価（evaluator / attempt 3）を試みたが**評価不能**（合否は出していない）。実機（iPhone 17 Pro Max、`B7121EA8-8AED-5E66-B696-511BFFC729E2`）向けのビルド・インストール・`build-for-testing` はすべて成功し、17:32 に `devicectl device process launch` で1度だけ起動もできたが、17:38 以降は端末が施錠されたままで、`xcodebuild test -destination 'id=B7121EA8-…'` が `Failed to start remote service "com.apple.mobile.notification_proxy" on device … The device is passcode protected.` を繰り返し、`Test Case` の行が1件も出ない（テストが1本も始まらない）。`devicectl device process launch` も `BSErrorCodeDescription = Locked` で失敗。17:49〜18:19 の約30分、20秒間隔で試し続けたが一度も解除されなかった。シミュレータ（iPhone 17）でのフルスイートは現在の作業ツリーでも **90/90 全通過**（`SameQTests` 57 ＋ `SameQUITests` 33、failures 0）だが、attempt 2 の不合格理由は `-SameQFakeTranslate` が通らない実セッション経路の問題なので、これは修正の証拠にならない。再開にはユーザーによる①ロック解除②自動ロック「なし」への一時変更が必要。evaluator 用の一時 XCUITest `SameQUITests/EvalSixDeviceTests.swift`（D01〜D05）を用意済み（未コミット）。[`eval-3.md`](.product/sprints/06-translation/eval-3.md)
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
- 2026-08-27: スプリント13 実装（generator / attempt 1）。F36 サーバー側で担保する制限・停止・保持。新規マイグレーション `supabase/migrations/20260827000006_server_enforcement.sql` で `rate_limit_events` テーブル（条件1）・`consume_rate_limit(p_action, p_max, p_window_seconds)` スライディングウィンドウ RPC（条件1）・`current_user_status()` RPC（条件2）・`current_server_time()` RPC（条件5・評価用）・`my_viewed_posts()` RPC（条件4・評価用）・`purge_expired_safety_logs(p_retention_seconds)` 関数＋`app_purge_expired_safety_logs()` RPC（条件6・pg_cron 有効化はユーザー側作業）・`delete_my_account()` `security definer` RPC（条件7・auth.users と public.users を cascade 削除）を新設。`SameQ/Backend/Backend.swift` に `func currentServerSideStatus() async throws -> String` をプロトコル要求として追加、`LocalBackend` は `"active"` 固定、`SupabaseBackend` は `current_user_status` RPC を呼ぶ（fail-open）。`SupabaseBackend.swift` から process-local `RateLimiter` を撤去し `setLike` / `reportPost` の冒頭で `consume_rate_limit` RPC を呼ぶ `checkRateLimit(action:settings:)` ヘルパに置き換え（条件1・再起動越しの継続）。`SupabaseBackend.deleteAccount()` から `client.rpcVoid(function: "delete_my_account")` を呼ぶよう変更（条件7・他端末への削除伝播）。`SupabaseClient.swift` に引数なし RPC 用 `rpcVoid(function:)` を追加。`AppSession.start()` 冒頭で `backend.currentServerSideStatus()` を呼び `"banned"` のとき `.banned` 画面に固定（`-SameQBanned` Debug 経路は温存、通信失敗時は fail-open）（条件2）。`SameQUITests/SprintThirteenAcceptanceTests.swift` を新規追加（test01 `-SameQBanned` で BannedView / test02 LocalBackend 経路で起動できる / test03 LocalBackend の process-local いいね連打が動く）。フルテスト実行（シミュレータ単独）: ユニット 166/166（5.96 秒・TEST SUCCEEDED） + UI SprintThirteen 3/3 + SprintTwelve 3/3 + SprintEleven 4/4 = 10/10（142.8 秒・TEST SUCCEEDED）。Debug ビルド SUCCEEDED。クラッシュ0、未処理エラー0、タイムアウト0。実機 2 台での Supabase 経由 e2e（条件1: 連打制限が再起動越しで継続／条件2: サーバ側 status=banned で BannedView／条件3: BAN ユーザの投稿が他端末から消える／条件5: 端末時計をずらしてもお題の有効期間が一致／条件7: アカウント削除が他端末へ伝播）は evaluator 担当（generator は `migration 6` の `supabase db push` を generator 環境では実行不可）。[`self-review.md`](.product/sprints/13-server-enforcement/self-review.md)
- 2026-08-27: スプリント13 修正（generator / attempt 2）。evaluator の指摘4件＋改善提案1件に対応。(1) `consume_rate_limit` / `delete_my_account` のローカル変数を PostgreSQL 予約語 `current_user` から `v_uid` へ全置換（`migration 6` 側も原因 migration として修正を反映、`migration 7` を新規追加して `create or replace` で再投入）。SQLSTATE 42883 `operator does not exist: uuid = name` を解消し、Supabase 経由の `setLike` / `reportPost` が `checkRateLimit` の throw で連鎖失敗していたスプリント12の回帰も直す。(2) `users_update_own` ポリシーを drop → `using (id = auth.uid() and status = 'active')` で再作成。banned 行はオーナーから一切 UPDATE 不能に。(3) `SupabaseBackend.promptState()` のフィルタを `clock.now` から `current_server_time()` RPC の結果に切り替え（通信失敗時は端末時計へフォールバック）。端末時計を N 時間ずらしても今日のお題 id が同じになる。(4) `Backend` プロトコルに `purgeExpiredSafetyLogs() async throws -> Int` を追加し、`AppSession.start()` の BAN 判定直後で呼ぶ。`LocalBackend` は `pruneExpired(at: clock.now)` を実行、`SupabaseBackend` は `app_purge_expired_safety_logs()` RPC を呼ぶ（pg_cron 拡張が有効な環境では `migration 7` の `do $$ ... $$` ブロックで `purge-safety-logs-daily` を毎日 03:00 UTC にスケジュール登録）。(5) `checkRateLimit` を `async throws -> Int` から `async -> Int` に変更し `SupabaseError` 系の例外を `do/catch` で受けて 0 を返す（コメントは元から「fail-open」と書いていたが実装が throw していた不一致の解消）。`SprintThirteenAcceptanceTests` に `test04_launchReachesForegroundAfterAutoPurgeHook` を追加。フルテスト実行（シミュレータ単独）: ユニット 166/166（5.93 秒・TEST SUCCEEDED） + UI SprintThirteen 4/4（test01〜04） + SprintTwelve 3/3 + SprintEleven 4/4 = 11/11（141.5 秒・TEST EXECUTE SUCCEEDED）。Debug `build-for-testing` SUCCEEDED、Release `build` SUCCEEDED。クラッシュ0、未処理エラー0、タイムアウト0。実機 2 台での Supabase 経由 e2e（条件1: 連打制限が再起動越しで継続／条件2: PATCH users status='active' が 0 件マッチになる／条件3: BAN ユーザの投稿が他端末から消える／条件5: 端末時計をずらしてもお題 id が同一／条件6: 短い保持期間で `purge_expired_safety_logs(60)` が走り消えること＋`AppSession.start()` 経由でも消えること／条件7: アカウント削除で他端末の world_timeline から消える）は evaluator 担当（generator は `migration 7` の `supabase db push` を generator 環境では実行不可）。[`self-review.md`](.product/sprints/13-server-enforcement/self-review.md) の attempt 2
- 2026-08-28: スプリント14 blocked（generator / attempt 7）。eval-6.md を受け、generator.md「**同じ指摘で3回落ちたら止まる**」に従い status を `blocked` に変更。条件 4「サンドボックスでの購入・復元が運営側の課金ダッシュボードに取引として現れる」の差し戻しが eval-2 / eval-3 / eval-4 / eval-4 / eval-6 の **5 回連続**で、閾値「3 回」を超過。attempt 6 で `.storekit`（StoreKit Testing）経路を追加しシミュレータでの条件 2・3 検証経路は確保したが、StoreKit Testing は RevenueCat サーバに到達しないため条件 4 には寄与しないと evaluator が確認済み。generator コード側の役割は完了（条件 1 は見た目・導線同一・コード上達成、条件 5・6 はモック経路で担保、条件 7 は SprintTen 7/7、条件 2・3 は StoreKit Testing 経路で代替可能化）。残りはすべて人間作業: (a) 実機 + Sandbox Apple ID で実際に購入・復元を実行し RevenueCat ダッシュボード / REST API v2 で取引を確認、または (b) spec.md 受け入れ条件 4 を REST API v2 照会レベルへ緩和する（本差し替え主旨の変更につきユーザー判断必須）。**コード変更ゼロ**（attempt 6 の `.storekit` 追加が最終形）。作業ツリー clean。次はユーザー判断待ち — この `blocked` 状態は「同じ所の繰り返し」ではなく、外部サービス要件と autoloop 環境の原理的不一致なので、generator 側で突破する手段は尽きている。[`self-review.md`](.product/sprints/14-undefined/self-review.md) の attempt 7
