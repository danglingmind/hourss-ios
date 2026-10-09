# Offering an hour nobody has logged

**Status:** phases 0–3, 5 and 7 built. **Phase 4's blocker is gone; a second one is in its place — §10.3, §10.7.** Phase 6 remains.
**Date:** 9 October 2026

---

## 1. Why this exists

**The app exists to answer a question about a time the person has not tried.**

Everything else Hourss does — the rank statistic, the day-clustered bootstrap, the
correction, the silence budget — exists so that an answer can be trusted when it
comes. None of it is the product. The product is the question.

The promise, stated so it can be held to:

> **For any hour somebody has never logged, the app has a specific, honest,
> person-grounded reason to suggest it — and says which kind of reason it is.**

Four sources, in descending strength. Which one answers is the whole design.

| | Source | Needs | Status |
|---|---|---|---|
| 1 | Their own ratings at nearby hours | sessions logged near the hour | **new — phases 3–4** |
| 2 | Their own body and their own waking time | Health only; no logging at all | ships, unreliable — **phases 1–2** |
| 3 | What is ordinarily true of people | nothing | ships as `ExperimentPriors` — **phase 5** |
| 4 | A fortnight of actually doing it | their consent | ships |

Source 4 is the only one that ever *answers*. Sources 1–3 decide **which question
is worth a fortnight**. That distinction is §4 and it is the whole integrity
argument.

---

## 2. Two cases that look like one

The earlier draft of this document opened with a motivating example that its own
phase 0 then required the engine to refuse. That inconsistency is worth keeping on
the page, because the two cases underneath it have completely different answers and
conflating them is how this feature would get built wrong.

**Case A — the hour sits between hours they use.** Logs 06:00 and 08:00, never
07:00. Their own record contains information about 07:00, and the engine currently
throws it away by rounding six hours into one bucket. **Recoverable, by source 1.**

**Case B — the hour is nowhere near anything they have logged.** Logs only
20:00–22:00; is 07:00 better? **Their logged sessions contain no information about
07:00, and no procedure can extract any.** A gradient within the evening says
nothing about the morning. Any system returning a confident number here invented
it — that is a property of the data, not of the method, and it is as true of a
neural network as of a smoother.

**Case B is not a dead end, and this is the part the earlier draft missed.** Their
*body* knows about 07:00 even though their *log* does not: the phone records heart
rate all day, and `Physiology.DayShape` already reads which corners of the week sit
apart at hour resolution with zero logged sessions required. Their waking time is in
Health too. So case B is answered by source 2, with source 3 behind it and source 4
settling it.

**What follows for the plan:** the body half is the answer for case B, case B is the
harder and more common case, and the body half is currently the unreliable one. So
it is fixed first.

---

## 3. What is in the way, measured

**3.1 Time has four values.** `TimeBucket` (`Enums.swift:132`) is `morning` 05–11,
`midday` 11–14, `afternoon` 14–18, `evening` 18–05. Morning is **six hours wide**.
So "try 07:00" is not a sentence the engine can form even for somebody with a year
of mornings.

**3.2 The gate is absolute, and correctly so.** Six distinct rated days a side is
what makes a claim worth printing, and nothing here relaxes it. The gate is not the
bug. The bug is having **one mechanism**, so a question that cannot clear the gate
produces nothing rather than producing an *offer*.

**3.3 Clock time is not the person's time.** 07:00 is ninety minutes into the day
for somebody who wakes at 05:30 and before the day has started for somebody who
wakes at 09:00. The engine has no representation of waking, so every hour-based
offer it could make is anchored to a clock the person does not live by.

**3.4 The answer key could not describe the target.** `Planted.timeWindow` takes two
`TimeBucket`s, and 06:00 and 08:00 are both `.morning`. Closed in phase 0.

---

## 4. The rule

> **The curve, the body and the prior choose the question. The fortnight decides
> the answer.**

