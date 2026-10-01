import Foundation
import Testing
@testable import Hourss

/// That the store takes on one experiment at a time, never re-asks a refused
/// question, and closes a window when it runs out rather than when somebody looks.
@Suite("Experiment store")
@MainActor
struct ExperimentStoreTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private func store() -> HourssStore {
        HourssStore(repository: InMemoryRecordRepository())
    }

    private func proposal(_ id: String = "time.morning.vs.rest.feeling") -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: id, outcome: .feeling, type: .bestTimeWindow, standing: .confirmed,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            change: "Put one block in your morning on most days this fortnight.",
            caveat: "Time of day travels with whatever you tend to schedule then.",
            priority: .focus, priorityRank: 0, evidenceDays: 20,
            figure: 4.1, baselineFigure: 3.5)
    }

    // MARK: One at a time

    @Test("Accepting records the commitment and makes it the active one")
    func accepting() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))

        #expect(store.experiments.count == 1)
        #expect(store.activeExperiment?.id == experiment.id)
        #expect(experiment.change == proposal().change)
        #expect(store.unacknowledgedExperiment == nil)
    }

    /// The invariant the whole feature rests on.
    @Test("A second experiment is refused while one is running, not queued")
    func oneAtATime() {
        let store = store()
        #expect(store.acceptExperiment(proposal("a"), now: Self.start) != nil)
        // Refused, and nothing is written — a queued experiment would start on a
        // date nobody was told about.
        #expect(store.acceptExperiment(proposal("b"), now: Self.start) == nil)
        #expect(store.experiments.count == 1)
    }

    @Test("Abandoning frees the slot and leaves no verdict")
    func abandoning() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))
        store.abandonExperiment(experiment, now: Self.start.addingTimeInterval(86_400))

        #expect(store.activeExperiment == nil)
        #expect(store.experiments.first?.phase == .abandoned)
        #expect(store.experiments.first?.settlement == nil)
        // The slot is free, so another can be taken on.
        #expect(store.acceptExperiment(proposal("b"), now: Self.start) != nil)
    }

    @Test("Abandoning something already finished does nothing")
    func abandoningIsOnlyForActiveOnes() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))
        store.abandonExperiment(experiment, now: Self.start)
        let firstStamp = store.experiments.first?.abandonedAt

        store.abandonExperiment(experiment, now: Self.start.addingTimeInterval(99_999))
        #expect(store.experiments.first?.abandonedAt == firstStamp)
    }

    // MARK: Declines

    @Test("A refused question is never offered again, and survives a relaunch")
    func declinesArePermanent() throws {
        let repository = InMemoryRecordRepository()
        let first = HourssStore(repository: repository)
        first.declineExperiment(proposal("time.morning.vs.rest.feeling"))
        #expect(first.experimentKeysToExclude.contains("time.morning.vs.rest.feeling"))

        // A fresh store over the same record: the refusal is still there, because an
        // app that forgot is not an app that is allowed to ask again.
        let second = HourssStore(repository: repository)
        #expect(second.declinedExperiments.contains("time.morning.vs.rest.feeling"))
        #expect(second.experimentKeysToExclude.contains("time.morning.vs.rest.feeling"))
    }

    @Test("Anything already tested is excluded, including what was abandoned")
    func testedThingsAreNotReoffered() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal("a"), now: Self.start))
        #expect(store.experimentKeysToExclude.contains("a"))

        store.abandonExperiment(experiment, now: Self.start)
        // Still excluded. Somebody who started and stopped has answered the
        // question of whether they want to run it.
        #expect(store.experimentKeysToExclude.contains("a"))
    }

    @Test("Nothing is proposed while one is running")
    func noProposalsMidFortnight() {
        let store = store()
        store.acceptExperiment(proposal(), now: Self.start)
        #expect(store.experimentProposals().isEmpty)
    }

    // MARK: Settling

    @Test("A window closes when it runs out, not when somebody looks")
    func settlingCrossesTheBoundary() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))
        let closes = experiment.endsAt()

        // The day before: nothing settles, however often this is called.
        #expect(!store.settleClosedExperiments(now: closes.addingTimeInterval(-86_400)))
        #expect(store.activeExperiment != nil)
        #expect(store.unacknowledgedExperiment == nil)

        // On the boundary: it settles, exactly once.
        #expect(store.settleClosedExperiments(now: closes))
        #expect(store.activeExperiment == nil)
        #expect(store.experiments.first?.phase == .settled)
        // There are no observations in this store, so the honest verdict is that
        // there is nothing to read — not that the change failed.
        #expect(store.experiments.first?.settlement?.verdict == .cannotTell)

        let settlement = store.experiments.first?.settlement
        // Called again much later: already settled, so nothing is rewritten.
        #expect(!store.settleClosedExperiments(now: closes.addingTimeInterval(60 * 86_400)))
        #expect(store.experiments.first?.settlement == settlement)
    }

    @Test("A settled result waits to be seen, then stops claiming the slot")
    func acknowledging() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))
        store.settleClosedExperiments(now: experiment.endsAt())

        #expect(store.unacknowledgedExperiment?.id == experiment.id)
        store.acknowledgeExperiment(experiment, now: experiment.endsAt())

        #expect(store.unacknowledgedExperiment == nil)
        #expect(store.experiments.first?.phase == .acknowledged)
        // The figures stay: acknowledging is not discarding.
        #expect(store.experiments.first?.settlement != nil)
    }

    @Test("Settling frees the slot for the next one")
    func settlingFreesTheSlot() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal("a"), now: Self.start))
        store.settleClosedExperiments(now: experiment.endsAt())
        #expect(store.acceptExperiment(proposal("b"), now: experiment.endsAt()) != nil)
        #expect(store.experiments.count == 2)
    }

    @Test("Everything survives a relaunch")
    func persistence() throws {
        let repository = InMemoryRecordRepository()
        let first = HourssStore(repository: repository)
        let experiment = try #require(first.acceptExperiment(proposal(), now: Self.start))
        first.settleClosedExperiments(now: experiment.endsAt())
        first.declineExperiment(proposal("something.else"))

        let second = HourssStore(repository: repository)
        #expect(second.experiments.count == 1)
        #expect(second.experiments.first?.phase == .settled)
        #expect(second.experiments.first?.change == proposal().change)
        #expect(second.declinedExperiments.contains("something.else"))
    }
}
