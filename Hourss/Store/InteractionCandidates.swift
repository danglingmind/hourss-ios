import Foundation

/// Where layer 2.5's questions come from, and — mostly — where they go to die.
///
/// A conjunction search is a search over a product, and products are large. Four
/// families with a handful of values each give a few hundred two-way cells before
/// anyone has looked at a rating, and the smallest cells carry the biggest
/// apparent effects. Testing all of them would not be expensive so much as
/// self-defeating: every hypothesis entered into the correction costs power for
/// the ones that are real, so an unbounded search is a way of guaranteeing that
/// nothing survives it.
///
/// So this file is a pipeline of refusals, in the order §6.2 sets out and for the
/// reason it gives — cheapest first, so the expensive gate never runs on a
/// candidate a cheap one could have rejected:
///
/// 1. **Main-effect tree gating.** A conjunction whose parts say nothing on their
///    own is not asked about. This is the only stage that prunes the *space*
///    rather than the candidates, and it is what keeps the other two affordable.
/// 2. **Day pre-screening.** Four cells, six distinct days each. Sessions are not
///    the unit: six sessions on one Tuesday are one day of evidence.
/// 3. **The lift gate.** Whether the conjunction says anything its parts do not.
///
/// Nothing here decides what is *true*. `Statistics` does the arithmetic and the
/// correction step decides what survives having asked; this decides only what is
/// worth asking, which is a smaller and more consequential job than it sounds.
enum InteractionCandidates {

    // MARK: - Factors

    /// The conditions worth combining, drawn from the record rather than declared.
    ///
    /// Only values the person actually has. A factor nobody matches would produce
    /// a candidate whose cells are empty, which is a refusal that costs a slot in
    /// the budget to arrive at — and the budget is the scarce thing here.
    ///
    /// Health splits at the person's own median, computed exactly as
    /// `HypothesisRegistry` computes it: over days carrying both a value and a
    /// rating. A factor that split at a different point from its own main effect
    /// would be gated by evidence about a different population than the one it
    /// then goes on to describe.
    static func factors(in observations: [EngineObservation]) -> [Factor] {
        var out: [Factor] = []

        let buckets = Set(observations.map(\.timeBucket))
        for bucket in TimeBucket.allCases where buckets.contains(bucket) {
            out.append(Factor(family: .time, value: bucket.rawValue) { $0.timeBucket == bucket })
        }

        for name in Set(observations.map(\.activityName)).sorted() {
            out.append(Factor(family: .activity, value: HypothesisRegistry.slug(name)) {
                $0.activityName == name
            })
        }

        let lengths = Set(observations.map(\.durationBucket))
        for bucket in DurationBucket.allCases where lengths.contains(bucket) {
            out.append(Factor(family: .duration, value: bucket.rawValue) { $0.durationBucket == bucket })
        }

        // Both sides, or neither. Somebody who only ever logs on workdays has no
        // contrast to draw, and a factor matching everything is not a condition.
        if observations.contains(where: \.isWorkday), observations.contains(where: { !$0.isWorkday }) {
            out.append(Factor(family: .workday, value: "non") { !$0.isWorkday })
            out.append(Factor(family: .workday, value: "work") { $0.isWorkday })
        }

        // Both sides of a split, here and for workdays, because the lift gate is
        // one-sided: `lift >= minimumLift` and never `abs(lift)`. The lift of
        // `A ∩ high` is the exact negation of the lift of `A ∩ low`, so generating
        // both is what lets an interaction that runs *downward* be found at all —
        // it arrives as the positive lift on the complementary factor. Time,
        // activity and duration have no complementary factor to offer, since their
        // "not this" side is a mixture rather than a condition, so a downward
        // interaction on those is only reachable through whichever sibling value
        // happens to carry it. That is a real gap and it belongs to the gate's
        // one-sidedness rather than to this function.
        for metric in HealthMetric.allCases.filter(\.isDailyContext) {
            guard let median = median(of: metric, in: observations) else { continue }
            out.append(Factor(family: .health, value: "\(metric.rawValue).high") {
                ($0.dayHealth[metric] ?? .nan) >= median
            })
            out.append(Factor(family: .health, value: "\(metric.rawValue).low") {
                ($0.dayHealth[metric] ?? .nan) < median
            })
        }

        return out
    }