Nothing in sources 1–3 is evidence. None of it survived a correction, and none of it
may reach a sentence as a fact. What it may do is what `Surprise.priors` and
`Physiology.DayShape` already do: **decide which question is worth putting in front
of somebody.**

This is also why no model is needed. We are not predicting a rating. We are ranking
candidate hours by whether they are worth two weeks of somebody's attention — a much
weaker claim, and one a closed-form smoother supports where a point prediction
cannot.

Three consequences, each testable:

- **No number from any of the three reaches a string.** Same boundary as BR-25.
- **Refusal is a first-class output.** Outside support, nil — not a low score.
  `Physiology` already refuses for four distinct reasons rather than guessing.
- **An hour-led offer is a `Proposal`, never an `Insight`.** It enters
  `ExperimentStore.offers`, carries a premise framed as a question, and cannot
  become a claim without the fortnight.

---

## 5. Phases

Ordered by what serves §1, not by what is easiest.

### Phase 0 — the instrument — **built**

The answer key could not express an hour-of-day effect, so no measurement of this
feature would have meant anything.

- `Planted.hourOfDay(hour:halfWidth:delta:)` — a linear taper, not a step, because a
  step at an hour boundary is a bucket by another name and recoverable without the
  capability under test. Distance wraps at midnight.
- `Recipe.hours` — placement stated rather than emergent. Nil for everybody who
  existed; the random stream is untouched and `CohortTests` proves it.
- **Interpolator** (06:00 and 08:00, effect at 07:00) — case A.
- **Extrapolator** (20:00–22:00 only, effect at 07:00) — case B, and the integrity
  test. Required behaviour is refusal.
- **Flat hours** — support at every hour, signal at none. The shape a smoother most
  wants to find structure in.

### Phase 1 — make the body reliable

`DayShape` returns empty on the seeded fixture on some dates. Three suites fail
today that passed on 5 October, reproduced at `1a5b844` on a second simulator, with
nothing between touching physiology. Recorded in `BACKLOG.md`.

**This is the top of the list because of §2.** An empty `DayShape` is the vitals-led
offer not firing, and vitals is the source that answers case B. On those dates the
day-one path silently degrades to the population prior — a feature that looks like
it works while answering from a weaker source.

Diagnose before fixing. `DebugFixture.seededFeed` builds relative to `today` and the
analyzer fits over a trailing window, so the composition of that window moves with
the weekday; `SyntheticCohort.anchor` is `mostRecentMonday(onOrBefore:)` for exactly
this class of problem and the fixture has no equivalent. That is the suspicion, not
the finding.

Whatever the cause, it needs a test that fails on the bad dates rather than one that
happens to run on good ones — this is the third instance of the date-dependent class
`README.md` records.

### Phase 2 — anchor the day to waking

**The cheapest honesty win in the document, and it needs no logging at all.**

Health holds their sleep. Deriving a usual wake time turns "07:00" into "about
ninety minutes after you wake" — which is both more honest and more useful, and
makes an offer for a never-logged hour *person-specific* without a single session at
that hour.

- A usual waking time from Health, with its own refusal when sleep is too sparse.
- Hours expressed relative to it wherever an offer names one.
- Never suggest an hour before the person is up. The workday check in
  `PRD-VITALS` item 13 established this shape; this is its sleep-wise twin.

### Phase 3 — the hour curve

**`RatingShape`**, deliberately mirroring `Physiology.DayShape` so there is one idiom
for "a smooth over the day that chooses a question".

- **Input:** rated observations as `(hour, isWorkday, feeling)`.
- **Clustered on days.** Three sessions on one Tuesday are one day's evidence; a
  smoother weighted by session repeats the pseudo-replication the bootstrap exists
  to prevent.
- **Fit:** a wrapped circular kernel smoother on day-level medians. Wrapped because
  23:00 and 01:00 are two hours apart. Medians because a 1–5 scale makes outliers
  cheap, matching `Physiology`'s choice.
