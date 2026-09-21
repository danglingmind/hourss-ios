# Hourss — iOS shell

A working demo build of the Hourss iPhone app: real navigation, real state, and
six weeks of seeded history, with no backend behind it. Built to be shown to
people before Clerk, Supabase, StoreKit or HealthKit exist.

## Running it

```bash
xcodebuild -project Hourss.xcodeproj -scheme Hourss \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or open `Hourss.xcodeproj` in Xcode and hit run. Requires Xcode 26 / iOS 26 SDK;
deployment target is iOS 26.0 and the app is iPhone-only, portrait, light mode —
the design system defines a single warm-paper palette with no dark variant.

### On a device

Automatic signing is configured against team `NJ5P2B5WZJ`. Select your iPhone and
run, or from the command line:

```bash
xcodebuild -project Hourss.xcodeproj -scheme Hourss \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> \
  build/Build/Products/Debug-iphoneos/Hourss.app
```

To hand it to someone on a different team, change `DEVELOPMENT_TEAM` in the
project's four build configurations and pick a bundle identifier they own —
`com.hourss.app` is registered to this team.

## The demo path

Onboarding → Today → tap **+** → pick an activity → **Start** → the timer runs →
**Stop and reflect** → rate it → the session lands on Today's timeline and again
in Journal. That loop is real: one `@Observable` store backs every screen.

The **+** sheet also has a **Log past time** mode for the hour you were too busy
to log while it was happening — two flat sliders set the slot, defaulting to the
hour just gone. It saves as already finished and asks for the reflection straight
away.

Patterns is worth opening — the observations there are *computed* from the seeded
sessions, so the "4.6 vs 3.2 · 17 vs 11 sessions" evidence line and the session
list on the detail screen always agree with each other.

## What's here

| Area | Screens |
|---|---|
| Onboarding | Welcome, Health ask, Priorities, Intent, Mechanism, Proof, Account, Reminders, First log |
| Today | Empty, active session, day record |
| Logging | Start a session, log past time, end reflection |
| Patterns | Warming up, ranked list, insight detail |
| Journal | Archive with filters, day detail |
| You | Settings list, profile, account, preferences, privacy & data |

**Not built:** membership purchasing. Each needs a real
integration, and a mocked permission screen would teach the wrong thing — the spec
requires consent to precede the system prompt. Membership appears in `You` as real
state with no control behind it, because the only honest control is a purchase.

## Signing in

Sign in with Apple, and nothing else. There is no backend and no session: Apple
returns a stable per-team user identifier, Hourss keeps it in the Keychain, and
`AccountService` asks Apple on every launch whether it is still good — so revoking
Hourss under Settings ▸ Apple ID signs you out here too, in the app and while it
is open.

It is a hard gate. The beat sits after the proof screen rather than before it, so
the ask arrives on the back of three true statements about the person's own
history rather than in front of an app nobody has seen. **Note for submission:**
with everything on-device, a reviewer may reasonably ask what the account is for
under guideline 5.1.1(v), which forbids requiring an account for features that
don't need one. Deletion is in place — `Privacy & data ▸ Delete everything` clears
the record and the Keychain item, which is what 5.1.1(v) requires of anything
offering sign-in.

Two things the capability needs outside this repo: the **Sign in with Apple**
capability must be enabled for `com.hourss.app` in the developer portal (the
entitlement is already in `Hourss/Hourss.entitlements`), and the simulator or
device must be signed in to an Apple ID or the sheet returns `.unknown`.

UI tests cannot drive the Apple sheet — it is another process wanting a real Apple
ID — so `-hourss-debug-account <name>` starts the app already past the gate. It is
`#if DEBUG` and read straight from `ProcessInfo`, so no shipped build contains a
path that arrives signed in without Apple.

## Log reminders

Onboarding's eighth beat asks how often Hourss should ask what you are doing:
hourly, every two hours (the recommendation), every three, twice a day, or not at
all. Tapping the notification opens the activity list — the same sheet the `+`
button opens.

No server, and no background execution. The mechanism is one **repeating calendar
alarm per hour of the day**, registered with iOS and then forgotten about: eight
requests for the two-hour setting, fifteen for hourly, against an iOS cap of 64.
They fire whether Hourss has been opened in a week or not, which is the whole
requirement.

