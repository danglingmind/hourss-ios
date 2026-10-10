# Asking for the right thing at the right hour

**Status:** proposed, not built
**Date:** 10 October 2026

---

## 1. What is wrong today

One sentence, eight times a day, forever:

> **What are you doing right now?**
> One tap to log it.

It is the same at 8am and at 8pm, the same on a Tuesday as on a Saturday, and the
same whether the person agreed to a fortnight yesterday or has never run a test in
their life. Meanwhile the app knows, precisely, what logging it is short of — the
Patterns screen lists it — and knows exactly what it asked anybody mid-experiment to
do and when.

So the app has the information to ask well and does not use it.

---

## 2. The constraint that decides the architecture

**There is no server and no background execution.** A notification's content is
baked in when it is *scheduled*, not when it fires. Nothing can run at 9am to decide
what 9am should say. Everything must be computed ahead, written as pending requests,
and recomputed the next time the app is opened.

That is not a limitation to work around. It is the shape of the solution: a
**scheduler that runs on foreground**, reads the record, and writes a bounded set of
pre-baked requests covering the next few days.

### 2.1 Repeating buys forever; dated buys specific

Today's mechanism is one **repeating** calendar alarm per hour — eight requests cover
every day until the end of time, which is why reminders keep working for somebody who
has not opened the app in a week. The README calls that "the whole requirement".

Specific content cannot repeat: "log a session this Saturday" is wrong on Sunday. It
needs **dated** requests, which fire once and expire. And iOS caps pending requests
at **64**:

| Frequency | Per day | Days of lookahead if every request is dated |
| ------ | ------ | ------ |
| Hourly | 15 | 4 |
| Every two hours | 8 | 8 |
| Every three hours | 5 | 12 |
| Twice a day | 2 | 32 |

An hourly user who stops opening the app goes silent in four days. That is a real
regression from a property the app currently has.

**Resolution: split the hours, not the mechanism.** A small number of hours are
*reserved* for dated, specific asks over the next seven days; the remaining chosen
hours keep their repeating generic alarm. The two sets are disjoint, so two
notifications can never land in one hour, and the app never falls silent — the worst
case is that it goes back to saying the generic thing.

Three reserved hours over seven days is 21 dated requests, plus the generic
remainder. Comfortably inside 64 at every frequency.

---

## 3. The frequency setting becomes a budget

Somebody who chose "every two hours" did not ask for that sentence eight times. They
said **"up to eight interruptions a day is alright with me"**. That is a budget, and
today it is spent on one sentence repeated.

The engine spends the same budget on the most useful asks it has. It follows that a
better notification system should usually send **fewer** notifications than the
current one, not more: an ask worth making is worth making once, and the rest of the
budget is better left unspent than filled.

**Nothing here may raise anybody's chosen frequency.** The budget is a ceiling the
person set, and a scheduler that quietly exceeds it has taken something it was not
given.

---

## 4. The trap, and the rule that avoids it

The app knows a question is two days short. It is *very* tempting to say so:

> **Two more mornings and we will know.**

**That is forbidden, and the reason is already written down.** `PRD-LOCKS.md` §6
refuses a tally anywhere in the product, and refuses anything that turns a record
into a chore — it is why the question map is not sorted by closeness, why no screen
counts how many questions are open, and why the fold carries no "4 more" beside it. A
notification that counts down is the same gamification the app refuses on screen,
arriving by a route where nobody can see it alongside the rules it breaks.

It is also, specifically, a reason to log that is **not about the person's day** —
which is the one thing the record may never acquire.

> ### The rule
> **A notification may say what to do. It may never say how close they are.**

| Allowed | Refused |
| ------ | ------ |
| "Fancy a morning block?" | "Two more mornings and we will know." |
| "Saturdays are a blank page so far." | "You have logged 0 of 6 weekend days." |
| "You said you would try 9am this week." | "4 of 10 days done." |

The second column is every sentence that makes logging a score.

---

## 5. What may ask, and in what order

Five sources. Priority is by **what the person has already agreed to**, then by how
specific the ask can be.

### 5.1 A running test — highest

They agreed to it. The fortnight is spending their attention right now and the app
knows exactly what it asked for and when: `Experiment` carries the hypothesis, and
an hour-led one carries the hour itself.

A drawn window knows more still — `assignment` says which days were picked, so a
randomised test can ask only on days it drew, and say nothing on the days whose whole
job is to be left alone.

### 5.2 A session logged but not rated — second

The cheapest win in the app. The session is already there; the engine cannot use it
without a rating, and `ratedShare` is a number this app watches. One short prompt a
few hours after a session ends, at most once a day.

This is the only source that is *event-driven* rather than calendar-driven, and it is
schedulable the moment a session ends — a dated request at `end + n hours`, cancelled
if the rating arrives first.

### 5.3 A waiting question that is close — third

