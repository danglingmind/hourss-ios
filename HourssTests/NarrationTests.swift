import Testing
import Foundation
@testable import Hourss

/// Everything about narration that can be checked without a model.
///
/// Which is nearly all of it, and deliberately so. The model does not run in a
/// simulator, its output is not deterministic, and a layer whose correctness
/// could only be established by running it would be a layer nobody could ship
/// with confidence. So the design puts the model in the middle of a sandwich
/// that is entirely testable: the template underneath it, which is what most
/// people will read; the guard above it, which decides whether anything it wrote
/// may be shown; and the figures, which never pass through it at all.
///
/// What these tests do *not* establish is listed at the bottom of the file.
@Suite("Narration")
struct NarrationTests {

    // MARK: - Fixtures

    private static func rows(for person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay
        )
    }

    private static func conjunction(
        of keys: [String],
        in observations: [EngineObservation]
    ) -> Conjunction? {
        let available = InteractionCandidates.factors(in: observations)
        let wanted = keys.compactMap { key in available.first { $0.key == key } }
        guard wanted.count == keys.count else { return nil }
        return Conjunction(factors: wanted, outcome: .feeling)
    }

    /// A comparison with the one field narration reads, and plausible values in
    /// the rest. The arithmetic is `Statistics`' business and is tested there;
    /// what is under test here is that the *sign* reaches the right word and that
    /// no other number reaches the sentence at all.
    private static func comparison(delta: Double) -> Statistics.Comparison {
        Statistics.Comparison(delta: delta,
                              low: delta - 0.1, high: delta + 0.1,
                              focusCount: 0, baselineCount: 0,
                              focusDays: 0, baselineDays: 0,
                              pValue: 0.001)
    }

    private static func lift(combined: Double) -> InteractionLift {
        InteractionLift(within: comparison(delta: 0.5),
                        without: comparison(delta: 0.1),
                        lift: 0.4,
                        isEstimable: true,
                        combined: comparison(delta: combined))
    }

    /// A finding over a real person's real cells, with the statistics supplied.
    ///
    /// `InteractionCandidates.partition` is the same function the layer itself
    /// uses, so the session ids and the days behind the sample limit are the ones
    /// a genuine run would produce. Only the deltas are hand-set, because the
    /// direction of the claim is what the phrasing turns on and both directions
    /// have to be reachable.
    private static func finding(
        _ conjunction: Conjunction,
        in observations: [EngineObservation],
        combined: Double = 0.42,
        windowDays: Int = 42
    ) -> InteractionFinding {
        let cells = InteractionCandidates.partition(conjunction, in: observations)
        return InteractionFinding(
            conjunction: conjunction,
            interaction: lift(combined: combined),
            focusSessionIds: cells.within.sessionIds,
            baselineSessionIds: cells.withinBaseline.sessionIds
                + cells.without.sessionIds + cells.withoutBaseline.sessionIds,
            windowDays: windowDays,
            survivesCorrection: true
        )
    }

    private static func evidence(
        _ keys: [String],
        in person: SyntheticCohort.Person,
        combined: Double = 0.42
    ) throws -> NarrationEvidence {
        let observations = rows(for: person)
        let conjunction = try #require(Self.conjunction(of: keys, in: observations))
        let finding = Self.finding(conjunction, in: observations, combined: combined)
        return try #require(NarrationEvidence(finding: finding, observations: observations))
    }

    // MARK: - The template, which is the product

    /// The two-way sentence, in full, in both directions.
    ///
    /// Asserted verbatim rather than by keyword. This string is what a person on
    /// an iPhone 14 sees, forever, and a test that only checked it mentioned
    /// "morning" somewhere would let the grammar rot without saying so.
    @Test("Two-way narrates in both directions")
    func twoWayTemplate() throws {
        let up = try Self.evidence(["activity.deep-work", "time.morning"],
                                   in: SyntheticCohort.morningDeepWork, combined: 0.42)

        #expect(NarrationTemplate.sentence(for: up).hasPrefix(
            "Your Deep work sessions in the morning have felt more energizing than the rest of your sessions. "
            + "The same is not true of deep work elsewhere in your record. "
            + "Observed across "))

        let down = try Self.evidence(["activity.deep-work", "time.morning"],
                                     in: SyntheticCohort.morningDeepWork, combined: -0.42)

        #expect(NarrationTemplate.sentence(for: down).hasPrefix(
            "Your Deep work sessions in the morning have felt more draining than the rest of your sessions. "
            + "The same is not true of deep work elsewhere in your record. "
            + "Observed across "))
    }

    /// The three-way sentence, in full, in both directions.
    ///
    /// The health factor is fronted rather than queued behind the hour, which is
    /// the one structural decision in the template — `HypothesisRegistry` writes
    /// "On days after a longer night, your sessions have felt …" and a conjunction
    /// that said it the other way round would be the same claim in a second voice.
    @Test("Three-way fronts the health factor, in both directions")
    func threeWayTemplate() throws {
        let keys = ["activity.deep-work", "health.sleepHours.high", "time.morning"]

        let up = try Self.evidence(keys, in: SyntheticCohort.morningDeepWorkAfterSleep, combined: 0.42)
        #expect(NarrationTemplate.sentence(for: up).hasPrefix(
            "On days after a longer night, your Deep work sessions in the morning have felt "
            + "more energizing than the rest of your sessions. "
            + "The same is not true of deep work elsewhere in your record. "
            + "Observed across "))

        let down = try Self.evidence(keys, in: SyntheticCohort.morningDeepWorkAfterSleep, combined: -0.42)
        #expect(NarrationTemplate.sentence(for: down).hasPrefix(
            "On days after a longer night, your Deep work sessions in the morning have felt "
            + "more draining than the rest of your sessions. "
            + "The same is not true of deep work elsewhere in your record. "
            + "Observed across "))
    }

    /// A conjunction with no activity in it still has to be a sentence.
    ///
    /// "Your sessions" carries the qualifiers instead of a name, and the leading
    /// factor named on its own has to fit the contrast frame whichever family it
    /// came from. This is the combination the template would fail on first if the
    /// grammar were built around the activity case.
    @Test("A conjunction without an activity still reads")
    func noActivity() throws {
        let observations = Self.rows(for: SyntheticCohort.morningDeepWork)
        let conjunction = try #require(
            Self.conjunction(of: ["duration.medium", "time.morning"], in: observations))
        let finding = Self.finding(conjunction, in: observations)
        let evidence = try #require(NarrationEvidence(finding: finding, observations: observations))

        #expect(NarrationTemplate.sentence(for: evidence).hasPrefix(
            "Your sessions of 30 to 89 minutes in the morning have felt more energizing "
            + "than the rest of your sessions. "
            + "The same is not true of your sessions of 30 to 89 minutes elsewhere in your record. "
            + "Observed across "))
    }

    // MARK: - Figures

    /// Every number in the sentence, against the record it came from.
    ///
    /// The design rule is that the model never touches a figure, which is only
    /// worth anything if the figures we compose are right. Counted here from the
    /// observations directly rather than from anything narration produced, so the
    /// two can disagree.
    @Test("The sample limit matches the evidence record exactly")
    func figuresMatchTheRecord() throws {
        let observations = Self.rows(for: SyntheticCohort.morningDeepWork)
        let conjunction = try #require(
            Self.conjunction(of: ["activity.deep-work", "time.morning"], in: observations))
        let finding = Self.finding(conjunction, in: observations, windowDays: 42)
        let evidence = try #require(NarrationEvidence(finding: finding, observations: observations))

        let cells = InteractionCandidates.partition(conjunction, in: observations)
        let sessions = cells.within.sessionIds.count
        let days = cells.within.days.count

        #expect(evidence.sessionCount == sessions, "session count is the conjunction's own cell")
        #expect(evidence.dayCount == days, "day count is the distinct days behind that cell")

        let sentence = NarrationTemplate.sentence(for: evidence)
        #expect(sentence.hasSuffix("Observed across \(sessions) sessions over \(days) distinct days, past 6 weeks."),
                Comment(rawValue: "sample limit did not match the record: \(sentence)"))

        // And nothing else numeric leaked in. Every digit run in the sentence is
        // one of the two counts or the window's own figure; neither factor here
        // carries a figure of its own.
        let accountedFor = Set(["\(sessions)", "\(days)"])
            .union(NarrationGuard.figures(in: Engine.describe(windowDays: 42)))
        #expect(NarrationGuard.figures(in: sentence) == accountedFor,
                Comment(rawValue: "unexpected figures in: \(sentence)"))
    }

    /// The window is described no more generously than the evidence supports,
    /// which is `Engine.describe`'s rule and narration must not acquire its own.
    @Test("The window is the finding's, not the run's")
    func windowFollowsTheFinding() throws {
        let observations = Self.rows(for: SyntheticCohort.morningDeepWork)
        let conjunction = try #require(
            Self.conjunction(of: ["activity.deep-work", "time.morning"], in: observations))

        for days in [1, 14, 42, 120] {
            let finding = Self.finding(conjunction, in: observations, windowDays: days)
            let evidence = try #require(NarrationEvidence(finding: finding, observations: observations))
            #expect(NarrationTemplate.sentence(for: evidence).hasSuffix(", \(Engine.describe(windowDays: days))."),
                    Comment(rawValue: "window \(days) was not described as Engine describes it"))
        }
    }

    /// Singulars, because "1 sessions over 1 distinct days" is the kind of thing
    /// that ships.
    @Test("One session over one day reads as one")
    func singulars() {
        let evidence = NarrationEvidence(
            findingId: "complex.activity.deep-work.time.morning.vs.rest.feeling",
            terms: [.init(family: .activity, value: "deep-work", label: "Deep work"),
                    .init(family: .time, value: "morning", label: "morning")],
            outcome: .feeling, isHigher: true,
            sessionCount: 1, dayCount: 1, windowDays: 1)

        #expect(NarrationTemplate.sentence(for: evidence)
            .hasSuffix("Observed across 1 session over 1 distinct day, past day."))
    }

    // MARK: - The guard

    @Test("The guard rejects a causal claim")
    func rejectsCausation() {
        #expect(NarrationGuard.offence(in: "Your mornings have felt better because you slept longer.")
                == .causal("because"))
        #expect(NarrationGuard.offence(in: "Longer nights lead to better deep work.")
                == .causal("lead to"))
        #expect(NarrationGuard.offence(in: "Deep work in the morning makes you feel sharper.")
                == .causal("makes you"))
    }

    @Test("The guard rejects a medical or psychological claim")
    func rejectsClinicalClaims() {
        #expect(NarrationGuard.offence(in: "Your morning sessions show lower stress.")
                == .clinical("stress"))
        #expect(NarrationGuard.offence(in: "Deep work lifts your mood in the morning.")
                == .clinical("mood"))
        #expect(NarrationGuard.offence(in: "Your energy levels hold up in the morning.")
                == .clinical("energy levels"))
    }

    @Test("The guard rejects a population comparison")
    func rejectsPopulationComparison() {
        #expect(NarrationGuard.offence(in: "Like most people, you do deep work best in the morning.")
                == .population("most people"))
        #expect(NarrationGuard.offence(in: "That is a normal pattern to see.")
                == .population("normal"))
        #expect(NarrationGuard.offence(in: "Your mornings run above the average.")
                == .population("average"))
    }

    @Test("The guard rejects an instruction")
    func rejectsInstruction() {
        #expect(NarrationGuard.offence(in: "You should keep your deep work in the morning.")
                == .instruction("you should"))
        #expect(NarrationGuard.offence(in: "Try moving one afternoon block to the morning.")
                == .instruction("try"))
        #expect(NarrationGuard.offence(in: "Make sure the longer blocks land before midday.")
                == .instruction("make sure"))
    }

    /// A figure the record does not contain is an invention, and the reason the
    /// model is never handed one.
    @Test("The guard rejects a figure the record did not supply")
    func rejectsInventedFigures() {
        #expect(NarrationGuard.offence(in: "Your mornings have felt better across 18 sessions.")
                == .invention("18"))
        #expect(NarrationGuard.offence(in: "That held on about 40 percent of your days.")
                == .invention("40"))

        // The same figure, when it is the app's own phrase, passes.
        #expect(NarrationGuard.accepts("Your sessions of 30 to 89 minutes have read differently.",
                                       allowingFigures: ["30", "89"]))
        #expect(!NarrationGuard.accepts("Your sessions of 30 to 89 minutes have read differently.",
                                        allowingFigures: ["30"]))
    }

    /// Good prose that happens to contain forbidden words as substrings.
    ///
    /// "Carpentry" contains "try"; "normally" contains "normal"; "energizing" is
    /// the registry's own word and would be caught by any rule broad enough to
    /// catch "energy levels". If the guard rejects this sentence it will reject
    /// somebody's activity name, and the feature will quietly stop working for
    /// them and nobody else.
    @Test("The guard accepts good prose containing near-miss words")
    func acceptsNearMisses() {
        let clean = "Your Carpentry sessions normally run in the morning, and they have "
            + "felt more energizing than the rest of your sessions."
        #expect(NarrationGuard.offence(in: clean) == nil,
                Comment(rawValue: "rejected clean prose: \(String(describing: NarrationGuard.offence(in: clean)))"))

        // Every template sentence has to survive its own guard, or the fallback
        // would be a thing the app refuses to print.
        for keys in [["activity.deep-work", "time.morning"],
                     ["activity.deep-work", "health.sleepHours.high", "time.morning"]] {
            let observations = Self.rows(for: SyntheticCohort.morningDeepWorkAfterSleep)
            guard let conjunction = Self.conjunction(of: keys, in: observations),
                  let evidence = NarrationEvidence(
                      finding: Self.finding(conjunction, in: observations),
                      observations: observations)
            else { continue }

            let sentence = NarrationTemplate.sentence(for: evidence)
            let figures = NarrationGuard.figures(in: sentence)
            #expect(NarrationGuard.accepts(sentence, allowingFigures: figures),
                    Comment(rawValue: "the template tripped its own guard: \(sentence)"))
        }
    }

    // MARK: - Availability

    /// Every reason lands on the template, and none of them is an error.
    ///
    /// Four cases rather than the one the simulator reports, which is the whole
    /// reason `Narration.Availability` is our own type rather than Apple's.
    @Test("Every unavailable reason yields the template", arguments: Narration.Availability.Reason.allCases)
    func unavailableYieldsTemplate(reason: Narration.Availability.Reason) throws {
        let evidence = try Self.evidence(["activity.deep-work", "time.morning"],
                                         in: SyntheticCohort.morningDeepWork)
        let plan = Narration.plan(for: evidence, availability: .unavailable(reason))

        #expect(plan.sentence == NarrationTemplate.sentence(for: evidence),
                "an unavailable model must still produce the full template sentence")
        #expect(!plan.mayRefine, "nothing should be asked of a model that is not there")
        #expect(!plan.sentence.isEmpty, "the template is never empty")
    }

    @Test("An unavailable model leaves the store on the template", arguments: Narration.Availability.Reason.allCases)
    func storeFallsBack(reason: Narration.Availability.Reason) async throws {
        let evidence = try Self.evidence(["activity.deep-work", "time.morning"],
                                         in: SyntheticCohort.morningDeepWork)
        let store = await NarrationStore(availability: .unavailable(reason))

        await store.refine(evidence)
        let sentence = await store.sentence(for: evidence)
        let refined = await store.refined

        #expect(sentence == NarrationTemplate.sentence(for: evidence))
        #expect(refined.isEmpty, "nothing should have been recorded for an unavailable model")

        // And `refine` returns nothing rather than throwing or hanging.
        let direct = await Narration.refine(evidence, availability: .unavailable(reason))
        #expect(direct == nil)
    }

    /// A model that *is* available still produces the template first. The feed
    /// renders from `plan.sentence` on the frame it asks, and the refinement is a
    /// separate event that may never arrive.
    @Test("An available model still renders the template immediately")
    func templateFirst() throws {
        let evidence = try Self.evidence(["activity.deep-work", "time.morning"],
                                         in: SyntheticCohort.morningDeepWork)
        let plan = Narration.plan(for: evidence, availability: .ready)

        #expect(plan.sentence == NarrationTemplate.sentence(for: evidence))
        #expect(plan.mayRefine)
    }

    // MARK: - Scope

    /// Single factors are the registry's job and narration must never reach for
    /// them.
    ///
    /// `Conjunction` will happily hold one factor — nothing in the contract
    /// forbids it — so the refusal has to be made somewhere, and it is made at
    /// the point evidence is extracted, before availability is even consulted.
    /// A path into generation that skipped the check would have to skip evidence
    /// extraction too, which is not a thing that can be done by accident.
    @Test("Narration is never attempted for a single-factor finding")
    func refusesSingleFactors() async throws {
        let observations = Self.rows(for: SyntheticCohort.morningDeepWork)
        let single = try #require(Self.conjunction(of: ["activity.deep-work"], in: observations))
        let finding = Self.finding(single, in: observations)

        #expect(NarrationEvidence(finding: finding, observations: observations) == nil,
                "a one-factor conjunction has no narration evidence")
        #expect(Narration.plan(for: finding, observations: observations, availability: .ready) == nil,
                "a one-factor finding has no narration plan, model or no model")

        // Even handed an evidence value built by hand, with a model declared
        // ready, nothing is asked.
        let smuggled = NarrationEvidence(
            findingId: "complex.activity.deep-work.vs.rest.feeling",
            terms: [.init(family: .activity, value: "deep-work", label: "Deep work")],
            outcome: .feeling, isHigher: true,
            sessionCount: 20, dayCount: 14, windowDays: 42)

        #expect(!smuggled.isMultiFactor)
        #expect(!Narration.plan(for: smuggled, availability: .ready).mayRefine)
        #expect(await Narration.refine(smuggled, availability: .ready) == nil)

        let store = await NarrationStore(availability: .ready)
        await store.refine(smuggled)
        #expect(await store.refined.isEmpty)
    }

    /// Two factors is the boundary, and the boundary is inclusive.
    @Test("Two factors is enough")
    func twoFactorsIsEnough() throws {
        let evidence = try Self.evidence(["activity.deep-work", "time.morning"],
                                         in: SyntheticCohort.morningDeepWork)
        #expect(evidence.isMultiFactor)
        #expect(evidence.terms.count == 2)
    }

    // MARK: - Ordering

    /// The contrast sentence names the factor the interaction was measured about,
    /// which is the first by sorted key — the same choice
    /// `InteractionCandidates.partition` makes when it decides which factor is A.
    ///
    /// Not cosmetic. `within − without` is the effect of A among B against the
    /// effect of A elsewhere, so "the same is not true of X elsewhere" is only
    /// true of X = A. Naming B there would assert something the lift did not
    /// measure.
    @Test("The contrast names the conditioning factor")
    func contrastNamesTheConditioningFactor() throws {
        let evidence = try Self.evidence(
            ["activity.deep-work", "health.sleepHours.high", "time.morning"],
            in: SyntheticCohort.morningDeepWorkAfterSleep)

        #expect(evidence.terms.map(\.family) == [.activity, .health, .time],
                "terms must arrive in sorted-key order, as the partition conditions on them")
        #expect(NarrationTemplate.sentence(for: evidence)
            .contains("The same is not true of deep work elsewhere in your record."))
    }

    /// The model is shown phrases and one composed sentence's worth of figures,
    /// and the figures it is permitted to echo are only those the phrases already
    /// carry.
    @Test("The model is handed phrases, never the sample")
    func modelSeesNoSample() throws {
        let evidence = try Self.evidence(["activity.deep-work", "time.morning"],
                                         in: SyntheticCohort.morningDeepWork)
        let parts = NarrationTemplate.parts(for: evidence)

        #expect(parts.supplied.allSatisfy { NarrationGuard.figures(in: $0).isEmpty },
                "no figure reaches the model for this conjunction")
        #expect(!parts.limit.isEmpty, "the sample limit exists and is ours")
        #expect(parts.supplied.allSatisfy { !$0.contains("Observed across") })

        // A length factor is the one case where a supplied phrase legitimately
        // carries digits, and those digits are what the guard will then allow.
        let observations = Self.rows(for: SyntheticCohort.morningDeepWork)
        let lengths = try #require(Self.conjunction(of: ["duration.medium", "time.morning"], in: observations))
        let withLength = try #require(NarrationEvidence(
            finding: Self.finding(lengths, in: observations), observations: observations))
        let lengthParts = NarrationTemplate.parts(for: withLength)
        let permitted = lengthParts.supplied.reduce(into: Set<String>()) {
            $0.formUnion(NarrationGuard.figures(in: $1))
        }
        #expect(permitted == Set(["30", "89"]),
                Comment(rawValue: "permitted figures were \(permitted.sorted())"))
    }

    // MARK: - Not established here
    //
    // Stated rather than assumed, because the gap is real:
    //
    // * **No generated string has been through the guard in a test.** The model
    //   is unavailable in the simulator, so every path below `Narration.refine`
    //   returns nil before a session is created. The guard is tested on prose
    //   written by hand, which is not the same distribution as prose written by a
    //   3B model under guided generation.
    // * **The instructions are unmeasured.** Whether they actually keep the model
    //   off causal language is unknown until it runs on a device. The guard is
    //   the thing that makes this safe regardless; the instructions are what make
    //   it good, and only the first of those two is verified here.
    // * **`@Generable` shape adherence is unverified.** That `NarratedFinding`
    //   comes back with two non-empty phrases rests on the framework's guarantee,
    //   not on an observation.
    // * **Latency is unmeasured.** The claim that nothing blocks rests on the
    //   store's structure — `sentence(for:)` is synchronous and total — rather
    //   than on a timing, and no wall-clock assertion would be sound in a
    //   parallel suite anyway.
}
