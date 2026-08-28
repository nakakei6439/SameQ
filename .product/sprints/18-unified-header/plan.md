# スプリント 18: 画面上部の入り口をひとつにまとめ、お知らせと無料トライアルを足す（F42〜F45）

## 受け入れ条件（spec.md から転記）

- [ ] 今日のお題画面とお題待ち画面の上部に、左からメニュー・アプリ名「SameQ」、右に通知ベル・Plus 導線・自分の絵文字アバターが1行で並ぶ。歯車アイコンとヘッダー上のニックネーム文字列は表示されない。世界タイムラインの上部はこれまでどおりで、統合ヘッダーに置き換わっていない
- [ ] メニューを開くと自分の絵文字とニックネームが読み取り専用で表示され、「通知」「Plus」「設定」からそれぞれの画面に到達できる。設定画面の中身（プロフィール編集・規約・プライバシーポリシー・通知許可の状態・購入復元・ブロック管理・アカウント削除）はスプリント11のままで、項目の増減が無い
- [ ] メニューの下部にアプリのバージョンが表示され、その表記が実際に配布しているビルドの版と一致する（版を上げて入れ直すと表示も変わる）
- [ ] ベルからもメニューの「通知」からも同じお知らせ画面が開き、「アプリ通知」と「運営お知らせ」を切り替えられる。「アプリ通知」は常に空状態で、履歴を残さないことが分かる説明文が表示される（読み込み中のまま止まったり白紙になったりしない）
- [ ] 運営がサーバー側の管理手段でお知らせを追加すると、アプリを入れ直さずに「運営お知らせ」へ新しい順で並び、見出し・本文・公開日時が読める。1件も無いときは空状態の説明文が出る。アプリ内にお知らせを投稿・編集・削除する画面は1つも存在しない
- [ ] Plus 画面に「1ヶ月無料」に相当する案内が価格とともに表示され、購入ボタンのラベルが「無料で試す」に相当する文言になる。無料トライアルが提供されない状態ではこの案内もラベル変更も現れず、スプリント10・14と同じ購入表示に戻る
- [ ] メニュー下部のバージョン表示を8回連続でタップし、続いて出る入力欄に所定の8桁の数字を入れると開発者モードが現れ、Plus 状態を「実際の状態／常に Plus／常に無料」の3つから切り替えられる。切り替えは長文入力と限定装飾の可否に即座に反映され、アプリを終了して起動し直すと必ず「実際の状態」に戻る。8桁の数字を間違えた場合は開発者モードが現れない
- [ ] 端末言語を英語にすると、統合ヘッダー・メニュー・お知らせ画面・無料トライアルの案内の文言がすべて英語で表示され、日本語が残らない（スプリント15の範囲を維持）

## 実装方針

coordinator（Sonnet）が本スプリントの実装の大半を完了済み（commit `0047faf`）。
本スプリントの generator 作業は「仕上げ」と「検証の自動テスト化」に集中する。

### 実装済みの内容（coordinator）

- `SameQ/Design/AppHeaderBar.swift` — 統合ヘッダー（menu/appName/spacer/notifications/plus/avatar）
- `SameQ/Design/AppVersion.swift` — Bundle から版を読み "vX.Y (Z)" 形式に整形
- `SameQ/Feature/Menu/MenuView.swift` — メニュー（プロフィール要約・3行・バージョンフッター・隠し開発者モード）
- `SameQ/Feature/Notifications/NotificationsView.swift` — お知らせ（2タブ）
- `SameQ/Model/Announcement.swift` — Codable Identifiable
- `SameQ/Session/AppSession.swift` — `isMenuPresented` / `isNotificationsPresented` / `debugPlusOverride` /
  `loadAnnouncements()` を追加。`isPlus` は `debugPlusOverride` を優先