`UNTimeIntervalNotificationTrigger(repeats: true)` at 7200 seconds was the obvious
alternative and is rejected for one reason: it has no idea what the time is. It
would fire at 3am every night forever, with no way to bound it. A calendar trigger
is bounded by construction, because each one *is* a time of day. Hour and minute
only — pinning a date would send an 8am reminder at 3am the moment someone flew
anywhere.

Details worth knowing before changing any of it:

- **Nothing is ever scheduled outside 8am–10pm**, and there is a test that walks
  every frequency asserting it. A 3am notification is not a reminder, it is a
  reason to turn the app off in Settings — which Hourss cannot undo and will never
  be asked about again.
- **Each row states its own cost** ("15 a day", "8 a day"), and a test asserts
  those numbers against the actual schedule, because the copy lives a long way
  from `LogReminderFrequency.hours`.
- **Quiet mode really silences them.** It is applied inside
  `LogReminders.hours(for:)`, the one function every scheduling path goes through.
- **Choosing "Don't remind me" never raises the system prompt.** Asking permission
  to send nothing is the most irritating thing an app can do.
- **A refusal schedules nothing.** Pending requests that can never fire would make
  Preferences claim reminders are on when iOS has them off — so that screen reports
  the system's answer, not ours.
- **Dismissing a notification does not open the sheet.** Only
  `UNNotificationDefaultActionIdentifier` counts; a dismissal is a decision not to
  log.
- The delegate is registered in `HourssApp.init()`, not in a view's `task`. A tap
  that launches the app cold is delivered to whatever delegate exists at launch,
  and the case this feature exists for is precisely "the app was not open".
- UI tests pass `-hourss-debug-no-notifications`, which swaps in
  `SilentLogReminderScheduler`. The system permission prompt is another process and
  XCTest cannot dismiss it without an interruption monitor, so without this the
  reminders beat stops every walk dead.

`Profile.logPrompts` is gone — it was a toggle labelled "Max 3 a week" wired to
nothing. It is replaced by `logReminder`, which is **optional**: nil means "never
chose", so nobody is opted into notifications they were never offered.

## What Health writes to the record

Two of the eight starter activities are things a watch already records precisely,
so Hourss reads them rather than asking anyone to retype them: **workouts become
Exercise sessions** and **each night becomes one Personal / Rest session**. They
carry `source: .health`, are labelled "Health" wherever they appear, and back-fill
six weeks — enough that the Journal has something in it on day one.

The rules that matter, all in `Store/HealthImport.swift` and tested without a
device:

- **A night is filed under the morning it ended on.** Health records stages, not
  nights, so samples within 45 minutes of each other are merged into one block and
  only the longest block of a day survives. That day is also the block's identity
  (`health.sleep.2026-03-11`), because a block's own start moves whenever Health
  backfills another stage sample — and an identifier that moves is one that
  duplicates.
- **Importing is idempotent.** It runs on every launch. A block already on the
  record is updated in place, never added again.
- **Nothing imported competes with a hand-logged session.** A workout overlapping
  one somebody logged themselves is skipped — theirs has an intention and a rating
  on it.
- **Deleted stays deleted.** `Record.removedImports` remembers what was thrown
  away, so the next launch does not put it back.
- **Imported sleep is not pattern evidence.** Every night is already in the engine
  as daily context via `HealthMetric.sleepHours`; admitting it a second time as a
  session would let one night corroborate itself. Imported workouts *are* eligible,
  and are the only imported thing the reflection prompt ever asks about.

`applyHealthRead(from:to:)` is the single call that applies a read — daily context,
physiology and the import together. Use it rather than calling the three by hand;
`applyPhysiology` previously sat built and uncalled because two of the three
screens that connect Health remembered only the other one.

## Layout

```
Hourss/
├── DesignSystem/     colors, type, spacing, motion + shared components
├── Model/            entities and enums, mirroring the PRD's schema
├── Store/            in-memory store, seeded mock data, insight computation
├── Navigation/       root view and the hand-built tab bar
├── Features/         one folder per destination
└── Resources/Fonts/  DM Sans, DM Mono, Instrument Serif (OFL, licenses included)
```