- **Workday and non-workday kept apart**, as `DayShape` already does.
- **Output:** per hour, an estimate **and a support weight** — the summed kernel mass
  of real observations near it. Support is what makes refusal possible and is the
  single most important number in the feature.
- **Refusal:** below the support floor, nil.

No Core ML, no base model, no training data that does not exist. A closed-form
smoother over one person's own ratings, inspectable the way `Shrinkage`'s method of
moments is inspectable.

### Phase 4 — the offer

**`ExperimentHours`**, alongside `ExperimentVitals`, `ExperimentPriors`,
`ExperimentGaps` and `ExperimentStarters`.

- Reads `RatingShape`. Picks the best-estimated hour the person does not already
  use, subject to support above the floor and a gap worth a fortnight.
- Premise under the `PRD-VITALS` §9 framing rule, guard-enforced.
- Respects workdays and, from phase 2, waking.
- **Order in the chain:** after measured findings, before vitals. An hour-led offer
  is built from their own *ratings*, the outcome the app is about; vitals is built
  from heart rate, a proxy for it. Flagged in §8 as a decision.

### Phase 5 — the priors table, sourced

Source 3 already ships. What it does not have is provenance: engine doc §10.7 —
*"Every number in the expectedness table is hand-set from intuition. They are
plausible and they are not measured."* Every entry added makes that worse.

- **Each entry carries a source, or it is coarsened.** A three-level classification
  that intuition can defend beats a 0.72 that was invented. This is §10.7's own
  candidate.
- **Prefer mechanism to folklore.** Core temperature, sleep pressure, time since
  waking. These generalise because they are physiological — and they are measurable
  *on the person*, so the prior can be checked against their own body rather than
  only asserted.
- **Prefer adherence findings where that is the honest one.** "You are more likely to
  actually do it" is better supported than most performance claims about timing, and
  is a more useful thing to tell somebody.
- **Record the chronotype caveat beside the table.** Between-person spread exceeds
  the population time-of-day effect — `PRD-VITALS` item 15 already says so. A
  population prior about timing is weak evidence about an individual. Good enough to
  choose a question; never good enough to be a reason.
- **Body before prior stays.** Already the chain's order.

### Phase 6 — confidence that means something

Engine doc §10.4: the 0–100 number is a presentation device with no calibration
behind it, and the weights 0.72/0.28 and the bands at 80/65/50 are not derived from
anything.

It matters here specifically: an hour-led offer that runs a fortnight and comes back
"it held up" is where the app either earns the person's trust or spends it.

Calibrate `[edge, width, days, dayCount] → measured hit rate` by isotonic regression,
fitted offline against the cohort, shipped as a table. No model at runtime.

**State the limit in the doc that ships with it.** This calibrates against the
*generator's* assumptions — how often the engine recovers an effect of the kind we
chose to plant — not against the world. Somebody will read the band as a probability
about reality unless the sentence saying otherwise is written down.

### Phase 7 — hygiene, independent of all of the above

Neither serves §1. Both make every claim the app already prints more honest.

- **7.1 Resamples and the p-floor** (§10.3). At 2000 the floor is 0.0005 and every
  planted effect reports exactly that, so BH only discriminates in 0.005–0.05. Still
  2000 (`Statistics.swift:155`). Layer 1's speed work makes 10,000 affordable.
- **7.2 Inverse-variance weighting** (§10.8). `Reading.uncertainty` widens with
  cadence and the residual then enters layer 2 as a plain number. Weight by inverse
  uncertainty in `Statistics.compare`. One function, and §10.8's own candidate.

---

## 6. What this may never do

- **Never print a number any of the three sources produced.** They choose; they do
  not speak.
- **Never lower the six-day gate.** An offer is not a claim and does not need it; a
  claim still does.
- **Never extrapolate confidently.** Outside support, nil. The Extrapolator exists
  to fail the build if this erodes.
