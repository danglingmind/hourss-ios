import Foundation
import Testing
@testable import Hourss

/// That the app does not spend a fortnight asking somebody to keep doing what they
/// already do.
///
/// **The case.** Somebody who logs a session every morning, and whose mornings read
/// well, was offered *"log one session in your morning on most days, for two weeks"*.
/// They would clear adherence without changing anything, spend a fortnight on it,
/// and get back the one verdict the engine could already predict.
///
/// **Not a taste judgement.** `ExperimentOutcome` already refuses to read a window
/// carrying fewer than `Experiment.minimumDays` contrasting days. Days somebody
/// would have had anyway are not contrast. This is that floor applied a fortnight
/// earlier, where it costs nothing instead of costing two weeks.
@Suite("The size of the ask")
@MainActor
struct HollowAskTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private let calendar = Calendar.current

    /// Someone who logs at `hour` on `doingDays` of the last `total` days, and
    /// somewhere else on the rest.
    private func observations(hour: Int, doingDays: Int, total: Int = 28,
                              now: Date = Date()) -> [EngineObservation] {
        (0..<total).compactMap { offset in
            let day = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -offset, to: now)!)
            let at = calendar.date(bySettingHour: offset < doingDays ? hour : 15,
                                   minute: 0, second: 0, of: day)!
            return EngineObservation(
                sessionId: UUID(), day: day, startAt: at, durationMinutes: 60,
                activityName: "Deep work", activityCategory: "focus",
                timeBucket: TimeBucket.bucket(forHour: calendar.component(.hour, from: at)),
                durationBucket: .medium, isWorkday: true,
                feeling: 4, performance: nil, dayHealth: [:],
                heartRateResidual: nil, cadence: nil)
        }
    }

    // MARK: - The arithmetic

    /// The bound is the engine's own contrast floor, rearranged — not a new number.
    @Test("The bound comes from the contrast floor and the window length")
    func theBoundIsDerived() {
        let expected = 1 - Double(Experiment.minimumDays) / Double(Experiment.defaultWindowDays)
        #expect(ExperimentDesign.maximumRoutineShare == expected)
        // Six days of contrast out of fourteen leaves eight, so a change already made
        // on more than eight days in fourteen cannot be told apart from the habit.
        #expect(abs(ExperimentDesign.maximumRoutineShare - 8.0 / 14.0) < 0.000_001)
    }

    // MARK: - What it catches

    @Test("Asking a daily morning person for a morning session is hollow")
    func aDailyHabitIsHollow() throws {
        let morning = try #require(ExperimentVitals.timeWindow(.morning))
        let rows = observations(hour: 8, doingDays: 26)

        let share = ExperimentDesign.routineShare(of: morning, in: rows)
        #expect(share > 0.9, Comment(rawValue: "share was \(share)"))
        #expect(ExperimentDesign.isHollow(morning, in: rows))
    }

    @Test("Asking somebody for something they rarely do is a real ask")
    func anOccasionalHabitIsNotHollow() throws {
        let morning = try #require(ExperimentVitals.timeWindow(.morning))
        let rows = observations(hour: 8, doingDays: 4)
        #expect(!ExperimentDesign.isHollow(morning, in: rows))
    }

    /// Exactly at the bound is allowed; past it is not. Stated because a strict or
    /// loose inequality here is the difference between offering a fortnight that can
    /// just about answer and one that just about cannot.
    @Test("The bound itself is allowed")
    func theBoundaryIsInclusive() throws {
        let morning = try #require(ExperimentVitals.timeWindow(.morning))
        // 16 of 28 days is 0.571…, which is the bound to within rounding.
        #expect(!ExperimentDesign.isHollow(morning, in: observations(hour: 8, doingDays: 16)))
        #expect(ExperimentDesign.isHollow(morning, in: observations(hour: 8, doingDays: 20)))
    }

    @Test("An empty record asks for something, not nothing")
    func anEmptyRecordIsNotHollow() throws {
        let morning = try #require(ExperimentVitals.timeWindow(.morning))
        #expect(ExperimentDesign.routineShare(of: morning, in: []) == 0)
        #expect(!ExperimentDesign.isHollow(morning, in: []))
    }

    /// Only lately. Somebody who logged mornings for a year and stopped last month is
    /// being asked for a change, and the window is what lets the rule notice.
    @Test("A habit that has been dropped is no longer a habit")
    func onlyRecentDaysCount() throws {
        let morning = try #require(ExperimentVitals.timeWindow(.morning))
        let now = Date()
        // Mornings every day, but all of them more than two windows ago.
        let old = observations(hour: 8, doingDays: 28, total: 28,
                               now: calendar.date(byAdding: .day, value: -90, to: now)!)
        #expect(ExperimentDesign.routineShare(of: morning, in: old, now: now) == 0)
        #expect(!ExperimentDesign.isHollow(morning, in: old, now: now))
    }

    // MARK: - What the chain does with it

    /// The rule's whole point: a hollow offer does not merely waste its own slot.
    ///
    /// `completing` skips a focus area an earlier source already served, so one
    /// hollow proposal costs that area every other offer the chain could have made.
    /// The interpolator logs mornings daily; before this rule the measured source
    /// served their focus with "log one session in your morning" and the hour-led
    /// offer — "try 07:00, which you have never logged" — was skipped behind it.
    @Test("Dropping a hollow offer lets a real one through")
    func theChainReachesPastAHollowOffer() throws {
        let person = SyntheticCohort.interpolator
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy, .balance]
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.rebuildInsights()

        let proposals = store.experimentProposals(resamples: 200)
        for proposal in proposals {
            guard let hypothesis = store.hypothesis(for: proposal.hypothesisId) else { continue }
            #expect(!ExperimentDesign.isHollow(hypothesis, in: store.engineObservations),
                    Comment(rawValue: "a hollow offer survived: \(proposal.change)"))
        }

        // And something real reached focus in its place.
        let focus = proposals.filter { $0.priority == .focus }
        #expect(!focus.isEmpty, "focus lost its offer entirely rather than gaining a better one")
    }
}