    /// The person's own median for a metric, over days that could contribute to a
    /// comparison at all. Mirrors `HypothesisRegistry.healthAssociations`,
    /// including the four-day floor: a median over three days is a number, not a
    /// split.
    private static func median(of metric: HealthMetric, in observations: [EngineObservation]) -> Double? {
        var valueByDay: [Date: Double] = [:]
        for observation in observations where observation.feeling != nil {
            if let value = observation.dayHealth[metric] { valueByDay[observation.day] = value }
        }
        let values = valueByDay.values.sorted()
        guard values.count >= 4 else { return nil }
        return values[values.count / 2]
    }

    /// Two values of the same dimension never co-occur, so their conjunction is
    /// empty by construction and asking about it is asking about nothing.
    /// Different health metrics are a different dimension each — sleep and HRV can
    /// both run high on the same day, where morning and evening cannot.
    private static func dimension(of factor: Factor) -> String {
        switch factor.family {
        case .health: "health." + metricName(in: factor.value)
        case .time, .activity, .duration, .workday: factor.family.rawValue
        }
    }

    private static func metricName(in value: String) -> String {
        value.split(separator: ".").dropLast().joined(separator: ".")
    }

    // MARK: - Main effects

    /// What layer 2 already found out about one factor.
    struct MainEffect {
        let delta: Double
        /// Survived Benjamini–Hochberg *and* was reportable on its own terms.
        let clearedLayer2: Bool

        /// How large the effect is, direction discarded. A factor that drags
        /// ratings down is as good a thing to condition on as one that lifts them.
        var strength: Double { abs(delta) }

        /// §6.2 stage 1: cleared layer 2, or met the unadjusted magnitude gate.
        ///
        /// The unadjusted arm matters more than it looks. A factor can be real and
        /// still fail the correction — that is what a correction is for — and a
        /// conjunction is a different question from its parts, so refusing to ask
        /// it because a *part* did not survive multiplicity would be inheriting a
        /// penalty from a test that was not this one.
        var hasSignal: Bool { clearedLayer2 || strength >= unadjustedMagnitudeGate }
    }

    /// Cliff's own boundary between negligible and small, used here unadjusted.
    /// The same number governs `Statistics.Magnitude.of`; it is repeated rather
    /// than derived because this is a different decision that happens to share a
    /// threshold, and tying them together would hide that.
    static let unadjustedMagnitudeGate = 0.147

    /// Layer 2's results, indexed by the hypothesis id a factor maps onto.
    ///
    /// Taken from `Engine.findings(for:)` rather than recomputed. Recomputing
    /// would mean two estimates of the same quantity that could disagree, and the
    /// one the gate used would not be the one the person was shown.
    static func mainEffects(from findings: [Finding]) -> [String: MainEffect] {
        findings.reduce(into: [:]) { out, finding in
            out[finding.hypothesis.id] = MainEffect(
                delta: finding.comparison.delta,
                clearedLayer2: finding.isReportable
            )
        }
    }

    /// The single-factor question a factor is the focus side of.
    ///
    /// Workday and health map two factors onto one hypothesis, because layer 2
    /// asks those as a single two-sided contrast. Cliff's δ only changes sign when
    /// the sides swap, and the gate reads magnitude, so both directions inherit
    /// the same signal — which is correct: if non-workdays differ from workdays,
    /// that fact is equally available whichever side is named first.
    static func mainEffectId(for factor: Factor, outcome: Outcome = .feeling) -> String {
        switch factor.family {
        case .time, .activity, .duration:
            "\(factor.family.rawValue).\(factor.value).vs.rest.\(outcome.rawValue)"
        case .workday:
            "workday.non.vs.work.\(outcome.rawValue)"
        case .health:
            "health.\(metricName(in: factor.value)).higher.vs.lower.\(outcome.rawValue)"
        }
    }

    // MARK: - Generation

    /// What generation decided, including what it threw away.
    ///
    /// The discarded counts are part of the output rather than a log line: the
    /// claim this layer makes for itself is that it searches a small space, and a
    /// claim about a number should carry the number.
    struct Plan {
        let factors: [Factor]
        /// Every pair that could be formed at all — same-dimension pairs excluded,
        /// since those are empty by construction and were never candidates.
        let combinatorialCount: Int
        /// Survivors of main-effect tree gating, in rank order.
        let gated: [Conjunction]
        /// What the budget allows to be tested.
        let candidates: [Conjunction]

