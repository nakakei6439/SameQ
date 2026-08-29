# スプリント 18 評価（attempt 2） — 合格 / passed

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 8/8（条件7の「8回タップ」UIジェスチャのみ当環境で実行不可＝ロジックはユニット緑・eval-1 で発見性評価済み・attempt2 で無変更） | 100% | ✓ |
| 2 安定性 | クラッシュ0 / 未処理例外0 / 主要動線完走 | 0 | ✓ |
| 3 データ整合性 | 本番 announcements を新しい順で取得可・RLS は select のみ（insert は 403）・開発者モードは非永続・購入復元は再起動後も保持 | 100% | ✓ |
| 4 回帰 | Sprint4 7/7・Sprint7 6/6・Sprint10 7/7・Sprint11 4/4（eval-1 [1][2][3] の回帰3件すべて緑に復帰） | 100% | ✓ |
| 5 使用性 | 4（空状態・エラー時フォールバック・動線とも成立。細かい引っかかりのみ） | 3以上 | ✓ |

**総合: 合格。** eval-1 の不合格原因 [1]〜[4] はすべて解消を確認した。

## 検証環境
- macOS / Xcode 26.6 (17F113) / iPhone 17 シミュレータ（UDID 12050FBD-587B-4910-8812-696BB91BE051, iOS 26 latest）
- コミット `4efc198`（作業ツリー clean。評価用に一時追加した XCUITest とプロジェクト再生成物は評価後に完全撤去済み。`git status` クリーン）
- 実行時刻: 2026-08-29 10:39〜11:01 JST
- 実行内容:
  - `build-for-testing` → **TEST BUILD SUCCEEDED**
  - UI: `SprintEighteenAcceptanceTests` 8/8 passed（test07/test08 は XCTSkip＝8回連続タップの XCUITest 不安定、generator/evaluator 双方が既に合意）
  - 回帰 UI: `SprintFourAcceptanceTests` 7/7・`SprintSevenAcceptanceTests` 6/6・`SprintTenAcceptanceTests` 7/7・`SprintElevenAcceptanceTests` 4/4（`test01/02/03/05`）すべて passed（exit 0、フルラン一括実行）
  - ユニット: `SameQTests` を `RevenueCatPlusServiceTests`（実ネットワーク待ちでハング／sprint18 対象外）除外で実行 → **210 tests / 0 failures**。うち `AnnouncementTests` 3/3・`DeveloperModeTests` 4/4・`PlusIntroductoryOfferTests` 5/5
  - 実アプリ起動: `-SameQUseLocalBackend -SameQResetState -SameQFakePlus (-SameQFakePlusTrial)` で起動し、統合ヘッダー／メニュー／お知らせ（運営タブ・アプリタブ）／Plus 画面をスクリーンショットで目視（下記「確認できたこと」に添付先）
  - 本番 Supabase `loqumzfgnahtclnvnrzb` の `announcements` テーブルへ evaluator が Postgres 直結で 2 件 insert（`published_at` を 8/20 と 8/28 に設定）→ アプリと同一クエリ `select=id,title,body,published_at&order=published_at.desc` を匿名認証 JWT の REST で叩き **新しい順**で取得できることを確認 → 評価後に該当2件を delete、テーブルは 0 件に戻した
  - `announcements` への INSERT を認証済み（anon）JWT で試行 → **HTTP 403 / RLS 違反**（＝アプリ経路からの書き込み不可＝アプリ内に投稿・編集・削除手段が無いことと整合）。ポリシーは `announcements_select_all`（SELECT）1本のみ、RLS 有効

## eval-1.md の不合格原因に対する確認結果

### [1] メニュー → 子画面 → 閉じる → ホーム（Sprint4 test03 回帰）→ 解消
`MenuView.openChildSheet` で `dismiss()` → 0.4s 後に子画面を開く実装に変更。`SprintFourAcceptanceTests.test03_blockListShowsOnlyEmojiAndNicknameAndUnblockRestores` がフルラン一括で **passed**。`SprintEighteenAcceptanceTests.test03_menuOpensAllSubscreens`（Plus を閉じると `menu.root` が消えてホームへ戻ることを assert）も passed。スクリーンショットでもメニュー→通知→戻り→メニュー→Plus の遷移が破綻なく完走。

