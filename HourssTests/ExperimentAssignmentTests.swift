import Foundation
import Testing
@testable import Hourss

/// Phase 4: the days the app draws, and what a window read against them can say.
///
/// **What these are actually defending.** The draw is the only part of this feature
/// that moves the honest claim closer to cause, and it does that by being made
/// before any of the data exists. Every property below is therefore about a thing
/// not happening later: the days not being redrawn, the direction not being chosen
/// afterwards, the arms not being quietly narrowed to the days the person liked.
/// A bug in any of those would not produce a wrong number or a crash. It would
/// produce a slightly better-looking result and a claim the design no longer
/// supports, which is the failure this suite exists for.
@Suite("Experiment assignment")
struct ExperimentAssignmentTests {

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    /// Midnight UTC, so a day offset and a calendar day agree exactly.
    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private static let window = Experiment.randomisedWindowDays

    /// Every other day assigned, which is one shape the blocked draw can produce and
    /// is spelled out here rather than drawn: a test about the *measurement* that got
    /// its arms from the generator would fail for two unrelated reasons at once.
    private static let evens = Array(stride(from: 0, to: window, by: 2))

    private func assignment(_ offsets: [Int] = evens, seed: UInt64 = 1) -> Experiment.Assignment {
        Experiment.Assignment(seed: seed, dayOffsets: offsets)
    }

    private func experiment(assignment: Experiment.Assignment?,
                            predictsHigher: Bool = true,
                            windowDays: Int = window) -> Experiment {
        Experiment(
            hypothesisId: "time.morning.vs.rest.feeling",
            outcome: .feeling,
            startedAt: Self.start,
            windowDays: windowDays,
            focusLabel: "Morning",
            baselineLabel: "The rest of your day",
            predictsHigher: predictsHigher,
            assignment: assignment,
            premise: "Your mornings have read higher so far, across 8 days.",
            change: "Put one block in your morning on each of the days picked for you, "
                + "and not on the rest.",
            caveat: "Time of day travels with whatever you tend to schedule then."
        )
    }

    /// Splits on hour, as the registry's time buckets do. Before 11am is the change.
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

    /// A morning block — the change — on each of these days.
    private func change(on offsets: [Int], feeling: Double?) -> [EngineObservation] {
        offsets.map { row(dayOffset: $0, hour: 9, feeling: feeling) }
    }

    /// An afternoon session on each of these days: rated, and not the change.
    private func other(on offsets: [Int], feeling: Double) -> [EngineObservation] {
        offsets.map { row(dayOffset: $0, hour: 15, feeling: feeling) }
    }

    private func read(_ experiment: Experiment,
                      _ observations: [EngineObservation]) -> ExperimentOutcome.Reading {
        ExperimentOutcome.read(experiment, hypothesis: hypothesis(),
                               observations: observations, calendar: Self.calendar)
    }

    private static var odds: [Int] { (0..<window).filter { !evens.contains($0) } }

    // MARK: - The draw

    @Test("Half an even window is assigned, inside the window, sorted and distinct")
    func theShapeOfADraw() {
        for seed in UInt64(0)..<40 {
            let offsets = Experiment.Assignment.drawing(windowDays: Self.window, seed: seed)
            #expect(offsets.count == Self.window / 2)
            #expect(Set(offsets).count == offsets.count)
            #expect(offsets.allSatisfy { (0..<Self.window).contains($0) })
            // Already ascending out of the draw, which is what lets the stored list
            // be compared against a fresh one without sorting either of them.
            #expect(offsets == offsets.sorted())
        }
    }