- **Never compare the person to anybody else in a sentence.** The prior may rank. It
  may not be quoted.
- **Never become a silent recommendation.** An untried hour is always an *offer to
  test*.
- **Never suggest an hour the person is asleep or at work.**

---

## 7. Deliberately parked

From the ML analysis, with the reason each is out rather than merely unscheduled:

- **A base model trained on aggregate data.** There is none, no server and no
  collection. Every layer above inherits the absence.
- **Folding interventional results into a predictive model.** `BACKLOG.md` records
  this as decided: mixing pre-registered and mined evidence in one correction is the
  confusion the no-correction argument depends on avoiding.
- **Replacing the interaction gates with a regularized GBM.** Regularization is not
  FDR control; unbounded discovery feeding a step-up procedure makes multiplicity
  worse.
- **Recency-weighted fine-tuning for §10.6.** It does not answer what §10.6 asks —
  whether a decayed estimate can still support an honest interval — it discards the
  interval.
- **Cross-activity transfer and cold start.** Both ship, as `ExperimentPriors` and
  the vitals/priors/starters chain.

---

## 8. Open decisions

1. **Where `ExperimentHours` sits in the chain.** Proposed before vitals; the
   argument for after is that heart rate is measured and a rating is reported.
2. **The support floor.** Genuinely underivable — it answers "how much of their own
   evidence is enough to be worth asking". Candidate: the lowest floor at which the
   Extrapolator is still refused.
3. **Kernel bandwidth.** Narrower interpolates less and refuses more. Same method:
   pick it from the cohort and record what it costs the Interpolator.
4. **Whether a curve may ever downgrade an hour somebody already uses.** "Your 8pm
   looks like your worst hour" is a claim, not an offer, and is out under §6 — but it
   is the obvious next request.
5. **Whether a person's own settled experiments may rank the next offer.** Per-person
   rather than population, and *not* the thing `BACKLOG.md` bans — that ban is on
   mixing pre-registered results into the same correction as mined evidence. Using a
   finished fortnight to choose the next question is a different act, and nobody has
   looked at it.

---

## 10. Amendments the build forced

### 10.1 Item 9 — expressing an hour relative to waking — dropped

**What it asked for.** That an offer say "about ninety minutes after you wake"
rather than "around 7am", on the §3.3 argument that a clock hour is not the
person's time.

**Why it is not built.** The argument is right about the *problem* and wrong about
the *remedy*. Two things follow from knowing when somebody wakes: do not name an
hour they are asleep for, and phrase the hour in their terms. The first is a gate,
it is the half that prevents a harm, and it shipped as item 10. The second turns
out to make the copy worse.

"Around 7am" is what somebody sets an alarm by. "About ninety minutes after you
wake" is what they have to do arithmetic on before they can act, and `PRD-PLAIN.md`
asks of every sentence whether it could be shorter without losing the fact — this
one is longer and loses the fact somebody needs. The compromise, naming both, fails
the same test twice over.

The intermediate version — keeping the clock hour and adding a short qualifier like
"first thing" when the hour sits close to waking — was written out and reads as
padding. `ExperimentCopy.where_` already returns "around 7am", which is plain, and
nothing in the sweep's three questions asks it to be anything else.

**What was kept.** `WakeShape.usualWake` exists and is read, because the gate needs
it. If a later surface genuinely wants to speak in waking-relative terms — a
morning-specific screen, say — the value is already there and refuses honestly when
somebody has no usual waking time.

**Reopening it** would need a reason that is about the reader rather than about the
engine's representation, which is the test §4 sets for everything in this document.

### 10.2 A total-support floor is not enough — two-sided support added

**What the PRD asked for.** One `minimumSupport` floor: below it, nil.

**What the cohort found.** That floor catches `extrapolator`, whose support at
07:00 is `0.00` — an hour far from everything. It does not catch an hour just
*outside* the edge of somebody's day. The interpolator's curve, with the floor as
specified:

