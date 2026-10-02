import Testing
import Foundation
@testable import Hourss

/// Whether a raised heart rate is a good sign, answered per person and then used.
///
/// Two things are held here and they are a chain rather than two features.
///
/// **The question.** `HypothesisRegistry.residualCalibration` splits somebody's
/// sessions at their own median heart-rate residual and asks how the two sides
/// felt. It is the inverse of the `physiology.*` family — same number, the other
/// role — and it is the only split in the registry that compares *within* a day.
///
/// **The answer, used.** `Outcome.higherIsBetter` used to be a constant that was
/// nil for a residual, which made every `physiology.*` finding unreachable by
/// `Recommendations` and `ExperimentDesign` by construction. It is now
/// `Finding.direction`, resolved once per run from that person's own confirmed
/// calibration. Most of what follows asserts that nothing is directed until one
/// confirms, because that is where the danger is: everything downstream inherits
/// this one answer, so a wrong one is not one wrong claim but every physiology
/// claim wrong the same way at once.
@Suite("Residual calibration and direction")
struct CalibrationTests {

    // MARK: - Fixtures

    /// A history whose residual and whose ratings are linked, and in which nothing
    /// else is.
    ///
    /// Two sessions a day, one morning and one afternoon. Each day has exactly one
    /// session on the high side of the residual and one on the low side, and
    /// **which of the two it is alternates by day** — so the time bucket, the
    /// activity and the duration all carry no signal at all, and the only thing
    /// that predicts a rating is the residual. That is deliberate: a fixture where
    /// the residual correlates with the hour cannot tell a calibration from a
    /// timing claim wearing its clothes.
    ///
    /// - Parameter higherFeelsBetter: which way the planted link runs. Passing
    ///   `true` is the person for whom a raised heart rate goes with better
    ///   sessions, and the whole point of the mechanism is that both are allowed.
    static func observations(
        days: Int = 20,
        higherFeelsBetter: Bool = false,
        residual: Double = 6
    ) -> [EngineObservation] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var rows: [EngineObservation] = []

        for dayOffset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            // The morning carries the high residual on even days and the low one on
            // odd days.
            let morningIsHigh = dayOffset.isMultiple(of: 2)

