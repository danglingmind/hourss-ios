import Testing
import Foundation
@testable import Hourss

/// Reading the shape of somebody's own heart-rate curve across their own day.
///
/// `Physiology` has fitted a per-person baseline on `Cell { band, isWorkday }` since
/// layer 3 shipped and has used it **only as a denominator** — every residual is
/// measured against it and nothing ever read the shape. These are the tests for the
/// shape, and most of them are about the ways reading it could invent a difference
/// that is not there.
///
/// The feeds are noiseless on purpose. Every band is a flat number, so each
/// baseline is exactly that number and every expected difference is arithmetic
/// rather than a tolerance — which means a failure here is a change in behaviour and
/// never a sampling accident.
@Suite("The shape of a day")
struct DayShapeTests {

    // MARK: - Fixtures

    /// Monday, so a run of days starts on a workday and the two day types are both
    /// well represented in any span over a week.
    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private static let calendar = Calendar.current

    /// A feed covering whole hours of whole days, at a heart rate the caller decides
    /// per hour and day type.
    ///
    /// Samples every five minutes, so each half-hour tile carries six of them — above
    /// `Analyzer.minimumSamplesForFitting` and above `minimumHeartRateSamples`, so no
    /// window is dropped for thinness and the tiling is the only thing deciding what
    /// the fit sees.
    ///
    /// Steps are a flat trickle rather than zero. The reference bin is then
    /// `.minimal` for every window, which is what makes the baselines comparable:
    /// a feed with no steps at all would put everything in `.still`, which works
    /// equally well, but a feed with *some* still windows and some minimal ones would
    /// fit the baselines from whichever bin happened to clear
    /// `minimumReferenceWindows` and compare bands across two different paces.
    private func feed(
        days: Int = 40,
        hours: (Int) -> Range<Int> = { _ in 7..<23 },
        bpm: (_ hour: Int, _ isWorkday: Bool) -> Double
    ) -> Physiology.Feed {
        var heartRate: [Physiology.Sample] = []
        var steps: [Physiology.Sample] = []
        let workdays: Set<Int> = [2, 3, 4, 5, 6]

        for day in 0..<days {
            guard let midnight = Self.calendar.date(byAdding: .day, value: day, to: Self.start)
            else { continue }
            let isWorkday = workdays.contains(Self.calendar.component(.weekday, from: midnight))
            for hour in hours(day) {
                for minute in stride(from: 0, to: 60, by: 5) {
                    guard let at = Self.calendar.date(
                        bySettingHour: hour, minute: minute, second: 0, of: midnight) else { continue }
                    heartRate.append(Physiology.Sample(at: at, value: bpm(hour, isWorkday)))
                    steps.append(Physiology.Sample(at: at, value: 6))
                }
            }
        }
        return Physiology.Feed(heartRate: heartRate, steps: steps)
    }

    private func shape(_ feed: Physiology.Feed) -> Physiology.DayShape {
        Physiology.Analyzer(feed: feed, fittingWindows: Physiology.Window.tiling(feed)).dayShape
    }

    /// Flat except for one band, which sits `offset` beats away from the rest.
    private func dip(_ band: TimeBucket, of offset: Double, days: Int = 40,
                     onlyOnDaysOff: Bool = false) -> Physiology.DayShape {
        shape(feed(days: days) { hour, isWorkday in
            guard TimeBucket.bucket(forHour: hour) == band else { return 65 }
            if onlyOnDaysOff && isWorkday { return 65 }
            return 65 + offset
        })
    }

    private func place(_ shape: Physiology.DayShape,
                       _ band: TimeBucket, workday: Bool) -> Physiology.DayShape.Place? {
        shape.places.first { $0.band == band && $0.isWorkday == workday }
    }

    // MARK: - That it reads anything at all

    /// The whole point: the numbers have stopped being private.
    @Test("A band that sits apart is reported, as a difference and not as a heart rate")
    func theShapeIsReadable() throws {
        let shape = dip(.morning, of: -10)
        let morning = try #require(place(shape, .morning, workday: true),
                                   "a ten-beat dip in the mornings was not reported at all")

