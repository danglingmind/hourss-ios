import Testing
import Foundation
@testable import Hourss

/// A fortnight proposed from somebody's own heart-rate curve.
///
/// Two things are being tested and only one of them is logic. The other is the line
/// the copy holds: a reading, never a verdict. A premise that said "your late
/// mornings are your most efficient" would be a medical opinion built out of wrist
/// data, and the framing is the whole safeguard — so it is the thing with the most
/// tests on it rather than the least.
@Suite("Vitals-led proposals")
struct ExperimentVitalsTests {

    // MARK: - Fixtures

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)
    private static let calendar = Calendar.current

    private func place(_ band: TimeBucket, _ difference: Double,
                       workday: Bool = true, hour: Int? = nil) -> Physiology.DayShape.Place {
        Physiology.DayShape.Place(band: band, isWorkday: workday,
                                  hour: hour, difference: difference)
    }

    /// Places are handed in furthest-first, as `MovementCurve.dayShape` produces them.
    private func shape(_ places: [Physiology.DayShape.Place]) -> Physiology.DayShape {
        Physiology.DayShape(places: places.sorted { $0.magnitude > $1.magnitude })
    }

    /// A row in the band and day type it claims to be in, which is all this source
    /// reads an observation for.
    private func row(_ band: TimeBucket, workday: Bool) -> EngineObservation {
        // Walk forward to a day of the kind asked for, so the row's own `isWorkday`
        // and its timestamp agree. Nothing here reads the timestamp, but a row whose
        // two halves disagree is a fixture that will mislead whoever reuses it.
        let hour: Int = switch band {
        case .morning: 9
        case .midday: 12
        case .afternoon: 15
        case .evening: 20
        }
        var day = Self.start
        let workdays: Set<Int> = [2, 3, 4, 5, 6]
        for _ in 0..<7 {
            if workdays.contains(Self.calendar.component(.weekday, from: day)) == workday { break }
            day = Self.calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        let startAt = Self.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return EngineObservation(
            sessionId: UUID(),
            day: Self.calendar.startOfDay(for: startAt),
            startAt: startAt,
            durationMinutes: 60,
            activityName: "Deep work",
            activityCategory: "work",
            timeBucket: band,
            durationBucket: .medium,
            isWorkday: workday,
            feeling: 4,
            performance: nil,
            dayHealth: [:],
            heartRateResidual: nil,
            cadence: nil
        )
    }

    /// Somebody who logs in every corner of their week, so occupancy never decides
    /// anything in the tests that are not about occupancy.
    private var everywhere: [EngineObservation] {
        TimeBucket.allCases.flatMap { [row($0, workday: true), row($0, workday: false)] }
    }

    private func calibrated(_ higherIsBetter: Bool) -> OutcomeDirection {
        OutcomeDirection(residualHigherIsBetter: higherIsBetter)
    }

    // MARK: - The chain

    /// The whole offer, end to end.
    @Test("A band that sits apart becomes a fortnight somebody can accept")
    func theChainCloses() throws {
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus],
            shape: shape([place(.morning, -9, hour: 10)]),
            observations: everywhere).first)

        // Settled against the registry's own question about that band, so the
        // fortnight can be read two weeks later.
        #expect(proposal.hypothesisId == "time.morning.vs.rest.feeling")
        #expect(proposal.type == .bestTimeWindow)
        #expect(proposal.priority == .focus)

        // Nothing has been measured about how that band's sessions read, which is
        // what the fortnight is for.
        #expect(proposal.standing == .starter)
        #expect(proposal.evidenceDays == 0)
        #expect(proposal.figure == 0)
    }

    /// The id is the key `ExperimentOutcome` looks the predicate up by a fortnight
    /// later, so it is taken from the registry rather than typed. Pinned here, because
    /// an id drifting by one character would settle every one of these as "cannot
    /// tell", silently, in two weeks, on somebody else's phone.
    @Test("Every band's id exists in the registry")
    func idsMatchTheRegistry() throws {
        let registered = Set(HypothesisRegistry.hypotheses(for: []).map(\.id))
        for band in TimeBucket.allCases {
            let hypothesis = try #require(ExperimentVitals.timeWindow(band))
            #expect(registered.contains(hypothesis.id))
            #expect(hypothesis.focusLabel == band.label)
        }
    }

    // MARK: - Direction

    /// With a confirmed calibration, which end of the curve is pointed at.
    ///
    /// The calibration never reaches a screen — it chooses which true thing is
    /// offered, exactly as a population prior does in `Surprise`. What it changes is
    /// the band, and nothing else.
    @Test("A calibration that favours a lower heart rate points at the lower end")
    func lowerEnd() throws {
        let both = shape([place(.morning, -9), place(.afternoon, 12)])
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: both, direction: calibrated(false),
            observations: everywhere).first)
        #expect(proposal.focusLabel == TimeBucket.morning.label,
                "a calibration favouring the low end was offered the high one")
        #expect(proposal.premise.contains("sits lower"))
    }

    @Test("A calibration that favours a raised heart rate points at the higher end")
    func higherEnd() throws {
        let both = shape([place(.morning, -14), place(.afternoon, 8)])
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: both, direction: calibrated(true),
            observations: everywhere).first)
        // Even though the morning is further from the rest of the day, it is the
        // wrong end for this person.
        #expect(proposal.focusLabel == TimeBucket.afternoon.label)
        #expect(proposal.premise.contains("sits higher"))
    }

    /// A calibration that only has one end available offers nothing rather than the
    /// other one. The direction is the only thing licensing a choice between the two,
    /// and spending it to pick the end it refused would be worse than staying quiet.
    @Test("A calibration with nothing at its end offers nothing")
    func wrongEndOnly() {
        let low = shape([place(.morning, -9)])
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: low, direction: calibrated(true),
            observations: everywhere).isEmpty)
    }

    /// Without a calibration there is no direction, so the furthest place is offered
    /// and the copy says only what was measured.
    @Test("Without a calibration the furthest place is offered either way")
    func uncalibrated() throws {
        let both = shape([place(.morning, -14), place(.afternoon, 8)])
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: both, observations: everywhere).first)
        #expect(proposal.focusLabel == TimeBucket.morning.label)

        // And the sentence is the same sentence a calibrated proposal would carry.
        // The calibration buys which band, never a word on the card — see
        // `ExperimentCopy.vitalsPremise`.
        let withOne = ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -14)]),
            direction: calibrated(false), observations: everywhere).first
        #expect(withOne?.premise == proposal.premise)
        #expect(withOne?.change == proposal.change)
    }

    // MARK: - The line the copy holds

    /// The premise states a measurement and then says outright that the thing being
    /// proposed is not known. Neither half may read as a verdict about the person.
    @Test("The premise is a reading, and says in the same breath what is not known")
    func thePremiseIsAReading() throws {
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9, hour: 10)]),
            direction: calibrated(false), observations: everywhere).first)

        // What was measured.
        #expect(proposal.premise.contains("your heart rate sits lower"))
        #expect(proposal.premise.contains("around 10am"))
        #expect(proposal.premise.contains("On your workdays"))

        // And what has not been.
        #expect(proposal.premise.contains("Nothing you have logged says yet"))

        // Never that it is better. Every one of these turns a cardiac reading into a
        // claim about performance, which is a medical opinion the app does not have
        // and will not get from sixty days of wrist data.
        let text = proposal.premise.lowercased()
        for verdict in ["best", "optimal", "ideal", "most efficient", "peak", "at its best",
                        "should", "better", "worse", "productive", "sharpest",
                        "find out whether", "will "] {
            #expect(!text.contains(verdict),
                    Comment(rawValue: "the premise made a claim: '\(verdict)' in \(proposal.premise)"))
        }
    }

    /// No superlative, because this function is handed one place rather than the day
    /// and a caller choosing a place for its own reasons would make a superlative
    /// false without changing a word of the sentence.
    @Test("The reading compares, and never crowns")
    func noSuperlative() {
        for place in [place(.morning, -9), place(.afternoon, 9, workday: false),
                      place(.evening, -7, hour: 21)] {
            let reading = ExperimentCopy.vitalsReading(place).lowercased()
            #expect(!reading.contains("lowest"))
            #expect(!reading.contains("highest"))
            #expect(reading.contains("elsewhere in your day"))
        }
    }

    /// Hours are written the way somebody says them, and the two ends of the clock
    /// are words rather than numbers that read as nonsense.
    @Test("An hour reads as a time of day")
    func hoursReadAsTimes() {
        #expect(ExperimentCopy.clockHour(0) == "midnight")
        #expect(ExperimentCopy.clockHour(7) == "7am")
        #expect(ExperimentCopy.clockHour(11) == "11am")
        #expect(ExperimentCopy.clockHour(12) == "midday")
        #expect(ExperimentCopy.clockHour(13) == "1pm")
        #expect(ExperimentCopy.clockHour(23) == "11pm")
    }

    /// Every string this source can produce, swept for the bans that still apply.
    ///
    /// `instruction` is excluded and only `instruction`, as everywhere else in this
    /// feature: a proposal's whole job is to ask for a change, and `NarrationGuard`'s
    /// own comment on that list says the free tier proposes a test. Causal, clinical
    /// and population offences are failures here exactly as they are in narration —
    /// and the clinical list is the one that matters most to this source, because it
    /// is the only one in the app whose premise quotes a heart rate.
    @Test("No vitals copy makes a causal, clinical or population claim")
    func copyPassesTheGuard() {
        var strings: [String] = []
        for band in TimeBucket.allCases {
            for workday in [true, false] {
                for hour in [nil, 0, 7, 12, 15, 23] as [Int?] {
                    let place = Physiology.DayShape.Place(
                        band: band, isWorkday: workday, hour: hour, difference: -9)
                    strings.append(ExperimentCopy.vitalsReading(place))
                    strings.append(ExperimentCopy.vitalsPremise(place))
                    strings.append(ExperimentCopy.vitalsChange(place))
                    let raised = Physiology.DayShape.Place(
                        band: band, isWorkday: workday, hour: hour, difference: 9)
                    strings.append(ExperimentCopy.vitalsPremise(raised))
                }
                if let hypothesis = ExperimentVitals.timeWindow(band) {
                    strings.append(ExperimentCopy.vitalsCaveat(hypothesis.caveat))
                }
            }
        }

        for text in strings {
            let figures = NarrationGuard.figures(in: text)
            switch NarrationGuard.offence(in: text, allowingFigures: figures) {
            case .none, .instruction:
                continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }

    /// The limit travels with the claim, and both limits do: the fortnight tests a
    /// band and the premise quotes a heart rate.
    @Test("The caveat carries the registry's own wording for both halves")
    func theCaveatIsBorrowed() throws {
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9)]),
            observations: everywhere).first)
        let hypothesis = try #require(ExperimentVitals.timeWindow(.morning))
        #expect(proposal.caveat.contains(hypothesis.caveat))
        #expect(proposal.caveat.contains(HypothesisRegistry.residualCaveat))
    }

    // MARK: - Workdays

    /// The mistake this exists to avoid by name: proposing ten in the morning to
    /// somebody who is at work at ten on five days in seven.
    ///
    /// The watch records a workday morning whether or not that morning is the person's
    /// to spend, so the vitals alone cannot tell the two apart. Somebody who logs only
    /// on their days off has said something about their weekday mornings that the
    /// heart-rate feed cannot, so where that evidence exists it orders the list.
    ///
    /// Both places here sit at the same end of the curve and the workday one is
    /// *further* from the rest of the day, so the ordering is the only thing that can
    /// decide between them.
    @Test("Where the record says which days are theirs, it orders the offer")
    func workdaysAreRespected() throws {
        let both = shape([place(.evening, -12, workday: true),
                          place(.morning, -8, workday: false)])

        let daysOffOnly = [row(.morning, workday: false), row(.afternoon, workday: false)]
        let offered = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: both, direction: calibrated(false),
            observations: daysOffOnly).first)
        #expect(offered.focusLabel == TimeBucket.morning.label,
                "a workday evening was put ahead of a days-off morning to somebody who logs nothing on workdays")
        #expect(offered.change.contains("on your days off"))

        // Somebody who logs in both kinds of day gets the place furthest from the
        // rest of their day, which is what the ordering says when the record has
        // nothing to add.
        let everyKindOfDay = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: both, direction: calibrated(false),
            observations: everywhere).first)
        #expect(everyKindOfDay.focusLabel == TimeBucket.evening.label)
    }

    /// **A preference and not a gate**, and the distinction is the whole first-day
    /// case. Read as a gate this refused everybody with an empty record — somebody
    /// with sixty days of wrist data and nothing logged, who is the reason this source
    /// reads vitals rather than ratings at all.
    @Test("An empty record does not silence the offer")
    func anEmptyRecordStillGetsAnOffer() throws {
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.evening, -11, hour: 22)]),
            direction: calibrated(false), observations: []).first,
            "somebody on their first day was offered nothing")
        #expect(proposal.hypothesisId == "time.evening.vs.rest.feeling")
        // And it still says which days it means, which is the part that was free.
        #expect(proposal.change.contains("on most workdays"))
    }

    /// Filter 2 of `ExperimentDesign`, a layer early. Adherence counts days gained on
    /// the focus side, so asking somebody who logs every session at nine in the
    /// morning for one more morning session makes the heavy side heavier and leaves the
    /// comparison exactly as impossible as it was — a fortnight that could only come
    /// back "cannot tell".
    @Test("The band that already holds most of somebody's day is refused")
    func theHeavySideIsRefused() throws {
        let morning = shape([place(.morning, -11, workday: true)])

        let fixedRoutine = (0..<10).map { _ in row(.morning, workday: true) }
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: morning, observations: fixedRoutine).isEmpty,
            "somebody who logs nothing but mornings was asked for another morning")

        // The same shape to somebody whose day is split between two bands: no band
        // carries a majority, so there is a contrast a fortnight could sharpen.
        let split = fixedRoutine + (0..<10).map { _ in row(.afternoon, workday: true) }
        let offered = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: morning, observations: split).first)
        #expect(offered.focusLabel == TimeBucket.morning.label)
    }

    /// Per day type, because a fixed weekday routine says nothing about somebody's
    /// Saturdays.
    @Test("A majority on workdays does not refuse the same band on days off")
    func dominanceIsPerDayType() throws {
        let daysOffMorning = shape([place(.morning, -11, workday: false)])
        let weekdayMornings = (0..<10).map { _ in row(.morning, workday: true) }
            + [row(.afternoon, workday: false), row(.evening, workday: false)]
        let offered = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: daysOffMorning, observations: weekdayMornings).first)
        #expect(offered.change.contains("on your days off"))
    }

    /// Which days are meant is said in the change as well as the premise, because
    /// that is the difference between a request somebody can act on and one they
    /// cannot.
    @Test("The change names the days it means")
    func theChangeNamesTheDays() throws {
        let onWorkdays = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9, workday: true)]),
            observations: everywhere).first)
        #expect(onWorkdays.change.contains("on most workdays"))
        #expect(onWorkdays.premise.contains("On your workdays"))

        let onDaysOff = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9, workday: false)]),
            observations: everywhere).first)
        #expect(onDaysOff.change.contains("on your days off"))
        #expect(onDaysOff.premise.contains("On your days off"))
    }

    /// The change asks for the band, which is what the fortnight measures. The hour
    /// is a better reading and stays in the premise: asking for ten o'clock while
    /// adherence counts every morning would mean somebody logging at eleven cleared
    /// the test without doing the thing.
    @Test("The change asks for exactly what is measured")
    func theChangeMatchesTheMeasurement() throws {
        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9, hour: 10)]),
            observations: everywhere).first)
        #expect(proposal.change.contains("morning hours"))
        #expect(!proposal.change.contains("10am"))
        #expect(proposal.premise.contains("10am"))
    }

    // MARK: - Nothing to offer

    @Test("No shape, no offer")
    func nothingWithoutAShape() {
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: nil, observations: everywhere).isEmpty)
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: Physiology.DayShape(places: []),
            observations: everywhere).isEmpty)
    }

    /// Nothing was said about what matters, so there is no area to work on and this
    /// layer picks none on somebody's behalf. The same guard every other source opens
    /// with.
    @Test("No priorities, no offer")
    func nothingWithoutPriorities() {
        #expect(ExperimentVitals.proposals(
            for: [], shape: shape([place(.morning, -9)]), observations: everywhere).isEmpty)
    }

    /// Which priorities a time-of-day test can serve is `Priority.insightTypes`'
    /// decision, and today only one of them lists `bestTimeWindow`.
    @Test("Only a priority a time window can serve gets one")
    func onlyPrioritiesThatFit() throws {
        let shape = shape([place(.morning, -9)])
        #expect(ExperimentVitals.proposals(
            for: [.sleep, .movement, .calm, .balance], shape: shape,
            observations: everywhere).isEmpty)

        // And where it does fit, the rank is the rank in what they actually ranked
        // rather than the position in the list that came back.
        let third = try #require(ExperimentVitals.proposals(
            for: [.sleep, .movement, .focus], shape: shape, observations: everywhere).first)
        #expect(third.priorityRank == 2)
    }

    @Test("A question already tested, declined or measured is never offered again")
    func exclusionsHold() {
        let shape = shape([place(.morning, -9)])
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: shape, observations: everywhere,
            excluding: ["time.morning.vs.rest.feeling"]).isEmpty)

        // Past the point the engine can read a band, the measured path owns it — and
        // a premise saying nothing logged speaks to it would be the app
        // contradicting itself.
        #expect(ExperimentVitals.proposals(
            for: [.focus], shape: shape, observations: everywhere,
            measured: ["time.morning.vs.rest.feeling"]).isEmpty)

        // With a second band available, the exclusion costs the priority its
        // best place rather than its only offer.
        let two = self.shape([place(.morning, -12), place(.afternoon, 9)])
        let fallback = ExperimentVitals.proposals(
            for: [.focus], shape: two, observations: everywhere,
            excluding: ["time.morning.vs.rest.feeling"]).first
        #expect(fallback?.focusLabel == TimeBucket.afternoon.label)
    }

    /// A priority a better offer already serves gets no vitals offer, so the list
    /// never holds two offers for one focus area.
    @Test("Anything already offered keeps its priority to itself")
    func completingSkipsWhatIsServed() {
        let existing = ExperimentVitals.proposals(
            for: [.focus], shape: shape([place(.morning, -9)]), observations: everywhere)
        let completed = ExperimentVitals.completing(
            existing, priorities: [.focus],
            shape: shape([place(.afternoon, 9)]), observations: everywhere)
        #expect(completed.count == existing.count)
        #expect(completed.first?.focusLabel == TimeBucket.morning.label)
    }

    // MARK: - End to end

    /// The one case the whole phase exists for: a shape read off a real feed turning
    /// into an offer, with no hand-built `Place` anywhere in it.
    @Test("A real feed produces an offer")
    func fromAFeedToAnOffer() throws {
        var heartRate: [Physiology.Sample] = []
        var steps: [Physiology.Sample] = []
        for day in 0..<40 {
            guard let midnight = Self.calendar.date(
                byAdding: .day, value: day, to: Self.start) else { continue }
            for hour in 7..<23 {
                for minute in stride(from: 0, to: 60, by: 5) {
                    guard let at = Self.calendar.date(
                        bySettingHour: hour, minute: minute, second: 0, of: midnight)
                    else { continue }
                    let bpm: Double = TimeBucket.bucket(forHour: hour) == .morning ? 54 : 66
                    heartRate.append(Physiology.Sample(at: at, value: bpm))
                    steps.append(Physiology.Sample(at: at, value: 6))
                }
            }
        }
        let feed = Physiology.Feed(heartRate: heartRate, steps: steps)
        let analyzer = Physiology.Analyzer(
            feed: feed, fittingWindows: Physiology.Window.tiling(feed))

        let proposal = try #require(ExperimentVitals.proposals(
            for: [.focus], shape: analyzer.dayShape,
            direction: calibrated(false), observations: everywhere).first,
            "a twelve-beat morning dip read off a real feed produced no offer")
        #expect(proposal.hypothesisId == "time.morning.vs.rest.feeling")
        #expect(proposal.premise.contains("sits lower"))
    }

    // MARK: - The fixture

    /// What the simulator fixture actually reaches, pinned rather than assumed.
    ///
    /// Three facts, and the third is the one worth knowing before wiring this in.
    ///
    /// 1. **The shape is there.** `DebugFixture.seededFeed` plants a circadian sine
    ///    whose two ends clear the floor at hourly resolution — see `DayShapeTests`.
    /// 2. **The calibration resolves, and it resolves to the low end.** The fixture
    ///    plants `(3 - feeling) * 3.5` beats on each rated window, so a heart rate
    ///    above this person's usual travels with sessions they rated *worse*, and
    ///    `residualHigherIsBetter` comes back false.
    /// 3. **And this source still stands down on it**, because the fixture is a
    ///    sixty-day record with ratings spread across every band, so the engine already
    ///    has a `Finding` for all four time windows. `measured` is what refuses it, and
    ///    refusing is correct: the premise says nothing logged speaks to that band yet,
    ///    which would be false, and the measured path owns a question it can read.
    ///
    /// So a vitals-led proposal is reachable on a simulator only with `measured`
    /// withheld. That is not a flaw in either half — this source exists for the person
    /// whose record cannot produce a timing finding, and the fixture is deliberately
    /// somebody whose record can. It is recorded here because the alternative is
    /// finding it out from an empty card.
    @Test("What the seeded fixture reaches, and what refuses it")
    @MainActor
    func theFixture() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)

        let input = EngineInput(observations: store.engineObservations,
                                priorities: store.profile.priorities)
        let findings = Engine.applyingCorrection(to: Engine.findings(for: input))
        let direction = findings.first?.direction ?? .uncalibrated
        #expect(direction.residualHigherIsBetter == false, Comment(rawValue:
            "the fixture's calibration did not resolve to the low end: \(direction)"))

        let analyzer = Physiology.Analyzer(
            feed: DebugFixture.seededFeed(),
            sessions: store.sessions,
            workdays: store.profile.workdays)
        let shape = analyzer.dayShape
        #expect(!shape.isEmpty)

        let offered = try #require(ExperimentVitals.proposals(
            for: store.profile.priorities, shape: shape, direction: direction,
            observations: store.engineObservations,
            excluding: store.experimentKeysToExclude).first, Comment(rawValue:
                "the fixture reached no vitals-led proposal even with nothing measured "
                + "standing in the way: \(shape.places)"))
        #expect(offered.premise.contains("your heart rate sits lower"))

        // And with the engine's own findings handed over, as a caller that mirrors
        // `ExperimentStarters` would hand them over, it stands down.
        let measured = Set(findings.map(\.hypothesis.id))
        #expect(measured.contains("time.morning.vs.rest.feeling"))
        #expect(ExperimentVitals.proposals(
            for: store.profile.priorities, shape: shape, direction: direction,
            observations: store.engineObservations, measured: measured,
            excluding: store.experimentKeysToExclude).isEmpty)
    }
}
