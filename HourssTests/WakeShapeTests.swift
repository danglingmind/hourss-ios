import Foundation
import Testing
@testable import Hourss

/// That a usual waking time is claimed only when there is one.
///
/// The returned number is the smaller half of this file. What is actually under
/// test is the refusal: somebody whose week is split between early starts and late
/// ones has no usual waking time, their median describes none of their mornings,
/// and anchoring suggestions to it would be worse than anchoring to nothing.
@Suite("Wake shape")
struct WakeShapeTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private let calendar = Calendar.current

    /// A night ending `wakeAt` minutes after midnight, on the day `offset` days
    /// after the anchor.
    ///
    /// Minutes after midnight rather than an hour and a minute, which is the unit
    /// `WakeShape` itself works in and the one that cannot be built wrong. Two
    /// drafts of this helper trapped on `bySettingHour` — once on a negative minute
    /// and once on a minute above 59 — because the arithmetic that makes a readable
    /// spread of wake times does not respect either boundary.
    private func night(_ offset: Int, wakeAt minutes: Int) -> Session {
        let day = calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset,
                                                         to: Self.start)!)
        let end = day.addingTimeInterval(TimeInterval(minutes * 60))
        return Session(activityId: UUID(),
                       startAt: end.addingTimeInterval(-7 * 3600),
                       endAt: end,
                       source: .health,
                       healthKind: .sleep,
                       externalId: "health.sleep.\(offset)")
    }

    /// An ordinary logged session, which is not a night however long it is.
    private func logged(_ offset: Int, hour: Int) -> Session {
        let day = calendar.date(byAdding: .day, value: offset, to: Self.start)!
        let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return Session(activityId: UUID(), startAt: at, endAt: at.addingTimeInterval(3600))
    }

    // MARK: - What it returns

    @Test("A steady sleeper gets their waking time")
    func steadySleeper() throws {
        // Fourteen nights, waking between 06:40 and 07:20.
        let nights = (0..<14).map { night($0, wakeAt: 6 * 60 + 40 + ($0 % 5) * 10) }
        let wake = try #require(WakeShape.usualWake(from: nights))
        #expect(wake >= 6 * 60 + 30 && wake <= 7 * 60 + 30,
                Comment(rawValue: "got \(wake) minutes"))
    }

    @Test("A weekend lie-in does not cost somebody their routine")
    func oneLieInIsStillARoutine() {
        // Ten weekday mornings at 06:30 and four weekend ones at 08:30. The IQR
        // holds this; the full spread would not, which is why it is the IQR.
        var nights = (0..<10).map { night($0, wakeAt: 6 * 60 + 30) }
        nights += (10..<14).map { night($0, wakeAt: 8 * 60 + 30) }
        #expect(WakeShape.usualWake(from: nights) != nil,
                "an ordinary weekend should not read as having no routine")
    }

    // MARK: - What it refuses

    @Test("Too few nights is not a habit")
    func tooFewNights() {
        let nights = (0..<(WakeShape.minimumNights - 1)).map { night($0, wakeAt: 7 * 60) }
        #expect(WakeShape.usualWake(from: nights) == nil)
    }

    @Test("A split week has no usual waking time")
    func splitWeekRefuses() {
        // Alternating 06:00 and 10:00 starts. The median lands near 08:00, which
        // describes none of these mornings — that is the number this refuses to
        // hand back rather than the absence of one.
        let nights = (0..<20).map { night($0, wakeAt: ($0.isMultiple(of: 2) ? 6 : 10) * 60) }
        #expect(WakeShape.usualWake(from: nights) == nil,
                "a four-hour spread is not one habit")
    }

    @Test("Nothing on the record is nil, not a guess")
    func emptyRecord() {
        #expect(WakeShape.usualWake(from: []) == nil)
    }

    @Test("Only nights count, however many sessions there are")
    func loggedSessionsAreNotNights() {
        let sessions = (0..<30).map { logged($0, hour: 7) }
        #expect(WakeShape.usualWake(from: sessions) == nil,
                "a logged 7am session says when somebody worked, not when they woke")
    }

    @Test("A block ending after midday is dropped rather than wrapped")
    func afternoonBlocksAreDropped() {
        // Twelve ordinary mornings and six afternoon blocks. Wrapped into the
        // median those would drag the answer hours later; dropped, they cost
        // nothing. A genuine night shift loses its answer either way, and nil is
        // what this file would hand them regardless.
        var sessions = (0..<12).map { night($0, wakeAt: 7 * 60) }
        sessions += (12..<18).map { night($0, wakeAt: 15 * 60) }

        #expect(WakeShape.wakeMinutes(from: sessions).count == 12)
        let wake = WakeShape.usualWake(from: sessions)
        #expect(wake != nil)
        #expect(wake.map { abs($0 - 7 * 60) <= 30 } == true,
                Comment(rawValue: "afternoon blocks moved the answer: \(String(describing: wake))"))
    }

    // MARK: - The gate

    @Test("An hour before somebody is up is refused")
    func asleepHoursAreRefused() {
        let wake = 7 * 60
        #expect(!WakeShape.isAwake(at: 5, wake: wake))
        #expect(!WakeShape.isAwake(at: 6, wake: wake))
        #expect(WakeShape.isAwake(at: 7, wake: wake))
        #expect(WakeShape.isAwake(at: 9, wake: wake))
    }

    /// Not knowing is not a reason to say nothing.
    ///
    /// The alternative — refusing every hour when no waking time is known — would
    /// silence every offer for everybody whose sleep Health never recorded, which is
    /// a much larger harm than occasionally naming an early hour to somebody the app
    /// has no information about.
    @Test("Without a waking time the gate is open")
    func unknownWakeDoesNotSilenceEverything() {
        #expect(WakeShape.isAwake(at: 5, wake: nil))
        #expect(WakeShape.isAwake(at: 23, wake: nil))
    }

    // MARK: - The gate, where it is actually applied

    /// An early place is dropped from the vitals offer for somebody who sleeps late,
    /// and kept for somebody who does not.
    ///
    /// Asserted through `ExperimentVitals.ranked` rather than on `isAwake` alone,
    /// because the gate being correct and the gate being *wired* are different
    /// claims and only the second one ships. The same two places, the same shape,
    /// one waking time apart.
    @Test("A place before waking never reaches the offer")
    func theGateIsWired() {
        let early = Physiology.DayShape.Place(band: .morning, isWorkday: true,
                                              hour: 6, difference: -9)
        let later = Physiology.DayShape.Place(band: .evening, isWorkday: true,
                                              hour: 21, difference: -8)
        let shape = Physiology.DayShape(places: [early, later])

        let forAnEarlyRiser = ExperimentVitals.ranked(
            shape, direction: .uncalibrated, observations: [], wake: 5 * 60)
        #expect(forAnEarlyRiser.count == 2, "somebody up at five is up at six")

        let forALateRiser = ExperimentVitals.ranked(
            shape, direction: .uncalibrated, observations: [], wake: 8 * 60)
        #expect(forALateRiser.map(\.hour) == [21],
                Comment(rawValue: "6am survived for somebody who wakes at 8: "
                        + "\(forALateRiser.map(\.hour))"))

        let unknown = ExperimentVitals.ranked(
            shape, direction: .uncalibrated, observations: [], wake: nil)
        #expect(unknown.count == 2, "not knowing when somebody wakes may not silence them")
    }

    /// A band carries no hour to judge, so it is never gated.
    ///
    /// Refusing somebody's whole morning because its first hour is early would throw
    /// away the part of it they are up for — and `morning` is 05:00–11:00, which
    /// spans almost everybody's waking.
    @Test("A band-resolution place is kept whatever time somebody wakes")
    func bandsAreNotGated() {
        let band = Physiology.DayShape.Place(band: .morning, isWorkday: true,
                                             hour: nil, difference: -9)
        let kept = ExperimentVitals.ranked(
            Physiology.DayShape(places: [band]),
            direction: .uncalibrated, observations: [], wake: 10 * 60)
        #expect(kept.count == 1)
    }
}
