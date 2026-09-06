import Testing
import Foundation
@testable import Hourss

/// Layer 3, against people whose physiology has a known cause.
///
/// `stillMeetings` and `walkingMeetings` are the whole argument for this layer.
/// Both carry the same planted effect — meetings run eleven beats a minute above
/// their hour's baseline — and the only thing that differs is that one of them
/// walks through the meeting. A heart-rate-only engine sees two identical people.
/// If the residual cannot tell them apart either, the layer is not earning its
/// place, and the test says so rather than being loosened until it passes.
@Suite("Movement-adjusted heart rate")
struct PhysiologyTests {

    // MARK: - Fixtures

    private func feed(
        _ person: SyntheticCohort.Person,
        vigorous: [DateInterval] = []
    ) -> Physiology.Feed {
        Physiology.Feed(
            heartRate: person.heartRate.map { Physiology.Sample(at: $0.at, value: $0.value) },
            steps: (person.samples[.steps] ?? []).map { Physiology.Sample(at: $0.at, value: $0.value) },
            vigorous: vigorous
        )
    }

    private func analyzer(
        _ person: SyntheticCohort.Person,
        vigorous: [DateInterval] = []
    ) -> Physiology.Analyzer {
        Physiology.Analyzer(feed: feed(person, vigorous: vigorous), sessions: person.sessions)
    }

    private func sessions(_ person: SyntheticCohort.Person, named: String) -> [Session] {
        guard let id = person.activities.first(where: { $0.name == named })?.id else { return [] }
        return person.sessions.filter { $0.activityId == id && $0.isEligibleForPatterns }
    }

    private func otherSessions(_ person: SyntheticCohort.Person, than named: String) -> [Session] {
        guard let id = person.activities.first(where: { $0.name == named })?.id else { return [] }
        return person.sessions.filter { $0.activityId != id && $0.isEligibleForPatterns }
    }

    /// Median residual over a person's sessions of one activity, plus enough
    /// context to read a failure without rerunning anything.
    private func residuals(
        _ person: SyntheticCohort.Person,
        named: String
    ) -> (median: Double, count: Int, medianCadence: Double) {
        let engine = analyzer(person)
        let readings = sessions(person, named: named).compactMap { engine.reading(for: $0) }
        return (
            Physiology.median(readings.map(\.residual)) ?? .nan,
            readings.count,
            Physiology.median(readings.map(\.cadence)) ?? .nan
        )
    }

    /// Raw median heart rate in an activity's windows minus the rest, with no
    /// adjustment of any kind. This is what an engine without layer 3 would see.
    private func rawElevation(_ person: SyntheticCohort.Person, named: String) -> Double {
        let samples = person.heartRate.map { Physiology.Sample(at: $0.at, value: $0.value) }
            .sorted { $0.at < $1.at }
        func level(_ group: [Session]) -> Double? {
            let beats = group.flatMap { session -> [Double] in
                guard let end = session.endAt else { return [] }
                return Physiology.slice(samples, from: session.startAt, to: end).map(\.value)
            }
            return Physiology.median(beats)
        }
        guard let inside = level(sessions(person, named: named)),
              let outside = level(otherSessions(person, than: named)) else { return .nan }
        return inside - outside
    }

    // MARK: - The separation

