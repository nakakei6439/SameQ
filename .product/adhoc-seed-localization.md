# 単発タスク（spec スプリントではない）: LocalBackend のシード内容を英語ロケール対応にする

## 背景

App Store 用マーケティングスクショを ja / en の2言語で撮っている。撮影は
`-SameQUseLocalBackend -SameQScenario expiring` で LocalBackend（オフライン決定論）
経路を使う。ja は問題なし。en で撮ると、端末言語が English でも次の2箇所が
**日本語のまま**表示され、英語版スクショとして使えない:

1. **今日のお題の本文** — `SameQ/Resources/SeedData.json` の `prompt_001` の
   `text`「今日、思わず笑ってしまったことは何ですか？」が言語固定。
   `SeedCatalog` がこれをそのまま `Prompt.text` にしている。
2. **運営お知らせの本文** — `SameQ/Backend/LocalBackend.swift` の
   `announcements(locale:)` が locale を無視して
   「SameQ へようこそ / 毎日1つのお題に、世界のどこかの誰かと同時に答えます。」を
   常に返す。

シミュレータでは Apple Translation が全ペア未対応を返すため、翻訳経由では英語化
できない。LocalBackend が読むシード自体を端末言語で出し分ける必要がある。

## やること

### 1. `SeedData.json` の `prompt_001` に英語テキストを持たせる

- `File.SeedPrompt`（`SameQ/Backend/SeedCatalog.swift`）に任意フィールドを1つ追加。
  形式は任意だが、シンプルに `textEn: String?` か
  `textLocalized: [String: String]?` のどちらか。他の seed prompt（prompt_002 以降）
  には付けなくてよい（`.live` の受け入れ条件で prompt_001 しか使わないため）。
- `prompt_001` の英語文: **"What made you laugh out loud today?"**
- `SeedCatalog` で `Prompt` を組み立てるとき、端末 UI 言語が英語
  （`L10n.isJapanese == false`。`L10n` は同 target 内から参照可）なら英語文を、
  そうでなければ従来の `text`（日本語）を `Prompt.text` に入れる。
- `promptLanguage` の扱いは既存のまま（英語表示時は `"en"` を入れるのが自然だが、
  表示に影響しないなら現状維持でも可。判断は実装側に委ねる）。

### 2. `LocalBackend.announcements(locale:)` を locale 対応にする

- `locale == "en"` のとき英語の Announcement を返す。それ以外は現状の日本語のまま。
  （`locale` は既に `"ja"` / `"en"` のどちらかで渡ってくる。`Backend.swift` の
  ドキュメントコメント参照。）
- 英語版:
  - title: **"Welcome to SameQ"**
  - body: **"Answer one question a day, at the same moment as someone else in the world."**
- `id` は言語で変えてよい（別 UUID）か、同じでも可。実装判断に委ねる。

## 触ってよいファイル

- `SameQ/Resources/SeedData.json`
- `SameQ/Backend/SeedCatalog.swift`
- `SameQ/Backend/LocalBackend.swift`
- 必要ならこれらに対応する既存ユニットテスト（`SameQTests/`）

## 触らないもの

- Supabase 経路（`SupabaseBackend`）。本番のお題・お知らせは別途 `announcements`
  テーブル運用で ja/en 別行を入れている。今回は LocalBackend だけの話。
- 翻訳ロジック（`Translator`）。
- スプリント spec / state.json。これは spec 外の単発対応。

## 受け入れ条件（evaluator が実機/シミュレータで確認する）

1. 端末言語 **English** + `-SameQUseLocalBackend -SameQScenario expiring` で起動 →
   オンボーディング後の「Today's prompt」に **"What made you laugh out loud today?"**
   が表示される（日本語文が出ない）。
2. 同上で メニュー → Notifications → Announcements タブに
   **"Welcome to SameQ"** の英語お知らせが表示される（日本語文が出ない）。
3. 端末言語 **日本語** + 同フラグ → お題は「今日、思わず笑ってしまったことは
   何ですか？」、お知らせは「SameQ へようこそ」のまま（回帰なし）。
4. 既存のユニットテストが緑（`SeedCatalog` / `LocalBackend` / announcements 関連。
   シード構造を変えたら関連テストも更新）。
5. Debug / Release ともビルド成功。

## 自己評価（self-review）に書くこと

- 変更したファイルと差分の要点
- en / ja 両方で 1〜3 を満たすことをどう確認したか（シミュレータ操作 or テスト）
- 追加/更新したテスト
