# Devpost Submission — SameQ (RevenueCat Shipaton 2026)

> 2026-09-24 に全面改稿。8/30 版は「お題を AI で作らない／製品内 LLM ゼロ」を柱にしていたが実態と合わないため破棄。
> 締切: **2026-09-30 23:45 PDT = 日本時間 10/1 15:45**。目標は 9/29 中に提出。
> 応募部門: **#BuildInPublic Award / RevenueCat Design Award / RevenueCat Peace Prize / HAMM Award**（Grand Prize は全作品が自動で対象）
> 数字は 2026-09-24 に実測（コミット 197・スプリント 23・migration 23・Swift 約15,600行・テストファイル 53）。

---

## Name
SameQ

## Tagline
One question a day. Answer it, and the world's answers unlock.

## Links
| 欄 | 値 |
|---|---|
| App Store | https://apps.apple.com/us/app/sameq/id6805425491 （9/24 に配信国を設定し、米国・日本とも 200 を確認） |
| Video | https://youtube.com/shorts/HHfCszrPHQ8 （47秒） |
| Judge access | SameQ Plus has a 1-month free trial, so judges can try every premium feature at no cost. |

## Description

SameQ is an iOS app where everyone in the world gets the same question once a day. You write
a short answer. **Only after you answer** can you read how strangers answered, one at a time.

- **Answer first, then read.** The database enforces this, not just the UI: the timeline
  returns nothing until you've answered today's question.
- **No profile, follow, search, ranking, or replies.** You are an emoji and a nickname. Answers
  disappear when the day's question ends.
- **Everyone speaks your language.** Posts are translated on the device with Apple's
  Translation framework. Post text is never sent to a translation server, and there is no
  "translated" badge or "see original" button.
- **Safe by default.** Report and block are always one tap away. A blocklist is checked on
  the device and again on the server. Reported posts are hidden automatically, and repeat
  offenders are suspended automatically.
- **Never empty.** Five operator personas post clearly labeled answers every day, so the first
  person to answer on a quiet day still has something to read.

Free to use. **SameQ Plus** (RevenueCat) is a monthly subscription with a one-month free trial.
It gives you 2,000-character answers instead of 140, and text styling. The core loop stays free.

## How it was built

Solo developer. First commit August 17, 2026; live on the App Store September 24 after five
reviews. I built it with a three-role agent setup on Claude Code: a planner writes the spec,
a generator builds one sprint at a time, and an evaluator runs the app and grades each sprint
against acceptance criteria. The evaluator never edits code, and the generator never grades its
own work. I decide what ships.

**Where AI is and isn't used:** the app makes no AI calls at runtime. Today's question is picked
by a deterministic Postgres function. The 999-question pool was drafted with AI before launch,
then reviewed in batches and checked by script. Operator answers come from five personas, each
labeled with its name plus "(SameQ)". One of them openly says it's an AI. None of them pretend to
be ordinary users.

## Built with
SwiftUI (iOS 18+), Supabase (Postgres, anonymous Auth, Row Level Security, RPC functions),
RevenueCat (purchases-ios 5.87.0), Apple Translation framework, NaturalLanguage framework.

## RevenueCat integration
`RevenueCatPlusService` implements a `PlusService` protocol. The paywall doesn't know which
backend it's using, and StoreKit and fake versions sit behind the same protocol for tests. It
fetches `com.nakakei6439.SameQ.plus.monthly` by product ID and reads the `plus` entitlement.
RevenueCat errors become friendly messages (cancelled, network, other), and Restore is supported.
The paywall shows the free-trial badge from the product's introductory offer, the auto-renewal
terms, and links to the Terms and Privacy Policy.

---

## Category: #BuildInPublic Award

