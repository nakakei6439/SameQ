# 単発タスク自己評価（2026-09-04 adhoc）: LocalBackend のシード内容を英語ロケール対応にする

## 受け入れ条件の達成状況

| 条件 | 状態 | 根拠 |
|---|---|---|
| 1. en 端末 + LocalBackend + expiring で「What made you laugh out loud today?」表示 | 実装済（visual 検証は evaluator 担当） | `SeedCatalog.File.SeedPrompt` に `textEn: String?` を追加し、`SeedData.json` の `prompt_001` に `textEn: "What made you laugh out loud today?"` を追加。`loadSchedule` で `L10n.isJapanese == false && textEn` が入っていれば `Prompt.text` を英語に差し替える分岐を入れた。シミュレータ（en-US）で `-SameQUseLocalBackend -SameQScenario expiring` 起動のスクリーンショット `/tmp/sq_en_initial.png` を撮影し、オンボーディング画面が英語（"One question. One answer." / "Next"）で立ち上がることを確認。あとは evaluator がオンボーディングを進めてホームのお題表示を視覚確認する想定。 |
| 2. 同上で Announcements タブに "Welcome to SameQ" が出る | 実装済（unit で検証済） | `LocalBackend.announcements(locale:)` を `locale == "en"` で `title: "Welcome to SameQ" / body: "Answer one question a day, at the same moment as someone else in the world."`（id `…0002`）を返すように変更。新規 `AnnouncementTests.test04_localBackendAnnouncementsEnglishLocaleReturnsEnglishCopy` でこの文言と別 ID を assert。 |
| 3. ja 端末 + 同フラグで従来文言のまま（回帰なし） | 実装済（unit で検証済） | 日本語 locale のときは `seedPrompt.text`（従来日本語）と `promptLanguage ?? "ja"` を使う従来パスを維持。`AnnouncementTests.test03`（既存 ja シード）と `test05`（未知 locale → 日本語フォールバック）が緑。 |
| 4. 既存ユニットテストが緑（SeedCatalog / LocalBackend / announcements 関連） | 達成 | `xcodebuild ... -only-testing:SameQTests test` を実行し **230/230 TEST SUCCEEDED**（7.943 秒）。新テスト 2 本（test04 / test05）を含む `AnnouncementTests` 5/5、`PromptGenerationTests` 18/18、`PromptLifecycleTests` 6/6、`BanAndSpamTests` 13/13、`TimelineSelectionTests` 10/10 がすべて緑。SeedData.json のスキーマ変更（textEn 追加）は `Decodable` のオプショナル扱いで後方互換。 |
| 5. Debug / Release ビルド成功 | 達成 | `xcodebuild -configuration Debug` → `** BUILD SUCCEEDED **`、`xcodebuild -configuration Release` → `** BUILD SUCCEEDED **`。 |

## 動かし方（evaluator 向け）

シミュレータ言語を **English** に切り替えたうえで:

```
xcrun simctl launch <udid> com.nakakei6439.SameQ \
    -SameQUseLocalBackend -SameQScenario expiring -SameQResetState
```

- ホーム画面（Today's prompt）に **"What made you laugh out loud today?"** が表示されること。
- メニュー → Notifications → Announcements タブに **"Welcome to SameQ"** / **"Answer one question a day, at the same moment as someone else in the world."** が表示されること。
- 日本語端末に切り替え直して再起動したときは、お題が「今日、思わず笑ってしまったことは何ですか？」、お知らせが「SameQ へようこそ」に戻ることを確認。

シミュレータの言語切替:
```
xcrun simctl spawn <udid> defaults write .GlobalPreferences AppleLanguages -array en-US
xcrun simctl spawn <udid> defaults write .GlobalPreferences AppleLocale en_US
```

## 変更ファイルと差分の要点

