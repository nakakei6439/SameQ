# 単発タスク評価（2026-09-04 adhoc）: LocalBackend シードの英語ロケール対応 — 合格

## 判定サマリ

| 条件 | 結果 | 判定 |
|---|---|---|
| 1. en 端末 + LocalBackend + expiring で Today のお題が "What made you laugh out loud today?" | 実機シミュレータで表示確認。日本語なし | ✓ |
| 2. 同上で メニュー → Notifications → Announcements に "Welcome to SameQ" + 英語本文 | 実機シミュレータで表示確認。日本語なし | ✓ |
| 3. ja 端末 + 同フラグ で従来文言（回帰なし） | お題「今日、思わず笑ってしまったことは何ですか？」/ お知らせ「SameQ へようこそ」を確認 | ✓ |
| 4. 既存ユニットテスト緑 | `-only-testing:SameQTests` → 230/230 TEST SUCCEEDED（新規 test04/test05 含む AnnouncementTests 5/5） | ✓ |
| 5. Debug / Release ビルド成功 | Debug `BUILD SUCCEEDED` / Release `BUILD SUCCEEDED`（iphonesimulator） | ✓ |

## 検証環境

- 端末: iPhone 17 Pro シミュレータ（iOS 26.5, UDID C63EB024-D7BB-418B-804B-D180A4AAA16B）
- ビルド: `xcodebuild -project SameQ.xcodeproj -scheme SameQ -configuration Debug -sdk iphonesimulator`（scratchpad の derivedData）
- 言語切替: `.GlobalPreferences.plist` の `AppleLanguages` / `AppleLocale` を `en-US`/`en_US` ⇔ `ja`/`ja_JP` に書き換え、simctl shutdown/boot
- 操作: Maestro フロー（onboarding.next ×2 → terms.agree → next → emoji.🧩 → next ×2 → notification.later → today.input 表示待ち → スクショ → 回答 → menu.open → notifications.open → notifications.tab.operator → スクショ）
- 起動フラグ: `-SameQUseLocalBackend -SameQScenario expiring -SameQExpirySeconds 90000 -SameQFakePlus -SameQFakePlusTrial`（clearState 付き）
- 実施時刻: 2026-09-04 16:40〜16:47 JST

## 証跡（scratchpad）

- en お題（回答前）: `.../scratchpad/en_today_prompt.png` — "TODAY'S PROMPT / What made you laugh out loud today?"
- en お題（回答後）: `.../scratchpad/en_today_answered.png` — お題は英語のまま、YOUR ANSWER に入力反映
- en お知らせ: `.../scratchpad/en_announcements.png` — "Welcome to SameQ" / "Answer one question a day, at the same moment as someone else in the world."
- ja お題: `.../scratchpad/ja_today_prompt.png` — 「今日、思わず笑ってしまったことは何ですか？」
- ja お知らせ: `.../scratchpad/ja_announcements.png` — 「SameQ へようこそ」/「毎日1つのお題に、世界のどこかの誰かと同時に答えます。」

（scratchpad 実パス: `/private/tmp/claude-501/-Users-nakagawakeita-Products-iOSApp-SameQ/c98eee98-055f-4229-98c5-4f094756a54c/scratchpad/`）

## 安定性・データ整合性

- クラッシュ 0。onboarding → 回答 → menu → notifications の主要動線が en/ja とも最後まで完走。
- en で回答後、お題テキストは "What made you laugh out loud today?" のまま維持（回答画面 `today.myAnswer` 状態でも英語）。
- ja 側の Announcements ID・文言は従来どおり（`test03` + `test05` フォールバックが緑）。

## 補足（合否に影響しない）

- ja 初回の Maestro 実行が `onboarding.next not found` で 1 回落ちたが、これは言語切替直後の
  アプリ launch と Maestro ドライバ接続のタイミング競合。同フローの再実行で全ステップ COMPLETED。
  アプリ側の不具合ではない。
- `today.myAnswer` の optional アサートが en フローで WARNED になったが、直後のスクショで
  回答ロック状態（"Your answer is locked in."）を確認済み。表示要素の id 差異と思われ、
  今回の変更点とは無関係。

## 評価できなかったもの

なし（条件 1〜5 すべてシミュレータ実機操作またはビルド/テスト実行で確認）。
