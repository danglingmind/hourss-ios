import Foundation
import Testing
@testable import Hourss

/// That the hour curve finds an hour nobody logged, and refuses one it cannot reach.
///
/// The three people this is measured on were built for it in phase 0 and carry
/// their answer by construction. `interpolator` has a +1.2 effect at 07:00 and logs
/// 06:00 and 08:00 — their own record contains information about 07:00 and the
/// engine currently throws it away. `extrapolator` has the same effect at the same
/// hour and logs only 20:00–22:00; their record contains nothing about 07:00 and no
/// procedure can invent any, so the required answer is refusal. `flatHours` has
/// support at every hour and signal at none.
///
/// The second and third are what this suite is for. A smoother asked about an
/// unobserved hour will return a number that looks exactly like the ones that mean
/// something, and the only thing standing between that and a confident lie is the
/// support floor.
@Suite("Rating shape")
struct RatingShapeTests {

    private func rows(_ person: SyntheticCohort.Person) -> [EngineObservation] {
        ObservationBuilder.rows(
            sessions: person.sessions,
            reflections: person.reflections,
            activities: person.activities,
            healthByDay: person.healthByDay,
            residuals: [:],
            workdays: Profile().workdays
        )
    }

    // MARK: - The kernel

    @Test("Distance wraps at midnight")
    func kernelWraps() {
        // 23:00 and 01:00 are two hours apart, so they weigh the same as 07:00 and
        // 09:00. A kernel that measured twenty-two would cut the day in half at an
        // arbitrary point.
        let across = RatingShape.kernel(from: 23, to: 1, bandwidth: 1.5)
        let within = RatingShape.kernel(from: 7, to: 9, bandwidth: 1.5)
        #expect(abs(across - within) < 0.000_001)
    }

    @Test("Weight falls away with distance and is full at the centre")
    func kernelShape() {
        #expect(RatingShape.kernel(from: 7, to: 7, bandwidth: 1.5) == 1)
        let one = RatingShape.kernel(from: 7, to: 8, bandwidth: 1.5)
        let two = RatingShape.kernel(from: 7, to: 9, bandwidth: 1.5)
        let far = RatingShape.kernel(from: 7, to: 19, bandwidth: 1.5)
        #expect(one > two && two > far)
        #expect(far < 0.000_001, "the other side of the day may not inform an hour")
    }

    // MARK: - Day clustering

