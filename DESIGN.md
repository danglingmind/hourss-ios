# Design system decisions

What the visual system does, and why it does it that way. The tokens themselves
live in code — `HourssFont.swift`, `Surface.swift`, `Spacing.swift`,
`Motion.swift`, `HourssColor.swift`, `Radius.swift` — and this records the
decisions those files
cannot state on their own, particularly the ones that reverse an earlier
position.

Read this before changing a mark, a weight, or a colour's job. Several entries
below exist because the obvious change was tried and was wrong.

---

## The standing rules

These have not changed and should not be changed casually.

**Hierarchy comes from lines, not surfaces.** `HRule` does the job a card border
does elsewhere. There are no shadows, and no filled panels except `forest` where a
whole region changes ground (`ActiveSessionPanel`, the Patterns lead insight). The
"no rounded corners" half of this rule has been retired — see *Blocks round now*
below — and nothing else about it moved.

**Filled buttons are banned.** `DirectionalLink` — bold 14pt text plus an
oversized orange arrow — is the only action idiom. The press shift is the entire
affordance. *This remains in force.* A proposal to exempt one primary action per
screen was raised and is not implemented; if it ever is, it belongs here as a
deliberate reversal rather than as a quiet exception.

**A person is only ever measured against their own history.** No population
comparison reaches any string a reader sees, including obliquely — "unusually",
"rare", "unlike most" are forbidden by name. The prior tables in
`HealthDigest.swift` and `Recommendations.swift` rank what to show first and
nothing else.

**Colour never carries meaning alone.** Every bar travels with its score and its
wording; every arc reading has a label and a value beside its swatch.

**Absence is never zero.** An unrated session renders an empty track, not a
middle value. A metric with no reading has no entry, not a nought.

---

## Blocks round now

Zero radius was policy, with a written rationale, for the whole life of the app.
`hourss-ui-system.json` said `radius.default: 0px` — *"the product relies on type
and lines, not rounded panels"* — and the code went further than the token did:
`AppleSignInButton` exists as a UIKit wrapper **specifically** so that Apple's
button could be forced to `cornerRadius = 0`, and both sheets in `RootView` spent a
`presentationCornerRadius(0)` to refuse the one iOS gives for free.

The owner has reversed it. Every block component now takes one token, `Radius.block`
in `Shared/Radius.swift`, currently **14pt**. This is recorded as a decision because
the next person will find the old rationale in three places and has to know it was
retired rather than forgotten.

**What a block is.** A filled or bordered surface that stands on its own ground:
`PrimaryAction`, the tab bar's `+`, the preset chips, the slot stepper's `−`/`+`,
the activity rows (`SelectableChip`), `ProfileView`'s workday cells, Today's
active-session panel, the Patterns lead insight, the sheets' own containers, the
Live Activity's stop control, and Apple's sign-in button.

**What a block is not.** Lines, rules, bars and data marks. `HRule`, `DayHours`'
hour cells, `ComparisonArc`, `ComparisonMark`, `DataBar`, `CoverageMark`,
`HeatCalendar`'s cells, `EditorialSlider`'s track and the tab bar's travelling rule
are all type-and-line elements and all stay square. A 2pt bar with rounded ends is a
capsule, which the token file banned for reasons that have nothing to do with
radius and which still hold.

**One token, and no second one.** The point of the request was that one number be
tunable. A `Radius.card` beside `Radius.block` would put the number back in two
places, so there isn't one, and no view writes a radius of its own —
`blockSurface(_:)` is the only way a block gets its corners. The sweep in
`README.md` enforces that by hand.

**The two that were left square have been given gaps, and now take the token.**
`SelectableChip` (the activity picker and the onboarding intents) and
`ProfileView`'s workday cells were the exception for one sprint: filled and
tappable, but flush against their neighbours inside a ruled strip, where
`Radius.block` notches every seam and runs an `HRule` across four corners. The
exception named its own exit — *if either is ever given gaps, it stops being a
list* — and the owner, having seen the rest of the radius change on device, asked
for it. So the layout changed first and the radius followed: both stack at
`Space.xs` now, the rules between the rows are gone, and the fill comes from
`blockSurface` like every other block.

