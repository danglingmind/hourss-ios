import Foundation

/// Multiplicity control for layer 2.5.
///
/// Layer 2 corrects single-factor hypotheses with Benjamini–Hochberg, which
/// controls the false-discovery rate under independence or positive regression
/// dependence. Neither holds here. A conjunction search tests the same sessions a
/// dozen times over — `activity.deep-work ∩ time.morning` and
/// `activity.deep-work ∩ duration.long` share most of their focus rows, and both
/// share their baseline with everything else — so the dependence is arbitrary
/// rather than merely positive, and BH's guarantee does not transfer (§10.2).
///
/// **The lift gate does not stand in for this.** The gate refuses *redundancy*: a
/// conjunction whose effect belongs entirely to one of its factors. It has nothing
/// to say about noise, and cohort measurement established that a person with no
/// interaction at all produces apparent lift above the gate's threshold. So this
/// is the only thing between the layer and inventing conjunctions for people who
/// have none, and it is treated as load-bearing rather than as a formality.
///
/// Two procedures live here, deliberately:
///
/// * **Benjamini–Yekutieli** — BH with the threshold divided by the harmonic
///   number, valid under *arbitrary* dependence. The correct assumption, at a
///   price that has to be measured rather than assumed tolerable.
/// * **Day-label permutation FDR** — permute the outcome across whole calendar
///   days and recompute the statistic, so the null is built from the same
///   co-occurrence structure the data actually has instead of from an assumption
///   about it. Days rather than sessions for the same reason the bootstrap
///   resamples days: three sessions on one Tuesday are not three pieces of
///   evidence about Tuesdays.
///
/// Neither is chosen here. `InteractionCorrectionTests` runs both over the cohort
/// and the recommendation is made against numbers.
enum InteractionCorrection {

    /// The same Q layer 2 is held to, named once in `Engine` with the paragraph
    /// justifying 0.10 attached. Interactions are corrected *separately* from main
    /// effects — a different family, a different procedure — but there is no
    /// argument for a different tolerance for being wrong.
    static let falseDiscoveryRate = Engine.falseDiscoveryRate

    /// Permutations per run, by default and at most.
    ///
    /// Each permutation recomputes every surviving candidate's lift, which is four
    /// Cliff's deltas and no resampling — cheap enough to afford several hundred of
    /// and nowhere near cheap enough to afford tens of thousands on a phone.
    ///
    /// The number is a *power* setting, not a precision setting, and that is the
    /// surprising part. No permutation p can fall below `1/(B + 1)`, so `B` decides
    /// the smallest claim the procedure is capable of making before any data is
    /// seen — and a step-up threshold of `k/m · q` at `m = 45` is 0.0022 at rank 1,
    /// which a budget of 200 cannot reach. Measured over the cohort, admissions per
    /// person:
    ///
    /// ```
    /// B      floor     real 2-way   real 3-way   noise   confounded
    /// 500    0.00200       5             0         0         0
    /// 1000   0.00100       3             0         0         0
    /// ```
    ///
    /// Doubling the budget does not buy admissions, which is the useful finding:
    /// 500 is past the point where resolution is what limits this, and the real
    /// three-way is refused for a reason `B` cannot fix. See
    /// `permutationFDR(to:observations:…)` for what that reason is.
    static let defaultPermutations = 500
    static let maximumPermutations = 2000

    // MARK: - What the step-up procedures rank by

    /// Which measured p-value a step-up procedure orders candidates on.
    ///
    /// Neither is a p-value *for the lift*, and that is a real limitation rather
    /// than a presentational one: `InteractionLift` carries three bootstrap
    /// comparisons and the frozen contract measures no null distribution for their
    /// difference. A step-up procedure needs a p, so it gets one of these, and the
    /// measurement reports both rather than picking quietly.
    enum Statistic: String, CaseIterable {
        /// The conjunction against everything outside it. The quantity the
        /// contract warns makes a confounded conjunction look strong — used for
        /// *ordering* here, never for gating, but it is still the noisier of the
        /// two and the comparison exists to show by how much.
        ///
        /// Whichever is chosen, both are blunted the same way. Measured on the
        /// cohort, 15 of 24 candidates report exactly the bootstrap's floor, and
        /// raising resamples from 2,000 to 10,000 leaves all 15 tied at the new
        /// floor — they are past the resolution limit rather than near it. Any
        /// step-up over these p-values is therefore ordering most of its input
        /// alphabetically, which is the strongest argument in this file for not
        /// using one.
        case combined
        /// The weaker of the two separations a conjunction claim needs: the
        /// conjunction against the rest, and A against ¬A among the B sessions. An
        /// intersection–union p, valid at its own level because rejecting requires
        /// every component to reject.
        case intersectionUnion

