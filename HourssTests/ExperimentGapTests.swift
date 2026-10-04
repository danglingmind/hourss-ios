import Foundation
import Testing
@testable import Hourss

/// That a gap is offered only where the absence is a choice, never where it is a life.
///
/// The first version of this offered a test for any empty side, time of day included,
/// and one example killed it: somebody whose work ends at three and who then sleeps
/// has no evening sessions because they have no evenings. Reasoning from absence
/// points at exactly the hours a person does not have.
///
/// What survives is activities, where the absence really is a choice between things
/// somebody already does, inside hours they already have.
@Suite("Experiment gaps")
@MainActor
struct ExperimentGapTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private static let calendar = Calendar.current

    /// `entries` is (day, hour, activity index into `Activity.defaults`).
    private func store(_ entries: [(day: Int, hour: Int, activity: Int)]) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy]
        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        for entry in entries {
            let date = Self.calendar.date(byAdding: .day, value: entry.day, to: Self.start)!
            let startAt = Self.calendar.date(bySettingHour: entry.hour, minute: 0, second: 0, of: date)!
            let session = Session(activityId: store.activities[entry.activity].id,
                                  startAt: startAt, endAt: startAt.addingTimeInterval(3600))
            sessions.append(session)
            reflections[session.id] = Reflection(sessionId: session.id, feelingScore: 4,
                                                 performanceScore: nil, note: nil, submittedAt: startAt)
        }
        store.sessions = sessions
        store.reflections = reflections
        store.rebuildInsights()
        return store
    }

    private func gaps(_ store: HourssStore) -> [ExperimentDesign.Proposal] {
        ExperimentGaps.gaps(
            for: store.profile.priorities,
            pending: Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                     priorities: store.profile.priorities))
        )
    }

    /// The objection that narrowed this, as a test.
    @Test("No gap ever names a time of day")
    func timeIsNeverAGap() {
        // Somebody whose day ends at three: mornings and early afternoons only, for a
        // month. Every evening and midday question has an empty side, and not one of
        // them is a thing to offer — the empty evening is their life.
        var entries: [(Int, Int, Int)] = []
        for day in 0..<30 { entries.append((day, 9, 0)); entries.append((day, 13, 0)) }
        let store = store(entries)

        for gap in gaps(store) {
            #expect(gap.hypothesisId.hasPrefix("activity."),
                    Comment(rawValue: "a gap named something other than an activity: \(gap.hypothesisId)"))
        }
        // And nothing anywhere asks them to be awake in the evening.
        for gap in gaps(store) {
            #expect(!gap.change.lowercased().contains("evening"))
        }
    }

    @Test("Duration is excluded with time, for the same reason")
    func durationIsNotAGap() {
        // Only short sessions, for a month. A record with no long ones may belong to
        // somebody whose day cannot hold one.
        let entries = (0..<30).map { (day: $0, hour: 9, activity: 0) }
        for gap in gaps(store(entries)) {
            #expect(!gap.hypothesisId.hasPrefix("duration."))
        }
    }

    /// What a gap is actually for.
    @Test("An activity done too rarely to compare is offered")
    func aRareActivityIsAGap() throws {
        // Deep work every day, Creative on two. Creative exists in the record, so the
        // question exists — and has too little on one side to be asked.
        var entries: [(Int, Int, Int)] = []
        for day in 0..<20 { entries.append((day, 9, 0)) }
        entries.append((3, 14, 4))
        entries.append((11, 14, 4))
        let store = store(entries)

        let offers = gaps(store)
        let creative = try #require(offers.first { $0.hypothesisId.contains("creative") })
        #expect(creative.standing == .starter)
        #expect(creative.evidenceDays == 0)
        #expect(creative.change.contains("Creative"))
    }

    @Test("An activity already done enough is not a gap")
    func aFullSideIsNotAGap() {
        // Deep work on twenty days: its own side is full, so there is nothing to fill.
        let entries = (0..<20).map { (day: $0, hour: 9, activity: 0) }
        for gap in gaps(store(entries)) {
            #expect(!gap.hypothesisId.contains("deep-work"))
        }
    }

    @Test("A gap names the absence and promises no outcome")
    func thePremiseIsHonest() throws {
        var entries: [(Int, Int, Int)] = []
        for day in 0..<20 { entries.append((day, 9, 0)) }
        entries.append((3, 14, 4))
        let store = store(entries)
        let gap = try #require(gaps(store).first)

        #expect(gap.premise.contains("comparison possible"))
        let text = (gap.premise + " " + (gap.context ?? "")).lowercased()
        for promise in ["better", "improve", "find out whether", "discover", "unlock",
                        "will show", "boost", "should"] {
            #expect(!text.contains(promise),
                    Comment(rawValue: "a gap promised an outcome: '\(promise)' in \(text)"))
        }
    }

    @Test("A gap is never offered for a question already refused")
    func declinedIsSkipped() throws {
        var entries: [(Int, Int, Int)] = []
        for day in 0..<20 { entries.append((day, 9, 0)) }
        entries.append((3, 14, 4))
        let store = store(entries)
        let first = try #require(gaps(store).first)

        let after = ExperimentGaps.gaps(
            for: store.profile.priorities,
            pending: Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                     priorities: store.profile.priorities)),
            excluding: [first.hypothesisId]
        )
        #expect(!after.contains { $0.hypothesisId == first.hypothesisId })
    }
}