        // Ten below the median of the other three bands, which are all 65.
        #expect(abs(morning.difference + 10) < 0.001,
                Comment(rawValue: "expected -10, got \(morning.difference)"))
        #expect(morning.isLower)

        // And only that band. The other three sit on top of each other, so none of
        // them differs from the median of the rest.
        for band in [TimeBucket.midday, .afternoon, .evening] {
            #expect(place(shape, band, workday: true) == nil,
                    Comment(rawValue: "\(band) was reported for a day that is flat outside its mornings"))
        }
    }

    /// What `lowest` and `highest` are for, which is phase 3 pointing at one end.
    @Test("The ends of the curve are reachable without exposing the baselines")
    func theEndsAreNamed() throws {
        // Morning low, afternoon high, midday and evening between them.
        let shape = shape(feed { hour, _ in
            switch TimeBucket.bucket(forHour: hour) {
            case .morning: 55
            case .afternoon: 80
            default: 65
            }
        })
        let lowest = try #require(shape.lowest)
        let highest = try #require(shape.highest)
        #expect(lowest.band == .morning)
        #expect(highest.band == .afternoon)
        #expect(lowest.difference < 0)
        #expect(highest.difference > 0)
    }

    // MARK: - The floor

    /// Chosen rather than derived, and the code says so. What it buys is silence
    /// about a difference too small to be worth a sentence.
    @Test("Under five beats a minute, nothing is said")
    func theFloorHolds() {
        #expect(dip(.morning, of: -4.9).isEmpty,
                "a difference under the floor was reported")
        #expect(!dip(.morning, of: -5.1).isEmpty,
                "a difference over the floor was withheld")
    }

    /// Five is five whichever way the band sits.
    @Test("The floor applies to a band sitting high as well as one sitting low")
    func theFloorIsSymmetric() throws {
        #expect(dip(.afternoon, of: 4).isEmpty)
        let high = try #require(place(dip(.afternoon, of: 9), .afternoon, workday: true))
        #expect(!high.isLower)
    }

    // MARK: - Workdays

    /// The cell already carries the distinction, so reading it costs nothing — and
    /// pooling the two would report a difference between two kinds of day as a
    /// difference between two times of day.
    @Test("A dip on days off is never reported as a dip on workdays")
    func dayTypesStayApart() throws {
        let shape = dip(.morning, of: -12, onlyOnDaysOff: true)

        let off = try #require(place(shape, .morning, workday: false),
                               "a dip on days off was not reported")
        #expect(abs(off.difference + 12) < 0.001)

        #expect(place(shape, .morning, workday: true) == nil,
                "a dip that only happens on days off was attributed to workdays")

        // And every place that did come back says which kind of day it is about, so
        // nothing downstream can read one as the other.
        #expect(shape.places.allSatisfy { !$0.isWorkday })
    }

    // MARK: - Borrowed baselines

    /// **The subtlest requirement in phase 1.**
    ///
    /// `MovementCurve.baseline(for:)` falls back to the day type's number and then to
    /// the person's overall one, which is right for scoring a session and wrong here.
    /// A borrowed number sits wherever the day type sits, so including it does two
    /// things: it can report a band as differing when what really happened is that it
    /// was never measured, and — the case this test is built around — it can *drag
    /// the yardstick* and quietly delete a real difference.
    ///
    /// The feed gives the evening a single hour on a single day, which is two
    /// half-hour windows and so under `minimumWindowsPerCell`. The remaining three
    /// bands are 55, 58 and 72.
    ///
    /// - Read from the earned cells only, the mornings are measured against
    ///   `median(58, 72) == 65`, which is ten beats away and worth a sentence.
    /// - Read through `baseline(for:)`, the evening borrows the day type's median of
    ///   58, the yardstick becomes `median(58, 72, 58) == 58`, and the mornings are
    ///   three beats away and vanish under the floor.
    ///
    /// So a version of this that reached for the convenient accessor would lose a real
    /// finding rather than gain a fake one, which is the harder failure to notice and
    /// the reason this test exists rather than an assertion that the evening is absent.
    @Test("A cell that borrowed its baseline is neither reported nor used as a yardstick")
    func borrowedBaselinesAreExcluded() throws {
        let sparse = feed(hours: { day in day == 0 ? 7..<19 : 7..<18 }) { hour, _ in
            switch TimeBucket.bucket(forHour: hour) {
            case .morning: 55
            case .midday: 58
            case .afternoon: 72
            case .evening: 95
            }
        }
        let shape = self.shape(sparse)

        let morning = try #require(place(shape, .morning, workday: true), Comment(rawValue:
            "the mornings were lost, which is what happens when a borrowed evening "
            + "baseline joins the comparison: \(shape.places)"))
        #expect(abs(morning.difference + 10) < 0.001,
                Comment(rawValue: "expected -10 against the two earned bands, got \(morning.difference)"))

        // And the band that never earned a number says nothing, despite sitting
        // thirty beats off anything else — because two windows is not evidence that
        // this person's evenings differ, only that nobody looked.
        #expect(!shape.places.contains { $0.band == .evening },
                Comment(rawValue: "an evening with two windows was reported: \(shape.places)"))
    }

    /// A difference needs a "rest of the day" to be a difference from.
    ///
    /// Two earned bands is a comparison between two times of day, and every sentence
    /// built on a place claims something about the rest of a day. So a day type with
    /// fewer than three earned cells produces nothing at all.
    @Test("A day with only two measured bands has no shape")
    func twoBandsAreNotADay() {
        // Mornings and afternoons only, twenty beats apart.
        let narrow = feed(hours: { _ in 7..<11 }) { _, _ in 55 }
        let wide = feed(hours: { _ in 14..<18 }) { _, _ in 75 }
        let combined = Physiology.Feed(
            heartRate: (narrow.heartRate + wide.heartRate).sorted { $0.at < $1.at },
            steps: (narrow.steps + wide.steps).sorted { $0.at < $1.at })
        #expect(shape(combined).isEmpty,
                "a twenty-beat gap between the only two bands somebody has was reported as a shape")
    }

    // MARK: - Hourly, and never a gate

    /// Where the density is there, the hour is named.
    @Test("An hour stands in for its band where enough separate days of it were recorded")
    func hourlyWhereTheDensitySupportsIt() throws {
        // Seven o'clock sits well below the rest of the morning, which itself sits on
        // the rest of the day. The hour is picked on density rather than on how
        // extreme it is, and every morning hour has the same density here, so the
        // tie-break takes the earliest — which is the one that was planted.
        let shape = shape(feed { hour, _ in
            switch hour {
            case 7: 50
            case 8..<11: 64
            default: 65
            }
        })
        let morning = try #require(place(shape, .morning, workday: true))
        #expect(morning.hour == 7,
                Comment(rawValue: "expected the hour to be resolved, got \(String(describing: morning.hour))"))
        // Seven o'clock against the median of the other three bands, all 65.
        #expect(abs(morning.difference + 15) < 0.001,
                Comment(rawValue: "expected the hour's own number, got \(morning.difference)"))
    }

    /// And where it is not, nothing is withheld.
    ///
    /// Each morning hour appears on a quarter of the days, so no single hour clears
    /// `minimumDaysPerHour` while the band clears `minimumWindowsPerCell` comfortably.
    /// The band is reported, with its hour unresolved — an hour is an improvement
    /// where the data earns it and never a condition of being told anything.
    @Test("Thin hourly density falls back to the band rather than to silence")
    func theHourIsNeverAGate() throws {
        let rotating = feed(days: 24, hours: { day in
            let morningHour = 7 + day % 4
            return morningHour..<(morningHour + 1)
        }) { _, _ in 55 }

        let afternoons = feed(days: 24, hours: { _ in 11..<23 }) { _, _ in 65 }
        let combined = Physiology.Feed(
            heartRate: (rotating.heartRate + afternoons.heartRate).sorted { $0.at < $1.at },
            steps: (rotating.steps + afternoons.steps).sorted { $0.at < $1.at })

        let shape = self.shape(combined)
        let morning = try #require(place(shape, .morning, workday: true), Comment(rawValue:
            "a band with real density but no dense hour was withheld: \(shape.places)"))
        #expect(morning.hour == nil,
                Comment(rawValue: "an hour was claimed on a few days of it: \(String(describing: morning.hour))"))
        #expect(abs(morning.difference + 10) < 0.001)
    }

    /// Determinism, because the shape decides which fortnight somebody is offered.
    @Test("The same history produces the same shape twice")
    func theOrderIsStable() {
        let feed = feed { hour, _ in
            switch TimeBucket.bucket(forHour: hour) {
            case .morning: 55
            case .afternoon: 80
            default: 65
            }
        }
        let first = shape(feed).places
        let second = shape(feed).places
        #expect(first == second)
        // Furthest from the rest of the day leads, which is what phase 3 reads when
        // it has no calibration to pick an end with.
        #expect(zip(first, first.dropFirst()).allSatisfy { $0.magnitude >= $1.magnitude })
    }

    // MARK: - Nothing to say

    @Test("No curve is an empty shape rather than a crash or a guess")
    func noCurveIsNoShape() {
        let empty = Physiology.Analyzer(feed: Physiology.Feed(), fittingWindows: [])
        #expect(empty.curve == nil)
        #expect(empty.dayShape.isEmpty)

        // A week is below `minimumDays`, so there is a feed and still no curve.
        let week = feed(days: 7) { _, _ in 65 }
        let thin = Physiology.Analyzer(feed: week, fittingWindows: Physiology.Window.tiling(week))
        #expect(thin.curve == nil)
        #expect(thin.dayShape.isEmpty)
    }

    /// A flat day is the common case and the app says nothing about it.
    @Test("A day that does not move says nothing")
    func aFlatDayIsSilent() {
        #expect(shape(feed { _, _ in 64 }).isEmpty)
    }

    // MARK: - The fixture

    /// Whether the simulator fixture reaches a shape at all.
    ///
    /// `DebugFixture.seededFeed` plants a circadian sine of eight beats peak to
    /// trough across 7am to 11pm. At band resolution the medians land either side of
    /// three to five beats, so the band alone does not reliably clear the floor; the
    /// hourly refinement is what earns the sentence, because the ends of that sine —
    /// the early morning and the late evening — are further from the rest of the day
    /// than any whole band is, and sixty days of every hour clears
    /// `minimumDaysPerHour` comfortably.
    ///
    /// So this is also the test that the hourly half is load-bearing rather than
    /// decorative: a version of phase 1 that stopped at the band would read this
    /// fixture as a flat day.
    ///
    /// Recorded as a test rather than a note, because the fixture is what the UI suite
    /// walks and what anybody looking at the app with data in it sees. If it starts
    /// failing, the fixture's curve has flattened and nothing vitals-led is reachable
    /// on a simulator — which is not a product bug and is exactly the kind of thing
    /// that is otherwise discovered nine minutes into a UI run.
    @Test("The seeded feed reaches a shape, by way of the hour rather than the band")
    @MainActor
    func theFixtureReachesAShape() throws {
        let feed = DebugFixture.seededFeed()
        let shape = self.shape(feed)
        #expect(!shape.isEmpty, Comment(rawValue:
            "the seeded feed produced no shape, so nothing vitals-led is reachable "
            + "on a simulator"))

        // Both ends of the sine, and both resolved to an hour rather than a band.
        // Hoisted out of the macro: `allSatisfy` is `rethrows`, and inside `#expect`
        // with a `Comment` the expansion will not compile.
        let everyPlaceHasAnHour = shape.places.allSatisfy { $0.hour != nil }
        let everyPlaceIsLower = shape.places.allSatisfy(\.isLower)
        #expect(everyPlaceHasAnHour, Comment(rawValue:
            "the fixture reached the floor at band resolution, which the sine should "
            + "not quite manage: \(shape.places)"))
        #expect(everyPlaceIsLower, Comment(rawValue:
            "the sine's extremes sit below the middle of the day, not above it: \(shape.places)"))
        #expect(Set(shape.places.map(\.band)) == [.morning, .evening], Comment(rawValue:
            "expected the two ends of the recorded day, got \(shape.places.map(\.band))"))
    }
}
