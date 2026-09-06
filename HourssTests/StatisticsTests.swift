import Testing
import Foundation
@testable import Hourss

/// What layer 1 owes the rest of the engine.
///
/// Two kinds of test live here. The first kind checks Cliff's delta against
/// answers worked out by hand, pair by pair, because a statistic verified only
/// against itself can be confidently wrong. The second kind checks the properties
/// the redesign exists for: that noise produces an interval spanning zero, that a
/// fortnight of data is admitted to be thinner evidence than three months, and
/// that six sessions on one day are not counted as six days' worth.
@Suite("Cliff's delta and its bootstrap")
struct StatisticsTests {

    // MARK: - Known answers

    @Test("Complete separation is +1")
    func completeSeparation() {
        #expect(Statistics.cliffsDelta(focus: [4, 5], baseline: [1, 2]) == 1.0)
    }

    @Test("Complete separation the other way is −1")
    func reverseSeparation() {
        #expect(Statistics.cliffsDelta(focus: [1, 2], baseline: [4, 5]) == -1.0)
    }

    @Test("Identical groups are zero")
    func identicalGroups() {
        #expect(Statistics.cliffsDelta(focus: [1, 2, 3], baseline: [1, 2, 3]) == 0.0)
    }

    @Test("All ties are zero, not one")
    func allTies() {
        // Every pair ties, so neither side is credited and the numerator is empty.
        #expect(Statistics.cliffsDelta(focus: [3, 3], baseline: [3, 3]) == 0.0)
    }

    @Test("A worked asymmetric case")
    func workedAsymmetricCase() {
        // focus [2, 5] against baseline [1, 3, 3, 4], all eight pairs:
        //   2 > 1 above;  2 < 3 below;  2 < 3 below;  2 < 4 below
        //   5 > 1 above;  5 > 3 above;  5 > 3 above;  5 > 4 above
        // five above, three below, eight pairs: (5 − 3) / 8 = 0.25
        #expect(Statistics.cliffsDelta(focus: [2, 5], baseline: [1, 3, 3, 4]) == 0.25)
    }

    @Test("Ties across the two groups count for neither side")
    func tiesAcrossGroups() {
        // focus [3, 5] against baseline [1, 3, 3, 4]:
        //   3 > 1 above;  3 = 3 tie;    3 = 3 tie;    3 < 4 below
        //   5 > 1 above;  5 > 3 above;  5 > 3 above;  5 > 4 above
        // five above, one below, two ties; the ties stay in the denominator only:
        // (5 − 1) / 8 = 0.5
        #expect(Statistics.cliffsDelta(focus: [3, 5], baseline: [1, 3, 3, 4]) == 0.5)
    }

    @Test("Single-element groups")
    func singleElementGroups() {
        #expect(Statistics.cliffsDelta(focus: [5], baseline: [1]) == 1.0)
        #expect(Statistics.cliffsDelta(focus: [1], baseline: [5]) == -1.0)
        #expect(Statistics.cliffsDelta(focus: [3], baseline: [3]) == 0.0)
    }

    @Test("An empty side is no evidence, not a perfect effect")
    func emptySide() {
        #expect(Statistics.cliffsDelta(focus: [], baseline: [1, 2]) == 0.0)
        #expect(Statistics.cliffsDelta(focus: [1, 2], baseline: []) == 0.0)
    }

    @Test("Repeated values do not disturb the binary search")
    func heavilyTiedGroups() {
        // focus [1, 1, 1] against baseline [1, 1]: six pairs, every one a tie.
        #expect(Statistics.cliffsDelta(focus: [1, 1, 1], baseline: [1, 1]) == 0.0)
        // focus [1, 2] against baseline [2, 2, 2]: 1 is below all three, 2 ties
        // all three: (0 − 3) / 6 = −0.5
        #expect(Statistics.cliffsDelta(focus: [1, 2], baseline: [2, 2, 2]) == -0.5)
    }

    // MARK: - What the interval is for