```
4:3.47(s14)  5:3.46(s29)  6:3.44(s43)  7:3.40(s48)  8:3.36(s42)
```

04:00 and 05:00 score **above** the planted hour and clear a floor of 6 comfortably.
The arithmetic is right: no hour is logged at the peak, so the curve plateaus across
06:00–08:00, and an hour beyond the earliest logged one inherits that plateau
without the afternoon pulling it down. The argmax landed on an hour this person has
never been awake for — the exact failure the feature exists to prevent, in a shape
the floor cannot see.

**Why one number could not do it.** `minimumSupport` answers *"is this hour near
anything?"*. The question that matters at the edge of a day is *"is this hour
**between** things?"*, and the two have different answers exactly there. §2 of this
document already draws that line and the implementation had collapsed it into one
test.

**The rule.** An hour needs kernel mass earlier *and* later —
`minimumSideSupport`, half the total floor on each side, the weakest rule that
still means "surrounded" rather than "near". Hours 4, 5, 9, 12, 20 and 21 drop out
of the interpolator's curve; 06:00–19:00 remains, and among the hours they do not
already use **07:00 wins**, which is where the effect is planted.

**Open decisions 2 and 3, settled by measurement**, as §8 said they would be.
Bandwidth 1.5 and total floor 6. At that bandwidth the interpolator's support at
07:00 is **48.05** and the extrapolator's is **0.00** — not a close call, which is
what makes the exact value of the floor uncritical and the existence of one
essential. `RatingShapeTests` is the record and fails if either moves.

### 10.3 The hour-led offer cannot reach anybody — **blocking, needs a decision**

**What was built.** `ExperimentHours` reads `RatingShape`, picks the best hour the
person does not already use, respects waking and workdays, and writes a premise
that names the hour and says plainly that nothing logged settles it. Nine tests,
all passing. The source works.

**What it cannot do.** Fire. Measured on `interpolator`, through the real chain:

```
measured time ids: time.{morning,midday,afternoon,evening}.vs.rest.feeling   — all four
candidates:        07:00, 10:00, 18:00, 11:00
band for top:      Morning  → already measured → excluded
```

**Why, and it is not a bug.** Two constraints meet and leave no room:

1. **The change must ask for what the fortnight measures.** `ExperimentCopy.vitalsChange`
   records this: the experiment settles against `time.<band>.vs.rest.feeling`, whose
   focus side is every session in the band, so a change asking for an hour would have
   adherence counting mornings while the card said seven o'clock — somebody logging at
   eleven every day would clear adherence without doing the thing. So the change asks
   for the band, and the offer carries the band's row.
2. **Anybody dense enough for a curve has their bands measured already.** The curve
   needs ten days of ratings spread across hours; a record that dense carries six days
   either side of every band. So the row the offer carries is a question already
   answered, and the chain correctly refuses to ask it again.

Widening either is wrong. Letting a measured question be re-offered would spend
somebody's fortnight on a settled question. Loosening the band tie would break
adherence, which is the thing that makes a result mean anything.

**The only way out is an hour of its own.** The experiment would target "sessions
within the kernel's reach of 07:00, against the rest", which:

- makes the change honestly hour-level, so adherence counts the thing asked for;
- is a genuinely different question from the band, so offering it is not a repeat;
- **must never enter `HypothesisRegistry.hypotheses`**, or every person pays power
  under the correction for an hour only one person was offered. It would exist as an
  experiment target only — which the system already half-supports, since `BACKLOG.md`
  records a randomised experiment whose hypothesis has left the registry falling
  through to the chosen-window copy.

**Why this is not being built unasked.** It reaches the correction, adherence and
outcome resolution — three places where a mistake is a wrong answer rather than a
missing one — and it is materially more than §5 budgeted for phase 4. It is a scope
decision, not an implementation detail.