        func p(of finding: InteractionFinding) -> Double {
            switch self {
            case .combined: finding.interaction.combined.pValue
            case .intersectionUnion:
                max(finding.interaction.combined.pValue, finding.interaction.within.pValue)
            }
        }
    }

    // MARK: - Step-up procedures

    enum Procedure: String, CaseIterable {
        /// What layer 2 uses. Present only so the cost of the correct assumption
        /// can be stated as a number.
        case benjaminiHochberg
        /// Valid under arbitrary dependence, which is what a conjunction search
        /// has.
        case benjaminiYekutieli

        /// The divisor BY applies to BH's threshold.
        ///
        /// Yekutieli and Benjamini (2001) show that dividing by `H(m) = Σ 1/i`
        /// restores FDR control under *any* dependence structure. It is the price
        /// of not having to argue about which structure we have: `H(60) ≈ 4.68`,
        /// so at sixty candidates every threshold is almost five times stricter.
        func dependencePenalty(m: Int) -> Double {
            switch self {
            case .benjaminiHochberg: 1
            case .benjaminiYekutieli: harmonicNumber(m)
            }
        }
    }

    /// `H(m) = 1 + 1/2 + … + 1/m`. Summed rather than approximated: at the `m` a
    /// pruned candidate set actually reaches, the series is short and an
    /// asymptotic form would be less accurate than the thing it approximates.
    static func harmonicNumber(_ m: Int) -> Double {
        guard m > 0 else { return 1 }
        return (1...m).reduce(0.0) { $0 + 1 / Double($1) }
    }

    /// The p-value a candidate at rank `k` of `m` has to beat.
    ///
    /// Exposed because it is the number the decision turns on. At `k = 1` it is the
    /// hardest threshold in the procedure, and the bootstrap's own floor at
    /// `1/resamples` is either below it or is not — which settles whether the
    /// procedure can admit anything at all before any data is seen.
    static func threshold(rank k: Int,
                          of m: Int,
                          q: Double = falseDiscoveryRate,
                          procedure: Procedure) -> Double {
        guard m > 0 else { return 0 }
        return Double(k) / Double(m) * q / procedure.dependencePenalty(m: m)
    }

    /// Apply a step-up procedure, setting `survivesCorrection` on every finding.
    ///
    /// A candidate whose interaction was never estimable is marked `false` and is
    /// **left out of `m`**. It is not a test that failed; it is a question the four
    /// cells could not be assembled to ask, and counting it would make every real
    /// candidate pay for a comparison nobody made — the same distinction
    /// `Engine.findings` draws by never building a `Finding` at all.
    static func applying(_ procedure: Procedure,
                         to findings: [InteractionFinding],
                         statistic: Statistic = .combined,
                         q: Double = falseDiscoveryRate) -> [InteractionFinding] {
        var corrected = findings
        for index in findings.indices where !findings[index].interaction.isEstimable {
            corrected[index].survivesCorrection = false
        }

        let testable = findings.indices.filter { findings[$0].interaction.isEstimable }
        let m = testable.count
        guard m > 0 else { return corrected }

        // Ranked by p, ties broken by conjunction id so the same data always
        // corrects the same way. The tie-break carries real weight here: the
        // bootstrap p is floored at 1/resamples, so a well-separated candidate set
        // can be entirely tied and the ordering among them is then alphabetical
        // rather than statistical (§10.3).
        let ranked = testable.sorted {
            let (a, b) = (findings[$0], findings[$1])
            let (pa, pb) = (statistic.p(of: a), statistic.p(of: b))
            if pa != pb { return pa < pb }
            return a.conjunction.id < b.conjunction.id
        }

        // The largest k whose p still sits under its own threshold. Every rank
        // below k survives with it, including ranks that failed their own — that
        // step-up is what separates either procedure from testing each hypothesis
        // alone.
        var cutoff = 0
        for (index, finding) in ranked.enumerated() {
            let k = index + 1
            if statistic.p(of: findings[finding]) <= threshold(rank: k, of: m, q: q, procedure: procedure) {
                cutoff = k
            }
        }

        for (index, finding) in ranked.enumerated() {
            corrected[finding].survivesCorrection = index + 1 <= cutoff
        }
        return corrected
    }

