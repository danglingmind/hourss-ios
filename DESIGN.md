# Design system decisions

What the visual system does, and why it does it that way. The tokens themselves
live in code — `HourssFont.swift`, `Surface.swift`, `Spacing.swift`,
`Motion.swift`, `HourssColor.swift` — and this records the decisions those files
cannot state on their own, particularly the ones that reverse an earlier
position.

Read this before changing a mark, a weight, or a colour's job. Several entries
below exist because the obvious change was tried and was wrong.

---

## The standing rules

These have not changed and should not be changed casually.

**Hierarchy comes from lines, not surfaces.** `HRule` does the job a card border
does elsewhere. There are no rounded corners, no shadows, and no filled panels
except `forest` where a whole region changes ground (`ActiveSessionPanel`, the
`DayContextCard`).

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

**Round caps are a deliberate exception** in a system that is otherwise square
everywhere — every `DataBar` is a `Rectangle`. A butt cap on a curve reads as a
slice cut out of a disc; a round one reads as a measurement that stopped where it
stopped. This is the only rounded geometry in the app.

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
lime 60pt square that is not a tab and must never look underlined.

**It passes below it, continuously.** The geometry allows this outright rather
than by luck: the lime square is 38pt tall inside a 44pt button inside a 54pt
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