Two things that came with it, neither of them optional. **An unselected row has to
be drawn.** On a flush ruled list the rules gave an unselected row its only visible
edge, because its fill was `Color.clear`; with the rules gone that is a radius on a
shape nobody draws and a gap with nothing either side of it. Both now paint
`surface.track` when unselected — the value `RatingScale` already used for an
unselected segment. **And the rules were not replaced.** A filled rounded block with
space around it is separated from its neighbour; a 1pt line between two of them is a
second separator doing one job twice, which is the mistake *One rule weight* below
is about. The leading rule under each list's eyebrow went too: it was the top edge
of a strip that no longer exists.

Ruled unfilled lists are untouched and still correct — Today's quick-start rows are
text and an arrow with a rule under each, never a fill, so they are a list and not a
set of blocks.

**Circular corners, not `.continuous`.** `AppleSignInButton` can only offer
`CALayer.cornerRadius`, which is circular, and it sits directly beside a
`PrimaryAction` on the sign-in screen. Matching the two is worth more than the
marginally smoother curve.

**Still no shadows.** Only radius moved.

---

## Orange is a signal now, not decoration

Orange (`#E65837`) used to appear only on the wordmark dot and arrow glyphs — 7
to 18pt, never filling anything, never marking state. The app had a high-chroma
accent and nothing for it to mean.

It now marks **the thing you are looking at**, and only that:

- the selected row's rule in `DayTimeline`'s gutter
- the current time on `DayHours` — line and label
- the selected tab's underline in `EditorialTabBar`

Everything else it does is still navigational (arrows, the back chevron). Do not
spend it on a third job.

The tab underline is that same one job at the largest scale the app has for it —
the screen you are on is the thing you are looking at — which is why it is an
application of this rule and not an exception to it. A different accent for
navigation chrome would have been the exception.

**One collision to know about.** `Color.orange` is `#E65837` and
`Color.drainingFill` is `#E66645` — near enough the same hue that a draining
session and the now-line read as one colour at a glance. They are told apart by
*shape*: the now-line stands 4pt proud of the band at top and bottom, so it is a
line laid across the day rather than another block logged in it. Any future use
of orange over a fill needs its own non-colour distinction.

---

## One rule weight, and why a second was tried

`HRule` at 1pt is the only rule in the system. It separates a heading from what
it heads and one list row from the next, at the same weight, which does mean a
screen offers the eye nothing to rank.

A 2pt ink `SectionRule` was built to fix exactly that and applied at nine places
— heading | fact, fact | day, claim | evidence — then removed after being looked
at on a device. It worked: the breaks became findable. It also made the screens
look *ruled*, which is a worse thing to be than flat. The flatness is a real
cost and this was not the way to pay it; if it is revisited, the lever is
probably space rather than more lines.

---

## Readouts name their subject first

**`TitledFigure`** — title 34pt (`.dayNumeral`) → figure 26pt (`.stepName`,
muted) → detail 16pt (`.body`, muted).

This reverses what `HealthFactRow` used to argue, and the old reasoning is worth
keeping because it is the thing being overruled:

> The figure carries the fact and the sentence explains it, so the figure is set
> at display size and the sentence is muted underneath — the reverse of a
> dashboard, where the number is a label on a chart.

Every clause of that is right about a chart and wrong about a card. A chart
arrives with axes, a legend and a title standing around its number, so the number
really is the only part not already on screen. A card has nothing but what is
printed on it. Leading with "12%" put the one element that cannot be understood
alone in the position the eye lands on first, and made the subject cost a full
sentence to recover — every time, on a screen people open daily.

The figure was not demoted below the prose. It is still larger than the sentence
and still carries the fact. It has only stopped arriving before the thing it
measures.

**Titles are never authored at the call site.** They come from
`HealthMetric.title` ("Time asleep", "Heart rate variability", "Steps") — the
same strings the consent list shows, which have already been through the phrasing
rules. Nothing is appended: not the fact's `kind`, not the direction, not a
qualifier. A name is not a claim; anything joined to it might be.

**Where this was deliberately *not* applied.** These already name their subject
adequately, and converting them would be churn or worse:

| Surface | Why it was left alone |
|---|---|
| `InsightDetailView` | An `Eyebrow` names the metric and window directly above the content |
| `PatternsView` coverage rows | Title leads at 16pt, figure trails at 11pt — compact rows, and three 34pt titles would out-shout the block's own headline |
| `DayDetailView` header | Converting it would shrink a *date* to 26pt, treating an identity as a figure |
| `RatingScale` | `kind.title` at 23pt already sits above the numerals |
| Observation slot's `"N of 12 days with a rating"` | Prose at the same size as every other slot lead line, with `Eyebrow("Evidence so far")` above it. Also pinned verbatim by `SlotTests.swift` and inside a band whose rule is "one thing, never a feed" — changing it requires relaxing that test first, which is a BR-28 copy decision |

