# スプリント 18 評価（attempt 1） — 不合格（needs_fix）

## 判定サマリ
| 基準 | 結果 | 閾値 | 判定 |
|---|---|---|---|
| 1 受け入れ条件 | 5.5/8（公開日時未表示・無料トライアルOFF状態が検証不能） | 100% | ✗ |
| 2 安定性 | クラッシュ0 / 未処理例外0 / 主要動線は完走可（メニュー戻りに難あり） | 0 | ✓ |
| 3 データ整合性 | 本番 announcements テーブル実在・新しい順・匿名JWTで取得可。debugPlusOverride は非永続 | 100% | ✓ |
| 4 回帰 | Sprint4 test03 決定的失敗 / Sprint10 test02・test07 決定的失敗 / Sprint11 test03 フレーク。Sprint7 6/6 緑 | 100% | ✗ |
| 5 使用性 | 3（空状態は揃うが、メニュー階層の戻りが混乱する） | 3以上 | ✓ |

**総合: 不合格。** 基準1・基準4 が閾値未達。

## 検証環境
- macOS 26.5.2 / Xcode 26.6 / iPhone 17 Pro シミュレータ（UDID 4C9A260E-…、iOS 26.3.1）
- コミット `875d88c`（作業ツリー clean）
- 実行内容（2026-08-29 08:06〜08:26 JST）:
  - ユニット: `SameQTests` を実行。`AnnouncementTests` 3/3・`DeveloperModeTests` 4/4・`PlusIntroductoryOfferTests` 5/5 緑。他 153 ケース緑・0 失敗（`RevenueCatPlusServiceTests` は実ネットワーク待ちで長時間ブロックするため打ち切り＝新規失敗ではない）
  - UI: `SprintEighteenAcceptanceTests` 7/7（+2 skip）、回帰 `SprintFour` `SprintSeven` `SprintTen` `SprintEleven` を実行 → **4 失敗**
  - 失敗 4 件を単独で再実行して決定性を確認
  - 本番 Supabase `loqumzfgnahtclnvnrzb` の `announcements` テーブルへ evaluator が直接 2 件 insert → 匿名サインインの JWT で `select=id,title,body,published_at&order=published_at.desc`（アプリと同一クエリ）を叩き新しい順で取得できることを確認 → 後始末で delete、テーブルは 0 件に戻した
  - 失敗テストの画面収録（.xcresult 添付 mp4）からフレーム抽出して画面状態を目視確認

## 不合格の原因（これを直せば通る）

### [1] ハンバーガーメニューから入った先の画面を閉じると、ホームに戻らずメニューに戻る（Sprint4 回帰・決定的）
- **再現手順**:
  1. `-SameQUseLocalBackend -SameQResetState -SameQAnswerCount 10` で起動しオンボーディングを済ませ、回答を投稿
  2. 「世界の回答を読む」→ 1件目のカードの … からブロック → タイムラインを閉じる
  3. ヘッダー左「≡」→ メニューの「設定」→ ブロック一覧で「解除」→ 「閉じる」で設定を閉じる
  4. ホームの「世界の回答を読む」ボタンを押そうとする
- **期待**: 設定を閉じたらホーム（今日のお題画面）に戻り、「世界の回答を読む」が押せる（spec 受け入れ条件・Sprint04 受け入れ条件「解除するとその人の回答が再び表示対象に戻る」を新導線でも満たす）
- **実際**: 設定シートを閉じると **メニューシートが再び前面に出て**、ホームは背面に隠れたまま。`today.openTimeline`（「世界の回答を読む」）が not hittable になり操作不能。`SprintFourAcceptanceTests.test03_blockListShowsOnlyEmojiAndNicknameAndUnblockRestores` が
  `Failed to ... not hittable: Button ... identifier: 'today.openTimeline'` で失敗（フルラン・単独再実行の両方で再現）
- **根拠**:
  - `/tmp/s18/four_end.png`（失敗時フレーム）= 設定を閉じた直後に「メニュー」シート（プロフィール Mizuki / 通知・Plus・設定 / v1.0 (1)）が前面に表示されている
  - `/tmp/s18/four_t30.png` = メニューがハーフシートで、その下にホームの統合ヘッダーが見える＝メニューはシート、設定はさらにその上のシートという二重スタック
  - `SameQ/Feature/Menu/MenuView.swift:96-108` `menuRow` は `session.isNotificationsPresented / isPlusViewPresented / isSettingsPresented = true` を立てるだけで、メニュー自身（`isMenuPresented` / `dismiss()`）を閉じていない。`SameQ/App/RootView.swift` が各画面を独立した `.sheet` で出すため、メニューの上に子画面がスタックする
- **推測（症状と分離）**: 子画面を開くときに `session.isMenuPresented = false`（またはメニューを `dismiss()`）してから遷移させれば、閉じたときにホームへ戻ると思われる

### [2] アカウント削除を新導線で行うとオンボーディングに戻らないことがある（Sprint11 回帰・フレーク）
- **再現手順**:
  1. `-SameQUseLocalBackend -SameQResetState` で起動しオンボーディング完了
  2. 「≡」→「設定」→「アカウントを削除」→ 確認ダイアログの「削除する」をタップ
