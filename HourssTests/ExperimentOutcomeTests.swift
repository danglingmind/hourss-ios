import Foundation
import Testing
@testable import Hourss

/// That a window reads the way it is supposed to, including when it cannot be read.
@Suite("Experiment outcome")
struct ExperimentOutcomeTests {

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private func experiment(predictsHigher: Bool = true, windowDays: Int = 14) -> Experiment {
        Experiment(
            hypothesisId: "time.morning.vs.rest.feeling",
            outcome: .feeling,
            startedAt: Self.start,
            windowDays: windowDays,
            focusLabel: "Morning",
            baselineLabel: "The rest of your day",
            predictsHigher: predictsHigher,
            premise: "Your mornings have run higher so far.",
            change: "Put one block before 11am.",
            caveat: "Time of day travels with whatever you tend to schedule then."
        )
    }

    /// Splits on hour: before 11am is the focus side. Mirrors the registry's own
    /// time-bucket shape without depending on it, so these tests exercise the
    /// outcome layer rather than the registry.
    private func hypothesis() -> Hypothesis {
        Hypothesis(
            id: "time.morning.vs.rest.feeling",
            type: .bestTimeWindow,
            outcome: .feeling,
            focusLabel: "Morning",
            baselineLabel: "The rest of your day",
            focus: { Self.calendar.component(.hour, from: $0.startAt) < 11 },
            baseline: { Self.calendar.component(.hour, from: $0.startAt) >= 11 },
            phrase: { _ in "" },
            caveat: ""
        )
    }

    /// One rated session, on `dayOffset` days after the window opens, at `hour`.
    private func row(dayOffset: Int, hour: Int, feeling: Double?) -> EngineObservation {
        let day = Self.calendar.date(byAdding: .day, value: dayOffset, to: Self.start)!
        let startAt = Self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        return EngineObservation(
            sessionId: UUID(), day: Self.calendar.startOfDay(for: startAt), startAt: startAt,
            durationMinutes: 60, activityName: "Deep work", activityCategory: "work",
            timeBucket: hour < 11 ? .morning : .afternoon,
            durationBucket: .medium, isWorkday: true,
            feeling: feeling, performance: nil, dayHealth: [:],
            heartRateResidual: nil, cadence: nil
        )
    }

    /// `days` consecutive days of both sides, starting `from` days into the window.
    ///
    /// `from` exists because two calls without it produce the same calendar days
    /// twice rather than appending to each other, and a test that means "ten days"
    /// then quietly asserts against eight.
    private func rows(days: Int, from: Int = 0,
                      focusFeeling: Double, baseFeeling: Double) -> [EngineObservation] {
        (from..<(from + days)).flatMap { offset in
            [row(dayOffset: offset, hour: 9, feeling: focusFeeling),
             row(dayOffset: offset, hour: 15, feeling: baseFeeling)]
        }
    }

    // MARK: Verdicts

    @Test("A clear separation in the predicted direction holds up")
    func holdsUp() {
        // Every morning above every afternoon: Cliff's delta is 1, and the
        // interval cannot straddle zero.
        var observations = rows(days: 8, focusFeeling: 5, baseFeeling: 2)
        observations += rows(days: 2, from: 8, focusFeeling: 4, baseFeeling: 3)

        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        #expect(reading.verdict == .heldUp)
        #expect(reading.adherenceDays == 10)
        #expect(reading.baselineDays == 10)
        #expect(reading.focusFigure > reading.baselineFigure)
        #expect(reading.isReadable)
    }

    @Test("Two sides that interleave did not hold up")
    func didNotHoldUp() {
        // Alternating, so neither side is reliably above the other.
        let observations = (0..<10).flatMap { offset -> [EngineObservation] in
            let high = offset.isMultiple(of: 2)
            return [row(dayOffset: offset, hour: 9, feeling: high ? 4 : 2),
                    row(dayOffset: offset, hour: 15, feeling: high ? 2 : 4)]
        }
        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        #expect(reading.verdict == .didNotHoldUp)
        #expect(reading.comparison?.spansZero == true)
    }

    /// The case that separates a test from a fishing expedition.
    @Test("A clear separation the wrong way round did not hold up")
    func backwardsIsNotSuccess() {
        // Mornings far *below* afternoons, against a prediction of higher.
        let observations = rows(days: 10, focusFeeling: 2, baseFeeling: 5)
        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        #expect(reading.comparison?.spansZero == false)
        #expect(reading.verdict == .didNotHoldUp)

        // The identical data, predicted the other way round, holds up — which is
        // the whole point of the direction being declared in advance.
        let reversed = ExperimentOutcome.read(experiment(predictsHigher: false),
                                              hypothesis: hypothesis(),
                                              observations: observations, calendar: Self.calendar)
        #expect(reversed.verdict == .heldUp)
    }

    // MARK: Floors

    @Test("Too few days of the change cannot be read")
    func lowAdherenceCannotBeRead() {
        var observations = rows(days: 10, focusFeeling: 5, baseFeeling: 2)
        // Strip the focus side down to three days, leaving the baseline intact.
        observations = observations.filter { row in
            let hour = Self.calendar.component(.hour, from: row.startAt)
            if hour >= 11 { return true }
            let offset = Self.calendar.dateComponents([.day], from: Self.start, to: row.startAt).day ?? 0
            return offset < 3
        }
        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        #expect(reading.verdict == .cannotTell)
        #expect(reading.adherenceDays == 3)
        #expect(reading.baselineDays == 10)
        // The counts survive, so the card can say what would have been enough.
        #expect(reading.comparison == nil)
        #expect(!reading.isReadable)
    }

