# Questions that open

**Status:** proposed, not built
**Date:** 3 October 2026

---

## 1. The idea

Patterns shows what the app has found. It says nothing about what it is *trying* to
find, or how close any of it is.

The engine asks about sixty questions on every run. Each one has a gate it has to
clear — six distinct days on each side — and `Engine.findings` already measures
exactly how far every question is from its gate, then throws that number away:

```swift
guard focus.days.count >= hypothesis.minimumDays,
      baseline.days.count >= hypothesis.minimumDays else { return nil }
```

That discarded number is the whole feature. Every question becomes a card. The
ones that have cleared their gate are open. The ones that have not say what they
are waiting for, in days, kept live. When one opens, it is announced.

## 2. The thing that decides whether this works

**You unlock a question, not an answer.**

An open card can say *nothing stood out here*. That is a real result and the most
common one. If the design implies that opening a card pays out a finding, then the
app becomes a slot machine that mostly pays nothing — and the first empty one
teaches somebody that the whole screen is a tease.

So every piece of copy, every animation and the announcement itself has to carry
one idea: **the app can now ask this. Here is what it found, including nothing.**

Everything below is downstream of that sentence. A locked card that says "unlock
to see what your mornings do" is a lie. One that says "six morning days and six
others — you have four and nine" is the truth, and it is also more interesting,
because it tells somebody what to do.

## 3. What other apps do

**Duolingo's skill tree.** You see the whole map: what is ahead, what it costs,
what is done. The value is the *map*, not the unlocking.
→ **Take:** show every question, including the far-off ones. The space itself is
information — "the app is watching for this" is worth knowing before it arrives.

**Apple Fitness awards.** A reveal with weight: a modal, an animation, a thing that
happened. Awards are always good news, which is the half we cannot copy.
→ **Take:** the announcement is a moment, not a badge that silently appears.
→ **Leave:** the implication that what is revealed is a prize.

**Credit Karma / Monzo.** "We need three months of history before we can show you
this." Honest, specific, unglamorous.
→ **Take:** the locked state says exactly what is missing, in the unit the person
can act in — days, not percentages.

**Oura and Whoop.** No locks at all. They show partial data with a confidence
marker and let you judge.
→ **Consider:** this is the alternative design, and it is the one Hourss already
half-implements with leads on the Patterns tab. Locks and leads must not become two
answers to one question — §7.

**What nobody good does:** lock something that is already known, to manufacture a
reveal. If a question has cleared its gate, it is open. There is no queue.

## 4. The three states

| State | What it means | What it shows |
| --- | --- | --- |
| **Open** | gate cleared, question asked | the finding, or that nothing stood out |
| **Close** | short by a countable amount | what is missing, in days, live |
| **Far** | one side has nothing at all | the thing that has never happened |

**Close and Far are the same state with different copy**, and splitting them
matters: "two more afternoon days" is a task somebody can finish this week. "You
have not logged an evening yet" is a different sentence about a different kind of
gap, and reading the second as the first is discouraging.

## 5. The announcement

When a question clears its gate, it is announced **once**, on the next time the app
is opened.

- It names the question, and **carries the answer with it** — including when the
  answer is nothing. A reveal that defers the answer to a second tap is the slot
  machine.
- It is a sheet, not a toast. A toast is for something that does not matter.
- One at a time. Several opening at once is a queue, not a moment, and a queue
  teaches somebody to dismiss without reading.
- Reduce Motion lands on the finished state, as everything else here does.

**What is stored:** which question keys have been announced. Nothing else — whether
a question is open is derived from the record on every run, like every other claim
in this app.

## 6. What this must not become

- **No score.** Nothing counts how many are open. `RecordFacts` records why at
  length and `abandonExperiment` keeps no tally for the same reason.
- **No streak, no "x% complete".** A completion bar over sixty questions says the
  goal is to open them all, and it is not: somebody whose days are genuinely flat
  will open many and find nothing in most, and that is the engine being right.
- **No ordering by closeness.** Sorting by "nearly there" turns the screen into a
  to-do list of things to go and log, which is how a record becomes a chore.
  Ordering stays by the person's own priorities.
- **Nothing is locked that is known.** No artificial delay, ever.

## 7. Locks against leads

Patterns already has a "Worth testing" section: findings that cleared the gate but
not the correction. That is a third state, and three states is one too many unless
the difference is obvious.

