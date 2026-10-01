# Experiments

**Status:** proposed, not built
**Supersedes:** nothing. Extends layer 4 (`Recommendations.swift`) and adds one tier below it.
**Date:** 1 October 2026

---

## 1. The intent

> The whole idea is to work on the user's preferred areas to focus which we collect
> during onboarding and then based on the health data and logged sessions we should
> help user to improve on their lives — not just only show them the patterns. The
> existing patterns are useful but they leave users no action to improve or act on.

That is the brief, and it is the test every decision below answers to. Three
inputs — **stated focus areas**, **Health history**, **logged sessions** — one
output: a change the person makes, and an honest account of what happened when
they made it.

Pattern-finding stays. It stops being the product and becomes the thing that
decides what is worth testing.

## 2. Why the current app cannot do this

Not a matter of tone. Three findings from the code.

**The paid tier has no action in it.** `Recommendations.action(for:)` emits
`"Your morning is where blocks have held up best."` — the claim, restated. The
function carries a comment forbidding itself from saying "try", on the reasoning
that an instruction would collapse the free and paid tiers into the same words.
The result is that the one surface built to produce action produces description.

**`experiment` is a dead string.** `Hypothesis.experiment` is set on 2 of 6
families, is rendered on `InsightDetailView` and read by nothing else. Nothing
proposes it, nothing records that it was taken up, nothing measures a window,
nothing reports back. The app has the word and none of the mechanism.

**Nothing can arrive before day 12.** `EvidenceFloor.days = 12`, and every
relational claim sits behind the interval gate *and* a Benjamini–Yekutieli
correction over up to 60 candidates. Until then the slot says
`evidenceProgress(days:)`. Correct, and empty.

So the gap is not that the engine is too cautious about what it *knows*. It is
that nothing converts what it knows into something the person does.

## 3. What licenses this — and it is not relaxing the bar

The honest objection to acting earlier is that observation cannot establish
cause, so advice built on it is a guess. That objection is right, and it is why
the answer is not a lower threshold on the same evidence.

**Intervention is a different kind of evidence.** Observing that mornings
correlate with better ratings is weak. Deciding in advance to move a block to the
morning, doing it, and measuring what follows is a *test*. The person changed one
thing on purpose, and the prediction existed before the data did.

**Pre-registration removes the multiplicity problem entirely.** BY-correcting
over 60 candidates exists because the engine searches a space and the best of 60
comparisons will look good by chance. An experiment tests **one** hypothesis,
named and fixed before the window opens. There is no search, so there is nothing
to correct for. This is why a clinical trial declares its primary endpoint in
advance and is then permitted a far simpler analysis than a fishing expedition
over the same data.

That is a principled reason the gate for a pre-registered test is lower than the
gate for a mined pattern, and it does not weaken anything already shipped.

**What an experiment does and does not license.** It is not a randomised trial;
it is within-person, pre-post, unblinded. Confounds remain — a good fortnight is
a good fortnight. So:

- it licenses **"this held up when you changed it on purpose"**
- it licenses **"keep doing it"**, because the person tested it themselves
- it does **not** license **"this causes"**, and no copy will say so

Phase 4 (§14) adds randomised day assignment, which does close most of that gap.
It is deliberately not in phase 1.

## 4. The evidence ladder

Four rungs, replacing a binary. Each states its own standing on the card.

| Rung | What it is | Earliest | Source |
|---|---|---|---|
| **1 · Observed** | A fact about one measurement. No relationship claimed. | Day 1 | `HealthDigest`, `RecordFacts` — **shipped** |
| **2 · Worth testing** | A lead that has not cleared the gates, labelled as a lead, offering a test. | ~3 rated days | `Engine.findings` without correction + `Shrinkage` — **new surface, existing maths** |
| **3 · Tested** | What happened when the person changed it. | Lead + window | **new** |
| **4 · Confirmed** | Cleared the interval gate and the correction. | Day 12+ | `Engine` — **shipped, unchanged** |

Rung 2 is the day-one unlock and rung 3 is the point of the feature. Rung 4 is
untouched: nothing about its thresholds, correction or copy changes.

