# Calibrating the heart-rate residual

**Status:** proposed, not built
**Depends on:** nothing. Every input already exists on the phone.
**Date:** 2 October 2026

---

## 1. The idea, in one line

**Let somebody's own ratings decide whether a raised heart rate is a good sign or
a bad one for them, and then use the answer.**

The app refuses to say whether a heart rate above your usual is better or worse,
and it is right to refuse — that is a medical opinion and it does not have one.
But *this person's own feeling ratings* can answer it for *this person*, which is
an association between two of their own measurements and exactly the kind of thing
the engine already does.

## 2. What exists, and the exact gap

Layer 3 (`Physiology.swift`) produces a **residual** per session: observed heart
rate minus what that person's own cadence, hour and day type predict, fitted from
a rolling sixty-day window. It is the most sophisticated thing in the app and the
only measurement nothing else could give them.

It is also, today, a dead end.

```swift
// EngineContracts.swift
var higherIsBetter: Bool? {
    case .feeling, .performance: true
    case .heartRateResidual: nil      // ← this
}
```

That `nil` is correct and it is load-bearing in two places:

```swift
// Recommendations.build
&& $0.hypothesis.outcome.higherIsBetter != nil

// ExperimentDesign.isEligible
finding.hypothesis.outcome.higherIsBetter == true
```

So **every `physiology.*` finding is unreachable by the two surfaces that can do
anything.** The registry computes them, the correction corrects them, the feed can
show them — and not one can become a recommendation or an experiment, ever, by
construction. The app does real work and then declines to use it.

The gap is not the measurement. It is the missing direction.

## 3. Why this is the unlock rather than a nicety

**It is the only thing in the app that produces evidence without a rating.**

Everything else is bottlenecked on ratings: six distinct days on each side of any
comparison, a twelve-day floor before the slot will say anything, and rung 2
arriving later than planned — the hole phase 3's starters exist to paper over. A
residual needs nobody to rate anything. It arrives for every session with enough
heart-rate samples, forever, passively.

Calibration does not add a measurement. It makes the one already being computed
*usable*, and it unlocks the whole `physiology.*` family at once rather than one
claim at a time.

**It also compares within a day, which nothing else here does.** Every other split
in the registry is per-day — `dayHealth` is a property of the day, so all of a
day's sessions land on the same side. A residual is per *session*, so two sessions
on the same afternoon can land on opposite sides of it. The bootstrap resamples
whole days, so a drawn day then contributes to both arms, and everything that
travels with the day — how much somebody slept, whether it was a workday, what
kind of week it was — is held constant inside the comparison instead of being a
confound the caveat has to apologise for. That is a genuinely stronger design than
the daily splits, and it falls out of the data rather than being bought.

## 4. The mechanism: one new hypothesis family

One hypothesis, per person, mirroring `healthAssociations` exactly:

```
id:        residual.higher.vs.lower.feeling
outcome:   .feeling                           ← the thing being measured
focus:     heartRateResidual >= their median  ← the thing being split on
baseline:  heartRateResidual <  their median
```

The split is **their own median residual** over sessions that carry both a
residual and a rating — the same rule `healthAssociations` uses and for the same
reason: a median taken over sessions without a rating splits the data at a point
no evidence sits on either side of.

Note the inversion. Today `physiology.*` has the residual as the *outcome* and
splits on activity. This has the residual as the *split* and feeling as the
outcome. Same number, opposite role, and the second one is the one that can answer
"which way round is it for me".

**Phrasing**, anchored on the higher side with the direction supplied by the
evidence, as `healthAssociations` already does:

> Sessions where your heart rate ran above your usual have felt more draining than
> your others.

Caveat, carried unchanged from the existing physiology family:

> Heart rate moves with more than effort — a warm room, caffeine, or talking will
> do it.

## 5. What a confirmed calibration licenses

**`Outcome.heartRateResidual.higherIsBetter` stops being a global constant and
becomes a per-person value**, derived from that person's own calibration finding
and `nil` until one exists.

That single change cascades:

| Today | After a confirmed calibration |
| --- | --- |
| `physiology.<activity>` findings are descriptive only | they can become recommendations |
| no residual hypothesis can be experimented on | they clear `isEligible`'s direction filter |
| "your heart rate ran 4 bpm above usual during deep work" | the same sentence, with something to do about it |

It licenses **"for you, a raised heart rate during a session has gone with worse
ones"**. It does not license anything about health, about other people, or about
cause — and the `clinical` and `population` bans in `NarrationGuard` are untouched.

## 6. The rules that keep it honest

**Only a confirmed calibration directs anything.** A lead must not. The whole point
of a direction is that everything downstream inherits it, so a calibration that is
wrong makes every physiology claim wrong in the same wrong direction at once —
which is worse than having no direction, because it is confidently wrong rather
than silent. It clears the interval gate and the correction or it does nothing.

**No imputation, ever.** The obvious next thought is to score unrated sessions with
their residual and feed those back as outcomes. That is circular — testing
hypotheses on numbers the app invented — and it is forbidden. The residual is its
own outcome; nobody guesses a rating.

