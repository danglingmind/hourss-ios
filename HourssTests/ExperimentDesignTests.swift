import Foundation
import Testing
@testable import Hourss

/// That a proposal is only offered where a change can honestly be asked for, and
/// that every sentence it can produce is allowed on screen.
@Suite("Experiment design")
struct ExperimentDesignTests {

    // MARK: Fixtures

    private func finding(
        id: String = "time.morning.vs.rest.feeling",
        type: InsightType = .bestTimeWindow,
        outcome: Outcome = .feeling,
        delta: Double = 0.42,
        low: Double? = nil,
        high: Double? = nil,
        focusDays: Int = 20,
        baselineDays: Int = 30,
        survivesCorrection: Bool? = true,
        focusLabel: String = "Morning"
    ) -> Finding {
        Finding(
            hypothesis: Hypothesis(
                id: id, type: type, outcome: outcome,
                focusLabel: focusLabel, baselineLabel: "The rest of your day",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "Your \(focusLabel.lowercased()) sessions have felt more energizing." },
                caveat: "Time of day travels with whatever you tend to schedule then."
            ),
            comparison: Statistics.Comparison(
                delta: delta, low: low ?? (delta - 0.18), high: high ?? (delta + 0.18),
                focusCount: focusDays, baselineCount: baselineDays,
                focusDays: focusDays, baselineDays: baselineDays, pValue: 0.004
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.8, baselineCoverage: 0.8,
            survivesCorrection: survivesCorrection, windowDays: 42
        )
    }

    private func input(_ priorities: [Priority]) -> EngineInput {
        EngineInput(observations: [], priorities: priorities)
    }

    // MARK: Eligibility

    @Test("A confirmed, directed, favourable finding of a doable type is eligible")
    func theHappyCase() {
        let f = finding()
        #expect(ExperimentDesign.isEligible(f))
        #expect(ExperimentDesign.standing(of: f) == .confirmed)
    }

