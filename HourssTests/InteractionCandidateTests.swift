import Testing
import Foundation
@testable import Hourss

/// What layer 2.5 must refuse, and the one thing it must find.
///
/// The cohort's five conjunction people are the answer key: one real two-way, one
/// real three-way, one confound that is entirely a main effect, one person with no
/// interaction at all and a schedule that fills every cell, and one real
/// interaction spread over too few days. Four of those five are negatives, which
/// is the right ratio — a conjunction search has many more ways to be wrong than
/// to be right, and the interesting question about this layer is never whether it
/// can find something.
@Suite("Interaction candidates")
struct InteractionCandidateTests {

    /// Fewer than the engine's default. The interval is not what these tests
    /// assert on — the point estimate and the gate decisions are — and a bootstrap
    /// this size still pins δ down far more tightly than the differences being
    /// checked. Determinism is unaffected: `Statistics.Seeded` is seeded the same
    /// way at any count.
    private static let resamples = 400

    private func rows(for person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay
        )
    }

    /// Layer 2's results, corrected — which is what the gate reads. `clearedLayer2`
    /// is nil-valued until `applyingCorrection` has run, so handing raw findings to
    /// the gate would silently reduce it to its magnitude arm alone.
    private func mainEffects(for person: SyntheticCohort.Person) -> [String: InteractionCandidates.MainEffect] {
        let input = EngineInput(observations: rows(for: person))
        let tested = Engine.findings(for: input, resamples: Self.resamples)
        return InteractionCandidates.mainEffects(from: Engine.applyingCorrection(to: tested))
    }

    /// The conjunction the cohort was built around, by hand rather than by search,
    /// so a test about the *gate* cannot fail for a reason belonging to generation.
    private func deepWorkMorning(in observations: [EngineObservation]) -> Conjunction? {
        conjunction(of: ["activity.deep-work", "time.morning"], in: observations)
    }

    private func conjunction(of keys: [String], in observations: [EngineObservation]) -> Conjunction? {
        let available = InteractionCandidates.factors(in: observations)
        let wanted = keys.compactMap { key in available.first { $0.key == key } }
        guard wanted.count == keys.count else { return nil }
        return Conjunction(factors: wanted, outcome: .feeling)
    }

    // MARK: - The measurement

    /// The three numbers the threshold has to be defensible against.
    ///
    /// `InteractionLift.minimumLift` arrived as 0.147 — Cliff's negligible bound —
    /// but a lift is a *difference of two δs* and runs −2…2, so the band does not
    /// transfer. This measures what the cohort actually produces in those units:
    /// a real interaction, a confound, and the largest thing a person with no
    /// interaction at all can be made to yield.
    ///
    /// The last number is the one that matters. If noise reaches the threshold,
    /// the gate is not refusing noise — it is refusing *redundancy*, which is a
    /// different and much narrower job than the specification claims for it.
    ///
    /// Measured, on this cohort, at this seed:
    ///
    /// | quantity                                      | δ units |
    /// | --------------------------------------------- | ------- |
    /// | real two-way, `morningDeepWork`               |  +0.526 |
    /// | real three-way, `morningDeepWorkAfterSleep`   |  +0.469 |
    /// | confounded, `deepWorkMostlyMorning`           |  −0.020 |
    /// | largest spurious, `scatteredNoise`            |  +0.292 |
    ///
    /// **0.147 is doing nothing.** Noise clears it nearly twice over, and five of
    /// the thirty-one candidates screened on a person with no interaction at all
    /// pass it. What the gate does do it does decisively: the confound lands at
    /// −0.020, an order of magnitude under the threshold, because a main effect
    /// that is the same inside and outside its supposed condition has a
    /// conditional contrast of zero by construction. That is redundancy, not
    /// noise, and the two failures are not interchangeable.
    @Test("Measured: real, confounded, and spurious lift in delta units")
    func measuredLifts() throws {
        let real = try #require(lift(for: SyntheticCohort.morningDeepWork))
        let confounded = try #require(lift(for: SyntheticCohort.deepWorkMostlyMorning))
        let spurious = try #require(largestSpuriousLift())

        // Reported through an expectation rather than printed, so the numbers
        // survive in the test log whichever way the run goes.
        #expect(real > confounded, Comment(rawValue:
            "real \(fmt(real)) · confounded \(fmt(confounded)) · largest spurious \(fmt(spurious.lift)) "
            + "on \(spurious.id)"))

        // The real interaction is separated from the confound by a wide margin.
        // That is the discrimination the lift definition was chosen for, and it
        // holds in δ units as it did in rating units.
        #expect(real - confounded > 0.4, Comment(rawValue:
            "real and confounded lift are \(fmt(real - confounded)) apart, which is not a separation"))

        // The finding, asserted so it cannot quietly stop being true: a person
        // with nothing in them produces a lift above the contract's threshold.
        // If this ever fails because the spurious ceiling *dropped*, the threshold
        // can be revisited; while it holds, 0.147 is not a gate against noise.
        #expect(spurious.lift > InteractionLift.minimumLift, Comment(rawValue:
            "pure noise reached \(fmt(spurious.lift)) against a threshold of \(InteractionLift.minimumLift)"))

        // What a defensible threshold would have to be. 0.330 is Cliff's own
        // small-to-medium boundary — no better justified in these units than
        // 0.147 was, but it has the one property the measurement demands: it sits
        // above everything this cohort's noise produced and below both real
        // interactions. It is a floor, not a solution; the thing that is actually
        // supposed to control false discovery here is §6.3's correction.
        let recommended = 0.330
        #expect(spurious.lift < recommended, Comment(rawValue:
            "the recommended threshold \(recommended) no longer clears measured noise at \(fmt(spurious.lift))"))
        #expect(real > recommended, Comment(rawValue:
            "the recommended threshold would refuse the cohort's only real two-way at \(fmt(real))"))
    }

    private func lift(for person: SyntheticCohort.Person) -> Double? {
        let observations = rows(for: person)
        guard let conjunction = deepWorkMorning(in: observations) else { return nil }
        return InteractionCandidates
            .screen(conjunction, in: observations, resamples: Self.resamples)
            .lift?.lift
    }

    /// The worst a person with nothing in them can be made to produce.
    ///
    /// Every candidate the pipeline generates for `scatteredNoise`, screened, and
    /// the largest lift that came back. By construction none of them is real.
    private func largestSpuriousLift() -> (id: String, lift: Double)? {
        let person = SyntheticCohort.scatteredNoise
        let observations = rows(for: person)
        let plan = InteractionCandidates.plan(for: observations, mainEffects: mainEffects(for: person))
        var worst: (id: String, lift: Double)?
        for candidate in plan.candidates {
            guard let lift = InteractionCandidates
                .screen(candidate, in: observations, resamples: Self.resamples).lift else { continue }
            if worst == nil || lift.lift > worst!.lift { worst = (candidate.id, lift.lift) }
        }
        return worst
    }

    private func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    // MARK: - Finding the real one

    @Test("A real interaction is generated and clears the lift gate")
    func realInteractionSurvives() throws {
        let person = SyntheticCohort.morningDeepWork
        let observations = rows(for: person)
        let plan = InteractionCandidates.plan(for: observations, mainEffects: mainEffects(for: person))

        let wanted = try #require(deepWorkMorning(in: observations)).id
        #expect(plan.candidates.contains { $0.id == wanted }, Comment(rawValue:
            "the cohort's only real two-way was never generated; \(plan.candidates.count) candidates were"))

        let screening = InteractionCandidates.screen(
            try #require(deepWorkMorning(in: observations)),
            in: observations, resamples: Self.resamples)
        let lift = try #require(screening.lift, "a real interaction was refused before it was measured")
        #expect(lift.isEstimable)
        #expect(lift.lift >= InteractionLift.minimumLift, Comment(rawValue:
            "a planted 1.4-point interaction measured a lift of \(fmt(lift.lift))"))
    }

    // MARK: - Refusing the confound

    /// The test this layer exists to pass.
    ///
    /// Deep work is good everywhere and he mostly does it in the morning, so the
    /// intersection against everything else is large, real and well supported —
    /// and belongs entirely to deep work. `combined` shows exactly that trap, which
    /// is why the gate reads the conditional contrast instead.
    @Test("The confounded conjunction is refused")
    func confoundedConjunctionIsRefused() throws {
        let person = SyntheticCohort.deepWorkMostlyMorning
        let observations = rows(for: person)
        let candidate = try #require(deepWorkMorning(in: observations))
        let lift = try #require(
            InteractionCandidates.screen(candidate, in: observations, resamples: Self.resamples).lift)

        #expect(lift.lift < InteractionLift.minimumLift, Comment(rawValue:
            "a pure main effect produced an interaction lift of \(fmt(lift.lift))"))

        // And the trap it was refused in spite of: scored against the rest of his
        // record the same cells look like a strong finding.
        #expect(lift.combined.delta > 0.2, Comment(rawValue:
            "the confound is supposed to look tempting; combined δ was \(fmt(lift.combined.delta))"))
    }

    // MARK: - Refusing what cannot be estimated

    @Test("An empty fourth cell is not estimable, not zero")
    func emptyCellIsNotEstimable() throws {
        // Creative work only ever happens in the morning, so ¬morning ∩ Creative
        // is empty and the effect of Creative among non-mornings does not exist to
        // be compared with.
        let observations = Self.handBuilt(days: 40) { day, index in
            index == 0 ? ("Creative", 8) : ("Admin", day % 2 == 0 ? 9 : 15)
        }
        let candidate = try #require(conjunction(of: ["activity.creative", "time.morning"],
                                                 in: observations))
        let screening = InteractionCandidates.screen(candidate, in: observations,
                                                     resamples: Self.resamples)
        #expect(screening.refusal == .notEstimable(.without), Comment(rawValue:
            "expected a refusal for the missing A∩¬B cell, got \(String(describing: screening))"))
        // Not a lift of zero wearing a refusal's clothes: there is no number here.
        #expect(screening.lift == nil)
    }

    // MARK: - Refusing what is too thin

    @Test("A cell under six distinct days is refused before resampling")
    func thinCellIsRefusedOnDays() throws {
        // Ninety days of everything else, and the real interaction on five of
        // them. The refusal has to come from counting days inside the intersection
        // rather than from the size of the history.
        let person = SyntheticCohort.rareMorningCreative
        let observations = rows(for: person)
        let candidate = try #require(conjunction(of: ["activity.creative", "time.morning"],
                                                 in: observations))

        let screening = InteractionCandidates.screen(candidate, in: observations,
                                                     resamples: Self.resamples)
        switch screening.refusal {
        case let .tooFewDays(_, days):
            #expect(days < InteractionBudget.minimumDaysPerCell)
        case let other:
            Issue.record(Comment(rawValue: "expected a day refusal, got \(String(describing: other))"))
        }

        // The refusal is reached with no resampling at all: a screen at one
        // resample returns the same answer as a screen at four hundred, which it
        // could not do if the bootstrap had been consulted.
        #expect(InteractionCandidates.screen(candidate, in: observations, resamples: 1).refusal
                == screening.refusal)
    }

    // MARK: - The pruning actually prunes

    /// Where the pruning actually comes from, which is not where §6.2 says.
    ///
    /// A realistic record gives 24 factors and **236** pairs that are not empty by
    /// construction. Stage 1 is supposed to cut that down, and on the person who
    /// has something to find it barely does: 236 → **218**, because "at least one
    /// constituent has signal" is nearly free once a record contains one strong
    /// activity — the registry asks each activity against *everything else*, so one
    /// dominant activity hands every other activity a large contrast of its own.
    /// The budget carries that case: 218 → **60**.
    ///
    /// On the person with nothing to find, stage 1 does the work it was designed
    /// for: 236 → **48**, and the budget never binds. That is the right direction
    /// — the search is smallest where there is least to find — but it means the
    /// bound on the worst case is the budget and not the tree.
    @Test("Main-effect gating prunes the search space")
    func gatingPrunes() {
        let noise = SyntheticCohort.scatteredNoise
        let noiseRows = rows(for: noise)
        let noisePlan = InteractionCandidates.plan(for: noiseRows, mainEffects: mainEffects(for: noise))

        #expect(noisePlan.combinatorialCount > 200, Comment(rawValue:
            "the unpruned space is supposed to be large; it was \(noisePlan.combinatorialCount)"))
        #expect(noisePlan.gated.count * 3 < noisePlan.combinatorialCount, Comment(rawValue:
            "gating kept \(noisePlan.gated.count) of \(noisePlan.combinatorialCount) pairs on a person "
            + "with no pattern, which is not pruning"))

        // And on a person who does have a pattern, the budget is what bounds it.
        let real = SyntheticCohort.morningDeepWork
        let realRows = rows(for: real)
        let realPlan = InteractionCandidates.plan(for: realRows, mainEffects: mainEffects(for: real))

        #expect(realPlan.candidates.count * 3 < realPlan.combinatorialCount, Comment(rawValue:
            "\(realPlan.candidates.count) tested of \(realPlan.combinatorialCount) conceivable "
            + "(\(realPlan.gated.count) survived gating), which is not far below"))
        #expect(realPlan.candidates.count <= InteractionBudget.maximumCandidates, Comment(rawValue:
            "\(realPlan.candidates.count) candidates over a budget of \(InteractionBudget.maximumCandidates)"))
    }

    /// The three-way arm has to be reachable, not merely written.
    ///
    /// It was not, at first: the two-way pass spent the entire budget on anybody
    /// with a main effect, so `remaining` was always zero and no three-way was ever
    /// generated. Reserving a quarter of the budget fixes it, and this person is
    /// how that stays fixed — the factor sleep splits is where most of his effect
    /// lives, and a search that stops at two factors finds something true and
    /// incomplete.
    @Test("A real three-way is reached and measured")
    func threeWayIsReachable() {
        let person = SyntheticCohort.morningDeepWorkAfterSleep
        let found = InteractionCandidates.findings(
            for: EngineInput(observations: rows(for: person)),
            mainEffects: mainEffects(for: person),
            resamples: Self.resamples)

        let threes = found.filter { $0.conjunction.factors.count == 3 }
        #expect(!threes.isEmpty, "no three-way candidate was reached at all")
        #expect(found.count <= InteractionBudget.maximumCandidates, Comment(rawValue:
            "\(found.count) tests run against a budget of \(InteractionBudget.maximumCandidates)"))

        let planted = threes.first {
            $0.conjunction.id.contains("activity.deep-work")
                && $0.conjunction.id.contains("time.morning")
                && $0.conjunction.id.contains("health.sleepHours.high")
        }
        #expect(planted != nil, Comment(rawValue:
            "the planted three-way was not among \(threes.map(\.conjunction.id))"))
        if let planted {
            #expect(planted.interaction.lift >= InteractionLift.minimumLift, Comment(rawValue:
                "the planted three-way measured \(fmt(planted.interaction.lift))"))
        }
    }

    @Test("The budget drops the tail untested")
    func budgetCapsCandidates() {
        let person = SyntheticCohort.scatteredNoise
        let observations = rows(for: person)
        let effects = mainEffects(for: person)
        let full = InteractionCandidates.plan(for: observations, mainEffects: effects)
        let capped = InteractionCandidates.plan(for: observations, mainEffects: effects, budget: 3)

        #expect(capped.candidates.count == min(3, full.gated.count))
        #expect(capped.droppedToBudget == max(0, full.gated.count - 3))
        // The tail is dropped, not the head: what survives a smaller budget is a
        // prefix of what survives a larger one, so tightening the budget never
        // changes which questions are considered most worth asking.
        #expect(capped.candidates.map(\.id) == Array(full.candidates.map(\.id).prefix(3)))
    }

    // MARK: - Determinism

    @Test("Generation is deterministic")
    func deterministicGeneration() {
        let person = SyntheticCohort.morningDeepWork
        let observations = rows(for: person)
        let effects = mainEffects(for: person)
        let first = InteractionCandidates.plan(for: observations, mainEffects: effects)
        let second = InteractionCandidates.plan(for: observations, mainEffects: effects)

        #expect(first.candidates.map(\.id) == second.candidates.map(\.id))
        #expect(first.factors.map(\.key) == second.factors.map(\.key))

        // And the measurement with it: an evidence line that moves between two
        // runs on identical data is not evidence.
        guard let candidate = first.candidates.first else { return }
        let a = InteractionCandidates.screen(candidate, in: observations, resamples: Self.resamples).lift
        let b = InteractionCandidates.screen(candidate, in: observations, resamples: Self.resamples).lift
        #expect(a?.lift == b?.lift)
    }

    @Test("A conjunction's id does not depend on the order its factors arrived in")
    func conjunctionIdIsOrderIndependent() throws {
        let observations = rows(for: SyntheticCohort.morningDeepWork)
        let forwards = try #require(conjunction(of: ["activity.deep-work", "time.morning"], in: observations))
        let backwards = try #require(conjunction(of: ["time.morning", "activity.deep-work"], in: observations))
        #expect(forwards.id == backwards.id)
        // And so does the measurement, which is a stronger claim: the conditioning
        // side is chosen by sorted key, not by arrival.
        #expect(InteractionCandidates.screen(forwards, in: observations, resamples: Self.resamples).lift?.lift
                == InteractionCandidates.screen(backwards, in: observations, resamples: Self.resamples).lift?.lift)
    }

    // MARK: - Rows built by hand

    /// Sessions with stated activities and hours, for the cases the cohort cannot
    /// express — an empty cell has to be empty by construction, and a generator
    /// that draws from a distribution will eventually fill it.
    private static func handBuilt(
        days: Int,
        _ slot: (_ day: Int, _ index: Int) -> (activity: String, hour: Int)
    ) -> [EngineObservation] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        var out: [EngineObservation] = []
        for day in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -day, to: anchor) else { continue }
            for index in 0..<2 {
                let (activity, hour) = slot(day, index)
                guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)
                else { continue }
                out.append(EngineObservation(
                    sessionId: UUID(),
                    day: date,
                    startAt: start,
                    durationMinutes: 45,
                    activityName: activity,
                    activityCategory: "work",
                    timeBucket: TimeBucket.bucket(forHour: hour),
                    durationBucket: .medium,
                    isWorkday: calendar.component(.weekday, from: date) != 1,
                    feeling: Double(3 + (day % 3) - 1),
                    performance: 3,
                    dayHealth: [:],
                    heartRateResidual: nil,
                    cadence: nil
                ))
            }
        }
        return out
    }
}
