import Foundation
import Testing
@testable import Hourss

/// That the cohort can describe an hour-of-day effect, and does.
///
/// **Why this suite exists before any of the feature does.** `PRD-HOURS.md` §2.3:
/// the answer key could not express the effect the work is meant to recover.
/// `Planted.timeWindow` takes two `TimeBucket`s, and 06:00 and 08:00 are both
/// `.morning`, so "07:00 is worth a point over 09:00" was not a sentence the
/// generator could be given. A cohort that cannot state the target cannot be used
/// to check whether it was hit — it would agree with any procedure, including one
/// that invented the answer.
///
/// So these tests are about the instrument rather than the engine. They assert that
/// the taper is shaped the way the case documents, that the three new people carry
/// the hours they claim, and that the ratings in their record actually move the way
/// the answer key says. Everything in phase 1 is measured against these people, and
/// a silent fault here would make every one of those measurements meaningless.
@Suite("Hour cohort")
struct HourCohortTests {

    private let calendar = Calendar.current

    private func session(at hour: Int, minute: Int = 0) -> Session {
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return Session(activityId: UUID(), startAt: start, endAt: start.addingTimeInterval(1800))
    }

    // MARK: - The taper

    @Test("Full strength at the centre, nothing at the edge")
    func taperEndpoints() {
        let centre = SyntheticCohort.hourTaper(session(at: 7), centre: 7, halfWidth: 1.5)
        #expect(centre == 1)

        // At exactly half-width it is already out: the case says "to nothing
        // `halfWidth` hours away", and a boundary that still contributes would put
        // a sliver of effect in the hour a test is about to assert is clean.
        let edge = SyntheticCohort.hourTaper(session(at: 8, minute: 30), centre: 7, halfWidth: 1.5)
        #expect(edge == 0)

        let beyond = SyntheticCohort.hourTaper(session(at: 13), centre: 7, halfWidth: 1.5)
        #expect(beyond == 0)
    }

    @Test("Linear between, and measured to the minute")
    func taperIsLinearAndFineGrained() {
        // Half way out is half strength.
        let half = SyntheticCohort.hourTaper(session(at: 7, minute: 45), centre: 7, halfWidth: 1.5)
        #expect(abs(half - 0.5) < 0.0001)

        // Forty minutes apart is not the same hour. This is the property that
        // makes the case finer than a bucket: two sessions inside 07:00 get
        // different contributions.
        let early = SyntheticCohort.hourTaper(session(at: 7, minute: 0), centre: 7, halfWidth: 1.5)
        let late = SyntheticCohort.hourTaper(session(at: 7, minute: 40), centre: 7, halfWidth: 1.5)
        #expect(early > late)
    }

    @Test("Distance wraps at midnight")
    func taperWraps() {
        // 23:30 is half an hour from 00:00, not twenty-three and a half.
        let near = SyntheticCohort.hourTaper(session(at: 23, minute: 30), centre: 0, halfWidth: 1.5)
        #expect(abs(near - (1 - 0.5 / 1.5)) < 0.0001)

        // And the same read from the other side. 00:00 is one hour past 23:00,
        // so it carries a third; 00:30 is a full half-width out and carries
        // nothing, which is the edge rule above read across midnight.
        let other = SyntheticCohort.hourTaper(session(at: 0), centre: 23, halfWidth: 1.5)
        #expect(abs(other - (1 - 1.0 / 1.5)) < 0.0001)
        #expect(SyntheticCohort.hourTaper(session(at: 0, minute: 30), centre: 23, halfWidth: 1.5) == 0)
    }

    // MARK: - Placement

    @Test("Stated hours are the only hours used")
    func peopleKeepTheirHours() {
        let cases: [(SyntheticCohort.Person, Set<Int>)] = [
            (SyntheticCohort.interpolator, [6, 8, 13, 16, 19]),
            (SyntheticCohort.extrapolator, [20, 21, 22]),
            (SyntheticCohort.flatHours, [6, 8, 10, 13, 16, 19, 21]),
        ]
        for (person, expected) in cases {
            let used = Set(person.sessions.map { calendar.component(.hour, from: $0.startAt) })
            #expect(used == expected,
                    Comment(rawValue: "\(person.name) used \(used.sorted())"))
        }
    }

    @Test("The interpolator never logs the hour its effect sits on")
    func interpolatorHasAHoleAtSeven() {
        let hours = SyntheticCohort.interpolator.sessions
            .map { calendar.component(.hour, from: $0.startAt) }
        #expect(!hours.contains(7), "the hole at 07:00 is the whole point of this person")
        // And the hours either side are both there, or there is nothing to
        // interpolate between and the person tests something else.
        #expect(hours.contains(6))
        #expect(hours.contains(8))
    }

    @Test("A day never puts two sessions in one hour")
    func hoursAreDrawnWithoutReplacement() {
        for person in [SyntheticCohort.interpolator, SyntheticCohort.flatHours] {
            let byDay = Dictionary(grouping: person.sessions) {
                calendar.startOfDay(for: $0.startAt)
            }
            for (day, sessions) in byDay {
                let hours = sessions.map { calendar.component(.hour, from: $0.startAt) }
                #expect(hours.count == Set(hours).count,
                        Comment(rawValue: "\(person.name) doubled up on \(day)"))
            }
        }
    }

    // MARK: - The effect is actually in the ratings

    /// The planted effect reaches the record, in the direction and roughly the size
    /// the answer key states.
    ///
    /// Asserted on the mean rating of the hours nearest the centre against the
    /// hours furthest from it, rather than on any engine output — this is a claim
    /// about the generator, and routing it through the engine would let an engine
    /// fault hide a generator fault.
    @Test("The interpolator's near hours are rated above their far ones")
    func interpolatorRatingsCarryTheEffect() {
        let person = SyntheticCohort.interpolator
        var near: [Double] = []
        var far: [Double] = []
        for session in person.sessions {
            guard let score = person.reflections[session.id]?.feelingScore else { continue }
            let hour = calendar.component(.hour, from: session.startAt)
            if hour == 6 || hour == 8 { near.append(Double(score)) } else { far.append(Double(score)) }
        }
        let nearMean = near.reduce(0, +) / Double(near.count)
        let farMean = far.reduce(0, +) / Double(far.count)

        #expect(near.count > 40, "too few near-hour ratings to say anything")
        #expect(far.count > 40)
        // 06:00 and 08:00 sit one hour from a 1.5-hour taper, so each carries about
        // a third of 1.2 — call it 0.4 — against hours that carry none. Asserted as
        // a band rather than a point because the rating is clamped to 1...5 and
        // rounded, both of which pull a planted delta toward the middle.
        #expect(nearMean - farMean > 0.15,
                Comment(rawValue: "near \(nearMean), far \(farMean)"))
        #expect(nearMean - farMean < 0.9)
    }

    @Test("Flat hours carry no hour effect at all")
    func flatHoursAreFlat() {
        let person = SyntheticCohort.flatHours
        var byHour: [Int: [Double]] = [:]
        for session in person.sessions {
            guard let score = person.reflections[session.id]?.feelingScore else { continue }
            byHour[calendar.component(.hour, from: session.startAt), default: []].append(Double(score))
        }
        let means = byHour.mapValues { $0.reduce(0, +) / Double($0.count) }
        let spread = (means.values.max() ?? 0) - (means.values.min() ?? 0)
        // Noise at 0.85 across seven hours of roughly ninety days each will not sit
        // at zero. What it must not do is look like the planted 1.2 of a real one.
        #expect(spread < 0.5, Comment(rawValue: "hour means: \(means.sorted { $0.key < $1.key })"))
    }
}
