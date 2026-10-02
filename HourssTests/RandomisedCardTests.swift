import Foundation
import Testing
@testable import Hourss

/// That a drawn window can be offered, taken and followed from the cards.
///
/// The engine, the draw and every string existed before these: what was missing was
/// any route to them. A feature reachable only from its own tests is not shipped.
@Suite("Randomised card")
@MainActor
struct RandomisedCardTests {

    private func store(_ person: SyntheticCohort.Person) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy, .balance]
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        store.rebuildInsights()
        return store
    }

    @Test("A drawable proposal carries its ask, and an undrawable one carries none")
    func theAskIsOnlyWhereItCanBeTaken() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposals = store.experimentProposals()
        try #require(!proposals.isEmpty, "the cohort stopped producing proposals")

        for proposal in proposals {
            // The app can pick a day but cannot make it a day of longer sleep or a
            // day off, so offering a draw there would be the form of a randomised
            // test with none of its content.
            #expect((proposal.randomisedAsk != nil) == proposal.canRandomise)
            if proposal.canRandomise {
                let ask = try #require(proposal.randomisedAsk)
                #expect(!ask.isEmpty)
            }
        }
    }

    @Test("Taking the draw starts a drawn window, not an ordinary one")
    func takingTheDraw() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })
        let experiment = try #require(store.acceptRandomisedExperiment(proposal))

        let assignment = try #require(experiment.assignment, "no days were drawn")
        #expect(experiment.windowDays == Experiment.randomisedWindowDays)
        // Half the window, which is what makes two arms of equal size.
        #expect(assignment.dayOffsets.count == experiment.windowDays / 2)
        #expect(store.activeExperiment?.id == experiment.id)
    }

    @Test("The active card tells somebody whether today is one of their days")
    func theActiveCardIsFollowable() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let experiment = try #require(store.acceptRandomisedExperiment(proposal, now: start))
        let assignment = try #require(experiment.assignment)

        // A drawn and an undrawn day, from the draw itself rather than guessed.
        let drawn = try #require(assignment.dayOffsets.first)
        let notDrawn = try #require((0..<experiment.windowDays).first {
            !assignment.dayOffsets.contains($0)
        })

        func card(dayOffset: Int) -> SlotCopy {
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: start)!
            return ObservationSlot.copy(
                for: .activeExperiment(id: experiment.id), experiment: experiment,
                reading: ExperimentOutcome.Reading(
                    verdict: .cannotTell, adherenceDays: 2, baselineDays: 2,
                    focusFigure: 0, baselineFigure: 0, comparison: nil),
                daysRemaining: experiment.windowDays - dayOffset, now: day)
        }

        #expect(card(dayOffset: drawn).allStrings.contains("Today is one of your days."))
        #expect(card(dayOffset: notDrawn).allStrings.contains("Today is not one of your days."))
        // And the list itself, because fourteen dates do not fit in anybody's head.
        #expect(card(dayOffset: drawn).allStrings.contains { $0.hasPrefix("Your days:") })
    }

    @Test("A chosen window says none of that, because it has no days to name")
    func anOrdinaryWindowIsUnchanged() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first)
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let experiment = try #require(store.acceptExperiment(proposal, now: start))
        #expect(experiment.assignment == nil)

        let copy = ObservationSlot.copy(
            for: .activeExperiment(id: experiment.id), experiment: experiment,
            reading: ExperimentOutcome.Reading(
                verdict: .cannotTell, adherenceDays: 2, baselineDays: 2,
                focusFigure: 0, baselineFigure: 0, comparison: nil),
            daysRemaining: 9, now: start)

        for line in copy.allStrings {
            #expect(!line.hasPrefix("Your days:"))
            #expect(!line.contains("one of your days"))
        }
    }

    @Test("Every string the two cards can produce is allowed on screen")
    func copyPassesTheGuard() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first { $0.canRandomise })
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let experiment = try #require(store.acceptRandomisedExperiment(proposal, now: start))

        var strings = [try #require(proposal.randomisedAsk), ExperimentCopy.randomiseTitle]
        for offset in [0, 1, 13, 27] {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: start)!
            strings += ObservationSlot.copy(
                for: .activeExperiment(id: experiment.id), experiment: experiment,
                reading: nil, daysRemaining: 28 - offset, now: day).allStrings
        }

        for text in strings {
            let offence = NarrationGuard.offence(in: text,
                                                 allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }
}
