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
        if let restId = byName["Personal / Rest"],
           let wake = cal.date(bySettingHour: 6, minute: 40, second: 0, of: today) {
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

        store.sessions = sessions.sorted { $0.startAt < $1.startAt }
        store.reflections = reflections

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