**Until it is settled**, `ExperimentHours` is dead code behind a live wiring: it runs
on every offer build, returns nothing, and costs one `RatingShape.fit`. It is left in
place rather than removed because the source is correct and tested, and the thing
missing from it is a row.

### 10.4 The priors were coarsened, not sourced — and that was the honest branch

Item 19 offered two routes: a citation beside every row, or three levels intuition
can defend. Taken: **three levels.**

**Why not citations.** A citation that has not been checked is worse than an honest
shrug — it moves a number from "somebody guessed" to "somebody measured" without
anybody having measured, and it makes the next reader trust a row more rather than
less. Verifying twenty-four rows against real literature is a piece of research, not
a coding task, and half-doing it would leave the table in the worst state of the
three: some rows sourced, some not, and nothing on the page saying which.

**What was wrong with the numbers.** Every value in both tables was hand-set from
intuition — the engine document says so in its own §10.7 — and they sat at two
decimals beside each other as though 0.68 and 0.66 differed for a reason. Nothing
was ever measured that could separate them, and a reader could not tell invented
precision from recorded precision.

**The levels.** `Belief.wide` (0.82) — almost everybody believes it and there is a
plain mechanism. `Belief.common` (0.68) — generally believed, nothing surprising.
`Belief.leaning` (0.58) — believed by many and genuinely contested, or resting on
evidence that is thin, lab-bound, or measuring something adjacent to what is
claimed. The ends of the old range are kept, so the table's overall ordering is
unchanged and only the invented distinctions inside it are gone.

**Ties are the point.** Rows that differed by two hundredths now score identically
and are separated by specificity and evidence instead — the terms that rest on this
person's own record. That is the right order of authority and the old precision
obscured it.

Both tables took the same three values rather than a second scale, since "how widely
is this believed" means the same thing in each and two vocabularies for one idea is
how they drift apart.

**One test moved.** `pairingsAreUnreachableFromAFinding` pinned `0.66`. Its subject
is which row a finding reaches, not what is in it, so it now asserts that the band
row was found rather than a literal — which is what it was always about.

**Item 20.** The chronotype caveat already sat beside the pairings. It now sits in
the table's own boundary note, where it covers every time-of-day row: between-person
spread in when people are at their best exceeds the average time-of-day effect, so
such a row describes a population whose two halves point opposite ways and may be
backwards for any individual. Survivable only because a prior chooses a question and
the fortnight answers it — a wrong row costs somebody a question they did not need,
where the same row quoted as a reason would cost them a wrong belief about
themselves. It is also why no time-of-day row sits above `common` and every pairing
sits at `leaning`.

### 10.5 Resamples raised to ten thousand, measured, and put back

**What §10.3 of the engine document says.** The bootstrap p is floored at one
resample, so at two thousand the smallest p any comparison can report is 0.0005 and
every planted effect in the cohort reports exactly that, leaving BH to discriminate
only in 0.005–0.05.

**The compression is real. It changes nothing.** BH keeps the largest *k* with
`p(k) ≤ (k/m)·q`, so a floored p only blocks a finding when `1/R > q/m` — that is,
when `m > q·R` = 0.10 × 2000 = **two hundred hypotheses in one run**. The registry
mints about twenty testable main effects and `InteractionBudget` caps candidates at
thirty. Ties at the bottom of a step-up procedure do not move its cutoff.

**Measured rather than reasoned at.** At ten thousand the unit suite ran **1050
seconds against 310** — a 3.4× tax on every run — and the only test that changed
behaviour was one asserting the old floor as a literal. So the raise buys headroom
for a registry four times the current size and nothing else.

**Put back to two thousand, with three things kept:** the count is now one named
constant instead of a bare `2000` in fifteen signatures across seven files, so the
change is a one-line edit when it is due; `StatisticsTests` derives the floor from
the count rather than pinning `1/2000`, since a test that cannot tell a moved floor
from a regression is worse than no test; and `BACKLOG.md` records the condition that
reverses the decision — `m` approaching two hundred, most likely by adding outcomes,
which the engine document raises as its own §10.9.