    /// The property the scheme was chosen for.
    @Test("Exactly one day of each consecutive pair carries the change")
    func blockedWithinPairs() {
        // A uniform draw over half-sized subsets can return the first fortnight,
        // which is the before-and-after comparison this design exists to avoid — a
        // month with flu or a deadline in one half of it would land entirely in one
        // arm. One day per pair bounds the imbalance at every point in the window to
        // a single day, so a trend across the month reaches both arms almost equally.
        for seed in UInt64(0)..<40 {
            let drawn = Set(Experiment.Assignment.drawing(windowDays: Self.window, seed: seed))
            for pair in stride(from: 0, to: Self.window, by: 2) {
                let assigned = [pair, pair + 1].filter(drawn.contains)
                #expect(assigned.count == 1,
                        Comment(rawValue: "seed \(seed) assigned \(assigned) of pair \(pair)"))
            }
            // And therefore: never more than one day apart at any prefix.
            for prefix in 1...Self.window {
                let ahead = drawn.filter { $0 < prefix }.count
                #expect(abs(2 * ahead - prefix) <= 1)
            }
        }
    }

    @Test("An odd window draws its last day on its own")
    func oddWindow() {
        for seed in UInt64(0)..<20 {
            let drawn = Set(Experiment.Assignment.drawing(windowDays: 7, seed: seed))
            #expect(drawn.count == 3 || drawn.count == 4)
            for pair in [0, 2, 4] {
                #expect([pair, pair + 1].filter(drawn.contains).count == 1)
            }
        }
        // Over enough seeds the orphan goes both ways, so no day of the window is
        // special for a reason that has nothing to do with the person.
        let orphan = (UInt64(0)..<40).map {
            Experiment.Assignment.drawing(windowDays: 7, seed: $0).contains(6)
        }
        #expect(orphan.contains(true) && orphan.contains(false))
    }

    @Test("A degenerate window draws nothing rather than trapping")
    func degenerateWindow() {
        #expect(Experiment.Assignment.drawing(windowDays: 0, seed: 7).isEmpty)
        #expect(Experiment.Assignment.drawing(windowDays: -3, seed: 7).isEmpty)
        #expect(Experiment.Assignment.drawing(windowDays: 1, seed: 7).count <= 1)
    }

    @Test("The same seed draws the same days, and different seeds do not all agree")
    func determinism() {
        for seed in UInt64(0)..<20 {
            #expect(Experiment.Assignment.drawing(windowDays: Self.window, seed: seed)
                    == Experiment.Assignment.drawing(windowDays: Self.window, seed: seed))
        }
        let sets = Set((UInt64(0)..<50).map {
            Experiment.Assignment.drawing(windowDays: Self.window, seed: $0)
        })
        #expect(sets.count > 20, "the draw barely varies with its seed: \(sets.count) sets of 50")
    }

    /// The seed has to mean the same thing on the next launch, or the draw is not
    /// auditable — which is the whole reason it is written down.
    @Test("A seed is stable across calls and mixes in both of its inputs")
    func seeds() {
        let a = Experiment.Assignment.seed(hypothesisId: "time.morning.vs.rest.feeling",
                                           startedAt: Self.start)
        #expect(a == Experiment.Assignment.seed(hypothesisId: "time.morning.vs.rest.feeling",
                                                startedAt: Self.start))
        // A different question, same moment: a different draw. Without this every
        // person testing their mornings would get the identical pattern of days.
        #expect(a != Experiment.Assignment.seed(hypothesisId: "duration.long.vs.rest.feeling",
                                                startedAt: Self.start))
        // The same question a day later: a different draw. Without this the pattern
        // lines up with the weekday somebody happened to accept on, and weekday is
        // one of the things this app measures.
        #expect(a != Experiment.Assignment.seed(
            hypothesisId: "time.morning.vs.rest.feeling",
            startedAt: Self.calendar.date(byAdding: .day, value: 1, to: Self.start)!))
        // Inside the range every JSON number path represents exactly, so the seed
        // still reads as itself after a trip through the record file.
        #expect(a < (1 << 48))
    }

    @Test("A stored assignment can be re-derived from its own seed")
    func auditable() {
        // Nothing at runtime does this. A person asking why these days, or anybody
        // reading the record, can.
        for day in 0..<9 {
            let started = Self.calendar.date(byAdding: .day, value: day, to: Self.start)!
            let made = Experiment.Assignment.make(hypothesisId: "time.morning.vs.rest.feeling",
                                                  startedAt: started, windowDays: Self.window)
            #expect(made.dayOffsets
                    == Experiment.Assignment.drawing(windowDays: Self.window,
                                                     seed: made.seed).sorted())
            #expect(made.assignedCount == Self.window / 2)
        }
    }

    @Test("A day of the window is matched through the calendar, not through seconds")
    func dayOffsets() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        // Opens the day before the spring clock change, so a seconds-based offset
        // would be an hour out and every day after it would land in the wrong arm.
        let started = london.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 9))!
        let drawn = assignment([0, 2, 4])
        for offset in 0..<6 {
            let moment = london.date(byAdding: .day, value: offset, to: started)!
            #expect(drawn.dayOffset(of: moment, startedAt: started,
                                    windowDays: Self.window, calendar: london) == offset)
            #expect(drawn.isAssigned(moment, startedAt: started,
                                     windowDays: Self.window, calendar: london)
                    == offset.isMultiple(of: 2))
        }
        // Outside the window in either direction is nil rather than clamped.
        #expect(drawn.dayOffset(of: started.addingTimeInterval(-86_400),
                                startedAt: started, windowDays: Self.window,
                                calendar: london) == nil)
        #expect(drawn.dayOffset(of: london.date(byAdding: .day, value: Self.window,
                                                to: started)!,
                                startedAt: started, windowDays: Self.window,
                                calendar: london) == nil)
    }

    // MARK: - Measurement

    @Test("The arms are the drawn days, and a clear separation on them holds up")
    func heldUp() {
        let observations = change(on: Self.evens, feeling: 5) + other(on: Self.odds, feeling: 2)
        let reading = read(experiment(assignment: assignment()), observations)

        #expect(reading.verdict == .heldUp)
        #expect(reading.adherenceDays == Self.window / 2)
        #expect(reading.contaminationDays == 0)
        #expect(reading.contrastDays == Self.window / 2)
        #expect(reading.isRandomised)
        #expect(reading.focusFigure > reading.baselineFigure)
    }

    /// The test that says what randomisation bought, and it is the one that would
    /// still pass if the measurement quietly went back to being phase 1's.
    @Test("Every rated day stays in the arm it was assigned to, whatever happened on it")
    func intentionToTreat() {
        // Six of the fourteen assigned days carried the change and read 5. The other
        // eight assigned days read 1. None of the unassigned days carried the change
        // and they read 4 throughout.
        //
        // Comparing the days the change *happened* on against the rest — a
        // per-protocol reading — gives 5.0 against about 2.9 and holds up handsomely.
        // It is also worthless: the person chose those six days after the draw, so
        // whatever made them pick those days is back inside the result and the draw
        // bought nothing. Intention to treat keeps all fourteen assigned days in the
        // assigned arm, which reads 2.7 against 4.0 and does not hold up.
        let kept = Array(Self.evens.prefix(6))
        let missed = Array(Self.evens.dropFirst(6))
        let observations = change(on: kept, feeling: 5)
            + other(on: missed, feeling: 1)
            + other(on: Self.odds, feeling: 4)

        let reading = read(experiment(assignment: assignment()), observations)

        #expect(reading.adherenceDays == 6)
        #expect(reading.contaminationDays == 0)
        // 38 over 14. A per-protocol arm would be exactly 5.0, and this must not be.
        #expect(abs(reading.focusFigure - 38.0 / 14.0) < 0.0001)
        #expect(reading.verdict != .heldUp)
    }

    @Test("Adherence counts assigned days and contamination counts the rest")
    func complianceOnBothSides() {
        let onAssigned = Array(Self.evens.prefix(10))
        let onUnassigned = Array(Self.odds.prefix(3))
        let observations = change(on: onAssigned, feeling: 4)
            + change(on: onUnassigned, feeling: 4)
            + other(on: Self.odds, feeling: 3)

        let reading = read(experiment(assignment: assignment()), observations)
        #expect(reading.adherenceDays == 10)
        #expect(reading.contaminationDays == 3)
        #expect(reading.baselineDays == Self.window / 2)
        #expect(reading.contrastDays == Self.window / 2 - 3)
    }

    /// Contamination is not a footnote: it is the other way a drawn window fails.
    @Test("A change made on every day leaves nothing to read it against")
    func contaminationRemovesTheContrast() {
        // High adherence, perfect separation on the figures, and no contrast at all.
        let observations = change(on: Array(0..<Self.window), feeling: 5)
            + other(on: Array(0..<Self.window), feeling: 2)
        let reading = read(experiment(assignment: assignment()), observations)

        #expect(reading.adherenceDays == Self.window / 2)
        #expect(reading.contaminationDays == Self.window / 2)
        #expect(reading.contrastDays == 0)
        #expect(reading.verdict == .cannotTell, "a window with no contrast was read anyway")
        #expect(reading.comparison == nil)
    }

    @Test("Too little of the change on the assigned days cannot be read either")
    func lowAdherence() {
        let observations = change(on: Array(Self.evens.prefix(3)), feeling: 5)
            + other(on: Self.odds, feeling: 2)
        let reading = read(experiment(assignment: assignment()), observations)
        #expect(reading.verdict == .cannotTell)
        #expect(reading.adherenceDays == 3)
        #expect(reading.contaminationDays == 0)
    }

    /// Logged however the case needs: `unassignedRated` is how many of the unassigned
    /// days carry a rating at all, which is what lets the contrast floor be tested
    /// separately from the dilution rule below.
    private func reading(adherent: Int, contaminated: Int,
                         unassignedRated: Int = Self.window / 2) -> ExperimentOutcome.Reading {
        let observations = change(on: Array(Self.evens.prefix(adherent)), feeling: 4)
            + change(on: Array(Self.odds.prefix(contaminated)), feeling: 4)
            + other(on: Array(Self.odds.prefix(unassignedRated)), feeling: 2)
        return read(experiment(assignment: assignment()), observations)
    }

    @Test("Both floors bite at exactly the minimum, and the figures survive either way")
    func theBoundaries() {
        let floor = Experiment.minimumDays
        #expect(reading(adherent: floor, contaminated: 0).verdict != .cannotTell)
        #expect(reading(adherent: floor - 1, contaminated: 0).verdict == .cannotTell)

        // Contrast is the unassigned rated days that did not carry the change, and
        // the floor applied to it is the same six — not a contamination percentage,
        // which would be a constant invented for this phase alone.
        //
        // Tested here on a thinly logged arm rather than a contaminated one, which is
        // where the floor is now the condition that bites on its own: a month logged
        // across all fourteen unassigned days cannot get its contrast down to six
        // without the change having taken eight of them, and that trips the separation
        // rule first. Both conditions stay, because they answer different questions —
        // one asks whether there were enough days, the other whether the days were
        // still telling two things apart.
        #expect(reading(adherent: floor, contaminated: 0, unassignedRated: floor)
                    .contrastDays == floor)
        #expect(reading(adherent: floor, contaminated: 0, unassignedRated: floor)
                    .verdict != .cannotTell)
        #expect(reading(adherent: floor, contaminated: 0, unassignedRated: floor - 1)
                    .verdict == .cannotTell)
    }

    /// The failure the floors could not see, and the reason this gate exists.
    @Test("A diluted contrast is not read, and is not reported as no difference")
    func dilutionIsNotANullResult() {
        let floor = Experiment.minimumDays

        // The month this was added for. Six clean unassigned days beside eight
        // carrying the change: both floors clear — ten days of adherence, six days of
        // contrast — and the arm the change was withheld from is majority-treated. An
        // intention-to-treat comparison there is between two sets of days that differ
        // in the change on a minority of their days, so it is badly underpowered
        // toward the null, and the card reported "No difference you could act on" —
        // a statement about the change, when the only honest one available is about
        // the month.
        let diluted = reading(adherent: 10, contaminated: 8)
        #expect(diluted.adherenceDays == 10)
        #expect(diluted.contaminationDays == 8)
        #expect(diluted.contrastDays == floor)
        #expect(diluted.armsSeparated == false)
        #expect(diluted.verdict == .cannotTell)
        // Nothing was compared, so nothing is carried that a card could read a
        // difference off.
        #expect(diluted.comparison == nil)

        // Level arms: the change on six picked days and six unpicked ones. Both floors
        // clear again, the contrast floor has nothing to say about it, and the two arms
        // are alike in the one respect the draw made them differ in.
        let level = reading(adherent: floor, contaminated: floor)
        #expect(level.contrastDays == Self.window / 2 - floor)
        #expect(level.armsSeparated == false)
        #expect(level.verdict == .cannotTell)

        // And it is silent on every window the floors already admit. A rule that
        // failed a month over one stray Tuesday would be stricter than the thing it
        // protects, and the window at exactly the adherence floor with nothing
        // contaminated reads exactly as it did before this existed.
        #expect(reading(adherent: floor, contaminated: 0).armsSeparated == true)
        #expect(reading(adherent: floor, contaminated: 0).verdict != .cannotTell)
        #expect(reading(adherent: floor, contaminated: 1).verdict != .cannotTell)
        #expect(reading(adherent: 12, contaminated: 5).verdict != .cannotTell)
    }

    /// Why this could be added at all: there is no number in it.
    @Test("The separation rule is an ordering and not a threshold")
    func theRuleIntroducesNoConstant() {
        for adherence in 0...12 {
            for contamination in 0...12 {
                for contrast in 0...12 {
                    let once = Experiment.armsSeparated(
                        adherenceDays: adherence, contaminationDays: contamination,
                        contrastDays: contrast)
                    // A threshold anywhere in it would move when the counts are scaled.
                    let tenfold = Experiment.armsSeparated(
                        adherenceDays: adherence * 10, contaminationDays: contamination * 10,
                        contrastDays: contrast * 10)
                    #expect(once == tenfold,
                            Comment(rawValue: "scaling changed the answer at "
                                    + "\(adherence)/\(contamination)/\(contrast)"))
                }
            }
        }
        // The two orderings it claims to be, one per arm.
        #expect(Experiment.armsSeparated(adherenceDays: 10, contaminationDays: 8,
                                         contrastDays: 6) == false)
        #expect(Experiment.armsSeparated(adherenceDays: 6, contaminationDays: 6,
                                         contrastDays: 8) == false)
        #expect(Experiment.armsSeparated(adherenceDays: 7, contaminationDays: 6,
                                         contrastDays: 8) == true)
    }

    @Test("A drawn window the wrong way round did not hold up")
    func backwardsIsNotSuccess() {
        let observations = change(on: Self.evens, feeling: 2) + other(on: Self.odds, feeling: 5)
        #expect(read(experiment(assignment: assignment()), observations).verdict == .didNotHoldUp)
        // The identical month, predicted the other way, holds up — the direction is
        // fixed before the window opens for a drawn window exactly as for a chosen
        // one, and randomising the days licenses nothing about choosing it later.
        #expect(read(experiment(assignment: assignment(), predictsHigher: false), observations)
                    .verdict == .heldUp)
    }

    @Test("Sessions outside the window belong to neither arm")
    func windowIsRespected() {
        let late = (Self.window..<(Self.window + 10)).flatMap {
            [row(dayOffset: $0, hour: 9, feeling: 5), row(dayOffset: $0, hour: 15, feeling: 2)]
        }
        let reading = read(experiment(assignment: assignment()), late)
        #expect(reading.adherenceDays == 0)
        #expect(reading.baselineDays == 0)
        #expect(reading.verdict == .cannotTell)
    }

    @Test("An unrated day is in neither arm and is not adherence")
    func unratedDoesNotCount() {
        let observations = change(on: Self.evens, feeling: nil) + other(on: Self.odds, feeling: 3)
        let reading = read(experiment(assignment: assignment()), observations)
        #expect(reading.adherenceDays == 0)
        #expect(reading.verdict == .cannotTell)
    }

    @Test("The same drawn window reads the same way twice")
    func deterministic() {
        let observations = change(on: Self.evens, feeling: 4) + other(on: Self.odds, feeling: 3)
        let forwards = read(experiment(assignment: assignment()), observations)
        let backwards = read(experiment(assignment: assignment()), observations.reversed())
        #expect(forwards == backwards)
    }

    @Test("A hypothesis that has left the registry cannot be read, and says nothing else")
    func missingHypothesis() {
        let reading = ExperimentOutcome.read(
            experiment(assignment: assignment()), hypothesis: nil,
            observations: change(on: Self.evens, feeling: 5), calendar: Self.calendar)
        #expect(reading.verdict == .cannotTell)
        // Nil rather than zero: with no predicate there is nothing to say about
        // contamination, and zero would read as somebody having kept off every
        // unassigned day.
        #expect(reading.contaminationDays == nil)
    }

    /// Phases 1 to 3, unchanged by any of this.
    @Test("Without an assignment the arms are the hypothesis's own groups again")
    func theChosenKindStillReadsItsOwnWay() {
        // Mornings on the even days only, afternoons everywhere. Read as a drawn
        // window that is what the assigned arm is; read as a chosen one the mornings
        // are the focus group wherever they fall, and the afternoons on the even days
        // are baseline rather than being in the focus arm.
        let observations = change(on: Self.evens, feeling: 5)
            + other(on: Array(0..<Self.window), feeling: 2)

        let chosen = read(experiment(assignment: nil, windowDays: Experiment.defaultWindowDays),
                          observations)
        #expect(chosen.contaminationDays == nil)
        #expect(!chosen.isRandomised)
        #expect(chosen.contrastDays == nil)
        // No arms to order, so no answer rather than a default one — the same reason
        // `contaminationDays` is nil here rather than zero.
        #expect(chosen.armsSeparated == nil)
        // Seven morning days inside a fortnight, and fourteen afternoon days.
        #expect(chosen.adherenceDays == 7)
        #expect(chosen.baselineDays == Experiment.defaultWindowDays)
        #expect(chosen.verdict == .heldUp)

        let drawn = read(experiment(assignment: assignment()), observations)
        #expect(drawn.isRandomised)
        // Every even day carries both a 5 and a 2 now, so the arms barely separate —
        // the same record, a different question, and a different answer.
        #expect(drawn.baselineDays == Self.window / 2)
    }

    // MARK: - Settling

    @Test("Settling freezes the contamination count with the rest of the figures")
    func settling() {
        let observations = change(on: Self.evens, feeling: 5)
            + change(on: Array(Self.odds.prefix(2)), feeling: 5)
            + other(on: Self.odds, feeling: 2)
        let open = experiment(assignment: assignment())
        let closed = open.endsAt(calendar: Self.calendar)

        let settled = ExperimentOutcome.settle(open, hypothesis: hypothesis(),
                                               observations: observations, now: closed,
                                               calendar: Self.calendar)
        let settlement = settled.settlement
        #expect(settlement?.contaminationDays == 2)
        #expect(settlement?.contrastDays == Self.window / 2 - 2)
        #expect(settlement?.verdict == .heldUp)
        // The days are not touched by settling. A settled experiment whose assignment
        // had moved would be a result about a month that never happened.
        #expect(settled.assignment == open.assignment)

        // And a month later, with the baseline window slid along, the figures are
        // exactly the ones that were frozen.
        let again = ExperimentOutcome.settle(
            settled, hypothesis: hypothesis(),
            observations: observations + change(on: Self.odds, feeling: 1),
            now: Self.calendar.date(byAdding: .day, value: 60, to: closed)!,
            calendar: Self.calendar)
        #expect(again.settlement == settlement)
    }
}

