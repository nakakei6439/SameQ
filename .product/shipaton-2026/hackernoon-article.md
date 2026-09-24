# HackerNoon #Shipaton Writing Contest — 下書き（ケータの声で書き直し版）

> 投稿先: HackerNoon（`#shipaton` タグ必須）。**9/27 までに投稿**（編集部の審査で公開まで数日かかりうる。締切 9/30）
> 投稿前に: (1) `【ここに実話を1行】` を埋めるか、その行ごと消す (2) 画像の差し込み（[IMAGE] の箇所）(3) 本文中の数字が最新か
> タグ案: `#shipaton` `#ios` `#app-store` `#indie-dev` `#swiftui` `#revenuecat` `#buildinpublic` `#app-review`
> 声: ケータ（`.claude/agents/sameq-answer-keita.md`）。事実・数字は淡々版と同じ。変えたのは語り口だけ。

---

# Five App Reviews to Ship an Anonymous Social App: What Guideline 1.2 Taught Me

*A build log from RevenueCat Shipaton 2026*

On September 24, 2026, my app SameQ went live on the App Store. Five reviews. Four rejections.
One 13-day wait in the Resolution Center where nothing happened at all.

I'm not here to complain about Apple. Every rejection pointed at something real, even when the
message didn't say what. So this is the practical version: what happened, what I got wrong, and
what I'd do if I were you.

## What SameQ is

Once a day, everyone in the world gets the same question. You write a short answer. **Only
after you answer** can you read how strangers answered, one at a time.

No profile. No follow. No search. No ranking. No replies. You're an emoji and a nickname.
Answers disappear when the day's question ends. And every answer shows up in your own language.
SameQ uses only Apple's on-device Translation framework, so post bodies are never sent to a
translation server. No "translated" badge, no "see original" button. It should just feel like
everyone speaks your language.

It's free. There's one optional subscription, **SameQ Plus**, handled by RevenueCat.

[IMAGE: Today screen / locked timeline / unlocked answer — 3 screenshots side by side]

## How it got built

I'm one developer in my 40s with a day job and a family. So I don't get long, quiet blocks
of time. I get gaps.

【ここに実話を1行: 例「平日は◯時から◯時が開発の時間」など】

First commit: August 17, 2026. By launch day: 197 commits, 23 sprints, 23 Supabase
migrations, about 15,600 lines of Swift, 53 test files.

I didn't type all of that myself, and I'm not going to pretend I did. I ran the project
through three agents on Claude Code:

- A **planner** turns a short idea into a spec with sprints and acceptance criteria.
- A **generator** builds one sprint at a time.
- An **evaluator** runs the app on the simulator and grades it against the criteria.

The evaluator can't edit code. The generator doesn't grade its own work. My job is to decide
what to build, read the reports, and not call anything "done" until it's been checked.

It wasn't smooth. I hit usage limits in the first week and spent days switching between agents
just to keep sprints moving. At one point my 500GB Mac was completely full, and the agent
cleaned it up for me. Fine. Keep moving.

That split between builder and checker paid off in App Review, just not the way I expected.

## Review 1: "The session has expired"

**Build 1.0 (1). Rejected under Guideline 2.1(a), App Completeness.**

The reviewer hit "Your session has expired" during onboarding. I'd already fixed a bug like
this for TestFlight testers. But the build under review was archived *before* that fix.

So what do you do? Before you hit submit, check which commit the archive came from. "I fixed
that last week" means nothing if the fix isn't in the binary.

## Review 2: "We could not see any other users' posts"

**Build 1.0.2 (6). Rejected under 2.1(a) and 2.1(b).**

This one was my own design biting me. SameQ's core rule is *answer first, then read*, and
the database enforces it: the `world_timeline` view returns nothing until you've answered
today's question. On a quiet day with few real users, a reviewer answers and sees... nothing.
The app looks broken.

The fix made the product better. I added `ensure_official_answers()`, a self-healing Postgres
function. The first client that notices today's question has no operator answers inserts them,
and it's safe to run more than once. Now every day has something to read, clearly labeled as
coming from the operator. (The 2.1(b) part was simpler: I hadn't submitted the in-app purchase
for review with the binary. My mistake. Fixed.)

While I was in there, I found a quiet bug: the timeline query wasn't selecting the
`body_language` column, so every post counted as "unknown language." On a device that couldn't
translate, answers in your own language were silently skipped.

So what do you do? If your core mechanic hides content, treat the reviewer as your first user
on your emptiest day. Make sure there's something there.

## Review 3: Guideline 1.2, all eight items at once

**Build 1.0.2 (7). Rejected under 1.2 (User-Generated Content) and 3.1.2 (Subscriptions).**

Guideline 1.2 is the checklist for apps with user-generated content, and Apple wants **all**
of it. Not most. All.

| Apple asks for | What SameQ does |
|---|---|
| A way to filter objectionable content | An English/Japanese blocklist checked **on the device and again on the server**, so a modified client can't skip it |
| A way to report content | Report, with a reason; hidden from your feed right away |
| A way to block abusive users | Block; manage the list in Settings |
| Terms that say you won't tolerate objectionable content | A zero-tolerance clause, summarized right above the required checkbox |
| Acting on reports within 24 hours | Auto-hide after 3 reports (1 if the text matches the blocklist); auto-suspend after 3 hidden posts; a daily manual review |
| Removing your own post immediately | "Delete this answer," a soft delete so the moderation log survives |
| Contact information in the app | "Contact us" as the first row in Settings, also on the suspended-user screen |
| 18+ age rating | Set in App Store Connect |

