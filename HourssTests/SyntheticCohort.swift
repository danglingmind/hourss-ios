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
        let truth: Truth
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
        var healthByDay: [HealthMetric: [Date: Double]] {
            samples.reduce(into: [:]) { out, entry in
                out[entry.key] = Sample.rollUpByDay(entry.value, cumulative: entry.key.isCumulative)
            }
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

    /// Anchored so generated history is stable relative to the day the test runs.
    /// The engine applies no date filter of its own, so only the hour-of-day and
    /// weekday of each session actually reach a comparison.
    static var anchor: Date { Calendar.current.startOfDay(for: Date()) }
}
