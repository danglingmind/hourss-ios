import Foundation
@testable import Hourss

/// Generated people carrying a known answer key.
///
/// The engine's behaviour on real data cannot be checked, because real data has no
/// answer key — a claim that is real and a claim that is an artifact read exactly
/// alike once they are phrased as sentences. These people exist so both halves of
/// correctness become assertable: that a planted effect is *found*, and that an
/// absent one is *not invented*.
///
/// The second half is the one that matters. Any procedure can find patterns in
/// noise; the only way to know whether ours does is to hand it noise and watch.
enum SyntheticCohort {

    // MARK: - Answer key

    /// An effect deliberately written into a person's data.
    enum Planted: Equatable, CustomStringConvertible {
        /// Sessions in `worse` are rated `delta` lower than those in `better`.
        case timeWindow(better: TimeBucket, worse: TimeBucket, delta: Double)
        /// This activity is rated `delta` away from the person's other activities.
        case activityEffect(named: String, delta: Double)
        /// Sessions in this duration bucket are rated `delta` above the rest.
        case durationEffect(bucket: DurationBucket, delta: Double)
        /// Ratings on days after more sleep run `delta` higher.
        case sleepAssociation(delta: Double)
        /// Heart rate during this activity runs `bpm` above the hour's baseline.
        /// `movement` records whether the person was also walking — the whole
        /// point of the layer-3 residual is telling these two apart.
        case heartRate(activity: String, bpm: Double, movement: Bool)
        /// The person walks at about `cadence` steps a minute throughout the day —
        /// inside logged sessions and outside them — and that pace costs them
        /// `bpm` beats a minute wherever it happens.
        ///
        /// This is what makes a meeting residual an out-of-sample number. Without
        /// it, someone whose only brisk windows are their meetings hands the curve
        /// one bin containing nothing but meetings, and "what walking costs" and
        /// "what meetings cost" are then the same estimate wearing two names.
        case movementHabit(cadence: Double, bpm: Double)
        /// This activity, in this time bucket — and optionally only on days after
        /// the person's own sleep median — is rated `delta` above what the
        /// activity and the hour separately account for.
        ///
        /// Deliberately *only* the interaction. Whatever either factor is worth on
        /// its own is planted as its own effect, so `delta` is the lift over an
        /// additive world and nothing else. A conjunction case that folded the
        /// main effects in would make the confounded person impossible to write:
        /// he needs a large activity effect and an interaction of exactly zero,
        /// and those have to be separately settable to be separately zeroable.
        case conjunction(activity: String, bucket: TimeBucket, afterMedianSleep: Bool, delta: Double)
        /// Heart rate during this activity runs `bpm` above what the person's own
        /// movement explains — the part of a rise walking does not buy.
        ///
        /// Deliberately not the same claim as `.heartRate`. For somebody who walks
        /// through everything, "the rise" and "the rise movement cannot account
        /// for" are two different numbers, and the residual only ever means to
        /// recover the second.
        case unexplainedRise(activity: String, bpm: Double)

        var description: String {
            switch self {
            case let .timeWindow(better, worse, delta):
                "\(worse.label) rated \(fmt(delta)) below \(better.label)"
            case let .activityEffect(named, delta):
                "\(named) rated \(fmt(delta)) \(delta < 0 ? "below" : "above") the rest"
            case let .durationEffect(bucket, delta):
                "\(bucket.label) rated \(fmt(delta)) above the rest"
            case let .sleepAssociation(delta):
                "days after more sleep rated \(fmt(delta)) higher"
            case let .heartRate(activity, bpm, movement):
                "\(activity) runs \(fmt(bpm)) bpm high, \(movement ? "while walking" : "sitting still")"
            case let .movementHabit(cadence, bpm):
                "walks at \(fmt(cadence)) steps a minute all day, worth \(fmt(bpm)) bpm"
            case let .conjunction(activity, bucket, afterMedianSleep, delta):
                "\(activity) in the \(bucket.label.lowercased())"
                + (afterMedianSleep ? " after above-median sleep" : "")
                + " rated \(fmt(delta)) above what either factor alone buys"
            case let .unexplainedRise(activity, bpm):
                "\(activity) runs \(fmt(bpm)) bpm above what movement explains"
            }
        }

