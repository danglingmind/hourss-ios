import Foundation
import Testing
@testable import Hourss

/// The whole chain, on a realistic record rather than hand-built findings.
///
/// Every other experiment suite builds its own `Finding` values, which is right for
/// testing one layer and useless for proving the layers fit together. These run the
/// real engine over a synthetic person, so a change that quietly stops producing
/// proposals — a filter that excludes everything, a registry id that no longer
/// matches — fails here rather than in the simulator.
@Suite("Experiment integration")
@MainActor
struct ExperimentIntegrationTests {

    private func store(for person: SyntheticCohort.Person,
                       priorities: [Priority] = [.focus, .energy]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = priorities
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        store.rebuildInsights()
        return store
    }

    @Test("A person with a real pattern is offered something to test")
    func theChainProduces() throws {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let proposals = store.experimentProposals()

        #expect(!proposals.isEmpty, "the engine survived its gates but produced no proposal")
        let first = try #require(proposals.first)
        // Every part a card needs, present and non-empty.
        #expect(!first.change.isEmpty)
        #expect(!first.premise.isEmpty)
        #expect(!first.caveat.isEmpty)
        #expect(store.profile.priorities.contains(first.priority))
        // The hypothesis is findable again, which is what settling depends on.
        #expect(store.hypothesis(for: first.hypothesisId) != nil)
    }

    @Test("Accepting, waiting and settling produces a readable verdict")
    func theLoopCloses() throws {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first)

        // Opened far enough back that the window closes inside the record, so the
        // fortnight has real sessions in it rather than an empty future.
        let opened = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let experiment = try #require(store.acceptExperiment(proposal, now: opened))
        #expect(store.activeExperiment?.id == experiment.id)
        #expect(store.experimentProposals().isEmpty, "a proposal was offered mid-fortnight")

        #expect(store.settleClosedExperiments(now: Date()))
        let settled = try #require(store.experiments.first)
        let settlement = try #require(settled.settlement)

        // Any of the three verdicts is a pass — which one depends on the cohort and
        // on what day this runs. What must hold is that it reached a verdict at all
        // and can describe it.
        let sentence = ExperimentCopy.result(for: settled, settlement: settlement)
        #expect(!sentence.isEmpty)
        #expect(settlement.adherenceDays >= 0)

        // And the result card can be built from it.
        let copy = ObservationSlot.copy(for: .settledExperiment(id: settled.id),
                                        experiment: settled)
        #expect(!copy.eyebrow.isEmpty)
        #expect(!copy.accessibilityLabel.isEmpty)
    }

    @Test("A fortnight with the change in it can actually be read")
    func adherenceAccrues() throws {
        // The cohort logs most days, so a window over its own history should clear
        // the six-day floor on both sides — if it cannot, the floor is unreachable in
        // practice and the feature only ever says "not enough to tell".
        let store = store(for: SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first)
        let opened = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let experiment = try #require(store.acceptExperiment(proposal, now: opened))

        let reading = store.reading(for: experiment)
        #expect(reading.adherenceDays >= Experiment.minimumDays,
                Comment(rawValue: "only \(reading.adherenceDays) days of adherence in a "
                        + "fortnight of a heavy logger — the floor may be unreachable"))
        #expect(reading.verdict != .cannotTell)
    }

    @Test("Declining promotes the next proposal rather than emptying the slot")
    func decliningMovesOn() throws {
        let store = store(for: SyntheticCohort.afternoonSlump, priorities: [.focus, .energy])
        let first = try #require(store.experimentProposals().first)
        store.declineExperiment(first)

        let after = store.experimentProposals()
        #expect(!after.contains { $0.hypothesisId == first.hypothesisId })
        // Not asserting that something else exists — that depends on the cohort — but
        // if it does, it must be a different question.
        if let next = after.first { #expect(next.hypothesisId != first.hypothesisId) }
    }

    /// That the shared path and the separate paths cannot disagree.
    @Test("One engine run gives the same answers as two")
    func slotOutputAgreesWithTheSeparatePaths() {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let output = store.slotOutput()

        // The engine is deterministic over the record, so these must match exactly.
        // If they ever stop matching, the correction is being applied differently on
        // the two paths and one of the surfaces is making a claim the other refused.
        #expect(output.recommendations.map(\.id) == store.slotRecommendations().map(\.id))
        #expect(output.proposals.map(\.id) == store.experimentProposals().map(\.id))
    }

    @Test("The shared path offers nothing mid-fortnight either")
    func slotOutputRespectsAnActiveWindow() throws {
        let store = store(for: SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.slotOutput().proposals.first)
        store.acceptExperiment(proposal, now: Date())
        // The guard is duplicated on the two paths, so it is asserted on both.
        #expect(store.slotOutput().proposals.isEmpty)
        #expect(store.experimentProposals().isEmpty)
        // Recommendations are unaffected — they are a different surface.
        #expect(!store.slotOutput().recommendations.isEmpty)
    }

    @Test("Everything the chain produces is allowed on screen")
    func realCopyPassesTheGuard() {
        let store = store(for: SyntheticCohort.afternoonSlump,
                          priorities: Priority.allCases)
        for proposal in store.experimentProposals() {
            for text in [proposal.change, proposal.premise] {
                let offence = NarrationGuard.offence(
                    in: text, allowingFigures: NarrationGuard.figures(in: text))
                switch offence {
                case .none, .instruction: continue
                case .some(let found):
                    Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
                }
            }
        }
    }
}

