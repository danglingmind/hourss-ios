import Foundation
import Testing
@testable import Hourss

/// What `ExperimentStore.offers` actually hands back, with every source wired in.
///
/// Each source has its own suite testing it in isolation. This one exists because
/// the precedence rule between them — `PRD-VITALS.md` §10 — is enforced only by the
/// order the list is assembled in, and nothing inside any one source can see that
/// order. A ranking held in one function and asserted nowhere is a ranking that
/// drifts the first time somebody appends a line.
///
/// The ranking is by *what an offer rests on*, strongest first: this person's own
/// ratings, then their own body, then what is expected of people in general, then an
/// absence in their own record, then a Health reading about something else.
@Suite("The offer chain")
@MainActor
struct OfferChainTests {

    private func dayOneStore() -> HourssStore {
        // What the day-one fixture argument produces, built directly: Health read,
        // nothing logged. `DebugFixture.isDayOne` reads process arguments, which a
        // unit test cannot set, so the state is assembled rather than requested.
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy, .balance]
        store.activities = Activity.defaults
        store.applyPhysiology(feed: DebugFixture.seededFeed())
        store.rebuildInsights()
        return store
    }

    private func isVitalsLed(_ proposal: ExperimentDesign.Proposal) -> Bool {
        proposal.premise.contains("heart rate")
    }

    private func isPriorLed(_ proposal: ExperimentDesign.Proposal) -> Bool {
        // The one kind of premise in this app that names people in general, so the
        // ordinary sweep refuses it and the exempt one passes it. Identified by that
        // rather than by wording, which belongs to `ExperimentPriorTests`.
        guard case .population = NarrationGuard.offence(in: proposal.premise) else { return false }
        return NarrationGuard.priorPremiseOffence(in: proposal.premise) == nil
    }

    @Test("A Health read with nothing logged is offered the body before the prior")
    func vitalsOutrankPriors() throws {
        let store = dayOneStore()
        let shape = try #require(store.dayShape)
        #expect(!shape.isEmpty, Comment(rawValue:
            "the seeded feed produced no shape, so nothing vitals-led is reachable"))

        let offers = store.experimentProposals(resamples: 50)
        #expect(!offers.isEmpty)

        let vitals = offers.firstIndex(where: isVitalsLed)
        let prior = offers.firstIndex(where: isPriorLed)
        let vitalsIndex = try #require(vitals, Comment(rawValue:
            "no vitals-led offer with a shape in hand: \(offers.map(\.premise))"))
        if let priorIndex = prior {
            #expect(vitalsIndex < priorIndex, Comment(rawValue:
                "a prior outranked the person's own body: \(offers.map(\.premise))"))
        }
    }

    @Test("Nothing measured, so every offer stands as a starter")
    func dayOneOffersAreAllStarters() {
        for offer in dayOneStore().experimentProposals(resamples: 50) {
            #expect(offer.standing == .starter)
            #expect(offer.evidenceDays == 0)
        }
    }

    /// The rule each source enforces alone and none of them can check together.
    @Test("One offer per focus area, however many sources ran")
    func onePerPriority() {
        let offers = dayOneStore().experimentProposals(resamples: 50)
        let priorities = offers.map(\.priority)
        #expect(Set(priorities).count == priorities.count, Comment(rawValue:
            "two offers landed on one focus area: \(priorities)"))
    }

    @Test("No offer repeats a question another source already took")
    func noRepeatedQuestion() {
        let offers = dayOneStore().experimentProposals(resamples: 50)
        let ids = offers.map(\.hypothesisId)
        #expect(Set(ids).count == ids.count, Comment(rawValue: "a question was offered twice: \(ids)"))
    }

    /// A full record, where the measured path should own everything it reaches.
    @Test("A measured finding is never displaced by an unmeasured offer")
    func measuredComesFirst() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)
        let offers = store.experimentProposals(resamples: 50)
        let first = try #require(offers.first)
        #expect(first.standing != .starter, Comment(rawValue:
            "the fixture's measured findings lost their place: \(offers.map(\.premise))"))

        // And no unmeasured offer sits above a measured one anywhere in the list.
        let lastMeasured = offers.lastIndex { $0.standing != .starter }
        let firstStarter = offers.firstIndex { $0.standing == .starter }
        if let lastMeasured, let firstStarter {
            #expect(lastMeasured < firstStarter, Comment(rawValue:
                "the list interleaves measured and unmeasured offers: \(offers.map(\.standing))"))
        }
    }

    /// The §9 rule that matters most, checked where the sentences meet rather than
    /// where they are written.
    @Test("Only a prior-led premise names people, across the whole chain")
    func onlyThePriorNamesPeople() {
        for store in [dayOneStore(), { let s = HourssStore(repository: InMemoryRecordRepository())
                                       DebugFixture.seed(into: s); return s }()] {
            for offer in store.experimentProposals(resamples: 50) {
                if isPriorLed(offer) { continue }
                // `.population` specifically, not a clean sweep. A measured premise
                // quotes figures out of the evidence record — which is what
                // `allowingFigures` exists for at the call site — so asserting the
                // whole sweep passes here would fail on a legitimate number and say
                // nothing about whether people were named.
                if case .population(let word) = NarrationGuard.offence(in: offer.premise) {
                    Issue.record("a premise that is not prior-led named people: '\(word)' in \(offer.premise)")
                }
            }
        }
    }
}