An eyebrow immediately above a figure is sufficient. Reach for `TitledFigure`
where the number dominates its own label, not everywhere a number appears.

---

## Comparisons are arcs

**`ComparisonArc`** replaced two stacked horizontal bars wherever two values are
compared — `HealthFactRow`, `InsightDetailView`, the onboarding proof beat.

Stacked bars are the most literal way to draw a comparison and the easiest to
ignore: they sit at the same weight as the body text around them and read as
punctuation rather than as the finding. An arc is the one mark that owns vertical
space, and the comparison *is* the fact.

**Concentric, not one track split in two.** A split track says the two values are
shares of something. They are not — "weekends" and "weekdays" are two independent
means of the same measurement, and slicing one arc would assert a part-to-whole
relationship the data does not carry.

**Why different radii do not distort it.** A reader compares these by angular
extent, not drawn length. The same fraction subtends the same angle at any
radius, so the inner ring is not penalised for being the shorter curve.

**No figure in the well.** Every surface drawing this already states its headline
number immediately above. A number in the middle would be that number twice, and
a derived "difference" would be new user-facing copy saying what the two readings
below already say.

**Round caps are a deliberate exception** among the data marks, which are square
everywhere — every `DataBar` is a `Rectangle`. A butt cap on a curve reads as a
slice cut out of a disc; a round one reads as a measurement that stopped where it
stopped. It is no longer the only rounded geometry in the app — blocks round on
`Radius.block` now — but it is still the only rounded *mark*, and the caps are not
on the token: they are a stroke property of a curve, not a corner of a block.

Three or more values fall back to the stacked bars. Concentric rings stop being
legible around there, and a comparison of many things is a list, not a meter.

---

## The day has a shape

**`DayHours`** — 24 cells, one per hour, above the session list on both Today and
the Journal day screen. It lives inside `DayTimeline` so the two screens cannot
drift apart.

It is not `SegmentStrip`. That mark packs sessions end to end in proportion to
their length, which makes a shape of the day but carries no clock position: three
hours logged at 09:00 and three at 21:00 draw identically. Here position *is* the
information, the axis is fixed midnight to midnight, and the gaps are real.

**Hours, not a continuous scale.** At phone width a day is about 340pt, so a
25-minute session on a continuous scale is six points wide and reads as a speck.
Rounding to the hour keeps the shortest thing anybody logs visible, and "which
hour" is the resolution the question is asked at.

**One continuous band with hairline hour ticks**, not 24 separated cells.
Consecutive logged hours should read as one block of time rather than a row of
tallies. The ticks are ink at 14% — a canvas-coloured tick would read as the band
being cut up again, which is what the continuous band was for.

**Three fill states, and they must stay three.**

| State | Fill |
|---|---|
| Nothing logged | `surface.track` |
| Logged, never rated | `surface.ruleColor` |
| Logged and rated | `Feeling.fillColor` |

An hour that was logged but never rated must not fall back to the empty track the
way a `DataBar` does. That would make "I did something and said nothing about it"
and "I did nothing" the same mark — the one distinction the strip exists to draw.

**Anything logged beats sleep read from a watch**, however little of the hour it
took. A night covers seven or eight hours of most days, so ranking purely by
overlap buried every early-morning session under it. A half-hour of work at six
in the morning is the most interesting thing the strip can say, and it was the
one thing it hid. Sleep is the ground the day sits on rather than a thing done in
it — the same reason nothing else in the app asks how a night felt.

**Sessions are clamped to their day.** A night imported from Health is filed
under the morning it ended on, so it genuinely begins before the day did. An
unclamped span claims hours belonging to yesterday.

---

## Selection has to be findable

`DayTimeline` selection was 0.53 opacity on unselected rows and a 4pt shift on the
selected one, per the original spec. Both were too quiet: on a day holding two
rows there is nothing for the dimming to be read against, and the shift moved the
list on every tap without ever saying which row had won.

Now: an **orange rule in the gutter**, full-strength times on the selected row,
everything unselected at **0.42**. The shift is gone — two devices moving at once
made the list twitch.

The reading below still names the session it belongs to, so colour is not the only
carrier.

---

## Rows show both ends of a session

A single time said when something started and left "for how long" to be inferred
from a bar, which is the one question a record of your hours should never make you
estimate.

