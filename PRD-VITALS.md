# Suggestions with a reason behind them

**Status:** proposed, for discussion. Nothing built.
**Date:** 4 October 2026

---

## 1. What is wrong now

Gap-filling (`ExperimentGaps`, uncommitted) offers a test because one side of a
comparison is empty: *no sessions in your evening yet, try some.*

That is a fact about the record and **not a reason to do anything**. Somebody whose
work ends at 3pm and who then sleeps has no evening sessions because they have no
evenings, and telling them to log one is the app talking without knowing anything.
The emptiness is their life, not a gap.

The older sources are not much better. `ExperimentStarters` builds from stated
priorities and a Health reading about something else entirely, and **never looks at
what somebody logs** — so it can propose a morning session to a person who already
works every morning.

So: what should actually be behind a suggestion?

## 2. Two kinds of evidence, and only one may be spoken

**Their own body.** What this person's vitals do across their own day. Personal,
specific, and already computed.

**What is known about bodies in general.** Chronobiology, alertness curves, the
afternoon dip. Real knowledge, and about *people*, not about this person.

The app's standing rule forbids the second: `NarrationGuard` bans "studies",
"research", "most people", "typical". That rule is the reason the app can say *this
is about you*, and it should not be lifted.

**But there is a legitimate middle, and the code already uses it.**
`Surprise.expectedness` holds "the share of people this pattern ordinarily holds
for", with a note on it saying *never shown*. It decides what is **surprising**, not
what is true.

That is the honest use of population knowledge, and it is how science works:

> **A prior chooses what to test. The person's own data decides the answer.**

"Most people dip after lunch, so work mornings" is forbidden and should stay
forbidden. "Most people dip after lunch — worth finding out whether you do" is a
*choice of question*, and the answer still comes from a fortnight of their own
ratings. Nothing about the prior ever reaches the screen.

## 3. What their own vitals already know

`Physiology.Fit` fits a per-person heart-rate baseline on `Cell { band, isWorkday }`
— morning / midday / afternoon / evening, workday or not — from a rolling sixty-day
window, with four windows required before a cell earns its own number rather than
borrowing the day type's.

**It is used only as a denominator.** Every session's residual is measured against
it, and nothing ever reads the *shape* of it. But the shape is the thing being
asked for here: where in their own day their body sits differently.

This needs no new permission, no new reading, and no new computation. It needs the
numbers to stop being private.

## 4. Why this cannot repeat the 3pm mistake

**The curve only exists where somebody lives.** A cell gets a baseline from four
windows of that person's actual day. Somebody who sleeps from four in the afternoon
has no evening windows, so there is no evening baseline, so **the app can never name
an evening to them.**

That is the structural difference from gap-filling, and it is the strongest argument
for this approach. Gap-filling reasoned from absence and so pointed at exactly the
hours somebody does not have. This reasons from presence and can only ever point at
hours they do.

## 5. The chain, and where it breaks

> their vitals say the body sits differently at X
> → their ratings say that direction goes with better sessions
> → so: try the thing they care about at X, and find out

The second step is `PRD-CALIBRATION.md`, built: it learns from somebody's own
ratings whether a raised residual travels with better or worse sessions **for
them**. Without it, "your heart rate is lower in the morning, work there" is an
efficiency claim the app has no grounds for and no licence to make.

**And that is where it breaks.** The calibration needs six rated days a side — which
the flat-record person, the one this whole thread is about, may not have. So the
full chain is available to somebody who already rates a lot, and the person who
needs it most may be short of it.

Options, none free:
- Offer the test on the vitals difference alone, phrased as a reading and not a
  verdict, and let the fortnight decide. **Weakest evidence, strongest honesty.**
- Wait for the calibration. Correct, and leaves the hard case unserved.
- Use a population prior to pick the question and the person's vitals to pick the
  hour, saying neither. **Most useful, and the one that needs the most care.**

This is the main thing to decide and it is not decided here.

## 6. The line the copy has to hold

**A reading, never a verdict.**

