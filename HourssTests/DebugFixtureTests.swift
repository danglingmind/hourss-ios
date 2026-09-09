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
        let store = HourssStore()
        DebugFixture.seed(into: store)
        #expect(!store.visibleInsights.isEmpty, Comment(rawValue:
                "the fixture produced no visible observation; " +
                "\(store.insights.count) were computed and none survived the bands"))
    }

    @Test("The fixture's observations carry real evidence")
    func demoInsightsAreWellFormed() {
        let store = HourssStore()
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