- **期待**: 初回設定画面（`onboarding.next`）に戻る（Sprint11 受け入れ条件3）
- **実際**: フルラン時に `SprintElevenAcceptanceTests.test03_accountDeletionShowsConfirmationAndResetsToOnboarding` が
  `line 173: XCTAssertTrue failed`（8 秒待っても `onboarding.next` が出現しない）で失敗。**単独再実行では 20.5 秒で PASS** したためフレーク。ただし [1] と同じ「メニュー＋設定＋確認ダイアログの三重スタック」を一気に閉じる経路（`AppSession.resetToOnboarding()` が `isMenuPresented`/`isSettingsPresented` を同時に false 化）に起因する不安定さで、負荷時に再現する
- **根拠**: `/tmp/s18/eleven_end.png`（失敗時フレーム）= 「削除する」ダイアログが設定シートの上に出たまま、背後に設定シートが見えている。SwiftUI の入れ子シート同時 dismiss の既知の不安定挙動
- **推測**: [1] を直して「メニューを閉じてから設定へ」にすればスタックが浅くなり、この不安定さも解消する見込み

### [3] FakePlusService が無料トライアルを常時提示し、Plus の購入ボタン文言が固定で変わる（Sprint10 回帰・決定的 / 受け入れ条件6 の半分が検証不能）
- **再現手順**:
  1. `-SameQFakePlus -SameQUseLocalBackend -SameQResetState -SameQScenario live` で起動（＝トライアル無しの Plus 表示を見たい素の状態）
  2. ヘッダーの Plus 導線 → Plus 画面
- **期待**: spec 受け入れ条件6「**無料トライアルが提供されない状態ではこの案内もラベル変更も現れず、スプリント10・14と同じ購入表示に戻る**」。評価者注記でも「トライアルがある状態／無い状態それぞれで … 正しく切り替わること」を**シミュレータの検証用起動オプションで**確認できることを求めている
- **実際**:
  - `SameQ/Backend/FakePlusService.swift:77-86` が `introductoryOfferDescription: L10n.Plus.freeTrialBadge(value: 1, unit: .month)` を **無条件で** 返す。トライアルを OFF にする起動オプションが存在しない（`SameQ/Backend/LaunchOptions.swift` に該当フラグ無し）
  - このため FakePlus 経路では購入ボタンが常に「無料で試す」になり、`SprintTenAcceptanceTests.test02_plusViewShowsPriceAndButtons`（`label CONTAINS 'Plus に登録'` を期待）と `test07_purchaseThenRestoreAfterRelaunch_returnsPlusState`（同じく購入ボタンを `'Plus に登録'` で取得してタップ）が、フルラン・単独再実行の両方で決定的に失敗
  - 結果、spec が要求する「トライアル無し表示（＝Sprint10/14 と同じ）」の状態をシミュレータで一度も再現・確認できない
- **根拠**: `/tmp/s18/phase2.log` `/tmp/s18/phase3.log`（両方で test02/test07 失敗）、`git show 0047faf -- SameQ/Backend/FakePlusService.swift`
- **推測**: `-SameQFakePlusTrial` のような起動オプションを新設し、既定（フラグ無し）は `introductoryOfferDescription: nil`（＝Sprint10/14 と同じ表示）にする。そうすれば既存 Sprint10 テストは無改修で通り、Sprint18 の test06 はフラグ付きで通り、評価者が両状態を確認できる

### [4] 運営お知らせに「公開日時」が表示されない（受け入れ条件5 未達）
- **再現手順**:
  1. 本番 `announcements` にお知らせを1件以上 insert（evaluator が実施済み・後始末済み）
  2. アプリのメニュー →「通知」→「運営お知らせ」タブ
- **期待**: spec 受け入れ条件5「『運営お知らせ』へ新しい順で並び、**見出し・本文・公開日時が読める**」
- **実際**: `SameQ/Feature/Notifications/NotificationsView.swift:118-132` の行ビューは `Text(item.title)` と `Text(item.body)` のみを描画し、`item.publishedAt`（`Announcement.publishedAt`、DB から取得済みの値）をどこにも表示していない。見出し・本文は読めるが公開日時が読めない
- **根拠**: コード（上記行）、および `announcements` の REST 取得結果に `published_at` が含まれることは evaluator が匿名 JWT で確認済み（データはあるが UI が出していない）
- **推測**: 行ビューに `Text(item.publishedAt, format: …)` を1行足すだけ。ロケール表示は L10n/`Date.FormatStyle` に合わせる