**Social links**（全14件の一覧は `buildinpublic-links.md`）
- X profile: https://x.com/nakakei6439
- Day 1 — first try at an agent harness: https://x.com/nakakei6439/status/2089309411353501751
- Public beta on TestFlight: https://x.com/nakakei6439/status/2094252470927257663
- Stuck in App Review: https://x.com/nakakei6439/status/2096362463340228625
- Approved: https://x.com/nakakei6439/status/2102877623382888782
- HackerNoon build log: https://hackernoon.com/how-sameq-survived-four-app-store-rejections（9/28 公開）
- Launch day (EN): https://x.com/nakakei6439/status/2102955516893040997
- Launch day (JA): https://x.com/nakakei6439/status/2102955672686194847
- Demo video: https://youtube.com/shorts/HHfCszrPHQ8
- Article announcement on X: https://x.com/nakakei6439/status/2104870985015169038
- Submission announcement on X: https://x.com/nakakei6439/status/2105041174373474672

**How building in public helped**

I posted from day one, in Japanese and English: my first attempt at a planner/generator/evaluator
agent harness, running into usage limits, switching models to keep sprints going, the public
TestFlight beta, and the weeks stuck in App Review. Building in public forced me to write down
what went wrong while it was still happening, and that record is how the app got fixed.

- **TestFlight feedback → a real bug.** Testers reported "no question right now" at certain
  hours. Tracing it led to a silent failure in the database function that creates each day's
  question (an overlap constraint), fixed in v1.0.2 on August 30.
- **Five App Reviews, logged in the open.** Every rejection and every reply to the reviewer is
  written up in the repo. That's how I caught that my own review notes pointed the reviewer to a
  button that didn't exist.
- **Explaining the app out loud changed it.** Writing "the reviewer is your user on your
  emptiest day" led to operator answers, so nobody opens an empty timeline. Explaining the
  answer-first lock led to moving Report/Block right under each answer.
- **Honesty about AI.** Saying publicly where AI is and isn't used became a rule in the product:
  anything the operator posts carries the operator's name.

---

## Category: RevenueCat Design Award

SameQ is designed mostly by what it leaves out.

- **The lock is the product.** Other people's answers stay hidden until you write yours, so you
  answer honestly instead of copying the room. Then answers appear one at a time. You can't
  scroll back, so each one gets your full attention.
- **Translation you never notice.** No language picker, no badge, no "see original." Answers
  show a brief "preparing…" state instead of flashing the original language, so strangers simply
  appear to speak your language. Even nicknames are transliterated into your script.
- **Nothing to chase.** No follower counts, no rankings, no feed that never ends. Answers
  disappear when the day's question ends.
- **Calm by default.** One question a day, delivered at a random time, so it arrives like a
  small surprise rather than a streak to protect.
- **Safety that stays out of the way.** Report or block is one tap below any answer, with a
  visible label, and nothing is sent to the other person.

Watch in the video: the timeline unlocking after you answer, one stranger's answer at a time, and
the Plus paywall.

---

## Category: RevenueCat Peace Prize

**Impact.** Most social apps sort people into audiences and feeds. SameQ puts one stranger in
front of you, answering the same question you just answered, in your own language. You can't
find their profile, follow them, or argue with them. You just see that someone far away thought
about the same thing today. It's a small, daily counter to feeds that make the world feel
hostile and divided.

It's also built to be safe for people who don't want to be found: no email, no phone number, no
profile, and post text is never sent to a translation server.

**Feasibility and scale.** It's cheap and robust enough to run for years:
- No AI calls or translation API at runtime, so cost doesn't grow per message. Translation runs
  on each user's device.
- Each day's question comes from a self-healing database function. The first client that
  notices it's missing creates it, so there's no cron job and no daily batch to break.
- Moderation runs mostly on its own: blocklist on the device and the server, auto-hide after
  reports, auto-suspend for repeat offenders, and a short daily manual review.

---

## Category: HAMM Award

> 価格と無料トライアルは 2026-09-24 に App Store Connect API で確認済み（米国 $2.99/月、日本 ¥500/月、1ヶ月無料トライアル）。
> 数字は 9/29–30 に ASC Analytics・RevenueCat Overview の実測値へ差し替え済み。

**Strategy: charge for more room to express yourself, never for access.**

SameQ's core loop (answer today's question, unlock strangers' answers, read them in your
language) is free, forever. Charging for the core loop would break the product: the more people
answer, the more everyone gets to read. So the paywall never locks reading or answering.

