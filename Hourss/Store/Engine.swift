import CryptoKit
import Foundation

/// Tests every hypothesis in the registry, corrects for having tested many, and
/// phrases whatever is left.
///
/// The engine knows nothing about time of day, activities or sleep. It receives
/// questions from `HypothesisRegistry`, answers them with `Statistics`, and drops
/// most of the answers on the floor. Most of what it does is refuse to speak.
enum Engine {

    /// The false-discovery rate Benjamini–Hochberg is held to.
    ///
    /// Q = 0.10 means that among the claims that survive, we accept that around
    /// one in ten is noise. The conventional 0.05 is a clinical-trial number,
    /// chosen where a false positive puts a drug on the market; this is a personal
    /// journal, where a false positive is one sentence in a feed that the person
    /// can disagree with and hide, and where being too strict has its own cost —
    /// a real pattern withheld for another month is also a failure. A permissive
    /// rate is defensible here. It is not defensible unstated, which is why the
    /// number is named once, in a constant, with this paragraph attached.
    static let falseDiscoveryRate = 0.10

    // MARK: - Entry point

    static func run(_ input: EngineInput, resamples: Int = 2000) -> [Insight] {
        let tested = findings(for: input, resamples: resamples)
        let corrected = applyingCorrection(to: tested)
        return corrected
            .filter(\.isReportable)
            .map { insight(from: $0, input: input) }
            // `Confidence` reserves everything below 50 for the engine's own use:
            // "not enough yet" is a state the feed has, not a card it shows.
            .filter { $0.band != .internalOnly }
            .sorted { rank($0, priorities: input.priorities) > rank($1, priorities: input.priorities) }
    }

    // MARK: - Testing

    /// Every hypothesis that had enough evidence to be *tested at all*.
    ///
    /// A hypothesis that never cleared `minimumDays` produces no finding and never
    /// enters the correction. This is the difference between a question asked and
    /// a question skipped, and conflating them would make the engine quieter every
    /// time someone added an activity they rarely log.
    static func findings(for input: EngineInput, resamples: Int = 2000) -> [Finding] {
        let observations = input.observations
        return HypothesisRegistry.hypotheses(for: observations).compactMap { hypothesis in
            let focus = side(hypothesis.focus, of: hypothesis, in: observations)
            let baseline = side(hypothesis.baseline, of: hypothesis, in: observations)

            // Days, not sessions, and checked before resampling: the bootstrap on
            // a hopeless split costs the same as the bootstrap on a real one.
            guard focus.days.count >= hypothesis.minimumDays,
                  baseline.days.count >= hypothesis.minimumDays else { return nil }

            let comparison = Statistics.compare(
                focus: focus.rated,
                baseline: baseline.rated,
                resamples: resamples
            )

            let days = focus.days.union(baseline.days)
            return Finding(
                hypothesis: hypothesis,
                comparison: comparison,
                focusSessionIds: focus.sessionIds,
                baselineSessionIds: baseline.sessionIds,
                focusCoverage: focus.coverage,
                baselineCoverage: baseline.coverage,
                survivesCorrection: nil,
                windowDays: min(input.windowDays, span(of: days))
            )
        }
    }

    private struct Side {
        var rated: [Statistics.Observation] = []
        var sessionIds: [UUID] = []
        var days: Set<Date> = []
        var matched = 0
        /// Share of matching sessions that carried a rating at all.
        var coverage: Double { matched == 0 ? 0 : Double(rated.count) / Double(matched) }
    }

    private static func side(
        _ predicate: (EngineObservation) -> Bool,
        of hypothesis: Hypothesis,
        in observations: [EngineObservation]
    ) -> Side {
        var side = Side()
        for observation in observations where predicate(observation) {
            side.matched += 1
            guard let value = observation.value(of: hypothesis.outcome) else { continue }
            side.rated.append(.init(day: observation.day, value: value))
            side.sessionIds.append(observation.sessionId)
            side.days.insert(observation.day)
        }
        return side
    }

    /// Calendar days from the first piece of evidence to the last, inclusive.
    private static func span(of days: Set<Date>) -> Int {
        guard let first = days.min(), let last = days.max() else { return 0 }
        return Int(last.timeIntervalSince(first) / 86_400) + 1
    }

    // MARK: - Correction

