# スプリント 07: ニックネームの自動ローカライズ

## 受け入れ条件（spec.md 212〜217行 から転記）
- [ ] 端末言語と異なる文字体系のニックネームが、閲覧者の文字体系で表示される
      （例：日本語のニックネームが英語端末ではラテン文字表記になる）
- [ ] 変換は音写であり、意味翻訳された言葉にならない
- [ ] 音写できないニックネームの回答は、ニックネーム未設定として絵文字のみが表示され、
      原文がそのまま出ることはない
- [ ] ニックネーム未設定の回答は絵文字のみが表示され、レイアウトが崩れない
- [ ] 自分のニックネームは設定画面と自分の回答表示では入力した原文のまま表示される

## 実装方針
1. **`SameQ/Backend/NicknameTransliterator.swift`（新規）** — Foundation の
   `String.applyingTransform` で音写する純関数クラス。端末言語を `targetLanguageCode` で
   受け取り、原文 → ラテン → 端末言語の2段書き換えを行う（例: みずき → "Mizuki" → ミズキ）。
   音写できなければ `nil` を返し、呼び出し側が「絵文字のみ表示」へフォールバックする。
2. **`Post` / `BlockedAuthor` / `AppUser` に `displayedNickname(transliterator:)` を追加** —
   モデル層だけで完結させ、View 側は表示文字列を受け取るだけにする。`isOwn` 判定は
   `Post.displayedNickname(transliterator:isOwn:)` の引数で受ける（表示点ごとに `authorID` と
   自分の `id` を見比べる）。
3. **`AppSession.nicknameTransliterator`** を追加。`translator` と同じ要領で `Translator` の
   `targetLanguageCode` をそのまま借用する（端末言語は1箇所で読む設計に揃える）。
4. **View 側** —
   - `AnswerCardView`：`displayedNickname` を受け取り `post.displayNickname` の代わりに表示。
     `TimelineView.cardStack(post:)` が `isOwn` を判定（`post.authorID == session.user?.id`）して渡す。
   - `SettingsView` の行：`BlockedAuthor.displayedNickname` をそのまま使用。
   - `TodayPromptView.identityRow`：自分のニックネームを raw 表示（既存の
     `session.user?.displayNickname` をそのまま使う＝transliterator を経由しない）。
5. **起動引数 `-SameQNicknameTranslitDebug`**（Debug 限定）を追加し、`NicknameTransliterator` を
   「常に音写失敗扱い」にする検証モードを用意（受け入れ条件3の再現用。F13 の
   `-SameQBanned` 等と同じ扱い）。

## 影響範囲
- 既存の `Post.displayNickname` は残す（オンボーディングや `state.json` の互換性のため）。
  表示専用に `displayedNickname(...)` を追加する形にして、既存テストが壊れないようにする。
- `BlockedAuthor.displayNickname` も同様に残す（`state.json` の互換性）。
- `TodayPromptView.identityRow` は **触らない**（自分のニックネームは原文表示のため）。
- ニックネーム未設定 / 音写失敗の絵文字のみ表示は既存の `displayNickname == nil → emoji only`
  ロジックをそのまま使う（受け入れ条件4・3）。
- 翻訳（`Translator`）と直交する処理だが、端末言語を読む窓口は `Translator.targetLanguageCode`
  を流用するため、`NicknameTransliterator.init` で `targetLanguageCode` を引数で受ける。

## テスト方針
- `SameQTests/NicknameTransliteratorTests.swift`（新規・ユニット）— ja/ko/ar/ru/Latin/diacritics/
  絵文字のみ/空文字/失敗ケースを網羅。
- `SameQUITests/SprintSevenAcceptanceTests.swift`（新規・UI）— 端末言語 ja と en を `-AppleLanguages`
   で切り替えて、画面に出る文字列を `staticTexts` で直接検証。`-SameQNicknameTranslitDebug`
   で「音写失敗 → 絵文字のみ」を確認。
- 回帰は既存の 77 ユニット + 35 UI テストを全件走らせる。
