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
        let few = Array(person.sessions.filter(\.isEligibleForPatterns).prefix(5))
        let engine = Physiology.Analyzer(feed: feed(person), sessions: few)

        #expect(engine.curve == nil, "five windows is not a fitted curve")
        let session = try #require(few.first)
        #expect(engine.residual(for: session) == nil,
                "no curve means no residual, not a residual against nothing")

        // The bar is days as well as windows: thirty sessions from three days is
        // three days of evidence about this person.
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: person.sessions.filter(\.isEligibleForPatterns)) {
            calendar.startOfDay(for: $0.startAt)
        }
        let crammed = byDay.sorted { $0.key < $1.key }.prefix(4).flatMap(\.value)
        let cramped = Physiology.Analyzer(feed: feed(person), sessions: crammed)
        #expect(cramped.curve == nil, "windows from four days cannot fit a curve however many there are")
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
