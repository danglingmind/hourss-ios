import Testing
import Foundation
@testable import Hourss

/// The entitlement, and the evidence figure the observation slot counts in.
///
/// Two things that look unrelated and are not: the slot's content is chosen by
/// entitlement crossed with how much history exists, so a wrong answer from
/// either one puts the wrong line on the highest-traffic screen in the app.
@Suite("Membership and the evidence count")
@MainActor
struct MembershipTests {

    // MARK: - Fixtures

    /// A defaults suite per test. `UserDefaults.standard` is shared with every
    /// other suite in the bundle and with whatever the simulator ran last, so a
    /// persistence test written against it would pass or fail on test ordering.
    private func scratchDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "hourss.tests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(sessions: [Session], rated: [UUID: Int]) -> HourssStore {
        let store = HourssStore()
        store.sessions = sessions
        for (id, feeling) in rated {
            store.saveReflection(sessionId: id, feeling: feeling, performance: nil, note: nil)
        }
        return store
    }

    /// An hour-long session starting at `hour` on the day `daysAgo` back.
    private func session(daysAgo: Int, hour: Int, minutes: Int = 60) -> Session {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        let start = calendar.date(byAdding: .hour, value: hour, to: day)!
        return Session(activityId: Activity.defaults[0].id,
                       startAt: start,
                       endAt: start.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    // MARK: - The entitlement

    @Test("The tier survives the object that set it")
    func tierPersistsAcrossInstances() {
        let defaults = scratchDefaults()

        let first = Membership(defaults: defaults)
        #expect(first.tier == .free, "nobody starts entitled")
        first.setTier(.member)

        // A second instance stands in for the next launch: the entitlement has to
        // come back off disk, not out of the instance that wrote it.
        let second = Membership(defaults: defaults)
        #expect(second.tier == .member)
        #expect(second.isEntitled)

        second.setTier(.free)
        #expect(Membership(defaults: defaults).tier == .free, "revocation persists too")
    }

    @Test("A free member is not entitled and a member is")
    func entitlementFollowsTier() {
        let membership = Membership(defaults: scratchDefaults())

        membership.setTier(.free)
        #expect(membership.isEntitled == false)

        membership.setTier(.member)
        #expect(membership.isEntitled)

        // The same answer read off the tier itself, since the slot's precedence
        // table is written against `Tier` rather than against the object.
        #expect(Tier.free.isEntitled == false)
        #expect(Tier.member.isEntitled)
    }

    // MARK: - The evidence count

    @Test("Six sessions on one Tuesday are one day of evidence")
    func countsDaysRatherThanSessions() {
        let sameDay = (0..<6).map { session(daysAgo: 3, hour: 8 + $0) }
        let store = makeStore(sessions: sameDay,
                          rated: Dictionary(uniqueKeysWithValues: sameDay.map { ($0.id, 4) }))

        #expect(store.ratedDayCount == 1, "six ratings, one calendar day")
        #expect(store.eligibleSessionCount == 6, "the session heuristic still counts six")
    }

    @Test("Each distinct day counts once, however many sessions it carries")
    func countsEachDistinctDay() {
        // Three days, carrying three, one and two sessions.
        let sessions = [
            session(daysAgo: 5, hour: 9), session(daysAgo: 5, hour: 11), session(daysAgo: 5, hour: 15),
            session(daysAgo: 4, hour: 10),
            session(daysAgo: 2, hour: 9), session(daysAgo: 2, hour: 14),
        ]
        let store = makeStore(sessions: sessions,
                          rated: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, 3) }))

        #expect(store.ratedDayCount == 3)
        #expect(store.meetsEvidenceFloor == false)
    }

    @Test("An unrated session contributes nothing")
    func unratedSessionsDoNotCount() {
        let rated = session(daysAgo: 6, hour: 9)
        let unratedSameDay = session(daysAgo: 6, hour: 14)
        let unratedOwnDay = session(daysAgo: 1, hour: 10)
        // A reflection with a note but no feeling: answered, and still unrated.
        let noteOnly = session(daysAgo: 0, hour: 11)

        let store = makeStore(sessions: [rated, unratedSameDay, unratedOwnDay, noteOnly],
                          rated: [rated.id: 5])
        store.saveReflection(sessionId: noteOnly.id, feeling: nil, performance: 4, note: "fine")

        #expect(store.ratedDayCount == 1, "only the day with a feeling score on it")

        // And the unrated day arrives the moment it is rated, which is what makes
        // the reflection ask worth putting above the upgrade prompt.
        store.saveReflection(sessionId: unratedOwnDay.id, feeling: 2, performance: nil, note: nil)
        #expect(store.ratedDayCount == 2)
    }

    @Test("A running session is not a day of evidence")
    func runningAndTooShortSessionsDoNotCount() {
        let running = Session(activityId: Activity.defaults[0].id, startAt: Date())
        let tooShort = session(daysAgo: 7, hour: 9, minutes: 2)

        let store = makeStore(sessions: [running, tooShort], rated: [:])
        // Rate them anyway: neither is a row the engine will ever see, so a
        // rating cannot promote them into evidence.
        store.saveReflection(sessionId: running.id, feeling: 4, performance: nil, note: nil)
        store.saveReflection(sessionId: tooShort.id, feeling: 4, performance: nil, note: nil)

        #expect(store.ratedDayCount == 0)
    }

    @Test("The floor is twelve days and is read as a count of days")
    func floorIsTwelveDistinctDays() {
        // Twelve days, two sessions each. Twenty-four sessions clears the session
        // heuristic twice over; only the day count decides here.
        var sessions: [Session] = []
        for day in 0..<12 {
            sessions.append(session(daysAgo: day, hour: 9))
            sessions.append(session(daysAgo: day, hour: 16))
        }
        let store = makeStore(sessions: sessions,
                          rated: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, 4) }))

        #expect(store.ratedDayCount == EvidenceFloor.days)
        #expect(store.meetsEvidenceFloor)

        // One day short is below the floor, whatever the session count says.
        let short = makeStore(sessions: Array(sessions.dropLast(2)),
                          rated: Dictionary(uniqueKeysWithValues: sessions.dropLast(2).map { ($0.id, 4) }))
        #expect(short.ratedDayCount == 11)
        #expect(short.meetsEvidenceFloor == false)
    }

    // MARK: - Against the cohort

    @Test("The count equals the distinct rated days the engine sees")
    func matchesWhatTheEngineSees() {
        for person in SyntheticCohort.everyone {
            let store = HourssStore()
            store.activities = person.activities
            store.sessions = person.sessions
            store.reflections = person.reflections

            // The engine's own view: one row per eligible session, days already
            // reduced to `startOfDay`, and only rows carrying a feeling can reach
            // a feeling comparison.
            let rows = ObservationBuilder.rows(
                sessions: person.sessions,
                reflections: person.reflections,
                activities: person.activities,
                healthByDay: person.healthByDay
            )
            let engineDays = Set(rows.filter { $0.feeling != nil }.map(\.day)).count

            #expect(store.ratedDayCount == engineDays, Comment(rawValue:
                    "\(person.name): store \(store.ratedDayCount), engine \(engineDays)"))
            // Every generated person rates most of what they log, so a zero here
            // would mean the fixture fell apart rather than that the two agreed.
            #expect(engineDays > 0, Comment(rawValue: "\(person.name) produced no rated days"))
        }
    }

    @Test("A long history carries more days of evidence than a short one")
    func cohortStraddlesTheFloor() {
        // Each cohort person is a computed property that regenerates on access,
        // so sessions and reflections must come off one binding. Read twice, they
        // are two different people and none of the reflection keys match.
        let slump = SyntheticCohort.afternoonSlump
        let full = HourssStore()
        full.sessions = slump.sessions
        full.reflections = slump.reflections

        #expect(full.meetsEvidenceFloor, Comment(rawValue:
                "afternoon slump has \(full.ratedDayCount) rated days"))

        // Short history carries a real effect over eighteen days, so it clears the
        // floor while the engine still, correctly, says nothing about it. The
        // floor is a necessary condition and was never a sufficient one, and this
        // is the person who makes the difference concrete rather than academic.
        let brief = SyntheticCohort.shortHistory
        let short = HourssStore()
        short.sessions = brief.sessions
        short.reflections = brief.reflections

        #expect(short.ratedDayCount < full.ratedDayCount, Comment(rawValue:
                "short \(short.ratedDayCount) vs full \(full.ratedDayCount)"))
        #expect(short.meetsEvidenceFloor, Comment(rawValue:
                "eighteen days of logging is above the floor, at \(short.ratedDayCount)"))
    }
}