Sources are picked up through an Xcode file-system-synchronized group, so new
files need no project-file edit.

## Notes for whoever picks this up

**The zero-radius rule is load-bearing.** `hourss-ui-system.json` sets
`radius.default: 0px` — *"the product relies on type and lines, not rounded
panels"* — and defines no shadows at all. That is why the tab bar, sheets and
headers are hand-built rather than `TabView` and `List`: stock iOS 26 chrome is
rounded, translucent and shadowed, and it fights the system on every screen.
There is a conformance sweep in the test suite's spirit worth re-running by hand:

```bash
grep -rn "cornerRadius\|RoundedRectangle\|Capsule()\|\.shadow(\|Image(systemName" Hourss/ Shared/
```

It should return nothing but `Features/Account/AppleSignInButton.swift`, where the
two hits are `cornerRadius = 0` being *set* on Apple's button. That control is the
one exception to drawing everything in the house style — the mark and proportions
are Apple's and may not be redrawn — and the radius is the single property Apple
exposes, which is why the button is wrapped from UIKit rather than taken from
SwiftUI's `SignInWithAppleButton`, which hides it.

**The interaction suite is date-dependent, and it is not flaky.** Which tests in
`InteractionCandidateTests` / `InteractionCorrectionTests` fail depends on what
day you run them: the cohorts are generated relative to `Date()`, so the weekday
alignment of the generated history shifts, and a threshold that cleared yesterday
misses today. It is stable *within* a day — the same run produces the same value
to the last decimal place — which is what makes it look like a real regression.
Two different failures were observed on consecutive days, each reproducing exactly
on a clean checkout of the same commit. Before blaming a change for one of these,
run the same test on a worktree at `HEAD`; if it fails identically, the change is
innocent. Fixing it properly means pinning the generator to a fixed reference date
rather than `Date()`.

**The activity marks are drawn, not borrowed.** `Shared/ActivityGlyph.swift` is
eight paths on a shared 24×24 grid at one stroke weight — a target, two speech
marks, a checklist, an open book, a spark, a dumbbell, two rings, a crescent.
They were previously eight arrangements of rectangles, on the principle that the
system rules out borrowed iconography; they were coherent and unreadable, and an
icon that has to be explained is a label in a worse typeface. The discipline moved
rather than disappeared: nothing here is an SF Symbol or a borrowed asset, which is
also why `Image(systemName` stays in the conformance sweep.

Two rules hold the set together, and both are tested in `ActivityGlyphTests`:

- **`phase: 0` must be the finished mark.** Every list, chip and Lock Screen
  renders the resting pose, so an animation has to depart from a complete icon and
  return to it — never animate *into* completeness. Three of these got this wrong
  first time round (admin drew two of three rows faint, exercise drew its whole
  trace at 28%, meetings left a bubble dimmed), so the icon nearly everybody saw
  was the unfinished one. The test measures opacity rather than ink, because
  `creative` legitimately has more ink mid-animation as its points reach outward —
  what separates the two is that a finished mark's only part-transparent pixels are
  its antialiased edges.
- **`Kind`'s raw values are a stored format.** `LiveSessionController` writes them
  into the Live Activity's attributes and the widget reads them back, so renaming a
  case silently blanks the icon on somebody's Lock Screen for the length of their
  session.

Coordinates are snapped to the device pixel grid before drawing (`GlyphPen.px`). A
3-unit stroke on a 24 grid at 16pt is exactly 2pt, but the *positions* land on
thirds of a point, and a 2pt line straddling a pixel boundary renders as two grey
1pt lines. To look at the set while changing it, render `ActivityGlyph` through
`ImageRenderer` at several sizes — that is how the first cut was caught.

`AnimatedActivityGlyph` drives the phase at 30fps and is used on the running-session
card, where each animation is the activity's own gesture: a ring locking on, a turn
being taken, a page turning over the gutter, a weight dropping. Reduce Motion gets the resting pose,
which is a real icon rather than a degraded one.

