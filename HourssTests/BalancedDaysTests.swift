import Foundation
import Testing
@testable import Hourss

/// That the warming-up screen can name the gate that actually stops a pattern.
@Suite("Balanced days")
@MainActor
struct BalancedDaysTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private static let calendar = Calendar.current

    private func store(_ entries: [(dayOffset: Int, hour: Int)]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        let activity = store.activities.first!
        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        for entry in entries {
            let day = Self.calendar.date(byAdding: .day, value: entry.dayOffset, to: Self.start)!
            let startAt = Self.calendar.date(bySettingHour: entry.hour, minute: 0, second: 0, of: day)!
            let session = Session(activityId: activity.id, startAt: startAt,
                                  endAt: startAt.addingTimeInterval(3600))
            sessions.append(session)
            reflections[session.id] = Reflection(sessionId: session.id, feelingScore: 4,
                                                 performanceScore: nil, note: nil,
                                                 submittedAt: startAt)
        }
        store.sessions = sessions
        store.reflections = reflections
        return store
    }

    /// The case this measure exists for.
    @Test("Logging only mornings is worth nothing, however many days it runs")
    func oneSidedIsZero() {
        // A month of rated mornings fills every other bar on the warming-up screen
        // and buys no comparison at all: one side has thirty days and the other has
        // none. The old screen said the rated-day bar was full and left somebody to
        // work out why that bought nothing.
        let store = store((0..<30).map { ($0, 9) })
        #expect(store.ratedDayCount == 30)
        #expect(store.bestBalancedDays == 0)
    }

    @Test("Both sides of a split count the weaker one")
    func theWeakerSideDecides() {
        // Six mornings and two afternoons, on distinct days. The comparison is
        // limited by the two.
        var entries = (0..<6).map { (dayOffset: $0, hour: 9) }
        entries += (6..<8).map { (dayOffset: $0, hour: 15) }
        #expect(store(entries).bestBalancedDays == 2)
    }

    @Test("Six on each side reaches the floor")
    func theFloor() {
        var entries = (0..<6).map { (dayOffset: $0, hour: 9) }
        entries += (6..<12).map { (dayOffset: $0, hour: 15) }
        let store = store(entries)
        #expect(store.bestBalancedDays >= EvidenceFloor.perSide)
        // And twelve rated days was never the thing that mattered — these two
        // records have the same day count and different answers.
        #expect(store.ratedDayCount == 12)
        #expect(self.store((0..<12).map { ($0, 9) }).ratedDayCount == 12)
        #expect(self.store((0..<12).map { ($0, 9) }).bestBalancedDays == 0)
    }

    @Test("Days are counted, not sessions")
    func daysNotSessions() {
        // Six sessions on one Tuesday are one day of evidence about Tuesdays. Both
        // buckets on the same six days is six a side, not twelve.
        var entries = (0..<6).map { (dayOffset: $0, hour: 9) }
        entries += (0..<6).map { (dayOffset: $0, hour: 15) }
        #expect(store(entries).bestBalancedDays == 6)
    }

    @Test("Unrated sessions do not count, because no comparison can use them")
    func unratedDoNotCount() {
        let store = store((0..<6).map { ($0, 9) } + (6..<12).map { ($0, 15) })
        #expect(store.bestBalancedDays == 6)
        // Strip every rating and the measure goes to zero, as every comparison does.
        store.reflections = [:]
        #expect(store.bestBalancedDays == 0)
    }

    @Test("An empty record is zero rather than a crash")
    func empty() {
        #expect(store([]).bestBalancedDays == 0)
    }
}
