# Shipaton デモ動画 — 台本と編集指示

> 条件: **2分未満**（審査員は2分より先を見なくてよい）、YouTube か Vimeo で**公開**、動いているアプリが映っていること。
> 素材: `video-clips/full-take.mp4`（iPhone 16 シミュレータ・英語 UI・78.8秒・無音・H.264・2026-09-24 収録）
> 静止画: `assets/01-today.png` `02-timeline.png` `05-plus.png`（1179×2556）
> 仕上がりの目標: **約75秒**。音声は字幕のみでも可（読み上げを入れる場合は下の字幕をそのまま読む）。

## 素材の中身（full-take.mp4 のタイムコード）
| 時間 | 映っているもの | 使う？ |
|---|---|---|
| 0.0–5.7 | ホーム画面 → アプリ起動（白画面） | ✂ 削る |
| 5.7–18.4 | オンボーディング（規約同意 → 絵文字を選ぶ → 通知は後で） | 7.0–18.4 を 2倍速で約6秒 |
| 18.4–24.9 | 今日のお題に回答を入力して送信 | そのまま約6秒 |
| 24.9–26.1 | 回答後、世界の回答が開く | そのまま |
| 26.1–67.5 | 世界の回答（見知らぬ人の1件）。**41秒間止まっている** | 先頭の約6秒だけ使う |
| 67.5–74.6 | 閉じる → メニュー → お知らせ → メニュー | ✂ 削る（または 2倍速で2秒） |
| 74.6–76.6 | Plus 画面（1ヶ月無料トライアル・¥480） | 短いので `05-plus.png` の静止画を4秒 |
| 76.6–78.8 | Today に戻る | 締めに使う |

注意: Plus 画面の価格は検証用の偽データ（`-SameQFakePlus`）で **¥480** と出ている。米国の審査員向けには、
静止画にテロップ「Price shown in your local currency」を足すか、価格の部分がはっきり映らない尺にする。

## 構成と字幕（英語）
| # | 尺 | 画面 | 字幕 |
|---|---|---|---|
| 1 | 0:00–0:05 | 黒地にタイトル → `01-today.png` | **SameQ** — One question a day, for everyone in the world. |
| 2 | 0:05–0:11 | オンボーディング（2倍速） | No email. No phone number. Just an emoji. |
| 3 | 0:11–0:17 | 今日のお題 → 回答を入力 | Everyone gets the same question today. You answer first. |
| 4 | 0:17–0:20 | 送信 | You can't peek until you answer. |
| 5 | 0:20–0:28 | 世界の回答が開く | Then you meet one stranger's answer. One at a time, in your language. |
| 6 | 0:28–0:34 | 同じ画面（「Report or block」に寄る） | No followers. No feed. Report or block is one tap away. |
| 7 | 0:34–0:42 | `02-timeline.png` をゆっくりズーム | Answers are translated on your device. Post text never goes to a translation server. |
| 8 | 0:42–0:50 | `05-plus.png` | SameQ Plus, powered by RevenueCat: longer answers and text styling. 1-month free trial. |
| 9 | 0:50–0:56 | Today に戻る | The core is free, forever. |
| 10 | 0:56–1:05 | 黒地 | Built solo for RevenueCat Shipaton 2026. **SameQ** on the App Store. |

合計 約65秒。余裕があれば #5 の見知らぬ人の回答をもう一件（スワイプ）足してもよい。ただし素材には2件目が無いので、撮り直しが要る。

## 足りていないもの（正直に）
- **翻訳の実演が無い**: シミュレータは端末内翻訳のモデルが無いので、日本語の回答が英語で出る場面は撮れない。
  実機（英語端末＋翻訳モデル取得済み）で画面収録するか、字幕での説明に留める。
- **スワイプで次の人に進む場面が無い**: 素材には1件目しか映っていない。

## 公開
- YouTube に**公開**（限定公開は不可の可能性。ルール上は "publicly visible"）。タイトル案: `SameQ — One question a day (RevenueCat Shipaton 2026)`
- URL を `submission-statement.md` の Video 欄に貼る。