**Rung 2 is safe because of `Shrinkage`, which is already built.** A mean of four
afternoons is mostly noise, and the noisiest group produces the most extreme
number — so the most striking early lead is usually the least real. `Shrinkage`
pulls each group toward the person's own grand mean by how much evidence stands
behind it, which is exactly the correction a lead needs. It exists, it is tested,
and nothing currently shows its output. A lead displays the **shrunk** estimate
and the day count, never the raw mean.

## 5. The loop

```
                 ┌─────────────────────────────────────────┐
                 │  focus areas  ·  Health  ·  sessions    │
                 └──────────────────┬──────────────────────┘
                                    ▼
    ┌───────────── PROPOSED ──────────────┐   one at a time, chosen by
    │  a premise, a change, a window      │   the person's top priority
    └───────────────┬─────────────────────┘
                    │ person accepts        │ person declines → not offered again
                    ▼                       ▼
    ┌───────────── ACTIVE ────────────────┐
    │  window open · adherence accruing   │  person may abandon at any time
    └───────────────┬─────────────────────┘
                    │ window closes
                    ▼
    ┌───────────── SETTLED ───────────────┐
    │  held up  ·  did not  ·  can't tell │
    └───────────────┬─────────────────────┘
                    │
                    ▼  a settled experiment feeds the next proposal
```

**One active experiment at a time, ever.** Two concurrent changes make both
unreadable, and that is the whole value of the feature. This is a hard
invariant with a test, not a guideline.

**Lifecycle rules**

- A proposal names its premise, its change, its window length and what will be
  measured — all four before acceptance. A test whose endpoint is chosen
  afterwards is the fishing the correction exists to stop.
- Declining is permanent for that hypothesis. An app that re-asks is nagging.
- Abandoning is free, unpunished and uncounted. No streak, no "you gave up".
- The window is **14 days** by default. Rationale: the engine's own per-side
  minimum is 6 distinct days, and 14 days gives a realistic shot at 6 qualifying
  ones without the person forgetting they agreed to anything.

## 6. Where proposals come from

Selection is **always** by `profile.priorities`, walked in the person's own
order — exactly as `Recommendations.build` already does. This is the brief's
"preferred areas to focus" and it is already wired: `Priority.insightTypes` maps
each focus area to the insight types that serve it.

Three sources, in descending strength. The first available one wins.

**(a) From a confirmed pattern (rung 4).** Strongest. *"Your mornings have held
up best. Test whether it survives when you move a block there on purpose."* Needs
day 12+.

**(b) From a lead (rung 2).** *"Your afternoons have run heavier so far — 4 days.
Want to test it?"* Needs ~3 rated days. This is where most early experiments come
from.

**(c) From Health history alone, seeded by the focus area (rung 1).** The day-one
case, and the reason onboarding's focus ranking earns its place. No ratings
exist, but a year of Health data does. Someone who ranks **Sleep** first and
whose history carries a weekday/weekend contrast gets:

> Your sleep reads 48m shorter on Tuesdays than Saturdays.
> Test a consistent bedtime for two weeks?

Descriptive premise, proposed test. No claim. Every `Priority` must have at least
one (c) proposal available from Health alone, or that focus area is a promise
onboarding cannot keep — the same standard `Priority.basis` already holds itself
to.

## 7. Measurement

An experiment carries a **target group** (what is being changed) and a
**baseline** (what it is measured against). Both are fixed at acceptance.

**Primary outcome** is the rating the hypothesis is directed on. Only hypotheses
with `outcome.higherIsBetter != nil` are eligible — the identical filter
`Recommendations.build` already applies, and for the same reason: an undirected
measurement like a heart-rate residual has no better side, so no change can be
proposed and no result can be read.

**Adherence is measured and reported, and it gates the verdict.** Someone who
commits to morning blocks and manages two in a fortnight has not run the
experiment. Adherence is the count of **distinct days** in the window carrying a
qualifying session. The threshold is **6 distinct days**, borrowed from the
engine's own per-side minimum rather than invented here.

**Three verdicts, and the null ones are first-class.**

| Verdict | Condition | Reads as |
|---|---|---|
| **Can't tell** | adherence < 6 days, or baseline < 6 days | "Six days of it would be enough to read. You managed three." |
| **Held up** | interval on the difference excludes zero, favourable | "Those blocks settled at 4.2 against your 3.4." |
| **Did not hold up** | interval includes zero, or unfavourable | "No difference you could act on." |