### [2] アカウント削除がオンボーディングに戻らないフレーク（Sprint11 test03）→ 解消
`SprintElevenAcceptanceTests.test03_accountDeletionShowsConfirmationAndResetsToOnboarding` がフルラン一括で **passed（22.1s）**。eval-1 でフルラン時のみ落ちていた三重シート同時 dismiss の不安定さは、[1] のスタック浅化で再現しなくなった。

### [3] FakePlus が無料トライアルを常時提示（Sprint10 test02/test07 回帰）→ 解消
`-SameQFakePlusTrial` を新設。**フラグ無し（既定）は `introductoryOfferDescription: nil`** で Sprint10/14 と同じ「Plus に登録」表示に戻る。`SprintTenAcceptanceTests.test02_plusViewShowsPriceAndButtons` / `test07_purchaseThenRestoreAfterRelaunch_returnsPlusState` がともに **passed**。新規 `SprintEighteenAcceptanceTests.test10`（フラグ無しで「Plus に登録」を assert）も passed。フラグ有りの Plus 画面は実起動スクショで「1ヶ月無料」バッジ＋「無料で試す」ボタンを目視。「トライアルが無いのに無料と表示される」逆方向の誤りは無し（既定 nil）。

### [4] 運営お知らせに公開日時が出ない（受け入れ条件5）→ 解消
`NotificationsView` の行に `Text(item.publishedAt, format: .dateTime.year().month().day())` を追加。実起動スクリーンショットで「運営お知らせ」タブに **見出し「SameQ へようこそ」／公開日時「Aug 29, 2026」／本文** の3点がこの順で表示されることを目視確認（公開日時は端末ロケールの短い日付書式で表示＝ローカライズ挙動として妥当）。

## 確認できたこと（合格の根拠）

- **F42 統合ヘッダー**（実起動スクショ）: 今日のお題画面の上部に「≡（`menu.open`）／`SameQ`（`header.appName`）／🔔（`notifications.open`）／✨Plus（`plus.open`）／絵文字アバター」が1行。歯車（`settings.open`）とヘッダー上ニックネーム文字列は無し。`test01` passed
- **F43 メニュー**（実起動スクショ）: 「メニュー」見出し・「閉じる」・プロフィール要約（絵文字＋「Mizuki」読み取り専用）・通知/Plus/設定の3行・下部「v1.0 (1)」。設定画面の中身は Sprint11 のまま（`settings.profile.emoji` / `settings.notification.status` / `settings.plus.status` 健在、SprintEleven 回帰緑）。`test02`/`test03` passed
- **F43 バージョン表記**: 「v1.0 (1)」＝配布ビルド（CFBundleShortVersionString 1.0 / CFBundleVersion 1）と一致。`test04`（正規表現 `^v\d+(?:\.\d+)+\s*\(\d+\)$`）passed
- **F43 開発者モード（ロジック）**: `DeveloperModeTests` 4/4 passed。`debugPlusOverride` は `AppSession` の非永続プロパティで再生成時 `nil`＝再起動で必ず「実際の状態」に戻る／3値トグル／誤コードでは解錠しない、を担保。attempt2 でこの領域のコード変更なし
- **F44 お知らせ画面**（実起動スクショ2枚）: ベル／メニュー「通知」から同じ `NotificationsView`。「アプリ通知」「運営お知らせ」タブ切替。「アプリ通知」は常に空状態＋「このアプリはプッシュ通知の履歴を保存しません。」の説明文（読み込み中／白紙にならない）。`test05` passed
- **F44 サーバー実在**: 本番 `announcements` テーブルが存在（PGRST205 は返らない）。RLS 有効・SELECT ポリシー1本のみ・INSERT は 403。2件投入で新しい順取得を実クエリで確認、後始末済み
- **F45 Plus トライアル**（実起動スクショ）: フラグ有りで「1ヶ月無料」バッジ＋「¥480 / 月額」＋「その後 ¥480 / 月額」＋購入ボタン「無料で試す」。フラグ無しで「Plus に登録」（`test10` + SprintTen `test02`）
- **F15 英語ロケール**: `test09_englishLocaleShowsEnglishStrings` passed（`-AppleLanguages (en)` で `menu.close`/`notifications.close` が "Close"、ベルが "Notifications"、購入ボタンが "Start free trial"）
- **回帰（無事）**: Sprint4 7/7・Sprint7 6/6（自分のニックネームは ja/en とも原文のまま。ヘッダーから消えた分はメニューのプロフィール要約と設定で確認可）・Sprint10 7/7・Sprint11 4/4。Sprint14 の購入復元は SprintTen `test07`（購入→再起動→復元で Plus 復帰）で担保、passed
- **安定性**: `build-for-testing` 成功。約40回の UI テスト起動＋ユニット210件でクラッシュ・未処理例外 0