### 10.6 A filter, not inverse-variance weighting

**The gap.** `Reading.uncertainty` widens with cadence and with how few samples a
window held, and gated only what could be *shown*. The residual then entered layer 2
as a plain number, so a reading carried with a 12 bpm error bar counted exactly the
same as one carried with 5. The engine document's §10.8, which offers two remedies.

**Why not the weighting this phase asked for.** The statistic is Cliff's delta, a
rank statistic over *pairs*, so a weighted version is a different estimator — and the
measured false-positive behaviour the whole silence budget rests on (0/300 at ninety
days, 16/300 at twenty) was measured for the unweighted one. Swapping estimators
invalidates that table until it is measured again, which is a piece of work rather
than a line. A filter removes rows and leaves the estimator exactly as measured.

**The bar is derived, not invented.** `DayShape.minimumDifference` is five beats —
the smallest difference this app will say anything about. An error bar wider than
twice it cannot support a statement about a difference that size. So ten, from a
constant the app already committed to.

**It is selection on a covariate, not on the outcome, and that distinction is the
whole safety argument.** `uncertainty` is built from cadence, sample count and the
curve's own scatter; none of them reads the residual. Filtering on
`exceedsUncertainty` instead — which was the tempting one, since it already exists —
would keep the large residuals on both sides of every comparison and drop the small
ones, inflating every effect size measured afterwards. `ResidualPrecisionTests` pins
that the entry gate ignores the residual's value, because the hazard is that somebody
later swaps one for the other.

**What it costs, measured.** Sitting still loses nothing (100% kept, uncertainty
4.4–5.7). Walking through most of a day loses a good deal — `walksEverywhere` keeps
51%, `walksAndStrains` 39%. Those are the people the residual layer was built for, so
a test pins that a walker keeps enough readings to still be compared; a bar set too
high would remove the whole case the layer exists to find, and the suite would stay
green because the claim would simply stop being made.

### 10.7 §10.3 is closed, and it was not the last gate

**What §10.3 said was needed.** An hour-level hypothesis that never enters the
registry, so it costs nobody power under the correction, and makes the change
honestly hour-level so adherence counts the thing asked for. It was estimated as
reaching the correction, adherence and outcome resolution — "three places where a
mistake is a wrong answer rather than a missing one".

**That estimate was wrong and the work was contained.** Traced:

- **The correction** is not touched. An unregistered row never enters `m`, and a
  pre-registered experiment's verdict never goes through BH at all.
- **Adherence** is not touched. `ExperimentOutcome` already counts it with
  `hypothesis.focus`, so an hour-shaped focus makes adherence hour-shaped for free —
  the very constraint that forced the band dissolves the moment the row is an hour.
- **Outcome resolution** is one two-line function, and `ExperimentOutcome.read`
  already takes the hypothesis as a parameter and handles nil gracefully.

So `HourHypothesis` was built: minted on demand, rebuilt from its id at settling
time — which an hour can be and most rows cannot, since its focus is arithmetic on a
start time and needs nothing from the record. The window is half an hour either
side, narrow because the neighbours are exactly what the offer must be separated
from: the interpolator logs 06:00 and 08:00, and at a full hour either side both
would count as adherence to a request for 07:00.

**The second gate, one level up.** The offer still does not survive the whole chain,
for a different reason. `ExperimentHours` serves only priorities carrying
`.bestTimeWindow`, which is **`focus` alone**, and `completing` skips any priority an
earlier source already served. `ExperimentDesign` serves focus for almost everybody —
if nothing is measured it still emits a starter — so the hour-led offer is skipped
before it is reached.