No multiplicity correction, per §3 — one pre-registered hypothesis, no search.
The interval is the existing day-clustered bootstrap from `Statistics.swift`,
unchanged.

**"Did not hold up" must be as well-presented as "held up".** It is the feature's
credibility: an app whose tests always succeed is not running tests. It is also
the honest version of the payoff I argued for and failed to design earlier —
being wrong about yourself is interesting, and here the app is not the one who
was wrong.

## 8. What is stored, and what is not

`RecordStore.swift` sets the rule and it decides this cleanly:

> Insights are absent because they are derived — storing a claim alongside the
> data it came from is how the two drift apart. What survives is only what belongs
> to the person rather than to the computation.

**Stored** — the commitment belongs to the person: the hypothesis identity
(`Engine.identity(of:)`, already stable), the start date, the window length, the
target and baseline definitions, the verdict's *acknowledgement*, and declines.

**Not stored** — adherence and the verdict are recomputed from sessions on every
launch, like every other derived value.

**One exception, with the existing precedent.** When an experiment settles, its
figures are frozen into the record, for the same reason `physiology` is: the
baseline is computed from a rolling window of the person's own history, so
re-deriving it next month gives a *different number for the same settled
experiment*. A figure that changes between launches cannot be shown to anyone.
This is `Record.physiology`'s argument applied unchanged, not a new exception.

Mechanically: one new optional array on `Record`, following the `removedImports`
and `physiology` pattern — optional because a synthesized `Codable` fails on a
missing key for a non-optional property however sensible its default looks.
`schemaVersion` goes to **3**.

## 9. Copy rules

`NarrationGuard` stands. Two clarifications, no loosening.

**Instruction voice is permitted here, and only here.** It is already how the
guard is scoped: `NarrationGuard` runs over `Narration` output and `RecordFacts`
copy, never over `Recommendation.action`. The comment on the `instruction` list
already says *"the free tier proposes a test"* — this feature is that sentence,
implemented. `Narration` and `RecordFacts` keep the full ban.

**The causal and clinical bans are absolute, including in experiment results.**
This is the trap, because the natural way to report a successful test is
forbidden vocabulary. `improves`, `improve`, `helps`, `boosts`, `because`,
`leads to` are on the causal list; `energy levels`, `intensity`, `stress` are on
the clinical one. So:

| Not this | This |
|---|---|
| ~~Morning blocks improve your focus.~~ | Those blocks settled at 4.2 against your 3.4. |
| ~~This helped, so keep it up.~~ | It held up for two weeks. Worth keeping. |
| ~~Earlier starts boost your energy.~~ | Your earlier blocks rated higher than the rest. |

A test sweeps every generated experiment string for causal, clinical and
population offences, with `instruction` excluded — mirroring the sweep
`RecordFactsTests.copyPassesTheNarrationGuard` already runs.

## 10. Surfaces

No new tab. Experiments appear where the app already speaks.

**Today — the observation slot.** `SlotContent` gains two cases. Precedence
matters and the existing ordering already encodes the principle that the rating
the engine runs on outranks the upsell:

```
activeExperiment      ← new, below unfinishedReflection
settledExperiment     ← new, above recommendation; a result outranks a claim
recommendation
unfinishedReflection
upgradePrompt
leadObservation
evidenceProgress / stillLooking
```

`settledExperiment` sits highest because a finished test is the most valuable
thing the app can hold, and it is shown once and acknowledged.

**Patterns tab** gains the proposal, and the lead rung (2) that was previously
invisible. An insight detail screen with an `experiment` gets a real control
instead of a sentence.

**Visual standing.** `HealthDigest.Fact.Standing` was just built on the principle
that rarity shows through **space, not ornament** — `DESIGN.md` records a 2pt rule
weight and a full-bleed canvas both reverted whole. A settled experiment is the
rarest thing in the app and should have the most room; the same two tokens
extend, and nothing new is invented. No new colour, badge, border or type size.

**Entitlement.** Confirmed-pattern experiments (source a) are a member
capability, matching `Recommendations` today. **Sources (b) and (c) are free** —
they are the day-one value the brief asks for, and gating them would put the
upsell in front of the first useful thing the app does.