| Allowed | Forbidden |
| --- | --- |
| "Your heart rate sits lowest in your late mornings." | "Your late mornings are your most efficient." |
| "Worth finding out whether deep work lands better there." | "Deep work will land better there." |
| "Your body reads differently across your day." | "Your body is at its best at 10am." |

The first column states what was measured and proposes a test. The second makes a
claim about performance from a cardiac reading, which is a medical opinion the app
does not have and will not get from sixty days of wrist data.

`NarrationGuard`'s clinical ban already forbids most of the right-hand column.
Nothing here loosens it.

## 7. Settled

**Hour, not a gate.** Fit hourly where there is enough density and fall back to the
band where there is not. Accuracy improves where somebody logs a lot; nothing is
withheld from anybody who does not. An hour is never required for a pattern or a
test to appear.

**Two beats per minute is not a difference worth a sentence.** A real floor is
needed and there is nothing in the app to derive it from — this is the one number
here that has to be chosen rather than borrowed, and it should be chosen knowing
that.

**Gap-filling goes, for time.** Not giving something a time block is a choice, and
an app that reads a choice as a hole is the 3pm problem in general form. It may
survive for *activities*, where "you have never given Deep work a session of its
own" really is about a choice and not about hours somebody does not have.

**Workdays count.** The cell already carries the distinction, so a suggestion can
respect it for free — and must, or it will propose ten in the morning to somebody
who is at work at ten on five days in seven.

**No config file.** It was considered and dropped. Most of what would have gone in
it is either a statistical floor that must not be casually tunable — six days a side
is what the bootstrap needs, not a preference — or a value that belongs beside the
code that reads it.

## 8. Which hours suit which activity

`Surprise.priors` already holds expectations about **time of day** and about
**activities**, separately:

```
"timeOfDay.afternoon": Prior(raised: false, share: 0.70)   // the post-lunch dip
"activity.meetings":   Prior(raised: false, share: 0.78)
```

What it does not hold is the **pairing** — that deep work in a morning is a
different expectation from either "morning" or "deep work" alone. That pairing is
the thing worth adding, and it is what makes "try deep work at ten" a question the
app can think of asking.

**Same shape, nothing new.** `Prior(raised:share:)`, keyed on the id grammar, with
an absent key meaning no expectation either way. No weighting beyond the `share`
already there, and no second mechanism.

**Still never shown.** The boundary note above that table is the whole reason this
is allowed: a prior decides which true thing comes first, and the person is told
only what is true of them. A pairing prior may put "deep work in your mornings"
ahead of other questions to ask. It may not appear as a reason, and it may not
survive into any sentence.

**Be honest about what the literature supports.** Between-person chronotype spread
is larger than the within-person time-of-day effect, and most of the alertness work
is small, lab-based and measuring reaction time rather than anything resembling
focused work. These entries are the things *everybody already believes*, which is
exactly what the existing table says it is — a list of folk expectations, not a list
of findings. Written with that in the comment beside them, at shares that admit it.

## 9. Still open

1. **The flat-record case (§5), which is the one that matters.** The chain needs the
   calibration, the calibration needs six rated days a side, and the person this
   whole thread began with may not have them. Three options are listed there, none
   free.
2. **The bpm floor.** Settled that 2 is too small; not settled what it should be, or
   what could justify any particular number.
3. **Whether a pairing prior may choose the question** when the vitals chain is
   incomplete — which is §9.1 wearing a different hat, and probably has the same
   answer.

## 8. What it would take

**Phase 1 — read the curve.** Expose the cell baselines and a value describing where
a person's day differs. No screen changes.

**Phase 2 — the proposal.** A source alongside the existing ones, ranked by how much
of the chain it has: measured finding, then calibrated vitals, then uncalibrated
vitals, then Health-seeded starter.

**Phase 3 — priors choose the question.** If §7.1 is settled that way. The prior
stays unshown, as `Surprise.expectedness` already is.

**Phase 4 — retire or narrow gap-filling**, per §7.4.
