# HackerNoon #Shipaton Writing Contest — 下書き

> 投稿先: HackerNoon（`#shipaton` タグ必須）。**9/27 までに投稿**（編集部の審査で公開まで数日かかりうる。締切 9/30）
> 投稿前に: (1) App Store の URL が開くか確認 (2) 画像の差し込み（[IMAGE] の箇所）(3) 本文中の数字が最新か
> タグ案: `#shipaton` `#ios` `#app-store` `#indie-dev` `#swiftui` `#revenuecat` `#buildinpublic` `#app-review`

---

# Five App Reviews to Ship an Anonymous Social App: What Guideline 1.2 Taught Me

*A build log from RevenueCat Shipaton 2026*

On September 24, 2026, my app SameQ went live on the App Store. It took five reviews, four
rejections, and one 13-day wait in the Resolution Center.

This is not a complaint post. Every rejection pointed at something real, even when the message
didn't say what it was. Here is what happened, what I got wrong, and what I'd tell anyone
shipping an app where strangers can post.

## What SameQ is

Once a day, everyone in the world gets the same question. You write a short answer. **Only after
you answer** can you read how strangers answered, one at a time.

There's no profile, no follow, no search, no ranking, no replies. You are an emoji and a
nickname. Answers disappear when the day's question ends. And every answer shows up in your own
language: SameQ uses only Apple's on-device Translation framework, so post bodies are never
sent to a translation server, and there is no "translated" badge or "see original" button. It
should feel like everyone is simply speaking your language.

It is free. One optional subscription, **SameQ Plus**, is handled by RevenueCat.

[IMAGE: Today screen / locked timeline / unlocked answer — 3 screenshots side by side]

## How it was built

I'm a solo developer. The first commit was on August 17, 2026. By launch day there were
197 commits, 23 sprints, 23 Supabase migrations, roughly 15,600 lines of Swift and
53 test files.

I didn't write all of that by hand. I ran the project through a three-role agent setup on
Claude Code: a **planner** turns a short idea into a spec with sprints and acceptance criteria,
a **generator** implements one sprint at a time, and an **evaluator** runs the app on the
simulator and grades it against the criteria. The evaluator can't edit code, and the generator
doesn't grade its own work. My job was deciding what to build, reading the reports, and
refusing to call something done until it had been checked.

That separation paid off in App Review, just not the way I expected.

## Review 1: "The session has expired"

**Build 1.0 (1). Rejected under Guideline 2.1(a), App Completeness.**

The reviewer hit a "Your session has expired" error during onboarding. I had already fixed a
bug like this for TestFlight testers, but the build under review was archived before that fix.

**Lesson:** before you submit, check which commit the archived binary was built from. "I fixed
that last week" means nothing if the fix isn't in the binary.

## Review 2: "We could not see any other users' posts"

**Build 1.0.2 (6). Rejected under 2.1(a) and 2.1(b).**

This one was my own design working against me. SameQ's core rule is *answer first, then
read*, and it's enforced in the database: the `world_timeline` view returns nothing unless you
have answered today's question. On a quiet day with few real users, a reviewer who answers
sees... nothing. The app looks broken.

