# RevenueCat Shipaton 2026 — 準備チェックリスト（Keita Nakagawa / SameQ）

> 提出締切: **2026-09-30**
> ハーフウェイ: **2026-09-01**（「If your app isn't in review yet, get it in this week」）
> 提出先: https://shipaton.com/ (Devpost)
> Devpost 提出物: ① アプリ本体 ② 動画 ③ 説明文 (Submission Statement)

## 状況サマリ (2026-08-30 時点)

- [x] アプリのコア実装 (SameQ v1.0.x)
- [x] アプリ内課金の RevenueCat 統合 (Plus 月額・1 ヶ月無料トライアル)
- [x] TestFlight 外部テスター準備 (v1.0.2 build 4 アップロード済み)
- [x] Devpost Submission Statement ドラフト → `.product/shipaton-2026/submission-statement.md`
- [x] Product Hunt ローンチ資料 95% 完成 → `.product/product-hunt-launch.md`
- [ ] **App Store 公開 (v1.0.0 or v1.0.2 を public release に)** ← 9/1 までに in review
- [ ] **Demo 動画 (英語 1 本)** ← 9/15 までに撮影
- [ ] **Devpost 提出（最終）** ← 9/29 までに余裕持って

## 週次タスク (Day 0 = 8/30 日曜)

### 9/1 (月) - Halfway
- [ ] **App Store Connect で v1.0.0 / v1.0.2 を App Store 公開用に追加提出**
  - iOS 18.0+ deployment target
  - スクリーンショット 6.5" / 6.7" / 6.9" / iPad 各サイズ
  - Privacy Policy URL (要確認: github pages ホスティング or 個人サイト)
  - 暗号化: ITSAppUsesNonExemptEncryption = false (Info.plist 済み)
- [ ] **#Shipaton 初日投稿 (X / Twitter)**
  - 英語: Day 1 of #Shipaton: SameQ is live on TestFlight
  - 日本語: 同上
  - 添付画像: `.product/producthunt/en/01-pain.png` 流用
- [ ] **Devpost アカウント作成 & 仮登録**

### 9/2-7 (火-日) - 外部テスター FB 反映
- [ ] TestFlight build 3 / build 4 のフィードバック収集
- [ ] App Store 審査結果待ち (1〜3 営業日、新 iOS 同時期で長引く可能性)
- [ ] Submission Statement 第 2 稿 (寝かせた目で推敲)
- [ ] 動画シナリオ作成 (10 シーン以内、1〜2 分)

### 9/8-14
- [ ] **Demo 動画撮影**
  - 実機画面収録: 起動 → オンボーディング → お題 → 回答 → 世界タイムライン → Plus paywall
  - 音声解説: 英語 (ネイティブ or 慣れた日本人)
  - 編集: QuickTime + iMovie で軽くトランジション
  - YouTube unlisted にアップロード (Devpost 直リンク可能)
- [ ] アプリ内スクリーンショット (3 種: お題画面 / 回答画面 / 世界タイムライン)
- [ ] Shipaton Discord に参加 → `#product-feedback` で外部 FB もらう

### 9/15-21
- [ ] Devpost フォームに全項目入力
  - Name: SameQ
  - Tagline: One question a day. Write one honest answer — and the world unlocks.
  - Description: ドラフトから貼る
  - Built with: SwiftUI, Supabase, RevenueCat, Apple Translation
  - Gallery: スクショ 3〜5 枚
  - Video: YouTube URL
  - Topics: 待って PH フォームのサジェストで確認
- [ ] **Description の最終リハーサル** (声に出して読み、自然か)
- [ ] App Store 公開 URL を Devpost の Link 欄に貼る

### 9/22-29
- [ ] **Devpost 提出 (9/29 までに)** — 9/30 当日にバタバタしないため
- [ ] 提出後、Apple 側で審査通過していれば公式 Tweet に App Store リンクを追加

## 動画撮影チェックリスト

- [ ] **音声**: 英語 (テキスト起こしを Description 末尾に貼る案もあり)
- [ ] **画面収録ツール**: macOS QuickTime + iPhone Lightning ケーブル or ミラーリング
- [ ] **デモシナリオ** (60〜90 秒):
  1. 起動画面 (3 秒)
  2. オンボーディング — 絵文字選択 (5 秒)
  3. 「次のお題が届くまで…」状態から (5 秒)
  4. 通知で届く → タップ → お題表示 (10 秒)
  5. 回答投稿 (15 秒、テキスト入力中も映す)
  6. 回答後の「自分の回答」カード表示 (5 秒)
  7. 世界タイムライン (15 秒、誰かの回答が翻訳されて見える)
  8. 設定 → 言語切替 → 同じ投稿が翻訳で読める (15 秒)
  9. Plus paywall (10 秒、Paywall が出て購入導線)
  10. お題待ち画面に戻る (5 秒)
- [ ] 編集時の注意: テロップは最小限、英語字幕を付けるとハッシュタグ文化に刺さる
- [ ] 解像度: 1080p or 4K、ファイルサイズ < 100MB

## 逆算タイムライン

```
9/30 (Tue)  ── Devpost 〆
9/29 (Mon)  ── 提出完了（前日）
9/22-28    ── 動画 + Description 最終化
9/15-21    ── Devpost フォーム入力開始
9/8-14     ── 動画撮影 + スクショ
9/2-7      ── App Store 審査 + TestFlight FB
9/1 (Mon)  ── #Shipaton Day 1 投稿 + App Store 提出
8/30       ── ✅ 現状、ここ
```

## 連絡 / 重要リンク

- Devpost: https://shipaton.com/
- 週次ニュースレター: support@devpost.com (Week 4 受信済み)
- Shipaton Discord: https://discord.gg/shipaton26
- HackerNoon ライティングコンテスト: $2,500 in prizes → contests.hackernoon.com/shipaton-writing-contest

## 参考: 評価される要素 (メールから)

> "The optional extras separate the top five from the top hundred"
> — Charlie Chapman, Shipaton 主催

- **動画の完成度** (Pamela Hill: "Give the video real time")
- **Built solo** の明記 (single-developer の本気度)
- **#Shipaton #BuildInPublic の継続投稿**
- **What I learned** に哲学・思想的な深さがあると加点されやすい
- **App Store に実際に並んでる版** をジャッジ対象とする (Apple 審査通す必要)

---

_作成: Mavis / 2026-08-30 21:32 JST_
_参照: https://shipaton.com/, Devpost Week 4 メール_