    /// BH over interaction candidates. Not recommended for use — it is here so the
    /// cost of BY is a measured difference rather than a claim.
    static func benjaminiHochberg(_ findings: [InteractionFinding],
                                  statistic: Statistic = .combined,
                                  q: Double = falseDiscoveryRate) -> [InteractionFinding] {
        applying(.benjaminiHochberg, to: findings, statistic: statistic, q: q)
    }

    /// BY over interaction candidates.
    static func benjaminiYekutieli(_ findings: [InteractionFinding],
                                   statistic: Statistic = .combined,
                                   q: Double = falseDiscoveryRate) -> [InteractionFinding] {
        applying(.benjaminiYekutieli, to: findings, statistic: statistic, q: q)
    }

    // MARK: - Permutation FDR over day labels

    /// How a permutation run turns its null into a decision.
    ///
    /// The two answer different questions and the difference is not cosmetic.
    enum Mode: String, CaseIterable {
        /// One lift threshold for everybody, chosen so the pooled null says the
        /// expected number of false discoveries above it is within `q` of the
        /// number of discoveries. The classical empirical-FDR estimator.
        ///
        /// It assumes the candidates' nulls are on a comparable scale, and they
        /// are not: a conjunction resting on six days has a far wider null than
        /// one resting on forty, and pooling lets the thin candidates set the bar
        /// for the thick ones. Measured on the cohort it is the more erratic of
        /// the two — one admission for the real two-way person where the
        /// per-candidate mode finds five, and a threshold that moves
        /// non-monotonically as the candidate budget changes.
        case pooledThreshold
        /// Each candidate gets its **own** permutation p-value — the share of its
        /// own null lifts that reached its observed lift — and those p-values go
        /// through a step-up procedure. A candidate is then judged against the
        /// noise its own cells produce rather than against the worst cells in the
        /// search.
        ///
        /// The cost is resolution: with `B` permutations no p can fall below
        /// `1/(B+1)`, which is a coarser floor than the bootstrap's and interacts
        /// directly with how strict the step-up is.
        case perCandidateStepUp
    }

    /// What a permutation run concluded, and on what.
    ///
    /// The threshold and the estimated rate are returned rather than kept private
    /// because a correction that cannot say *what it required* is not auditable.
    struct PermutationResult {
        let findings: [InteractionFinding]
        /// The lift a candidate had to reach. Nil when no threshold met `q` — the
        /// procedure refusing everything, which is a result and not a failure.
        let liftThreshold: Double?
        /// Estimated FDR at that threshold: expected null discoveries over actual
        /// discoveries.
        let estimatedFDR: Double?
        let admitted: Int
        /// Candidates that entered the procedure. Non-estimable ones are excluded,
        /// as in the step-up procedures.
        let m: Int
        let permutations: Int
        /// Every threshold considered and what it would have cost, steepest first.
        ///
        /// A procedure that refuses everything and a procedure that had nothing to
        /// refuse look identical from the outside. This is how they are told apart:
        /// it shows the estimated rate at the strongest candidate the person has,
        /// which is the number that says whether the refusal was close or hopeless.
        let curve: [Step]

        struct Step {
            /// The candidate that sets this rung, named. A count of admissions says
            /// how loud a procedure is; only the id says whether it was loud about
            /// the right thing.
            let id: String
            let lift: Double
            let discoveries: Int
            /// Pooled mode: the estimated false-discovery rate at this threshold.
            /// Per-candidate mode: this candidate's own permutation p-value.
            let estimatedFDR: Double
        }
    }