        /// Candidates the budget refused to look at. Not a failure — a decision to
        /// look in fewer places rather than a decision to believe more easily.
        var droppedToBudget: Int { gated.count - candidates.count }
    }

    /// Two-way candidates: stage 1 of the pipeline, plus the budget.
    ///
    /// Ranked by the strength of the strongest constituent main effect, ties
    /// broken by the weaker one and then by id. Strength rather than p-value
    /// because rank here is a statement about which conjunctions are worth the
    /// power they cost, and a factor that is large but imprecisely measured is
    /// still the more interesting thing to condition on.
    static func plan(
        for observations: [EngineObservation],
        mainEffects: [String: MainEffect],
        outcome: Outcome = .feeling,
        budget: Int = InteractionBudget.maximumCandidates
    ) -> Plan {
        let factors = factors(in: observations)

        var combinatorial = 0
        var ranked: [(conjunction: Conjunction, strongest: Double, weakest: Double)] = []
        for i in factors.indices {
            for j in factors.indices where j > i {
                let (a, b) = (factors[i], factors[j])
                guard dimension(of: a) != dimension(of: b) else { continue }
                combinatorial += 1

                let first = mainEffects[mainEffectId(for: a, outcome: outcome)]
                let second = mainEffects[mainEffectId(for: b, outcome: outcome)]
                // Stage 1. A factor layer 2 never tested — for want of days, say —
                // has no signal to offer, which is not the same as having none.
                // The conjunction is thinner than the factor either way.
                guard first?.hasSignal == true || second?.hasSignal == true else { continue }

                let strengths = [first?.strength ?? 0, second?.strength ?? 0].sorted(by: >)
                ranked.append((Conjunction(factors: [a, b], outcome: outcome),
                               strengths[0], strengths[1]))
            }
        }

        ranked.sort {
            if $0.strongest != $1.strongest { return $0.strongest > $1.strongest }
            if $0.weakest != $1.weakest { return $0.weakest > $1.weakest }
            return $0.conjunction.id < $1.conjunction.id
        }

        let gated = ranked.map(\.conjunction)
        return Plan(factors: factors,
                    combinatorialCount: combinatorial,
                    gated: gated,
                    candidates: Array(gated.prefix(max(0, budget))))
    }

    // MARK: - Screening

    /// One of the four cells the interaction is estimated from.
    enum Cell: String, Equatable {
        /// A∩B — the conjunction itself.
        case within
        /// ¬A∩B — what B looks like without A.
        case withinBaseline
        /// A∩¬B — what A does elsewhere.
        case without
        /// ¬A∩¬B — neither.
        case withoutBaseline
    }

    /// Why a candidate was not measured.
    ///
    /// `Equatable` so a test can name the refusal it expected rather than asserting
    /// on a rendered string. `Screening` deliberately is not: comparing two whole
    /// screenings would mean comparing two bootstrap results for exact equality,
    /// which is a thing to want only by accident.
    enum Refusal: Equatable {
        /// A cell has no rated sessions at all. The contrast does not exist in
        /// this record, so there is no number to be wrong about — `isEstimable`
        /// in the contract's terms, and a refusal rather than a zero.
        case notEstimable(Cell)
        /// A cell exists but rests on too few distinct days. Checked before the
        /// bootstrap, because the bootstrap on a hopeless split costs exactly what
        /// it costs on a real one.
        case tooFewDays(Cell, days: Int)
    }

    enum Screening {
        case refused(Refusal)
        case measured(InteractionLift)

        var lift: InteractionLift? {
            if case let .measured(lift) = self { return lift }
            return nil
        }

        var refusal: Refusal? {
            if case let .refused(refusal) = self { return refusal }
            return nil
        }
    }

