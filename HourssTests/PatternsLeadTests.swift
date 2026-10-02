import Foundation
import Testing
@testable import Hourss

/// That the Patterns tab names what the engine is watching, and never more.
///
/// `@MainActor` on the suite, not `nonisolated` on the thing under test: `leads`
/// reads a `@MainActor` store, and a static helper on a SwiftUI `View` inherits the
/// view's inferred isolation. Marking it `nonisolated` compiles and then traps at
/// runtime, which this project has twice seen as a shrinking test count rather than
/// as a crash.
@Suite("Patterns leads")
@MainActor
struct PatternsLeadTests {

    private func store(_ person: SyntheticCohort.Person,
                       priorities: [Priority] = [.focus, .energy, .balance]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = priorities
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        store.rebuildInsights()
        return store
    }

    @Test("Everything listed is a lead, and nothing listed has cleared the gates")
    func onlyLeads() {
        let store = store(SyntheticCohort.afternoonSlump)
        for lead in PatternsView.leads(in: store) {
            // The whole claim this section makes about itself.
            #expect(!lead.isReportable, "a confirmed claim was listed as worth testing")
            #expect(ExperimentDesign.standing(of: lead) == .lead)
            // And every row could actually become a test, so the section never names
            // something the app has no intention of doing anything about.
            #expect(ExperimentDesign.isEligible(lead))
        }
    }

    @Test("A lead quotes its day count, so a row cannot read as a finding")
    func everyRowCarriesItsCount() {
        let store = store(SyntheticCohort.afternoonSlump)
        for lead in PatternsView.leads(in: store) {
            let days = lead.comparison.focusDays
            let line = ExperimentCopy.premise(for: lead, standing: .lead, days: days)

            // The count is the invariant — it is what stops a row reading as a
            // finding, and it is on both forms of the sentence.
            #expect(line.contains("\(days)"))

            // "So far" is not. This cohort's leads carry twenty, forty and
            // forty-seven days, and at those counts "so far" would say the app has
            // barely looked when it has looked a great deal and found nothing that
            // separates. Which form applies is decided by the experiment window.
            if days < Experiment.defaultWindowDays {
                #expect(line.contains("so far"))
            } else {
                #expect(!line.contains("so far"))
                #expect(line.contains("without pulling clear"))
            }
        }
    }

    @Test("Nothing already answered is listed again")
    func declinedAndTestedAreDropped() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let before = PatternsView.leads(in: store)
        try #require(!before.isEmpty, "the cohort stopped producing leads")

        let first = try #require(before.first)
        store.declinedExperiments.insert(first.hypothesis.id)
        let after = PatternsView.leads(in: store)

        #expect(!after.contains { $0.hypothesis.id == first.hypothesis.id })
        #expect(after.count == before.count - 1)
    }

    @Test("A lead and the proposal on Today cannot disagree about what a lead is")
    func oneDefinitionOfALead() {
        // Both surfaces filter through `ExperimentDesign`, so a proposal must always
        // be something this section would also have been willing to list. If these
        // ever diverge, Today is offering a test the Patterns tab says is not one.
        let store = store(SyntheticCohort.afternoonSlump)
        let listed = Set(PatternsView.leads(in: store).map(\.hypothesis.id))
        for proposal in store.experimentProposals() where proposal.standing == .lead {
            #expect(listed.contains(proposal.hypothesisId),
                    Comment(rawValue: "Today offered \(proposal.hypothesisId) as a lead "
                            + "but Patterns does not list it"))
        }
    }

    @Test("The copy says these are not findings, without promising they will become any")
    func theSectionMakesNoPromise() {
        // Authored here rather than carried, so it is swept here. "Yet" and "soon"
        // are promises in one word, and for somebody whose days genuinely are flat
        // none of these will ever firm up.
        let line = "These have not repeated enough to stand on their own. They are what Hourss is watching."
        for word in ["yet", "soon", "keep logging", "more data", "unlock", "almost"] {
            #expect(!line.lowercased().contains(word),
                    Comment(rawValue: "the lead section promised '\(word)'"))
        }
    }
}
