# Devpost Submission Statement — SameQ for RevenueCat Shipaton 2026

> 提出前に Devpost フォームの字数・必須項目と突き合わせてから貼ること。
> 文字数は Devpost 側の "Tell us more" フィールドが 5000 chars 程度は許容する想定だが、
> 画像や動画フィールドは別なので本文は短めに意識する。

---

## App name
**SameQ**

## Tagline (80 chars 以内)
**One question a day. Write one honest answer — and the world unlocks.**

---

## Description (paste into Devpost form)

SameQ is an iOS app where, once a day, everyone in the world gets the same
question. You write a short, honest answer. **Only after you write yours**
can you read how one stranger, somewhere, answered the same thing.

There is no profile to curate, no feed to scroll, no one to follow, no
likes to chase. The mechanic is the product: **you can't peek until you
answer**. Words fade after a while. Every answer shows in your own
language, automatically — we use Apple's on-device translation framework
only, and never send post bodies to a server.

Anonymity is total: no email, no phone, just an emoji you pick. The app
is free, with one optional subscription — **SameQ Plus** (handled by
RevenueCat) — for longer posts and text styling. The core experience
stays free forever.

### Why I built it

I was tired of social media as performance: curating a profile, chasing
likes, watching a feed that never ends. SameQ strips that down to one
thing per day. I built the first version over 18 sprints as a solo
developer, on an iPhone 17 Pro.

The hardest call I made was: **don't generate the questions with AI.**

My kid told me two things while I was working on this app, both
unprompted:

> "AI has no love."

> "You can tell when generative AI made it."

That crystallized something I'd been circling. The whole point of
SameQ is that there's a person behind every question. If the questions
are machine-generated, the answers feel anonymous in a bad way — not
"the author stayed anonymous" but "nobody is here." So the question
pool is curated by hand (with deterministic, fair rotation), and the
roadmap includes a feature where the most-appreciated answerers
periodically get to write the next day's question. **The prompt has
the writer's fingerprint on it.** That's the contract.

### Built with

- **SwiftUI** + **Observation** (`@Observable`) — fully native, no third-party UI
- **Supabase** — Postgres + Auth + Row Level Security + Edge Functions; 12 migrations so far
- **RevenueCat** — `RevenueCat_Purchases` SDK (purchases-ios 5.87.1) for the Plus subscription
- **Apple Translation** — on-device, no external translation API, no server-side translation
- **Xcode 17F113 / iOS 26.5 SDK** — minimum deployment target iOS 18.0
- **No LLM is used in the product.** Everything the user sees is curated or user-generated.

### RevenueCat integration

`RevenueCatPlusService` (or its `StoreKitPlusService` / `FakePlusService`
test-only variants) configures `Purchases` with a sandboxed API key.
The single entitlement is `plus`, mapped to a monthly subscription
product with a 1-month free trial (`PlusIntroductoryOfferTests` verify the
trial length, intro offer eligibility, and post-trial renewal).

Paywall surface:
- `PlusView` shows the intro offer, manage-subscription deep link into
  iOS Settings, and the legal text (terms / privacy)
- Trial state is checked at app launch and on view appearance; cached
  state is restored when the SDK is offline (so a Plus user never falls
  back to free on a flaky network — `attempt 4` of the `refreshPlusEntitlement`)

### The dark corners (what I learned the hard way)

1. **Constraints create the product.** No follow, no like, no profile,
   no search — these aren't missing features, they're the design.
   Every "should I add this?" question gets answered by "would this
   feel like a like-chase if I did?"
2. **The hardest part is the question pool.** I tried every shortcut:
   Edge Functions, fixed catalogs, "smart" rotation. The only thing
   that worked was committing to a hand-curated, fairly-rotated,
   visible-to-anyone pool, and being honest about it.
3. **Auto-translation must be invisible.** Showing a "translated"
   badge or a "view original" button puts the language back in the
   user's face. SameQ's UI shows only the user's own language, and the
   server never sees a post body — translation happens on device.
4. **The launch-day bug taught me to design for the "between days"**.
   Prompts run on a 28-hour cycle to absorb timezone variance, but the
   day-boundary gap is real. The self-healing migration I shipped on
   2026-08-30 (the day this statement was drafted) fixed a silent-fail
   in the server-side "fill today's prompt" routine that was the
   underlying cause of a TestFlight feedback report.

### What's next

- Like-ranking question curation (the feature my kid's quote made me
  commit to building)
- More languages: I want to support every iPhone language eventually
- A version of the app that ships the question of the day as a
  Home Screen widget, so the question finds the user instead of the
  other way around

### Tech by the numbers

- ~5,000 lines of Swift across the `SameQ/` target
- 12 Supabase migrations, 6 of which ship server-side enforcement
- 100+ unit tests + UI tests across 22 test files
- 0 LLM calls in the product
- 1 developer (me)

---

## Links to include in Devpost form

| フィールド | 値 |
|---|---|
| App Store URL (when live) | `https://apps.apple.com/app/id6805425491` |
| TestFlight build (during Shipaton) | `https://testflight.apple.com/join/xv7kJFRm` |
| GitHub (private during Shipaton) | (Devpost 側で non-public OK か確認) |
| Demo video (when ready) | YouTube unlisted or Devpost direct upload |

## What I'm asking Devpost / RevenueCat

I'm not looking for a winner badge — I'm looking for early users who
read the mechanic and either love it or tell me it's wrong. The former
are the people SameQ is for. The latter are the people I learn from.

If you try it, please send me a one-sentence reaction. I read every
TestFlight feedback and every App Store review.

— Keita Nakagawa (中川景太)
Tokyo, 2026-08-30

---

# 提出前セルフチェック

- [ ] App Store で `apps.apple.com/app/id6805425491` が生きている
- [ ] Demo video がリンク先から再生できる
- [ ] Devpost フォームの文字数制限（5000 chars 前後）に収まっている
- [ ] スクリーンショット 1〜3 枚が添付されている（Product Hunt 用の `.product/producthunt/en/*.png` を流用可）
- [ ] RevenueCat の項目に「Subscribes via RevenueCat SDK 5.87.1」と記載
- [ ] "Built solo" を明記（Built with 節の末尾）
- [ ] 子の言葉は 1 箇所にのみ使う（多用しない、AI べた褒めにならないように）

# Devpost フォームの「Built with」チェック候補

Devpost 側で「Built with」をタグ / 自由記述で書く欄があれば:
- SwiftUI / iOS / Supabase / RevenueCat / Apple Translation Framework

---

_ドラフト作成: Mavis / 2026-08-30 21:30 JST_
_提出時に Kids quote の利用方針を再検討してから投稿_