- `SameQ/App/RootView.swift` — `.sheet` を 2 つ追加（MenuView / NotificationsView）
- `SameQ/Backend/Backend.swift` — `announcements() async throws -> [Announcement]` をプロトコルに追加
- `SameQ/Backend/LocalBackend.swift` / `SupabaseBackend.swift` — 上記を実装
- `SameQ/Backend/PlusService.swift` — `introductoryOfferDescription: String?` と `PlusTrialPeriodUnit` enum を追加
- `SameQ/Backend/RevenueCatPlusService.swift` — `discount.paymentMode == .freeTrial` を検知し
  `introductoryOfferDescription` を組み立てる
- `SameQ/Backend/FakePlusService.swift` — `availableProducts` が `introductoryOfferDescription: "1ヶ月無料"` を返す
- `SameQ/Feature/Plus/PlusView.swift` — `purchaseSection` に trialBadge 追加、購入ボタンラベルを
  `purchaseTrialCta` に切り替え
- `SameQ/Feature/Today/TodayPromptView.swift` / `Waiting/WaitingPromptView.swift` — 旧 `headerRow` を
  `AppHeaderBar(identityIdentifier:)` に置き換え
- `SameQ/L10n.swift` — Menu / Notifications / Plus（trial 関連）セクションを追加
- `supabase/migrations/20260829000011_announcements.sql` — `announcements` テーブル＋ RLS

### 本 attempt（attempt 1）での追加作業

1. **既存 UI テストの menu.open 対応**
   - `SprintEightAcceptanceTests.swift`: 4 箇所を `menu.open → settings.open` パターンに更新
   - `SprintElevenAcceptanceTests.swift`: 4 箇所
   - `SprintFifteenAcceptanceTests.swift`: 2 箇所
   - `SprintSeventeenAcceptanceTests.swift`: 1 箇所（`openSettings` ヘルパー）
2. **新規 UI テスト `SameQUITests/SprintEighteenAcceptanceTests.swift`**
   - 統合ヘッダーの並びと識別子（メニュー / アプリ名 / 通知ベル / Plus / アバター）
   - メニューから通知 / Plus / 設定へ到達でき、設定の中身が変わっていないこと
   - バージョン表記が "vX.Y (Z)" 形式
   - お知らせ画面の 2 タブ（空状態の説明文・空お知らせ）
   - 無料トライアル表示（`plus.trialBadge`、購入ボタンが「無料で試す」）
   - 無料トライアルが無い状態（FakePlus 経路でtrialBadge を非表示に）で旧表示に戻る
   - 隠し開発者モード: 8 タップ → パスコード入力 → 3 つの Plus override が機能、
     再起動で「実際の状態」に戻る、誤入力で開発者モードが出ない
   - en 端末で主要文言が英語
3. **ユニットテスト追加**
   - `AnnouncementTests.swift` — Codable ラウンドトリップ
   - `DeveloperModeTests.swift` — `debugPlusOverride` が `isPlus` を上書きすること、
     プロセス再生成後は `nil` に戻る（永続化されないこと）
   - `PlusIntroductoryOfferTests.swift` — `RevenueCatPlusService.introductoryOfferDescription` の
     `freeTrial` 判定、`FakePlusService.availableProducts()` の `introductoryOfferDescription` 出力
   - `LocalBackendAnnouncementsTests.swift` — `LocalBackend.announcements()` が空配列とサンプル
     を返すこと、`Backend` プロトコル整合性
4. **Supabase マイグレーション本番適用** — `20260829000011_announcements.sql` を
   `supabase db push` 経由で適用（CLI 不在なら README に手順記載で代替）
5. **self-review.md 作成**

## 影響範囲

- 既存 UI テスト 4 ファイルで `settings.open` を直接叩いていた 11 箇所を menu 経由に
  書き換え（タップ回数は +2 回/箇所、待ち受け `waitForExistence` は既存 UI テストの
  パターンに揃える）
- 新規追加する画面・識別子は既存機能とぶつからない（`menu.open` / `notifications.open` /
  `plus.open` / `settings.open` / `menu.*` / `notifications.*` / `plus.trialBadge` /
  `menu.dev.*` / `menu.version`）