    /// Estimate the FDR empirically by permuting the outcome across calendar days.
    ///
    /// **The defaults are the recommendation, and they are measured rather than
    /// argued.** Per-candidate permutation p-values with a BH step-up is the best
    /// arrangement measured. Over the cohort at the search's current budget:
    ///
    /// ```
    ///                        candidates   admitted   what that is
    /// scattered noise            28          0       correct — has no interaction
    /// deep work, mostly morning  37          0       correct — confounded, not an interaction
    /// morning deep work          45          5       correct — includes the planted 2-way
    /// …after sleep               39          0       a real interaction, refused
    /// ```
    ///
    /// The step-up is BH rather than BY because BY over permutation p-values admits
    /// nothing for anybody at any budget a phone can pay for: its rank-1 threshold
    /// at `m = 45` is 0.00051 and a permutation p cannot fall below `1/(B + 1)`, so
    /// BY would need `B ≥ 1974` before it could reject at rank 1 at all.
    ///
    /// **The refusal in the last row is a budget problem, not a procedure problem,
    /// and it is the one open item this file leaves.** That person's strongest
    /// candidate holds a permutation p of 0.0060 at every candidate count tried —
    /// it is a property of their data. What moves is the threshold it is compared
    /// against: `k/m · q`. At `m = 25` the step-up carries three of their
    /// candidates; at `m = 39` it carries none. Cutting
    /// `InteractionBudget.maximumCandidates` from 60 to 30 recovers them, admits
    /// nothing further for either person who should get nothing, and costs the
    /// two-way person two of five claims. `InteractionBudget` already says the
    /// reason in prose — "the search space is the enemy of the thing being searched
    /// for" — and this is the measurement behind it. The wrong answer is raising Q.
    ///
    /// BH's own guarantee needs positive dependence, which is exactly what this
    /// file argues we do not have — so what is on offer here is not a theorem. It
    /// is that the calibration each p-value is made against is the real
    /// day-clustered joint null rather than an assumed one, and that the two people
    /// who must produce nothing produce nothing at every budget tried. That is
    /// evidence, it is weaker than a proof, and it is written down as such.
    ///
    /// The test statistic is the **interaction lift**, not a p-value. That is the
    /// point: the lift has no measured null under the frozen contract, and a
    /// permutation supplies one directly. It also sidesteps §10.3 entirely — the
    /// bootstrap's p-value floor cannot blunt an ordering that never uses p.
    ///
    /// The null is built by reassigning whole days' worth of outcome values to
    /// other days. Sessions keep every attribute a factor can split on, so cell
    /// membership is identical in every permutation and only the association
    /// between a session's attributes and its rating is destroyed. Within-day
    /// clustering survives, because a day's block of ratings travels together —
    /// which is the whole reason to permute days rather than sessions, and the
    /// reason this null is wider than an independence assumption would draw it.
    ///
    /// **Days are exchanged only with days carrying the same number of ratings.**
    /// This is not tidiness. An unrestricted exchange has to do something when a
    /// one-rating day lands on a three-session day, and every available answer —
    /// repeating the value, sampling it three times — writes a within-day
    /// correlation of exactly 1 into days that do not have one. That inflates the
    /// variance of any day-clustered statistic, and it inflates it most for the
    /// candidates with the smallest cells, which are the ones a conjunction search
    /// is already most likely to be wrong about. Restricting to equal-sized days
    /// keeps the transfer exact: the donor's multiset of ratings arrives intact.
    /// It is a smaller permutation group, and on a record where some size stratum
    /// holds a single day that day is fixed — recorded here because it is a real
    /// loss of null richness rather than a free improvement.
    ///
    /// Missingness is preserved exactly: a session nobody rated stays unrated, so
    /// every cell has the same size under the null as it does in the data and a
    /// permutation cannot manufacture power by filling in a thin cell.
    static func permutationFDR(
        to findings: [InteractionFinding],
        observations: [EngineObservation],
        mode: Mode = .perCandidateStepUp,
        procedure: Procedure = .benjaminiHochberg,
        permutations: Int = defaultPermutations,
        q: Double = falseDiscoveryRate,
        seed: UInt64 = 0x484F_5552
    ) -> PermutationResult {
        var corrected = findings
        for index in findings.indices where !findings[index].interaction.isEstimable {
            corrected[index].survivesCorrection = false
        }

        // A conjunction of one factor is not an interaction and has no four cells
        // to build; it cannot enter a procedure whose statistic is a lift.
        let testable = findings.indices.filter {
            findings[$0].interaction.isEstimable && findings[$0].conjunction.factors.count >= 2
        }
        for index in findings.indices where findings[index].interaction.isEstimable
            && findings[index].conjunction.factors.count < 2 {
            corrected[index].survivesCorrection = false
        }

        let m = testable.count
        let rounds = max(1, min(permutations, maximumPermutations))
        guard m > 0 else {
            return PermutationResult(findings: corrected, liftThreshold: nil, estimatedFDR: nil,
                                     admitted: 0, m: 0, permutations: rounds, curve: [])
        }

        let cells = testable.map { Cells(findings[$0].conjunction, over: observations) }
        let outcomeOf = testable.map { findings[$0].conjunction.outcome }
        // Sorted rather than a raw Set: set iteration order is not stable, and a
        // correction whose result depends on it is not reproducible.
        let outcomes = Set(outcomeOf).sorted { $0.rawValue < $1.rawValue }

        // The observed statistic is recomputed here rather than read off
        // `interaction.lift`. Observed and null have to come out of the same
        // arithmetic or the comparison between them is between two estimators.
        var base: [Outcome: [Double?]] = [:]
        for outcome in outcomes { base[outcome] = observations.map { $0.value(of: outcome) } }
        let observed = (0..<m).map { cells[$0].lift(base[outcomeOf[$0]] ?? []) }

        // Days in sorted order, each owning the indices of its own sessions. Sorted
        // rather than merely grouped: dictionary order is not stable between
        // launches, and a permutation drawn in key order would hand the same
        // history a different null each time the app started.
        let calendar = Calendar.current
        var byDay: [Date: [Int]] = [:]
        for (index, observation) in observations.enumerated() {
            byDay[calendar.startOfDay(for: observation.day), default: []].append(index)
        }
        let days = byDay.keys.sorted().map { byDay[$0] ?? [] }

        // Days grouped by how many ratings they carry, since only same-sized days
        // may be exchanged. Built per outcome: a day that carries three feelings
        // may carry one residual, and the stratum a day belongs to is a fact about
        // the outcome being permuted rather than about the day.
        var strata: [Outcome: [[Int]]] = [:]
        for outcome in outcomes {
            guard let source = base[outcome] else { continue }
            var bySize: [Int: [Int]] = [:]
            for (day, indices) in days.enumerated() {
                let rated = indices.reduce(0) { $0 + (source[$1] == nil ? 0 : 1) }
                bySize[rated, default: []].append(day)
            }
            strata[outcome] = bySize.keys.sorted().map { bySize[$0] ?? [] }
        }

        // Every null lift from every permutation, pooled. Pooling is what makes
        // this dependence-aware: each permutation moves the whole candidate set at
        // once, so candidates that rise and fall together in the data rise and fall
        // together under the null too.
        var nullByCandidate = [[Double]](repeating: [], count: m)
        for candidate in 0..<m { nullByCandidate[candidate].reserveCapacity(rounds) }

        var rng = Statistics.Seeded(seed: seed)
        var shuffled: [Outcome: [[Int]]] = strata
        var permuted: [Outcome: [Double?]] = [:]

        for _ in 0..<rounds {
            for outcome in outcomes {
                guard let source = base[outcome], var groups = shuffled[outcome] else { continue }
                var values = [Double?](repeating: nil, count: observations.count)
                for group in groups.indices {
                    // Fisher–Yates within the stratum, drawn from the seeded
                    // generator so a run is reproducible and a failing measurement
                    // can be investigated.
                    var i = groups[group].count - 1
                    while i > 0 {
                        let j = Int(rng.next().multipliedFullWidth(by: UInt64(i + 1)).high)
                        groups[group].swapAt(i, j)
                        i -= 1
                    }
                    // The stratum's days in their fixed order receive the ratings
                    // of the same stratum's days in shuffled order. Equal sizes, so
                    // the donor's block arrives whole.
                    for (position, donor) in groups[group].enumerated() {
                        let recipient = strata[outcome]?[group][position] ?? donor
                        let pool = days[donor].compactMap { source[$0] }
                        var taken = 0
                        for index in days[recipient] where source[index] != nil {
                            values[index] = pool[taken]
                            taken += 1
                        }
                    }
                }
                shuffled[outcome] = groups
                permuted[outcome] = values
            }

            for candidate in 0..<m {
                if let lift = cells[candidate].lift(permuted[outcomeOf[candidate]] ?? []) {
                    nullByCandidate[candidate].append(lift)
                }
            }
        }

        for candidate in 0..<m { nullByCandidate[candidate].sort() }

        if mode == .perCandidateStepUp {
            return stepUpOnPermutationP(corrected: corrected, testable: testable,
                                        observed: observed, null: nullByCandidate,
                                        procedure: procedure, rounds: rounds, q: q, m: m)
        }

        let nullLifts = nullByCandidate.flatMap { $0 }.sorted()

        /// How many pooled null lifts reached `threshold`, per permutation.
        func expectedFalse(atLeast threshold: Double) -> Double {
            Double(nullLifts.count - lowerBound(nullLifts, threshold)) / Double(rounds)
        }

        // Every observed lift is a candidate threshold. The chosen one is the
        // lowest whose estimated FDR still clears q, which is the largest rejection
        // region the null supports — a stricter choice would refuse claims the
        // measured error rate says are affordable.
        var best: (threshold: Double, fdr: Double, admitted: Int)?
        var curve: [PermutationResult.Step] = []
        for candidate in (0..<m).filter({ observed[$0] != nil })
            .sorted(by: { (observed[$0] ?? 0) > (observed[$1] ?? 0) }) {
            guard let threshold = observed[candidate] else { continue }
            let discoveries = observed.filter { lift in (lift ?? -.infinity) >= threshold }.count
            guard discoveries > 0 else { continue }
            let fdr = expectedFalse(atLeast: threshold) / Double(discoveries)
            curve.append(.init(id: findings[testable[candidate]].conjunction.id,
                               lift: threshold, discoveries: discoveries, estimatedFDR: fdr))
            guard fdr <= q else { continue }
            if discoveries > (best?.admitted ?? 0) { best = (threshold, fdr, discoveries) }
        }

        for (candidate, finding) in testable.enumerated() {
            guard let best, let lift = observed[candidate] else {
                corrected[finding].survivesCorrection = false
                continue
            }
            corrected[finding].survivesCorrection = lift >= best.threshold
        }

        return PermutationResult(findings: corrected,
                                 liftThreshold: best?.threshold,
                                 estimatedFDR: best?.fdr,
                                 admitted: best?.admitted ?? 0,
                                 m: m,
                                 permutations: rounds,
                                 curve: curve)
    }

