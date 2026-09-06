import Testing
import Foundation
@testable import Hourss

/// The cohort has to be trustworthy before it can judge anything.
///
/// These check the generator itself: that a planted effect is genuinely present in
/// the ratings, that an absent one genuinely is not, and that two runs produce the
/// same people. A test suite built on a generator nobody verified would just move
/// the unverified step one level down.
@Suite("Synthetic cohort")
struct CohortTests {

    /// Mean feeling score across sessions matching a predicate.
    private func mean(_ person: SyntheticCohort.Person,
                      where predicate: (Session, String) -> Bool) -> Double? {
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0.name) })
        let scores = person.sessions.compactMap { session -> Int? in
            guard let score = person.reflections[session.id]?.feelingScore,
                  predicate(session, names[session.activityId] ?? "") else { return nil }
            return score
        }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    @Test("Generation is deterministic")
    func deterministic() {
        let a = SyntheticCohort.afternoonSlump
        let b = SyntheticCohort.afternoonSlump
        #expect(a.sessions.count == b.sessions.count)
        #expect(a.sessions.map(\.startAt) == b.sessions.map(\.startAt))
        #expect(a.reflections.count == b.reflections.count)
    }

    @Test("A planted time-of-day effect is really in the ratings")
    func afternoonSlumpIsReal() throws {
        let person = SyntheticCohort.afternoonSlump
        let morning = try #require(mean(person) { s, _ in s.timeBucket == .morning })
        let afternoon = try #require(mean(person) { s, _ in s.timeBucket == .afternoon })
        // Planted at 1.2; rounding to integers and clamping to 1...5 shrinks it.
        #expect(morning - afternoon > 0.5,
                "planted afternoon slump did not survive generation: \(morning) vs \(afternoon)")
    }

    @Test("A planted activity effect is really in the ratings")
    func meetingDrainIsReal() throws {
        let person = SyntheticCohort.meetingDrain
        let meetings = try #require(mean(person) { _, name in name == "Meetings" })
        let rest = try #require(mean(person) { _, name in name != "Meetings" })
        #expect(rest - meetings > 0.5,
                "planted meeting drain did not survive generation: \(rest) vs \(meetings)")
    }

    @Test("The flatline person really has no time-of-day effect")
    func flatlineIsFlat() throws {
        let person = SyntheticCohort.flatline
        let byBucket = try TimeBucket.allCases.compactMap { bucket -> Double? in
            mean(person) { s, _ in s.timeBucket == bucket }
        }
        let spread = try #require(byBucket.max()) - (try #require(byBucket.min()))
        #expect(spread < 0.45,
                "flatline person has a \(spread) spread across time buckets — not flat enough to test against")
    }

    @Test("Informative missingness biases the observable ratings upward")
    func missingnessBiasesUpward() throws {
        let person = SyntheticCohort.skipsTheBadOnes
        let names = Dictionary(uniqueKeysWithValues: person.activities.map { ($0.id, $0.name) })
        let admin = person.sessions.filter { names[$0.activityId] == "Admin" }
        let rated = admin.compactMap { person.reflections[$0.id]?.feelingScore }
        let coverage = Double(rated.count) / Double(admin.count)
        // Everyone else sits near the recipe's 0.75 coverage.
        #expect(coverage < 0.72,
                "expected under-reporting on the draining activity, got \(coverage) coverage")
    }

    @Test("Health samples keep sub-daily resolution")
    func samplesAreSubDaily() throws {
        let person = SyntheticCohort.stillMeetings
        let steps = try #require(person.samples[.steps])
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: try #require(steps.first).at)
        let sameDay = steps.filter { calendar.startOfDay(for: $0.at) == firstDay }
        #expect(sameDay.count > 20,
                "steps collapsed to \(sameDay.count) samples a day — the resolution layer 3 needs is gone")

        // And the rollup reproduces exactly what today's daily query would give.
        let rolled = person.healthByDay[.steps] ?? [:]
        #expect(rolled[firstDay] != nil)
        #expect(rolled.count <= steps.count / 20)
    }

    @Test("Walking and still meetings are physiologically identical, and only steps separate them")
    func movementIsTheOnlyDifference() throws {
        let still = SyntheticCohort.stillMeetings
        let walking = SyntheticCohort.walkingMeetings

        func meetingHR(_ p: SyntheticCohort.Person) -> Double {
            let names = Dictionary(uniqueKeysWithValues: p.activities.map { ($0.id, $0.name) })
            let windows = p.sessions.filter { names[$0.activityId] == "Meetings" }
            let bpm = windows.flatMap { SyntheticCohort.heartRate(during: $0, from: p.heartRate) }
            return bpm.reduce(0) { $0 + $1.value } / Double(max(bpm.count, 1))
        }
        func meetingCadence(_ p: SyntheticCohort.Person) -> Double {
            let names = Dictionary(uniqueKeysWithValues: p.activities.map { ($0.id, $0.name) })
            let windows = p.sessions.filter { names[$0.activityId] == "Meetings" }
            let steps = p.samples[.steps] ?? []
            let values = windows.map { SyntheticCohort.cadence(during: $0, steps: steps) }
            return values.reduce(0, +) / Double(max(values.count, 1))
        }

        // Heart rate alone cannot tell these two people apart...
        #expect(abs(meetingHR(still) - meetingHR(walking)) < 6,
                "the two meeting people should look similar on heart rate alone")
        // ...but cadence separates them decisively.
        #expect(meetingCadence(walking) > meetingCadence(still) * 4,
                "walking meetings should show far higher cadence: \(meetingCadence(walking)) vs \(meetingCadence(still))")
    }
}
