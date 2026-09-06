import Testing
import Foundation
@testable import Hourss

/// The seeded demo has to survive the engine that judges it.
///
/// The demo history was tuned against an engine that would claim almost anything;
/// the current one requires an interval clear of zero, a non-negligible near edge,
/// and survival of the correction. A demo with an empty Patterns screen is not a
/// failing test so much as a broken product, and six UI tests assert a lead
/// insight exists — so this catches it in two seconds rather than nine minutes.
@Suite("Seeded demo")
@MainActor
struct DemoDataTests {

    @Test("The demo has observations to show")
    func demoProducesInsights() {
        let store = HourssStore()
        MockData.seed(into: store)
        #expect(!store.visibleInsights.isEmpty, Comment(rawValue:
                "the seeded demo produced no visible observation; " +
                "\(store.insights.count) were computed and none survived the bands"))
    }

    @Test("The demo's observations carry real evidence")
    func demoInsightsAreWellFormed() {
        let store = HourssStore()
        MockData.seed(into: store)
        for insight in store.visibleInsights {
            #expect(insight.evidence.comparisonCount > 0)
            #expect(insight.evidence.baselineCount > 0)
            #expect(!insight.caveat.isEmpty)
            #expect(!store.sessions(for: insight).isEmpty,
                    "an observation cites sessions the store cannot find")
        }
    }
}
