import Foundation
import Testing
@testable import Hourss

/// Phase 3: an experiment measured on the heart-rate residual, which needs nobody
/// to rate anything — and the amendment to what licenses a direction at all.
@Suite("Residual experiment")
struct ResidualExperimentTests {

    private func physiology(delta: Double = 0.42, low: Double? = nil, high: Double? = nil,
                            days: Int = 20, survives: Bool? = true,
                            direction: Bool?) -> Finding {
        var finding = Finding(
            hypothesis: Hypothesis(
                id: "physiology.deep-work.vs.rest.heartRateResidual",
                type: .bodyContext, outcome: .heartRateResidual,
                focusLabel: "Deep work", baselineLabel: "Your other sessions",
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "During deep work, your heart rate has run above your usual." },
                caveat: HypothesisRegistry.residualCaveat
            ),
            comparison: Statistics.Comparison(
                delta: delta, low: low ?? (delta - 0.18), high: high ?? (delta + 0.18),
                focusCount: days, baselineCount: days,
                focusDays: days, baselineDays: days, pValue: 0.004
            ),
            focusSessionIds: [], baselineSessionIds: [],
            focusCoverage: 0.8, baselineCoverage: 0.8,
            survivesCorrection: survives, windowDays: 42
        )
        finding.direction = OutcomeDirection(residualHigherIsBetter: direction)
        return finding
    }

    // MARK: The unlock

    @Test("A directed physiology claim can now become an experiment, and carries a change")
    func theRoadIsPaved() throws {
        // Direction gates the *gate*; it is not what produces the sentence.
        let undirected = physiology(direction: nil)
        #expect(!ExperimentDesign.isEligible(undirected))

        let directed = physiology(direction: true)
        #expect(ExperimentDesign.isEligible(directed))

        // And the gate opening is not enough on its own. Before phase 3 this
        // returned nil for every physiology finding — both arms of `.bodyContext`
        // went looking for a `HealthMetric` and a physiology id's subject is an
        // activity slug — so a newly-admitted claim was silently skipped and the
        // unlock bought nothing.
        let change = try #require(ExperimentCopy.change(for: directed))
        #expect(change.contains("Deep work"))
        #expect(ExperimentCopy.change(type: .bodyContext, focusLabel: "Deep work",
                                      metric: nil, outcome: .feeling) == nil)
    }

    /// The thing that makes this worth having at all.
    @Test("The change says it needs no ratings, because it does not")
    func itAsksLessRatherThanMore() throws {
        let change = try #require(ExperimentCopy.change(for: physiology(direction: true)))
        #expect(change.contains("heart rate"))
        #expect(change.contains("no ratings"))
    }

    @Test("A directed physiology claim also becomes a recommendation")
    func recommendationsReachItToo() throws {
        let directed = physiology(direction: true)
        let input = EngineInput(observations: [], priorities: [.movement, .calm])
        // `.bodyContext` is what `movement` and `calm` map to.
        let recommendations = Recommendations.build(from: [directed], input: input)
        let first = try #require(recommendations.first)
        #expect(first.action.contains("Deep work"))
        // The lever is the activity. Nothing suggests moving a heart rate.
        for banned in ["lower", "raise", "reduce", "bring down", "get your heart"] {
            #expect(!first.action.lowercased().contains(banned),
                    Comment(rawValue: "a physiology action asked for a heart rate: \(first.action)"))
        }
    }

    @Test("Directed the other way, the sentence turns with it")
    func directionTurnsTheSentence() throws {
        let input = EngineInput(observations: [], priorities: [.movement])
        func action(_ higherIsBetter: Bool) throws -> String {
            let finding = physiology(direction: higherIsBetter)
            return try #require(Recommendations.build(from: [finding], input: input).first).action
        }
        #expect(try action(true).contains("closest to"))
        #expect(try action(false).contains("furthest from"))
    }

    // MARK: Figures carry their unit

    @Test("A residual result is in bpm, signed, and a rating result is not")
    func figuresKnowWhatTheyAre() {
        func result(_ outcome: Outcome, focus: Double, baseline: Double) -> String {
            var e = Experiment(
                hypothesisId: "physiology.deep-work.vs.rest.heartRateResidual",
                outcome: outcome, startedAt: Date(),
                focusLabel: "Deep work", baselineLabel: "Your other sessions",
                premise: "p", change: "c", caveat: "v")
            e.settlement = Experiment.Settlement(
                verdict: .heldUp, adherenceDays: 9, baselineDays: 12,
                focusFigure: focus, baselineFigure: baseline,
                delta: 0.4, intervalLow: 0.1, intervalHigh: 0.7, settledAt: Date())
            return ExperimentCopy.result(for: e, settlement: e.settlement!)
        }

        // A bare "4.2" against "3.4" reads as a rating on a five-point scale. It is
        // beats per minute above this person's own usual, which is a different
        // quantity out by a factor nobody could see.
        let bpm = result(.heartRateResidual, focus: 4.2, baseline: -1.5)
        #expect(bpm.contains("4.2 bpm above your usual"))
        #expect(bpm.contains("1.5 bpm below your usual"))

        // The sign is a real answer, not a formatting detail.
        #expect(result(.heartRateResidual, focus: -2.0, baseline: 0.0).contains("2.0 bpm below"))
        #expect(result(.heartRateResidual, focus: 0.0, baseline: 3.0).contains("your usual"))

        // And a rating is untouched.
        let rating = result(.feeling, focus: 4.2, baseline: 3.4)
        #expect(rating.contains("4.2"))
        #expect(!rating.contains("bpm"))
    }

    // MARK: The direction's own bar

    @Test("An invisible calibration directs nothing")
    func aDirectionMustBeArguable() {
        func calibration(low: Double, high: Double) -> Finding {
            var f = Finding(
                hypothesis: Hypothesis(
                    id: HypothesisRegistry.residualCalibrationId,
                    type: .bodyContext, outcome: .feeling,
                    focusLabel: "Above your usual", baselineLabel: "Below your usual",
                    focus: { _ in true }, baseline: { _ in false },
                    phrase: { _ in "" }, caveat: HypothesisRegistry.residualCaveat),
                comparison: Statistics.Comparison(
                    delta: (low + high) / 2, low: low, high: high,
                    focusCount: 30, baselineCount: 30,
                    focusDays: 15, baselineDays: 15, pValue: 0.004),
                focusSessionIds: [], baselineSessionIds: [],
                focusCoverage: 0.8, baselineCoverage: 0.8,
                survivesCorrection: true, windowDays: 42)
            f.direction = .uncalibrated
            return f
        }

        // Clear of zero and plainly visible: it directs.
        let visible = calibration(low: 0.30, high: 0.62)
        #expect(visible.isReportable)
        #expect(OutcomeDirection.resolved(from: [visible]).higherIsBetter(.heartRateResidual) == true)

        // Clear of zero and below the band the feed shows: reportable, and it must
        // still direct nothing. A direction reorients every physiology claim this
        // person sees, so one resting on a sentence they were never shown is a
        // premise they cannot disagree with — the one thing this engine is built to
        // allow.
        // Past Cliff's negligible band, so `isReportable` holds, with a near edge
        // almost on zero so the confidence ramp puts it under the visible floor.
        let invisible = calibration(low: 0.002, high: 0.42)
        #expect(invisible.isReportable)
        #expect(Confidence.band(Engine.confidence(invisible.comparison)) == .internalOnly)
        #expect(OutcomeDirection.resolved(from: [invisible]).higherIsBetter(.heartRateResidual) == nil)
    }

    @Test("Every string this phase authors is allowed on screen")
    func copyPassesTheGuard() throws {
        var strings = [try #require(ExperimentCopy.change(for: physiology(direction: true)))]
        let input = EngineInput(observations: [], priorities: [.movement])
        for higher in [true, false] {
            let finding = physiology(direction: higher)
            strings.append(try #require(Recommendations.build(from: [finding], input: input).first).action)
        }
        for text in strings {
            let offence = NarrationGuard.offence(in: text,
                                                 allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }
}
