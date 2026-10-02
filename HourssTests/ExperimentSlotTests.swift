import Foundation
import Testing
@testable import Hourss

/// The slot's precedence, where experiments meet everything that was already there.
@Suite("Experiment slot")
struct ExperimentSlotTests {

    private let settled = UUID()
    private let active = UUID()
    private let proposal = UUID()
    private let recommendation = UUID()
    private let insight = UUID()
    private let session = UUID()

    /// A state with everything set at once, so a precedence test is a statement
    /// about ordering rather than about which fields happened to be filled in.
    private func crowded(tier: Tier = .member, requiresMembership: Bool = false) -> SlotState {
        SlotState(
            tier: tier,
            ratedDayCount: 20,
            unratedSessionId: session,
            recommendationCount: 2,
            leadRecommendationId: recommendation,
            leadInsightId: insight,
            settledExperimentId: settled,
            activeExperimentId: active,
            proposalId: proposal,
            proposalRequiresMembership: requiresMembership
        )
    }

    // MARK: Precedence

    @Test("A finished test outranks everything, including the rating ask")
    func settledWins() {
        #expect(ObservationSlot.content(for: crowded()) == .settledExperiment(id: settled))
    }

    @Test("A running window outranks a proposal, a recommendation and the ask")
    func activeIsNext() {
        var state = crowded()
        state.settledExperimentId = nil
        #expect(ObservationSlot.content(for: state) == .activeExperiment(id: active))
    }

    /// The reason this feature exists, as an assertion.
    @Test("A proposal outranks a recommendation")
    func proposalBeatsRecommendation() {
        var state = crowded()
        state.settledExperimentId = nil
        state.activeExperimentId = nil
        // A recommendation restates what held up; a proposal asks for one change and
        // measures it. When both are available the one with something to do wins.
        #expect(ObservationSlot.content(for: state) == .experimentProposal(id: proposal))
    }

    @Test("With no experiments at all, nothing about the old order has changed")
    func existingOrderIsUntouched() {
        var state = crowded()
        state.settledExperimentId = nil
        state.activeExperimentId = nil
        state.proposalId = nil
        #expect(ObservationSlot.content(for: state) == .recommendation(id: recommendation))
    }

    // MARK: Entitlement

    @Test("A lead reaches a free member, because it is the first useful thing")
    func leadIsFree() {
        var state = crowded(tier: .free, requiresMembership: false)
        state.settledExperimentId = nil
        state.activeExperimentId = nil
        #expect(ObservationSlot.content(for: state) == .experimentProposal(id: proposal))
    }