The 3.1.2 part was about subscription links. While fixing the metadata, I noticed that my
**in-app paywall** was also missing the auto-renewal text and the Terms/Privacy links. The
reviewer never mentioned it, but it was wrong, so I fixed all three places.

So what do you do? With a checklist rejection, don't guess which item they meant. Ship all
eight in one build.

## Review 4: Same rejection. And a note I got wrong.

**Build 1.0.3 (8). Rejected again under 1.2.**

The message repeated the whole list and didn't name a missing item. So I reread my own App
Review Notes, and there it was. I'd written "tap `...` on an answer" to report or block. That
button didn't exist. The real control was a small circled ellipsis in the header, with no
label, and it only showed up after you'd posted your own answer.

I wrote those notes from memory. The reviewer followed my directions and found nothing. That's
on me.

I replied in the Resolution Center. I said the notes were wrong, gave the exact tap sequence
using the labels on screen, and asked which of the eight items they couldn't verify.

Then nothing. For 13 days.

So what do you do? Write review notes from the source, not from memory. Now I pull every button
label from the localization file and the actual view code before I write a single step.

## What I did with those 13 days

Waiting doesn't ship anything. So I stopped waiting and tested like the reviewer: a real
iPhone, device language set to English, no translation models downloaded, the production
server. The simulator wouldn't have shown me any of this.

【ここに実話を1行: 審査待ちのあいだ、生活のほうで何が並行して回っていたか】

- **Tapping fast made answers vanish before you saw them.** A guard was missing, so every extra
  tap marked the next answer as read. The production table showed 5 reads in 7 seconds, and
  that day's answers were used up. I added a regression test.
- **Deleting a post could hang forever**, because requests had no timeout. Every request now
  gives up after 20 seconds.
- **An emoji on the first onboarding screen showed up as a blank box** on a real device.
- **The operator answers had nothing to do with the question.** The prompt pool grew from 48 to
  999 questions, and one of two copies of the same index calculation never got updated. For
  about two weeks, the question and the operator answers were picked by two unrelated numbers.
  Now the answers are matched on the day's actual question text. No second copy, nothing to
  drift.

I also moved Report/Block out of the header and put it right under the answer card, with a
visible label: **Report or block**.

Then on September 24, while I was preparing the next build, Apple approved build 8. It went
live right away. The fixes above go out in the next update.

So what do you do? When a review stalls, act like the reviewer. Every bug on that list would
have hit a real user first.

## Where AI is and isn't in the product

People ask, so here's the straight answer.

- **The app makes no AI calls at runtime.** Today's question is picked by a deterministic
  Postgres function (same UTC day, same question for everyone). Translation is Apple's
  on-device framework.
- **The question pool (999 questions) was drafted with AI before launch**, then I reviewed it in
  batches. Anything culture-specific, leading, or yes/no got cut. A script also checked every
  one: word count, ends with a question mark, no duplicates, no yes/no openers.
- **Operator answers are written with five personas**, and they're labeled that way. Each has
  its own name plus "(SameQ)": a robot that openly says it's an AI, a backpacker who writes in
  English, an ancient dragon, a one-year-old cat, and a practical dad from the Kansai region.
  (That last one is basically me.) None of them pretend to be ordinary users. That was a spec
  rule from day one: no operator content under a name that looks like a regular person.

Early on, my kid said something to me, completely unprompted: *"You can tell when AI made
something."*

That one stuck. I didn't hear it as "don't use AI." I heard "don't hide it." So a person
decides what ships, and anything the operator posts carries the operator's name.

【ここに実話を1行（任意）: その一言を聞いたときの場面】

## RevenueCat

SameQ Plus is a monthly subscription with a one-month free trial. You get longer answers
(2,000 characters instead of 140) and text styling. The core loop (answer, unlock, read) is
free and stays free.

I kept the integration small on purpose. `RevenueCatPlusService` implements a `PlusService`
protocol, so the paywall UI doesn't care what's behind it. A StoreKit version and a fake version
sit behind the same protocol for tests. It fetches the product by App Store product ID, reads
one entitlement called `plus`, and maps RevenueCat's errors to friendly messages (cancelled,
network, other), so a failed purchase never throws a scary dialog at you.

```swift
private static func entitlement(from info: CustomerInfo?, entitlementID: String) -> PlusEntitlement? {
    guard let info, let info = info.entitlements[entitlementID] else { return nil }
    guard info.isActive, let expiresAt = info.expirationDate else { return nil }
    ...
}
```

## Before your first review, do these five things

1. **Treat the reviewer as your user on your emptiest day.** If your app hides content, make
   sure something is there.
2. **With checklist guidelines, ship everything on the list in one build.**
3. **Write review notes from the code.** Every label, every tap, in the order the reviewer will
   see them.
4. **Test on a real device, in a language that isn't yours, against production.**
5. **If one calculation lives in two places, delete one.** Don't count on keeping copies in sync.

That's it. SameQ is on the App Store: https://apps.apple.com/us/app/sameq/id6805425491

Answer today's question. Somewhere, somebody answered it too.

*— Keita Nakagawa, Tokyo. Built solo for RevenueCat Shipaton 2026.*