            for (hour, isHigh) in [(9, morningIsHigh), (15, !morningIsHigh)] {
                // A little spread, because a fixture with no noise in it cannot
                // test machinery whose job is to discount noise — and a zero-width
                // interval is not a thing this engine ever sees in the field.
                let jitter = Double((dayOffset + hour) % 2)
                let feelsBetter = isHigh == higherFeelsBetter
                rows.append(EngineObservation(
                    sessionId: UUID(),
                    day: day,
                    startAt: day.addingTimeInterval(Double(hour) * 3600),
                    durationMinutes: 60,
                    activityName: hour == 9 ? "Deep work" : "Meetings",
                    activityCategory: "Work",
                    timeBucket: TimeBucket.bucket(forHour: hour),
                    durationBucket: .medium,
                    isWorkday: true,
                    feeling: feelsBetter ? 4 + jitter : 2 - jitter,
                    performance: nil,
                    dayHealth: [:],
                    heartRateResidual: isHigh ? residual + jitter : -residual - jitter,
                    cadence: 5
                ))
            }
        }
        return rows
    }

    static func input(_ rows: [EngineObservation], priorities: [Priority] = []) -> EngineInput {
        EngineInput(observations: rows, windowDays: 42, priorities: priorities)
    }

    static func calibration(in rows: [EngineObservation]) -> Hypothesis? {
        HypothesisRegistry.hypotheses(for: rows)
            .first { $0.id == HypothesisRegistry.residualCalibrationId }
    }

    /// A finding with the few numbers that matter chosen. Direction is left at its
    /// default, which is `.uncalibrated` — the state these tests are mostly about.
    static func finding(
        id: String,
        outcome: Outcome,
        type: InsightType = .bodyContext,
        delta: Double = 0.6,
        corrected: Bool = true,
        days: Int = 20
    ) -> Finding {
        Finding(
            hypothesis: Hypothesis(
                id: id, type: type, outcome: outcome,
                focusLabel: "Focus", baselineLabel: "Baseline",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "" }, caveat: "A limit.", experiment: nil
            ),
            comparison: Statistics.Comparison(
                delta: delta,
                low: delta - 0.15, high: delta + 0.15,
                focusCount: 40, baselineCount: 40,
                focusDays: days, baselineDays: days,
                pValue: 0.001
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.9, baselineCoverage: 0.9,
            survivesCorrection: corrected,
            windowDays: 42
        )
    }

    // MARK: - The hypothesis exists and is well formed

    @Test("The calibration is registered once a median means anything")
    func registersOnEnoughValues() throws {
        let rows = Self.observations()
        let hypothesis = try #require(Self.calibration(in: rows),
                                      "no calibration hypothesis on a history full of residuals")
        #expect(hypothesis.outcome == .feeling, "the calibration measures the rating, not the heart rate")
        #expect(hypothesis.id == "residual.higher.vs.lower.feeling",
                "the id is stable; insight identity rides on it")
        #expect(hypothesis.caveat == HypothesisRegistry.residualCaveat,
                "the physiology family's caveat was rewritten rather than carried")
        #expect(hypothesis.experiment == nil, "a test of this claim would be a test of a heart rate")
    }

    @Test("Below four values there is no median, so there is no question")
    func doesNotRegisterBelowTheMinimum() {
        // Three rated residuals. A median of three is a coin toss between two
        // numbers, and the cost of asking anyway is power taken from every other
        // hypothesis under the correction.
        let rows = Array(Self.observations(days: 2).prefix(3))
        #expect(rows.count == 3)
        #expect(Self.calibration(in: rows) == nil)

        // And a history with residuals that nobody rated is the same silence. A
        // median over unrated sessions would split the data where no evidence sits
        // on either side, and scoring those sessions from their own residual to
        // fill the gap is forbidden outright.
        let unrated = Self.observations().map { row in
            EngineObservation(
                sessionId: row.sessionId, day: row.day, startAt: row.startAt,
                durationMinutes: row.durationMinutes, activityName: row.activityName,
                activityCategory: row.activityCategory, timeBucket: row.timeBucket,
                durationBucket: row.durationBucket, isWorkday: row.isWorkday,
                feeling: nil, performance: nil, dayHealth: [:],
                heartRateResidual: row.heartRateResidual, cadence: row.cadence
            )
        }
        #expect(Self.calibration(in: unrated) == nil)
    }

    @Test("The two sides partition the rows that have a residual, and no row is in both")
    func sidesPartitionCleanly() throws {
        let rows = Self.observations()
        let hypothesis = try #require(Self.calibration(in: rows))

        for row in rows {
            let onFocus = hypothesis.focus(row)
            let onBaseline = hypothesis.baseline(row)
            #expect(!(onFocus && onBaseline), "a session landed on both sides of the median")
            #expect(onFocus || onBaseline, "a session with a residual landed on neither side")
        }

        // A row with no residual belongs to neither side rather than to the lower
        // one. `nan` makes both comparisons false, which is the device
        // `healthAssociations` uses and the reason this holds.
        let blank = EngineObservation(
            sessionId: UUID(), day: rows[0].day, startAt: rows[0].startAt,
            durationMinutes: 60, activityName: "Deep work", activityCategory: "Work",
            timeBucket: .morning, durationBucket: .medium, isWorkday: true,
            feeling: 3, performance: nil, dayHealth: [:],
            heartRateResidual: nil, cadence: nil
        )
        #expect(!hypothesis.focus(blank))
        #expect(!hypothesis.baseline(blank))
    }

    // MARK: - The property nothing else in the registry has

    /// §3's claim, and the strongest thing about the design.
    ///
    /// Every other association splits on `dayHealth`, which is a property of the
    /// *day*, so all of a day's sessions land on the same side and the comparison
    /// is between days. A residual is a property of the *session*, so two sessions
    /// on one afternoon can land on opposite sides — and because
    /// `Statistics.compare` resamples whole days, a drawn day then carries evidence
    /// into both arms at once. Everything that travels with a day is thereby held
    /// constant inside the comparison instead of being a confound the caveat has to
    /// apologise for.
    ///
    /// The health family is the control rather than a second assertion: if the
    /// daily splits ever started doing this too, the claim being made here would be
    /// about nothing.
    @Test("The calibration compares within a day; the health associations cannot")
    func comparesWithinDays() throws {
        var rows = Self.observations()
        // Health, so the control side of this test has something to be about. One
        // value per day, as a daily metric is by definition.
        let sleepByDay = Dictionary(
            grouping: rows, by: \.day
        ).mapValues { _ in Double.random(in: 6...8) }
        rows = rows.map { row in
            EngineObservation(
                sessionId: row.sessionId, day: row.day, startAt: row.startAt,
                durationMinutes: row.durationMinutes, activityName: row.activityName,
                activityCategory: row.activityCategory, timeBucket: row.timeBucket,
                durationBucket: row.durationBucket, isWorkday: row.isWorkday,
                feeling: row.feeling, performance: row.performance,
                dayHealth: [.sleepHours: sleepByDay[row.day] ?? 7],
                heartRateResidual: row.heartRateResidual, cadence: row.cadence
            )
        }

        func daysOnBothSides(of hypothesis: Hypothesis) -> Set<Date> {
            let focus = Set(rows.filter(hypothesis.focus).map(\.day))
            let baseline = Set(rows.filter(hypothesis.baseline).map(\.day))
            return focus.intersection(baseline)
        }

        let calibration = try #require(Self.calibration(in: rows))
        #expect(!daysOnBothSides(of: calibration).isEmpty, Comment(rawValue:
            "the calibration split no day across both arms — the fixture or the "
                + "hypothesis stopped being per-session"))

        for hypothesis in HypothesisRegistry.hypotheses(for: rows)
        where hypothesis.id.hasPrefix("health.") {
            #expect(daysOnBothSides(of: hypothesis).isEmpty, Comment(rawValue:
                "\(hypothesis.id) split a day across both arms, which a daily metric cannot do"))
        }

        // And the consequence the bootstrap actually sees: the tested finding
        // reports days on each side that overlap, so a resampled day contributes to
        // both. `Statistics.compare` buckets focus and baseline under one key per
        // day and multiplies both by the same draw count, which is what makes this
        // sound rather than double counting.
        let finding = try #require(
            Engine.findings(for: Self.input(rows), resamples: 200)
                .first { $0.hypothesis.id == HypothesisRegistry.residualCalibrationId })
        let focusDays = Set(rows.filter { finding.focusSessionIds.contains($0.sessionId) }.map(\.day))
        let baselineDays = Set(rows.filter { finding.baselineSessionIds.contains($0.sessionId) }.map(\.day))
        #expect(!focusDays.intersection(baselineDays).isEmpty, Comment(rawValue:
            "no day reached both arms of the tested comparison: "
                + "\(focusDays.count) focus days, \(baselineDays.count) baseline days"))
        #expect(finding.comparison.focusDays + finding.comparison.baselineDays > focusDays.union(baselineDays).count,
                "the two sides between them cited no day twice, so nothing was held constant")
    }

    // MARK: - Resolution

    @Test("A history with no calibration directs nothing")
    func noCalibrationLeavesEverythingUndirected() {
        // Residuals, ratings, and no link between them: alternating sign against a
        // constant rating, so the comparison interval straddles zero.
        let flat = Self.observations().enumerated().map { index, row in
            EngineObservation(
                sessionId: row.sessionId, day: row.day, startAt: row.startAt,
                durationMinutes: row.durationMinutes, activityName: row.activityName,
                activityCategory: row.activityCategory, timeBucket: row.timeBucket,
                durationBucket: row.durationBucket, isWorkday: row.isWorkday,
                feeling: Double(3 + (index % 3) - 1), performance: nil, dayHealth: [:],
                heartRateResidual: row.heartRateResidual, cadence: row.cadence
            )
        }
        let corrected = Engine.applyingCorrection(
            to: Engine.findings(for: Self.input(flat), resamples: 400))
        let calibration = corrected.first {
            $0.hypothesis.id == HypothesisRegistry.residualCalibrationId
        }
        #expect(calibration?.isReportable != true, Comment(rawValue:
            "the fixture meant to plant no link planted one: delta "
                + "\(String(describing: calibration?.comparison.delta))"))
        for finding in corrected {
            #expect(finding.direction == .uncalibrated, Comment(rawValue:
                "\(finding.hypothesis.id) was directed with no calibration behind it"))
        }
        #expect(OutcomeDirection.uncalibrated.higherIsBetter(.heartRateResidual) == nil)
        // The outcomes that were never a question stay answered.
        #expect(OutcomeDirection.uncalibrated.higherIsBetter(.feeling) == true)
        #expect(OutcomeDirection.uncalibrated.higherIsBetter(.performance) == true)
    }

    @Test("A confirmed calibration directs every finding in its own run")
    func aConfirmedCalibrationDirectsTheRun() throws {
        let rows = Self.observations()
        let corrected = Engine.applyingCorrection(
            to: Engine.findings(for: Self.input(rows), resamples: 400))

        let calibration = try #require(
            corrected.first { $0.hypothesis.id == HypothesisRegistry.residualCalibrationId },
            "the calibration was not even tested on twenty days of two sessions")
        #expect(calibration.isReportable, Comment(rawValue:
            "the planted calibration did not confirm: delta \(calibration.comparison.delta), "
                + "interval [\(calibration.comparison.low), \(calibration.comparison.high)], "
                + "correction \(String(describing: calibration.survivesCorrection))"))

        // The planted link is "higher residual, worse session", so this person's
        // answer is that higher is not better. Read off the evidence, not written
        // down anywhere.
        #expect(calibration.comparison.delta < 0)
        for finding in corrected {
            #expect(finding.direction.residualHigherIsBetter == false, Comment(rawValue:
                "\(finding.hypothesis.id) did not inherit the run's direction"))
            #expect(finding.higherIsBetter == (finding.hypothesis.outcome == .heartRateResidual
                                               ? false : true))
        }
    }

    @Test("The other person calibrates the other way, off the same shape of data")
    func theDirectionIsPerPerson() throws {
        let rows = Self.observations(higherFeelsBetter: true)
        let corrected = Engine.applyingCorrection(
            to: Engine.findings(for: Self.input(rows), resamples: 400))
        let calibration = try #require(
            corrected.first { $0.hypothesis.id == HypothesisRegistry.residualCalibrationId })
        #expect(calibration.isReportable)
        #expect(calibration.comparison.delta > 0)
        for finding in corrected {
            #expect(finding.direction.residualHigherIsBetter == true, Comment(rawValue:
                "\(finding.hypothesis.id) inherited the wrong direction"))
        }
    }

    /// Checklist item 7, and the rule the whole design rests on.
    @Test("A lead directs nothing, however close it came")
    func onlyAConfirmedCalibrationDirects() {
        let physiology = Self.finding(id: "physiology.deep-work.vs.rest.heartRateResidual",
                                      outcome: .heartRateResidual)

        // Every ingredient of a confirmed calibration except the correction. This
        // is exactly a lead: enough days, an interval clear of zero, and a claim
        // the feed has decided not to make.
        let lead = Self.finding(id: HypothesisRegistry.residualCalibrationId,
                                outcome: .feeling, delta: -0.6, corrected: false)
        #expect(ExperimentDesign.standing(of: lead) == .lead, "the fixture is not a lead")
        for finding in Engine.resolvingDirection(in: [lead, physiology]) {
            #expect(finding.direction == .uncalibrated,
                    "a lead calibration directed the run")
        }

        // Correction alone is not enough either: an interval containing zero is the
        // engine's honest "not yet", and `isReportable` reads both.
        let straddling = Finding(
            hypothesis: lead.hypothesis,
            comparison: Statistics.Comparison(
                delta: -0.6, low: -0.9, high: 0.2,
                focusCount: 40, baselineCount: 40, focusDays: 20, baselineDays: 20,
                pValue: 0.001),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.9, baselineCoverage: 0.9,
            survivesCorrection: true, windowDays: 42)
        #expect(!straddling.isReportable)
        for finding in Engine.resolvingDirection(in: [straddling, physiology]) {
            #expect(finding.direction == .uncalibrated)
        }

        // Nor is a calibration that was never tested.
        for finding in Engine.resolvingDirection(in: [physiology]) {
            #expect(finding.direction == .uncalibrated)
        }
    }

    @Test("A reversed calibration reverses every finding that reads it")
    func aReversedCalibrationReverses() throws {
        let physiology = Self.finding(id: "physiology.deep-work.vs.rest.heartRateResidual",
                                      outcome: .heartRateResidual)
        func direction(calibrationDelta: Double) -> Bool? {
            let calibration = Self.finding(id: HypothesisRegistry.residualCalibrationId,
                                           outcome: .feeling, delta: calibrationDelta)
            let resolved = Engine.resolvingDirection(in: [calibration, physiology])
            return resolved.first { $0.hypothesis.outcome == .heartRateResidual }?.higherIsBetter
        }
        #expect(direction(calibrationDelta: 0.6) == true)
        #expect(direction(calibrationDelta: -0.6) == false)
    }

    /// The correction is one list, and the calibration is on it.
    ///
    /// Exempting it so that it cleared more easily would be the engine's own
    /// guardrail routed around from the inside, on the single claim everything else
    /// depends on. The price is that it costs the others a little power, and this
    /// pins that it is actually being charged.
    @Test("The calibration is corrected with everything else, as one more candidate")
    func theCalibrationPaysForItself() throws {
        let rows = Self.observations()
        let findings = Engine.findings(for: Self.input(rows), resamples: 200)
        #expect(findings.contains { $0.hypothesis.id == HypothesisRegistry.residualCalibrationId },
                "the calibration was not among the tested findings")

        // Benjamini–Hochberg's thresholds are k/m·q, so m is the whole list. Drop
        // the calibration and every remaining threshold loosens — which is the cost
        // being accepted, measured rather than asserted.
        let withCalibration = Engine.applyingCorrection(to: findings)
        let without = Engine.applyingCorrection(
            to: findings.filter { $0.hypothesis.id != HypothesisRegistry.residualCalibrationId })
        #expect(withCalibration.count == without.count + 1)

        let ranks = Dictionary(uniqueKeysWithValues: withCalibration.map {
            ($0.hypothesis.id, $0.comparison.pValue)
        })
        for finding in without {
            #expect(ranks[finding.hypothesis.id] == finding.comparison.pValue,
                    "removing the calibration changed another hypothesis's own estimate")
        }
    }

    // MARK: - What a confirmed calibration unlocks

    /// Checklist item 9. The finding is identical in both halves; only the
    /// direction differs, which is the whole claim of phase 2.
    @Test("A physiology finding is ineligible undirected and eligible once directed")
    func directionIsWhatMadePhysiologyUnreachable() {
        let undirected = Self.finding(id: "physiology.deep-work.vs.rest.heartRateResidual",
                                      outcome: .heartRateResidual, delta: 0.55)
        #expect(undirected.higherIsBetter == nil)
        #expect(!ExperimentDesign.isEligible(undirected), Comment(rawValue:
            "the filter this phase exists to open was already open"))

        var directed = undirected
        directed.direction = OutcomeDirection(residualHigherIsBetter: true)
        #expect(ExperimentDesign.isEligible(directed), Comment(rawValue:
            "a confirmed calibration did not make a favourable physiology finding eligible"))
        #expect(ExperimentDesign.standing(of: directed) == .confirmed)

        // Directed the other way, the focus side is the worse side, and adherence
        // is counted in days gained on the focus side — so it is correctly refused
        // again. A direction is not a licence; it is the information the existing
        // filters needed to be able to answer at all.
        var reversed = undirected
        reversed.direction = OutcomeDirection(residualHigherIsBetter: false)
        #expect(!ExperimentDesign.isEligible(reversed))
    }

    @Test("The recommendation filter reaches a physiology finding only once directed")
    func recommendationsReachPhysiologyOnlyOnceDirected() {
        // `Recommendations.build`'s own survivor gate, which is the line the PRD
        // names: `higherIsBetter != nil`. Asserted on the predicate rather than on
        // the output, because the sentence a directed physiology finding would get
        // is copy this phase deliberately does not author — `action(for:)` returns
        // nil for it, and the reason is written there.
        let undirected = Self.finding(id: "physiology.deep-work.vs.rest.heartRateResidual",
                                      outcome: .heartRateResidual, delta: 0.55)
        #expect(undirected.higherIsBetter == nil, "undirected is the state to beat")

        var directed = undirected
        directed.direction = OutcomeDirection(residualHigherIsBetter: false)
        #expect(directed.higherIsBetter == false, "directed, and directed downward")
        #expect(directed.isReportable, "the gate ahead of the direction filter must already pass")
    }

    /// The calibration directs; it is never itself a thing to act on.
    ///
    /// The only change that could add days to "sessions where your heart rate ran
    /// above your usual" is a change to a heart rate, and nothing in this app asks
    /// for one.
    @Test("The calibration itself is never a recommendation or an experiment")
    func theCalibrationIsNeverActedOn() {
        var calibration = Self.finding(id: HypothesisRegistry.residualCalibrationId,
                                       outcome: .feeling, delta: 0.6)
        calibration.direction = OutcomeDirection(residualHigherIsBetter: true)
        #expect(calibration.isReportable, "the fixture has to clear everything else to prove anything")
        #expect(calibration.higherIsBetter == true, "a feeling outcome is directed by definition")
        #expect(!ExperimentDesign.isEligible(calibration))

        let rows = Self.observations()
        let corrected = Engine.applyingCorrection(
            to: Engine.findings(for: Self.input(rows, priorities: [.movement, .calm, .energy]),
                                resamples: 400))
        let recommendations = Recommendations.build(
            from: corrected, input: Self.input(rows, priorities: [.movement, .calm, .energy]))
        #expect(!recommendations.contains {
            $0.insightId == Engine.identity(of: HypothesisRegistry.residualCalibrationId)
        }, "the calibration became a recommendation")

        let proposals = ExperimentDesign.proposals(
            from: corrected, input: Self.input(rows, priorities: [.movement, .calm, .energy]))
        #expect(!proposals.contains { $0.hypothesisId == HypothesisRegistry.residualCalibrationId },
                "the calibration became an experiment")
    }

    // MARK: - Copy

    @Test("The sentence is anchored on the higher side and takes its word from the evidence")
    func phrasingComesFromTheEvidence() throws {
        let rows = Self.observations()
        let hypothesis = try #require(Self.calibration(in: rows))

        func sentence(delta: Double) -> String {
            hypothesis.phrase(Self.finding(id: hypothesis.id, outcome: .feeling, delta: delta))
        }
        #expect(sentence(delta: -0.6)
                == "Sessions where your heart rate ran above your usual have felt more draining than your others.")
        #expect(sentence(delta: 0.6)
                == "Sessions where your heart rate ran above your usual have felt more energizing than your others.")

        // Both readings are anchored on the same side, so the sentence never has to
        // reach for the elliptical lower phrasing — and a reader is never invited to
        // treat the heart rate itself as the good or the bad thing.
        for delta in [-0.6, 0.6] {
            #expect(sentence(delta: delta).hasPrefix("Sessions where your heart rate ran above your usual"))
        }
    }

    /// Checklist item 11, over every string this phase can produce.
    @Test("No string names a direction as normal, expected or shared")
    func noDirectionIsCalledNormal() throws {
        let rows = Self.observations()
        let hypothesis = try #require(Self.calibration(in: rows))
        var strings = [hypothesis.caveat, hypothesis.focusLabel, hypothesis.baselineLabel]
        for delta in [-0.6, 0.6] {
            strings.append(hypothesis.phrase(
                Self.finding(id: hypothesis.id, outcome: .feeling, delta: delta)))
        }
        // And the sentences a real run publishes, which is where a claim and its
        // caveat actually meet a reader.
        for insight in Engine.run(Self.input(rows), resamples: 400) {
            strings += [insight.statement, insight.caveat, insight.experiment].compactMap { $0 }
        }

        let words = strings.joined(separator: " ").lowercased()
        // Two people can calibrate in opposite directions off identical data, and
        // that is correct rather than a bug — so no copy may suggest that one of the
        // two is the one to expect.
        for banned in ["normal", "typical", "expected", "usually", "most people",
                       "average", "others do", "than others", "as it should",
                       "healthy", "unhealthy", "abnormal", "unusual", "rare",
                       "unlike most", "elevated", "high heart rate", "low heart rate"] {
            #expect(!words.contains(banned), Comment(rawValue:
                "a direction was named \"\(banned)\": \(words)"))
        }
        // And nothing suggests moving the number itself.
        for banned in ["raise", "lower your", "bring it down", "get it up",
                       "should be", "aim for", "target"] {
            #expect(!words.contains(banned), Comment(rawValue:
                "copy about a heart rate said \"\(banned)\": \(words)"))
        }
        // The causal, clinical and population bans every sweep in this codebase
        // holds, applied here too.
        for banned in ["because", "causes", "caused", "due to", "leads to",
                       "makes you", "diagnos", "risk of", "stress", "strain"] {
            #expect(!words.contains(banned), Comment(rawValue:
                "\"\(banned)\" in calibration copy: \(words)"))
        }
    }
}