Start and end are **stacked** rather than set as "9:00 – 10:30" on one line: a
twelve-hour locale spends about a third of the row on that string and takes it
from the activity's name. The end time is dropped when both land in the same
minute — a session stopped seconds after it began printing its own clock twice
looks like a fault in the row rather than a very short session.

---

## Motion

Everything routes through `Motion.animation(reduced:)`. Reduce Motion lands on the
finished state directly; it never gets a shortened version.

`RevealOnAppear` is a left-to-right rectangular mask — the gesture a bar makes.
**It is wrong for an arc**, where it drags a straight edge across a curve, so
`ComparisonArc` animates its own trim and `HealthFactRow` opts comparison marks
out of the shared modifier. Any future non-linear mark needs the same treatment.

---

## The selected tab is a rule that travels

Selection in `EditorialTabBar` was a text colour swap and nothing else — ink on
the selected label, muted on the other three. At eyebrow size that is a few dozen
pixels of contrast difference at the bottom of the screen, and it failed the same
way `DayTimeline`'s opacity failed: with nothing beside it to compare against, a
muted label just looks like a label. Which tab you were on was recoverable by
reading all four and deciding which was darkest.

Now an **orange rule, 2pt, on the bottom edge of the 54pt row**, the width of the
slot it marks. Not a fixed width: the four tabs divide whatever is left after the
`+` takes its 60pt, so the mark is derived from the bar's own geometry and stays
matched to the tab if the bar's width ever changes.

**2pt, and not 3.** `DayTimeline`'s gutter mark is 3pt, but it is vertical and
about 40pt long. The same weight run across ~79pt of tab stops being a rule and
becomes a bar — and this sits 1pt away from the `.rule` hairline that closes the
content area, so the two weights have to stay legible as different things.

**The text distinction stays.** Ink-vs-muted is still there under the rule. The
standing rule that colour never carries meaning alone is not suspended because
the colour got bigger.

### It slides, and that needed a spring

`Motion` held only ease-out at 160/200ms, and neither works here. Those tokens
are for a thing that appears, recolours, or shifts by a few points — a curve that
leaves at full speed and decays is right when the eye has nothing to track. This
is one object crossing up to 140pt with the eye following it, and an ease-out
spends its last third slowing to a crawl, which reads as the line being dragged
into place rather than thrown there.

So `Motion.travel(reduced:)` — `.spring(response: 0.32, dampingFraction: 0.80)`,
tuned against the system tab bar's own transition, which is a spring and not an
ease. `.snappy` (0.3 / 0.85) was the other candidate and is nearly the same
animation; 0.80 damping was picked over it for the ~1.5% of overshoot, one or two
points at this distance, which makes the line settle rather than stop dead.
**It is a token, not a call-site spring**, for the reason the whole file exists:
the next thing that travels should feel like this one without anyone having to go
and read this component.

Reduce Motion gets `nil`, as everything else does — the line is simply already
under the new tab. Never a shortened spring.

The label crossfade still uses the ease-out `fast` token. A colour change is not
a journey and does not want a spring.

### Crossing the `+`

Patterns to Journal takes the rule straight through the middle, where there is a
lime 60pt block that is not a tab and must never look underlined.

**It passes below it, continuously.** The geometry allows this outright rather
than by luck: the lime block is 38pt tall inside a 44pt button inside a 54pt
row, so its lower edge is 8pt above the row's, and the rule occupies the bottom
2pt. The two never share a pixel — the line is not behind the `+` or through it,
it is under the whole row, on its way past.

Rejected, and why:

- **Skipping the middle** — the rule jumping the 60pt gap — puts a discontinuity
  in the one motion whose entire job is to be followed by the eye.
- **Fading or contracting while crossing** removes the mark at exactly the moment
  the reader is hunting for where it went, and buys nothing: a rule in flight is
  read as in flight, not as underlining whatever it is momentarily over.

What makes both unnecessary is that nothing ever comes to rest in the middle. The
`+` opens a sheet; it is never a selection, so there is no state in which the rule
sits under it. The elegant handling of the middle case turned out to be to let the
layout be honest about the fact that the `+` is not on the same row of the
hierarchy as the tabs, and put the mark in a band the `+` does not reach.

## A finished test is the loudest thing on Today, and a failed one just as loud

Experiments added three states to the observation slot, and the ordering was the
only real decision: a settled result sits above everything, including the
unfinished-reflection ask that outranks the upgrade prompt. It earns that by
being the one thing in the app somebody worked two weeks for, and by claiming
the slot exactly once — acknowledging it is what gives it up.