/// The drawn-day chain, on the same synthetic people the rest of this file uses.
///
/// Separate suite rather than more cases in the one above, because every test here
/// needs a four-week window rather than a fortnight and the helper that opens one
/// is the only thing they share.
@Suite("Experiment integration, drawn days")
@MainActor
struct RandomisedExperimentIntegrationTests {

    private func store(for person: SyntheticCohort.Person,
                       priorities: [Priority] = [.focus, .energy]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = priorities
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        store.rebuildInsights()
        return store
    }

    /// If this fails the feature is unreachable, whatever else passes.
    @Test("A real person is offered at least one proposal whose days can be drawn")
    func somethingRealCanBeDrawn() throws {
        let store = store(for: SyntheticCohort.afternoonSlump, priorities: Priority.allCases)
        let proposals = store.experimentProposals()
        #expect(!proposals.isEmpty)
        #expect(proposals.contains { $0.canRandomise },
                Comment(rawValue: "no proposal on a real record could have its days drawn — "
                        + "filter 4 excludes everything the engine actually produces"))
        // And the ask exists for exactly those, so a card cannot offer the control
        // without the paragraph that earns it.
        for proposal in proposals {
            #expect((proposal.randomisedAsk != nil) == proposal.canRandomise)
        }
    }

    @Test("Accepting, living a month and settling produces a readable verdict")
    func theLoopCloses() throws {
        let store = store(for: SyntheticCohort.afternoonSlump, priorities: Priority.allCases)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })

        // Opened far enough back that four weeks close inside the record, so the
        // window holds real sessions rather than an empty future.
        let opened = Calendar.current.date(
            byAdding: .day, value: -(Experiment.randomisedWindowDays + 2), to: Date())!
        let experiment = try #require(store.acceptRandomisedExperiment(proposal, now: opened))
        #expect(store.activeExperiment?.id == experiment.id)
        #expect(store.experimentProposals().isEmpty, "a proposal was offered mid-window")

        // The active card's three strings all exist while it runs.
        #expect(ExperimentCopy.assignedDays(for: experiment) != nil)
        #expect(ExperimentCopy.today(for: experiment, on: opened) != nil)

        #expect(store.settleClosedExperiments(now: Date()))
        let settled = try #require(store.experiments.first)
        let settlement = try #require(settled.settlement)

        // Any verdict is a pass — which one depends on the cohort and on the draw.
        // What must hold is that contamination was measured at all, and that the
        // result can be said.
        #expect(settlement.contaminationDays != nil)
        #expect(!ExperimentCopy.result(for: settled, settlement: settlement).isEmpty)
        #expect(settled.assignment == experiment.assignment)
    }

    @Test("A heavy logger contaminates a drawn window, and it says so rather than reading it")
    func contaminationIsTheRealisticOutcome() throws {
        // This cohort logs a morning block on most of its days, which is exactly the
        // case the contamination gate is for: high adherence on the drawn days, the
        // change happening anyway on the rest, and no contrast left. The honest answer
        // is that the month cannot be read — and a verdict here would be a difference
        // measured between two indistinguishable halves of a month.
        let store = store(for: SyntheticCohort.afternoonSlump, priorities: Priority.allCases)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })
        let opened = Calendar.current.date(
            byAdding: .day, value: -(Experiment.randomisedWindowDays + 2), to: Date())!
        let experiment = try #require(store.acceptRandomisedExperiment(proposal, now: opened))

        let reading = store.reading(for: experiment)
        let contamination = try #require(reading.contaminationDays)
        let contrast = try #require(reading.contrastDays)
        if contrast < Experiment.minimumDays {
            #expect(reading.verdict == .cannotTell)
            #expect(contamination > 0)
        } else if reading.armsSeparated == false {
            // Clearing the contrast floor is not the same as having a contrast left to
            // read. A heavy logger can leave six clean days beside eight carrying the
            // change, and two arms that differ in the change on a minority of their
            // days cannot be told apart whatever the floor says.
            #expect(reading.verdict == .cannotTell)
            #expect(contamination > 0)
        } else {
            // A record this heavy clearing both conditions is possible and not a
            // failure; what is asserted either way is that the counts agree with the
            // verdict rather than that one particular month came out one way.
            #expect(reading.adherenceDays < Experiment.minimumDays
                    || reading.verdict != .cannotTell)
        }
    }

    @Test("Everything a drawn window puts on a real screen is allowed on it")
    func realCopyPassesTheGuard() throws {
        let store = store(for: SyntheticCohort.afternoonSlump, priorities: Priority.allCases)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })
        let opened = Calendar.current.date(
            byAdding: .day, value: -(Experiment.randomisedWindowDays + 2), to: Date())!
        let experiment = try #require(store.acceptRandomisedExperiment(proposal, now: opened))
        store.settleClosedExperiments(now: Date())
        let settled = try #require(store.experiments.first)

        var strings = [experiment.change, experiment.caveat, experiment.premise]
        strings += [proposal.randomisedAsk, ExperimentCopy.assignedDays(for: experiment),
                    ExperimentCopy.today(for: experiment, on: opened)].compactMap { $0 }
        if let settlement = settled.settlement {
            strings.append(ExperimentCopy.result(for: settled, settlement: settlement))
        }
        for text in strings {
            let offence = NarrationGuard.offence(
                in: text, allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }
}
