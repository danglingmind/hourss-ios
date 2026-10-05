# Plain English, everywhere

## The complaint

> The language you are using is too complex to understand.
> You have been giving the reasoning and explanation according to our algorithm
> terms, which is a bad UX. The sentences should be for a normal user who doesn't
> know anything about the engine or our algo. It should be plain and simple
> English reasoning. You need to fix this throughout the app.

Two sentences from the app, given as the two poles:

- **Good.** "Mornings suit focused work for a lot of people."
- **Bad.** "Trimmed from 30m to fit around what you have already logged."

The bad one is not bad because of a rare word. Every word in it is common. It is
bad because it describes **what the app did to a data structure** — took a length,
shortened it, placed it around occupied ranges — and asks the reader to hold that
model in their head. The good one describes **a thing that is true about
mornings**.

## The rule

> Say what is true about the person's day. Never say what the app did to work it
> out.

A reader has a day, hours in it, things they did, and how those felt. That is the
whole of the vocabulary available. They do not have sides, baselines, windows,
contrasts, evidence, membership, or comparisons, and every one of those words is
the app talking about its own insides.

Three tests for a sentence, in order:

1. **Would somebody say this out loud to a friend?** "Your evenings and the rest
   of your day came out about the same" passes. "Your days have been compared, and
   none of them separated from the rest" does not.
2. **Does it name a thing the reader has, or a thing the app has?** Hours, days,
   sessions, how something felt — theirs. Sides, figures, records, evidence — ours.
3. **Could it be shorter without losing the fact?** The bad sentences are almost
   all long. Plainness and brevity turn out to be the same edit.

### What this does not change

**The caution stays.** Plain is not loose. "Mornings suit focused work" is a plain
sentence that makes no causal claim, names no population as an authority, and
promises nothing — `NarrationGuard` still forbids all three, and nothing in this
document relaxes it. A sentence that got plainer by becoming a promise has got
worse.

**Numbers stay where they were earned.** "Morning settled at 4.8 against your 3.5
across 8 days" is not jargon; it is the figures, which somebody asked to see. The
heading above it does not need to be "Evidence so far".

## The translation table

The left column is every construction in the app that breaks the rule, with its
count. The right column is what replaces it. This is the whole of the change; the
phases below are just where it lands.

| Engine phrase | Plain phrase |
| --- | --- |
| X reads against Y / read one against the other | how X feels next to Y / X and Y |
| makes the comparison possible | there would be enough to tell |
| nothing to compare | everything is in one place |
| separated from the rest / stands apart from the rest | came out different from your other days |
| pulling clear of the rest | standing out |
| settled far enough apart to read | the two sets of days clearly differed |
| too close together to tell apart | the two sets came out about the same |
| measured against anything yet | nothing has been checked yet |
| Evidence / Evidence so far / See the evidence | What this is built on / How it is going / See the numbers |
| Pattern membership / Membership | Does this apply to you? |
| Days on both sides / an empty side | Days to compare / nothing on one half of the question |
| An observation, not a rule | Something that repeats, not a rule |
| still standing after every other pattern was checked | it survived being checked against everything else |
| it leans one way, and has not been watched long enough | it tilts one way so far, on too few days to say |
| trimmed from X to fit around what you have already logged | only X free here — the rest is already logged |

## Keeping it

A one-time pass is a pass that drifts back. `NarrationGuard.jargon` holds the left
column's words, and every copy surface already swept by a test sweeps for it too —
eleven suites already treat a `.population` offence as fatal, and the same sweep
reports `.jargon` now. A new sentence carrying "baseline" or "read against"
therefore fails a test rather than shipping.

The list is words, not grammar, so it cannot catch a sentence that is plain in
vocabulary and still describes machinery. That is what the three tests above are
for, and they are judgement rather than code. The word list catches the relapse;
the rule catches the invention.

## Phases

**Phase 1 — the guard.** `NarrationGuard.jargon`, a `.jargon` offence case, and the
list wired into the existing sweep. Done first so that every later phase is checked
by it rather than by me reading.

**Phase 2 — `ExperimentCopy`.** 76 sentences, the largest surface and the one the
owner has been reading all week. Every "reads against", every "comparison", the
three verdict explanations, the sheet's five section headings.

**Phase 3 — Patterns and questions.** `QuestionCopy`, `PatternsView`,
`QuestionAnnouncement`, `InsightDetailView`. "Days on both sides", "Questions with
an empty side", "Your days have been compared", "See the evidence".

**Phase 4 — Today, Tests, You.** `ObservationSlotView` ("Pattern membership",
"Evidence so far"), `TestsScreen`, `YouView`, `ProfileView`, `OnboardingFlow`.

**Phase 5 — the logging sheet.** The trim note, `SlotPicker`'s label, and
`DayContextCard`.

**Phase 6 — the suites.** Full unit run on iPhone 17 Pro by UDID, then the UI
suite. Both green before this is called done.

## Checklist

- [x] **1.** `jargon` list and `.jargon` case; the sweep reports it.
- [x] **2.** Every suite that sweeps copy treats `.jargon` as fatal.
- [x] **3.** `ExperimentCopy`: no "read against", no "comparison", no "figure".
- [x] **4.** The three verdicts said in one short sentence each.
- [x] **5.** The proposal sheet's five headings.
- [x] **6.** `QuestionCopy`: the waiting and open sentences.
- [x] **7.** `PatternsView`: the four bar labels and the nothing-stands state.
- [x] **8.** `QuestionAnnouncement`'s four headings.
- [x] **9.** `ObservationSlotView`: membership, evidence, the still-looking state.
- [x] **10.** `TestsScreen`, `YouView`, `ProfileView`, `OnboardingFlow`.
- [x] **11.** The trim note and `SlotPicker`'s accessibility label.
- [x] **12.** Unit suite green, then the UI suite.
      824 tests in 75 suites, no crashes, 319s.

## What the sweep caught that I would have missed

Three things, all found by the guard rather than by reading:

**"Observed across 43 distinct days"** — in every narrated sentence the engine
produces, which is the most-read copy in the app. "Distinct" was doing real work
for us and none for a reader, who would never imagine the count included the same
day twice. Now "Seen across 53 sessions over 43 days".

**My own rewrite smuggled in an instruction.** "One change you agreed to try"
tripped `instruction("try")` — the history screen may not ask anybody to do
anything, because everything on it has already happened. Plain and permitted are
different axes, and the guard holds both.

**Two words on the list were too broad.** "Membership" caught `YouView`'s paid
plan, which is an ordinary product noun, and "data" would have caught "Health
data", which is what Apple calls it. Narrowed to "pattern membership" and "data
point", with the reason recorded on the list.
