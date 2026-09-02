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
| Onboarding | Welcome, What Hourss notices, Intent, Activities, First log |
| Today | Empty, active session, day record |
| Logging | Start a session, log past time, end reflection |
| Patterns | Warming up, ranked list, insight detail |
| Journal | Archive with filters, day detail |
| You | Profile, preferences, privacy & data |

**Not built:** Health permission, notifications, account, membership, and profile
editing. Each needs a real integration, and a mocked permission screen would
teach the wrong thing — the spec requires consent to precede the system prompt.
They appear in `You` as visibly disabled rows so the scope reads as deliberate.

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

It should return nothing.

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