/// What a drawn window says, and the one sentence this phase added to what the app
/// is allowed to claim.
@Suite("Experiment assignment copy")
struct ExperimentAssignmentCopyTests {

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private func experiment(assignment: Experiment.Assignment?) -> Experiment {
        Experiment(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: .feeling,
            startedAt: Self.start, windowDays: Experiment.randomisedWindowDays,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            assignment: assignment,
            premise: "p",
            change: "Put one block in your morning on each of the days picked for you, "
                + "and not on the rest.",
            caveat: "Time of day travels with whatever you tend to schedule then.")
    }

    private func settlement(_ verdict: Experiment.Verdict,
                            adherence: Int = 12, baseline: Int = 14,
                            contamination: Int? = 1) -> Experiment.Settlement {
        Experiment.Settlement(
            verdict: verdict, adherenceDays: adherence, baselineDays: baseline,
            contaminationDays: contamination,
            focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
            intervalLow: 0.1, intervalHigh: 0.7, settledAt: Self.start)
    }

    private var drawn: Experiment {
        experiment(assignment: Experiment.Assignment.make(
            hypothesisId: "time.morning.vs.rest.feeling", startedAt: Self.start,
            windowDays: Experiment.randomisedWindowDays))
    }

    // MARK: The ask

    @Test("The change names the days and asks for the rest to be left alone")
    func theChange() throws {
        for type in ExperimentDesign.randomisableTypes {
            let change = try #require(
                ExperimentCopy.randomisedChange(type: type, focusLabel: "Morning"),
                "a randomisable type has no drawn-window change: \(type)")
            #expect(change.contains("picked for you"))
            // The half that makes the window readable. Without it somebody does the
            // thing on the days that suit them and there is no contrast left.
            #expect(change.contains("not on the rest"))
            // A drawn window is four weeks. Any copy of it calling itself a fortnight
            // is describing a different commitment from the one being made.
            #expect(!change.lowercased().contains("fortnight"))
        }
        // The families whose focus side the app cannot assign. A drawn day is not a
        // day of longer sleep and cannot be made into a day off.
        for type in [InsightType.sleepContext, .bodyContext, .workdayContrast,
                     .drainingTimeWindow, .activityDrain, .performanceFeelingSplit,
                     .fragmentation, .emergingChange] {
            #expect(ExperimentCopy.randomisedChange(type: type, focusLabel: "Morning") == nil,
                    Comment(rawValue: "\(type) was offered a drawn window"))
        }
    }

    @Test("The ask says what is wanted and what it buys, and promises nothing")
    func theAsk() {
        let ask = ExperimentCopy.randomisedAsk(windowDays: 28, assignedDays: 14)
        #expect(ask.contains("14"))
        #expect(ask.contains("28"))
        // The cost, said out loud rather than discovered on day three.
        #expect(ask.contains("would rather not"))
        // The return, at exactly the strength the design supports. "Did not pick"
        // since the ask was shortened on the owner's reading — same clause, same
        // claim, one verb, and it is now the verb the first sentence uses too.
        #expect(ask.contains("did not pick"))
        #expect(!ask.lowercased().contains("fortnight"))
        for overclaim in ["will", "proves", "shows that", "guarantee", "works"] {
            #expect(!ask.lowercased().contains(overclaim),
                    Comment(rawValue: "the ask promised '\(overclaim)': \(ask)"))
        }
    }

    @Test("A drawn window's caveat keeps the hypothesis's own and adds its limit")
    func theCaveat() {
        let base = "Time of day travels with whatever you tend to schedule then."
        let caveat = ExperimentCopy.randomisedCaveat(base)
        // Kept, not replaced: whatever travels with a morning block still travels
        // with it on a day the app picked.
        #expect(caveat.hasPrefix(base))
        #expect(caveat.contains("One person, four weeks"))
    }

    // MARK: The days

    @Test("The day list is every assigned day and nothing else")
    func theDayList() throws {
        let window = drawn
        let assignment = try #require(window.assignment)
        let line = try #require(ExperimentCopy.assignedDays(for: window,
                                                            calendar: Self.calendar))
        #expect(line.hasPrefix("Your days: "))
        // One entry per assigned day. A list that quietly dropped one would be an
        // instruction nobody could follow and a day nobody could be held to.
        #expect(line.components(separatedBy: ",").count == assignment.assignedCount)
        // Chosen windows have no list, and nil says so rather than an empty string.
        #expect(ExperimentCopy.assignedDays(for: experiment(assignment: nil),
                                            calendar: Self.calendar) == nil)
    }

    /// Without this a drawn window is an instruction nobody can follow.
    @Test("Each day of the window says whether it carries the change")
    func todayLines() throws {
        let window = drawn
        let assignment = try #require(window.assignment)
        for offset in 0..<Experiment.randomisedWindowDays {
            let day = Self.calendar.date(byAdding: .day, value: offset, to: Self.start)!
            let line = try #require(ExperimentCopy.today(for: window, on: day,
                                                         calendar: Self.calendar))
            #expect(line == (assignment.isAssigned(dayOffset: offset)
                             ? "Today is one of your days."
                             : "Today is not one of your days."))
        }
        // Nothing to say before it opens, after it closes, or about a chosen window.
        #expect(ExperimentCopy.today(for: window,
                                     on: Self.start.addingTimeInterval(-86_400),
                                     calendar: Self.calendar) == nil)
        #expect(ExperimentCopy.today(
            for: window,
            on: Self.calendar.date(byAdding: .day, value: Experiment.randomisedWindowDays,
                                   to: Self.start)!,
            calendar: Self.calendar) == nil)
        #expect(ExperimentCopy.today(for: experiment(assignment: nil), on: Self.start,
                                     calendar: Self.calendar) == nil)
    }

    // MARK: The result

    /// The sentence this whole phase was built to be allowed to write.
    @Test("A drawn window that held up says the days were chosen for them")
    func heldUpNamesTheDraw() {
        let sentence = ExperimentCopy.result(for: drawn, settlement: settlement(.heldUp))
        #expect(sentence.contains("It held up when the days were chosen for you."))
        #expect(sentence.contains("4.2"))
        #expect(sentence.contains("3.4"))
        // Still not a cause, in any of the forms that would be the easy mistake here.
        for forbidden in ["causes", "caused", "because", "why", "proves"] {
            #expect(!sentence.lowercased().contains(forbidden),
                    Comment(rawValue: "a drawn result claimed '\(forbidden)': \(sentence)"))
        }
        // And a chosen window says no such thing, because it cannot.
        let chosen = ExperimentCopy.result(for: experiment(assignment: nil),
                                           settlement: settlement(.heldUp, contamination: nil))
        #expect(!chosen.contains("chosen for you"))
    }

    @Test("Neither arm is labelled with the group, because neither arm is the group")
    func armsAreNotLabelledAsGroups() {
        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp] {
            let sentence = ExperimentCopy.result(for: drawn, settlement: settlement(verdict))
            // The assigned arm holds every rated session on a picked day, including
            // the days the change did not happen on. Calling that figure "Morning"
            // would attach a label the number does not carry.
            #expect(!sentence.contains("Morning"))
            #expect(sentence.contains("Your picked days"))
        }
    }

    @Test("A null result reads as plainly as a positive one")
    func didNotHoldUp() {
        let sentence = ExperimentCopy.result(for: drawn, settlement: settlement(.didNotHoldUp))
        #expect(sentence.contains("No difference you could act on."))
        #expect(sentence.contains("4.2"))
    }

    @Test("Contamination is reported as a count of what happened, not as a reproach")
    func contaminationSentence() {
        let sentence = ExperimentCopy.result(
            for: drawn,
            settlement: settlement(.cannotTell, adherence: 12, baseline: 14, contamination: 11))
        // Both numbers and the floor, so "not enough" never arrives without saying
        // what would have been.
        #expect(sentence.contains("11"))
        #expect(sentence.contains("14"))
        #expect(sentence.contains("3 to read against"))
        #expect(sentence.contains("\(Experiment.minimumDays) would have been enough"))
        for blame in ["you should", "failed", "unfortunately", "did not follow", "broke"] {
            #expect(!sentence.lowercased().contains(blame),
                    Comment(rawValue: "the contamination sentence blamed somebody: \(sentence)"))
        }

        // Low adherence still reads as low adherence rather than as contamination:
        // the change not happening and the change happening everywhere are different
        // facts about the month and must not share a sentence.
        let thin = ExperimentCopy.result(
            for: drawn,
            settlement: settlement(.cannotTell, adherence: 3, baseline: 14, contamination: 11))
        #expect(thin.contains("There were 3."))

        // And a drawn window with nothing logged on its unassigned days is a
        // shortfall, not contamination — there was no change to contaminate with.
        let empty = ExperimentCopy.result(
            for: drawn,
            settlement: settlement(.cannotTell, adherence: 8, baseline: 2, contamination: 0))
        #expect(empty.contains("without it would have been enough"))
        #expect(empty.contains("There were 2."))
    }

    /// The one place this feature's copy could overstate, and what it says instead.
    ///
    /// **These two sentences are the whole point of the gate.** A window that could
    /// not separate its two sets of days and a window that separated them and found
    /// nothing are different statements, and only the second one is about the change.
    /// A reader who could mistake one for the other would act on a null result the
    /// month never produced.
    @Test("A month that could not separate its days does not read as no difference")
    func dilutionDoesNotReadAsANull() {
        let diluted = ExperimentCopy.result(
            for: drawn,
            settlement: settlement(.cannotTell, adherence: 10, baseline: 14, contamination: 8))
        // Both counts, so "could not be read" never arrives without saying what the
        // month was made of.
        #expect(diluted.contains("10 of the days it was picked for"))
        #expect(diluted.contains("8 of the 14 days it was not"))
        #expect(diluted.contains("too alike to read one against the other"))
        // And none of the verdict's own words, in either direction.
        #expect(!diluted.contains("No difference"))
        #expect(!diluted.contains("held up"))
        // Counted, never reproached. Nobody did anything wrong by putting a block in
        // their morning on a Tuesday.
        for blame in ["you should", "failed", "unfortunately", "did not follow", "broke",
                      "too often", "should have"] {
            #expect(!diluted.lowercased().contains(blame),
                    Comment(rawValue: "the dilution sentence blamed somebody: \(diluted)"))
        }

        // The result it is not. A window whose arms stayed apart and found nothing says
        // so plainly, and says nothing about being unable to tell.
        let null = ExperimentCopy.result(
            for: drawn, settlement: settlement(.didNotHoldUp, contamination: 0))
        #expect(null.contains("No difference you could act on."))
        #expect(!null.contains("too alike"))
        #expect(!null.contains("also happened on"))
        // The headings differ too, which is what a reader who looks once sees.
        #expect(ExperimentCopy.verdictTitle(.cannotTell) != ExperimentCopy.verdictTitle(.didNotHoldUp))
    }

    /// Dilution that is not enough to stop the reading is still part of the reading.
    @Test("A readable result counts the days the change happened on anyway")
    func dilutionIsReportedBesideTheVerdict() {
        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp] {
            let sentence = ExperimentCopy.result(
                for: drawn,
                settlement: settlement(verdict, adherence: 12, baseline: 14, contamination: 4))
            #expect(sentence.contains(
                "The change also happened on 4 of the 14 days it was not picked for"))
            #expect(sentence.contains("closer together than the draw asked for"))
            // The verdict still leads. The clause is what the window managed, not a
            // hedge folded into what it measured.
            #expect(sentence.hasPrefix("Your picked days settled at"))
        }
        // Nothing added when nothing happened on an unpicked day.
        #expect(!ExperimentCopy.result(for: drawn, settlement: settlement(.heldUp, contamination: 0))
                    .contains("also happened"))
        // And a chosen window has no unasked days to count, so it says nothing at all.
        #expect(!ExperimentCopy.result(for: experiment(assignment: nil),
                                       settlement: settlement(.heldUp, contamination: nil))
                    .contains("also happened"))
    }

    /// The sweep, extended to everything this phase can put on a screen.
    ///
    /// `instruction` is excluded and only `instruction`, as everywhere else in this
    /// feature: a drawn window's whole content is an instruction about particular
    /// days. Causal, clinical and population offences fail here exactly as they do in
    /// narration, and the date formatter's own output is swept too — a weekday name
    /// is the one string here the app does not write.
    @Test("No drawn-window copy makes a causal, clinical or population claim")
    func copyPassesTheGuard() {
        var strings: [String] = [
            ExperimentCopy.randomiseTitle,
            ExperimentCopy.randomisedAsk(windowDays: Experiment.randomisedWindowDays,
                                         assignedDays: Experiment.randomisedWindowDays / 2),
            ExperimentCopy.randomisedCaveat(
                "Time of day travels with whatever you tend to schedule then."),
        ]
        strings += ExperimentCopy.controlTitles
        // The one sentence this phase had left inside a view body. Swept here now that
        // it is a string the sweep can see.
        strings.append(ExperimentCopy.testedPrefix)
        for label in ["Morning", "Deep work", "30 to 89 minutes"] {
            for type in ExperimentDesign.randomisableTypes {
                if let change = ExperimentCopy.randomisedChange(type: type, focusLabel: label) {
                    strings.append(change)
                }
            }
        }
        let window = drawn
        strings.append(ExperimentCopy.assignedDays(for: window,
                                                   calendar: Self.calendar) ?? "")
        for offset in 0..<Experiment.randomisedWindowDays {
            let day = Self.calendar.date(byAdding: .day, value: offset, to: Self.start)!
            strings.append(ExperimentCopy.today(for: window, on: day,
                                                calendar: Self.calendar) ?? "")
        }
        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp, .cannotTell] {
            // The last two are the diluted shapes: one the gate stops (ten adherent
            // days against eight contaminated ones) and one it admits and reports in
            // the sentence instead.
            for (adherence, baseline, contamination) in
                [(12, 14, 0), (12, 14, 11), (3, 14, 2), (8, 2, 0), (0, 0, 0), (14, 14, 14),
                 (10, 14, 8), (12, 14, 4)] {
                strings.append(ExperimentCopy.result(
                    for: window,
                    settlement: settlement(verdict, adherence: adherence,
                                           baseline: baseline, contamination: contamination)))
            }
        }

        for text in strings {
            let offence = NarrationGuard.offence(
                in: text, allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }
}
