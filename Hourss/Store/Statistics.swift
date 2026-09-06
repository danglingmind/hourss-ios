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
    ///
    /// Sorting the baseline once and binary-searching each focus rating into it
    /// costs O((n + m) log m), where comparing every pair costs O(n·m). At three
    /// hundred ratings a side that is the difference between a phone spending a
    /// moment on the registry and spending a minute on it.
    static func cliffsDelta(focus: [Double], baseline: [Double]) -> Double {
        guard !focus.isEmpty, !baseline.isEmpty else { return 0 }
        let sorted = baseline.sorted()
        var above = 0, below = 0
        for f in focus {
            let lower = lowerBound(sorted, f)
            above += lower
            below += sorted.count - upperBound(sorted, f, from: lower)
        }
        return Double(above - below) / Double(focus.count * baseline.count)
    }

    /// First position at or after which every value is ≥ `target`; equivalently,
    /// how many values sit strictly below it.
    private static func lowerBound(_ sorted: [Double], _ target: Double) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < target { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// First position holding a value strictly greater than `target`. The gap
    /// between this and the lower bound is the run of ties, which Cliff's delta
    /// credits to neither side.
    private static func upperBound(_ sorted: [Double], _ target: Double, from start: Int) -> Int {
        var low = start, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] <= target { low = mid + 1 } else { high = mid }
        }
        return low
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

        // Sorted rather than merely listed: dictionary order is not stable between
        // launches, so drawing days in key order would hand the same history a
        // different interval each time the app started.
        let days = byDay.keys.sorted()
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

        // The one sort the bootstrap needs, lifted clear of the loop. Every
        // resampled baseline is drawn from these same values, so the order of the
        // scale — and each focus rating's place on it — is settled once here
        // rather than two thousand times below.
        let scale = Array(Set(baselineValues)).sorted()
        let dayCount = days.count

        // Days flattened into one array per kind, each day owning a range. A day's
        // ratings are visited four thousand times per comparison, and every visit
        // to an array nested inside another is a retain and a release.
        var baselineRank: [Int] = []    // where each baseline rating sits on the scale
        var focusLow: [Int] = []        // scale positions strictly below a focus rating
        var focusHigh: [Int] = []       // positions at or below it; the gap is the ties
        var baselineStart: [Int] = [0]
        var focusStart: [Int] = [0]
        for day in days {
            let bucket = byDay[day] ?? ([], [])
            for value in bucket.baseline { baselineRank.append(lowerBound(scale, value)) }
            for value in bucket.focus {
                let low = lowerBound(scale, value)
                focusLow.append(low)
                focusHigh.append(upperBound(scale, value, from: low))
            }
            baselineStart.append(baselineRank.count)
            focusStart.append(focusLow.count)
        }

        var rng = Seeded(seed: seed)
        var deltas: [Double] = []
        deltas.reserveCapacity(resamples)

        // Reused across resamples rather than reallocated. `fewerThan[j]` ends each
        // pass holding how many drawn baseline ratings fall below scale position
        // *j*; `times[d]` is how often day *d* came up in the draw.
        var fewerThan = [Int](repeating: 0, count: scale.count + 1)
        var times = [Int](repeating: 0, count: dayCount)

        // The inner loops are written as `while` rather than `for i in a..<b`
        // deliberately. A debug build does not optimise range iteration away, and
        // this loop body runs tens of millions of times across a full registry.
        for _ in 0..<resamples {
            var i = 0
            while i <= scale.count { fewerThan[i] = 0; i += 1 }
            var d = 0
            while d < dayCount { times[d] = 0; d += 1 }
            d = 0
            while d < dayCount {
                // Multiply-and-take-the-high-word draws a day in one multiply.
                // Its bias is on the order of one part in 2^64, which no bootstrap
                // of two thousand resamples could notice.
                times[Int(rng.next().multipliedFullWidth(by: UInt64(dayCount)).high)] += 1
                d += 1
            }

            d = 0
            while d < dayCount {
                let drawn = times[d]
                if drawn > 0 {
                    var i = baselineStart[d]
                    let end = baselineStart[d + 1]
                    while i < end { fewerThan[baselineRank[i] + 1] += drawn; i += 1 }
                }
                d += 1
            }
            var j = 1
            while j <= scale.count { fewerThan[j] += fewerThan[j - 1]; j += 1 }
            let baselineDrawn = fewerThan[scale.count]

            // A resample that empties one side carries no information about the
            // difference; dropping it is standard and does not bias the interval.
            guard baselineDrawn > 0 else { continue }

            var exceeded = 0, fellShort = 0, focusDrawn = 0
            d = 0
            while d < dayCount {
                let drawn = times[d]
                if drawn > 0 {
                    var i = focusStart[d]
                    let end = focusStart[d + 1]
                    while i < end {
                        exceeded += drawn * fewerThan[focusLow[i]]
                        fellShort += drawn * (baselineDrawn - fewerThan[focusHigh[i]])
                        i += 1
                    }
                    focusDrawn += drawn * (end - focusStart[d])
                }
                d += 1
            }
            guard focusDrawn > 0 else { continue }
            deltas.append(Double(exceeded - fellShort) / Double(focusDrawn * baselineDrawn))
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