The difference is real: a **lead has been measured and did not separate**, a
**locked card has not been measured at all**. One is an answer, the other is a
question. They belong in different places on the screen and must never share a word
— no "not yet" on both.

**Decide during phase 1** whether leads keep their own section or become a state of
their own card, and write the answer down.

## 8. Risks

| Risk | Judgement |
| --- | --- |
| **It cheapens the app.** A gamified shell on something whose premise is honesty. | The guard is §2: open a question, not an answer. If the copy slips into promising findings, the feature is worse than nothing and should be reverted whole, as two visual changes already have been. |
| **Sixty cards is a wall.** | Group by priority, as Patterns already does, and show the far ones collapsed. The map is the value; the wall is not. |
| **The announcement arrives for something dull.** "Nothing stood out in your afternoons" with an animation. | This is the common case and the design has to be good at it, not apologise for it. The reveal is the same either way — that *is* the honesty. |
| **Live day counts invite gaming.** Somebody logs a session they did not do, to open a card. | Accepted. It is their record, and a record somebody games is a record that stops being useful to them first. |

## 9. Phases

**Phase 1 — the engine stops discarding.** `Engine.findings` returns under-powered
questions with their shortfall instead of nil. Nothing changes on screen. This is
the only phase other phases depend on.

**Phase 2 — the locked card.** Patterns shows every question, open or not, with
what each is waiting for. No announcement yet.

**Phase 3 — the announcement.** Detection, persistence, the sheet, the motion.

**Phase 4 — the map.** Far questions collapsed, the whole space legible without
being a wall.

## 10. Checklist

### Phase 1 — the engine — **done**

Built as `Engine.pending(for:)` and `Engine.Pending`, with `findings` untouched.

**A separate function rather than a flag or a wider return type**, which was the
decision §10 left open. A flag on `Finding` would put an untested question into the
type that the correction, the feed, recommendations and experiments all consume;
each would need a guard, every guard would need a test, and one missed guard puts a
claim on screen that six days of evidence never supported. With two types there is
nothing to leak, and a test pins that the two lists are disjoint.

**One thing found by writing the test.** An empty record already has nine pending
questions — four time buckets, four durations, workdays — because none of those
depends on what somebody logged in order to *exist*. So the map is readable on day
one, before anything has been logged at all, which is the half of this feature
worth more than the unlocking.

- [x] **1.** A `Shortfall` value: which side is short, by how many days, and what the
      gate is.
- [x] **2.** `Engine.findings` returns these rather than dropping them. The existing
      return type must not change meaning — callers that want only testable findings
      keep getting exactly those.
- [x] **3.** Nothing under-powered may reach the correction, the feed,
      recommendations or experiments. A test pins each.
- [x] **4.** The shortfall is computed from days, never sessions.

### Phase 2 — the card — **done**

**Leads are not a third state.** §7 left this open and the answer collapsed it: a
lead is a question that cleared its gate, was measured, and did not separate — which
is what an *open* card says when the answer is nothing. Giving it a section of its
own said a measured non-answer belongs somewhere other than with the answers, which
is the opposite of what this app believes. So there are two states, open and
waiting, and the standalone leads section is gone.

Close and far stayed one state told apart by its sentence, as planned.

**One thing the copy got wrong first.** A single noun template produced "Nothing
logged in your 180 min or more yet" — a duration is a property of a session, not a
place in the day, and an activity is neither. The phrasing is now keyed off the
registry's own family. A second pass found "No a session in your evening yet",
whose test had hedged with an `||` instead of failing; both are fixed and the test
asserts the grammar now.

### Phase 2 — the card
- [x] **5.** Three states, derived, never stored.
- [x] **6.** Copy per state, in days. "Far" names the thing that has never happened.
- [x] **7.** Open cards show the finding or that nothing stood out.
- [x] **8.** Grouped by priority, as now. No ordering by closeness.
- [x] **9.** Decide leads versus locks and write it into `DESIGN.md`.

### Phase 3 — the announcement — **done**

**Detection and announcing are separate acts.** `rebuildInsights()` records which
questions the engine can now ask — free, because `findings` has just returned
exactly those — and nothing else. Speaking is one call,
`HourssStore.announceOpenedQuestion()`, made once by `HourssApp`'s launch task.
That split is what §5's "next time the app is opened" requires: the rebuild runs
many times a launch, including the instant a rating clears a gate, and a sheet
raised from there would interrupt somebody for logging. It is called after Health
rather than from the store's `init`, because `healthByDay` is not in the record —
so a health question announced at restore would never be announced at all.