    /// Per-candidate permutation p, then a step-up over those p-values.
    ///
    /// `p = (1 + #{null ≥ observed}) / (B + 1)`. The added one is not a rounding
    /// convenience: the observed assignment is itself one of the arrangements the
    /// null is drawn from, and leaving it out lets a candidate report a p of zero,
    /// which is a claim the permutation never made.
    private static func stepUpOnPermutationP(
        corrected: [InteractionFinding],
        testable: [Int],
        observed: [Double?],
        null: [[Double]],
        procedure: Procedure,
        rounds: Int,
        q: Double,
        m: Int
    ) -> PermutationResult {
        var corrected = corrected
        var pValues = [Double](repeating: 1, count: m)
        for candidate in 0..<m {
            guard let lift = observed[candidate] else { continue }
            let exceeded = null[candidate].count - lowerBound(null[candidate], lift)
            pValues[candidate] = Double(1 + exceeded) / Double(rounds + 1)
        }

        let ranked = (0..<m).sorted {
            pValues[$0] != pValues[$1]
                ? pValues[$0] < pValues[$1]
                : corrected[testable[$0]].conjunction.id < corrected[testable[$1]].conjunction.id
        }
        var cutoff = 0
        for (index, candidate) in ranked.enumerated() {
            let k = index + 1
            if pValues[candidate] <= threshold(rank: k, of: m, q: q, procedure: procedure) { cutoff = k }
        }

        var admitted = 0
        var curve: [PermutationResult.Step] = []
        for (index, candidate) in ranked.enumerated() {
            let survives = index + 1 <= cutoff
            corrected[testable[candidate]].survivesCorrection = survives
            if survives { admitted += 1 }
            curve.append(.init(id: corrected[testable[candidate]].conjunction.id,
                               lift: observed[candidate] ?? 0,
                               discoveries: index + 1,
                               estimatedFDR: pValues[candidate]))
        }

        // The threshold reported is the lift of the weakest candidate admitted, so
        // the result still answers "what did this require" in the units the claim
        // is made in.
        let boundary = cutoff > 0 ? observed[ranked[cutoff - 1]] : nil
        return PermutationResult(findings: corrected,
                                 liftThreshold: boundary,
                                 estimatedFDR: cutoff > 0 ? pValues[ranked[cutoff - 1]] : nil,
                                 admitted: admitted, m: m, permutations: rounds, curve: curve)
    }

