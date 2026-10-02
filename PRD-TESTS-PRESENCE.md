# Making a test feel like something

**Status:** proposed, not built
**Date:** 2 October 2026

---

## 1. The problem

Taking on a test is the most important thing this app asks anybody to do. It is
also the quietest.

Today a proposal is a card below the fold. Accepting it is a tap on a text link —
the same weight as "Add how it felt". Once it is running it is one card among
cards. The list of what you have tested is two taps deep inside You.

Nothing about any of that says this is the thing the app is for.

## 2. What other apps do

Four patterns worth stealing from, and one worth avoiding.

**Research consent flows (ResearchKit, Apple Heart Study).** Joining a study is a
short sequence of plain screens: what this is, what you will do, how long, what we
measure, then agree. It feels significant *because* it is a sequence rather than a
button. Nothing is hidden and nothing is long.
→ **Take:** a sheet, with the same four questions, in that order.

**Challenges (Strava, Apple Fitness).** Opt in, time-boxed, progress visible every
day without looking for it, a result at the end. This is structurally the same
thing Hourss is doing.
→ **Take:** daily presence. A test in progress should be visible without scrolling.

**Whoop's journal behaviours.** You tag a habit daily and it reports "on days you
did X, your recovery was Y% higher". The hook is not the commitment, it is that the
report arrives and is specific.
→ **Take:** we already do the report. Make it arrive louder.

**Streaks and habit apps.** A commitment moment, then a number that only goes down.
→ **Avoid.** We have decided against streaks twice, for the reason `RecordFacts`
records: a number whose only movement is downward is a thing to protect rather than
a thing to learn from.

## 3. What to build

### A. A sheet to accept

Tapping a proposal opens a sheet instead of starting it. The sheet answers four
questions, in plain words, in this order:

1. **What you would do.** The change, set large. One sentence.
2. **Why this one.** What the app saw, with the numbers and the day count.
3. **How it decided.** One honest line — what it compared, and that it compared you
   with yourself.
4. **What you get at the end.** All three answers, named up front: it held up, it
   did not, or there was not enough to tell.

Then: how long, what gets measured, and the limit. One button to start, one quiet
line to decline.

**Point 4 is the unusual one and it is the point.** Saying beforehand that a test
can come back "no difference" does two things: it makes a result that holds up feel
earned, and it stops a null result reading as the app being broken. Nobody else
does this because nobody else is prepared to publish their failures. We are.

### B. Visible every day

A test in progress gets a thin strip under the Today header: what it is, and
whether today is one of its days. No scrolling. It is the one thing in the app
somebody has agreed to do, so it should not be something they have to go and find.

### C. One place that is the feature

A **Tests** screen holding all three states together — what is on offer, what is
running, and everything finished. Reached from the strip and from Patterns.

Today the three live in three different places and none of them is the feature.

### D. The weight it is drawn with

A settled result is a forest card because it is the rarest thing the app shows. A
proposal should be too. The whole lifecycle is the loud thing, not just its end.

That reverses a judgement made earlier — that a proposal "arrives whenever the
engine has something, and a card that is emphatic every other week is just the
house style". That reasoning was right about frequency and wrong about importance,
and frequency is the smaller consideration.

## 4. What stays the same

- **No streaks, no counts, no score.** Nothing tallies how many held up.
- **A null result is presented exactly as loudly as a positive one.**
- Plain words. "Session", not "block". "Two weeks", not "this fortnight".
- Nothing moves to a tab it does not deserve; this adds one screen, not a section.

## 5. Phases

**Phase 1 — the sheet.** The accept moment becomes a decision instead of a tap.
Biggest change in how it feels, and it needs no new navigation.

**Phase 2 — daily presence.** The strip on Today.

**Phase 3 — one home.** The Tests screen, and the list moves out of You.

**Phase 4 — weight.** The proposal card takes the forest surface.

## 6. Checklist

### Phase 1 — the sheet
- [ ] **1.** `TestProposalSheet`, raised from the proposal card and from Patterns.
- [ ] **2.** Four sections in the order above, from `ExperimentCopy` only — no second
      wording for anything already said elsewhere.
- [ ] **3.** "How it decided" needs a sentence per standing: confirmed, lead,
      starter. Three honest lines, no maths.
- [ ] **4.** "What you get" names all three verdicts, in the words the result will
      actually use.
- [ ] **5.** The randomised option is the second control *in the sheet*, where its
      ask has room to be read.
- [ ] **6.** Accepting dismisses to a short confirmation: what was started, when it
      ends, and the day list if drawn.
- [ ] **7.** Declining is one quiet line, and still permanent.
- [ ] **8.** Copy sweep over every new string; `instruction` lifted, the rest not.

### Phase 2 — presence
- [ ] **9.** A strip under the Today header while a test runs: the change, and
      today's state for a drawn window.
- [ ] **10.** It is not shown when nothing is running. No empty state in a header.

### Phase 3 — one home
- [ ] **11.** `TestsView`: on offer, running, finished — in that order.
- [ ] **12.** The record screen moves there; `You → Tests` becomes a link to it.

### Phase 4 — weight
- [ ] **13.** The proposal card takes `blockSurface(.forest)`, and `isCarded` covers
      both states.
- [ ] **14.** Check on device that two forest cards never appear at once.

### Verification
- [ ] **15.** Full unit suite on iPhone 17 Pro by UDID, then the UI suite.
- [ ] **16.** `DebugFixture` can reach every state of the sheet.
