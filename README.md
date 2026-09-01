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

Patterns is worth opening — the observations there are *computed* from the seeded
sessions, so the "4.6 vs 3.2 · 17 vs 11 sessions" evidence line and the session
list on the detail screen always agree with each other.

## What's here

| Area | Screens |
|---|---|
| Onboarding | Welcome, What Hourss notices, Intent, Activities, First log |
| Today | Empty, active session, day record |
| Logging | Start session, end reflection |
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
grep -rn "cornerRadius\|RoundedRectangle\|Capsule()\|\.shadow(\|Image(systemName" Hourss/
```

It should return nothing.

**Display type needs negative leading.** `display` is line-height 0.91 and
SwiftUI's `lineSpacing` clamps at zero, so headlines are authored as pre-broken
lines and stacked in a `VStack` with negative spacing (`DisplayHeadline`). Adding
a headline means supplying its line breaks.

**Edge-swipe back needs help.** Every detail screen draws its own header, so it
sets `navigationBarBackButtonHidden(true)` — and UIKit switches off the
interactive pop gesture whenever the back button is hidden. `SwipeBackEnabler`
(`Navigation/SwipeBack.swift`) puts it back, with a delegate that declines at the
root of a stack so the gesture cannot fire with nothing to pop. Apply
`.enablesSwipeBack()` at the root of any new `NavigationStack`.

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
`.enablesSwipeBack()` is ever dropped.

`Screenshots/` holds the most recent run's captures.
