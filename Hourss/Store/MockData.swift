import Foundation

/// Seeds roughly six weeks of history so the Patterns screens have something real
/// to stand on.
///
/// Two things matter here. First, generation is deterministic (fixed seed), so a
/// demo looks identical every launch. Second, the observations shown in Patterns
/// are *computed from these sessions*, not hardcoded — the "4.2 vs 3.4" evidence
/// line and the session list behind it always agree, because they come from the
/// same array.
@MainActor
enum MockData {

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
        var rng = Seeded(seed: UInt64(abs(metric.rawValue.hashValue % 100_000)) &+ 0x484B)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: Double] = [:]

        for dayOffset in 0...42 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let jitter = Double(Int.random(in: -10...10, using: &rng)) / 10

            byDay[day] = switch metric {
            case .sleepHours: (isWeekend ? 8.0 : 7.0) + jitter * 0.6
            case .hrv: (isWeekend ? 58 : 48) + jitter * 6
            case .restingHeartRate: (isWeekend ? 55 : 60) + jitter * 3
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
        store.profile.goals = [.focus, .energy]

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
        store.insights = InsightBuilder.build(sessions: store.sessions, reflections: reflections, activities: store.activities)
    }
}