        private func fmt(_ d: Double) -> String { String(format: "%.1f", abs(d)) }
    }

    /// A claim that would be wrong about this person. Asserted as *absence*.
    enum Forbidden: Equatable, CustomStringConvertible {
        /// Nothing at all should reach the visible threshold.
        case anyVisibleClaim
        /// This specific kind of claim would be an artifact.
        case claim(InsightType)

        var description: String {
            switch self {
            case .anyVisibleClaim: "any visible claim"
            case let .claim(type): "a \(type.rawValue) claim"
            }
        }
    }

    struct Truth {
        var planted: [Planted] = []
        var forbidden: [Forbidden] = []
        /// Why this person is in the cohort, in one line.
        var rationale: String = ""
    }

    // MARK: - A generated person

    struct Person {
        let name: String
        /// The whole input this person was built from, kept so the person can be
        /// rebuilt with one part of it changed. `rebuilt(at:)` is the only reason
        /// it is here, and the reason that matters: a time basis you cannot vary
        /// is a time basis nobody can check.
        let recipe: Recipe
        var truth: Truth { recipe.truth }
        let activities: [Activity]
        let sessions: [Session]
        let reflections: [UUID: Reflection]
        /// Full-resolution samples, kept at the resolution HealthKit actually
        /// stores them in. Layer 3 reads these; today's engine reads the rollup.
        let samples: [HealthMetric: [Sample]]
        /// Raw heart rate, which `HealthMetric` has no case for because the app
        /// does not read it. Carried separately so that gap is testable rather
        /// than theoretical.
        let heartRate: [Sample]

        /// How the current engine sees health: one number per day, which is the
        /// shape `intervalComponents: DateComponents(day: 1)` produces.
        ///
        /// Rolled up once at construction rather than on every access. The result
        /// was already the same both ways — `Sample` is a value type and the
        /// rollup is pure — but a *computed* view onto a cached person is the
        /// shape the UUID bug took, and the rollup runs on every call to
        /// `ObservationBuilder.rows`, which the interaction suites make hundreds
        /// of. Storing it removes both the hazard and the cost.
        let healthByDay: [HealthMetric: [Date: Double]]

        init(recipe: Recipe,
             activities: [Activity],
             sessions: [Session],
             reflections: [UUID: Reflection],
             samples: [HealthMetric: [Sample]],
             heartRate: [Sample]) {
            self.name = recipe.name
            self.recipe = recipe
            self.activities = activities
            self.sessions = sessions
            self.reflections = reflections
            self.samples = samples
            self.heartRate = heartRate
            self.healthByDay = samples.reduce(into: [:]) { out, entry in
                out[entry.key] = Sample.rollUpByDay(entry.value, cumulative: entry.key.isCumulative)
            }
        }

        /// This person against a different day, and nothing else changed.
        ///
        /// The recipe is the entire input to generation, so a person and their
        /// rebuild differ in exactly one thing. What that one thing can reach is
        /// the question `CohortTests.timeBasisIsFixed` asks: a whole number of
        /// weeks reaches only the dates, and anything else reaches the weekday of
        /// every session — and through the weekday, `isWorkday`, the weekend
        /// sleep bonus, the sleep median, and the answer key's own
        /// `afterMedianSleep` predicate.
        func rebuilt(at anchor: Date) -> Person {
            var recipe = self.recipe
            recipe.anchor = anchor
            return SyntheticCohort.make(recipe)
        }

        /// Rated, pattern-eligible sessions — the only ones the engine can use.
        var ratedCount: Int {
            sessions.filter { $0.isEligibleForPatterns && reflections[$0.id]?.feelingScore != nil }.count
        }
    }

    struct Sample: Equatable {
        let at: Date
        let value: Double

        /// Mean for rate-like metrics, sum for cumulative ones — matching what
        /// `HKStatisticsCollectionQuery` would return for each option.
        static func rollUpByDay(_ samples: [Sample], cumulative: Bool) -> [Date: Double] {
            let calendar = Calendar.current
            var buckets: [Date: [Double]] = [:]
            for sample in samples {
                buckets[calendar.startOfDay(for: sample.at), default: []].append(sample.value)
            }
            return buckets.mapValues { values in
                cumulative ? values.reduce(0, +) : values.reduce(0, +) / Double(values.count)
            }
        }
    }