## 11. What this reuses

Deliberately long, because the instruction was to not rearchitect.

| Existing | Used for | Change |
|---|---|---|
| `Priority` + `insightTypes` | proposal selection by focus area | none |
| `Recommendations.build` priority walk | the selection loop | extended, not replaced |
| `Engine.findings` | hypothesis source for rungs 2 and 4 | none |
| `Engine.applyingCorrection` | rung 4 only | none |
| `Engine.identity(of:)` | stable experiment key | none |
| `Shrinkage` | makes rung 2 safe to show | none — finally surfaced |
| `Surprise` | ordering proposals | none |
| `Statistics` bootstrap | the verdict interval | none |
| `HypothesisRegistry` | premise phrasing, `focusLabel`, caveats | `experiment` becomes structured |
| `HealthDigest` | day-one premises (source c) | none |
| `Record` / `RecordRepository` | persistence | one optional array, schema 3 |
| `Session.isEligibleForPatterns` | which sessions count | none |
| `SlotContent` | Today surface | two cases |
| `Tier` | entitlement | none |
| `NarrationGuard` | copy safety | none; scope documented |
| `TitledFigure`, `HRule`, `Space`, `Motion`, `Fact.Standing` | all UI | none |

## 12. What is new

- `Experiment` — the stored commitment
- `ExperimentDesign` — hypothesis or lead → a checkable change, a target, a window
- `ExperimentOutcome` — derived verdict: adherence, figures, one of three results
- `Lead` — rung 2: an uncorrected finding with its shrunk estimate and day count
- `ExperimentCopy` — premise, change, result strings, guard-swept
- Store hooks on `HourssStore`: propose, accept, decline, abandon, acknowledge
- Three card surfaces: proposal, active, settled

## 13. Non-goals

- **No streaks on experiments.** Adherence is reported as a count and never as a
  thing to protect. `RecordFacts` records why.
- **No reminders in phase 1.** `LogReminders` exists; wiring it to nag about an
  experiment is a different product decision.
- **No multi-factor experiments.** One change at a time.
- **No population comparison.** Still impossible, still not a rule we can lift.
- **No medical claims.** Unchanged and absolute.
- **No plan-my-day.** Adjacent, out of scope.

## 14. Risks and open decisions

| Risk | Judgement |
|---|---|
| **Confounding.** A good fortnight reads as a successful experiment. | Accepted in phase 1 and stated in the copy. Phase 4 randomises day assignment, which genuinely addresses it. |
| **Adherence will be poor.** Most people will not manage 6 days. | This is why "can't tell" is a first-class verdict rather than a failure state. If it dominates in testing, the window lengthens before the threshold drops. |
| **A failed experiment reads as the app being wrong.** | Framing: the app proposed a test, the test answered. Report it plainly and offer the next one. |
| **Scope.** This is the largest change we have made. | Phased below; phase 1 is shippable alone. |
| **Open:** is 14 days right? | Decide from real adherence data after phase 2, not now. |
| **Open:** can a settled experiment feed rung 4? | Probably not — mixing pre-registered and mined evidence in one correction is exactly the confusion §3 relies on avoiding. Default: no. |

## 15. Phases

**Phase 1 — the loop, on confirmed patterns.** `Experiment`, persistence,
design from a rung-4 finding, adherence, verdict, the three cards. Members only,
day 12+. Shippable alone, and proves the mechanism on the strongest evidence.

**Phase 2 — leads (rung 2).** Surface `Shrinkage`'s output. Experiments from
leads, free. This is where the day-one wait actually shortens.

**Phase 3 — Health-seeded starters (source c).** Every focus area gets a
proposal on day one from Health history alone.

**Phase 4 — randomised assignment.** The app picks which days carry the change.
Turns a pre-post comparison into a genuine within-person randomised test, and is
the only phase that moves the honest claim closer to cause.

Phase 1 is the commitment. 2 and 3 are the brief's day-one half. 4 is the upgrade
that makes the evidence real rather than merely honest.

---

## 16. Implementation checklist

**Progress:** steps 1–9 built and passing (456 unit tests, 102s, iPhone 17 Pro).
Nothing committed yet.

