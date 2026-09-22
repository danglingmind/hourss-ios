# Backlog

What was planned or surfaced during the first-week work and did not get built.

Every item below was checked against the code before it was written down, and
several of them read differently from how they were remembered — those
corrections are stated inline rather than quietly fixed, because the wrong
version is what somebody will arrive carrying. Where a claim here rests on a
line of source, the line is named.

Baseline at the time of writing: 312 unit tests passing, UI suite passing. Both
interaction suites also pass in isolation — see *The interaction suites' green is
untested*, which is not the same statement.

---

## Where to start

Ordered by what earns most per hour, not by importance. The first three are
genuinely small.

1. ~~**Seed Health into the debug fixture**~~ — DONE. Wired into `DebugFixture.seed(into:)`. `store.healthByDay` is empty
   in the simulator, so neither shipped feature can render there. Both UI suites
   already admit this in a comment and work around it. Everything visual below is
   blocked behind this, including looking at your own work.
2. ~~**The sweep**~~ — DONE. Build is warning-free. One dead local the compiler already warns about, one
   no-op ternary, three stale doc comments, two unused spacing tokens, one dead
   enum. None of it changes behaviour; all of it is currently lying to the next
   reader.
3. **`DayContextCard`'s date** (*small, decision*). One line, either way, and it
   is wrong today for anybody rating from the Journal.
4. **Record-fed facts.** The largest gap. The fact pool is fixed at ~37 items and
   does not grow as somebody logs, which is the opposite of the intent.
5. **Two rule weights** (*small-ish, design decision*). One 1pt `HRule` does two
   different jobs across 90 call sites, so a screen has no rankable structure.
6. **The interaction suites' isolation.** Cheap to instrument, and until it is
   done the suites' green means less than it looks like.
7. **Measurement** (*decision*). The app contains no analytics of any kind, so
   this is a decision about whether to add a network dependency, not a ticket to
   add an event.
8. Everything else, roughly in the order it appears below.

---

## Facts that grow with the record

### Record-fed fact generators

**Status:** partially built. The shape is settled and one generator ships; three
of the four listed problems are solved, and the remaining work is more
generators rather than more design.