**Two marks leave their box.** `Kind.runway` gives extra grid units above the
24×24 square, because `Canvas` clips to its own frame: the weight falls from 26
units up, and the page arcs over the book through 10. Layout still reserves the
plain square — the runway overflows upward and is drawn over the card, which is the
point for the dumbbell: it arrives from outside it.

**The open book opens upward, and that had to be fixed.** It was drawn with the
spine *higher* than the outer edges, so the top made a Λ and the whole thing read
as a book held face down. Both edges dip toward the gutter now, which is the V an
open book actually makes.

Its page turn loops on the same trick as the dumbbell: at either end of a turn the
sheet lies exactly on top of a static leaf, so it is invisible there and the jump
back has nothing to see. Three things make it paper rather than a tween. The turn
is fast off the flick, slows as the sheet stands up, then falls away (`t + k·sin
2πt`) — a page is a pendulum, so the slow part belongs at the top, not at both
ends. Its width is the cosine of the angle, because that is what a rotating sheet
projects. And it bows sideways as it rises, which is the only thing keeping it
visible at vertical, where projection alone would leave it exactly zero pixels
wide.

The hard part was that **a page rotating about the gutter is geometrically
invisible in a flat front view** — its projection lies entirely within the leaf
beneath it, and everything in a glyph is one colour. Two things fix that: the arc
has to break the book's outline (hence the runway), and a hairline is erased along
the sheet's own boundary with `.destinationOut`, letting the background through as
the separation a raised page's edge actually shows. That cut widens with the lift,
so it is absent at the two moments the sheet lies flat and would otherwise outline
a leaf that is not moving.

Its loop is a rep, and that is load-bearing rather than decorative. A drop that
repeats needs the weight back at the top, and every other way of getting it there
either pops or hides behind a fade that reads as a rendering bug. Throwing it up
and letting gravity return it means the reversal happens at the apex, off-canvas,
where there is no seam to see. Both arcs are the same parabola run in opposite
directions — `2u - u²` climbing and slowing, `1 - u²` falling and gathering speed —
so the motion obeys gravity rather than an easing curve. Two things learned the
hard way while building it: the dust must be drawn *after* the weight (drawn first,
the plates fill straight over it and the impact reads as the weight merely
arriving), and it must start clear of the ground line, which is the same colour and
otherwise swallows the burst into lumps on the floor.

**`PastSessionTests` fails between midnight and 1am, and the app is right.**
`StartSessionView`'s window runs back sixteen hours, so the default past slot is
"the last hour ending now". At 00:35 that is 23:35 yesterday to 00:35 today, and a
session is filed by when it started — so it correctly lands on *yesterday* and
never appears on Today, which is what `testLoggingPastTimeLandsInTheRecordWithARating`
asserts. Reproduced at `HEAD` in that window (0 rows before, 0 after) as much as on
any branch. The fix belongs in the test, not the sheet: assert the session exists in
the record rather than on Today, or drive the slot to a time that cannot cross
midnight.

**Display type needs negative leading.** `display` is line-height 0.91 and
SwiftUI's `lineSpacing` clamps at zero, so headlines are authored as pre-broken
lines and stacked in a `VStack` with negative spacing (`DisplayHeadline`). Adding
a headline means supplying its line breaks.

**Backdating is not a second-class path.** Forcing every session through a live
timer quietly biases the record toward the hours calm enough to remember, which is
the opposite of what the product is for. `logPastSession` deliberately does *not*
stop a running session — catching up on an earlier hour should not end what you
are doing now — and it flags overlaps rather than refusing them, because the spec
keeps overlapping hours but leaves them out of pattern computation.

**The slider is hand-built too.** `Slider` has a capsule track and a circular
thumb; `radius.default` is 0, so `EditorialSlider` is rectangles, with the marker
as a 2pt rule rather than a knob and the whole track draggable. It exposes itself
through `accessibilityRepresentation` as a real `Slider` — rebuilding the visuals
should not cost the semantics, or VoiceOver loses swipe-to-adjust.