The fix changed the product for the better. I added `ensure_official_answers()`, a
self-healing Postgres function. The first client that notices today's question has no operator
answers inserts them, and it's safe to run more than once. Every day now has at least a few
answers to read, clearly labeled as coming from the operator. (The 2.1(b) part was simpler: I
hadn't submitted the in-app purchase for review alongside the binary.)

I also found a quiet bug while I was there: the timeline query wasn't selecting the
`body_language` column, so every post was treated as "unknown language." On a device that
couldn't translate, answers in your own language were silently skipped.

**Lesson:** if your core mechanic hides content, the reviewer is your first user on your
emptiest day. Design for that day.

## Review 3: Guideline 1.2, all eight items at once

**Build 1.0.2 (7). Rejected under 1.2 (User-Generated Content) and 3.1.2 (Subscriptions).**

Guideline 1.2 is the checklist for apps with user-generated content, and Apple says you need
**all** of it:

| Apple asks for | What SameQ does |
|---|---|
| A way to filter objectionable content | An English/Japanese blocklist checked **on the device and again on the server**, so a modified client can't skip it |
| A way to report content | Report, with a reason; hidden from your feed right away |
| A way to block abusive users | Block; manage the list in Settings |
| Terms that say you won't tolerate objectionable content | A zero-tolerance clause, a summary shown right above the required checkbox |
| Acting on reports within 24 hours | Auto-hide after 3 reports (1 if the text matches the blocklist); auto-suspend after 3 hidden posts; a daily manual review |
| Removing your own post immediately | "Delete this answer," a soft delete so the moderation log survives |
| Contact information in the app | "Contact us" as the first row in Settings, also on the suspended-user screen |
| 18+ age rating | Set in App Store Connect |

The 3.1.2 part was about subscription links. While fixing the metadata, I noticed that my
**in-app paywall** was also missing the auto-renewal text and the Terms/Privacy links. The
reviewer hadn't mentioned it, but it was wrong, so I fixed all three places.

**Lesson:** when you get a checklist rejection, treat it as "all or nothing." I shipped all
eight in one build instead of guessing which one they meant.

## Review 4: the same rejection, and a note I got wrong

**Build 1.0.3 (8). Rejected again under 1.2.**

The message repeated the full list and didn't name a missing item. So I reread my own App
Review Notes and found the problem. I had written "tap `...` on an answer" to report or
block. That button didn't exist. The real control was a small circled ellipsis in the header,
with no label, and it only appears after you post your own answer.

I had written those notes from memory. The reviewer followed my directions and found nothing.

I replied in the Resolution Center. I admitted the notes were wrong, gave the exact tap
sequence using the labels shown on screen, and asked which of the eight items they couldn't
verify. Then nothing happened for 13 days.

**Lesson:** write review notes from the source, not from memory. I now pull every button
label from the localization file and the actual view code before writing a single step.

## What I did during those 13 days

I stopped waiting and tested the app the way the reviewer would: a real iPhone, the device
language set to English, no translation models downloaded, the production server. The
simulator wouldn't have shown what I found.

- **Tapping quickly made answers vanish before you saw them.** A guard was missing, so each
  extra tap marked the next answer as read. The production table showed 5 reads in 7 seconds;
  that day's answers were used up. I added a regression test.
- **Deleting a post could hang forever**, because requests had no timeout. Every request now
  gives up after 20 seconds.
- **An emoji on the first onboarding screen showed as a blank box** on a real device.
- **The operator answers had nothing to do with the question.** The prompt pool had grown
  from 48 to 999 questions, and one of two copies of the same index calculation was never
  updated. For about two weeks, the question and the operator answers were picked by two
  unrelated numbers. Now the answers are matched on the day's actual question text, so there's
  no second copy to fall out of sync.

I also moved Report/Block out of the header and put it right under the answer card with a
visible label: **Report or block**.

Then, on September 24, while I was preparing a new build, Apple approved build 8. It went live
immediately. The fixes above are in the next update.

**Lesson:** a review that won't move is a good time to act like the reviewer. Every bug in
that list would have met a real user first.

## Where AI is and isn't in the product

People ask, so here it is.

- **The app makes no AI calls at runtime.** Choosing today's question is a deterministic
  Postgres function (same UTC day, same question for everyone). Translation is Apple's
  on-device framework.
- **The question pool (999 questions) was drafted with AI before launch**, then reviewed by me
  in batches. I rejected anything culture-specific, leading, or yes/no. It was also checked by
  script: word count, question mark at the end, no duplicates, no yes/no openers.
- **Operator answers are written with five personas**, and they're labeled that way. Each has
  its own name plus "(SameQ)": a robot that says openly it's an AI, a backpacker who writes in
  English, an ancient dragon, a one-year-old cat, and a practical dad from the Kansai region. They never
  pretend to be ordinary users. That line was a spec rule from the start: no operator content
  under a name that looks like a regular person.

Early on, my kid said, unprompted: *"You can tell when AI made something."* I didn't take that
as "don't use AI." I took it as "don't hide it." A person decides what ships, and anything the
operator posts carries the operator's name.

## RevenueCat

SameQ Plus is a monthly subscription with a one-month free trial. It gives you longer answers
(2,000 characters instead of 140) and text styling. The core loop (answer, unlock, read) is
free and always will be.

The integration is small on purpose. `RevenueCatPlusService` implements a `PlusService`
protocol, so the paywall UI doesn't know which backend it's talking to. A StoreKit version and
a fake version sit behind the same protocol for tests. It fetches the product by App Store
product ID, reads a single entitlement called `plus`, and maps RevenueCat's errors to
friendly messages (cancel, network, other), so a failed purchase never shows a scary dialog.

```swift
private static func entitlement(from info: CustomerInfo?, entitlementID: String) -> PlusEntitlement? {
    guard let info, let info = info.entitlements[entitlementID] else { return nil }
    guard info.isActive, let expiresAt = info.expirationDate else { return nil }
    ...
}
```

## What I'd tell you before your first review

1. **The reviewer is your user on your emptiest day.** If your app hides content, make sure
   something is there.
2. **With checklist guidelines, ship everything on the list in one build.**
3. **Write review notes from the code.** Every label, every tap, in the order the reviewer
   will see them.
4. **Test on a real device in a language that isn't yours, on production.**
5. **If one calculation is copied in two places, remove the dependency.** Don't count on
   keeping the copies in sync.

SameQ is on the App Store: https://apps.apple.com/app/id6805425491

If you try it, answer today's question. Somewhere, someone answered it too.

*— Keita Nakagawa, Tokyo. Built solo for RevenueCat Shipaton 2026.*