**Done.** `Fact.metric` and `Fact.group` collapsed into `Fact.Subject` —
`.health(HealthMetric)` or `.record(RecordTopic)` — with computed `title`,
`healthGroup` (nil for a record fact, which is what keeps it out of the consent
scope and the engine's factor space), `key` and `varietyKey`. `RecordFacts.pool`
supplies `longestStretch`, excluding imported sleep. `DailyFact` takes the two
pools separately and offers the record first: merging them was wrong, because
`surprise` scores an unknown prior at half a bit against better than four for a
strong Health prior, so a record fact would have sorted below nearly every
Health fact and arrived five weeks late — the opposite of its purpose. Key
parsing now splits from the end, since a record key has three components where a
Health key has two; splitting from the front had silently disabled variety
control for exactly the facts added to improve it. `AllFactsView` leads with the
record sections. `build(from:)` is untouched and still Health-only, which is
right: on day one there is no record.

**Still to do.** `RecordTopic` now has three cases — `.length`, `.coverage`,
`.dayTotal` — and each is a variety axis, so each one widens the distinct-day
count. Facts also carry a `revision`: a record fact keyed on subject and kind
alone was dispensed once and never again, so beating your own longest stretch
went unmentioned, which is the single most obvious thing the feature exists to
do. The discriminator sits after a `#` so the kind stays readable off the end of
the key, and `pair(ofKey:)` strips it so two holders of one record are still one
topic for variety purposes.

The remaining generator worth writing is a ratings superlative, and it does not
belong in this pool. On a five-point scale the top value is usually tied several
ways, so the honest formulation compares one session against everything logged
before it at the moment of rating — which makes it a `DayContextCard` fact, not a
dispensed one.

**Deliberately not built: a logging streak.** It is descriptive and would pass
every rule in `RecordFacts`, and it is still the wrong fact for this app. A
streak is a thing somebody can break, so the moment it exists the app has an
opinion about how often you log — on a screen whose empty state reads "Whatever
you're doing right now is enough." Every other fact here reports something that
happened; a streak reports something you are at risk of losing. Adopting it is a
product decision somebody should make out loud.

---

## Physiology per session

### Move 2 — session-level escalation

**Status:** not built, and blocked on two pieces of infrastructure. The
day-level card (`DayContextCard`) is what shipped.

**Why it matters.** The plan was that the 2nd and later rated sessions of a day
return a per-session signal rather than nothing: `heartRateResidual` — *"your
heart rate ran below what your movement explains"* — and `cadence`. Both fields
already exist on the observation
(`Hourss/Store/EngineContracts.swift:44` and `:48`), fed from
`Physiology.Reading` via `ObservationBuilder.swift:57-58`, and the engine already
treats `heartRateResidual` as an outcome. The measurement is built. Nothing
surfaces it per session.

**The blockers, all verified.**

- **Nothing re-reads HealthKit after launch.** `HealthService.refresh()`
  (`Hourss/Store/HealthService.swift:201`) is reached from exactly four places, all
  user- or launch-triggered: cold launch (`Hourss/HourssApp.swift:61-64`),
  onboarding (`Hourss/Features/Onboarding/OnboardingFlow.swift:185`), the Connect
  button in You (`Hourss/Features/You/YouView.swift:559` → `connect()` →
  `finishConnecting()`), and the recheck button
  (`Hourss/Features/Health/ReconnectHealthView.swift:57` → `recheckAccess()`).
  A grep across `Hourss`, `Shared`, `HourssWidgets` and both test targets for
  `scenePhase`, `BGTaskScheduler`, `HKObserverQuery`, `willEnterForeground`,
  `didBecomeActive` and `enableBackgroundDelivery` returns **nothing**. A session
  rated at 3pm is scored against heart-rate samples read at 8am, which do not
  include it.
- **A window needs 5 heart-rate samples.** `Analyzer.minimumHeartRateSamples = 5`
  (`Hourss/Store/Physiology.swift:464`). At the resting sample rate that is roughly
  20–25 minutes, so short sessions return `nil` — correctly, but it means the
  escalation is silent for a large share of what people log.
- **Any workout blacks out the following 45 minutes.**
  `Analyzer.leadInMinutes = 45` (`Physiology.swift:488`), enforced by
  `isContaminated(before:)`. The doc is explicit that a contaminated baseline is
  *not correctable*, so this is a real exclusion and not a tunable.
- **The residual is never persisted.** `Record`
  (`Hourss/Store/RecordStore.swift:13-40`) has no physiology field, deliberately:
  *"Health is absent because HealthKit already holds it and re-reads it."* The
  curve is refit on every launch from a rolling 60-day window
  (`HealthService.physiologyDays = 60`, `HealthService.swift:429`;
  `readPhysiology()` at `:434`), so the same session's residual differs tomorrow
  as the window slides. Showing somebody a number today and a different number
  for the same session next week is worse than showing nothing.

**The one piece of good news.** The 10-day curve requirement is on *sensor*
history, not logging history. `MovementCurve.minimumDays = 10` and
`minimumWindows = 20` (`Physiology.swift:274-277`) are counted over window
summaries, and `Window.tiling` fits from unlogged time by design — *"Fitting it
only on logged sessions wastes the overwhelming majority of the day and makes the
curve hostage to a habit"* (`Physiology.swift:136-147`). So a Watch user with 60
days of samples has a fitted curve on day one, before they log anything.

**What it would take.** Persistence plus a refresh trigger, in that order.
Persistence is the harder half because it reverses `Record`'s stated reason for
excluding Health: a stored residual is a *derived* value being kept, which is the
thing `RecordStore.swift:5-8` says makes claims and data drift apart. The
defensible version stores the residual with the curve's own identity — window
count, day count, reference bin — so a reading fitted from a different curve can
be recognised and dropped rather than silently reused.

**Cost to watch.** `HourssStore.applyPhysiology(feed:)`
(`Hourss/Store/HourssStore.swift:507`) constructs `Physiology.Analyzer`, which
tiles 60 days into 30-minute windows (~2,900 of them), summarises each, and fits
— synchronously, on the main actor, since both `applyHealthRead`
(`Hourss/Store/HealthImport.swift:164`) and `HourssStore` are `@MainActor`. It
also triggers `rebuildInsights()` twice per read, once from `applyHealthContext`
and once from `applyPhysiology`. Today that cost is paid once at launch behind a
splash. A foreground trigger moves it into **every resume**. `Analyzer` is
`Sendable` and pure, so moving the fit off the main actor is possible and is
probably a prerequisite rather than a follow-up.

**Also worth knowing.** `Physiology.Reading.exceedsUncertainty`
(`Physiology.swift:443`) — *"Whether the residual clears its own error bar.
Anything that does not is a number, not a finding, and must not be shown as
one"* — currently has **zero callers**. It is the gate this feature needs, already
written and unused. Do not build a surface that forgets to call it.

---

## The sealed guess

### Move 3 — commit to a guess, then show whether it held

**Status:** not built. Deliberately held, and the hold was right.

**Why it matters.** On day one, from Health data alone, the app commits: *"my
guess: your sharpest stretch is 9–11am — I could be wrong, log a week and we'll
see."* Over the following week it shows whether the person's own ratings agree.
Being wrong is a *good* outcome and is the interesting payoff — an app that
predicted you and missed is more credible than one that never risked anything.
Highest-upside item here, and the highest-risk.

**The risk, stated honestly.** This was remembered as being close to a "Signal"
tier that was deliberately rejected. There is no such tier anywhere in the
source, `README.md` or `DESIGN.md`, so that framing cannot be checked — but the
collision it was pointing at is real and is written down in two places:

- `SlotContent.evidenceProgress` (`Hourss/Store/ObservationSlot.swift:47-53`):
  *"This is a floor and never a forecast. Copy rendering this must not carry a
  date, a remaining count, or any word implying that reaching the floor produces
  a recommendation."*
- `SlotContent.stillLooking` (`ObservationSlot.swift:55-61`): copy *"may not
  suggest something is being withheld, nor that more logging will change the
  answer, because for a person whose days genuinely are flat it will not."*

"Log a week and we'll see" is a forecast with a remaining count in it. The
proposed distinction — that the sentence claims something about *the app* rather
than hedging a claim about *the user's data* — is a genuine distinction and it is
the entire load-bearing argument for the feature. It is also one word of copy
away from becoming the thing both rules forbid, and both rules exist because the
failure they prevent is unrecoverable: a countdown that empties and delivers
nothing is what a member remembers the product for.

**What it would take, if it is taken.** Not much code — a stored guess with a
made-on date, and a weekly resolution against rated sessions. The work is
elsewhere: a copy contract with its own sweep test (the model is
`DayDeviationTests`' sweep over `DayContextCopy`), and an explicit written
decision in `DESIGN.md` that this is a sanctioned exception to
`evidenceProgress`'s no-forecast rule, in the same form the filled-capsule
reversal would need. Do not ship it as a quiet exception.

---

## Knowing whether any of it worked

### Decide whether to add analytics at all

**Status:** decision needed. Nothing exists to extend.

**Why it matters.** The one number that decides whether the first-week work
succeeded is *rated sessions on six distinct days before the fact pool runs
out* — six days being where the evidence floor starts to become reachable
(`EvidenceFloor.days = 12`, `Hourss/Store/ObservationSlot.swift:75`), and the
pool being ~37 facts at one a day. Nothing measures it.

**What was actually found.** A grep across `Hourss`, `Shared` and
`HourssWidgets` for `Analytics`, `analytics`, `telemetry`, `track(`, `logEvent`,
`Mixpanel`, `Firebase`, `Amplitude`, `Sentry`, `os_log`, `Logger(` and
`URLSession` returns **nothing at all**. There are five `print` statements, all
inside `#if DEBUG`. The app has no analytics layer, no logging service, and **no
network layer of any kind** — even sign-in goes through `AuthenticationServices`
locally.

So this is not "add an event". It is a decision about whether an app that
currently cannot make an outbound request should acquire the ability, in a
codebase whose standing rules are about never telling somebody something untrue
about themselves and whose privacy settings are free and permanent by design
(`ObservationSlot.swift:9-13`). The honest options are: a local-only counter the
owner reads off a debug screen; a one-off opt-in export; or nothing, and judge
the feature by other means. Whichever it is, write down which and why — an
absent analytics layer that nobody decided on looks identical to one nobody got
round to.

---

## Visual direction deliberately held

### One real button

**Status:** not built. Decision needed, and it is a knowing reversal.

**Why it matters.** `DirectionalLink`
(`Hourss/DesignSystem/Components/Primitives.swift:51-53`) is the only action
idiom in the app: *"Bold text plus an oversized orange arrow. The token file
explicitly bans filled capsules here — the shift on press is the entire
affordance."* `DESIGN.md` restates it as a standing rule and records that a
proposal to exempt one primary action per screen was raised and not implemented.
The proposal was a forest-filled full-width row, exactly one per screen.

**What it would take.** Small in code — a new primitive and one call site per
screen that has a primary action. The work is the decision. `DESIGN.md` already
specifies the shape it must take: *"if it ever is, it belongs here as a
deliberate reversal rather than as a quiet exception."* Whoever builds it writes
that entry first, naming which screens get the exemption and what stops it
spreading. A filled row that appears twice on one screen is the rule gone.

### Two rule weights

**Status:** not built.

**Why it matters.** `HRule` (`Primitives.swift:36-49`) is a single 1pt rectangle
with an optional colour override, and it is used at **90 call sites**. It draws
both structural breaks between regions and separation between list rows, at the
same weight, so the eye cannot rank a screen — everything is divided and nothing
is more divided than anything else. `DESIGN.md`'s standing rule is *"Hierarchy
comes from lines, not surfaces"*, which makes the rule the only instrument
available and means it currently plays one note.

**What it would take.** A heavier structural rule, and then the audit: 90 sites,
each of which has to be classified as structural or separating. The token itself
is trivial. Worth doing as its own pass rather than folded into another change,
because a half-applied weight distinction is less legible than one weight.

**Open question.** `DESIGN.md`'s tab-bar entry already reasons about 2pt vs 3pt
on the grounds that *"this sits 1pt away from the `.rule` hairline that closes
the content area, so the two weights have to stay legible as different things"*.
A structural `HRule` has to pick a weight that stays distinguishable from both
the hairline and the 2pt tab mark. That is a narrow band.

### The full "draw the day" signature

**Status:** partially built. `DayHours` delivers the intent at a fraction of the
scale.

**Why it matters.** The direction was a large full-bleed day form on forest
ground — the day as the screen's signature mark. What shipped is `DayHours`
(`Hourss/DesignSystem/Components/DayHours.swift`): 24 hour cells, `height =
DataBar.reading` = **30pt**, sitting inside `DayTimeline` under an
`Eyebrow("Hours logged")` on canvas (`Hourss/Features/Today/DayTimeline.swift:36`),
matched deliberately to the energy bar on every row beneath it
(`DayHours.swift:39-42`).

The information is all there and `DESIGN.md` records it properly under "The day
has a shape". What is missing is the *weight*: at 30pt inside a scroll view, a
strip reads as one more row of the list rather than as the thing the screen is
about. The gap is entirely scale and ground, not content.

**What it would take.** Not a rewrite of `DayHours` — a second presentation of
it, or a size and surface parameter. The forest ground is the harder part: the
three fill states (`DayHours.swift:276-280`) are canvas-derived
(`surface.track`, `surface.ruleColor`, `Feeling.fillColor`), and only the first
two route through `Surface`. `Feeling.fillColor` does not, so on forest it would
be the same colours on a dark ground with no adjustment — and `DESIGN.md` already
flags that `Color.drainingFill` and `Color.orange` collide, resolved today by the
now-line's 4pt overhang. At full-bleed scale that resolution may not hold.

### Fill the empty middle of the type scale

**Status:** **largely done** — this one is close to resolved, and the remembered
version is out of date.

`TitledFigure` (`Hourss/DesignSystem/Components/TitledFigure.swift`) sets
34 / 26 / 16 (`.dayNumeral` / `.stepName` / `.body`) and is now used on five
surfaces: `EnergyReading`, `HealthFactRow`, `PatternsView`, `DayContextCard`, and
through those, Today and the Journal. Current usage across the app:
`.stepName` (26pt) 14 call sites, `.dayNumeral` (34pt) 8, `.sectionLead` (23pt) 4,
`.bodyLarge` (18pt) 3. The 18–34 band is populated, and populated in body content
rather than only in headings, which was the actual complaint.

**What remains** is the far end, not the middle: `TypeStyle.display` (55pt) has no
`textStyle` call site at all and survives only as `DisplayHeadline`'s default
(`Primitives.swift:117`), and `readingScore` (58pt) is now entirely unused — see
*Retire or rehome `readingScore`* below. Close this item; open that one.

---

## Defects and debts

### Seed Health into the debug fixture

**Status:** *small fix, highest value per line in this document.*

**Why it matters.** `DebugFixture.seededDaily(for:)`
(`Hourss/Store/DebugFixture.swift:50`) and `DebugFixture.seededFeed(days:now:)`
(`DebugFixture.swift:268`) are both fully written, both deterministic, and both
have **zero callers**. `DebugFixture.seed(into:)` sets `sessions`, `reflections`
and rebuilds insights (`DebugFixture.swift:258-260`) and never touches
`healthByDay`. The only writer of `healthByDay` in the app is
`applyHealthContext`, reached only from `applyHealthRead`
(`Hourss/Store/HealthImport.swift:166`), which needs a real HealthKit read.

So in the simulator, with the fixture launch argument, `store.healthByDay` is
empty. `DailyFact().fact(for:from:)` is handed an empty pool
(`Hourss/Features/Today/TodayView.swift:86`) and returns `nil`, so the daily fact
row does not exist. `DayDeviation.standout(on:history:)` returns `nil`
(`Hourss/Features/Logging/ReflectionView.swift:133`), so the post-rating card
never appears. Neither of the two features that shipped can be looked at.

The UI suites already know. Both `HourssUITests/PastSessionTests.swift:192-196`
and `HourssUITests/LiveActivityTests.swift:294-298` carry the same helper, with
the same comment: *"The card only appears when Apple Health has a settled
deviation to report, which a simulator with no Health data never does… Asserting
on it here would be asserting on the machine rather than on the app."* They
conditionally dismiss the card and assert nothing about it.

**What it would take.** Call `seededDaily` for each metric from `seed(into:)`,
via `applyHealthContext`, and `seededFeed` via `applyPhysiology(feed:)` — the
file is `#if DEBUG` in its entirety, and the header
(`DebugFixture.swift:7-16`) explains that this is exactly why the gate is on the
file and not the call site. Then the two helpers above can become real assertions,
and `AllFactsView` becomes reachable in a screenshot run for the first time.

Check one thing while doing it: `seededDaily` generates weekend/weekday contrast
by construction, and `DayDeviation.minimumZ = 1.5` against a 14-day MAD
(`DayDeviation.swift:66-74`). The seed may need a planted outlier on today for the
card to fire deterministically, rather than firing on whichever day the test runs.

### `DayContextCard` shows last night's fact for last Tuesday's session

**Status:** *small fix, decision needed — one line either way.*

**Why it matters.** `ReflectionView.rate()` resolves the standout for `Date()`
(`Hourss/Features/Logging/ReflectionView.swift:133`), not for the session being
rated. Rating a session from last Tuesday through the Journal raises a card about
*last night's* sleep. It breaks no rule — the card never references the session,
which is its governing property (`DayContextCard.swift:5-8`) — and it reads
oddly, because the reader has just been looking at a date that is not today.

**The decision.** Either pass the session's day (`session.startAt`), which makes
the card about the day being rated and is what a reader would assume; or leave it
and accept that the card is about today because *today is when it is being shown*,
which is the argument the card's own header makes. Passing the session's day has
a cost worth knowing: `DayDeviation` needs ≥14 prior days for the metric
(`DayDeviation.swift:66`) and `HealthService` reads a 365-day window, so an old
day still resolves — but the standout for a past day will not change, so the card
becomes repeatable on that day, which the once-per-calendar-day claim
(`HourssStore.isContextCardDue`, `HourssStore.swift:301`) happens to cover.

Pick one and say so in a comment. It is ambiguous today, which is the actual
defect.

### Editing an old reflection can fire the day-context card

**Status:** blocked on a signal the save path does not carry.

**Why it matters.** `ReflectionView.onAppear` loads an existing reflection into
`@State` (`ReflectionView.swift:110-116`), and `rate()` requires only that
`feeling != nil` and `store.isContextCardDue`
(`ReflectionView.swift:131-132`). So opening last week's reflection, changing a
note, and saving will raise the day's card if no card has been raised yet today —
a reward for an edit rather than for a rating.

**What it would take.** A "was this reflection new" signal. `saveReflection`
(`Hourss/Store/HourssStore.swift:260-272`) overwrites the dictionary entry
unconditionally and has no notion of insert versus update, and `isContextCardDue`
is a bare calendar-day comparison against `UserDefaults`
(`HourssStore.swift:301-303`). The cheap version is local: capture whether
`store.reflection(for: sessionId)` was `nil` in `onAppear` and require that in
`rate()`. The honest version is that `saveReflection` should return or report
whether it created, since the card is not the only thing that will eventually
want to know.

**Open question.** Should changing a *rating* on an old session count? A person
who rates a session they had skipped has rated something for the first time. The
`nil`-on-appear check gets that right by accident; a
"session-had-no-feeling-before" check gets it right on purpose.

### The reflection's rating lives only in `@State` while the card is up

**Status:** partially mitigated. The residual risk is a hard kill.

**Why it matters.** The save is deliberately deferred: the store clears
`pendingReflectionSessionId`, which *is* the sheet's binding, so a card raised
after a save would be raised onto a torn-down view
(`ReflectionView.swift:119-124`). While the card is on screen the rating exists
only in `@State`. Two covers are in place: `.interactiveDismissDisabled(card != nil)`
(`ReflectionView.swift:106`) and an `onDisappear` commit
(`ReflectionView.swift:107-109`), with `commit()` made idempotent
(`ReflectionView.swift:152-156`). Neither runs on a process kill — app-switcher
swipe, or an OOM — and the window is however long somebody reads the card.

**What it would take.** Either persist on tap and re-present the card from the
store rather than from view state (the structural fix, and it requires unpicking
the binding coupling above), or write the pending rating to a scratch key on
appearance of the card and reconcile it at launch. The second is small and ugly;
the first is right and touches `Hourss/Navigation/RootView.swift:99-101`, which is
where `pendingReflectionSessionId` is actually bound.

**Note while you are in there:** the file's own header claims *"Feeling saves the
moment it is tapped"* (`ReflectionView.swift:5`). It does not — there is no
`onChange` anywhere in the view, and `commit()` is the only writer. The header
contradicts the deferred-save comment 97 lines below it. Fix the comment even if
you do not fix the behaviour.

### `StartSessionView` cannot prefill a slot older than 16 hours

**Status:** known, documented, unfixed.

**Why it matters.** Tapping an empty hour on the hour strip calls
`store.requestLog(at:)` (`DayTimeline.swift:42`), and `adoptPendingSlot`
(`Hourss/Features/Logging/StartSessionView.swift:258-282`) switches to past mode
and then gives up: `windowStart` runs back `maxDurationMinutes` = 16 hours
(`StartSessionView.swift:26`, `:40`), so an hour tapped on an older Journal day
fails the `offset >= 0, offset <= latestStart` guard
(`StartSessionView.swift:278`) and the sliders keep their last-hour default. The
mode still changes, which is deliberate and documented
(`StartSessionView.swift:264-270`) — the tap did mean "this already happened" —
but the person is now looking at a sheet set to today with no indication that
their tap was partly ignored.

**What it would take.** The sliders' whole coordinate system is minutes from
`windowStart`, and 16 hours is not arbitrary — it is the spec's longest valid
session, and the window is what lets a slot cross midnight
(`StartSessionView.swift:28-39`). Options: add a date component to the sheet for
the past case (largest, most correct); or refuse the tap on out-of-reach days at
the strip and say why, rather than opening a sheet that cannot express it
(smallest, and honest). The current behaviour is the worst of the three because
it silently half-answers.

### The observation slot's `"N of 12 days with a rating"` leads with its number

**Status:** blocked on a test, then a copy decision.

**Why it matters.** Every other readout in the app now names its subject first —
that is what `TitledFigure` is for, and `DESIGN.md` lists the surfaces where it
was deliberately not applied. This is the one readout still leading with a
figure. It is generated at
`Hourss/Features/Today/ObservationSlotView.swift:313` and pinned verbatim by
**`HourssTests/SlotTests.swift:314`**:

```swift
#expect(copy.lines.map(\.text).contains("7 of 12 days with a rating"))
```

with the spoken form pinned at `SlotTests.swift:317`. Both have to be relaxed
before the string can move.

**Why it is not simply a bug.** `DESIGN.md`'s table lists it as deliberately left
alone, on two grounds that both still hold: it is prose at the same size as every
other slot lead line with `Eyebrow("Evidence so far")` already above it, and the
slot's own rule is "one thing, never a feed" — a `TitledFigure` here is three
elements where the band allows one. And the copy is under a written constraint of
its own (`ObservationSlotView.swift:299-311`): no date, no "until", no count of
anything remaining, because every one of those turns a floor into a countdown.

**What it would take.** Relax the two `#expect`s to assert the *properties* the
copy must have — contains the day count, contains the floor, carries no date —
rather than the exact sentence. That is the right change to those tests
independent of whether the copy moves, and it is the same failure mode that
retired two interaction tests in the last commit: pinning a rendering instead of
a rule.

### Fact repetition tail

**Status:** partially mitigated, twice. Smaller than remembered.

**Why it matters.** The `.movement` group can contribute up to 16 of ~37 facts
(4 metrics × 4 generators, and all four movement metrics are cumulative so
`scale` fires for each), and those metrics are correlated by construction —
`DailyFact` says so at length (`DailyFact.swift:80-92`): *"'your step count has
been running higher lately' and 'your active energy has been running higher
lately' are one fact told twice."*

**What has already been done, and was not in the original note.** Two things.
`DailyFact` now demotes duplicates through a `(group, kind)` preference cascade
(`DailyFact.swift:105-110`) rather than removing them, so sixteen genuinely
distinct days come first and the repetitive tail arrives later, by design. And
`AllFactsView` groups by `HealthGroup` rather than running one ranked list
(`AllFactsView.swift:33-48`), on the explicit reasoning that *"four things known
about sleep is a section, where four sleep cards scattered through a list is a
stutter."*

**What is left.** Movement is still the longest section in the all-facts list and
still the most internally repetitive within itself. The remaining options are
narrow: cap facts per metric (loses true facts), cap per group inside a section
(same), or accept it. Probably accept it and record that — the two mitigations
above address the reading experience, and the last one addresses only a count.

### Hour strip tap targets are 14 × 30pt

**Status:** known, unguarded, and the comment describing it is optimistic.

**Why it matters.** 24 cells across roughly 340pt gives each hour about **14pt**
of width. The cells are flush (`HStack(spacing: 0)`, `DayHours.swift:81`) and
fill the band, so there is no dead ground to miss into — that part is right. But
the comment at `DayHours.swift:185-187` says the target is *"padded out to the
full tap height"*, and it is not: the band's frame is `height` = `DataBar.reading`
= 30pt (`DayHours.swift:42`, `DataBar.swift:20`), and the cell fills that. So the
real target is 14 × 30, and `Space.tapTarget` — the app's own declared minimum —
is 44 (`Hourss/DesignSystem/Spacing.swift:17`). Nothing in `AccessibilityTests`
asserts tap-target sizes, so this is not caught anywhere.

**What it would take, and what it costs.** The obvious alternative,
drag-to-scrub, costs the per-hour VoiceOver labels — each cell is currently its
own control with its own spoken string (`DayHours.swift:284-300`), written that
way precisely because *"an hour that is only ever distinguished by its fill is
distinguished by colour alone"*. A scrubber is one control with one label and the
strip stops being readable without sight.

Cheaper options that keep the labels: give the band an invisible 44pt-tall hit
area while drawing at 30 (fixes the vertical half, which is the half the comment
already claims); or widen the touch slop horizontally so a near-miss resolves to
the nearest hour rather than to the neighbour. Fix the comment either way — it
currently describes a target the code does not build.

### The interaction suites' green is untested

**Status:** not reproducing today. Worth instrumenting, not worth fixing blind.

**Why it matters.** The last commit's own message records it: *"Two interaction
tests removed… The suites they sit in have a test-isolation problem worth a
look — three other tests there change answer depending on which of their
neighbours ran."* The two removed tests
(`InteractionCandidateTests`' `gatingPrunes`, `InteractionCorrectionTests`'
`floorOccupancy`) were removed for a different and defensible reason — both
pinned exact counts from one cohort at one moment — and their removal tombstones
are still in the files. But if three other tests' answers depend on what ran
beside them, then the suites being green is a fact about the run order, not about
the engine.

**What was actually found.** Running both suites alone
(`-only-testing:HourssTests/InteractionCandidateTests
-only-testing:HourssTests/InteractionCorrectionTests`) passes: 23 tests, 2 suites,
55s, no failures. So the symptom does not reproduce from the suite boundary today.
That is worth knowing and is not the same as the problem being gone.

**Where the coupling can be, having looked.** The engine path is clean: no
`Date()`, no clock, no deadline, and no cache anywhere in `Engine`,
`InteractionCandidates`, `InteractionCorrection` or `Statistics`. `factors(in:)`
iterates `allCases` and `Set(...).sorted()`, so no dictionary ordering leaks in.
Randomness is `Statistics.Seeded` throughout, seeded identically at any resample
count. That leaves the test helpers, and two things in them:

- **`SyntheticCohort.anchor`** (`HourssTests/SyntheticCohort.swift:183`) is a
  *computed* property returning `Calendar.current.startOfDay(for: Date())`, and it
  is the origin every generated day is offset back from
  (`CohortGenerator.swift:96`, `:115`, `CohortHealth.swift:76`). The `Cohort`
  people are `static let` (`HourssTests/Cohort.swift:25` onward), so each is built
  **once, lazily, whenever the first test touches it** — and under Swift Testing's
  parallel execution, which test that is varies. Within one calendar day every
  person gets the same anchor and everything is deterministic. Across a midnight
  boundary, two people generated either side of it get anchors a day apart, and
  since the engine reads only hour-of-day and weekday
  (`SyntheticCohort.swift:180-182`), every weekday assignment shifts. A long
  combined unit-plus-UI run straddling midnight would do it.
- **`Person.healthByDay`** (`SyntheticCohort.swift:127`) is also computed, rolling
  up the stored samples on every access. Deterministic, but re-derived per call,
  and `Cohort.swift:5-11` records that the *last* bug of this exact family — a
  computed `Person` minting fresh session UUIDs per access, so sessions and
  reflections had mismatched keys — silently dropped every rating. The static-let
  fix was applied to the person and not to its computed members.

**What it would take.** Do not fix anything yet. Make the anchor a `static let`
so it is captured once per process and the midnight case cannot arise, then run
the full suite with `--repeat-until-failure` or a randomised order a few dozen
times and see whether any of the three tests moves. If nothing moves, record
*that* — with the run count — so the next person does not re-derive this from a
commit message.

### Retire or rehome `readingScore`

**Status:** *small fix.* Unused, with a stale doc comment.

`TypeStyle.readingScore` (`Hourss/DesignSystem/HourssFont.swift:93`) — 58pt
Instrument Serif — has no call sites anywhere in `Hourss`, `Shared`,
`HourssWidgets` or either test target. It went unused when `EnergyReading` was
converted to `TitledFigure` (`Hourss/DesignSystem/Components/EnergyViews.swift:44-50`).
Its doc comment still reads *"The large `/100` numeral in an energy reading"*
(`HourssFont.swift:92`), which describes a thing that no longer exists — and
`EnergyViews.swift:34-36` is where the reasoning for its removal lives
(*"the numeral was always lime regardless of score, so its colour never carried a
value"*).

Retiring it also retires the app's **only upright serif numeral**. The italic
serif survives as `TypeStyle.emphasis(_:)`, used in five display headlines, so
the family stays registered and `FontAudit` (`Hourss/HourssApp.swift:76-80`) stays
satisfied either way. That aesthetic loss was accepted deliberately; the decision
does not need re-litigating, only recording. Either delete the token, or keep it
and replace the doc comment with what it is actually reserved for. Do not leave it
describing a surface that was converted away from it.

### The health-value formatters

**Status:** decision needed, and it is smaller and more contested than
remembered.

**What is actually there.** Two functions format a `HealthMetric` value into a
display string, not three or more:

- `HealthDigest.difference(_:_:)` — `private`, `Hourss/Store/HealthDigest.swift:366`
- `DayContextCopy.figure(_:)` — `Hourss/Features/Logging/DayContextCard.swift:134`

Plus `HealthMetric.totalPhrase(_:)` (`HealthDigest.swift:426`), which formats a
value *and* names it, so it is a third thing rather than a third copy.

**And convergence was already argued against, on the record.** `DayContextCopy.figure`
carries this, verbatim: *"Deliberately its own formatter rather than a widened
`HealthDigest.difference`, which is private and phrases *differences between two
groups* — a different sentence, and the two should be free to diverge"*
(`DayContextCard.swift:131-133`). That is a real distinction: `difference` prints
`"45 minutes"` for a gap and `figure` prints `"8h 02m"` for a night, and they
would need different rules for sleep even if merged.

**The genuine duplication is elsewhere** — the per-metric *direction word*, which
exists in four places: `HealthMetric.higherPhrase` / `lowerPhrase`
(`Hourss/Store/HealthMetric.swift:84`, `:102`), `HealthMetric.lowerDirection`
(`HealthDigest.swift:415`), `Narration.healthPhrase`'s low-side switch
(`Hourss/Store/Narration.swift:296-312`, `private`), and
`DayContextCopy.superlative` (`DayContextCard.swift:161`). Each has a stated
reason to differ — `Narration.swift:287-295` explains that `lowerPhrase` is
elliptical by design and unusable at the front of a sentence — but four
exhaustive switches over eleven metrics means adding a metric requires finding
all four, and nothing points from any of them to the others.

**What it would take.** The honest minimum is cross-references: a comment on each
naming the other three and what makes it different. The larger version is one
`HealthMetric` phrasing surface with named forms (`.leading`, `.elliptical`,
`.superlativeHigh`, `.superlativeLow`), which the copy sweeps could then cover in
one place — currently `DayDeviationTests` sweeps `DayContextCopy` and
`RegistryTests` sweeps narration, and neither sees the other's vocabulary.
`Narration.healthPhrase` becoming non-private is the smallest useful step and
costs nothing.

---

## Found in the audit

Not from the original list. Everything here is verified; sizes are honest.

**No `TODO`, `FIXME`, `HACK` or `XXX` markers exist anywhere in the codebase.**
Worth stating, because it means this file is the only backlog — deferred work in
this repo is recorded in prose doc comments, and prose does not grep. If an item
below is deferred rather than done, it needs a line here.

### Compiler warnings currently shipping

Four, from a clean `xcodebuild test` run. All small.

- **`Hourss/Store/HealthService.swift:217`** — *"initialization of immutable value
  'anythingReal' was never used"*. It is a dead local, and the same expression is
  recomputed 12 lines later as `gotSomething` (`HealthService.swift:229`), which is
  the one that does the work. Delete the first.
- **`Hourss/Store/AppleIDAuthorizer.swift:105`** — `init()` deprecated in iOS 26.0;
  use `init(windowScene:)`. Presentation anchor for the Apple sign-in sheet, so
  worth fixing before it stops working rather than after.
- **`HourssTests/CohortTests.swift:94`** — `try` on a non-throwing expression.
- **`HourssTests/SlotTests.swift:285`** — redundant `#require`.

### `HealthDigest.scale`'s figure has a no-op ternary

*Small fix.* `HealthDigest.swift:350-352`:

```swift
figure: total >= 1000
    ? total.formatted(.number.precision(.fractionLength(0)))
    : total.formatted(.number.precision(.fractionLength(0))),
```

Both branches are identical, so the condition does nothing. Either the intent was
a grouping separator above 1000 (`.number.grouping(.automatic)` vs `.never`) — in
which case `totalPhrase` already does that for steps and kcal via
`rounded.formatted()`, `HealthDigest.swift:430-431` — or the branch is vestigial.
Whichever, it currently reads as a deliberate distinction that is not being made.

### `InsightFeedback` is dead

*Small fix.* `Hourss/Model/Enums.swift:275` declares
`enum InsightFeedback: String, Codable { case resonated, notMe, hide,
experimentStarted, experimentCompleted }`. No case is referenced anywhere in the
app, the tests, or the widgets, and `Record` (`RecordStore.swift:13-40`) has no
field that could persist it. Insight state is carried by `InsightStatus` instead.
Delete it, or note what it is reserved for — a `Codable` type with no writer is a
migration hazard the moment somebody starts writing it.

### `HealthGroup.benefit` is written and never shown

*Small fix.* `Hourss/Store/HealthMetric.swift:244` — *"What consenting to this
group buys you"*, one sentence per group ("How mornings go after a longer night").
Both consent surfaces show `group.title` plus `group.scopeDescription` instead:
`Hourss/Features/Onboarding/OnboardingFlow.swift:291-293` and
`Hourss/Features/You/YouView.swift:516-517`. This is shipped copy that has never
been seen by a user. It is also good copy — it may be that the onboarding beat
should show it and does not.

### `Physiology.Reading.exceedsUncertainty` has no callers

Not dead so much as waiting. `Hourss/Store/Physiology.swift:443` is the gate that
decides whether a residual may be shown at all, and nothing shows a residual per
session yet — see *Move 2* above, which is the thing that would call it. Left
here so it is not deleted as dead code by somebody tidying.

### `Space.xxl` and `Space.xxxl` are unused

*Small.* `Hourss/DesignSystem/Spacing.swift:11-12` — 96 and 150. Ported from the
web design system's spacing block and never reached on a phone. Harmless, but a
scale with unused steps in it invites somebody to use one because it exists.

### Stale doc comments

All *small*, all actively misleading.

- **`Hourss/Features/Logging/ReflectionView.swift:5`** — *"Feeling saves the moment
  it is tapped"*. It does not; there is no `onChange` in the view and `commit()` is
  the only writer. Directly contradicted by the comment at `:102-109` in the same
  file. This one matters because the deferred-save risk above turns on exactly
  this behaviour.
- **`Hourss/DesignSystem/HourssFont.swift:92`** — *"The large `/100` numeral in an
  energy reading"*, on a token no energy reading uses. Covered above.
- **`Hourss/DesignSystem/Components/DayHours.swift:185-187`** — *"the target is
  padded out to the full tap height"*. The band is 30pt and nothing pads to
  `Space.tapTarget`'s 44. Covered above.
- **`Hourss/Features/Today/AllFactsView.swift:35`** — *"four generators against
  eleven metrics"*. Eleven metrics exist, but `heartRate` never yields a daily
  value (`HealthService.swift:246-250`), so the pool is four generators against
  ten, and `scale` only fires for seven of those. The ceiling is 37, not 44.
- **`Hourss/Store/HealthDigest.swift:412-414`** — two stacked doc first-sentences
  on `lowerDirection`, the first one superseded by the second and left behind.
- **`Hourss/Store/HealthService.swift:219-226`** — *"The simulator branch survived
  that fix and is going the same way"*. Present tense about work that is finished;
  there is no simulator branch in `refresh()` any more.

There are exactly three `file:line` cross-references in the app source
(`ReflectionView.swift:92`, `DayDeviation.swift:89` and `:173`). Two are accurate.
The third — **`ReflectionView.swift:92`**, pointing at `RootView.swift:92` for the
sheet binding this view's whole save ordering depends on — is off by seven lines;
the binding is at `RootView.swift:99-101`. Worth either fixing or dropping the
line numbers and naming the symbol instead, since a reference that drifts is worse
than no reference: the reader lands on unrelated code and concludes the comment is
describing something they have not found yet.

### `README.md` does not mention either shipped feature

The "What's here" table (`README.md:49-59`) lists Today as *"Empty, active
session, day record"*. It does not mention the daily fact row, the all-facts
screen, or the post-rating card, and a grep of `README.md` for "fact" finds only
two unrelated uses of "card". `DESIGN.md` covers the *visual* decisions properly;
nothing covers what the features are or what they are gated on. The reader most
harmed is the one the README's own "Notes for whoever picks this up" section is
addressed to.

### Two `rebuildInsights()` per Health read

`applyHealthRead` (`Hourss/Store/HealthImport.swift:164-171`) calls
`applyHealthContext` and then `applyPhysiology(feed:)`, and each ends in
`rebuildInsights()` (`HourssStore.swift:489`, `:494`). So a launch rebuilds the
whole engine twice from the same record, on the main actor, plus the curve fit
described under *Move 2*. The comment above the function explains — correctly —
why the three applications are one call; it does not address the double rebuild.
A private `apply(context:physiology:)` that sets both and rebuilds once would be a
small change with a real launch-time payoff, and it becomes load-bearing if a
foreground refresh trigger is ever added.

### The UI suites' `dismissDayContextCardIfShown` is duplicated

`HourssUITests/PastSessionTests.swift:192-196` and
`HourssUITests/LiveActivityTests.swift:294-298` are byte-identical, doc comment
included. `HourssUITests/UITestSupport.swift` is where shared helpers live. Worth
folding together at the same time as making it a real assertion, once the fixture
seeds Health.
