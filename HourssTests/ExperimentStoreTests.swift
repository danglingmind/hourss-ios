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
            hypothesisId: id, outcome: .feeling, type: .bestTimeWindow, standing: .confirmed, basis: .measured,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            context: nil,
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

    // MARK: Drawn days

    @Test("Accepting with the days drawn stores the days and the seed")
    func acceptingADrawnWindow() throws {
        let store = store()
        let experiment = try #require(store.acceptRandomisedExperiment(proposal(), now: Self.start))

        let assignment = try #require(experiment.assignment)
        #expect(experiment.isRandomised)
        #expect(experiment.windowDays == Experiment.randomisedWindowDays)
        #expect(assignment.assignedCount == Experiment.randomisedWindowDays / 2)
        // The change is the drawn one, not the proposal's: a drawn window asks for
        // particular days and for restraint on the rest, which is a different ask.
        #expect(experiment.change != proposal().change)
        #expect(experiment.change.contains("picked for you"))
        #expect(experiment.caveat.hasPrefix(proposal().caveat))
        // Pre-registration, both halves of it, before any of the data exists.
        #expect(experiment.predictsHigher)
        #expect(store.activeExperiment?.id == experiment.id)
    }

    /// The one invariant that makes the draw worth anything.
    @Test("The days are never drawn again, by settling or by relaunching")
    func theDaysAreDrawnOnce() throws {
        let repository = InMemoryRecordRepository()
        let first = HourssStore(repository: repository)
        let experiment = try #require(
            first.acceptRandomisedExperiment(proposal(), now: Self.start))
        let drawn = try #require(experiment.assignment)

        // Across a settling, which is the one place that rewrites an experiment.
        first.settleClosedExperiments(now: experiment.endsAt())
        #expect(first.experiments.first?.assignment == drawn)

        // And across a relaunch, which is where a seed-only design would have been
        // free to redraw them under somebody mid-window.
        let second = HourssStore(repository: repository)
        #expect(second.experiments.first?.assignment == drawn)
        #expect(second.experiments.first?.assignment?.seed == drawn.seed)
    }

    @Test("A drawn window is refused where the days cannot carry the change")
    func refusedWhereTheDaysMeanNothing() {
        let store = store()
        // A sleep association splits on a Health reading, and a drawn day is not a
        // day of longer sleep — so the two arms would differ in nothing and the
        // result would wear a randomised test's clothes with none of its content.
        let sleep = ExperimentDesign.Proposal(
            hypothesisId: "health.sleepHours.higher.vs.lower.feeling", outcome: .feeling,
            type: .sleepContext, standing: .confirmed, basis: .measured,
            focusLabel: "Longer nights", baselineLabel: "Shorter nights",
            premise: "p", context: nil,
            change: "On a day after a longer night, put your bigger block in.",
            caveat: "v", priority: .sleep, priorityRank: 0, evidenceDays: 20,
            figure: 4.1, baselineFigure: 3.5)
        #expect(!sleep.canRandomise)
        #expect(sleep.randomisedAsk == nil)
        #expect(store.acceptRandomisedExperiment(sleep, now: Self.start) == nil)
        #expect(store.experiments.isEmpty)
        // The ordinary kind is still on offer for it, which is the point of the draw
        // being a second kind rather than a replacement.
        #expect(store.acceptExperiment(sleep, now: Self.start) != nil)
    }

    @Test("A window too short to supply both arms is refused rather than stretched")
    func refusedWhenTooShort() {
        let store = store()
        // Half of eleven days is five, and five cannot clear a floor of six however
        // well somebody adheres. Stretching it to four weeks silently would be the
        // app changing the terms of something somebody agreed to.
        #expect(store.acceptRandomisedExperiment(proposal(), now: Self.start,
                                                 windowDays: 2 * Experiment.minimumDays - 1) == nil)
        #expect(store.experiments.isEmpty)
        #expect(store.acceptRandomisedExperiment(proposal(), now: Self.start,
                                                 windowDays: 2 * Experiment.minimumDays) != nil)
    }

    @Test("One at a time holds across the two kinds")
    func oneAtATimeAcrossKinds() {
        let store = store()
        #expect(store.acceptRandomisedExperiment(proposal("a"), now: Self.start) != nil)
        // Neither kind may start while the other is running: two concurrent changes
        // make both unreadable whichever way their days were decided.
        #expect(store.acceptExperiment(proposal("b"), now: Self.start) == nil)
        #expect(store.acceptRandomisedExperiment(proposal("c"), now: Self.start) == nil)
        #expect(store.experiments.count == 1)
    }

    @Test("The ordinary kind still carries no assignment at all")
    func theChosenKindIsUnchanged() throws {
        let store = store()
        let experiment = try #require(store.acceptExperiment(proposal(), now: Self.start))
        #expect(experiment.assignment == nil)
        #expect(!experiment.isRandomised)
        #expect(experiment.windowDays == Experiment.defaultWindowDays)
        #expect(experiment.change == proposal().change)
        #expect(store.reading(for: experiment).contaminationDays == nil)
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