## 確認できた（合格している）こと
- **F42 統合ヘッダー**: 今日のお題画面で「≡ / SameQ / 🔔 / ✨(Plus) / 絵文字アバター」が1行。歯車なし・ヘッダー上のニックネーム文字列なし。お題待ち画面も `AppHeaderBar` に置換済み。世界タイムライン（`TimelineView`）は未変更（diff で確認）。`SprintEighteenAcceptanceTests.test01` 緑、`/tmp/s18/four_t30.png` で目視
- **F43 メニュー内容**: プロフィール要約（絵文字＋「Mizuki」読み取り専用）、通知／Plus／設定の3行、下部に `v1.0 (1)`。設定画面の中身は Sprint11 のまま（項目増減なし。SprintEleven test01/02/05/06 緑）。`test02`/`test03` 緑
- **F43 バージョン表記**: 配布ビルド（CFBundleShortVersionString 1.0 / CFBundleVersion 1）と一致。`test04` 緑
- **F43 隠し開発者モード（ロジック）**: `debugPlusOverride` は `AppSession` の非永続プロパティで、`isPlus` ゲッターを上書きするだけ（RevenueCat/StoreKit を一切呼ばない）。誤コード時は解錠しない。`DeveloperModeTests` 4/4 緑（非永続・実体上書き・誤解錠なしを担保）。※「バージョン8回タップ→アラート」の UI ジェスチャ自体は本評価では未実行（タップ自動化手段が無いため。generator も XCUITest では不安定として skip）
- **隠し開発者モードの見つかりにくさ（評価者所見）**: 11pt・淡色・中央寄せのバージョンキャプションを8回連続タップという発見性は十分低い。アラートが出ても「YYYYMMDD の生年月日」を要求し、正解（開発者の生年月日）を知らなければ無言で閉じてタップ数もリセットされる。**偶然到達される恐れは低く、要件を満たす**
- **F44 お知らせ画面**: ベル／メニュー「通知」から同じ `NotificationsView`。「アプリ通知」「運営お知らせ」タブ切り替え。「アプリ通知」は常に空状態＋「このアプリはプッシュ通知の履歴を保存しません」の説明文（読み込み中・白紙にならない）。`test05` 緑
- **F44 サーバー側の実在**: 本番 `announcements` テーブルが存在（スキーマ＝migration どおり、RLS 有効、`select` ポリシー1本のみ＝insert/update/delete はデフォルト拒否＝アプリ内に投稿画面なしと整合）。匿名サインインの JWT で新しい順に取得できることを実クエリで確認。1件も無いときは `notifications.operator.empty`（📮「お知らせはまだありません」）
- **F45 トライアルあり表示**: FakePlus 経路で「1ヶ月無料」バッジ＋購入ボタン「無料で試す」/「Start free trial」。`test06` 緑。RevenueCat 経路は `discount.paymentMode == .freeTrial` のときだけ検知＝「トライアルが無いのに無料と表示される」逆方向の誤りは無い（コード確認）
- **F15 英語ロケール**: `-AppleLanguages (en)` でヘッダー／メニュー／お知らせ／トライアル文言が英語。`test09` 緑
- **回帰（無事だったもの）**: Sprint07 ニックネーム 6/6 緑（自分のニックネームは ja/en どちらでも原文のまま。ヘッダーからは文字列が消えたが、メニューのプロフィール要約と設定で確認できる）。Sprint04 test01/02/04/05/06/07 緑、Sprint10 test01/03/04/05/06 緑、Sprint11 test01/02/05 緑
- **安定性**: クラッシュ・未処理例外 0。ビルド成功（Swift6 の `nonisolated initializer` 警告は `SupabaseBackend.swift` の既存分でスプリント18 と無関係）

## 改善提案（合否には影響しない）
- （中）隠し開発者モードのパスコードが実在の生年月日をソースにハードコード（`MenuView.swift:26` `"19820427"`）。バイナリ/ソースから自明なので、ビルドごとにランダム化した値を安全な場所（Keychain 等）から読む、あるいはトリガーをもう一段増やす
- （中）`FakePlusService` の商品名 `"Plus （月額）"`・`periodDescription` の日本語リテラル固定（L10n 未経由）。Sprint15 の方針に合わせるなら L10n 化
- （低）`SprintEighteenAcceptanceTests.test07/test08`（8回タップ→開発者モード）が `XCTSkip`。`SKTestSession` や `-SameQUnlockDevMode` のようなテスト専用フラグで UI 経路の自動テストを1本用意すると、この動線が今後デグレしても気づける
- （低）お知らせ行の本文が英語ロケールでも日本語のまま（運営が日本語で入れた場合）。多言語お知らせは別スプリント想定と self-review にあるが、spec 受け入れ条件3「無料トライアルの案内 … すべて英語」の範囲外なので合否には含めない

## 評価できなかったもの
- 「バージョン表示を8回連続タップ → アラート表示 → 8桁入力 → 開発者モード出現」の **UI ジェスチャそのもの**。シミュレータをプログラムからタップする手段（idb / simctl tap）が当環境に無く、generator も XCUITest では不安定として skip している。`debugPlusOverride` の振る舞い（非永続・実体上書き・誤解錠なし・3値トグル）は `DeveloperModeTests` で担保されているため、ロジックは確認済みだが、8回タップからアラートが出る経路は未実行
- 実機での無料トライアルの実課金適用（spec で「確認不要」と明記されているため対象外）