    /// Three sessions on one Tuesday are one day's evidence about that hour.
    ///
    /// The same argument the day-clustered bootstrap rests on: weighting by session
    /// inflates support precisely for the people who log heavily, who are the people
    /// most likely to be reading the result.
    @Test("An hour logged three times in one day counts once")
    func clusteredOnDays() {
        let person = SyntheticCohort.interpolator
        let points = RatingShape.dayPoints(rows(person))
        let keys = points.map { "\($0.day.timeIntervalSince1970)-\($0.hour)" }
        #expect(keys.count == Set(keys).count,
                "a day and an hour may appear at most once")
    }

    // MARK: - The three people

    /// The case the whole feature exists for: an hour inside their own range that
    /// they have never logged.
    @Test("The interpolator's unlogged hour is found, and reads above their others")
    func interpolatorIsRecovered() throws {
        let shape = RatingShape.fit(rows(SyntheticCohort.interpolator))
        #expect(!shape.isEmpty)

        // 07:00 sits one hour from two logged hours, so it should have ample support.
        let seven = try #require(shape.hour(7, isWorkday: true))
        #expect(seven.support >= RatingShape.minimumSupport)

        // The planted effect is at 07:00, so the smoothed estimate there must beat
        // the hours well away from it. Asserted against their afternoon and evening
        // rather than against 06:00 and 08:00 — those two carry a third of the taper
        // each, so they are raised too, which is exactly why 07:00 is reachable.
        let afternoon = try #require(shape.hour(16, isWorkday: true))
        #expect(seven.estimate > afternoon.estimate,
                Comment(rawValue: "07:00 \(seven.estimate) vs 16:00 \(afternoon.estimate)"))
    }

    /// The integrity test. Their record says nothing about 07:00 and the curve must
    /// say nothing either.
    @Test("The extrapolator is refused at the hour they have never been awake for")
    func extrapolatorIsRefused() {
        let shape = RatingShape.fit(rows(SyntheticCohort.extrapolator))
        #expect(shape.hour(7, isWorkday: true) == nil,
                "a smoother will happily return a number for 07:00 here, and it is invented")
        #expect(shape.hour(7, isWorkday: false) == nil)

        // And it is refused for want of support rather than because the fit failed
        // altogether — the hours they do log must still be there, or this test would
        // pass on an empty shape and prove nothing.
        #expect(shape.hour(21, isWorkday: true) != nil || shape.hour(21, isWorkday: false) != nil,
                "their own evening should be reachable")
    }

    /// Support everywhere, signal nowhere.
    @Test("Flat hours produce no hour that stands out")
    func flatHoursAreFlat() throws {
        let shape = RatingShape.fit(rows(SyntheticCohort.flatHours))
        let workday = shape.hours.filter(\.isWorkday)
        try #require(!workday.isEmpty)

        let spread = (workday.map(\.estimate).max() ?? 0) - (workday.map(\.estimate).min() ?? 0)
        // Noise at 0.85 over seven hours will not sit at zero. What it must not do is
        // look like the planted 1.2 of a real one.
        #expect(spread < 0.6, Comment(rawValue:
            "hours: \(workday.map { ($0.hour, round($0.estimate * 100) / 100) })"))
    }

    // MARK: - The floor, and what it is worth

    /// `PRD-HOURS.md` open decisions 2 and 3, settled by measurement and recorded.
    ///
    /// The support floor and the bandwidth are the two numbers in this feature that
    /// cannot be derived, and the document's method for both is the same: pick them
    /// from the cohort and record what they cost. This test is that record — it
    /// fails if a later change to either makes the interpolator unreachable or the
    /// extrapolator reachable, which are the only two outcomes that matter.
    @Test("The floor separates the two people it exists to separate")
    func theFloorIsWhereItNeedsToBe() throws {
        let near = RatingShape.fit(rows(SyntheticCohort.interpolator), minimumSupport: 0)
        let far = RatingShape.fit(rows(SyntheticCohort.extrapolator), minimumSupport: 0)

        let reachable = try #require(near.hour(7, isWorkday: true)?.support)
        let invented = far.hour(7, isWorkday: true)?.support ?? 0

        // Two orders of magnitude between them, which is what makes the exact value
        // of the floor uncritical and the existence of one essential.
        #expect(reachable > RatingShape.minimumSupport)
        #expect(invented < RatingShape.minimumSupport)
        #expect(reachable > invented * 10, Comment(rawValue:
            "reachable \(reachable), invented \(invented) — the gap is the whole margin"))
    }

    @Test("A thin record is not fitted at all")
    func tooFewDays() {
        let thin = Array(rows(SyntheticCohort.interpolator).prefix(4))
        #expect(RatingShape.fit(thin).isEmpty,
                "a curve over a handful of days is a curve over a handful of days")
    }

    // MARK: - Choosing

    @Test("The best hour ignores the ones already in use, and ties break early")
    func bestExcludesAndIsStable() throws {
        let shape = RatingShape.fit(rows(SyntheticCohort.interpolator))
        let best = try #require(shape.best(isWorkday: true))
        let without = shape.best(isWorkday: true, excluding: [best.hour])
        #expect(without?.hour != best.hour)

        // Two fits over one history agree, including on which hour wins.
        let again = RatingShape.fit(rows(SyntheticCohort.interpolator))
        #expect(again.best(isWorkday: true) == best)
    }

    /// **The whole feature, in one assertion.**
    ///
    /// Among the hours this person does not already use, the one the curve picks is
    /// the one their effect is planted at — an hour they have never logged, named
    /// from their own ratings at the hours either side of it. Nothing else in this
    /// suite would catch the curve getting the right shape and the wrong argmax.
    @Test("The unlogged hour the curve picks is the one the effect is planted at")
    func thePickedHourIsThePlantedOne() throws {
        let shape = RatingShape.fit(rows(SyntheticCohort.interpolator))
        let logged = Set([6, 8, 13, 16, 19])
        let pick = try #require(shape.best(isWorkday: true, excluding: logged))
        #expect(pick.hour == 7, Comment(rawValue:
            "picked \(pick.hour) at \(pick.estimate); candidates were "
            + "\(shape.hours.filter { $0.isWorkday && !logged.contains($0.hour) }.map { ($0.hour, round($0.estimate * 100) / 100) })"))
    }

    /// An hour just outside the earliest one somebody logs is extrapolation, and a
    /// total-support floor cannot see it.
    ///
    /// This is the hole the cohort found. With a one-sided floor the interpolator's
    /// curve ran `4:3.47 5:3.46 6:3.44 7:3.40` — 04:00 and 05:00 scoring *above* the
    /// planted hour, on support of 14 and 29 against a floor of 6. The arithmetic was
    /// right: no hour is logged at the peak, so the curve plateaus across 06:00–08:00
    /// and an hour outside the earliest logged one inherits the plateau without the
    /// afternoon pulling it down. The argmax landed on an hour this person has never
    /// been awake for.
    ///
    /// `minimumSupport` answers "is this hour near anything?". It cannot answer "is
    /// this hour *between* things?", and at the edges of a day those differ.
    @Test("An hour beyond the edge of somebody's day is refused, however near it is")
    func edgesAreNotInterpolation() {
        let shape = RatingShape.fit(rows(SyntheticCohort.interpolator))
        #expect(shape.hour(4, isWorkday: true) == nil,
                "04:00 is an hour before anything this person has ever logged")
        #expect(shape.hour(5, isWorkday: true) == nil)
        // And the edge itself is kept: 06:00 is logged, so it is surrounded by its
        // own evidence. The rule refuses hours beyond the record, not the record.
        #expect(shape.hour(6, isWorkday: true) != nil)
    }
}