    @Test("A confirmed proposal does not reach a free member")
    func confirmedIsPaid() {
        var state = crowded(tier: .free, requiresMembership: true)
        state.settledExperimentId = nil
        state.activeExperimentId = nil
        // Falls straight through, and lands where a free member would have landed
        // anyway — the rating ask, which already outranks the upgrade prompt because
        // asking somebody to pay before asking for the rating the engine runs on has
        // the product's own dependency backwards.
        #expect(ObservationSlot.content(for: state) == .unfinishedReflection(sessionId: session))
        // And with nothing to rate, the prompt it was always going to reach.
        state.unratedSessionId = nil
        #expect(ObservationSlot.content(for: state) == .upgradePrompt(count: 2))
        // Either way the proposal is not what they see, and nothing names it.
        #expect(!ObservationSlot.copy(for: ObservationSlot.content(for: state))
                    .allStrings.joined().lowercased().contains("fortnight"))
    }

    @Test("A confirmed proposal reaches a member")
    func confirmedReachesMembers() {
        var state = crowded(tier: .member, requiresMembership: true)
        state.settledExperimentId = nil
        state.activeExperimentId = nil
        #expect(ObservationSlot.content(for: state) == .experimentProposal(id: proposal))
    }

    // MARK: The displaced ask

    @Test("Every card that outranks the rating ask carries it instead")
    func theAskIsNeverLost() {
        // The whole point of the stacking rule: nothing above the ask throws it away.
        var state = crowded()
        #expect(ObservationSlot.displacedReflection(for: state) == session)

        state.settledExperimentId = nil
        #expect(ObservationSlot.displacedReflection(for: state) == session)

        state.activeExperimentId = nil
        #expect(ObservationSlot.displacedReflection(for: state) == session)

        state.proposalId = nil
        #expect(ObservationSlot.displacedReflection(for: state) == session)
    }

    @Test("A state that is already the ask displaces nothing")
    func theAskDoesNotDisplaceItself() {
        var state = SlotState(ratedDayCount: 2, unratedSessionId: session)
        #expect(ObservationSlot.content(for: state) == .unfinishedReflection(sessionId: session))
        #expect(ObservationSlot.displacedReflection(for: state) == nil)

        state.unratedSessionId = nil
        #expect(ObservationSlot.content(for: state) == .evidenceProgress(days: 2))
        #expect(ObservationSlot.displacedReflection(for: state) == nil)
    }

    // MARK: Copy reaches the screen

    @Test("A proposal says which standing it has, and never the wrong one")
    func standingIsStated() {
        func copy(_ standing: ExperimentDesign.Standing) -> SlotCopy {
            let p = ExperimentDesign.Proposal(
                hypothesisId: "h", outcome: .feeling, type: .bestTimeWindow, standing: standing,
                focusLabel: "Morning", baselineLabel: "Rest",
                premise: "Morning has read higher so far, across 4 days.",
                context: nil,
                change: "Put one block in your morning on most days this fortnight.",
                caveat: "Time of day travels with whatever you tend to schedule then.",
                priority: .focus, priorityRank: 0, evidenceDays: 4,
                figure: 4, baselineFigure: 3.5)
            return ObservationSlot.copy(for: .experimentProposal(id: p.id), proposal: p)
        }
        #expect(copy(.lead).eyebrow == "Worth testing")
        #expect(copy(.confirmed).eyebrow == "Test what held up")
        // The change leads, because it is the only part there is anything to do about.
        #expect(copy(.lead).lines.first?.emphasis == .lead)
        #expect(copy(.lead).lines.first?.text.contains("Put one block") == true)
    }

    @Test("A null result is set as loudly as a positive one")
    func nullResultsAreNotQuiet() {
        func copy(_ verdict: Experiment.Verdict) -> SlotCopy {
            var e = Experiment(
                hypothesisId: "h", outcome: .feeling, startedAt: Date(),
                focusLabel: "Morning", baselineLabel: "Rest",
                premise: "p", change: "Put one block in your morning.", caveat: "v")
            e.settlement = Experiment.Settlement(
                verdict: verdict, adherenceDays: 9, baselineDays: 12,
                focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
                intervalLow: 0.1, intervalHigh: 0.7, settledAt: Date())
            return ObservationSlot.copy(for: .settledExperiment(id: e.id), experiment: e)
        }
        // Same structure, same emphasis — an app whose tests always succeed is not
        // running tests, and a quietly-presented null result is the first step there.
        #expect(copy(.heldUp).lines.first?.emphasis == copy(.didNotHoldUp).lines.first?.emphasis)
        #expect(copy(.heldUp).eyebrow == "It held up")
        #expect(copy(.didNotHoldUp).eyebrow == "It did not hold up")
        #expect(copy(.heldUp).caveat != nil)
        #expect(copy(.didNotHoldUp).caveat != nil)
        // Nothing to qualify about a window that could not be read.
        #expect(copy(.cannotTell).caveat == nil)
    }

    @Test("The active card counts what happened and never sets a deadline")
    func activeCardCounts() {
        let e = Experiment(
            hypothesisId: "h", outcome: .feeling, startedAt: Date(),
            focusLabel: "Morning", baselineLabel: "Rest",
            premise: "p", change: "Put one block in your morning.", caveat: "v")
        func copy(adherence: Int, remaining: Int) -> SlotCopy {
            ObservationSlot.copy(
                for: .activeExperiment(id: e.id), experiment: e,
                reading: ExperimentOutcome.Reading(
                    verdict: .cannotTell, adherenceDays: adherence, baselineDays: adherence,
                    focusFigure: 0, baselineFigure: 0, comparison: nil),
                daysRemaining: remaining)
        }
        #expect(copy(adherence: 1, remaining: 5).allStrings.contains("One day of it so far."))
        #expect(copy(adherence: 4, remaining: 5).allStrings.contains("Four days of it so far."))
        #expect(copy(adherence: 4, remaining: 1).allStrings.contains("One more day of this fortnight."))
        #expect(copy(adherence: 4, remaining: 0).allStrings.contains("The fortnight closes today."))
        // No deadline language anywhere, in any of those shapes.
        for (a, r) in [(0, 13), (1, 1), (4, 0)] {
            let text = copy(adherence: a, remaining: r).allStrings.joined(separator: " ").lowercased()
            for banned in ["days left", "days to go", "deadline", "until"] {
                #expect(!text.contains(banned), Comment(rawValue: "'\(banned)' in: \(text)"))
            }
        }
    }
}
