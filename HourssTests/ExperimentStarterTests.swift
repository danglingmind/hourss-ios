import Foundation
import Testing
@testable import Hourss

/// Health history, shaped so a known set of facts comes out of it.
///
/// Shared with `ExperimentDesignTests`, which sweeps the copy a starter produces.
/// Built here rather than taken from `SyntheticCohort` because the whole point of a
/// starter is somebody who has logged *nothing* — the cohort people all have months
/// of sessions, which is the case starters exist to not need.
enum StarterFixture {

    /// Which `HealthDigest` generator a series is engineered to trip.
    ///
    /// Each shape is chosen against the generators' own guards rather than guessed:
    /// `weekdayRhythm` refuses a series whose extremes straddle the weekend,
    /// `weekendContrast` and `drift` both need an 8–10% gap. So a rhythm series puts
    /// its extremes on two weekdays and keeps the weekend in the middle, a contrast
    /// series makes every weekday identical, and a drift series makes every weekday
    /// identical and lifts the recent half.
    enum Shape { case rhythm, contrast, drift }

    /// Plausible daily level per metric, so the formatted figures in a premise read
    /// like somebody's history rather than like test data.
    static func base(_ metric: HealthMetric) -> Double {
        switch metric {
        case .sleepHours: 7
        case .hrv: 45
        case .restingHeartRate: 58
        case .respiratoryRate: 15
        case .heartRate: 72
        case .workoutMinutes: 30
        case .steps: 8_000
        case .activeEnergy: 520
        case .exerciseMinutes: 25
        case .mindfulMinutes: 10
        case .daylightMinutes: 65
        }
    }

    /// Half a year of one metric, shaped to trip one generator.
    static func series(_ metric: HealthMetric, _ shape: Shape, days: Int = 182) -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var out: [Date: Double] = [:]
        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Monday is 0, so 5 and 6 are Saturday and Sunday — the same shift
            // `HealthDigest.weekdayRhythm` uses.
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            let isWeekend = weekday >= 5
            let recent = offset <= days / 2

            let factor: Double
            switch shape {
            case .rhythm:
                // Extremes on Monday and Tuesday, weekend parked between them.
                factor = [1.0, 1.4, 1.12, 1.22, 1.16, 1.2, 1.2][weekday]
            case .contrast:
                factor = isWeekend ? 1.3 : 1.0
            case .drift:
                factor = recent ? 1.35 : 1.0
            }
            out[day] = base(metric) * factor
        }
        return out
    }

    /// Every metric the engine may split on, each carrying one shape.
    ///
    /// Shapes are dealt round-robin so the pool holds all three kinds, which is what
    /// makes the sweep cover every sentence `HealthDigest` can hand a premise.
    static var healthByDay: [HealthMetric: [Date: Double]] {
        let shapes: [Shape] = [.rhythm, .contrast, .drift]
        var out: [HealthMetric: [Date: Double]] = [:]
        for (index, metric) in HealthMetric.allCases.filter(\.isDailyContext).enumerated() {
            out[metric] = series(metric, shapes[index % shapes.count])
        }
        return out
    }

    /// One metric only, for the case where a priority's own `HealthGroup` is empty.
    static func healthByDay(only metric: HealthMetric, _ shape: Shape = .contrast)
        -> [HealthMetric: [Date: Double]] {
        [metric: series(metric, shape)]
    }

    /// Every fact the full fixture yields, in `HealthDigest`'s own order.
    static var pool: [HealthDigest.Fact] { HealthDigest.pool(from: healthByDay) }
}

/// Day-one proposals: built from Health alone, claiming nothing, and standing down
/// the moment anything measured exists.
@Suite("Experiment starters")
struct ExperimentStarterTests {

    private let activities = Activity.defaults

    private func starters(_ priorities: [Priority],
                          health: [HealthMetric: [Date: Double]] = StarterFixture.healthByDay,
                          measured: Set<String> = [],
                          excluding: Set<String> = []) -> [ExperimentDesign.Proposal] {
        ExperimentStarters.starters(for: priorities, healthByDay: health,
                                   activities: activities,
                                   measured: measured, excluding: excluding)
    }

    // MARK: Every priority is served

