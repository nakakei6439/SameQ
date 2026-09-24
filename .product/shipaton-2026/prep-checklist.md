# RevenueCat Shipaton 2026 — 準備チェックリスト（2026-09-24 更新）

> 締切: **2026-09-30 23:45 PDT = 日本時間 10/1 15:45**。目標は 9/29 中に提出。
> 提出先: Devpost（https://revenuecat-shipaton-2026.devpost.com/）
> 応募部門: **#BuildInPublic Award**（主軸）/ **RevenueCat Design Award** / **RevenueCat Peace Prize** / **HAMM Award**（Grand Prize は自動で対象）
> 別枠: **HackerNoon #Shipaton Writing Contest**（記事を `#shipaton` 付きで 9/30 までに公開）
> 8/30 版の計画は破棄した（お題を AI で作らない、という前提が実態と違ったため）。

## 状況
- [x] 1.0.3 (8) が App Store で公開（2026-09-24。ASC 上は READY_FOR_SALE）
- [ ] **ストアのページが開くか**: 9/24 時点では `apps.apple.com/us/app/id6805425491` と `/jp/` の両方が 404、iTunes lookup も 0 件。
      公開直後の反映待ちとみられる。**9/25 に再確認し、まだ 404 なら ASC で配信国（米国を含むか）を確認する**（米国から入手できることが応募条件）
- [x] RevenueCat で課金（Plus 月額・1ヶ月無料トライアル）→ 審査員向けのアクセスはトライアルで満たす

## 成果物
| ファイル | 中身 | 残作業 |
|---|---|---|
| `submission-statement.md` | Devpost 本文＋部門ごとの文章 3 本（英語） | #BuildInPublic のリンク欄（TODO）、動画 URL |
| `hackernoon-article.md` | HackerNoon 記事の下書き（英語・約1,800語） | 画像の差し込み、**9/27 までに投稿** |
| `assets/icon-1024.png` | アイコン 1024×1024 | なし |
| `assets/01-today.png` `02-timeline.png` `05-plus.png` | スクショ 1179×2556、英語 UI、端末フレームなし | Devpost には 1 枚あればよい。`02-timeline` か `01-today` を推奨 |
| `SameQ-Shipaton-demo.mp4` | 完成版デモ動画（46秒・1080×1920・字幕と BGM 入り。実画面を `video-build/build.py` で編集） | YouTube に公開して URL を本文へ |
| `video-script.md` | 編集指示・英語字幕・足りていないもの | — |

## 残タスク（ユーザー）
- [x] 9/24: X の投稿14件を集めて #BuildInPublic 欄を埋めた。追加投稿の下書き4本は `buildinpublic-links.md`
- [ ] 9/25: Shipaton（Devpost）の参加登録が済んでいるか確認する（HackerNoon の賞も登録が前提）
- [ ] 9/26–27: HackerNoon のアカウント作成、記事の投稿（`#shipaton` タグ）
- [x] 9/24: 動画を YouTube に公開 → https://youtube.com/shorts/HHfCszrPHQ8
- [ ] 9/28–30: #Shipaton #BuildInPublic 付きの投稿を足す（公開の報告、審査の振り返り、記事の告知、提出の報告）
- [ ] 9/29: Devpost に入力して提出

## 提出前の確認
- [ ] ストアの URL が米国から開く
- [ ] 動画は2分未満で、公開設定になっている
- [ ] 部門を3つ選び、それぞれの欄に文章を入れた
- [ ] 本文の数字が最新（コミット数などは提出日に取り直す）
