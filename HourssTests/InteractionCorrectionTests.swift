import Testing
import Foundation
@testable import Hourss

/// What multiplicity control has to do for layer 2.5, and what it costs.
///
/// The unit tests below check arithmetic. The suite's real subject is the
/// measurement at the bottom: the lift gate refuses *redundancy* and cohort
/// measurement showed it does not refuse *noise*, so the correction is the only
/// thing standing between a conjunction search and a person who has no
/// conjunctions. The number that decides this layer is how many claims each
/// procedure admits for `scatteredNoise`, who has none.
///
/// The measurement runs over the candidate set `InteractionCandidates` actually
/// produces — its main-effect gating, its day gate, its budget. A correction
/// measured against a different search than the one it corrects would be measuring
/// the two searches as much as the two procedures.
@Suite("Interaction multiplicity control")
struct InteractionCorrectionTests {

    // MARK: - Hand-built findings

    /// A comparison with a chosen p-value and nothing else meaningful.
    ///
    /// Everything a step-up procedure reads is the p; the rest is filled with
    /// values that would pass the reporting gates, so a test that fails fails on
    /// the correction rather than on an incidental refusal elsewhere.
    private func comparison(p: Double, delta: Double = 0.40) -> Statistics.Comparison {
        Statistics.Comparison(delta: delta, low: delta - 0.12, high: delta + 0.12,
                              focusCount: 40, baselineCount: 90,
                              focusDays: 20, baselineDays: 45, pValue: p)
    }

    /// A factor that matches nothing. These findings never meet an observation —
    /// the step-up procedures read p-values and ids, and inventing rows for them
    /// would only obscure that.
    private func factor(_ family: Factor.Family, _ value: String) -> Factor {
        Factor(family: family, value: value, matches: { _ in false })
    }

    private func finding(_ name: String,
                         p: Double,
                         withinP: Double? = nil,
                         lift: Double = 0.50,
                         estimable: Bool = true) -> InteractionFinding {
        let conjunction = Conjunction(
            factors: [factor(.activity, name), factor(.time, "morning")],
            outcome: .feeling)
        let interaction = InteractionLift(
            within: comparison(p: withinP ?? p, delta: 0.5),
            without: comparison(p: 1, delta: 0.5 - lift),
            lift: lift,
            isEstimable: estimable,
            combined: comparison(p: p))
        return InteractionFinding(conjunction: conjunction, interaction: interaction,
                                  focusSessionIds: [], baselineSessionIds: [], windowDays: 90,
                                  survivesCorrection: nil)
    }

    private func survivors(_ findings: [InteractionFinding]) -> Set<String> {
        Set(findings.filter { $0.survivesCorrection == true }.map(\.conjunction.id))
    }

    // MARK: - Benjamini–Yekutieli, by hand

    @Test("The harmonic number is the harmonic number")
    func harmonic() {
        #expect(InteractionCorrection.harmonicNumber(1) == 1)
        #expect(abs(InteractionCorrection.harmonicNumber(5) - 2.283333) < 1e-5)
        // The realistic candidate count. Every BY threshold at sixty candidates is
        // this much stricter than BH's, which is the whole argument to be had.
        #expect(abs(InteractionCorrection.harmonicNumber(60) - 4.679870) < 1e-5)
        #expect(InteractionCorrection.harmonicNumber(0) == 1, "an empty family must not divide by zero")
    }