    // MARK: - The four cells

    /// A conjunction's four cells, as row indices.
    ///
    /// Resolved once and reused across every permutation. Factors split on session
    /// attributes and day health, and a permutation moves neither — only the
    /// rating — so recomputing membership two hundred times would produce the same
    /// answer two hundred times at the cost of the whole budget.
    ///
    /// The split into A and B is `InteractionCandidates.partition`'s, exactly:
    /// factors sorted by key, A the first, B the conjunction of the rest. It has to
    /// be exactly, not merely similarly — `within − without` is not symmetric in A
    /// and B, so a different split computes a different statistic, and a null
    /// distribution for a statistic other than the one the finding carries is not
    /// a null distribution for anything. `permutationAgreesWithTheSearch` asserts
    /// the two arrive at the same number rather than trusting this paragraph.
    private struct Cells {
        let withinFocus: [Int]
        let withinBaseline: [Int]
        let withoutFocus: [Int]
        let withoutBaseline: [Int]

        init(_ conjunction: Conjunction, over observations: [EngineObservation]) {
            let sorted = conjunction.factors.sorted { $0.key < $1.key }
            guard let a = sorted.first else {
                self.init(withinFocus: [], withinBaseline: [], withoutFocus: [], withoutBaseline: [])
                return
            }
            let rest = Array(sorted.dropFirst())
            var withinFocus: [Int] = [], withinBaseline: [Int] = []
            var withoutFocus: [Int] = [], withoutBaseline: [Int] = []
            for (index, observation) in observations.enumerated() {
                let isA = a.matches(observation)
                let isB = rest.allSatisfy { $0.matches(observation) }
                switch (isA, isB) {
                case (true, true): withinFocus.append(index)
                case (false, true): withinBaseline.append(index)
                case (true, false): withoutFocus.append(index)
                case (false, false): withoutBaseline.append(index)
                }
            }
            self.init(withinFocus: withinFocus, withinBaseline: withinBaseline,
                      withoutFocus: withoutFocus, withoutBaseline: withoutBaseline)
        }

