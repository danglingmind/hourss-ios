import Foundation

#if DEBUG

/// Generated history, for tests and for looking at the app with something in it.
///
/// This is not the product. Nothing here runs unless a launch argument asks for
/// it, and the whole file is compiled out of any build that is not DEBUG — a
/// shipped binary contains no path that can invent a session, a rating or a
/// health reading. That matters more here than in most apps: every number the
/// engine shows is a claim about somebody's own life, and a claim computed from
/// data the app made up is a lie however carefully it is phrased.
///
/// The `#if DEBUG` wraps the file rather than its call site for the same reason
/// the entitlement override does. Gating the caller leaves the generator
/// compiled in and reachable by anything that can name it.
///
/// Two things still matter about how it generates. It is deterministic, so a
/// failing test can be run again; and the observations it produces are computed
/// from the sessions rather than written by hand, so a claim and its evidence
/// cannot contradict each other.
@MainActor
enum DebugFixture {

    /// The launch argument that asks for it. Absent, the app starts empty, which
    /// is what a real first run looks like.
    static let launchArgument = "-hourss-seed-fixture"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Asks the fixture to land on Today rather than at the first onboarding beat.
    ///
    /// Separate from `launchArgument` on purpose. The fixture deliberately starts at
    /// onboarding, because `DemoWalkthroughTests` walks the whole flow and needs it
    /// there — so setting `hasCompletedOnboarding` inside `seed` would silently gut
    /// the one test that covers the path a real person takes on their first launch.
    ///
    /// This exists for looking at the app: reaching Today otherwise costs a full
    /// walk through seven beats, which is a long time to wait to see whether a card
    /// renders.
    static let skipOnboardingArgument = "-hourss-skip-onboarding"