    // MARK: - Determinism

    /// The generator must produce identical people on every run, or a failing test
    /// cannot be reproduced. `SystemRandomNumberGenerator` would make every run a
    /// different experiment.
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

    /// Approximately normal, via the central limit theorem on four uniforms. Good
    /// enough for generating plausible ratings and far cheaper than Box–Muller.
    static func gaussian(_ rng: inout Seeded, sd: Double) -> Double {
        let sum = (0..<4).reduce(0.0) { acc, _ in acc + Double.random(in: -1...1, using: &rng) }
        return sum / 2 * sd
    }

    // MARK: - The time basis

    /// The day every generated history counts back from: the most recent Monday,
    /// resolved once for the whole process.
    ///
    /// This was `Calendar.current.startOfDay(for: Date())` — *computed*, so
    /// re-read at each of the two thousand-odd points the generator asks for a
    /// day, while the people themselves are lazily-initialised `static let`s that
    /// come into existence whenever a test first touches them. Two failures
    /// followed and both were real:
    ///
    /// * A person built at 23:59 and a person built at 00:01 counted back from
    ///   different days, so one run of one suite could hold two mutually
    ///   inconsistent cohorts. The same hazard sat inside a single `make` call,
    ///   whose sleep loop and session loop each re-read the anchor.
    /// * Across runs the whole cohort rotated with the calendar. Nothing in the
    ///   engine filters on absolute dates, but plenty reads the *weekday*: every
    ///   observation's `isWorkday`, and the generator's own weekend sleep bonus —
    ///   which moves `sleepMean` and `sleepMedian`, and with them the
    ///   `afterMedianSleep` half of the planted three-way and the
    ///   `health.sleepHours.high` factor the search conditions on.
    ///
    /// Measured rather than argued. Rebuilding the cohort against each of the
    /// seven weekday alignments in turn, holding everything else fixed:
    ///
    /// | quantity                                        | across the seven |
    /// | ----------------------------------------------- | ---------------- |
    /// | planted 3-way admitted (`permutationFDR`)        | 3,2,3,0,2,2,0    |
    /// | estimable candidates *m*, `scatteredNoise`       | 6 … 14           |
    /// | BY admissions, `scatteredNoise`                  | 1 … 4            |
    /// | rating-level quantities, everybody else          | unchanged        |
    ///
    /// The first row is the one that was costing runs.
    /// `InteractionCorrectionTests.cohortMeasurement` asserts that the planted
    /// three-way survives the recommended procedure, and on two alignments in
    /// seven it does not — so that suite failed on roughly two days a week and
    /// passed on the other five, with nothing in the diff to explain either.
    /// Everything the alignment moves, it moves through *m*: `workday.work` and
    /// the sleep-derived factors change which conjunctions are generated at all,
    /// and a step-up threshold is `k/m · q`, so every candidate the alignment adds
    /// raises the bar for the real one.
    ///
    /// **Why a weekday and not a stated date.** A constant like 2025-06-02 is the
    /// obvious fix and it breaks eight tests elsewhere: `applyPhysiology` scores
    /// only sessions inside `HealthService.physiologyDays`, so a cohort a year in
    /// the past is a cohort with no physiology at all. Pinning the *weekday*
    /// instead keeps the history where the app can still see it and gives the
    /// same guarantee, because it makes every anchor this can ever return differ
    /// from every other by a whole number of weeks — and generation is invariant
    /// under whole-week shifts. That invariance is the load-bearing claim, so it
    /// is asserted rather than described: `CohortTests.timeBasisIsFixed` rebuilds
    /// every person fifty-two weeks away and compares them line for line, and
    /// rebuilds them one day away to show the alignment is what the fixing is
    /// for.
    ///
    /// Injectable through `Recipe.anchor`, which is how that test moves it.
    static let anchor: Date = mostRecentMonday(onOrBefore: Date())

    /// Monday on or before `date`. A function rather than an expression so the
    /// rule can be checked at dates the run did not happen to fall on.
    static func mostRecentMonday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        // Sunday is 1 in Gregorian, so Monday is 2 and this is 0 on a Monday and
        // 6 on a Sunday, independent of the locale's first weekday.
        let back = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }
}