        private init(withinFocus: [Int], withinBaseline: [Int],
                     withoutFocus: [Int], withoutBaseline: [Int]) {
            self.withinFocus = withinFocus
            self.withinBaseline = withinBaseline
            self.withoutFocus = withoutFocus
            self.withoutBaseline = withoutBaseline
        }

        /// `δ(A∩B vs ¬A∩B) − δ(A∩¬B vs ¬A∩¬B)`, or nil if any cell came back empty
        /// under this assignment of values — an interaction that cannot be
        /// estimated is a refusal rather than a zero, under the null exactly as in
        /// the data.
        func lift(_ values: [Double?]) -> Double? {
            func gather(_ indices: [Int]) -> [Double] { indices.compactMap { values[$0] } }
            let a = gather(withinFocus), b = gather(withinBaseline)
            let c = gather(withoutFocus), d = gather(withoutBaseline)
            guard !a.isEmpty, !b.isEmpty, !c.isEmpty, !d.isEmpty else { return nil }
            return Statistics.cliffsDelta(focus: a, baseline: b)
                - Statistics.cliffsDelta(focus: c, baseline: d)
        }
    }

    /// How many values sit strictly below `target` in a sorted array.
    private static func lowerBound(_ sorted: [Double], _ target: Double) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < target { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