    /// Stages 2 and 3, in that order, on one candidate.
    ///
    /// The conditioning split — which factor is A and which is B — is taken from
    /// sorted key order, not from the data. `within − without` is not symmetric in
    /// A and B, so something has to choose; choosing by a property of the record
    /// would make the number move when the record grew, and an evidence line that
    /// moves for reasons unrelated to the evidence is worse than an arbitrary one.
    /// For a three-way, A is still the first key and B is the conjunction of the
    /// rest, which reduces it to the same 2×2 the contract describes.
    static func screen(
        _ conjunction: Conjunction,
        in observations: [EngineObservation],
        resamples: Int = 2000,
        minimumDays: Int = InteractionBudget.minimumDaysPerCell
    ) -> Screening {
        let cells = partition(conjunction, in: observations)

        // Each cell judged once and completely, in a fixed order, rather than
        // emptiness swept across all four and then thinness. Both refusals happen
        // before any resampling, so nothing is saved by separating them — and
        // separating them would mean a person whose conjunction rests on three
        // days was told the *other* cell was missing, which is true but not the
        // reason. The first cell that fails names the refusal.
        //
        // Empty and thin are different answers and are reported differently.
        // "You have never done this outside the morning" is a fact about how
        // somebody works and no amount of logging changes it; "you have done it on
        // four mornings" is a fact about how much they have logged so far.
        for (cell, group) in cells.inOrder {
            if group.values.isEmpty { return .refused(.notEstimable(cell)) }
            if group.days.count < minimumDays {
                return .refused(.tooFewDays(cell, days: group.days.count))
            }
        }

        let within = Statistics.compare(focus: cells.within.values,
                                        baseline: cells.withinBaseline.values,
                                        resamples: resamples)
        let without = Statistics.compare(focus: cells.without.values,
                                         baseline: cells.withoutBaseline.values,
                                         resamples: resamples)
        let combined = Statistics.compare(focus: cells.within.values,
                                          baseline: cells.without.values
                                            + cells.withinBaseline.values
                                            + cells.withoutBaseline.values,
                                          resamples: resamples)

        return .measured(InteractionLift(within: within,
                                         without: without,
                                         lift: within.delta - without.delta,
                                         isEstimable: true,
                                         combined: combined))
    }

    // MARK: - The layer

    /// Every interaction this record supports asking about, tested.
    ///
    /// Three-way candidates are built from two-way ones that showed signal, which
    /// is §6.2's "both constituent 2-way components" read literally: a three-way
    /// exists only where two of its own two-way components each cleared the lift
    /// gate on their own. That is a strong requirement and it is meant to be. The
    /// third factor triples the number of cells needing six days apiece, so a
    /// three-way is expensive in exactly the currency — power — that the budget
    /// exists to conserve.
    ///
    /// `survivesCorrection` is left nil. Interactions are corrected separately,
    /// under a procedure valid for dependent tests, and that is not this file's
    /// job to guess at.
    static func findings(
        for input: EngineInput,
        mainEffects: [String: MainEffect],
        outcome: Outcome = .feeling,
        resamples: Int = 2000,
        budget: Int = InteractionBudget.maximumCandidates
    ) -> [InteractionFinding] {
        let observations = input.observations
        // The two-way pass is not allowed to spend the whole budget. Measured on
        // the cohort it fills every slot on anybody with a real main effect — the
        // "activity vs everything else" family means one dominant activity gives
        // every *other* activity a large contrast — and a layer whose three-way
        // arm is unreachable in practice does not have a three-way arm. The
        // reserve is a quarter; whatever the two-way pass leaves unspent is added
        // to it, so the cap on tests run is still `budget` exactly.
        let twoWayBudget = budget - budget / 4
        let twoWay = plan(for: observations, mainEffects: mainEffects,
                          outcome: outcome, budget: twoWayBudget)

        var out: [InteractionFinding] = []
        var withSignal: [Conjunction] = []
        for candidate in twoWay.candidates {
            guard let lift = screen(candidate, in: observations, resamples: resamples).lift else { continue }
            out.append(finding(candidate, lift: lift, in: input))
            if lift.lift >= InteractionLift.minimumLift { withSignal.append(candidate) }
        }

        // The cap is on hypotheses *tested*, not on hypotheses of each arity: the
        // correction does not care what shape a test had.
        let remaining = max(0, budget - twoWay.candidates.count)
        for candidate in threeWay(from: withSignal, outcome: outcome).prefix(remaining) {
            guard let lift = screen(candidate, in: observations, resamples: resamples).lift else { continue }
            out.append(finding(candidate, lift: lift, in: input))
        }
        return out
    }