    /// The equivalent of `ExperimentDesignTests.balanceIsCovered`, for starters.
    ///
    /// A priority onboarding collects and the app can do nothing with is a promise it
    /// cannot keep, and on day one the measured paths can do nothing with *any* of
    /// them. So this is the stronger of the two pins: it is the only thing standing
    /// between six ranked focus areas and a first week of silence.
    @Test("Every priority produces a starter from Health alone")
    func everyPriorityIsServed() throws {
        for priority in Priority.allCases {
            let out = starters([priority])
            #expect(out.count == 1,
                    Comment(rawValue: "\(priority.title) produced \(out.count) starters"))
            let starter = try #require(out.first)
            #expect(starter.priority == priority)
            #expect(!starter.change.isEmpty)
            #expect(!starter.premise.isEmpty)
            #expect(!starter.caveat.isEmpty)
        }
    }

    @Test("All six at once are six distinct offers, in the person's own order")
    func allSixTogether() {
        let out = starters(Priority.allCases)
        #expect(out.count == Priority.allCases.count)
        #expect(out.map(\.priority) == Priority.allCases)
        #expect(out.map(\.priorityRank) == Array(0..<Priority.allCases.count))
        // One hypothesis cannot serve two priorities: the person would be offered the
        // same fortnight twice under two headings.
        #expect(Set(out.map(\.hypothesisId)).count == out.count)
    }

    /// The correspondence that keeps starters honest about *which* focus area they
    /// serve. Selection is by priority everywhere in this feature, and a starter
    /// filed under Sleep that tests durations would be the map ignored.
    @Test("A starter's type is one its priority actually asks for")
    func starterServesItsPriority() throws {
        for priority in Priority.allCases {
            let starter = try #require(starters([priority]).first)
            #expect(priority.insightTypes.contains(starter.type),
                    Comment(rawValue: "\(priority.title) got a \(starter.type.rawValue) starter"))
        }
    }

    @Test("The six are the shapes the design settled on")
    func theSixShapes() throws {
        func id(_ priority: Priority) -> String? { starters([priority]).first?.hypothesisId }

        #expect(id(.focus) == "time.morning.vs.rest.feeling")
        #expect(id(.energy) == "activity.deep-work.vs.rest.feeling")
        #expect(id(.sleep) == "health.sleepHours.higher.vs.lower.feeling")
        #expect(id(.movement) == "health.steps.higher.vs.lower.feeling")
        #expect(id(.calm) == "health.mindfulMinutes.higher.vs.lower.feeling")
        #expect(id(.balance) == "workday.non.vs.work.feeling")
    }

    // MARK: The ids have to be the registry's

    /// The silent failure this file is most exposed to.
    ///
    /// A starter's id is the key `ExperimentOutcome` looks the predicate up by a
    /// fortnight later. One character out and nothing fails, logs or throws — every
    /// starter settles as "cannot tell", two weeks later, on somebody else's phone.
    /// So every constructed id is checked against the registry built from
    /// observations that do support it.
    @Test("Every constructed hypothesis id is the one the registry mints")
    func idsMatchTheRegistry() throws {
        let observations = Self.observationsSupportingEverything()
        let registry = HypothesisRegistry.hypotheses(for: observations)
        let byId = Dictionary(registry.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var shapes: [ExperimentStarters.Shape] = [.workday]
        shapes += TimeBucket.allCases.map { .time($0) }
        shapes += DurationBucket.allCases.map { .duration($0) }
        shapes += HealthMetric.allCases.filter(\.isDailyContext).map { .health($0) }
        shapes += Activity.defaults.map { .activity($0.name) }

        for shape in shapes {
            let blueprint = try #require(ExperimentStarters.blueprint(for: shape),
                                         Comment(rawValue: "no blueprint for \(shape)"))
            let hypothesis = try #require(
                byId[blueprint.hypothesisId],
                Comment(rawValue: "\(blueprint.hypothesisId) is not a registry id"))

            // And the two sides have to be named the same way, or a settled card
            // describes a split the person was never offered.
            #expect(blueprint.type == hypothesis.type)
            #expect(blueprint.outcome == hypothesis.outcome)
            #expect(blueprint.focusLabel == hypothesis.focusLabel)
            #expect(blueprint.baselineLabel == hypothesis.baselineLabel)
            #expect(blueprint.caveat == hypothesis.caveat)
        }
    }

    /// Observations rich enough that every registry family is minted: ten activities
    /// over forty rated days, every daily-context metric present, both workday
    /// states, every time and duration bucket.
    static func observationsSupportingEverything() -> [EngineObservation] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let metrics = HealthMetric.allCases.filter(\.isDailyContext)
        var out: [EngineObservation] = []

        for offset in 1...40 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            var health: [HealthMetric: Double] = [:]
            for metric in metrics {
                health[metric] = StarterFixture.base(metric) * (offset.isMultiple(of: 2) ? 1.2 : 0.8)
            }
            for (index, activity) in Activity.defaults.enumerated() {
                let bucket = TimeBucket.allCases[(offset + index) % TimeBucket.allCases.count]
                let duration = DurationBucket.allCases[(offset + index) % DurationBucket.allCases.count]
                out.append(EngineObservation(
                    sessionId: UUID(),
                    day: day,
                    startAt: day.addingTimeInterval(Double(3600 * (6 + index))),
                    durationMinutes: 45,
                    activityName: activity.name,
                    activityCategory: activity.category,
                    timeBucket: bucket,
                    durationBucket: duration,
                    isWorkday: !offset.isMultiple(of: 7),
                    feeling: Double(1 + (offset + index) % 5),
                    performance: Double(1 + (offset + index) % 5),
                    dayHealth: health,
                    heartRateResidual: nil,
                    cadence: nil))
            }
        }
        return out
    }

    // MARK: Standing

    @Test("A starter says it has measured nothing, and is free")
    func standing() throws {
        for priority in Priority.allCases {
            let starter = try #require(starters([priority]).first)
            #expect(starter.standing == .starter)
            #expect(starter.isStarter)
            // The paywall cannot sit in front of the only thing the app can offer on
            // day one.
            #expect(!starter.requiresMembership)
            // Nothing measured, so nothing to quote. The lead form quotes a count
            // and a shrunk estimate; a starter has neither and must not imply one.
            #expect(starter.evidenceDays == 0)
            #expect(starter.figure == 0)
            #expect(starter.baselineFigure == 0)
            #expect(!starter.premise.contains("has read higher"))
            #expect(!starter.premise.contains("so far"))
        }
    }

    /// The card must not imply the app has read anything about their sessions, and
    /// this is the sentence that stops the premise being read as a reason.
    @Test("Every premise names what has not been read yet")
    func premiseNamesTheGap() throws {
        for priority in Priority.allCases {
            let starter = try #require(starters([priority]).first)

            // The premise *is* the gap now, rather than ending on it. These used to
            // be one string with the Health reading first, which put the reading
            // directly under the change on the card and made the two read as claim
            // and reason — the exact inference the fortnight exists to test.
            #expect(starter.premise.contains("Nothing you have logged says yet"))

            // And the reading is carried alongside, from `HealthDigest` rather than
            // written here, for the reason a confirmed premise reuses
            // `hypothesis.phrase` — one wording per fact.
            let health = try #require(starter.context)
            #expect(StarterFixture.pool.contains { $0.sentence == health },
                    Comment(rawValue: "\"\(health)\" is not a HealthDigest sentence"))

            // The order is the whole of the fix, so it is asserted rather than
            // assumed: a card reading change → reading → gap would be the shape this
            // change removed.
            let copy = ObservationSlot.copy(for: .experimentProposal(id: starter.id),
                                            proposal: starter)
            let texts = copy.lines.map(\.text)
            #expect(texts == [starter.change, starter.premise, health])
            #expect(copy.lines.last?.emphasis == .support)
        }
    }

    // MARK: Health that is absent or thin

    @Test("No Health, no starter")
    func noHealthNoStarter() {
        #expect(starters(Priority.allCases, health: [:]).isEmpty)
    }

    @Test("Health too thin for a fact produces no starter")
    func thinHealthNoStarter() {
        // `HealthDigest` needs ten days of a metric and five on each side of any
        // comparison, so a week-old phone yields an empty pool and the slot falls
        // back to the evidence mark it showed before starters existed.
        let week = StarterFixture.series(.sleepHours, .contrast, days: 7)
        #expect(HealthDigest.pool(from: [.sleepHours: week]).isEmpty)
        #expect(starters(Priority.allCases, health: [.sleepHours: week]).isEmpty)
    }

    @Test("Nothing ranked, nothing offered")
    func noPrioritiesNoStarters() {
        #expect(starters([]).isEmpty)
    }

    /// The real case behind the generic tail: Health carries only what the person's
    /// devices record, so a Sleep ranking on a phone with no sleep data has no
    /// sleep hypothesis to aim at.
    @Test("A priority whose own metrics are absent still reaches a change")
    func theGenericTailFires() throws {
        let stepsOnly = StarterFixture.healthByDay(only: .steps)
        for priority in Priority.allCases {
            let out = starters([priority], health: stepsOnly)
            let starter = try #require(out.first,
                                       Comment(rawValue: "\(priority.title) fell through"))
            #expect(!starter.change.isEmpty)
        }
        // Six priorities, six distinct changes, even with one metric between them.
        let all = starters(Priority.allCases, health: stepsOnly)
        #expect(all.count == Priority.allCases.count)
        #expect(Set(all.map(\.hypothesisId)).count == all.count)
    }

    @Test("A metric with too little history is not aimed at")
    func aThinMetricIsNotATarget() throws {
        // Thirteen days is one short of the window. A hypothesis over a metric
        // recorded on fewer days than the fortnight is long cannot supply six
        // qualifying days inside it, so the fortnight could only come back
        // "cannot tell".
        #expect(!ExperimentStarters.isAvailable(
            .health(.sleepHours),
            healthByDay: [.sleepHours: StarterFixture.series(.sleepHours, .contrast, days: 13)]))
        #expect(ExperimentStarters.isAvailable(
            .health(.sleepHours),
            healthByDay: [.sleepHours: StarterFixture.series(.sleepHours, .contrast, days: 14)]))
        // And time, duration and workday are always available, because the registry
        // mints them without reference to any data.
        #expect(ExperimentStarters.isAvailable(.time(.morning), healthByDay: [:]))
        #expect(ExperimentStarters.isAvailable(.duration(.medium), healthByDay: [:]))
        #expect(ExperimentStarters.isAvailable(.workday, healthByDay: [:]))
    }

    @Test("Somebody with no activities gets no activity starter")
    func noActivitiesNoActivityStarter() throws {
        let out = ExperimentStarters.starters(for: [.energy],
                                             healthByDay: StarterFixture.healthByDay,
                                             activities: [])
        let starter = try #require(out.first)
        // Falls to the generic tail rather than naming an activity nobody has.
        #expect(starter.type != .activityEnergizer)
    }

    // MARK: Precedence

    /// A starter is what the app offers when it has nothing better, never instead of
    /// something better.
    @Test("A real proposal keeps its place and the priority it served gets no starter")
    func realFindingsWin() throws {
        let real = Self.proposal(priority: .focus, rank: 0)
        let out = ExperimentStarters.completing(
            [real], priorities: Priority.allCases,
            healthByDay: StarterFixture.healthByDay, activities: activities)

        #expect(out.first?.id == real.id)
        #expect(out.first?.isStarter == false)
        #expect(out.count == Priority.allCases.count)
        // Focus was served by the measured proposal, so no starter claims it.
        #expect(out.filter { $0.priority == .focus }.count == 1)
        // Everything behind the real one is a starter, whatever its priority rank.
        let behind = out.dropFirst().allSatisfy { $0.isStarter }
        #expect(behind)
    }

    /// The ordering is the precedence rule: Today shows `proposals.first`.
    @Test("A lead for a lower priority still beats a starter for a higher one")
    func aLowerLeadStillWins() throws {
        // Balance is ranked last and is the only priority with a measured proposal.
        let real = Self.proposal(priority: .balance, rank: 5)
        let out = ExperimentStarters.completing(
            [real], priorities: [.focus, .energy, .sleep, .movement, .calm, .balance],
            healthByDay: StarterFixture.healthByDay, activities: activities)
        let lead = try #require(out.first)
        #expect(!lead.isStarter)
        #expect(lead.priority == .balance)
    }

    @Test("A hypothesis a real proposal already uses is not also offered as a starter")
    func noDoubleOffer() {
        // The measured proposal is the workday contrast under `energy`, which is not
        // the priority a workday starter would be filed under — so only the id can
        // stop it being offered twice.
        var real = Self.proposal(priority: .energy, rank: 1)
        real = ExperimentDesign.Proposal(
            hypothesisId: "workday.non.vs.work.feeling", outcome: .feeling,
            type: .workdayContrast, standing: .lead, basis: .measured,
            focusLabel: "Non-workdays", baselineLabel: "Workdays",
            premise: real.premise, context: nil, change: real.change, caveat: real.caveat,
            priority: .energy, priorityRank: 1, evidenceDays: 4,
            figure: 4, baselineFigure: 3.5)
        let out = ExperimentStarters.completing(
            [real], priorities: Priority.allCases,
            healthByDay: StarterFixture.healthByDay, activities: activities)
        #expect(out.filter { $0.hypothesisId == "workday.non.vs.work.feeling" }.count == 1)
    }

    @Test("Declines and tested hypotheses are never offered as starters")
    func declinesAreRespected() {
        let morning = "time.morning.vs.rest.feeling"
        #expect(starters([.focus]).first?.hypothesisId == morning)
        #expect(starters([.focus], excluding: [morning]).first?.hypothesisId != morning)
        // And the whole list honours it, rather than only the first entry.
        let out = starters(Priority.allCases, excluding: [morning])
        #expect(!out.contains { $0.hypothesisId == morning })
    }

    /// Once the engine can read a hypothesis, the measured path owns it.
    @Test("A hypothesis the engine has tested gets no starter")
    func measuredHypothesesStandDown() {
        let sleep = "health.sleepHours.higher.vs.lower.feeling"
        #expect(starters([.sleep]).first?.hypothesisId == sleep)
        // A starter here would say "nothing you have logged says yet" about a split
        // the engine has six rated days on each side of — the app contradicting
        // itself — and could ask for more of a group that currently reads worse.
        #expect(starters([.sleep], measured: [sleep]).first?.hypothesisId != sleep)
    }

    // MARK: Acceptance and measurement

    /// The claim the whole approach rests on: the measurement path needs no change.
    ///
    /// The sleep starter is the right one to check it with, because
    /// `health.sleepHours.…` is genuinely not in the registry until somebody has four
    /// rated days carrying a sleep value — unlike the time, duration and workday
    /// hypotheses, which are registered whether or not anything has been logged.
    @Test("A starter's hypothesis is absent today and reads as cannot-tell")
    func anAbsentHypothesisCannotBeRead() throws {
        let starter = try #require(starters([.sleep]).first)
        let experiment = ExperimentDesign.experiment(
            from: starter, startedAt: Date(timeIntervalSince1970: 1_767_225_600))

        // What somebody accepted is what they were shown, starter or not.
        #expect(experiment.hypothesisId == starter.hypothesisId)
        #expect(experiment.premise == starter.premise)
        #expect(experiment.change == starter.change)
        #expect(experiment.predictsHigher)

        // Not there yet, which is the entire premise of a starter.
        #expect(!HypothesisRegistry.hypotheses(for: []).contains { $0.id == starter.hypothesisId })

        // And reading it is "cannot tell" rather than an error or a crash. This is
        // why phase 3 touches no part of `ExperimentOutcome`.
        let reading = ExperimentOutcome.read(experiment, hypothesis: nil,
                                             observations: [], resamples: 50)
        #expect(reading.verdict == .cannotTell)
        #expect(reading.adherenceDays == 0)
        #expect(reading.comparison == nil)

        // And settling freezes that without complaint.
        let closed = experiment.endsAt().addingTimeInterval(60)
        let settled = ExperimentOutcome.settle(experiment, hypothesis: nil,
                                               observations: [], now: closed, resamples: 50)
        let settlement = try #require(settled.settlement)
        #expect(settlement.verdict == .cannotTell)
        #expect(!ExperimentCopy.result(for: settled, settlement: settlement).isEmpty)
    }

    /// The other half of the same claim: once they *have* logged, the hypothesis is
    /// there and the predicate is found by the id the starter stored.
    @Test("By the time the fortnight closes the hypothesis exists, if they logged")
    func theHypothesisArrives() throws {
        let starter = try #require(starters([.sleep]).first)
        let observations = Self.observationsSupportingEverything()
        let hypothesis = try #require(
            HypothesisRegistry.hypotheses(for: observations)
                .first { $0.id == starter.hypothesisId },
            "the id a starter stored does not come back once there is data")
        #expect(hypothesis.focusLabel == starter.focusLabel)
        #expect(hypothesis.baselineLabel == starter.baselineLabel)
    }

    // MARK: Determinism

    @Test("The same history produces the same starters every run")
    func determinism() {
        let health = StarterFixture.healthByDay
        let first = ExperimentStarters.starters(for: Priority.allCases, healthByDay: health,
                                                activities: activities)
        let second = ExperimentStarters.starters(for: Priority.allCases, healthByDay: health,
                                                 activities: activities)
        #expect(first.map(\.hypothesisId) == second.map(\.hypothesisId))
        #expect(first.map(\.premise) == second.map(\.premise))
        #expect(first.map(\.change) == second.map(\.change))
    }

    // MARK: Fixtures

    static func measuredProposal(priority: Priority, rank: Int) -> ExperimentDesign.Proposal {
        proposal(priority: priority, rank: rank)
    }

    private static func proposal(priority: Priority, rank: Int) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: "duration.medium.vs.rest.feeling", outcome: .feeling,
            type: .durationSweetSpot, standing: .lead, basis: .measured,
            focusLabel: "30–89 min", baselineLabel: "Other lengths",
            premise: "30–89 min has read higher so far, across 4 days.",
            context: nil,
            change: "End one block at the 30–89 min mark on most days this fortnight.",
            caveat: "Longer sessions may simply be the harder work.",
            priority: priority, priorityRank: rank, evidenceDays: 4,
            figure: 4, baselineFigure: 3.5)
    }
}