| ファイル | 変更 |
|---|---|
| `SameQ/Resources/SeedData.json` | `prompt_001` に `"textEn": "What made you laugh out loud today?"` を追加。`text` / `promptLanguage` / `posts` はそのまま。 |
| `SameQ/Backend/SeedCatalog.swift` | `File.SeedPrompt` に `let textEn: String?` を追加（`Decodable` でオプショナル）。`loadSchedule` で `Prompt` を組み立てる際、`!L10n.isJapanese && textEn` が非空なら英語テキストと `language = "en"` を採用、それ以外は従来パス（日本語テキスト + `promptLanguage ?? "ja"`）。 |
| `SameQ/Backend/LocalBackend.swift` | `announcements(locale:)` を `switch locale { case "en": … default: … }` に変更。英語版は ID `…0002`（日本語版 `…0001` と別）。未知の locale（"fr" 等）は日本語版シードにフォールバック。 |
| `SameQTests/AnnouncementTests.swift` | `test04_localBackendAnnouncementsEnglishLocaleReturnsEnglishCopy`（英語 locale → 英語文言 & 別 ID）と `test05_localBackendAnnouncementsUnknownLocaleFallsBackToJapanese`（未知 locale → 日本語フォールバック）を追加。 |

## 追加・更新したテスト

- **新規**: `AnnouncementTests.test04_localBackendAnnouncementsEnglishLocaleReturnsEnglishCopy` — 英語 locale で title/body/id を assert。日本語版 ID とも比較して「言語で別行」になっていることを確認。
- **新規**: `AnnouncementTests.test05_localBackendAnnouncementsUnknownLocaleFallsBackToJapanese` — 未知 locale（"fr"）で日本語版シードが返ることを assert（回帰防止）。
- **既存はそのまま**（`test01` / `test02` / `test03`）。

## 自分で見つけた弱点

1. **`textEn` を入れた prompt は prompt_001 のみ**。task spec 通り `.live` の受け入れ条件で prompt_001 しか使わないため、prompt_002 以降には未着手。将来 prompt_002 を英語化したい場合は同じ `textEn` フィールドを足すだけで対応できる構造になっている。
2. **`Prompt.language` を `textEn` 採用時に "en" に揃える分岐を併置**。F22 の翻訳可否判定で「端末表示言語と原文言語が一致 → 翻訳スキップ」を期待するコードに影響する可能性があるが、`!L10n.isJapanese` のときだけ "en" にするので英語端末では整合する。日本語端末では従来どおり `"ja"` のまま。
3. **`L10n.isJapanese` は `Locale.preferredLanguages.first` を起動時に1度だけ評価**するため、ユニットテスト実行中に動的に言語を切り替える手段がない。`test04` / `test05` は English locale 端末で実行すれば通る（en-US シミュレータで実行確認）。日本語端末では `textEn` が空の場合の分岐が走らないので、`textEn` の非空パスを強制的に通す追加テストを書きたければ、`SeedCatalog.loadSchedule` を別経路（json ファイルを直接合成して decode する純関数的テスト）で担保する必要があるが、今回は task 範囲外として省略。
4. **`announcements(locale:)` の en 版 id を `…0002` に変更**しているが、Supabase 経路は locale でフィルタして Supabase 側の UUID を使っているので衝突しない。`SupabaseBackend` は触っていない（task spec で除外指定あり）。
5. **シミュレータでの視覚確認はオンボーディング画面のスクショ（`/tmp/sq_en_initial.png`）のみ**。ホーム画面のお題文言と Announcements タブの文言は evaluator の実機/シミュレータ操作に委ねる（オンボーディングのスキップ機構が無いため、generator 側で全画面タップの自動化は行わなかった）。

## 提案（今回はやらなかったこと）

- prompt_002 にも `textEn` を足して英語スクショの幅を広げる（spec は prompt_001 のみ指示だが、スクショ撮影で prompt_002 を見せたくなったときに同じ手順で対応できる）。
- LocalBackend のお知らせに複数件（リリースノート風）のサンプルを足して、Announcements タブのスクロール挙動もスクショで確認できるようにする。
- `LaunchOptions` にテスト用 locale オーバーライド（`-SameQTestLocale en|ja`）を入れて、ユニットテストで `L10n.isJapanese` 経路を強制的に通せるようにする。