    /// Pairs of signal-bearing two-ways sharing exactly one factor. Deduplicated
    /// by id, since {A,B} joined with {A,C} and {A,C} joined with {B,C} name the
    /// same three-way, and asking it twice would pay for it twice.
    static func threeWay(from twoWays: [Conjunction], outcome: Outcome = .feeling) -> [Conjunction] {
        var seen: Set<String> = []
        var out: [Conjunction] = []
        for i in twoWays.indices {
            for j in twoWays.indices where j > i {
                let keys = Set(twoWays[i].factors.map(\.key))
                    .union(twoWays[j].factors.map(\.key))
                guard keys.count == 3 else { continue }
                var factors = twoWays[i].factors
                for factor in twoWays[j].factors where !factors.contains(where: { $0.key == factor.key }) {
                    factors.append(factor)
                }
                let conjunction = Conjunction(factors: factors, outcome: outcome)
                if seen.insert(conjunction.id).inserted { out.append(conjunction) }
            }
        }
        return out
    }

    private static func finding(
        _ conjunction: Conjunction,
        lift: InteractionLift,
        in input: EngineInput
    ) -> InteractionFinding {
        let cells = partition(conjunction, in: input.observations)
        let days = cells.within.days.union(cells.withinBaseline.days)
            .union(cells.without.days).union(cells.withoutBaseline.days)
        return InteractionFinding(
            conjunction: conjunction,
            interaction: lift,
            focusSessionIds: cells.within.sessionIds,
            baselineSessionIds: cells.withinBaseline.sessionIds
                + cells.without.sessionIds + cells.withoutBaseline.sessionIds,
            windowDays: min(input.windowDays, span(of: days)),
            survivesCorrection: nil
        )
    }

    // MARK: - Cells

    struct Group {
        var values: [Statistics.Observation] = []
        var sessionIds: [UUID] = []
        var days: Set<Date> = []
    }

    struct Cells {
        var within = Group()
        var withinBaseline = Group()
        var without = Group()
        var withoutBaseline = Group()

        /// Cheapest refusal first is only meaningful if the cells are examined in
        /// a fixed order, and a fixed order is what makes the refusal *reported*
        /// reproducible as well as the decision.
        var inOrder: [(Cell, Group)] {
            [(.within, within), (.withinBaseline, withinBaseline),
             (.without, without), (.withoutBaseline, withoutBaseline)]
        }
    }

    /// The 2×2 the interaction is read off, over rated sessions only.
    ///
    /// Unrated sessions are dropped here rather than filled. The scale means
    /// nothing if absence is silently given a value, and a cell whose ratings are
    /// missing is a thin cell — which the day gate already knows how to refuse.
    static func partition(_ conjunction: Conjunction, in observations: [EngineObservation]) -> Cells {
        let sorted = conjunction.factors.sorted { $0.key < $1.key }
        guard let a = sorted.first else { return Cells() }
        let rest = Array(sorted.dropFirst())

        var cells = Cells()
        for observation in observations {
            guard let value = observation.value(of: conjunction.outcome) else { continue }
            let inA = a.matches(observation)
            let inB = rest.allSatisfy { $0.matches(observation) }
            let entry = Statistics.Observation(day: observation.day, value: value)
            switch (inA, inB) {
            case (true, true): cells.within.add(entry, observation)
            case (false, true): cells.withinBaseline.add(entry, observation)
            case (true, false): cells.without.add(entry, observation)
            case (false, false): cells.withoutBaseline.add(entry, observation)
            }
        }
        return cells
    }

    /// Calendar days from the first piece of evidence to the last, inclusive.
    private static func span(of days: Set<Date>) -> Int {
        guard let first = days.min(), let last = days.max() else { return 0 }
        return Int(last.timeIntervalSince(first) / 86_400) + 1
    }
}

private extension InteractionCandidates.Group {
    mutating func add(_ entry: Statistics.Observation, _ observation: EngineObservation) {
        values.append(entry)
        sessionIds.append(observation.sessionId)
        days.insert(observation.day)
    }
}