**Nothing guards against being called twice, because the keys are spent first.**
The told set is written and persisted before the sheet is raised, so a second call
in the same launch finds nothing new and so does the next launch. Marking on the
way in rather than on dismissal loses a sheet somebody force-quits out of; the
alternative is a sheet that returns until it is dismissed in one particular way,
and the question is open on Patterns with its answer either way.

**Nil is a missing baseline and `[]` is an empty one**, which is the one place this
field breaks the house habit of collapsing empty arrays to nil. Missing means no
baseline has been taken — a new record, or the first launch of this build for
somebody with months of history — and that run absorbs everything already open in
silence. Collapsing the two would have made a new person's empty baseline read as
a missing one on their next launch, swallowing the first question they ever opened,
which is the one the feature exists for. A test pins it.

**One at a time means no backlog.** When several open together, one is announced
and the rest are marked told with it rather than drip-fed over later launches —
that is still the queue §5 refuses, only spread thin enough to be hard to see.

**Two things found by reading the sentences the cohorts actually produce.**
Lowercasing a registry label gave "Days with higher hrv"; only the first character
is sentence-cased now, so an acronym survives. And the possessive template gave
"Your Meetings sessions", because several default activities are already plural —
that family now borrows the registry's own "your time in Meetings". Neither would
have failed a test written from the template.

- [x] **10.** `Record.announcedHypotheses: [String]?`, optional, schema bump, and the
      `PersistenceTests` tripwire updated deliberately.
- [x] **11.** Detection on rebuild; one at a time; never on first run, when
      everything would open at once.
- [x] **12.** The sheet carries the answer, including nothing.
- [x] **13.** Motion through `Motion`; Reduce Motion lands finished.
- [x] **14.** A test that an announcement never fires twice for one question.

### Phase 4 — the map — **done**

**A `DirectionalLink` that opens in place, labelled "Questions with an empty
side".** The system `DisclosureGroup` brings a chevron, an indent and a spinning
triangle onto a screen whose only action idiom is bold text and an oversized
arrow, and it is the settings shape the tests entry was moved off You to escape. A
screen of its own was the other candidate and loses for the reason the leads
section lost: putting the never-happened questions behind a navigation boundary
says they belong somewhere other than with the questions they are listed among.
The name does not change when it opens — while the rows show, that line is the
only thing standing over them saying what they are — so the arrow turns, `↘` to
`↗`, one control changing state rather than two swapped. `DESIGN.md` carries the
full argument, along with the phase 2 decision about leads, which item 9 recorded
in `QuestionCopy` and here but not there.

**No count on the lid, and none computed anywhere.** "4 more questions" is a fact
about the screen and would have been legal; it sits one word from "4 of 12 open",
and a figure beside a fold is the first thing a reader starts comparing between
sections. The label locates the gap in the question rather than in the person —
"things you have not logged" was the first draft and is one step from a list of
errands, which §6 refuses by name. One untouched question is printed rather than
given a lid, because a lid over a single row spends the line it saves; the
threshold of two is the only number in the feature.

**The wall is not there, and that is the finding.** §8 budgeted for sixty cards.
The seeded fixture mints thirty-four hypotheses, twenty-seven of which have
already cleared their gates, so the whole waiting list is seven questions across
three priorities — two, three and none — and no priority holds more than one whose
side has never happened. The fold is therefore correct, tested and dormant on every
record this repo can produce. It engages on a thin or lopsided record: an empty
record has eight untouched questions under Focus alone, and `shortHistory` has
three. Both of those are `isWarmingUp`, so **Patterns does not draw the map at all
in exactly the state the fold exists for** — `isWarmingUp` is "no visible
insights", which is also "nothing has cleared a gate yet". Whether the map should
appear beside the warm-up readout is a product decision and was left alone; it is
the one thing standing between this feature and the day-one value phase 1 found.

- [x] **15.** Far questions collapsed by default.
- [x] **16.** The whole space readable at `AccessibilityL`. The lid's label is laid
      out in DM Sans Bold at the `UIFontMetrics` scaled size and counted, rather
      than budgeted in characters, and the measurement is proved able to fail.

### Verification
- [ ] **17.** Full unit suite on iPhone 17 Pro by UDID, then the UI suite.
- [ ] **18.** `DebugFixture` can reach all three states and an announcement.