Sequenced so every step is verifiable before the next depends on it. Steps 1–12
are **shared by phases 1 and 2** and have no fork in them.

### Foundation — the stored commitment

- [x] **1.** `Hourss/Model/Experiment.swift` — `Experiment` (hypothesis identity,
      start date, window days, target + baseline definitions, accepted/abandoned/
      acknowledged state, frozen figures when settled). `Codable`, `Hashable`.
- [x] **2.** `Record.experiments: [Experiment]?` — optional, per the
      `removedImports` precedent. Bump `currentSchemaVersion` to 3.
- [x] **3.** Test: a record written at schema 2 decodes with `experiments == nil`
      and does not throw. This is the step that is silently skipped and found in
      production.
- [x] **4.** `Record` encoding stays byte-stable — experiments written sorted, for
      the reason `physiology` is sorted. Test.
- [x] **5.** `HourssStore`: load/`persist()` wiring. Test round-trip.

### Derivation — adherence and verdict

- [x] **6.** `Hourss/Store/ExperimentOutcome.swift` — adherence as distinct
      qualifying days in the window; `Session.isEligibleForPatterns` decides what
      counts.
- [x] **7.** Verdict: three cases, 6-distinct-day threshold for both adherence and
      baseline, bootstrap interval from `Statistics.swift`. **No correction** — one
      pre-registered hypothesis (§3).
- [x] **8.** Freeze figures on settle. Test that a settled verdict does not move
      when the baseline window slides.
- [x] **9.** Tests: each verdict reachable; "can't tell" on low adherence; the
      boundary at exactly 6 days; determinism across runs.

### Design — hypothesis to proposal

- [ ] **10.** `Hourss/Store/ExperimentDesign.swift` — `Finding` → target group,
      baseline, window, change description. Only `outcome.higherIsBetter != nil`,
      reusing the `Recommendations.build` filter.
- [ ] **11.** Selection by `profile.priorities` in rank order, extending the
      existing walk in `Recommendations.build` rather than duplicating it.
- [ ] **12.** `ExperimentCopy` — premise, change, three result strings. Sweep test
      for causal + clinical + population, `instruction` excluded (§9).

### Store behaviour

- [ ] **13.** `propose` / `accept` / `decline` / `abandon` / `acknowledge`.
- [ ] **14.** **One active experiment, enforced.** Accepting while one is active
      is rejected, not silently queued. Test.
- [ ] **15.** Declines persist and the hypothesis is never re-proposed. Test.
- [ ] **16.** Settling on window close — on launch and on foreground, reusing the
      refresh path `DayDeviation`/physiology already use. Test across a date
      boundary with an injected clock, never `Date()`.

### Surfaces

- [ ] **17.** `SlotContent`: add `activeExperiment` and `settledExperiment` with
      the §10 precedence. Test the ordering as a value.
- [ ] **18.** Proposal card — premise, change, window, what will be measured. All
      four before acceptance.
- [ ] **19.** Active card — window remaining and adherence as a count. No streak.
- [ ] **20.** Settled card — verdict, figures, caveat. "Did not hold up" gets the
      same treatment as "held up".
- [ ] **21.** `InsightDetailView` — replace the `experiment` sentence with the
      control.
- [ ] **22.** Standing/space per §10. No new colour, badge, border or type size.
- [ ] **23.** Accessibility labels lead with the subject, never the figure.

### Verification

- [ ] **24.** Full unit suite on **iPhone 17 Pro** (`53352C15-…`), by UDID. Watch
      for `Restarting after unexpected exit` rather than trusting the summary.
- [ ] **25.** UI suite — the account gate means this device only.
- [ ] **26.** `DebugFixture`: seed an active and a settled experiment, so all three
      cards are reachable in the simulator. The health-seeding work proved this is
      the difference between a feature being testable and being invisible.
- [ ] **27.** `DESIGN.md` and `BACKLOG.md` updated. `README.md` layer description
      gains the ladder.

### Fork — after step 12, see §15

Phase 1 (confirmed patterns, members, day 12+) and phase 2 (leads, free, ~day 3)
share everything above. The fork is only which **source** ships first, and it is a
scope decision rather than a technical one.
