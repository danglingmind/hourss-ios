import Foundation
import Testing
@testable import Hourss

/// That a running test is visible without going to look for it.
@Suite("Running test strip")
@MainActor
struct RunningStripTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

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

    @Test("Nothing running means nothing in the header")
    func quietWhenNothingIsOn() {
        let store = store(SyntheticCohort.afternoonSlump)
        // A header with an empty state in it has stopped being a header, and the
        // slot below already says when no test is on — by offering one.
        #expect(store.activeExperiment == nil)
    }

    @Test("A running test is reachable from the store without running the engine")
    func cheapToRead() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let proposal = try #require(store.experimentProposals().first)
        let experiment = try #require(store.acceptExperiment(proposal, now: Self.start))

        // The strip reads this and nothing else. If it needed the engine it would be
        // running two thousand resamples inside a header that redraws on every
        // keystroke elsewhere in the app.
        #expect(store.activeExperiment?.id == experiment.id)
        #expect(store.activeExperiment?.change == proposal.change)
    }

    @Test("A drawn window says whether today is one of its days, and a chosen one says nothing")
    func todaysState() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let drawable = try #require(store.experimentProposals().first { $0.canRandomise })
        let drawn = try #require(store.acceptRandomisedExperiment(drawable, now: Self.start))
        let assignment = try #require(drawn.assignment)

        let picked = try #require(assignment.dayOffsets.first)
        let notPicked = try #require((0..<drawn.windowDays).first { !assignment.dayOffsets.contains($0) })
        func day(_ offset: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: offset, to: Self.start)!
        }

        #expect(ExperimentCopy.today(for: drawn, on: day(picked)) == "Today is one of your days.")
        #expect(ExperimentCopy.today(for: drawn, on: day(notPicked)) == "Today is not one of your days.")

        // Outside the window there is nothing true to say, so it says nothing.
        #expect(ExperimentCopy.today(for: drawn, on: day(drawn.windowDays + 1)) == nil)

        // And a chosen window has no days to name.
        store.abandonExperiment(drawn, now: Self.start)
        let next = try #require(store.experimentProposals().first)
        let chosen = try #require(store.acceptExperiment(next, now: Self.start))
        #expect(ExperimentCopy.today(for: chosen, on: day(1)) == nil)
    }
}

/// That a weekend contrast says its size in the unit people actually use.
@Suite("Contrast size")
struct ContrastSizeTests {

    @Test("Under a doubling it is a percentage")
    func percentages() {
        #expect(HealthDigest.contrastSize(0.12, higher: true).phrase == "12% higher")
        #expect(HealthDigest.contrastSize(0.42, higher: false).phrase == "42% lower")
        #expect(HealthDigest.contrastSize(0.99, higher: true).phrase == "99% higher")
    }

    /// The case that produced "423% higher" on screen.
    @Test("Past a doubling it is a multiple, because that is how people say it")
    func multiples() {
        // Workout minutes near zero on weekdays make this ratio unbounded. The
        // number was arithmetically right and read as a broken one.
        #expect(HealthDigest.contrastSize(1.0, higher: true).phrase == "about twice as high")
        #expect(HealthDigest.contrastSize(2.0, higher: true).phrase == "about 3 times as high")
        #expect(HealthDigest.contrastSize(4.23, higher: true).phrase == "about 5 times as high")
        for strength in [1.0, 2.0, 4.23, 20.0] {
            #expect(!HealthDigest.contrastSize(strength, higher: true).phrase.contains("%"))
        }
    }

    @Test("A lower weekend can never be a multiple")
    func lowerStaysAPercentage() {
        // `strength` is the gap over the weekday mean, so when weekends read lower
        // it cannot pass 1 — the weekend mean would have to go below zero. Nothing
        // should ever print "about twice as low".
        for strength in [0.5, 1.0, 3.0] {
            let phrase = HealthDigest.contrastSize(strength, higher: false).phrase
            #expect(phrase.hasSuffix("lower"))
            #expect(!phrase.contains("times"))
        }
    }

    @Test("Both branches stay grammatical in the sentence they land in")
    func grammar() {
        for (strength, higher) in [(0.12, true), (0.42, false), (1.0, true), (4.23, true)] {
            let sentence = "Your workout time reads \(HealthDigest.contrastSize(strength, higher: higher).phrase) at weekends."
            #expect(!sentence.contains("as higher"))
            #expect(!sentence.contains("% as"))
        }
    }
}