    @Test("Exactly the minimum is enough, and one fewer is not")
    func theBoundary() {
        let atFloor = rows(days: Experiment.minimumDays, focusFeeling: 5, baseFeeling: 2)
        #expect(ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                        observations: atFloor, calendar: Self.calendar)
                    .verdict != .cannotTell)

        let below = rows(days: Experiment.minimumDays - 1, focusFeeling: 5, baseFeeling: 2)
        #expect(ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                        observations: below, calendar: Self.calendar)
                    .verdict == .cannotTell)
    }

    @Test("Sessions outside the window are not counted")
    func windowIsRespected() {
        // Ten good days, all of them after the fortnight closed.
        let late = (20..<30).flatMap { offset in
            [row(dayOffset: offset, hour: 9, feeling: 5),
             row(dayOffset: offset, hour: 15, feeling: 2)]
        }
        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: late, calendar: Self.calendar)
        #expect(reading.adherenceDays == 0)
        #expect(reading.verdict == .cannotTell)
    }

    @Test("Unrated sessions are not adherence")
    func unratedDoesNotCount() {
        // The change was made every day, and never rated. There is nothing to read.
        let observations = (0..<10).flatMap { offset in
            [row(dayOffset: offset, hour: 9, feeling: nil),
             row(dayOffset: offset, hour: 15, feeling: 3)]
        }
        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        #expect(reading.adherenceDays == 0)
        #expect(reading.verdict == .cannotTell)
    }

    @Test("A hypothesis that has left the registry cannot be read")
    func missingHypothesis() {
        let reading = ExperimentOutcome.read(experiment(), hypothesis: nil,
                                             observations: rows(days: 10, focusFeeling: 5, baseFeeling: 2),
                                             calendar: Self.calendar)
        #expect(reading.verdict == .cannotTell)
        #expect(reading.adherenceDays == 0)
    }

    // MARK: Figures

    @Test("Figures are means of day means, not of sessions")
    func dayMeansNotSessionMeans() {
        // One day carries three morning sessions rated 5; nine carry one rated 2.
        // A session mean would be pulled up by the burst; a day mean must not be.
        var observations: [EngineObservation] = []
        for _ in 0..<3 { observations.append(row(dayOffset: 0, hour: 9, feeling: 5)) }
        for offset in 1..<10 { observations.append(row(dayOffset: offset, hour: 9, feeling: 2)) }
        for offset in 0..<10 { observations.append(row(dayOffset: offset, hour: 15, feeling: 3)) }

        let reading = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                             observations: observations, calendar: Self.calendar)
        // Day means: one 5 and nine 2s → 2.3. A session mean would be 2.75.
        #expect(abs(reading.focusFigure - 2.3) < 0.0001)
        #expect(reading.adherenceDays == 10)
    }

    @Test("The same window reads the same way twice")
    func deterministic() {
        let observations = rows(days: 9, focusFeeling: 4, baseFeeling: 3)
        let first = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                           observations: observations, calendar: Self.calendar)
        let second = ExperimentOutcome.read(experiment(), hypothesis: hypothesis(),
                                            observations: observations.reversed(),
                                            calendar: Self.calendar)
        #expect(first == second)
    }

    // MARK: Settling

    @Test("Settling freezes the reading and only happens once the window has closed")
    func settling() {
        let observations = rows(days: 10, focusFeeling: 5, baseFeeling: 2)
        let open = experiment()

        // Mid-window: nothing is frozen, however good it looks.
        let midway = Self.calendar.date(byAdding: .day, value: 3, to: Self.start)!
        #expect(ExperimentOutcome.settle(open, hypothesis: hypothesis(),
                                         observations: observations, now: midway,
                                         calendar: Self.calendar).settlement == nil)

        let closed = open.endsAt(calendar: Self.calendar)
        let settled = ExperimentOutcome.settle(open, hypothesis: hypothesis(),
                                               observations: observations, now: closed,
                                               calendar: Self.calendar)
        let settlement = settled.settlement
        #expect(settlement?.verdict == .heldUp)
        #expect(settlement?.adherenceDays == 10)
        #expect(settled.phase == .settled)

        // Settling twice is a no-op: the figures belong to the moment the window
        // closed, and a second pass months later must not rewrite them.
        let again = ExperimentOutcome.settle(
            settled, hypothesis: hypothesis(),
            observations: observations + rows(days: 4, from: 10, focusFeeling: 1, baseFeeling: 5),
            now: Self.calendar.date(byAdding: .day, value: 60, to: closed)!,
            calendar: Self.calendar)
        #expect(again.settlement == settlement)
    }

    @Test("An abandoned experiment never settles")
    func abandonedNeverSettles() {
        var abandoned = experiment()
        abandoned.abandonedAt = Self.calendar.date(byAdding: .day, value: 2, to: Self.start)
        let settled = ExperimentOutcome.settle(
            abandoned, hypothesis: hypothesis(),
            observations: rows(days: 10, focusFeeling: 5, baseFeeling: 2),
            now: abandoned.endsAt(calendar: Self.calendar), calendar: Self.calendar)
        #expect(settled.settlement == nil)
        #expect(settled.phase == .abandoned)
    }
}
