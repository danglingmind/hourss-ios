import Testing
import Foundation
@testable import Hourss

/// The debug fixture has to survive the engine that judges it.
///
/// It is not the product — nothing generates a session in a shipped build — but
/// it is what the UI suite walks and what anybody looking at the app with data
/// in it sees, so a fixture the engine finds nothing in is a broken tool.
///
/// The history was tuned against an engine that would claim almost anything;
/// the current one requires an interval clear of zero, a non-negligible near edge,
/// and survival of the correction. A demo with an empty Patterns screen is not a
/// failing test so much as a broken product, and six UI tests assert a lead
/// insight exists — so this catches it in two seconds rather than nine minutes.
@Suite("Debug fixture")
@MainActor
struct DemoDataTests {

    @Test("The fixture produces observations")
    func demoProducesInsights() {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)
        #expect(!store.visibleInsights.isEmpty, Comment(rawValue:
                "the fixture produced no visible observation; " +
                "\(store.insights.count) were computed and none survived the bands"))
    }

    /// Checklist item 13, and the one assertion in this file that is about a *chain*
    /// rather than about a screen.
    ///
    /// A direction is nil until somebody's own calibration confirms, so on a
    /// fixture whose heart rate and whose ratings are unrelated — which is what the
    /// seeded feed was — the whole `physiology.*` family stays exactly as
    /// unreachable as it was before direction existed, and nobody can look at the
    /// thing that was built. Three features have already shipped behind that hole
    /// here, most recently one that looked broken because a real Health read was
    /// wiping the fixture. A card nobody can get to is a card nobody reviews.
    @Test("The fixture produces a confirmed calibration, so direction is reachable")
    func fixtureCalibrates() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)

        let scored = store.engineObservations.filter { $0.heartRateResidual != nil }
        #expect(scored.count >= 12, Comment(rawValue:
            "only \(scored.count) of \(store.engineObservations.count) rows carry a residual; "
                + "the calibration cannot be tested below twelve"))

        let corrected = Engine.applyingCorrection(
            to: Engine.findings(for: EngineInput(observations: store.engineObservations,
                                                priorities: store.profile.priorities),
                                resamples: 400))
        let calibration = try #require(
            corrected.first { $0.hypothesis.id == HypothesisRegistry.residualCalibrationId },
            "the fixture never even tested the calibration")
        #expect(calibration.isReportable, Comment(rawValue:
            "the fixture's calibration did not confirm, so nothing downstream is directed: "
                + "delta \(calibration.comparison.delta), interval "
                + "[\(calibration.comparison.low), \(calibration.comparison.high)], "
                + "days \(calibration.comparison.focusDays)/\(calibration.comparison.baselineDays), "
                + "correction \(String(describing: calibration.survivesCorrection))"))

        // Which way round it came out is the generator's planted link read back, not
        // a number written down: a session rated draining runs above this person's
        // own curve, so higher is worse for them.
        #expect(calibration.direction.residualHigherIsBetter == false)
        for finding in corrected where finding.hypothesis.outcome == .heartRateResidual {
            #expect(finding.higherIsBetter == false, Comment(rawValue:
                "\(finding.hypothesis.id) is still undirected after a confirmed calibration"))
        }
    }

    @Test("The fixture's observations carry real evidence")
    func demoInsightsAreWellFormed() {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)
        for insight in store.visibleInsights {
            #expect(insight.evidence.comparisonCount > 0)
            #expect(insight.evidence.baselineCount > 0)
            #expect(!insight.caveat.isEmpty)
            #expect(!store.sessions(for: insight).isEmpty,
                    "an observation cites sessions the store cannot find")
        }
    }
}