**Edge-swipe back needs help.** Every detail screen draws its own header, so it
sets `navigationBarBackButtonHidden(true)` — and UIKit switches off the
interactive pop gesture whenever the back button is hidden. `SwipeBackEnabler`
(`Navigation/SwipeBack.swift`) puts it back, with a delegate that declines at the
root of a stack so the gesture cannot fire with nothing to pop. Apply
`.enablesSwipeBack()` at the root of any new `NavigationStack`.

**HRV is in, against the spec.** The PRD says *"defer HRV, mood, and sensitive
health categories"* and the BRD scopes V1 to sleep/workouts/mindful minutes. That
was overridden deliberately: the product's own positioning leads with *"a work log
paired with signals from your body"*, and HRV is the signal people mean. Ten
metrics are read across four consent groups. Mood (`HKStateOfMind`) is still out,
and not only because the PRD defers it — importing Apple's mood log would give the
app a second, competing answer to the question it exists to ask.

**Health context never becomes a health reading.** Every association is against
the person's own median, phrased *"on days when…"*, and carries a caveat. A
business rule forbids inferring a medical, psychological or causal conclusion, so
no metric is ever described as good or bad — only as higher or lower than usual.

**Setting `\.surface` alone is not enough.** `.environment(\.surface, .forest)`
publishes the surface but leaves descendants inheriting the *parent's* foreground,
which put ink on dark green — nearly invisible. Use `.surfaceContent(_:)` (or
`.surface(_:)`, which also paints the background). This failed quietly once and
will again.

**The Island rounds; the app does not.** `radius.default` is 0 everywhere in
Hourss and stays 0 — but the Live Activity's controls sit inside Apple's rounded
container, where a square rectangle reads as a mistake rather than a principle.
The exception is deliberate and ends at the edge of `HourssWidgets/`. The
conformance sweep below is scoped to `Hourss/` for exactly this reason.

**The Island is Apple's surface, not ours.** Its rounded container and placement
are not negotiable, so the rule there is: obey the container, and put nothing
borrowed inside it. `ActivityGlyph` draws each activity from rectangles on a 12×12
grid — the same vocabulary as everything else — so no SF Symbol appears anywhere
in the product. `LiveActivityIntent` runs in the *app's* process, which is what
lets a rating tapped on the lock screen reach the real store.

**`ActivityKit.Activity` needs qualifying.** Hourss has its own `Activity` model
(a thing you can log) and it shadows ActivityKit's inside the app target.

**No picker may ever be empty.** The activity starter set arrives fully selected,
so tapping every row turns them all *off* — and with nothing kept there is no
activity to log against, which takes the whole app out of service, not just one
screen. Onboarding now refuses to advance past the activities step with zero kept,
and `HourssStore.pickableActivities` falls back to the full set if zero is ever
reached another way. Read pickers from `pickableActivities`, not
`favoriteActivities`.

**An unrated session is unknown, not neutral.** `feelingScore` and
`performanceScore` are `Int?` everywhere, the 1–5 scale starts with nothing
selected, and `InsightBuilder` drops unrated sessions rather than counting them as
3. Roughly one seeded session in seven is deliberately unrated so this path stays
exercised.

**Today can legitimately be empty.** The seeded moments sit at fixed clock times
(08:30, 11:45, 15:10, 18:20), so before ~08:30 the day genuinely has nothing in it
and the empty state is the correct screen. Journal is populated at any hour.

**Fonts fail silently.** A wrong PostScript name falls back to the system font
with no error, and the app still looks plausible. `FontAudit` in `HourssApp.swift`
asserts all seven faces registered on launch in debug builds.

## Tests

```bash
xcodebuild -project Hourss.xcodeproj -scheme Hourss \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`DemoWalkthroughTests` drives the whole app and asserts the core loop actually
records what you logged; it also captures a screenshot of every screen as a test
attachment. `AccessibilityTests` checks the layout at accessibility type sizes and
that energy is never carried by colour alone. `SwipeBackTests` drags from the
screen edge on each pushed screen and asserts it pops — these fail if
`.enablesSwipeBack()` is ever dropped. `PastSessionTests` covers the backdating
flow, including that it leaves a running session alone. `ActivitySelectionTests`
guards the no-activities-kept dead end.

`Screenshots/` holds the most recent run's captures.
