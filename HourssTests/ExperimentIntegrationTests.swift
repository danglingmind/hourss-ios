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