/// The day-one person, through the store and onto Today.
///
/// Every assertion above is about one layer. This is the one that would have caught
/// the thing phase 3 exists to fix: somebody who has connected Health, ranked their
/// focus areas, logged nothing, and is shown an evidence mark for a week.
@Suite("Starters on day one")
@MainActor
struct StarterStoreTests {

    private func store(_ priorities: [Priority] = Priority.allCases) -> HourssStore {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = priorities
        store.activities = Activity.defaults
        store.applyHealthContext(StarterFixture.healthByDay)
        store.rebuildInsights()
        return store
    }

    @Test("Somebody who has logged nothing is offered something to test")
    func dayOneIsNotEmpty() throws {
        let store = store()
        #expect(store.sessions.isEmpty)
        // The measured paths have nothing: no sessions, so no findings, so no
        // proposals. That is the emptiness this phase answers.
        #expect(ExperimentDesign.proposals(
            for: EngineInput(observations: store.engineObservations,
                             priorities: store.profile.priorities),
            resamples: 50).isEmpty)

        let proposals = store.experimentProposals(resamples: 50)
        #expect(!proposals.isEmpty, "a connected Health history produced nothing to test")
        let allStarters = proposals.allSatisfy { $0.isStarter }
        #expect(allStarters)
        #expect(proposals.count == Priority.allCases.count)
    }

    /// The slot needs no view change: a starter is an ordinary `Proposal`.
    @Test("A starter claims the observation slot on Today")
    func theSlotShowsIt() throws {
        let store = store()
        let proposals = store.experimentProposals(resamples: 50)
        let state = store.slotState(on: Date(), recommendations: [], proposals: proposals)
        let lead = try #require(proposals.first)

        #expect(state.proposalId == lead.id)
        // Free, so the slot shows it without an entitlement.
        #expect(!state.proposalRequiresMembership)
        #expect(ObservationSlot.content(for: state) == .experimentProposal(id: lead.id))

        let copy = ObservationSlot.copy(for: .experimentProposal(id: lead.id), proposal: lead)
        // Its own word, not the lead's. Both read "Worth testing" at first, which is
        // true of each and hides the only difference: a lead has six rated days a
        // side behind it and a starter has nothing but a Health reading about
        // something else.
        #expect(copy.eyebrow == ExperimentCopy.eyebrow(for: lead.standing))
        #expect(copy.eyebrow != ExperimentCopy.eyebrow(for: .lead))
        #expect(copy.lines.first?.text == lead.change)
        #expect(copy.lines.first?.emphasis == .lead)
        // The card's control opens the sheet; it no longer starts anything. Agreeing
        // moved to `TestProposalSheet` so that it is a decision rather than a tap on
        // a text link weighing the same as "Add how it felt".
        #expect(copy.action == ExperimentCopy.openTitle)
        #expect(!copy.accessibilityLabel.isEmpty)
    }

    @Test("Accepting a starter opens a real fortnight, and closes the offer")
    func acceptingAStarter() throws {
        let store = store()
        let starter = try #require(store.experimentProposals(resamples: 50).first)
        let opened = Date(timeIntervalSince1970: 1_767_225_600)
        let experiment = try #require(store.acceptExperiment(starter, now: opened))

        #expect(store.activeExperiment?.id == experiment.id)
        #expect(experiment.premise == starter.premise)
        // One active experiment, ever — the invariant does not care where the
        // proposal came from.
        #expect(store.experimentProposals(resamples: 50).isEmpty)
        #expect(store.experimentKeysToExclude.contains(starter.hypothesisId))
    }

    @Test("Declining a starter is permanent, like any other decline")
    func decliningAStarter() throws {
        let store = store()
        let starter = try #require(store.experimentProposals(resamples: 50).first)
        store.declineExperiment(starter)
        let after = store.experimentProposals(resamples: 50)
        #expect(!after.contains { $0.hypothesisId == starter.hypothesisId })
        // And the next focus area is offered instead of nothing.
        #expect(!after.isEmpty)
    }

    /// This used to assert that an empty record with no Health gets nothing at all,
    /// and that was the dead end the whole app was built into.
    ///
    /// **What fills it has changed once, and the change is the point.** It was a gap —
    /// reasoning from an empty side of a question — until one example killed that for
    /// time of day: somebody whose work ends at three and who then sleeps has no
    /// evening sessions because they have no evenings. Gaps are activities only now,
    /// and an empty record has no activity gap either, because an activity nobody has
    /// logged has no question in the registry to be short of.
    ///
    /// So the offer here is prior-led: what is expected of people in general, said as
    /// a question about this person. That is a weaker thing to rest on than silence
    /// was meant to be, and it is honest about it in a way silence never was.
    @Test("No Health and an empty record still offers something")
    func noHealthStillOffersSomething() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = Priority.allCases
        store.activities = Activity.defaults
        store.rebuildInsights()

        // No Health means no Health-seeded starter — a starter's premise *is* a
        // Health fact, so without one there is nothing to seed from.
        #expect(ExperimentStarters.starters(for: Priority.allCases, healthByDay: [:]).isEmpty)

        // And no shape, because a shape is a reading of a Health curve there is none
        // of — so nothing vitals-led either.
        #expect(store.dayShape == nil)

        // What is left is the prior. Asserted by what makes a prior-led premise what
        // it is rather than by its wording: it is the one string in this app that
        // names people in general, so the ordinary sweep must refuse it as
        // `.population` and the one exempt sweep must pass it. Pinning the sentence
        // here instead would duplicate `ExperimentPriorTests` and break on a copy
        // edit that changed nothing about where the offer came from.
        let offers = store.experimentProposals(resamples: 50)
        #expect(!offers.isEmpty)
        let first = try #require(offers.first)
        #expect(first.standing == .starter)
        #expect(first.evidenceDays == 0)
        if case .population = NarrationGuard.offence(in: first.premise) {} else {
            Issue.record("the offer on an empty record is not prior-led: \(first.premise)")
        }
        #expect(NarrationGuard.priorPremiseOffence(in: first.premise) == nil)

        // And the slot now shows that offer rather than a progress mark.
        let state = store.slotState(on: Date(), recommendations: [], proposals: offers)
        #expect(ObservationSlot.content(for: state) == .experimentProposal(id: first.id))
    }

    /// Where the two halves meet, on one engine run rather than two.
    @Test("The one-run path and the separate path agree")
    func slotOutputAgrees() {
        let store = store()
        let output = store.slotOutput(resamples: 50)
        #expect(output.proposals.map(\.id) == store.experimentProposals(resamples: 50).map(\.id))
    }

    /// Precedence, on a real record rather than on hand-built values: somebody with
    /// months of sessions has measured proposals, and those lead.
    @Test("A person with real findings is led by them, not by a starter")
    func measuredBeatsStarter() throws {
        let person = SyntheticCohort.afternoonSlump
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.profile.priorities = Priority.allCases
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.applyHealthContext(person.healthByDay)
        store.rebuildInsights()

        // Fewer resamples than production: this asserts an ordering, and the
        // interval's third decimal has no bearing on which end of the list a
        // measured proposal sits at.
        let proposals = store.experimentProposals(resamples: 400)
        let lead = try #require(proposals.first)
        #expect(!lead.isStarter, "a starter was offered ahead of a measured proposal")
        // Starters still fill the focus areas the engine had nothing for, which is
        // the point — the list is complete without displacing anything.
        #expect(proposals.contains { !$0.isStarter })
    }
}