**That is a ranking question, not a bug, and it is the one §5 did not anticipate.**
The chain's rule is that measured beats unmeasured, which is right and is pinned by
`measuredComesFirst`. But the measured proposal for a habitual early riser is "log
one session in your morning", which is a request to keep doing what they already do,
while the hour-led offer is "try 07:00, which you never have". The second is worth
more to that person and the chain has no way to say so, because it compares sources
rather than what a proposal would actually ask somebody to change.

Closing it means a rule about **how much a proposal asks for**, not about where its
evidence came from — and that reaches `ExperimentDesign`, which is the most
load-bearing source in the chain. Left for a decision rather than taken at the end of
a long session.

**What is reachable today.** The source, its row and its copy are correct and
tested, and the offer appears wherever focus is unserved. `OfferChainTests` asserts
the ordering and the registry rule at that level and says in its own comment why not
through `experimentProposals`.

---

## 9. Checklist

### Phase 0 — the instrument
- [x] **1.** `Planted.hourOfDay(hour:halfWidth:delta:)`, tapering rather than stepped.
- [x] **2.** Hour placement stated on the recipe; existing people byte-identical.
- [x] **3.** Interpolator, Extrapolator, flat hours.
- [x] **4.** The planted effect reaches the ratings, asserted without the engine.

### Phase 1 — the body, made reliable
- [x] **5.** The empty-`DayShape` defect diagnosed, with the cause named.
- [x] **6.** Fixed, and a test that fails on the bad dates rather than passing on
      the good ones.
- [x] **7.** `README.md`'s date-dependence note gains the third instance.

### Phase 2 — the day anchored to waking
- [x] **8.** A usual waking time from Health, with its own refusal.
- [~] **9.** ~~Offers express an hour relative to waking.~~ **Amended — not built.**
      See §10.1.
- [x] **10.** Never an hour before the person is up; tested.

### Phase 3 — the curve
- [x] **11.** `RatingShape`, day-clustered, wrapped, workday-split.
- [x] **12.** Support weight per hour, nil below the floor — **and on each side of
      it**, see §10.2.
- [x] **13.** Interpolator recovered; Extrapolator refused; flat hours silent.
- [~] **14.** No figure from the curve reaches any string. **Deferred to phase 4**,
      where the first string exists; `RatingShape` has no string-producing API to
      test against today.

### Phase 4 — the offer
- [x] **15.** `ExperimentHours`, wired into `offers` in the §5 order. Carries
      `HourHypothesis` since §10.3 closed; reachable wherever focus is unserved, and
      skipped above that — §10.7.
- [x] **16.** Premise under the §9 framing rule, guard-enforced.
- [x] **17.** Workdays and waking respected.
- [x] **18.** `OfferChainTests` extended. The ordering is asserted at the source
      rather than through `experimentProposals`, because of §10.3.
- [x] **14.** No figure from the curve reaches any string. *(Deferred here from
      phase 3; the first strings now exist.)*

### Phase 5 — the priors table
- [x] **19.** Every entry sourced or coarsened; provenance beside the number.
      **Coarsened** — see §10.4 for why, and why not sourced.
- [x] **20.** The chronotype caveat recorded beside the table, over every
      time-of-day row rather than only the pairings.

### Phase 6 — confidence
- [ ] **21.** Isotonic calibration fitted offline, shipped as a table.
- [ ] **22.** What was calibrated against, stated in `DESIGN.md`.

### Phase 7 — hygiene
- [~] **23.** ~~Resamples raised~~; **raised, measured, reverted — §10.5.** The
      floor is now derived from the count in both the code and the test, and the
      count is one constant rather than fifteen literals.
- [~] **24.** ~~Inverse-variance weighting in `Statistics.compare`~~ — **a filter
      instead, §10.6.** The gap §10.8 names is closed.

### Verification
- [ ] **25.** Full unit suite on iPhone 17 Pro by UDID, then the UI suite.
- [ ] **26.** `DebugFixture` reaches an hour-led proposal.