    @Test("Sitting still through a raised heart rate leaves a positive residual")
    func stillMeetingsShowResidual() throws {
        let measured = residuals(SyntheticCohort.stillMeetings, named: "Meetings")
        print("PHYS still: residual=\(measured.median) cadence=\(measured.medianCadence) n=\(measured.count)")

        try #require(measured.count >= 5, "not enough scorable meeting windows to judge")
        #expect(measured.medianCadence < 20, Comment(rawValue:
            "this person is meant to be sitting still; cadence was \(measured.medianCadence)"))
        #expect(measured.median > 5, Comment(rawValue:
            "an 11 bpm rise with no movement behind it should survive the adjustment; got \(measured.median)"))
    }

    @Test("Walking through the same rise leaves almost nothing unexplained")
    func walkingMeetingsShowNoResidual() throws {
        let measured = residuals(SyntheticCohort.walkingMeetings, named: "Meetings")
        print("PHYS walking: residual=\(measured.median) cadence=\(measured.medianCadence) n=\(measured.count)")

        try #require(measured.count >= 5, "not enough scorable meeting windows to judge")
        #expect(measured.medianCadence > 60, Comment(rawValue:
            "this person is meant to be walking; cadence was \(measured.medianCadence)"))
        #expect(abs(measured.median) < 4, Comment(rawValue:
            "the walking accounts for the rise, so nothing should be left over; got \(measured.median)"))
    }

    @Test("The two are separated only after adjustment, never before")
    func rawHeartRateCannotSeparateThem() {
        let still = rawElevation(SyntheticCohort.stillMeetings, named: "Meetings")
        let walking = rawElevation(SyntheticCohort.walkingMeetings, named: "Meetings")
        print("PHYS raw elevation: still=\(still) walking=\(walking)")

        // Both are genuinely elevated, by construction.
        #expect(still > 6, Comment(rawValue: "still meetings raw elevation was \(still)"))
        #expect(walking > 6, Comment(rawValue: "walking meetings raw elevation was \(walking)"))
        // And raw heart rate says the same thing about both, which is the point:
        // without the movement decomposition there is nothing here to split on.
        #expect(abs(still - walking) < 4, Comment(rawValue:
            "raw heart rate should look alike for both; \(still) vs \(walking)"))

        let stillResidual = residuals(SyntheticCohort.stillMeetings, named: "Meetings").median
        let walkingResidual = residuals(SyntheticCohort.walkingMeetings, named: "Meetings").median
        #expect(stillResidual - walkingResidual > 4, Comment(rawValue:
            "the residual is the only thing that separates them; \(stillResidual) vs \(walkingResidual)"))
    }

    // MARK: - Learning the movement cost from somewhere other than the meetings

    /// The fixture is what it claims before anything is concluded from it.
    ///
    /// `walkingMeetings` walks only in meetings; these two walk through half of
    /// everything. If that were not true of the generated data, the out-of-sample
    /// claim below would be a sentence rather than a fact.
    @Test("The habitual walkers really do walk outside their meetings")
    func walkersWalkOutsideMeetings() throws {
        for person in [SyntheticCohort.walksEverywhere, SyntheticCohort.walksAndStrains] {
            let steps = person.samples[.steps] ?? []
            let brisk = otherSessions(person, than: "Meetings")
                .map { SyntheticCohort.cadence(during: $0, steps: steps) }
                .filter { $0 > 60 }
            #expect(brisk.count >= 40, Comment(rawValue:
                "\(person.name) has only \(brisk.count) brisk non-meeting sessions to learn walking from"))
        }

        // And the person the original result was measured on does not, which is
        // exactly the gap these two exist to close.
        let circular = SyntheticCohort.walkingMeetings
        let steps = circular.samples[.steps] ?? []
        let brisk = otherSessions(circular, than: "Meetings")
            .map { SyntheticCohort.cadence(during: $0, steps: steps) }
            .filter { $0 > 60 }
        #expect(brisk.count < 10, Comment(rawValue:
            "walkingMeetings is meant to walk only in meetings; found \(brisk.count) brisk sessions elsewhere"))
    }

    @Test("Walking learned from elsewhere still explains the meeting rise")
    func walksEverywhereShowsNoResidual() throws {
        let person = SyntheticCohort.walksEverywhere
        let measured = residuals(person, named: "Meetings")
        print("PHYS walksEverywhere: residual=\(measured.median) cadence=\(measured.medianCadence) n=\(measured.count)")

        try #require(measured.count >= 5, "not enough scorable meeting windows to judge")
        #expect(measured.medianCadence > 60, Comment(rawValue:
            "this person is meant to be walking through meetings; cadence was \(measured.medianCadence)"))
        #expect(abs(measured.median) < 4, Comment(rawValue:
            "the walking cost is fitted mostly from non-meeting windows, so nothing should be left over; got \(measured.median)"))
    }

    @Test("A rise movement only partly explains is recovered, not swallowed")
    func walksAndStrainsShowsThePartMovementDoesNotExplain() throws {
        let person = SyntheticCohort.walksAndStrains
        let measured = residuals(person, named: "Meetings")
        print("PHYS walksAndStrains: residual=\(measured.median) cadence=\(measured.medianCadence) n=\(measured.count)")

        try #require(measured.count >= 5, "not enough scorable meeting windows to judge")
        #expect(measured.medianCadence > 60, Comment(rawValue:
            "this person walks through meetings too; cadence was \(measured.medianCadence)"))
        // Planted at 9 bpm on top of an 11 bpm walking cost. A binary movement
        // gate scores this person zero by discarding him; the decomposition has
        // to return the 9 and not the 20.
        #expect(measured.median > 4, Comment(rawValue:
            "the 9 bpm movement cannot explain must survive the adjustment; got \(measured.median)"))
        #expect(measured.median < 15, Comment(rawValue:
            "only the unexplained part belongs in the residual, not the walking as well; got \(measured.median)"))
    }

    /// The strongest form of the question: hold the meetings out of the fit.
    ///
    /// The residuals above are already dominated by non-meeting windows, but the
    /// meetings are still in the bin. Refitting with them removed leaves no way at
    /// all for the meeting effect to reach the curve, so what comes back is a
    /// prediction in the ordinary sense — and the same procedure run on
    /// `walkingMeetings` shows what the original setup could and could not support.
    @Test("Held out of its own fit, the walking cost still lands")
    func meetingsScoredAgainstACurveTheyDidNotTrain() throws {
        func heldOut(_ person: SyntheticCohort.Person) -> (median: Double, count: Int) {
            let others = otherSessions(person, than: "Meetings").compactMap(Physiology.Window.init(session:))
            let engine = Physiology.Analyzer(feed: feed(person), fittingWindows: others)
            let readings = sessions(person, named: "Meetings").compactMap { engine.reading(for: $0) }
            return (Physiology.median(readings.map(\.residual)) ?? .nan, readings.count)
        }

        let clean = heldOut(SyntheticCohort.walksEverywhere)
        let strained = heldOut(SyntheticCohort.walksAndStrains)
        let circular = heldOut(SyntheticCohort.walkingMeetings)
        print("PHYS held out: clean=\(clean) strained=\(strained) walkingMeetings=\(circular)")

        try #require(clean.count >= 5, "no scorable meeting windows once the meetings left the fit")
        try #require(strained.count >= 5, "no scorable meeting windows once the meetings left the fit")
        #expect(abs(clean.median) < 4, Comment(rawValue:
            "walking learned entirely elsewhere should still account for the rise; got \(clean.median)"))
        #expect(strained.median > 4, Comment(rawValue:
            "the part movement does not explain should survive a held-out fit; got \(strained.median)"))

        // `walkingMeetings` walks nowhere else, so a curve fitted without their
        // meetings has never seen that pace and refuses rather than guessing. The
        // original near-zero number was therefore only ever available *because*
        // the meetings were in their own fit — which is what made it worth
        // checking against somebody who walks elsewhere.
        #expect(circular.count == 0, Comment(rawValue:
            "a curve with no brisk windows in it should refuse a brisk meeting, not score \(circular.count) of them"))
    }

    @Test("Two people who walk identically are separated by the residual alone")
    func cadenceAloneCannotSeparateTheWalkers() {
        let clean = residuals(SyntheticCohort.walksEverywhere, named: "Meetings")
        let strained = residuals(SyntheticCohort.walksAndStrains, named: "Meetings")
        print("PHYS walker split: clean=\(clean.median)@\(clean.medianCadence) strained=\(strained.median)@\(strained.medianCadence)")

        // Same habit, same pace: movement has nothing to say about which is which.
        #expect(abs(clean.medianCadence - strained.medianCadence) < 20, Comment(rawValue:
            "the two walkers should move alike; \(clean.medianCadence) vs \(strained.medianCadence)"))
        #expect(strained.median - clean.median > 4, Comment(rawValue:
            "only the residual separates them; \(strained.median) vs \(clean.median)"))
    }

    // MARK: - Refusals

    @Test("A session in the shadow of exercise returns nil rather than a correction")
    func leadInExclusion() throws {
        let person = SyntheticCohort.stillMeetings
        let clean = analyzer(person)
        let scorable = sessions(person, named: "Meetings").first { clean.reading(for: $0) != nil }
        let session = try #require(scorable, "needed one scorable meeting window to contaminate")

        // A workout ending twenty minutes before the session starts. Heart rate is
        // still on its way down; the baseline is contaminated, not correctable.
        let workout = DateInterval(
            start: session.startAt.addingTimeInterval(-60 * 60),
            end: session.startAt.addingTimeInterval(-20 * 60)
        )
        let contaminated = analyzer(person, vigorous: [workout])
        #expect(contaminated.reading(for: session) == nil,
                "a window 20 minutes after a workout must not be given a residual")

        // And the exclusion is the lead-in, not the workout existing at all.
        let longAgo = DateInterval(
            start: session.startAt.addingTimeInterval(-6 * 3600),
            end: session.startAt.addingTimeInterval(-5 * 3600)
        )
        #expect(analyzer(person, vigorous: [longAgo]).reading(for: session) != nil,
                "a workout five hours earlier is not contamination")
    }

    @Test("Too few heart-rate samples returns nil")
    func tooFewSamples() throws {
        let person = SyntheticCohort.stillMeetings
        let engine = analyzer(person)
        let session = try #require(sessions(person, named: "Meetings").first)

        // Ten minutes cannot hold five samples at any sampling rate a wrist uses
        // at rest. A heart rate built on one or two readings is not a heart rate.
        let sliver = Physiology.Window(
            start: session.startAt,
            end: session.startAt.addingTimeInterval(10 * 60)
        )
        #expect(engine.summary(for: sliver) == nil)
        #expect(engine.reading(for: sliver) == nil)
    }

    @Test("A curve is not fitted from too little history")
    func thinHistoryHasNoCurve() throws {
        let person = SyntheticCohort.stillMeetings

        // Thin means thin *sensor* history. The curve describes how this person's
        // heart answers movement, which is a fact about them rather than about
        // their logging, so it is fitted from everything the watch recorded and
        // not only from the stretches they happened to label. Three days of
        // readings is below the bar however many of them are logged.
        let calendar = Calendar.current
        let days = Set(person.heartRate.map { calendar.startOfDay(for: $0.at) }).sorted()
        let cutoff = try #require(days.dropFirst(3).first)

        let thin = Physiology.Feed(
            heartRate: person.heartRate.filter { $0.at < cutoff }
                .map { Physiology.Sample(at: $0.at, value: $0.value) },
            steps: (person.samples[.steps] ?? []).filter { $0.at < cutoff }
                .map { Physiology.Sample(at: $0.at, value: $0.value) }
        )
        let starved = Physiology.Analyzer(feed: thin, sessions: person.sessions)
        #expect(starved.curve == nil, "three days of readings is not a fitted curve")

        let inRange = try #require(person.sessions.first { ($0.endAt ?? $0.startAt) < cutoff })
        #expect(starved.residual(for: inRange) == nil,
                "no curve means no residual, not a residual against nothing")
    }

    /// The improvement this replaced: the curve used to be fitted only on logged
    /// sessions, so someone with a full year of readings who rarely logged had no
    /// curve at all, and the layer refused to score anything. Safe, and useless.
    @Test("A curve is fitted from readings even when little was logged")
    func sparseLoggingStillFitsACurve() throws {
        let person = SyntheticCohort.walksEverywhere
        let few = Array(person.sessions.filter(\.isEligibleForPatterns).prefix(5))
        let engine = Physiology.Analyzer(feed: feed(person), sessions: few)

        let curve = try #require(engine.curve,
                                 "a full history of readings should fit a curve on five logged sessions")
        #expect(curve.canExplain(cadence: 90),
                "the curve should have learned a brisk pace from unlogged time")
    }

    // MARK: - What the curve is for

    @Test("Movement is decomposed, not gated away")
    func movementIsExplainedNotDiscarded() throws {
        let person = SyntheticCohort.walkingMeetings
        let engine = analyzer(person)
        let curve = try #require(engine.curve, "the walking person should have enough history to fit")

        let atRest = curve.explained(atCadence: 0)
        let walking = curve.explained(atCadence: 100)
        print("PHYS lift: 0=\(atRest) 100=\(walking) ceiling=\(curve.fittedCeiling)")

        #expect(atRest == 0, "the lift is anchored on standing still")
        #expect(walking > 3, Comment(rawValue:
            "walking should be credited with some of the rise; got \(walking)"))

        // The correction that does the most arithmetic is the least trustworthy,
        // because wrist heart rate is least accurate while moving.
        let readings = sessions(person, named: "Meetings").compactMap { engine.reading(for: $0) }
        let quiet = otherSessions(person, than: "Meetings").compactMap { engine.reading(for: $0) }
        let movingUncertainty = Physiology.median(readings.map(\.uncertainty)) ?? .nan
        let stillUncertainty = Physiology.median(quiet.map(\.uncertainty)) ?? .nan
        #expect(movingUncertainty > stillUncertainty, Comment(rawValue:
            "uncertainty must widen with cadence, not narrow; \(movingUncertainty) vs \(stillUncertainty)"))
    }

    @Test("The output is a number and a movement context, never a verdict")
    func outputCarriesNoJudgement() throws {
        let engine = analyzer(SyntheticCohort.stillMeetings)
        let session = try #require(
            sessions(SyntheticCohort.stillMeetings, named: "Meetings").first { engine.reading(for: $0) != nil }
        )
        let reading = try #require(engine.reading(for: session))

        #expect(reading.observed == reading.expected + reading.residual)
        // The only words this layer produces describe how much somebody moved.
        let banned = ["stress", "intense", "anxious", "calm", "effort", "strain", "tense"]
        for word in Physiology.CadenceBin.allCases.map(\.context) {
            #expect(!banned.contains { word.lowercased().contains($0) }, Comment(rawValue:
                "movement context must not imply a cause: \"\(word)\""))
        }
        #expect(!reading.movementContext.isEmpty)
    }
}