The rating ask is not displaced by any of them. It is carried stacked beneath,
which is the rule a recommendation already set and which the active card has the
strongest claim to: the rating being asked for is the measurement that fortnight
is made of, so the two belong on screen together rather than competing.

**"It did not hold up" is set at exactly the weight of "It held up"** — same
eyebrow position, same lead emphasis, same caveat. There is a test pinning it.
An app whose tests always succeed is not running tests, and the first step to
not reporting a null result is reporting it quietly.

**The countdown ban survived an argument for lifting it.** The slot's copy sweep
forbids "days left", "days to go" and "until", because `evidenceProgress` must
never forecast. A fortnight somebody chose is not a forecast, so the ban could
have been scoped away for the active card. It was kept: a deadline reads as a
deadline whichever state shows it, and a deadline is the shape that turns a
count into something to defend. The card says "four more days of this
fortnight", and adherence is a count that is never framed as a thing to protect
— the same argument `RecordFacts` makes about streaks.

**Nothing new was invented to carry any of it.** No colour, badge, border,
second rule weight or type size. Whether a settled card should get *more room*
than the others — the lever the "One rule weight" section above nominated — is
deliberately still open, because two visual changes have been reverted whole and
the right moment to decide is after looking at the cards rather than before.

---

## A record of tests is a ruled list, not a column of cards

The settled result on Today is a forest block, and the section above argues why: it
is the rarest thing the app can show, it appears exactly once, and acknowledging it
is what gives the slot up. That last clause is what made a second surface necessary
— `ExperimentHistoryView`, on You — and the first thing to decide about it was
whether the cards came with it. They did not.

**Three forest blocks in a column is the house style with extra steps.** The
argument is already written down twice, in `ObservationSlotView.isCarded` and in
*Blocks round now*: a palette where four things are emphasised differently is a
palette where nothing is, and a card that is emphatic every other week is just how
the app looks. A list of settled results is by definition not rare. Worse, an
identical fill behind three different verdicts invites the fill to be read as a
status colour it is not — and the moment a reader starts scanning for the green
ones, the record has become a scoreboard. So the rows are the house ruled-list
idiom: `Eyebrow`, `HRule`, the existing type ramp, and nothing else.

**Space is the lever, which is what the "One rule weight" section nominated.** Each
record takes `Space.md` of vertical room inside its row and the rules between them
stay at 1pt. No second rule weight, no new colour, no badge, no new type size —
`roomAbove` on Today already pays the flatness cost this way and this is the same
payment on a list. The open question that section leaves about Today's card is
untouched; this closes it only for the list.

**The subject is on the top step and the verdict on the second, which inverts
Today.** The card is right to lead with the verdict: there is one of them, the
person knows which fortnight they agreed to, and the answer is the only news. A
list is not in that position. A column that opens every row with IT HELD UP / IT
DID NOT HOLD UP is a column of verdicts to be compared with each other, however
carefully each is worded, so the row leads with the change that was tested and
attaches the outcome to it. This is the same correction `EvidenceReadout` made on
Patterns, where the line named its subject four words after its figure.

**The three verdicts are drawn by one function with no branch in it.** Same eyebrow
position, same ramp, same room, same order; the only difference between a result
that held up and one that did not is the sentence. The per-experiment caveat is the
one thing that could not be kept per row — Today carries it and drops it for
`cannotTell`, correctly, because there is nothing to qualify about a window that
could not be read, and that asymmetry would draw two of the three verdicts a line
taller than the third. So the rows carry the same four things each and the limit
common to all of them sits under the list, where Patterns already puts
"Observations, not rules".

**Stopped experiments are in the list.** They carry no verdict and there is
genuinely nothing to report about the change, which is a good argument for leaving
them out. It loses to a simpler one: a record that silently drops the parts
somebody stopped is a selection they cannot see being made, and the person who
started three tests and finished one would find a history in which they only ever
started one. What keeps a stopped row from reading as a fourth verdict is that it
says in plain words that it has no result — and that nothing anywhere counts any of
this.

**Nothing is counted, and the screen's own copy is swept for it.** No rate, no
streak, no "two of three held up". `abandonExperiment` keeps no tally because a
number whose only use is a reproach does not get computed, and a list that totals
its own verdicts is that number assembled by the reader instead. The test suite
asserts that every string this screen authors quotes no figure at all.