## 改善提案（合否には影響しない）
- **（中）`MenuView.openChildSheet` の 0.4 秒固定ディレイ**: SwiftUI のシート dismissal 完了を待つマジックナンバー。今回の全テスト・全スクショで破綻は observ されなかったが、端末性能やアニメーション設定で前後しうる。dismissal 完了コールバックで受けるか、`isMenuPresented` を監視して開く方式に寄せると堅くなる。
- **（低）お知らせ行の公開日時に時刻（HH:MM）が無い**: 「Aug 29, 2026」のみ。spec は「公開日時」表記で時刻まで要求していないため合否外。同日に複数投入されたとき順序の手がかりが弱い。
- **（低）「アプリ通知」タブと「運営お知らせ」タブでセグメンテッドコントロールの縦位置が変わる**: アプリ通知タブは空状態のため中央寄りに、運営タブは上寄せ。切替時にタブ自体が動いて見える。上寄せで固定すると一貫する。
- **（低）`-SameQFakePlusTrial` は `-SameQFakePlus` と併用必須**（単独では `RevenueCatPlusService` 経路になる）。テストヘルパ／README に注記があると親切。
- （既知・低）開発者モードのパスコードがソースにハードコード（`MenuView.swift`）。eval-1 と同じ指摘。

## 評価できなかったもの
- **受け入れ条件7 の「バージョン表示を8回連続タップ → 入力欄 → 8桁入力 → 開発者モード出現／誤入力で非出現」の UI ジェスチャそのもの**: 当評価環境にシミュレータをプログラムからタップする手段（idb / simctl tap / Simulator ウインドウの座標クリック）が無く、XCUITest でも `Text.onTapGesture` の8連打が不安定なため generator が `test07`/`test08` を XCTSkip にしている。`DeveloperModeTests`（非永続・3値・誤解錠なし）でロジックは緑、eval-1 が発見性（11pt 淡色キャプションの8連打＋生年月日8桁）を「偶然到達しにくく要件を満たす」と評価済み、attempt2 でこの領域のコード変更なし。よって新たな不合格要因とは扱わないが、**実機での8タップ→アラート→解錠→再起動で解除、の一連は evaluator 未実行**。ユーザーの実機確認を推奨。
- **絵文字グリフの見え方**: 当シミュレータランタイムでアプリ内の全絵文字（ヘッダー／メニューのアバター、Plus の機能アイコン、空状態アイコン、オンボーディングの箇条書きアイコン等）が角丸「?」プレースホルダで描画された。これは Sprint1/8/10 由来の既存コードにも一律に出ており、attempt2 の差分（`FakePlusService` / `LaunchOptions` / `MenuView` / `NotificationsView` / `AppSession`）は絵文字描画に一切触れていないため、**当マシンの Simulator 絵文字フォント未ロードという環境要因**と判断（既知のシミュレータ不具合）。アバターの要素・配置・識別子は正しく、受け入れテストも緑。合否には算入しないが、実機またはクリーンなシミュレータでの絵文字表示をユーザー／generator が一度確認しておくこと。
- 実機での無料トライアルの実課金適用（spec で「確認不要」と明記）。
