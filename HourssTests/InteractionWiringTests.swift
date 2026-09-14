import Testing
import Foundation
@testable import Hourss

/// That the interaction layer is actually reached.
///
/// Written because this has gone wrong before: the physiology layer sat complete
/// and tested for a week with no caller, so every test passed while no session in
/// the running app carried a residual. A layer with no call site is indisputably
/// correct and entirely useless, and nothing in a unit suite notices.
@Suite("Interaction wiring")
@MainActor
struct InteractionWiringTests {

    private func store(_ person: SyntheticCohort.Person) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.rebuildInsights()
        return store
    }

    @Test("A planted conjunction reaches the store")
    func realInteractionSurfaces() {
        let found = store(SyntheticCohort.morningDeepWork).interactions
        #expect(!found.isEmpty, "the two-way person produced no interaction through the store")
        let allReportable = found.allSatisfy { $0.isReportable }
        #expect(allReportable)
    }

    @Test("A person with no interaction gets none")
    func noiseSurfacesNothing() {
        let found = store(SyntheticCohort.scatteredNoise).interactions
        #expect(found.isEmpty, Comment(rawValue:
                "noise produced \(found.count) conjunctions: " +
                found.map(\.conjunction.id).joined(separator: ", ")))
    }

    /// The confounded person is the one the whole layer exists to refuse: deep
    /// work rated well everywhere, most of it in the morning, so the conjunction
    /// looks strong and is entirely a main effect.
    @Test("A conjunction that is only a main effect is refused")
    func confoundedIsRefused() {
        let found = store(SyntheticCohort.deepWorkMostlyMorning).interactions
        #expect(found.isEmpty, Comment(rawValue:
                "a confounded conjunction reached the store: " +
                found.map(\.conjunction.id).joined(separator: ", ")))
    }

    @Test("Findings are ordered strongest first")
    func orderedByLift() {
        let lifts = store(SyntheticCohort.morningDeepWork).interactions.map(\.interaction.lift)
        // Hoisted: `sorted(by:)` is rethrows, and the expectation macro cannot
        // see through that to know this call does not throw.
        let descending = lifts.sorted(by: >)
        #expect(lifts == descending, Comment(rawValue: "out of order: \(lifts)"))
    }

    @Test("The rows narration needs are kept alongside the findings")
    func observationsAreRetained() {
        let built = store(SyntheticCohort.morningDeepWork)
        #expect(!built.engineObservations.isEmpty)
        // Narration names factors in the person's own words, which needs the rows.
        for finding in built.interactions {
            let evidence = NarrationEvidence(finding: finding,
                                             observations: built.engineObservations)
            #expect(evidence != nil,
                    "a surfaced finding could not be turned into a sentence")
        }
    }

    @Test("Every surfaced conjunction renders to prose the app would print")
    func everyFindingNarrates() {
        let built = store(SyntheticCohort.morningDeepWork)
        for finding in built.interactions {
            guard let evidence = NarrationEvidence(finding: finding,
                                                   observations: built.engineObservations) else {
                Issue.record(Comment(rawValue: "no evidence for \(finding.conjunction.id)"))
                continue
            }
            let sentence = NarrationTemplate.sentence(for: evidence)
            #expect(!sentence.isEmpty)
            #expect(sentence.contains("Observed across"), "the sample limit is missing")
        }
    }

    @Test("An empty record produces no interactions and does not fail")
    func emptyRecordIsQuiet() {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.rebuildInsights()
        #expect(store.interactions.isEmpty)
        #expect(store.engineObservations.isEmpty)
    }
}