    /// Benjamini–Hochberg, over every hypothesis this run actually tested.
    ///
    /// Twenty questions asked at a 5% tail each will hand back a confident answer
    /// to one of them from noise alone, and the old engine asked sixteen without
    /// ever accounting for it. BH controls the expected *share* of surviving
    /// claims that are false rather than the chance of any false claim at all,
    /// which is the right guarantee for a feed: it stays sensitive as the registry
    /// grows, where Bonferroni would go mute the moment someone logged a tenth
    /// activity.
    ///
    /// `m` is the number of findings passed in — tests run, not questions
    /// conceivable. Correcting for a hypothesis that was skipped for want of days
    /// would pay a penalty for evidence nobody looked at.
    ///
    /// Where this earns its keep is thin histories. Measured over noise, layer 1's
    /// own reportability gate lets nothing through at ninety days by three
    /// sessions, and roughly one run in twenty through at twenty days by four — so
    /// the correction does almost nothing for someone with a long history and
    /// nearly all of the work for someone who just started, which is precisely the
    /// person v1 handed four confident claims off eighteen days.
    static func applyingCorrection(
        to findings: [Finding],
        q: Double = falseDiscoveryRate
    ) -> [Finding] {
        let m = findings.count
        guard m > 0 else { return [] }

        // Ranked by p-value, ties broken by id so the same data always corrects
        // the same way.
        let ranked = findings.indices.sorted {
            let (a, b) = (findings[$0], findings[$1])
            if a.comparison.pValue != b.comparison.pValue {
                return a.comparison.pValue < b.comparison.pValue
            }
            return a.hypothesis.id < b.hypothesis.id
        }

        // The largest k whose p-value still sits under its own threshold. Every
        // rank below k survives with it, including any that failed their own
        // threshold — that step-up is what separates BH from testing each
        // hypothesis on its own.
        var cutoff = 0
        for (index, finding) in ranked.enumerated() {
            let k = index + 1
            if findings[finding].comparison.pValue <= Double(k) / Double(m) * q { cutoff = k }
        }

        var corrected = findings
        for (index, finding) in ranked.enumerated() {
            corrected[finding].survivesCorrection = index + 1 <= cutoff
        }
        return corrected
    }

    // MARK: - Confidence

    /// The number the UI bands into "Strong pattern" / "Emerging" / "Still
    /// watching".
    ///
    /// This is a presentation device over the interval, not a probability, and
    /// nothing downstream should treat it as one. It is monotone in exactly two
    /// things:
    ///
    /// - **separation** — how far the near edge of the interval sits from zero,
    ///   which is the *smallest* effect the data is still consistent with;
    /// - **precision** — how narrow the interval is, since a tight small effect is
    ///   better pinned down than a wide large one.
    ///
    /// It is monotone in neither session count nor day count. The old formula
    /// added up to thirty points for volume alone, so a person who logged a lot
    /// and had no pattern scored 72 — "Emerging" — off an effect of exactly zero.
    /// Volume already reaches this number the only way it legitimately can, by
    /// narrowing the interval.
    ///
    /// Two guards sit above the arithmetic, and both are structural rather than a
    /// matter of tuning: an interval containing zero, and an interval that reaches
    /// into Cliff's negligible band, each return a value below the visible floor
    /// of 50. No choice of weights below them can make "the data is consistent
    /// with no difference" or "the smallest effect this data supports is one
    /// nobody would notice" render as a band.
    static func confidence(_ comparison: Statistics.Comparison) -> Int {
        // The data is consistent with no difference at all.
        guard !comparison.spansZero else { return 40 }

        // Near edge of the interval. `spansZero` is already false, so both bounds
        // sit on the same side of zero and the smaller magnitude is the near one:
        // the smallest effect the data is still consistent with.
        let edge = min(abs(comparison.low), abs(comparison.high))

        // The interval clears zero but reaches into the negligible band, so the
        // smallest effect still consistent with this data is one nobody would
        // notice. `Comparison.isReportable` asks the same question of the point
        // estimate; asking it of the interval instead is the entire argument for
        // carrying an interval, and it is what separates a real effect from a
        // difference that merely happens to sit on one side of zero.
        guard Statistics.Magnitude.of(edge) != .negligible else { return 45 }

        // 0.474 is Cliff's threshold for a large effect: an interval whose *near*
        // edge is already large has nothing left to earn.
        let separation = min(1, edge / 0.474)
        // A quarter of the −1…1 range is about as wide as an interval can be while
        // still saying anything; anything wider scores zero here rather than
        // negative. Note the ordering: precision is read only after both guards
        // have passed, because the tightest interval `Statistics` can return is a
        // zero-width one at zero — perfect precision about nothing at all.
        let precision = 1 - min(1, comparison.width / 0.5)

        return 50 + Int(((0.65 * separation + 0.35 * precision) * 45).rounded())
    }