    /// Five candidates, thresholds worked out longhand.
    ///
    /// `m = 5`, `q = 0.10`, `H(5) = 2.283333`. BY's threshold at rank *k* is
    /// `k/5 × 0.10 / 2.283333 = k × 0.0087591`:
    ///
    /// ```
    /// k  p      BY threshold   BH threshold
    /// 1  0.001  0.008759  ✓    0.02  ✓
    /// 2  0.012  0.017518  ✓    0.04  ✓
    /// 3  0.030  0.026277  ✗    0.06  ✓
    /// 4  0.060  0.035036  ✗    0.08  ✓
    /// 5  0.500  0.043796  ✗    0.10  ✗
    /// ```
    ///
    /// BY stops at rank 2 and BH steps up to rank 4. Two real candidates refused
    /// by the change of procedure alone, on identical data.
    @Test("Benjamini–Yekutieli admits exactly the ranks worked out by hand")
    func byByHand() {
        let findings = [finding("a", p: 0.001), finding("b", p: 0.012),
                        finding("c", p: 0.030), finding("d", p: 0.060),
                        finding("e", p: 0.500)]

        let by = survivors(InteractionCorrection.benjaminiYekutieli(findings))
        #expect(by.count == 2, Comment(rawValue: "BY admitted \(by.count), not the two worked out by hand"))
        #expect(by.contains { $0.contains("activity.a") })
        #expect(by.contains { $0.contains("activity.b") })
        #expect(!by.contains { $0.contains("activity.c") })

        let bh = survivors(InteractionCorrection.benjaminiHochberg(findings))
        #expect(bh.count == 4, Comment(rawValue: "BH admitted \(bh.count), not the four worked out by hand"))
        #expect(bh.contains { $0.contains("activity.d") },
                "BH's step-up must carry rank 4 even though rank 3 failed its own threshold")
    }

    @Test("The step-up threshold is k/m · q / H(m)")
    func thresholds() {
        let bh = InteractionCorrection.threshold(rank: 1, of: 60, procedure: .benjaminiHochberg)
        let by = InteractionCorrection.threshold(rank: 1, of: 60, procedure: .benjaminiYekutieli)
        #expect(abs(bh - 0.10 / 60) < 1e-12)
        #expect(abs(by - 0.10 / 60 / InteractionCorrection.harmonicNumber(60)) < 1e-12)
        // The number that decides whether the layer can speak at all: the
        // bootstrap's floor at 2000 resamples is 0.0005, and BY's hardest
        // threshold at sixty candidates sits below it.
        #expect(by < 0.0005, Comment(rawValue:
                "BY's rank-1 threshold at m=60 is \(by) — at or above the 2000-resample floor, which would change the recommendation"))
    }

    @Test("Benjamini–Yekutieli is never more permissive than Benjamini–Hochberg")
    func byIsNeverMorePermissive() {
        // Deterministic pseudo-random p-value sets rather than one hand-picked
        // example: the property has to hold for every arrangement, including the
        // ones where the two procedures' step-up points coincide.
        var rng = Statistics.Seeded(seed: 0xBE11)
        for trial in 0..<40 {
            let m = 1 + trial % 25
            let findings = (0..<m).map { index -> InteractionFinding in
                let u = Double(rng.next() % 10_000) / 10_000
                // Squared, so most p-values land near zero and the interesting
                // regime — where BH admits and BY has to decide — is visited often.
                return finding("f\(trial).\(index)", p: max(0.0005, u * u))
            }
            let bh = survivors(InteractionCorrection.benjaminiHochberg(findings))
            let by = survivors(InteractionCorrection.benjaminiYekutieli(findings))
            #expect(by.isSubset(of: bh), Comment(rawValue:
                    "trial \(trial), m=\(m): BY admitted \(by.subtracting(bh).count) candidates BH refused"))
        }
    }

    @Test("A single candidate is penalised by neither procedure")
    func singleCandidateIsNotPenalised() {
        // H(1) = 1, so BY and BH are the same procedure at m = 1. A person with one
        // testable conjunction must not pay a dependence penalty for a dependence
        // that has nothing to depend on.
        let one = [finding("solo", p: 0.05)]
        #expect(survivors(InteractionCorrection.benjaminiYekutieli(one)).count == 1)
        #expect(survivors(InteractionCorrection.benjaminiHochberg(one)).count == 1)
        #expect(InteractionCorrection.threshold(rank: 1, of: 1, procedure: .benjaminiYekutieli) == 0.10)

        // And a single candidate is still tested rather than waved through.
        let weak = [finding("solo", p: 0.4)]
        #expect(survivors(InteractionCorrection.benjaminiYekutieli(weak)).isEmpty)
    }

    @Test("Candidates that were never testable do not inflate m")
    func untestedCandidatesDoNotInflateM() {
        let tested = [finding("a", p: 0.001), finding("b", p: 0.012),
                      finding("c", p: 0.030), finding("d", p: 0.060),
                      finding("e", p: 0.500)]
        let refused = (0..<20).map { finding("thin\($0)", p: 0.0005, estimable: false) }

        let alone = survivors(InteractionCorrection.benjaminiYekutieli(tested))
        let together = survivors(InteractionCorrection.benjaminiYekutieli(tested + refused))
        #expect(alone == together, Comment(rawValue:
                "twenty unestimable candidates changed the surviving set from \(alone.count) to \(together.count)"))

        // And they are refused rather than left undecided: nil would read as
        // "correction has not run", which is a different state entirely.
        let corrected = InteractionCorrection.benjaminiYekutieli(tested + refused)
        #expect(corrected.allSatisfy { $0.survivesCorrection != nil })
        #expect(corrected.filter { !$0.interaction.isEstimable }.allSatisfy { $0.survivesCorrection == false })
    }

    @Test("Both step-up procedures are deterministic")
    func stepUpIsDeterministic() {
        let findings = (0..<30).map { finding("d\($0)", p: Double($0 % 7) * 0.01 + 0.0005) }
        for procedure in InteractionCorrection.Procedure.allCases {
            let first = InteractionCorrection.applying(procedure, to: findings)
            let second = InteractionCorrection.applying(procedure, to: findings.reversed())
            // Reversed input, so the tie-break on conjunction id is doing work: at
            // the p-value floor whole blocks of candidates are exactly tied.
            #expect(survivors(first) == survivors(second), Comment(rawValue:
                    "\(procedure.rawValue) gave a different surviving set when the input order changed"))
        }
    }

    // MARK: - Permutation FDR

    @Test("Permutation FDR admits nothing for the person who has no interaction")
    func permutationRefusesNoise() {
        let rows = Self.rows(for: SyntheticCohort.scatteredNoise)
        let candidates = CohortCandidates.candidates(over: rows)
        #expect(candidates.count > 5, Comment(rawValue:
                "only \(candidates.count) candidates survived pruning for the noise person — too few to test a correction against"))

        for mode in InteractionCorrection.Mode.allCases {
            let result = InteractionCorrection.permutationFDR(
                to: candidates, observations: rows, mode: mode)
            #expect(result.admitted == 0, Comment(rawValue:
                    "\(mode.rawValue) admitted \(result.admitted) interactions for a person who has none, at a lift threshold of \(result.liftThreshold.map { "\($0)" } ?? "none")"))
        }
    }

    @Test("Permutation FDR is deterministic")
    func permutationIsDeterministic() {
        let rows = Self.rows(for: SyntheticCohort.morningDeepWork)
        let candidates = CohortCandidates.candidates(over: rows)
        let first = InteractionCorrection.permutationFDR(to: candidates, observations: rows, permutations: 60)
        let second = InteractionCorrection.permutationFDR(to: candidates, observations: rows, permutations: 60)
        #expect(first.admitted == second.admitted)
        #expect(first.liftThreshold == second.liftThreshold)
        #expect(survivors(first.findings) == survivors(second.findings), "two identical runs disagreed")

        // A different seed is a different experiment and may land elsewhere; what
        // must not happen is the same seed drifting.
        let reversed = InteractionCorrection.permutationFDR(to: candidates.reversed(), observations: rows, permutations: 60)
        #expect(survivors(reversed.findings) == survivors(first.findings),
                "reordering the candidate list changed which ones survived")
    }

    /// The observed statistic the permutation compares against has to be the one
    /// the finding carries.
    ///
    /// `InteractionCorrection` recomputes the lift itself — it has to, because the
    /// null is recomputed the same way and observed and null coming out of two
    /// different estimators would make the comparison meaningless. That means two
    /// pieces of code compute the same number, and this is the check that they
    /// still agree. `within − without` is not symmetric in A and B, so a drift in
    /// either file's conditioning split shows up here as a mismatch rather than as
    /// a quietly wrong correction.
    @Test("The permutation's own lift matches the one the search reported")
    func permutationAgreesWithTheSearch() {
        for person in [SyntheticCohort.morningDeepWorkAfterSleep, SyntheticCohort.scatteredNoise] {
            let rows = Self.rows(for: person)
            let candidates = CohortCandidates.candidates(over: rows)
            // Two permutations: the run is not the point, the curve's observed
            // lifts are, and those come from the unpermuted data either way.
            let result = InteractionCorrection.permutationFDR(
                to: candidates, observations: rows, mode: .perCandidateStepUp, permutations: 2)
            let reported = Dictionary(uniqueKeysWithValues:
                candidates.map { ($0.conjunction.id, $0.interaction.lift) })
            for step in result.curve {
                let expected = reported[step.id] ?? .nan
                #expect(abs(step.lift - expected) < 1e-9, Comment(rawValue:
                        "\(step.id): the correction computed a lift of \(step.lift) where the search reported \(expected)"))
            }
        }
    }

    @Test("Permutation FDR leaves no candidate undecided")
    func permutationDecidesEverything() {
        let rows = Self.rows(for: SyntheticCohort.deepWorkMostlyMorning)
        let result = InteractionCorrection.permutationFDR(
            to: CohortCandidates.candidates(over: rows), observations: rows, permutations: 60)
        #expect(result.findings.allSatisfy { $0.survivesCorrection != nil })
    }

    // MARK: - The measurement

    /// Both procedures over the cohort, with the numbers the decision rests on.
    ///
    /// Assertions here are the ones that would change the recommendation: noise
    /// admitting nothing, and the real interactions not being refused by whatever
    /// ships. Everything else is printed, because the point of the run is the table
    /// rather than a pass.
    @Test("Cohort measurement: what each procedure admits, and for whom")
    func cohortMeasurement() {
        let people = [SyntheticCohort.scatteredNoise,
                      SyntheticCohort.morningDeepWork,
                      SyntheticCohort.morningDeepWorkAfterSleep,
                      SyntheticCohort.deepWorkMostlyMorning]

        print("MEASURE ── interaction multiplicity control, Q = \(InteractionCorrection.falseDiscoveryRate)")
        print("MEASURE person                      m   floor  BH  BY  BHiu BYiu perm  permT  permFDR | reportable BH/BY/perm")

        var admitted: [String: (by: Int, byIU: Int, perm: Int)] = [:]

        for person in people {
            let rows = Self.rows(for: person)
            let candidates = CohortCandidates.candidates(over: rows)
            let m = candidates.filter(\.interaction.isEstimable).count
            let floor = candidates.filter { $0.interaction.combined.pValue <= 0.0005 }.count

            func count(_ findings: [InteractionFinding]) -> Int {
                findings.filter { $0.survivesCorrection == true }.count
            }
            func reportable(_ findings: [InteractionFinding]) -> Int {
                findings.filter(\.isReportable).count
            }

            let bh = InteractionCorrection.benjaminiHochberg(candidates)
            let by = InteractionCorrection.benjaminiYekutieli(candidates)
            let bhIU = InteractionCorrection.benjaminiHochberg(candidates, statistic: .intersectionUnion)
            let byIU = InteractionCorrection.benjaminiYekutieli(candidates, statistic: .intersectionUnion)
            // The recommended arrangement, and the two it is recommended over.
            let perm = InteractionCorrection.permutationFDR(to: candidates, observations: rows)
            let pooled = InteractionCorrection.permutationFDR(
                to: candidates, observations: rows, mode: .pooledThreshold)
            let permBY = InteractionCorrection.permutationFDR(
                to: candidates, observations: rows, mode: .perCandidateStepUp, procedure: .benjaminiYekutieli)

            admitted[person.name] = (count(by), count(byIU), perm.admitted)

            let name = person.name.padding(toLength: 30, withPad: " ", startingAt: 0)
            let t = perm.liftThreshold.map { String(format: "%.3f", $0) } ?? "  —  "
            let f = perm.estimatedFDR.map { String(format: "%.3f", $0) } ?? "  —  "
            print("MEASURE \(name) \(m)  \(floor)   \(count(bh))  \(count(by))  \(count(bhIU))  \(count(byIU))  \(perm.admitted)  \(t)  \(f) | \(reportable(bh))/\(reportable(by))/\(reportable(perm.findings))")

            print("MEASURE   permutation variants: per-candidate+BH \(perm.admitted) (\(reportable(perm.findings)) reportable), per-candidate+BY \(permBY.admitted) (\(reportable(permBY.findings)) reportable), pooled threshold \(pooled.admitted) (\(reportable(pooled.findings)) reportable)")
            for step in permBY.curve.prefix(4) {
                print(String(format: "MEASURE   permP %.4f lift %.3f %@", step.estimatedFDR, step.lift, step.id))
            }

            // The strongest candidates by lift, named. A count of admissions says
            // how loud a procedure is; only the ids say whether it was loud about
            // the right thing.
            for candidate in candidates.filter(\.interaction.isEstimable)
                .sorted(by: { $0.interaction.lift > $1.interaction.lift }).prefix(3) {
                print(String(format: "MEASURE   top lift %.3f p=%.4f %@",
                             candidate.interaction.lift,
                             candidate.interaction.combined.pValue,
                             candidate.conjunction.id))
            }

            if m > 0 {
                let byThreshold = InteractionCorrection.threshold(rank: 1, of: m, procedure: .benjaminiYekutieli)
                let bhThreshold = InteractionCorrection.threshold(rank: 1, of: m, procedure: .benjaminiHochberg)
                print(String(format: "MEASURE   rank-1 thresholds at m=%d: BH %.6f, BY %.6f, bootstrap floor 0.000500", m, bhThreshold, byThreshold))
            }
        }

        // The number that matters, and the reason this layer exists in the shape it
        // does. A person with no interaction must produce no interaction, and a
        // person whose conjunction is nothing but a main effect must produce none
        // either. Both are false discoveries by construction.
        #expect(admitted[SyntheticCohort.scatteredNoise.name]?.perm == 0, Comment(rawValue:
                "the recommended procedure invented \(admitted[SyntheticCohort.scatteredNoise.name]?.perm ?? -1) interactions for the noise person"))
        #expect(admitted[SyntheticCohort.deepWorkMostlyMorning.name]?.perm == 0, Comment(rawValue:
                "the recommended procedure invented \(admitted[SyntheticCohort.deepWorkMostlyMorning.name]?.perm ?? -1) interactions for the confounded person"))

        // And the other half of correctness: a layer that can never speak is worse
        // than no layer, so a planted interaction has to survive it.
        #expect((admitted[SyntheticCohort.morningDeepWork.name]?.perm ?? 0) > 0,
                "the recommended procedure refused a real two-way interaction")

        // The three-way person was refused outright at a budget of sixty and is
        // found at thirty, which is why the budget is thirty. Their strongest
        // candidate holds the same permutation p either way; what moved was the
        // threshold it was measured against, since a step-up compares each p
        // against k/m · q and every extra candidate raises the bar for all of
        // them. Asserted so that widening the search again fails here rather than
        // quietly costing a real finding.
        #expect((admitted[SyntheticCohort.morningDeepWorkAfterSleep.name]?.perm ?? 0) > 0,
                "a planted three-way interaction is being refused — check the candidate budget")

        // BY on the bootstrap p is recorded and not asserted on: it admits five
        // interactions for the noise person and every candidate the confounded
        // person has, which is the measurement that removes it from consideration.
        #expect((admitted[SyntheticCohort.scatteredNoise.name]?.by ?? 0) > 0,
                "BY refusing the noise person outright would change the recommendation")
    }

    /// How many permutations the per-candidate mode needs before it can speak.
    ///
    /// A permutation p cannot fall below `1/(B+1)`, and a step-up threshold at rank
    /// *k* of *m* is `k/m · q` divided by the dependence penalty. Those two numbers
    /// decide whether the procedure is capable of admitting anything *before* any
    /// data is seen: at `B = 200` the floor is 0.00498 and BH's rank-1 threshold at
    /// `m = 60` is 0.00167, so the strongest candidate a person could possibly have
    /// still fails at rank 1 and has to be carried by the step-up. This measures
    /// where the budget stops being the binding constraint.
    @Test("What the permutation budget costs")
    func permutationBudget() {
        for person in [SyntheticCohort.morningDeepWork,
                       SyntheticCohort.morningDeepWorkAfterSleep,
                       SyntheticCohort.scatteredNoise,
                       SyntheticCohort.deepWorkMostlyMorning] {
            let rows = Self.rows(for: person)
            let candidates = CohortCandidates.candidates(over: rows)
            for permutations in [500, 1000] {
                for procedure in InteractionCorrection.Procedure.allCases {
                    let result = InteractionCorrection.permutationFDR(
                        to: candidates, observations: rows,
                        mode: .perCandidateStepUp, procedure: procedure,
                        permutations: permutations)
                    let reportable = result.findings.filter(\.isReportable).count
                    print(String(format: "MEASURE budget %@ B=%d %@ m=%d admitted=%d reportable=%d floor=%.5f bestP=%.5f",
                                 person.name, permutations, procedure.rawValue, result.m,
                                 result.admitted, reportable, 1 / Double(permutations + 1),
                                 result.curve.first?.estimatedFDR ?? 1))
                }
            }
        }
    }

    /// What the size of the search costs the permutation procedure.
    ///
    /// The null is pooled across candidates, so every extra hypothesis widens the
    /// distribution the real one has to clear. `InteractionBudget` says this in
    /// prose — "the search space is the enemy of the thing being searched for" —
    /// and this is the number behind it: the same person, the same data, a
    /// different cap on how many places were looked in.
    @Test("What the candidate cap costs the permutation procedure")
    func candidateCountSensitivity() {
        var atThirty: [String: Int] = [:]
        for person in [SyntheticCohort.morningDeepWorkAfterSleep,
                       SyntheticCohort.morningDeepWork,
                       SyntheticCohort.scatteredNoise,
                       SyntheticCohort.deepWorkMostlyMorning] {
            let rows = Self.rows(for: person)
            for limit in [12, 20, 30, 60] {
                let candidates = CohortCandidates.candidates(over: rows, limit: limit)
                for mode in InteractionCorrection.Mode.allCases {
                    let result = InteractionCorrection.permutationFDR(
                        to: candidates, observations: rows, mode: mode, permutations: 500)
                    let best = result.curve.first
                    print(String(format: "MEASURE cap %@ limit=%d m=%d %@ admitted=%d best=%.3f at %.4f",
                                 person.name, limit, result.m, mode.rawValue, result.admitted,
                                 best?.lift ?? 0, best?.estimatedFDR ?? 0))
                    if limit == 30, mode == .perCandidateStepUp {
                        atThirty[person.name] = result.admitted
                    }
                }
            }
        }

        // The finding, and the only lever the measurement found that does not
        // involve loosening Q. A candidate's own permutation p barely moves with
        // `m` — the real three-way sits at 0.0060 whatever the budget — but the
        // step-up threshold it is compared against is `k/m · q`, and at the
        // shipping budget of 60 that threshold has fallen below it. Cutting the
        // budget to 30 recovers the three-way person without admitting anything
        // for either person who should get nothing.
        #expect(atThirty[SyntheticCohort.morningDeepWorkAfterSleep.name] ?? 0 > 0, Comment(rawValue:
                "a budget of 30 did not recover the real three-way: \(atThirty[SyntheticCohort.morningDeepWorkAfterSleep.name] ?? -1) admitted"))
        #expect(atThirty[SyntheticCohort.morningDeepWork.name] ?? 0 > 0, Comment(rawValue:
                "a budget of 30 did not recover the real two-way: \(atThirty[SyntheticCohort.morningDeepWork.name] ?? -1) admitted"))
        #expect(atThirty[SyntheticCohort.scatteredNoise.name] == 0, Comment(rawValue:
                "a budget of 30 invented \(atThirty[SyntheticCohort.scatteredNoise.name] ?? -1) interactions for the noise person"))
        #expect(atThirty[SyntheticCohort.deepWorkMostlyMorning.name] == 0, Comment(rawValue:
                "a budget of 30 invented \(atThirty[SyntheticCohort.deepWorkMostlyMorning.name] ?? -1) interactions for the confounded person"))
    }

    /// How much of the correction's blindness is the p-value floor.
    ///
    /// §10.3: at 2000 resamples the bootstrap cannot report a p below 0.0005, so
    /// every well-separated candidate reports exactly that and a p-ordered
    /// procedure's ranking among them is alphabetical rather than statistical.
    /// §10.3 also names the fix — 10,000 resamples is affordable — and the measured
    /// answer is that **it is not a fix**: the same candidates are tied at the
    /// lower floor. They are not near the resolution limit, they are past it, and
    /// no resample count anybody would pay for separates them.
    @Test("How many candidates sit at the bootstrap p-value floor")
    func floorOccupancy() {
        var occupancy: [Int: Int] = [:]
        for person in [SyntheticCohort.morningDeepWork, SyntheticCohort.scatteredNoise] {
            let rows = Self.rows(for: person)
            for resamples in [2000, 10_000] {
                let candidates = CohortCandidates.candidates(over: rows, resamples: resamples, limit: 24)
                let floor = 1.0 / Double(resamples)
                let atFloor = candidates.filter { $0.interaction.combined.pValue <= floor * 1.001 }.count
                let m = candidates.count
                let byThreshold = InteractionCorrection.threshold(
                    rank: 1, of: max(m, 1), procedure: .benjaminiYekutieli)
                print("MEASURE floor \(person.name) resamples=\(resamples) m=\(m) atFloor=\(atFloor) floor=\(floor) BYrank1=\(String(format: "%.6f", byThreshold))")
                occupancy[resamples, default: 0] += atFloor
            }
        }
        // The finding, asserted so it cannot quietly stop being true: five times the
        // resamples buys no separation at all among the candidates that matter.
        #expect(occupancy[2000] == occupancy[10_000], Comment(rawValue:
                "floor occupancy moved from \(occupancy[2000] ?? -1) to \(occupancy[10_000] ?? -1) at five times the resamples — §10.3's fix would then be worth taking"))
    }

    // MARK: - Cohort bridge

    private static func rows(for person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay)
    }
}

// MARK: - The candidate search

/// The real search, wrapped so the measurement reads as one line.
///
/// This began as a stand-in implementing §6.2 by hand while `InteractionCandidates`
/// was being built in parallel. It is not one any more: every number below comes
/// from the search that ships, including its main-effect gating, its day gate and
/// its budget. Two implementations of one pruning pipeline would have made the
/// correction's numbers unreadable — they would have measured the difference
/// between the two searches as much as the difference between the procedures.
enum CohortCandidates {
    static func candidates(over rows: [EngineObservation],
                           outcome: Outcome = .feeling,
                           resamples: Int = 2000,
                           limit: Int = InteractionBudget.maximumCandidates) -> [InteractionFinding] {
        let input = EngineInput(observations: rows)
        // Layer 2's own results feed the tree gate, rather than a second estimate
        // of the same quantity computed here.
        let mainEffects = InteractionCandidates.mainEffects(
            from: Engine.findings(for: input, resamples: resamples))
        return InteractionCandidates.findings(for: input, mainEffects: mainEffects,
                                              outcome: outcome, resamples: resamples,
                                              budget: limit)
    }
}