    static var skipsOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains(skipOnboardingArgument)
    }

    /// Health history and nothing logged — the state somebody is in on their first
    /// morning.
    ///
    /// **Without this, a day-one starter cannot be reached in the simulator at all.**
    /// A starter needs Health, and in a simulator the only Health that exists is the
    /// fixture's — but the fixture also seeds forty-two days of rated sessions, which
    /// produce measured proposals, and a measured proposal always beats a starter.
    /// So the one state the feature was built for was the one state nobody could
    /// look at. That is the same hole seeding Health closed for three other features,
    /// and a card nobody can get to is a card nobody reviews.
    static let dayOneArgument = "-hourss-fixture-day-one"

    static var isDayOne: Bool {
        ProcessInfo.processInfo.arguments.contains(dayOneArgument)
    }

    /// Also seed a window whose days the app drew, settled and running.
    ///
    /// **Behind its own argument, and that is the whole reason it is here.** A
    /// randomised window is four weeks long, so nobody is going to reach one by
    /// running the app — and an active experiment of any kind suppresses the proposal
    /// card, because nothing is offered mid-window. Seeding one unconditionally would
    /// therefore hide the card the fixture exists to let somebody try, and it would
    /// put a second result in front of the one `ExperimentHistoryUITests` acknowledges
    /// on Today. Both are real regressions in a fixture whose only job is to make
    /// things reachable, so this is opt-in: the default fixture is exactly what it was.
    static let randomisedArgument = "-hourss-fixture-randomised"

    static var seedsRandomised: Bool {
        ProcessInfo.processInfo.arguments.contains(randomisedArgument)
    }

    /// Small deterministic PRNG. `SystemRandomNumberGenerator` would make the demo
    /// different on every launch, which is exactly what we don't want.
    struct Seeded: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    /// Stand-in daily values for when HealthKit has nothing — always true on a
    /// simulator. Correlated with the seeded session ratings so the associations
    /// have a real signal to find rather than noise, and deterministic so the demo
    /// is identical every launch.
    static func seededDaily(for metric: HealthMetric) -> [Date: Double] {
        // Seeded from a stable hash of the raw value. `String.hashValue` is
        // randomly seeded per process, so the previous version changed the demo
        // data on every launch while claiming to be deterministic.
        var rng = Seeded(seed: metric.rawValue.unicodeScalars.reduce(UInt64(0x484B)) {
            $0 &* 31 &+ UInt64($1.value)
        })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]

        for dayOffset in 0...HealthService.historyDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let jitter = Double(Int.random(in: -10...10, using: &rng)) / 10

            byDay[day] = switch metric {
            case .sleepHours: (isWeekend ? 8.0 : 7.0) + jitter * 0.6
            case .hrv: (isWeekend ? 58 : 48) + jitter * 6
            case .restingHeartRate: (isWeekend ? 55 : 60) + jitter * 3
            // Only for exhaustiveness. `HealthService` never asks for a daily
            // heart rate; the simulator's per-sample stand-in is
            // `DebugFixture.seededFeed`.
            case .heartRate: (isWeekend ? 68 : 72) + jitter * 4
            case .respiratoryRate: 14.5 + jitter * 0.8
            case .workoutMinutes: isWeekend ? max(0, 45 + jitter * 15) : (Int.random(in: 0...2, using: &rng) == 0 ? 30 + jitter * 10 : 0)
            case .steps: (isWeekend ? 9000 : 6500) + jitter * 1200
            case .activeEnergy: (isWeekend ? 620 : 430) + jitter * 90
            case .exerciseMinutes: max(0, (isWeekend ? 42 : 24) + jitter * 10)
            case .mindfulMinutes: max(0, (Int.random(in: 0...2, using: &rng) == 0 ? 12 + jitter * 4 : 0))
            case .daylightMinutes: max(0, (isWeekend ? 95 : 40) + jitter * 20)
            }
        }
        return byDay
    }

    static func seed(into store: HourssStore) {
        var rng = Seeded(seed: 0x484F5552)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        store.profile.displayName = "Ren"

        // Priorities, because onboarding will not let anybody past without at least
        // one and the fixture was shipping a profile with none.
        //
        // That is not cosmetic. `Recommendations.build`, `ExperimentDesign.proposals`
        // and `ExperimentStarters.starters` all return empty on an unstated
        // priority — deliberately, since none of them will pick an area to work on
        // for somebody who has not named one. So a fixture without priorities makes
        // the recommendation, the proposal and the starter unreachable in the
        // simulator simultaneously, and the slot falls back to the evidence mark as
        // though the engine had found nothing. It looks like a feature that does not
        // work rather than a profile that is missing a field.
        //
        // These three in this order because they are what the planted signal
        // actually supports: deep work reads high in the morning (focus), meetings
        // after three drain (energy), and the weekends are generated differently
        // from the weekdays (balance).
        store.profile.priorities = [.focus, .energy, .balance]

        let byName = Dictionary(uniqueKeysWithValues: store.activities.map { ($0.name, $0.id) })
        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]

        /// The planted signal. Deep work rates high in the morning and noticeably
        /// lower after lunch; meetings after 3pm are the clearest drain. Everything
        /// else is noise so the pattern has to actually rise above a background.
        func rating(activity: String, hour: Int, rng: inout Seeded) -> Int {
            let jitter = Int.random(in: -1...1, using: &rng)
            let base: Int
            switch activity {
            case "Deep work": base = hour < 11 ? 5 : 3
            case "Meetings": base = hour >= 15 ? 2 : 3
            case "Exercise": base = 5
            case "Admin": base = 2
            case "Creative": base = hour < 12 ? 4 : 3
            case "Learning": base = 4
            case "Social": base = 4
            default: base = 4
            }
            return min(5, max(1, base + jitter))
        }

        // Six weeks back, up to and including yesterday.
        for dayOffset in stride(from: 42, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            let isWorkday = store.profile.workdays.contains(weekday)

            // What Health already knew about this day, imported rather than logged.
            //
            // Seeded *before* the sparse-day skip below, and that is the whole
            // point: a day nobody logged anything on is exactly the day the
            // importer exists for, and the Journal should show a night on it
            // rather than a blank. Both land in the 6–8am gap the hand-logged plans
            // leave free, so nothing here overlaps a manual session and quietly
            // drops it out of pattern computation.
            if let restId = byName["Personal / Rest"],
               let wake = cal.date(bySettingHour: 6, minute: Int.random(in: 0...45, using: &rng), second: 0, of: day) {
                let asleep = Int.random(in: 380...500, using: &rng)
                sessions.append(Session(
                    activityId: restId,
                    startAt: wake.addingTimeInterval(TimeInterval(-asleep * 60)),
                    endAt: wake,
                    source: .health,
                    healthKind: .sleep,
                    externalId: "health.sleep.fixture.\(dayOffset)"
                ))
            }

            // Unrated on purpose. An imported workout is the one imported thing the
            // reflection prompt does ask about, so leaving these unanswered is what
            // puts that prompt in a state worth looking at.
            if Int.random(in: 0...5, using: &rng) == 0,
               let exerciseId = byName["Exercise"],
               let start = cal.date(bySettingHour: 7, minute: Int.random(in: 0...15, using: &rng), second: 0, of: day) {
                sessions.append(Session(
                    activityId: exerciseId,
                    startAt: start,
                    endAt: start.addingTimeInterval(TimeInterval(Int.random(in: 25...45, using: &rng) * 60)),
                    source: .health,
                    healthKind: .workout,
                    externalId: "health.workout.fixture.\(dayOffset)"
                ))
            }

            // A few days are deliberately sparse — real logs have gaps, and the
            // Journal reads as a record rather than a generated grid.
            if Int.random(in: 0...9, using: &rng) < 2 { continue }

            var plan: [(String, Int, Int)] = []  // activity, start hour, minutes
            if isWorkday {
                plan.append(("Deep work", Int.random(in: 8...10, using: &rng), [50, 75, 95, 120].randomElement(using: &rng)!))
                plan.append(("Meetings", Int.random(in: 11...16, using: &rng), [30, 45, 60].randomElement(using: &rng)!))
                if Bool.random(using: &rng) {
                    plan.append(("Deep work", Int.random(in: 13...16, using: &rng), [45, 60, 90].randomElement(using: &rng)!))
                }
                if Bool.random(using: &rng) {
                    plan.append(("Admin", Int.random(in: 15...17, using: &rng), [25, 40].randomElement(using: &rng)!))
                }
                if Int.random(in: 0...9, using: &rng) < 4 {
                    plan.append(("Learning", 19, [30, 45].randomElement(using: &rng)!))
                }
            } else {
                if Bool.random(using: &rng) { plan.append(("Exercise", Int.random(in: 8...11, using: &rng), [40, 60].randomElement(using: &rng)!)) }
                if Bool.random(using: &rng) { plan.append(("Creative", Int.random(in: 10...15, using: &rng), [60, 90, 120].randomElement(using: &rng)!)) }
                if Bool.random(using: &rng) { plan.append(("Social", Int.random(in: 17...19, using: &rng), [90, 120].randomElement(using: &rng)!)) }
                plan.append(("Personal / Rest", Int.random(in: 15...18, using: &rng), [45, 60].randomElement(using: &rng)!))
            }

            for (name, hour, minutes) in plan {
                guard let activityId = byName[name],
                      let start = cal.date(bySettingHour: hour, minute: Int.random(in: 0...50, using: &rng), second: 0, of: day)
                else { continue }
                let session = Session(
                    activityId: activityId,
                    startAt: start,
                    endAt: start.addingTimeInterval(TimeInterval(minutes * 60))
                )
                sessions.append(session)

                // Roughly one session in seven is never rated — the model must carry
                // "unknown" through the whole app rather than filling in a middle value.
                if Int.random(in: 0...6, using: &rng) > 0 {
                    let feeling = rating(activity: name, hour: hour, rng: &rng)
                    reflections[session.id] = Reflection(
                        sessionId: session.id,
                        feelingScore: feeling,
                        performanceScore: Int.random(in: 0...2, using: &rng) == 0 ? nil : min(5, max(1, feeling + Int.random(in: -1...1, using: &rng))),
                        note: nil,
                        submittedAt: session.endAt ?? start
                    )
                }
            }
        }

        // Last night, as Health would have it.
        //
        // The six-week loop above covers yesterday back to day 42 and stops, so
        // without this the one day somebody is most likely to be looking at is the
        // one day with no imported night on it — which is exactly backwards.
        // Fixed rather than seeded, like the rest of today's record.
        //
        // The night has to have *finished*. Seeded at a fixed 6:40 it ended in
        // the future for anybody looking before breakfast, which is a session
        // that has not happened yet — and at one in the morning it covered the
        // hour the log sheet wanted to default into, so the sheet correctly
        // searched back and offered a slot on the previous evening instead. A
        // fixture that claims somebody is currently asleep is wrong before it is
        // inconvenient.
        if let restId = byName["Personal / Rest"],
           let wakeToday = cal.date(bySettingHour: 6, minute: 40, second: 0, of: today) {
            let wake = wakeToday <= Date()
                ? wakeToday
                : wakeToday.addingTimeInterval(-24 * 3600)
            sessions.append(Session(
                activityId: restId,
                startAt: wake.addingTimeInterval(-7.5 * 3600),
                endAt: wake,
                source: .health,
                healthKind: .sleep,
                externalId: "health.sleep.fixture.0"
            ))
        }

        // Today's record echoes the four moments from the landing page, so the app
        // visually rhymes with the marketing site.
        let todayPlan: [(String, Int, Int, Int, String, String)] = [
            ("Deep work", 8, 30, 95, "Write the hard thing", "Clear head. No rush."),
            ("Meetings", 11, 45, 60, "Team sync", "Useful, but demanding."),
            ("Admin", 15, 10, 40, "Inbox and loose ends", "Energy slips away."),
            ("Exercise", 18, 20, 35, "A walk without a podcast", "Back to yourself."),
        ]
        for (name, hour, minute, minutes, intention, note) in todayPlan {
            guard let activityId = byName[name],
                  let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: today),
                  start < Date()
            else { continue }
            let session = Session(
                activityId: activityId,
                startAt: start,
                endAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                note: note,
                intention: intention
            )
            sessions.append(session)
            reflections[session.id] = Reflection(
                sessionId: session.id,
                feelingScore: rating(activity: name, hour: hour, rng: &rng),
                performanceScore: nil,
                note: note,
                submittedAt: session.endAt ?? start
            )
        }

        // Day one keeps the Health history and drops everything logged. Applied
        // here rather than by skipping the generation above, so that the two modes
        // cannot drift: the same record is built either way and this is the only
        // line that differs.
        store.sessions = isDayOne ? [] : sessions.sorted { $0.startAt < $1.startAt }
        store.reflections = isDayOne ? [:] : reflections

        // Health, which until now was generated and then never handed to anybody.
        //
        // `seededDaily` and `seededFeed` were both written, both deterministic,
        // and both had zero callers — so `healthByDay` and `physiologyReadings`
        // were empty on a simulator no matter what the launch argument said.
        // Three features shipped behind that: the daily fact, the post-rating
        // card, and the session residual all render only when health exists, so
        // none of them could be seen by running the app, and both UI suites had
        // to write their assertions around the absence rather than through it.
        //
        // Ordered deliberately. Daily context first, because `applyPhysiology`
        // rebuilds observations and those read the day's health. The feed second,
        // because scoring needs the sessions above to already be in place.
        store.applyHealthContext(Dictionary(
            uniqueKeysWithValues: HealthMetric.allCases
                .filter(\.isDailyContext)
                .map { ($0, seededDaily(for: $0)) }
        ))
        store.applyPhysiology(feed: seededFeed())

        store.rebuildInsights()

        // After the rebuild, because a settled experiment is read against the rows
        // the engine holds and those do not exist until it has run. Not on day one:
        // somebody with nothing logged has not run a fortnight either, and a settled
        // result would claim the slot the starter is there to be looked at in.
        if !isDayOne { seedExperiments(into: store, today: today, calendar: cal) }

        // Last, and only when asked: every test that walks onboarding depends on
        // this staying false by default.
        if skipsOnboarding { store.hasCompletedOnboarding = true }
    }

    /// A settled experiment, so the result card is reachable without waiting a
    /// fortnight in the simulator.
    ///
    /// **Why this exists at all.** Three of this feature's four states are
    /// unreachable on a fresh fixture: a proposal needs the engine to have survived
    /// its gates, and an active or settled window needs somebody to have agreed to
    /// one and then waited two weeks. Seeding health data was the difference between
    /// three features being visible in the simulator and being invisible, and the
    /// same is true here — a card nobody can get to is a card nobody reviews.
    ///
    /// Only the settled one is planted. The proposal appears on its own once the
    /// engine has something, and accepting it is one tap — so seeding that too would
    /// be seeding the thing the fixture is meant to let somebody try.
    private static func seedExperiments(into store: HourssStore, today: Date, calendar: Calendar) {
        // Opened sixteen days ago, so a fourteen-day window has closed and settling
        // has something real to read: the fixture's planted signal is deep work in
        // the morning, which is the hypothesis most likely to have survived.
        guard let opened = calendar.date(byAdding: .day, value: -16, to: today) else { return }

        let morning = store.engineObservations.isEmpty
            ? nil
            : HypothesisRegistry.hypotheses(for: store.engineObservations)
                .first { $0.id.hasPrefix("time.morning") }
        guard let morning else { return }

        let experiment = Experiment(
            hypothesisId: morning.id,
            outcome: morning.outcome,
            startedAt: opened,
            focusLabel: morning.focusLabel,
            baselineLabel: morning.baselineLabel,
            premise: "Your morning sessions have felt more energizing.",
            change: "Put one block in your morning on most days this fortnight.",
            caveat: morning.caveat
        )
        var seeded: [Experiment] = [
            // 200 resamples, not the 2000 a real settling uses. This runs inside
            // `HourssStore.init`, on the main thread, before the first frame — a
            // full day-clustered bootstrap there is seconds of launch for a figure
            // nobody is going to publish, and it is the fixture's own number rather
            // than anybody's record. The verdict can differ from a real settling at
            // this count; that is acceptable for a fixture and would not be
            // anywhere else.
            ExperimentOutcome.settle(experiment, hypothesis: morning,
                                     observations: store.engineObservations,
                                     now: today, resamples: 200)
        ]
        // Three more, so that the record screen is a record rather than one row.
        //
        // `You → Tests` exists to show what somebody has tested over time, and a
        // fixture with a single entry cannot show the thing it is for: that the
        // three verdicts are presented alike, that a stopped test is kept, and that
        // acknowledging a result dismisses the card and not the record. Each is
        // pinned to a different start date so the ordering is visible, and the
        // oldest is already acknowledged.
        //
        // Hand-built rather than settled, unlike the one above. A fixture cannot
        // make the planted signal produce a chosen verdict on demand, and three more
        // bootstraps inside `init` would be launch time spent on figures nobody
        // publishes. These exist to be *looked at*, so their numbers are written
        // down rather than computed.
        // `focusLabel` per entry, not the morning hypothesis's for all of them.
        // `ExperimentCopy.result` opens with that label, so borrowing it gave a row
        // whose change is about session length a report reading "Morning settled
        // at…" — visible on the first screenshot of the finished screen, and exactly
        // the kind of thing a fixture is for catching.
        func past(_ daysAgo: Int, verdict: Experiment.Verdict?,
                  focusLabel: String, change: String, focus: Double, baseline: Double,
                  adherence: Int, acknowledged: Bool = false) -> Experiment? {
            guard let started = calendar.date(byAdding: .day, value: -daysAgo, to: today)
            else { return nil }
            var one = Experiment(
                hypothesisId: morning.id, outcome: morning.outcome, startedAt: started,
                focusLabel: focusLabel, baselineLabel: morning.baselineLabel,
                premise: "Your morning sessions have felt more energizing.",
                change: change, caveat: morning.caveat
            )
            guard let verdict else {
                // Stopped: no settlement at all, which is what makes it plainly not
                // a fourth verdict rather than a quieter one.
                one.abandonedAt = calendar.date(byAdding: .day, value: 3, to: started)
                return one
            }
            one.settlement = Experiment.Settlement(
                verdict: verdict, adherenceDays: adherence, baselineDays: 12,
                focusFigure: focus, baselineFigure: baseline,
                delta: focus - baseline, intervalLow: -0.1, intervalHigh: 0.6,
                settledAt: calendar.date(byAdding: .day, value: 14, to: started) ?? started
            )
            if acknowledged {
                one.acknowledgedAt = calendar.date(byAdding: .day, value: 15, to: started)
            }
            return one
        }

        seeded += [
            // Acknowledged, like everything else in the past. Exactly one result may
            // be unacknowledged at a time — `unacknowledgedExperiment` is what claims
            // the slot on Today, so a second one simply takes the slot when the first
            // is dismissed, and a test that acknowledges the card then waits for it
            // to go waits forever. A history is by definition things already seen.
            past(34, verdict: .didNotHoldUp, focusLabel: "90–179 min",
                 change: "End one block at the 90–179 min mark on most days this fortnight.",
                 focus: 3.5, baseline: 3.4, adherence: 9, acknowledged: true),
            past(62, verdict: nil, focusLabel: "Deep work",
                 change: "Give Deep work a block of its own on most days this fortnight.",
                 focus: 0, baseline: 0, adherence: 0),
            past(90, verdict: .cannotTell, focusLabel: "Non-workdays",
                 change: "Put one block on each of your days off this fortnight.",
                 focus: 0, baseline: 0, adherence: 3, acknowledged: true),
        ].compactMap { $0 }

        if seedsRandomised {
            seeded += randomised(morning: morning, store: store, today: today, calendar: calendar)
        }
        store.experiments = seeded
        store.persist()
    }

    /// A drawn window, settled, and a second one still running.
    ///
    /// Two rather than one because the two cards say different things and neither can
    /// be reached from the other: the settled one is the result — the only place the
    /// sentence about the days having been chosen for somebody appears — and the
    /// active one is the day list and the question of whether today is one of them,
    /// which is the part of this phase a person has to live with for a month.
    ///
    /// Both settle at the same instant the chosen window's result does — there is one
    /// `today` in a fixture run and reading the clock twice is the bug this codebase
    /// has already shipped once — so the order on Today is the order of this array,
    /// which `unacknowledgedExperiment` keeps for equal stamps. Acknowledging twice
    /// therefore walks chosen result, drawn result, drawn window in progress: three
    /// taps for every card this feature has.
    ///
    /// **Whatever verdict the fixture's own history produces is the right one to
    /// show, including the awkward one.** This record logs a morning block on most of
    /// its days, which is high adherence on the drawn days and heavy contamination on
    /// the rest — so the likeliest result here is that the window cannot be read, and
    /// that is the card most worth being able to look at. Bending the generator to
    /// manufacture a clean "held up" would be seeding the conclusion rather than the
    /// state.
    private static func randomised(morning: Hypothesis, store: HourssStore,
                                   today: Date, calendar: Calendar) -> [Experiment] {
        let window = Experiment.randomisedWindowDays
        guard let settledOpened = calendar.date(byAdding: .day, value: -(window + 2), to: today),
              let activeOpened = calendar.date(byAdding: .day, value: -10, to: today),
              let change = ExperimentCopy.randomisedChange(
                type: morning.type, focusLabel: morning.focusLabel)
        else { return [] }

        func drawn(opened: Date) -> Experiment {
            Experiment(
                hypothesisId: morning.id,
                outcome: morning.outcome,
                startedAt: opened,
                windowDays: window,
                focusLabel: morning.focusLabel,
                baselineLabel: morning.baselineLabel,
                // Through the same call the store uses, rather than a hand-written
                // day list. A fixture that drew its days differently from the app
                // would be a fixture nobody could trust about the one thing this
                // phase added.
                assignment: Experiment.Assignment.make(
                    hypothesisId: morning.id, startedAt: opened, windowDays: window),
                premise: "Your morning sessions have felt more energizing.",
                change: change,
                caveat: ExperimentCopy.randomisedCaveat(morning.caveat, windowDays: window))
        }

        return [
            ExperimentOutcome.settle(drawn(opened: settledOpened), hypothesis: morning,
                                     observations: store.engineObservations,
                                     now: today, resamples: 200),
            drawn(opened: activeOpened),
        ]
    }


    /// Deterministic physiology for simulator builds, which have no Health data at
    /// all. Never reachable on a device: see the note in `HealthService.refresh()`
    /// about what happens when invented values are presented back to somebody as
    /// their own history.
    static func seededFeed(days: Int = 60, now: Date = Date()) -> Physiology.Feed {
        var state: UInt64 = 0x484F5552 &* 6364136223846793005 &+ 1442695040888963407
        func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 10_000) / 10_000
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var heartRate: [Physiology.Sample] = []
        var steps: [Physiology.Sample] = []

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for minuteOfDay in stride(from: 7 * 60, to: 23 * 60, by: 5) {
                let at = day.addingTimeInterval(Double(minuteOfDay) * 60)
                let hour = Double(minuteOfDay) / 60
                var bpm = 61 + 8 * sin((hour - 7) / 16 * .pi) + (next() - 0.5) * 5
                var stepped = next() * 12
                if next() < 0.06 {
                    let bout = 150 + next() * 350
                    stepped += bout
                    bpm += bout / 30
                }
                heartRate.append(Physiology.Sample(at: at, value: bpm))
                steps.append(Physiology.Sample(at: at, value: stepped))
            }
        }
        return Physiology.Feed(heartRate: heartRate, steps: steps, vigorous: [])
    }
}

#endif
