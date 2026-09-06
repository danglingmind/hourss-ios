import Foundation
@testable import Hourss

/// Builds a `Person` from a recipe.
///
/// The answer key is the *input*, not a note written alongside it: every rating is
/// produced by applying the `Planted` effects and nothing else, so a person's data
/// and their truth cannot disagree. This mirrors how `Insight.Evidence` works in
/// the app — the claim and its support come from the same array by construction.
extension SyntheticCohort {

    struct Recipe {
        var name: String
        var seed: UInt64
        var days: Int = 90
        var sessionsPerDay: ClosedRange<Int> = 2...4
        /// The person's own centre of gravity. Not a population mean — nothing
        /// here is ever compared across people.
        var baseRating: Double = 3.4
        /// Day-to-day variation with no cause behind it. This is what a claim has
        /// to beat to be worth making.
        var noiseSD: Double = 0.75
        /// Share of eligible sessions that get a feeling score.
        var ratingCoverage: Double = 0.75
        /// When true, draining sessions are *less* likely to be rated — the
        /// informative-missingness case the BRD flags and the engine ignores.
        var skipsLowRatings: Bool = false
        var truth: Truth
    }

    static func make(_ recipe: Recipe) -> Person {
        var rng = Seeded(seed: recipe.seed)
        let calendar = Calendar.current
        let activities = Activity.defaults

        // ── Health first: ratings may depend on the previous night's sleep ──
        var sleepByDay: [Date: Double] = [:]
        for offset in 0...recipe.days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            sleepByDay[day] = (isWeekend ? 8.1 : 7.1) + gaussian(&rng, sd: 0.55)
        }
        let sleepMean = sleepByDay.values.reduce(0, +) / Double(sleepByDay.count)

        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        /// Windows the heart-rate generator needs, so physiology lines up with the
        /// sessions rather than being invented independently.
        var occupied: [(range: ClosedRange<Date>, activity: String)] = []

        for offset in 0..<recipe.days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchor) else { continue }
            let sleepLastNight = sleepByDay[day] ?? sleepMean

            var hour = Int.random(in: 8...10, using: &rng)
            for _ in 0..<Int.random(in: recipe.sessionsPerDay, using: &rng) {
                guard hour < 21 else { break }
                let activity = activities[Int.random(in: 0..<activities.count, using: &rng)]
                let minutes = [25, 45, 50, 60, 75, 95, 120][Int.random(in: 0...6, using: &rng)]

                guard let start = calendar.date(bySettingHour: hour,
                                                minute: Int.random(in: 0...45, using: &rng),
                                                second: 0, of: day) else { break }
                let end = start.addingTimeInterval(TimeInterval(minutes * 60))
                let session = Session(activityId: activity.id, startAt: start, endAt: end)
                sessions.append(session)
                occupied.append((start...end, activity.name))

                // ── The rating: base + every planted effect + noise, nothing else
                var value = recipe.baseRating
                for effect in recipe.truth.planted {
                    value += contribution(of: effect,
                                          to: session,
                                          named: activity.name,
                                          sleepLastNight: sleepLastNight,
                                          sleepMean: sleepMean)
                }
                value += gaussian(&rng, sd: recipe.noiseSD)
                let rating = max(1, min(5, Int(value.rounded())))

                // ── Whether they bothered to rate it
                var coverage = recipe.ratingCoverage
                if recipe.skipsLowRatings && rating <= 2 { coverage *= 0.3 }
                if Double.random(in: 0...1, using: &rng) < coverage {
                    reflections[session.id] = Reflection(
                        sessionId: session.id,
                        feelingScore: rating,
                        performanceScore: max(1, min(5, rating + Int.random(in: -1...1, using: &rng))),
                        note: nil,
                        submittedAt: end
                    )
                }
                hour += max(1, minutes / 60) + Int.random(in: 1...2, using: &rng)
            }
        }

        let health = healthSamples(recipe: recipe,
                                   sleepByDay: sleepByDay,
                                   occupied: occupied,
                                   rng: &rng)

        return Person(name: recipe.name,
                      truth: recipe.truth,
                      activities: activities,
                      sessions: sessions,
                      reflections: reflections,
                      samples: health.byMetric,
                      heartRate: health.heartRate)
    }

    /// How much one planted effect moves one session's rating. Effects that do not
    /// apply to this session contribute exactly zero.
    private static func contribution(
        of effect: Planted,
        to session: Session,
        named: String,
        sleepLastNight: Double,
        sleepMean: Double
    ) -> Double {
        switch effect {
        case let .timeWindow(_, worse, delta):
            session.timeBucket == worse ? -delta : 0
        case let .activityEffect(name, delta):
            named == name ? delta : 0
        case let .durationEffect(bucket, delta):
            session.durationBucket == bucket ? delta : 0
        case let .sleepAssociation(delta):
            (sleepLastNight - sleepMean) * delta
        case .heartRate:
            0   // physiological, not a rating effect
        }
    }
}