**SameQ Plus** sells *more room to express yourself*, which is what engaged users want once the
daily habit forms:
- Longer answers: up to 2,000 characters instead of 140
- Text styling: bold/italic, "balloon" asides, and Plus-only stamps

**Pricing.** One auto-renewing monthly plan: **$2.99/month** in the US (¥500 in Japan),
set per territory in App Store Connect. No tiers and no annual plan at launch. One choice keeps the
paywall simple and honest for a small, calm app.

**Free trial.** Every new subscriber gets **one month free**, long enough to go through about
30 daily questions and find out whether writing longer actually matters to them. The paywall reads
the free-trial badge from the product's introductory offer through RevenueCat, so the offer shown
always matches the one in App Store Connect.

**Where the paywall shows up.** Only when you're already trying to write:
- A soft "Want to write more?" card below your own answer, after you've posted
- The Plus button in the header and the menu

There are no interstitials, no paywall at launch, and no countdown timers.

**How it's built.** `RevenueCatPlusService` implements a `PlusService` protocol: fetch by
product ID, a single `plus` entitlement, purchase and restore. RevenueCat errors are mapped to
calm messages (cancelled, network, other), so a failed purchase never shows a scary dialog. The
paywall includes the auto-renewal terms and links to the Terms of Use and Privacy Policy
(required by Guideline 3.1.2, which we got right on the second try).

**Results so far (live since September 24, 2026).** Downloads: 8 (Sep 24–27; App Store
Connect Analytics, later days not yet processed as of Sep 29). Trials started: 0.
Active subscriptions: 0. Revenue: $0. It's early: the launch was held up by five App Reviews. The model is built to last: no per-message costs (no
translation API, no runtime AI calls), so even a small number of subscribers covers the
Supabase bill.

---

## Grand Prize（全作品が自動で対象。「公開後の成長」の欄）

> 9/29–30 に ASC（App Analytics）と RevenueCat から数字を取り、実測値へ差し替え済み。

SameQ went live on September 24, 2026 in 175 countries and regions after five App Reviews.
Since launch: 8 downloads and 0 Plus trials started (Sep 24–27; App Store Connect Analytics
data for later days is not yet processed).
Growth work so far has been building in public on X (Japanese and English), an in-app
announcement for each version, and a build log on HackerNoon. Every day's question also comes
with answers from five labeled operator personas, so the first visitors from any country find
something to read instead of an empty room.

---

## Notes for the judges（Devpost「Additional notes」欄に入力済み）

How to try SameQ (the version on the App Store is 1.0.3):

1. Answer first. SameQ hides everyone else's answers until you answer today's question. Type any short answer and submit it.
2. Tap "Read the world's answers" to meet strangers' answers, one at a time. Answers from five labeled operator personas (e.g. "Robo (SameQ)") are posted every day, so there is always something to read.
3. Translation follows your device language. On an English device, answers written in other languages show up in English. The first time, iOS may need a moment to download the translation model; the app shows "Preparing…" instead of the original text.
4. SameQ Plus: open Plus from the header or the menu. The 1-month free trial unlocks every premium feature (2,000-character answers, text styling, stamps).
5. Report / Block: in 1.0.3 it is the circled "..." at the top right of the answers screen. The next update (1.0.4) moves it right under each answer with a visible "Report or block" label; the demo video shows that newer layout.

Built solo. Thanks for taking the time to try it.

---

# 提出前セルフチェック（9/30 最終確認済み）
- [x] App Store URL が米国から開く（US/JP とも 200 を再確認）
- [x] 動画: 46秒・YouTube で公開・実機の画面が映っている（oEmbed 200 で公開設定を確認）
- [x] アイコン 1024×1024 / スクショを添付（Devpost 5/5 steps done）
- [x] #BuildInPublic のリンクをすべて実URLに差し替えた（HackerNoon 記事・X告知2本含む）
- [x] 審査員向けアクセス（1ヶ月無料トライアル）を記載
- [x] Devpost 各欄の文字数上限に収まっている（保存エラーなし）