**The calibration is corrected with everything else**, in the same run, as one more
candidate. It costs the other hypotheses a little power under Benjamini–Yekutieli
and that is the correct price. Exempting it so that it clears more easily would be
the engine's own guardrail routed around from the inside, on the one claim
everything else depends on.

**Direction is per person and is never compared.** Two people can see opposite
claims from identical data, and that is correct rather than a bug. No copy may
imply that one direction is the normal one.

**The caveat travels.** Anything that inherits the direction inherits the limit
that came with it.

## 7. What this does not do

- **It does not make heart rate a goal.** Nothing will ever suggest raising or
  lowering it. The direction exists so claims about *sessions* can be acted on, and
  the action is always about the session — when it happens, how long it runs, what
  it is — never about the body.
- **It does not improve the feeling patterns.** Those measure ratings. This is a
  different measurement and makes a different set of claims usable.
- **It does not need a watch app.** Continuous sampling during a live session would
  make the residual far less noisy — `minimumSamplesForFitting` is three — and it
  is a separate bet with a battery cost and a new target behind it. This uses what
  is already on the phone.

## 8. Risks

| Risk | Judgement |
| --- | --- |
| **Wrong direction poisons everything downstream.** | The reason only a confirmed calibration counts. Worth a second look at whether it should need a stricter bar than an ordinary claim, given how much rests on it. |
| **Coverage.** `physiology(in:)` already needs 12 sessions carrying a residual before it registers anything, and "most sessions have none." | Calibration needs the same 12 plus 6 rated days a side. Somebody whose watch is sparse gets nothing, silently, which is the right failure. |
| **It costs every other hypothesis power.** | One more candidate under the correction. Accepted, and stated above. |
| **A person's direction could genuinely flip over months.** | The residual is already fitted from a rolling sixty-day window, so the calibration moves with it. Whether a direction that flips should be announced, or quietly stop directing anything, is open. |
| **Small print risk: this is the app's closest approach to a clinical statement.** | The phrasing never leaves the session. "Sessions where your heart rate ran above your usual have felt more draining" says nothing about the heart rate being good, bad, high or low — only about which sessions they were. |

## 9. Phases

**Phase 1 — the calibration hypothesis.** Register it, phrase it, test it. It
appears on Patterns like any other claim and directs nothing. Shippable alone, and
on its own it is a genuinely new and personal observation.

**Phase 2 — direction.** `higherIsBetter` becomes per-person. The `physiology.*`
family becomes reachable by recommendations and experiments. This is the phase that
pays for the whole thing.

**Phase 3 — residual as an experiment outcome.** An experiment whose measured
quantity is the residual rather than a rating — a test that needs no rating at all,
for somebody who will never rate anything. The furthest this can go without a
watch.

## 9a. Why these are not three parallel jobs

Phases 1, 2 and 3 are a dependency chain in overlapping files, and it is worth
writing down so nobody tries to parallelise them again.

Phase 2 cannot resolve a direction until phase 1's finding exists. Phase 3 cannot
measure an experiment on the residual until phase 2 has given it one — the
`isEligible` filter it has to clear is the thing phase 2 changes. And all three
touch `EngineContracts.swift`, `HypothesisRegistry.swift` and
`ExperimentDesign.swift`, so three agents would be editing the same four files to
three different ends.

**1 and 2 are therefore one job.** 3 waits for it.

## 10. Checklist

### The hypothesis
- [ ] **1.** `HypothesisRegistry.residualCalibration(in:)`, mirroring
      `healthAssociations` — median over sessions with both a residual and a rating,
      minimum four values before a median means anything.
- [ ] **2.** Phrasing anchored on the higher side, direction from the evidence.
      Reuse `direction(finding)`; author no new vocabulary.
- [ ] **3.** Caveat carried from the physiology family, not rewritten.
- [ ] **4.** `RegistryTests`: focus and baseline partition, no row in both; the id
      is stable; it does not register below the minimum.
- [ ] **5.** A test that it compares within days — that a day can contribute to both
      arms, which is the property §3 claims and nothing else in the registry has.

### Direction
- [ ] **6.** `Outcome.higherIsBetter` moves from a static to a value resolved per
      run. Everything reading it today takes the resolved one.
- [ ] **7.** Resolution requires `isReportable` — the correction included. A lead
      directs nothing.
- [ ] **8.** Tests: an unconfirmed calibration leaves every physiology finding
      undirected; a confirmed one directs them all; a reversed one reverses them.
- [ ] **9.** `Recommendations` and `ExperimentDesign` reach physiology findings once
      directed, and a test pins that they could not before.

### Copy
- [ ] **10.** Sweep every string for causal, clinical and population offences.
      `instruction` is lifted only in `ExperimentCopy`, as ever.
- [ ] **11.** A test that no string names a direction as normal, expected or shared.

### Verification
- [ ] **12.** Full unit suite on iPhone 17 Pro by UDID; UI suite after.
- [ ] **13.** `DebugFixture` seeds residuals that produce a confirmed calibration, so
      the whole chain is reachable in the simulator. A card nobody can get to is a
      card nobody reviews — that has cost this project twice already.