    @Test("Noise spans zero")
    func noiseSpansZero() {
        let (focus, baseline) = groups(days: 40, perDay: 4, focusCentre: 3, baselineCentre: 3)
        let result = Statistics.compare(focus: focus, baseline: baseline)
        #expect(result.spansZero, Comment(rawValue:
                "two samples of the same distribution gave [\(result.low), \(result.high)]"))
        #expect(!result.isReportable)
    }

    @Test("A large real effect clears zero")
    func realEffectClearsZero() {
        let (focus, baseline) = groups(days: 40, perDay: 4, focusCentre: 4.6, baselineCentre: 1.4)
        let result = Statistics.compare(focus: focus, baseline: baseline)
        #expect(!result.spansZero, Comment(rawValue:
                "a separation across 40 days gave [\(result.low), \(result.high)]"))
        #expect(result.low > 0)
        #expect(result.magnitude == .large)
        #expect(result.isReportable)
    }

    @Test("Fewer days widen the interval")
    func fewerDaysWidenTheInterval() {
        // The same effect, the same ratings per day; only the number of days
        // differs. This is the property that stops a fortnight of logging
        // outranking three months of it.
        let brief = Statistics.compare(
            focus: groups(days: 6, perDay: 4, focusCentre: 3.4, baselineCentre: 2.6).focus,
            baseline: groups(days: 6, perDay: 4, focusCentre: 3.4, baselineCentre: 2.6).baseline)
        let long = Statistics.compare(
            focus: groups(days: 40, perDay: 4, focusCentre: 3.4, baselineCentre: 2.6).focus,
            baseline: groups(days: 40, perDay: 4, focusCentre: 3.4, baselineCentre: 2.6).baseline)
        #expect(brief.width > long.width, Comment(rawValue:
                "6 days gave width \(brief.width), 40 days gave \(long.width)"))
    }

    @Test("Concentrated days widen the interval, at equal observation count")
    func dayClusteringWidensTheInterval() {
        // Sixty ratings a side either way. The concentrated history has to come
        // out wider, or same-day sessions are still being counted as independent.
        //
        // Five days rather than three: at fewer than four days `compare` refuses
        // to resample at all and returns [−1, 1], which would pass this test for
        // a reason that has nothing to do with clustering.
        let concentrated = groups(days: 5, perDay: 12, focusCentre: 3.4, baselineCentre: 2.6)
        let spread = groups(days: 30, perDay: 2, focusCentre: 3.4, baselineCentre: 2.6)
        let tight = Statistics.compare(focus: concentrated.focus, baseline: concentrated.baseline)
        let loose = Statistics.compare(focus: spread.focus, baseline: spread.baseline)

        #expect(tight.focusCount == loose.focusCount)
        #expect(tight.baselineCount == loose.baselineCount)
        #expect(tight.width > loose.width, Comment(rawValue:
                "5 days × 12 gave width \(tight.width), 30 days × 2 gave \(loose.width)"))
    }

    @Test("The same history gives the same interval twice")
    func determinism() {
        let (focus, baseline) = groups(days: 20, perDay: 3, focusCentre: 3.6, baselineCentre: 2.8)
        let first = Statistics.compare(focus: focus, baseline: baseline)
        let second = Statistics.compare(focus: focus, baseline: baseline)
        #expect(first.delta == second.delta)
        #expect(first.low == second.low)
        #expect(first.high == second.high)
        #expect(first.pValue == second.pValue)
    }

    @Test("Too few days claims nothing")
    func tooFewDaysClaimsNothing() {
        let (focus, baseline) = groups(days: 3, perDay: 5, focusCentre: 5, baselineCentre: 1)
        let result = Statistics.compare(focus: focus, baseline: baseline)
        #expect(result.low == -1 && result.high == 1)
        #expect(!result.isReportable)
    }

    // MARK: - The p-value the correction step ranks by

    @Test("Identical groups give a p-value of one")
    func pValueForIdenticalGroups() {
        // The same ratings on both sides, not merely the same distribution: every
        // resample then puts delta at exactly zero, both tails hold the whole
        // distribution, and the p-value can only be one.
        let (focus, _) = groups(days: 40, perDay: 4, focusCentre: 3, baselineCentre: 3)
        let result = Statistics.compare(focus: focus, baseline: focus)
        #expect(result.delta == 0.0)
        #expect(result.low == 0.0 && result.high == 0.0)
        #expect(result.pValue == 1.0)
    }

    @Test("Noise does not give a small p-value")
    func pValueForNoise() {
        // Two independent draws from one distribution. The p-value is what layer
        // 2 ranks by, so what matters here is that noise stays well clear of the
        // range where a discovery would be claimed — not that it lands near one.
        // It will not: an unlucky draw genuinely does differ a little, and the
        // interval is entitled to say so.
        let (focus, baseline) = groups(days: 40, perDay: 4, focusCentre: 3, baselineCentre: 3)
        let p = Statistics.compare(focus: focus, baseline: baseline).pValue
        #expect(p > 0.05, Comment(rawValue: "noise gave p = \(p)"))
    }

    @Test("A clean separation gives a small p-value")
    func pValueForRealEffect() {
        let (focus, baseline) = groups(days: 40, perDay: 4, focusCentre: 4.6, baselineCentre: 1.4)
        let p = Statistics.compare(focus: focus, baseline: baseline).pValue
        #expect(p < 0.01, Comment(rawValue: "separated groups gave p = \(p)"))
        // The bootstrap cannot resolve below its own resolution, and must not
        // pretend it can.
        #expect(p >= 1.0 / 2000.0)
    }

    // MARK: - What a phone can afford

    /// A full registry run must stay affordable on a phone.
    ///
    /// Measured against a calibration loop rather than the clock. Swift Testing
    /// runs suites in parallel, so wall time here depends on what else happens to
    /// be executing: the same work measured 0.77s alone and 3.90s alongside the
    /// rest of the suite. An absolute bound would pass or fail on scheduling
    /// rather than on the code, which is worse than no test — it teaches the
    /// reader to ignore a red result.
    ///
    /// A ratio against a calibration loop absorbs most of that, though measurably
    /// not all of it: 15.7x alone against 38.6x alongside the full suite, where
    /// wall time moved five-fold. The residual gap is real — the calibration is a
    /// register-bound loop while `compare` allocates, and allocation suffers more
    /// under load. So the bound is set to catch an algorithmic regression rather
    /// than to police a few percent.
    @Test("Forty hypotheses cost no more than a fixed reference workload")
    func performanceCeiling() {
        let (focus, baseline) = groups(days: 60, perDay: 4, focusCentre: 3.4, baselineCentre: 2.8)
        #expect(focus.count + baseline.count >= 400)

        // Roughly 24 million integer operations — about 45ms, comfortably above
        // any timer resolution concern and around a fifteenth of the work under
        // test. It does not need to match that duration; it needs to be affected
        // by machine load in the same proportion, which any CPU-bound loop is.
        var calibration = 0
        let reference = ContinuousClock().measure {
            var i = 0
            while i < 24_000_000 { calibration &+= i & 7; i &+= 1 }
        }
        #expect(calibration > 0)

        var sink = 0.0
        let elapsed = ContinuousClock().measure {
            var run = 0
            while run < 40 {
                sink += Statistics.compare(focus: focus, baseline: baseline).delta
                run += 1
            }
        }
        #expect(sink.isFinite)

        // 15.7x measured alone, 38.6x under a full parallel suite. The bound
        // clears both with room for a slower machine, and still catches what it
        // exists to catch: the O(n*m) implementation this replaced was 165 times
        // slower and would score in the thousands.
        let ratio = elapsed / reference
        #expect(ratio < 60, Comment(rawValue:
                "40 comparisons cost \(String(format: "%.1f", ratio))x the reference " +
                "(\(elapsed) against \(reference)); the registry runs this on every refresh"))
    }

    // MARK: - Fixtures

    /// Ratings on the 1–5 scale the app actually collects, from a fixed stream.
    ///
    /// An interval assertion is only meaningful if the data behind it is the same
    /// on every run; a test that draws fresh randomness fails one morning a month
    /// and teaches nobody anything.
    private struct Stream {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func unit() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func rating(centre: Double) -> Double {
            (min(5, max(1, centre + (unit() - 0.5) * 2))).rounded()
        }
    }

    /// Two sides logged on the same days, each side drawn about its own centre.
    private func groups(
        days: Int,
        perDay: Int,
        focusCentre: Double,
        baselineCentre: Double,
        seed: UInt64 = 0x5354_4154
    ) -> (focus: [Statistics.Observation], baseline: [Statistics.Observation]) {
        let calendar = Calendar.current
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        var stream = Stream(seed: seed)
        var focus: [Statistics.Observation] = []
        var baseline: [Statistics.Observation] = []
        for back in 0..<days {
            let day = calendar.date(byAdding: .day, value: -back, to: reference)!
            for _ in 0..<perDay {
                focus.append(.init(day: day, value: stream.rating(centre: focusCentre)))
                baseline.append(.init(day: day, value: stream.rating(centre: baselineCentre)))
            }
        }
        return (focus, baseline)
    }
}