    // MARK: - Phrasing

    private static func insight(from finding: Finding, input: EngineInput) -> Insight {
        let hypothesis = finding.hypothesis
        let comparison = finding.comparison

        return Insight(
            id: identity(of: hypothesis.id),
            type: resolvedType(for: finding),
            statement: hypothesis.phrase(finding),
            evidence: .init(
                comparisonLabel: hypothesis.focusLabel,
                comparisonValue: mean(finding.focusSessionIds, in: input, outcome: hypothesis.outcome),
                comparisonCount: finding.focusSessionIds.count,
                baselineLabel: hypothesis.baselineLabel,
                baselineValue: mean(finding.baselineSessionIds, in: input, outcome: hypothesis.outcome),
                baselineCount: finding.baselineSessionIds.count,
                windowDescription: describe(windowDays: finding.windowDays),
                sessionIds: finding.focusSessionIds + finding.baselineSessionIds
            ),
            confidence: confidence(comparison),
            status: .visible,
            generatedAt: input.generatedAt,
            caveat: caveat(for: finding),
            experiment: hypothesis.experiment
        )
    }

    /// A hypothesis declares the positive pole of a matched pair; the evidence
    /// decides which of the two it turned out to be.
    private static func resolvedType(for finding: Finding) -> InsightType {
        guard finding.comparison.delta < 0,
              finding.hypothesis.outcome.higherIsBetter == true,
              let opposite = finding.hypothesis.type.oppositeDirection else {
            return finding.hypothesis.type
        }
        return opposite
    }

    /// The two numbers on the evidence line.
    ///
    /// Means, and descriptive only: nothing was decided by them. The claim rests
    /// on Cliff's delta, which does not assume the 1–5 scale is evenly spaced —
    /// but "0.41 vs −0.41" is not a thing to show anyone, and a person reading
    /// their own feed can check a pair of averages against their memory.
    private static func mean(_ ids: [UUID], in input: EngineInput, outcome: Outcome) -> Double {
        let wanted = Set(ids)
        let values = input.observations
            .filter { wanted.contains($0.sessionId) }
            .compactMap { $0.value(of: outcome) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// What the evidence actually spans, in the coarsest unit that does not
    /// overstate it. The old engine printed "past 6 weeks" on eighteen days.
    static func describe(windowDays days: Int) -> String {
        switch days {
        case ..<1: "no window"
        case 1: "past day"
        // Days up to three weeks. Rounding eighteen days to "2 weeks" loses a
        // quarter of the evidence in the telling; a person reading their own feed
        // can hold a two-digit number of days.
        case ..<21: "past \(days) days"
        case ..<70: "past \(Int((Double(days) / 7).rounded())) weeks"
        default: "past \(Int((Double(days) / 30.4).rounded())) months"
        }
    }

    private static func caveat(for finding: Finding) -> String {
        guard finding.hasUnevenCoverage else { return finding.hypothesis.caveat }
        // Not a footnote about tidiness: when one side is rated far more often
        // than the other, the two groups differ in who chose to rate them as well
        // as in the condition being compared, and part of the gap may be that.
        return finding.hypothesis.caveat
            + " The two sides were rated at different rates, so some of this gap may be which sessions got a rating."
    }

    // MARK: - Identity

    /// The insight's UUID, derived from the hypothesis id and nothing else.
    ///
    /// Same question, same id, every run — which is the whole reason saved and
    /// hidden state can survive a recomputation. The old engine minted a fresh
    /// UUID per rebuild, so granting health access silently emptied everything the
    /// person had saved.
    static func identity(of hypothesisId: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data("hourss.insight.\(hypothesisId)".utf8)).prefix(16))
        // Stamped as a version 5 (name-based) UUID, which is what this is.
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3],
                           digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11],
                           digest[12], digest[13], digest[14], digest[15]))
    }

    // MARK: - Ordering

    /// Feed order: confidence, nudged by what the person said they wanted to work
    /// on. Priorities move a claim up the feed; they never decide whether it is
    /// true, and nothing is filtered out for failing to match one.
    private static func rank(_ insight: Insight, priorities: [Priority]) -> Double {
        var score = Double(insight.confidence)
        if let position = priorities.firstIndex(where: { $0.insightTypes.contains(insight.type) }) {
            score += Double(max(0, 6 - position))
        }
        return score
    }
}
