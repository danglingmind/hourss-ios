import Testing
import Foundation
@testable import Hourss

/// Layer 4: shrinkage, surprise ranking, and the recommendations built on them.
@Suite("Shrinkage, surprise and recommendations")
@MainActor
struct RecommendationTests {

    private func rows(for person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay
        )
    }

    // MARK: - Shrinkage

    @Test("A thin group is pulled further than a well-evidenced one")
    func thinGroupsShrinkHarder() throws {
        // Both sit the same distance above the crowd; only the evidence differs.
        //
        // The day means must actually vary. With every day identical the within-
        // group variance is zero, the estimates are perfectly precise, and no
        // shrinkage is the correct answer — a fixture with no noise in it cannot
        // test a technique whose entire job is discounting noise.
        let groups = [
            Shrinkage.Group(key: "thin", dayMeans: spread(around: 4.6, count: 2)),
            Shrinkage.Group(key: "solid", dayMeans: spread(around: 4.6, count: 30)),
            Shrinkage.Group(key: "a", dayMeans: spread(around: 3.0, count: 20)),
            Shrinkage.Group(key: "b", dayMeans: spread(around: 3.2, count: 20)),
            Shrinkage.Group(key: "c", dayMeans: spread(around: 2.8, count: 20)),
        ]
        let result = Shrinkage.shrink(groups)
        let thin = try #require(result.estimates["thin"])
        let solid = try #require(result.estimates["solid"])

        #expect(abs(thin.pull) > abs(solid.pull), Comment(rawValue:
                "thin moved \(thin.pull), solid moved \(solid.pull)"))
        #expect(thin.weight < solid.weight)
    }

    @Test("Shrinkage never pushes an estimate past the grand mean")
    func shrinkageNeverOvershoots() {
        let groups = [
            Shrinkage.Group(key: "high", dayMeans: [5, 5]),
            Shrinkage.Group(key: "low", dayMeans: [1, 1]),
            Shrinkage.Group(key: "mid", dayMeans: Array(repeating: 3.0, count: 15)),
        ]
        let result = Shrinkage.shrink(groups)
        for estimate in result.estimates.values {
            let towardMean = estimate.raw <= result.grandMean
                ? (estimate.shrunk >= estimate.raw && estimate.shrunk <= result.grandMean + 1e-9)
                : (estimate.shrunk <= estimate.raw && estimate.shrunk >= result.grandMean - 1e-9)
            #expect(towardMean, Comment(rawValue:
                    "\(estimate.key): \(estimate.raw) -> \(estimate.shrunk), grand \(result.grandMean)"))
        }
    }

    @Test("A single group has nothing to be pulled toward")
    func loneGroupIsUntouched() throws {
        let result = Shrinkage.shrink([Shrinkage.Group(key: "only", dayMeans: [4, 2, 3])])
        let estimate = try #require(result.estimates["only"])
        #expect(estimate.raw == estimate.shrunk)
        #expect(estimate.weight == 1)
    }

    @Test("Shrinkage counts days, not sessions")
    func shrinkageCountsDays() {
        // Six sessions on two days is two days of evidence, not six.
        let observations = SyntheticCohort.afternoonSlump.sessions.prefix(0)
        #expect(observations.isEmpty)   // guard against the fixture drifting

        let groups = Shrinkage.groups(in: rows(for: SyntheticCohort.afternoonSlump)) { $0.timeBucket.rawValue }
        for group in groups {
            let distinctDays = Set(
                rows(for: SyntheticCohort.afternoonSlump)
                    .filter { $0.timeBucket.rawValue == group.key && $0.feeling != nil }
                    .map(\.day)
            ).count
            #expect(group.dayMeans.count == distinctDays, Comment(rawValue:
                    "\(group.key) reported \(group.dayMeans.count) values for \(distinctDays) days"))
        }
    }

    // MARK: - Surprise

    /// The finding this ranking exists to fix: ranking by magnitude leads with the
    /// most obvious true thing about a person.
    @Test("An obvious pattern ranks below a surprising one of equal strength")
    func obviousRanksBelowSurprising() {
        let obvious = finding(id: "workday.non.vs.work.feeling", delta: 0.45)
        let surprising = finding(id: "activity.learning.vs.rest.feeling", delta: 0.45)
        #expect(Surprise.score(surprising) > Surprise.score(obvious), Comment(rawValue:
                "obvious \(Surprise.score(obvious)) vs surprising \(Surprise.score(surprising))"))
    }

    @Test("A pattern running against the usual direction outranks the same effect running with it")
    func directionViolationOutranks() {
        // Days off usually feel better. This person's feel worse.
        let ordinary = finding(id: "workday.non.vs.work.feeling", delta: 0.40)
        let violating = finding(id: "workday.non.vs.work.feeling", delta: -0.40)
        #expect(Surprise.score(violating) > Surprise.score(ordinary), Comment(rawValue:
                "with \(Surprise.score(ordinary)) vs against \(Surprise.score(violating))"))
    }

    @Test("The sleep association, the most quoted finding there is, ranks near the bottom")
    func sleepRanksLow() {
        let sleep = finding(id: "health.sleepHours.higher.vs.lower.feeling", delta: 0.40)
        let unusual = finding(id: "health.respiratoryRate.higher.vs.lower.feeling", delta: 0.40)
        #expect(Surprise.score(unusual) > Surprise.score(sleep))
    }

    @Test("Evidence quality orders claims of the same kind but cannot lift an obvious one")
    func evidenceCannotOutrankSurprise() {
        // A rock-solid obvious claim against a merely decent surprising one.
        let obvious = finding(id: "workday.non.vs.work.feeling", delta: 0.75, low: 0.60, high: 0.90)
        let surprising = finding(id: "activity.creative.vs.rest.feeling", delta: 0.30, low: 0.16, high: 0.44)
        #expect(Surprise.score(surprising) > Surprise.score(obvious), Comment(rawValue:
                "a strongly evidenced obvious claim outranked a surprising one"))
    }

    @Test("A person's own activity carries no prior and is therefore neutral")
    func unknownSubjectsAreNeutral() {
        let mine = finding(id: "activity.tuba-practice.vs.rest.feeling", delta: 0.4)
        #expect(Surprise.expectedness(of: Surprise.pattern(of: mine)) == 0.5)
    }

    @Test("Ranking is deterministic")
    func rankingIsStable() {
        let findings = [
            finding(id: "activity.creative.vs.rest.feeling", delta: 0.4),
            finding(id: "workday.non.vs.work.feeling", delta: 0.4),
            finding(id: "health.sleepHours.higher.vs.lower.feeling", delta: 0.4),
        ]
        #expect(Surprise.ranked(findings).map(\.hypothesis.id)
                == Surprise.ranked(findings).map(\.hypothesis.id))
    }

    // MARK: - Recommendations

    @Test("A person with no pattern gets no recommendation")
    func noPatternNoRecommendation() {
        let recommendations = Recommendations.build(
            for: EngineInput(observations: rows(for: SyntheticCohort.flatline),
                             priorities: [.energy, .focus])
        )
        #expect(recommendations.isEmpty, Comment(rawValue:
                "noise produced \(recommendations.count) recommendations"))
    }

    @Test("Nothing is recommended when nothing was said to matter")
    func noPrioritiesNoRecommendation() {
        let recommendations = Recommendations.build(
            for: EngineInput(observations: rows(for: SyntheticCohort.afternoonSlump))
        )
        #expect(recommendations.isEmpty)
    }

    @Test("Priority order changes what comes first")
    func priorityOrderMatters() {
        let observations = rows(for: SyntheticCohort.afternoonSlump)
        let focusFirst = Recommendations.build(
            for: EngineInput(observations: observations, priorities: [.focus, .energy, .balance]))
        let balanceFirst = Recommendations.build(
            for: EngineInput(observations: observations, priorities: [.balance, .energy, .focus]))

        guard let a = focusFirst.first, let b = balanceFirst.first else {
            // Nothing survived for either order; the assertion below would be
            // vacuous, so say so rather than passing silently.
            #expect(focusFirst.isEmpty && balanceFirst.isEmpty,
                    "one order produced a recommendation and the other did not")
            return
        }
        #expect(a.priorityRank == 0 && b.priorityRank == 0)
        #expect(a.priority == .focus || b.priority == .balance,
                "neither order led with its own first priority")
    }

    @Test("Every recommendation rests on a claim the feed would also make")
    func recommendationsRestOnPublishedClaims() {
        let input = EngineInput(observations: rows(for: SyntheticCohort.afternoonSlump),
                                priorities: [.focus, .energy])
        let published = Set(Engine.run(input).map(\.id))
        for recommendation in Recommendations.build(for: input) {
            #expect(published.contains(recommendation.insightId), Comment(rawValue:
                    "recommendation cites \(recommendation.insightId), which the feed does not publish"))
            #expect(!recommendation.caveat.isEmpty)
        }
    }

    @Test("No recommendation reads as instruction, diagnosis or population comparison")
    func recommendationCopyStaysWithinBounds() {
        let forbidden = ["you should", "you must", "stress", "diagnos",
                         "most people", "average person", "normal range", "unhealthy"]
        for person in SyntheticCohort.everyone {
            let input = EngineInput(observations: rows(for: person),
                                    priorities: [.energy, .focus, .balance])
            for recommendation in Recommendations.build(for: input) {
                let text = (recommendation.claim + " " + recommendation.action + " "
                            + recommendation.caveat).lowercased()
                for word in forbidden {
                    #expect(!text.contains(word), Comment(rawValue:
                            "\(person.name): \"\(recommendation.action)\" contains \"\(word)\""))
                }
            }
        }
    }

    // MARK: - The two tiers must not converge

    /// Experiments are free and propose a test. Recommendations are paid and
    /// state what held up. Nothing enforces that but this.
    ///
    /// It is not a hypothetical drift: every recommendation string once opened
    /// with "Try" and closed with "this week", and one branch returned the
    /// hypothesis's own experiment text verbatim, so the paid feature emitted the
    /// free one word for word.
    @Test("No recommendation is phrased as an experiment")
    func recommendationsDoNotProposeTests() {
        let testingLanguage = ["try ", "see whether", "see if", "this week",
                               "for a week", "experiment", "give it a go", "test "]
        for person in SyntheticCohort.everyone {
            let input = EngineInput(observations: rows(for: person),
                                    priorities: [.energy, .focus, .balance, .sleep])
            for recommendation in Recommendations.build(for: input) {
                let text = (recommendation.action + " " + recommendation.claim).lowercased()
                for phrase in testingLanguage {
                    #expect(!text.contains(phrase), Comment(rawValue:
                            "\(person.name): \"\(recommendation.action)\" reads as an experiment (\"\(phrase)\")"))
                }
            }
        }
    }

    @Test("No recommendation repeats an insight's experiment verbatim")
    func recommendationsAreNotExperiments() {
        for person in SyntheticCohort.everyone {
            let input = EngineInput(observations: rows(for: person),
                                    priorities: [.energy, .focus, .balance, .sleep])
            let experiments = Set(Engine.run(input).compactMap(\.experiment))
            for recommendation in Recommendations.build(for: input) {
                #expect(!experiments.contains(recommendation.action), Comment(rawValue:
                        "\(person.name): the paid recommendation is the free experiment, verbatim"))
            }
        }
    }

    /// Experiments keep their own voice. A check the person runs has to read as
    /// one, or the free tier stops being useful in its own right.
    @Test("Experiments still propose a test rather than issue an instruction")
    func experimentsStillReadAsTests() {
        let instructions = ["you should", "you must", "make sure", "always ", "never "]
        for person in SyntheticCohort.everyone {
            let input = EngineInput(observations: rows(for: person))
            for experiment in Engine.run(input).compactMap(\.experiment) {
                let text = experiment.lowercased()
                for phrase in instructions {
                    #expect(!text.contains(phrase), Comment(rawValue:
                            "\(person.name): \"\(experiment)\" instructs rather than proposes"))
                }
            }
        }
    }

    // MARK: - Fixtures

    /// Day means scattered around a centre, deterministically. A fixed cycle
    /// rather than a generator, so the numbers in a failure message are the same
    /// ones a reader can work through by hand.
    private func spread(around centre: Double, count: Int) -> [Double] {
        let offsets = [0.6, -0.5, 0.3, -0.7, 0.4, -0.2, 0.8, -0.6, 0.1, -0.3]
        return (0..<count).map { centre + offsets[$0 % offsets.count] }
    }

    /// A `Finding` with a chosen hypothesis id and effect, for testing ranking in
    /// isolation from whether the effect is real.
    private func finding(id: String, delta: Double,
                         low: Double? = nil, high: Double? = nil) -> Finding {
        let lo = low ?? (delta - 0.18)
        let hi = high ?? (delta + 0.18)
        return Finding(
            hypothesis: Hypothesis(
                id: id, type: .activityEnergizer, outcome: .feeling,
                focusLabel: "Focus", baselineLabel: "Baseline",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "" }, caveat: "An association, not a cause."
            ),
            comparison: Statistics.Comparison(
                delta: delta, low: lo, high: hi,
                focusCount: 30, baselineCount: 70,
                focusDays: 20, baselineDays: 40, pValue: 0.004
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.8, baselineCoverage: 0.8,
            survivesCorrection: true, windowDays: 90
        )
    }
}
