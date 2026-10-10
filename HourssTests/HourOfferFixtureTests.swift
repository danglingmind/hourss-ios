import Foundation
import Testing
@testable import Hourss

/// That the state `PRD-HOURS.md` exists to produce can actually be looked at.
///
/// **A feature nobody can reach is a feature nobody reviews.** The whole of this
/// work ends in one card, and until now that card had only ever appeared in a unit
/// test against a generated person. `DebugFixture.hourOfferArgument` puts it on a
/// simulator and on a phone — the same argument-per-state pattern
/// `dayOneArgument` and `randomisedArgument` already use, and for the reason the
/// health-seeding work established: a card nobody can get to is a card nobody reads.
///
/// The fixture reads `ProcessInfo`, which a unit test cannot set, so this builds the
/// same record shape directly and asserts the offer comes out of it. If the two ever
/// drift, the argument stops producing what this says it produces — which is why the
/// shape is written here in the same terms as the fixture's own plan.
@Suite("Hour-offer fixture")
@MainActor
struct HourOfferFixtureTests {

    /// Every workday at eight and at ten, never at nine, with an afternoon to read
    /// against. The same plan `DebugFixture` lays down under its argument.
    private func store() -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = [.focus, .energy, .balance]
        store.activities = Activity.defaults

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let deepWork = Activity.defaults.first { $0.name == "Deep work" }!
        let meetings = Activity.defaults.first { $0.name == "Meetings" }!

        var sessions: [Session] = []
        var reflections: [UUID: Reflection] = [:]
        for offset in 0..<42 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let weekday = calendar.component(.weekday, from: day)
            guard weekday != 1, weekday != 7 else { continue }
            for (activity, hour, score) in [(deepWork, 8, 5), (deepWork, 10, 4), (meetings, 14, 2)] {
                let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
                let session = Session(activityId: activity.id, startAt: at,
                                      endAt: at.addingTimeInterval(3600))
                sessions.append(session)
                reflections[session.id] = Reflection(
                    sessionId: session.id, feelingScore: score, performanceScore: score,
                    note: nil, submittedAt: at)
            }
        }
        store.sessions = sessions
        store.reflections = reflections
        store.rebuildInsights()
        return store
    }

    @Test("The record reaches an offer for the hour nobody logged")
    func itReachesTheOffer() throws {
        let proposals = store().experimentProposals(resamples: 200)
        let offer = try #require(
            proposals.first { HourHypothesis.hour(fromId: $0.hypothesisId) != nil },
            Comment(rawValue: "no hour-led offer: \(proposals.map(\.hypothesisId))"))

        #expect(HourHypothesis.hour(fromId: offer.hypothesisId) == 9,
                "09:00 is the hour with ratings on both sides and none of its own")
        #expect(offer.change.contains("around 9am"), Comment(rawValue: offer.change))
        #expect(offer.premise.contains("never logged one at 9am"),
                Comment(rawValue: offer.premise))
    }

    /// Both halves of why this record is the one that works.
    ///
    /// The gap gives the curve something to interpolate to. The daily habit makes the
    /// measured proposal hollow, which is what stops it taking the focus area before
    /// the hour-led offer is reached — `PRD-HOURS.md` §10.8.
    @Test("It works because the morning is both the finding and the habit")
    func bothHalvesHold() throws {
        let store = store()
        let rows = store.engineObservations
        let morning = try #require(ExperimentVitals.timeWindow(.morning))

        #expect(ExperimentDesign.isHollow(morning, in: rows),
                "the measured morning offer must be hollow, or it takes focus first")
        #expect(!ExperimentHours.loggedHours(in: rows).contains(9),
                "09:00 must be unlogged, or there is nothing to offer")
        #expect(ExperimentHours.loggedHours(in: rows).isSuperset(of: [8, 10]),
                "08:00 and 10:00 must be logged, or 09:00 has no support either side")
    }
}
