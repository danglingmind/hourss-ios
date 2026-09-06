import Foundation

/// The statistic behind every comparison.
///
/// Three properties the previous confidence formula did not have.
///
/// **It is ordinal.** Feeling is a 1–5 scale where the distance from Draining to
/// Depleting is not known to equal the distance from Steady to Energizing. Taking
/// a mean of those numbers assumes a spacing nobody measured. Cliff's delta only
/// asks how often one group's ratings land above the other's, which is a question
/// the scale can actually answer.
///
/// **It carries an interval.** A point estimate cannot say "not yet"; an interval
/// that spans zero says exactly that, and says it for the right reason — the data
/// is consistent with there being no difference at all.
///
/// **It resamples days, not sessions.** Three sessions logged on one bad Tuesday
/// are not three independent pieces of evidence about Tuesdays. Treating them as
/// independent is pseudo-replication, and it inflates confidence precisely when
/// someone has been logging heavily, which is when they are most likely to be
/// reading their feed.
enum Statistics {

    /// One rating, tagged with the day it belongs to so the bootstrap can keep
    /// same-day observations together.
    struct Observation {
        let day: Date
        let value: Double

        init(day: Date, value: Double) {
            self.day = day
            self.value = value
        }
    }

    /// How large a difference is, on Cliff's own scale.
    ///
    /// Thresholds from Romano et al. (2006), who calibrated them against Cohen's
    /// conventions. They are a convention, not a law of nature, and they are
    /// applied to a person's own history rather than to any population.
    enum Magnitude: String {
        case negligible, small, medium, large

        static func of(_ delta: Double) -> Magnitude {
            switch abs(delta) {
            case ..<0.147: .negligible
            case ..<0.330: .small
            case ..<0.474: .medium
            default: .large
            }
        }
    }

    struct Comparison {
        /// Cliff's delta: −1 (every focus rating below baseline) to +1 (every one
        /// above). Zero means the two groups interleave completely.
        let delta: Double
        /// Percentile bootstrap interval, day-clustered.
        let low: Double
        let high: Double
        /// Observation counts, kept for the evidence line.
        let focusCount: Int
        let baselineCount: Int
        /// Distinct days behind each side — the number that actually governs how
        /// much independent evidence there is.
        let focusDays: Int
        let baselineDays: Int
        /// Bootstrap p-value: twice the smaller tail of the resampled deltas
        /// about zero. Not a classical p-value, and not shown to anyone — it
        /// exists so Benjamini–Hochberg has something to rank by when several
        /// hypotheses are tested in the same run.
        let pValue: Double

        /// The honest "not yet". If the interval contains zero, the data is
        /// consistent with no difference and nothing should be claimed.
        var spansZero: Bool { low <= 0 && high >= 0 }

        var magnitude: Magnitude { Magnitude.of(delta) }

        /// Width of the interval — how precisely the effect is pinned down. Used
        /// for ranking, since a tight small effect can be worth more than a wide
        /// large one.
        var width: Double { high - low }

        /// Whether this is worth showing at all. Both conditions are necessary:
        /// an interval clear of zero, and an effect big enough to notice.
        var isReportable: Bool { !spansZero && magnitude != .negligible }
    }

    /// Cliff's delta: the probability a focus rating exceeds a baseline rating,
    /// minus the probability it falls short. Ties count for neither.
    static func cliffsDelta(focus: [Double], baseline: [Double]) -> Double {
        guard !focus.isEmpty, !baseline.isEmpty else { return 0 }
        var above = 0, below = 0
        for f in focus {
            for b in baseline {
                if f > b { above += 1 } else if f < b { below += 1 }
            }
        }
        return Double(above - below) / Double(focus.count * baseline.count)
    }

    /// Deterministic generator. A confidence interval that moves between runs is
    /// not reproducible, and an irreproducible number should not be shown to
    /// anyone as evidence.
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

    /// Compare two groups, resampling whole days.
    ///
    /// The unit of resampling is the day rather than the session. Every rating
    /// from a drawn day travels with it, into whichever side it belongs to, so a
    /// day where someone logged six sessions contributes one draw of evidence and
    /// not six.
    static func compare(
        focus: [Observation],
        baseline: [Observation],
        resamples: Int = 2000,
        seed: UInt64 = 0x484F_5552
    ) -> Comparison {
        let focusValues = focus.map(\.value)
        let baselineValues = baseline.map(\.value)
        let point = cliffsDelta(focus: focusValues, baseline: baselineValues)

        let calendar = Calendar.current
        var byDay: [Date: (focus: [Double], baseline: [Double])] = [:]
        for o in focus {
            byDay[calendar.startOfDay(for: o.day), default: ([], [])].focus.append(o.value)
        }
        for o in baseline {
            byDay[calendar.startOfDay(for: o.day), default: ([], [])].baseline.append(o.value)
        }

        let days = Array(byDay.keys)
        let focusDays = byDay.values.filter { !$0.focus.isEmpty }.count
        let baselineDays = byDay.values.filter { !$0.baseline.isEmpty }.count

        func result(low: Double, high: Double, p: Double = 1) -> Comparison {
            Comparison(delta: point, low: low, high: high,
                       focusCount: focus.count, baselineCount: baseline.count,
                       focusDays: focusDays, baselineDays: baselineDays,
                       pValue: p)
        }

        // Too little to resample from: report the widest possible interval, which
        // spans zero and therefore claims nothing.
        guard days.count >= 4, !focus.isEmpty, !baseline.isEmpty else {
            return result(low: -1, high: 1)
        }

        var rng = Seeded(seed: seed)
        var deltas: [Double] = []
        deltas.reserveCapacity(resamples)

        for _ in 0..<resamples {
            var f: [Double] = [], b: [Double] = []
            for _ in 0..<days.count {
                let drawn = days[Int.random(in: 0..<days.count, using: &rng)]
                if let bucket = byDay[drawn] {
                    f.append(contentsOf: bucket.focus)
                    b.append(contentsOf: bucket.baseline)
                }
            }
            // A resample that empties one side carries no information about the
            // difference; dropping it is standard and does not bias the interval.
            guard !f.isEmpty, !b.isEmpty else { continue }
            deltas.append(cliffsDelta(focus: f, baseline: b))
        }

        guard deltas.count >= resamples / 4 else { return result(low: -1, high: 1) }
        deltas.sort()

        // Twice the smaller tail, floored at one resample — a bootstrap cannot
        // resolve a p-value finer than its own resolution, and pretending
        // otherwise would hand the correction step a number it did not measure.
        let below = Double(deltas.filter { $0 <= 0 }.count) / Double(deltas.count)
        let above = Double(deltas.filter { $0 >= 0 }.count) / Double(deltas.count)
        let p = max(1 / Double(deltas.count), min(1, 2 * min(below, above)))

        /// 95% percentile interval.
        func percentile(_ p: Double) -> Double {
            let index = Int((Double(deltas.count - 1) * p).rounded())
            return deltas[max(0, min(deltas.count - 1, index))]
        }
        return result(low: percentile(0.025), high: percentile(0.975), p: p)
    }
}