`Engine.pending` gives the hypothesis and both day counts. A `time.*` shortfall
targets a band; a `workday.*` shortfall targets a day type; an `activity.*` shortfall
targets a thing they do. All three are targetable to an hour and a weekday.

**Short questions only, never untouched ones.** `Pending.isUntouched` marks the
questions whose one side has never happened, and `PatternsView.partition` already
puts those behind a fold because a list of things somebody has never done is a wall
rather than a prompt. A notification about one is worse: on screen it can be folded
away, and in a notification it cannot.

### 5.4 The generic reminder — the floor

Today's behaviour, at every hour not reserved above. It is what keeps the app working
for somebody who never opens it.

### 5.5 Nothing

A real option and the default when no source has anything worth saying. An unspent
budget is not a failure.

---

## 6. Avoiding overlap and avoiding spam

- **One ask per hour, by construction.** Reserved hours and generic hours are
  disjoint sets, computed together.
- **The daily cap is the person's own frequency**, never more.
- **One ask per source per day.** A running test gets one prompt a day, not one per
  reserved hour.
- **A cooldown per ask.** The same question may not be asked two days running, so a
  single stubborn gap cannot colonise the week.
- **Nothing outside 8am–10pm.** Existing, tested, and not negotiable — a 3am
  notification is not a reminder, it is a reason to turn the app off in Settings.
- **Rescheduled on every foreground**, so an ask they have already satisfied is
  withdrawn rather than fired. This is the only cancellation the architecture
  allows, and it is why the horizon is days rather than weeks.

---

## 7. The content

Short, plain, and a little playful — and it is a **new copy surface**, so it answers
to `NarrationGuard` like every other.

Three properties beyond the sweep:

- **Two lines at most**, and the first must stand alone: a lock screen truncates, and
  a sentence that needs its second half is a sentence nobody read.
- **A pool per ask, not one string.** The same words every Tuesday is the problem
  this document opens with, reproduced one level down. A small rotation, chosen
  deterministically from the day so two schedules of the same state agree.
- **No engine words.** `PRD-PLAIN.md` governs: no baseline, no comparison, no
  evidence, no pattern. "Saturdays are a blank page so far" rather than "non-workday
  side is short".

---

## 8. What this is not

- **Not a new permission.** Authorisation is already asked for in onboarding's eighth
  beat, and nothing here asks for more than was granted.
- **Not a re-prompt.** Somebody who chose "not at all" gets nothing, forever, and the
  scheduler never reconsiders that.
- **Not a growth mechanic.** No streaks, no counts, no "you are nearly there". §4.
- **Not a second voice.** Anything a notification says, the app would say the same
  way on screen.

---

## 9. Open decisions

1. **Does the generic floor stay?** Keeping it means the app never goes silent and
   means somebody sometimes gets the old sentence. Dropping it makes every
   notification specific and lets the app lapse for anybody who stops opening it.
   Proposed: keep it, because lapsing silently is the worse failure and is invisible
   to us.
2. **How many hours are reserved.** Proposed three, which bounds dated requests at 21
   for a seven-day horizon. More specificity costs lookahead.
3. **Whether an unrated session may be chased at all.** It is the highest-value ask
   and also the one closest to nagging about a chore. Possibly once, never twice.
4. **Whether a randomised test may notify on its unassigned days.** It must not ask
   for the change — but a day drawn to be left alone still wants a rating if
   something was logged, and saying nothing at all may read as the test having
   stopped.

---

## 10. Checklist

### Phase 1 — the engine
- [ ] **1.** `NotificationPlan`: a value listing what to ask, at which hour, on which
      date, from which source — computed from the record, testable without iOS.
- [ ] **2.** Priority, caps and cooldowns in the plan, not at the scheduling call.
- [ ] **3.** Reserved and generic hours disjoint by construction, with a test.
- [ ] **4.** Never outside 8am–10pm; the existing test extended to the new path.
- [ ] **5.** Never more requests a day than the person's own frequency.

### Phase 2 — the asks
- [ ] **6.** A running test's ask, including drawn windows.
- [ ] **7.** The unrated-session ask, cancelled when the rating arrives.
- [ ] **8.** A short waiting question's ask; untouched ones excluded, with a test.
- [ ] **9.** The generic floor at every unreserved hour.

### Phase 3 — the words
- [ ] **10.** A pool per ask, chosen deterministically from the date.
- [ ] **11.** Every string through `NarrationGuard`.
- [ ] **12.** A test that no notification states a count, a shortfall or a share —
      §4, enforced rather than remembered.

### Phase 4 — the seams
- [ ] **13.** Rescheduled on foreground; satisfied asks withdrawn.
- [ ] **14.** Pending requests stay under the iOS cap at every frequency, with a test
      that computes the worst case rather than assuming it.
- [ ] **15.** `DebugFixture` can reach a plan containing each kind of ask.

### Verification
- [ ] **16.** Full unit suite on iPhone 17 Pro by UDID, then the UI suite.
