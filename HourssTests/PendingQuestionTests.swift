import Foundation
import Testing
@testable import Hourss

/// That the engine can say what it is waiting for, and that saying so cannot leak
/// an untested question into anything that makes a claim.
@Suite("Pending questions")
struct PendingQuestionTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private static let calendar = Calendar.current

    /// One rated session, `dayOffset` days in, at `hour`.
    private func row(dayOffset: Int, hour: Int, feeling: Double? = 4,
                     activity: String = "Deep work") -> EngineObservation {
        let day = Self.calendar.date(byAdding: .day, value: dayOffset, to: Self.start)!
        let startAt = Self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return EngineObservation(
            sessionId: UUID(), day: Self.calendar.startOfDay(for: startAt), startAt: startAt,
            durationMinutes: 60, activityName: activity, activityCategory: "work",
            timeBucket: hour < 11 ? .morning : .afternoon,
            durationBucket: .medium, isWorkday: true,
            feeling: feeling, performance: nil, dayHealth: [:],
            heartRateResidual: nil, cadence: nil
        )
    }

    private func input(_ rows: [EngineObservation]) -> EngineInput {
        EngineInput(observations: rows, priorities: [.focus, .energy])
    }

    // MARK: What it is short of

    @Test("A thin record says how far off each question is")
    func shortfallIsMeasured() throws {
        // Four mornings and nine afternoons: the morning side is two short of six.
        var rows = (0..<4).map { row(dayOffset: $0, hour: 9) }
        rows += (4..<13).map { row(dayOffset: $0, hour: 15) }

        let pending = Engine.pending(for: input(rows))
        let morning = try #require(pending.first { $0.hypothesis.id.hasPrefix("time.morning") })
        #expect(morning.focusDays == 4)
        #expect(morning.baselineDays == 9)
        #expect(morning.gate == 6)
        #expect(morning.shortfall == 2)
        #expect(!morning.isUntouched)
    }

    /// The case the copy has to tell apart from being merely short.
    @Test("A side that has never happened is untouched, not short")
    func untouchedIsADifferentGap() throws {
        // Only mornings, for a month. The evening question has one empty side.
        let rows = (0..<30).map { row(dayOffset: $0, hour: 9) }
        let pending = Engine.pending(for: input(rows))

        let evening = try #require(pending.first { $0.hypothesis.id.hasPrefix("time.evening") })
        #expect(evening.focusDays == 0)
        #expect(evening.isUntouched)
        // "Two more afternoon days" is a task somebody finishes this week. "You have
        // not logged an evening yet" is not the same sentence, and a screen that read
        // the second as the first would be telling somebody to do something they are
        // already doing.
        #expect(evening.shortfall == evening.gate)
    }

    @Test("Days are counted, not sessions")
    func daysNotSessions() throws {
        // Six mornings on one day. One day of evidence about mornings, not six.
        var rows = (0..<6).map { _ in row(dayOffset: 0, hour: 9) }
        rows += (1..<9).map { row(dayOffset: $0, hour: 15) }
        let morning = try #require(Engine.pending(for: input(rows))
            .first { $0.hypothesis.id.hasPrefix("time.morning") })
        #expect(morning.focusDays == 1)
    }

    @Test("Unrated sessions do not count, because no comparison can use them")
    func unratedDoNotCount() throws {
        var rows = (0..<6).map { row(dayOffset: $0, hour: 9, feeling: nil) }
        rows += (6..<12).map { row(dayOffset: $0, hour: 15) }
        let morning = try #require(Engine.pending(for: input(rows))
            .first { $0.hypothesis.id.hasPrefix("time.morning") })
        #expect(morning.focusDays == 0)
    }

    // MARK: It cannot leak

    /// The property that made a separate function the right shape.
    @Test("Nothing pending is ever also a finding")
    func theTwoListsNeverOverlap() {
        var rows = (0..<4).map { row(dayOffset: $0, hour: 9) }
        rows += (4..<13).map { row(dayOffset: $0, hour: 15) }
        rows += (0..<8).map { row(dayOffset: $0, hour: 16, activity: "Admin") }
        let engineInput = input(rows)

        let found = Set(Engine.findings(for: engineInput, resamples: 200).map(\.hypothesis.id))
        let waiting = Set(Engine.pending(for: engineInput).map(\.hypothesis.id))

        // A question is asked or it is waiting. Never both, and the types cannot
        // express both — which is why this is a separate function rather than a flag
        // on `Finding` that four other paths would each have to remember to check.
        #expect(found.isDisjoint(with: waiting))
        #expect(!found.isEmpty)
        #expect(!waiting.isEmpty)
    }

    @Test("Every finding cleared the gate on both sides")
    func findingsAreUnchanged() {
        var rows = (0..<4).map { row(dayOffset: $0, hour: 9) }
        rows += (4..<13).map { row(dayOffset: $0, hour: 15) }
        for finding in Engine.findings(for: input(rows), resamples: 200) {
            #expect(finding.comparison.focusDays >= finding.hypothesis.minimumDays)
            #expect(finding.comparison.baselineDays >= finding.hypothesis.minimumDays)
        }
    }

    /// The day-one case, and it works without anything being added for it.
    @Test("An empty record already has a map, with every question untouched")
    func emptyRecordStillHasQuestions() {
        // Nine hypotheses are minted whatever the record holds — four time buckets,
        // four durations, workdays — because none of them depends on what somebody
        // has logged to *exist*. Only the activity and health families are built from
        // the data.
        //
        // So somebody who has logged nothing can still see what the app is watching
        // for, which is the half of this feature worth more than the unlocking: the
        // map is information before any of it opens.
        let pending = Engine.pending(for: input([]))
        #expect(pending.count == 9)
        for question in pending {
            #expect(question.focusDays == 0)
            #expect(question.baselineDays == 0)
            #expect(question.isUntouched)
            #expect(question.shortfall == question.gate)
        }
        // And none of them is a finding, so nothing can be claimed from an empty
        // record by this route.
        #expect(Engine.findings(for: input([]), resamples: 200).isEmpty)
    }
}