    @Test("An undirected outcome cannot be experimented on")
    func undirectedIsExcluded() {
        // A heart-rate residual has no better side, so there is nothing to aim at.
        #expect(!ExperimentDesign.isEligible(
            finding(id: "physiology.deepwork.vs.rest.heartRateResidual",
                    outcome: .heartRateResidual)))
    }

    @Test("A focus side that reads worse cannot be experimented on")
    func unfavourableIsExcluded() {
        // Adherence is counted in days gained on the focus side, so this would be
        // asking somebody to do more of the thing that reads worst.
        #expect(!ExperimentDesign.isEligible(finding(delta: -0.42)))
    }

    @Test("A type nobody can act on is excluded however strong it is")
    func undoableTypesAreExcluded() {
        #expect(!ExperimentDesign.isEligible(
            finding(id: "x.y.z", type: .fragmentation, delta: 0.9, low: 0.7, high: 0.95)))
        // Filter 2: adherence counts days gained on the focus side, so doing less of
        // a draining window cannot be tested by doing more of it.
        #expect(!ExperimentDesign.isEligible(
            finding(id: "time.afternoon.vs.rest.feeling", type: .drainingTimeWindow,
                    delta: 0.9, low: 0.7, high: 0.95)))
    }

    /// The case that was excluded for the wrong reason.
    @Test("A workday contrast is testable, because its focus side is the days off")
    func workdayContrastIsDoable() throws {
        let f = finding(id: "workday.non.vs.work.feeling", type: .workdayContrast,
                        delta: 0.42, focusLabel: "Non-workdays")
        #expect(ExperimentDesign.isEligible(f))
        // Which days are workdays cannot be moved; what goes on them can.
        let change = try #require(ExperimentCopy.change(for: f))
        #expect(change.contains("days off"))
    }

    @Test("Responsive scheduling makes a health association doable")
    func healthAssociationsAreDoable() {
        let f = finding(id: "health.sleepHours.higher.vs.lower.feeling", type: .sleepContext)
        #expect(ExperimentDesign.isEligible(f))
        let change = ExperimentCopy.change(for: f)
        #expect(change != nil)
        // It asks when to put a block, never that the reading should change.
        let lowered = try! #require(change).lowercased()
        #expect(lowered.contains("put your bigger block"))
        #expect(!lowered.contains("sleep more"))
        #expect(!lowered.contains("sleep longer"))
    }

    // MARK: Standing

    @Test("A directional finding short of the gates is a lead, not a claim")
    func leadStanding() {
        // Correction not survived, but three days on each side.
        let f = finding(low: -0.1, focusDays: 4, baselineDays: 5, survivesCorrection: false)
        #expect(ExperimentDesign.standing(of: f) == .lead)
        #expect(ExperimentDesign.isEligible(f))
    }

    @Test("Below the lead floor there is nothing to test")
    func belowTheLeadFloor() {
        let f = finding(low: -0.1, focusDays: 2, baselineDays: 9, survivesCorrection: false)
        #expect(ExperimentDesign.standing(of: f) == nil)
        #expect(!ExperimentDesign.isEligible(f))
    }

    @Test("A lead is free and a confirmed claim is not")
    func entitlement() {
        let confirmed = ExperimentDesign.proposals(
            from: [finding()], input: input([.focus])).first
        #expect(confirmed?.standing == .confirmed)
        #expect(confirmed?.requiresMembership == true)

        let lead = ExperimentDesign.proposals(
            from: [finding(low: -0.1, focusDays: 4, baselineDays: 5, survivesCorrection: false)],
            input: input([.focus])).first
        #expect(lead?.standing == .lead)
        #expect(lead?.requiresMembership == false)
    }

    // MARK: Selection

    @Test("Proposals come back in the person's own order of priorities")
    func priorityOrder() {
        let findings = [
            finding(id: "time.morning.vs.rest.feeling", type: .bestTimeWindow),
            finding(id: "activity.deepwork.vs.rest.feeling", type: .activityEnergizer,
                    focusLabel: "Deep work"),
        ]
        // energy ranks first, and energy maps to activityEnergizer.
        let proposals = ExperimentDesign.proposals(from: findings, input: input([.energy, .focus]))
        #expect(proposals.count == 2)
        #expect(proposals.first?.priority == .energy)
        #expect(proposals.first?.type == .activityEnergizer)
        #expect(proposals.first?.priorityRank == 0)
        #expect(proposals.last?.priority == .focus)
    }

    @Test("A confirmed claim is preferred over a lead for the same priority")
    func confirmedBeatsLead() {
        let lead = finding(id: "duration.long.vs.rest.feeling", type: .durationSweetSpot,
                           delta: 0.8, low: -0.1, high: 0.95,
                           focusDays: 4, baselineDays: 4, survivesCorrection: false,
                           focusLabel: "90–179 min")
        let confirmed = finding(id: "time.morning.vs.rest.feeling", type: .bestTimeWindow)
        // Lead first in the array and with the larger effect, so only the standing
        // preference can put the confirmed one in front.
        let proposals = ExperimentDesign.proposals(from: [lead, confirmed], input: input([.focus]))
        #expect(proposals.count == 1)
        #expect(proposals.first?.standing == .confirmed)
    }

    @Test("Nothing is proposed twice, and declines are permanent")
    func declinesAreRespected() {
        let findings = [finding(id: "time.morning.vs.rest.feeling")]
        #expect(ExperimentDesign.proposals(from: findings, input: input([.focus])).count == 1)
        #expect(ExperimentDesign.proposals(
            from: findings, input: input([.focus]),
            excluding: ["time.morning.vs.rest.feeling"]).isEmpty)
    }

    @Test("Nothing was said about what matters, so nothing is proposed")
    func noPrioritiesNoProposals() {
        #expect(ExperimentDesign.proposals(from: [finding()], input: input([])).isEmpty)
    }

    /// This used to assert the opposite, and the hole it pinned was a filter applied
    /// one step too early rather than a gap in the hypothesis space.
    @Test("Balance gets a proposal, from the workday contrast")
    func balanceIsCovered() throws {
        let findings = [
            finding(id: "workday.non.vs.work.feeling", type: .workdayContrast,
                    delta: 0.42, focusLabel: "Non-workdays"),
            finding(id: "time.afternoon.vs.rest.feeling", type: .drainingTimeWindow,
                    delta: 0.9, low: 0.7, high: 0.95),
        ]
        let proposal = try #require(
            ExperimentDesign.proposals(from: findings, input: input([.balance])).first)
        #expect(proposal.type == .workdayContrast)
        #expect(proposal.priority == .balance)

        // Every stated priority now reaches a change, which is the property that
        // matters — a priority onboarding collects and the app can do nothing with
        // is a promise it cannot keep.
        for priority in Priority.allCases {
            #expect(!priority.insightTypes.isDisjoint(with: ExperimentDesign.experimentableTypes),
                    Comment(rawValue: "\(priority.title) has no testable insight type"))
        }
    }

    // MARK: Acceptance

    @Test("The commitment says exactly what the proposal said")
    func acceptanceCopiesTheWords() throws {
        let proposal = try #require(
            ExperimentDesign.proposals(from: [finding()], input: input([.focus])).first)
        let started = Date(timeIntervalSince1970: 1_767_225_600)
        let experiment = ExperimentDesign.experiment(from: proposal, startedAt: started)

        #expect(experiment.hypothesisId == proposal.hypothesisId)
        #expect(experiment.premise == proposal.premise)
        #expect(experiment.change == proposal.change)
        #expect(experiment.caveat == proposal.caveat)
        #expect(experiment.focusLabel == proposal.focusLabel)
        #expect(experiment.predictsHigher)
        #expect(experiment.startedAt == started)
        #expect(experiment.phase == .active)
        // Shared identity with the insight it rests on, as `Recommendation` has.
        #expect(proposal.id == Engine.identity(of: proposal.hypothesisId))
    }

    @Test("A lead quotes its day count, so it cannot read as a claim")
    func leadQuotesItsCount() throws {
        let proposal = try #require(ExperimentDesign.proposals(
            from: [finding(low: -0.1, focusDays: 4, baselineDays: 5, survivesCorrection: false)],
            input: input([.focus])).first)
        #expect(proposal.premise.contains("so far"))
        #expect(proposal.premise.contains("4 days"))
    }

    // MARK: Copy

    /// Every string this layer can produce, swept for the bans that still apply.
    ///
    /// `instruction` is excluded and only `instruction`: a proposal's whole job is
    /// to ask for a change, and `NarrationGuard`'s own comment on that list says the
    /// free tier proposes a test. Causal, clinical and population offences are
    /// failures here exactly as they are in narration.
    ///
    /// Starters are swept here too rather than in their own suite, because the bans
    /// are one rule and a second sweep is a second place for somebody to loosen it.
    /// Their premise is the only string in the feature this app does not write — the
    /// Health half is carried verbatim from `HealthDigest` — so the sweep runs over
    /// the assembled sentence rather than only the clause added to it.
    @Test("No experiment copy makes a causal, clinical or population claim")
    func copyPassesTheGuard() {
        var strings: [String] = []

        for (type, id) in [(InsightType.bestTimeWindow, "time.morning.vs.rest.feeling"),
                           (.durationSweetSpot, "duration.long.vs.rest.feeling"),
                           (.activityEnergizer, "activity.deepwork.vs.rest.feeling"),
                           (.sleepContext, "health.sleepHours.higher.vs.lower.feeling"),
                           (.bodyContext, "health.restingHeartRate.higher.vs.lower.feeling")] {
            let f = finding(id: id, type: type)
            if let change = ExperimentCopy.change(for: f) { strings.append(change) }
            strings.append(ExperimentCopy.premise(for: f, standing: .confirmed, days: 20))
            strings.append(ExperimentCopy.premise(for: f, standing: .lead, days: 4))
            strings.append(ExperimentCopy.premise(for: f, standing: .lead, days: 1))
            // Unreachable in production — `standing(of:)` never returns `.starter` —
            // but it is a branch that returns a string, so it is swept.
            strings.append(ExperimentCopy.premise(for: f, standing: .starter, days: 0))
        }

        let experiment = Experiment(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: .feeling,
            startedAt: Date(), focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "p", change: "c", caveat: "v")

        // Every string a starter can produce, over every priority. Starters are the
        // one path whose premise is not written by this app — the Health half is
        // carried from `HealthDigest` — so the sweep has to run over the assembled
        // sentence rather than only over the clause `ExperimentCopy` adds to it.
        for priority in Priority.allCases {
            for starter in ExperimentStarters.starters(
                for: [priority],
                healthByDay: StarterFixture.healthByDay,
                activities: Activity.defaults) {
                strings.append(starter.premise)
                strings.append(starter.change)
            }
            // And with one metric between them, which is what fires the generic tail
            // and so produces a different change for the same priority.
            for starter in ExperimentStarters.starters(
                for: [priority],
                healthByDay: StarterFixture.healthByDay(only: .steps),
                activities: Activity.defaults) {
                strings.append(starter.premise)
                strings.append(starter.change)
            }
        }

        // Every shape a starter's second sentence can take, including the arms no
        // shape reaches today, and every Health fact that can supply the first.
        let pool = StarterFixture.pool
        for type in [InsightType.bestTimeWindow, .durationSweetSpot, .activityEnergizer,
                     .workdayContrast, .sleepContext, .bodyContext, .drainingTimeWindow,
                     .activityDrain, .performanceFeelingSplit, .fragmentation, .emergingChange] {
            for metric in [HealthMetric?.none] + HealthMetric.allCases.map({ $0 }) {
                let unknown = ExperimentCopy.starterUnknown(
                    type: type, focusLabel: "Morning",
                    baselineLabel: "Rest of the day", metric: metric)
                strings.append(unknown)
                for fact in pool {
                    strings.append(ExperimentCopy.starterPremise(fact.sentence, unknown: unknown))
                }
            }
        }

        // And the labels every real shape puts into those sentences, so a bucket or
        // metric name that broke a rule would fail here rather than on a card.
        for bucket in TimeBucket.allCases {
            strings.append(ExperimentCopy.starterUnknown(
                type: .bestTimeWindow, focusLabel: bucket.label,
                baselineLabel: "Rest of the day", metric: nil))
        }
        for bucket in DurationBucket.allCases {
            strings.append(ExperimentCopy.starterUnknown(
                type: .durationSweetSpot, focusLabel: bucket.label,
                baselineLabel: "Other lengths", metric: nil))
        }
        for activity in Activity.defaults {
            strings.append(ExperimentCopy.starterUnknown(
                type: .activityEnergizer, focusLabel: activity.name,
                baselineLabel: "Everything else", metric: nil))
        }

        // The drawn-window strings, swept here as well as in
        // `ExperimentAssignmentCopyTests`: the bans are one rule, and the sweep that
        // runs over every type is the one a new family would be added to.
        strings.append(ExperimentCopy.randomisedAsk(
            windowDays: Experiment.randomisedWindowDays,
            assignedDays: Experiment.randomisedWindowDays / 2))
        strings.append(ExperimentCopy.randomisedCaveat(
            "Time of day travels with whatever you tend to schedule then."))
        for type in [InsightType.bestTimeWindow, .durationSweetSpot, .activityEnergizer,
                     .workdayContrast, .sleepContext, .bodyContext, .drainingTimeWindow,
                     .activityDrain, .performanceFeelingSplit, .fragmentation,
                     .emergingChange] {
            for label in ["Morning", "Deep work", "30 to 89 minutes"] {
                if let change = ExperimentCopy.randomisedChange(type: type, focusLabel: label) {
                    strings.append(change)
                }
            }
        }
        var drawn = experiment
        drawn.assignment = Experiment.Assignment.make(
            hypothesisId: drawn.hypothesisId, startedAt: drawn.startedAt,
            windowDays: Experiment.randomisedWindowDays)
        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp, .cannotTell] {
            for (adherence, baseline, contamination) in
                [(12, 14, 0), (12, 14, 11), (3, 14, 2), (8, 2, 0), (0, 0, 0)] {
                strings.append(ExperimentCopy.result(
                    for: drawn,
                    settlement: Experiment.Settlement(
                        verdict: verdict, adherenceDays: adherence, baselineDays: baseline,
                        contaminationDays: contamination,
                        focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
                        intervalLow: 0.1, intervalHigh: 0.7, settledAt: Date())))
            }
        }

        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp, .cannotTell] {
            strings.append(ExperimentCopy.verdictTitle(verdict))
            // Every shortfall shape, so each branch of `cannotTell` is swept.
            for (adherence, baseline) in [(10, 10), (3, 10), (10, 3), (2, 2), (0, 0)] {
                strings.append(ExperimentCopy.result(
                    for: experiment,
                    settlement: Experiment.Settlement(
                        verdict: verdict, adherenceDays: adherence, baselineDays: baseline,
                        focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
                        intervalLow: 0.1, intervalHigh: 0.7, settledAt: Date())))
            }
        }

        for text in strings {
            let figures = NarrationGuard.figures(in: text)
            let offence = NarrationGuard.offence(in: text, allowingFigures: figures)
            switch offence {
            case .none, .instruction:
                continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }

    @Test("A verdict that cannot be read names what would have been enough")
    func cannotTellNamesTheFloor() {
        let experiment = Experiment(
            hypothesisId: "h", outcome: .feeling, startedAt: Date(),
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "p", change: "c", caveat: "v")
        func sentence(adherence: Int, baseline: Int) -> String {
            ExperimentCopy.result(for: experiment, settlement: Experiment.Settlement(
                verdict: .cannotTell, adherenceDays: adherence, baselineDays: baseline,
                focusFigure: 0, baselineFigure: 0, delta: 0,
                intervalLow: -1, intervalHigh: 1, settledAt: Date()))
        }
        #expect(sentence(adherence: 3, baseline: 20).contains("There were 3."))
        #expect(sentence(adherence: 20, baseline: 2).contains("There were 2."))
        #expect(sentence(adherence: 2, baseline: 3).contains("There were 2 and 3."))
        // Every shape names the floor, so "not enough" never arrives without it.
        for (a, b) in [(3, 20), (20, 2), (2, 3)] {
            #expect(sentence(adherence: a, baseline: b).contains("\(Experiment.minimumDays) days"))
        }
    }
}
