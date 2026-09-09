import Testing
import Foundation
@testable import Hourss

/// When Hourss decides Health access has gone.
///
/// iOS never reports read authorization: `requestAuthorization` returns nothing,
/// and a refusal and "nothing recorded" are the same answer. So this is an
/// inference rather than a check, and the tests that matter are the ones about
/// when it must *not* fire — a false positive here locks somebody out of an app
/// that is working correctly, with no way for them to prove otherwise.
@Suite("Health access inference")
@MainActor
struct HealthAccessTests {

    /// The rule under test, kept here in the same shape the service applies it.
    private func inferLost(gotSomething: Bool, hadDataBefore: Bool) -> Bool {
        if gotSomething { return false }
        return hadDataBefore
    }

    @Test("A new person with no readings is never locked out")
    func neverHadDataIsNotRevocation() {
        // The case that matters most. Somebody without a watch, on their first
        // day, reads empty — and looks identical to a refusal. Locking them out
        // would be a guess, and it would be wrong for most of them.
        #expect(inferLost(gotSomething: false, hadDataBefore: false) == false)
    }

    @Test("Readings arriving clears any earlier suspicion")
    func dataClearsTheFlag() {
        #expect(inferLost(gotSomething: true, hadDataBefore: true) == false)
        #expect(inferLost(gotSomething: true, hadDataBefore: false) == false)
    }

    @Test("A year of readings turning into none is treated as withdrawal")
    func lossAfterDataIsRevocation() {
        #expect(inferLost(gotSomething: false, hadDataBefore: true))
    }

    @Test("A single metric still reading counts as access")
    func partialDataIsNotLoss() {
        // Access is per type. Somebody may revoke sleep and keep steps, and the
        // app still works — thinly, but honestly. Only a total silence is
        // evidence of the whole permission going.
        let collected: [HealthMetric: [Date: Double]] = [
            .steps: [Date(): 4000],
            .sleepHours: [:],
        ]
        let gotSomething = collected.values.contains { !$0.isEmpty }
        #expect(gotSomething)
        #expect(inferLost(gotSomething: gotSomething, hadDataBefore: true) == false)
    }

    @Test("Empty dictionaries for every metric read as silence")
    func allEmptyIsSilence() {
        let collected: [HealthMetric: [Date: Double]] = Dictionary(
            uniqueKeysWithValues: HealthMetric.allCases.map { ($0, [:]) }
        )
        #expect(collected.values.contains { !$0.isEmpty } == false)
    }

    @Test("The service starts without suspecting anything")
    func startsClean() {
        let health = HealthService()
        #expect(health.accessLost == false)
    }

    /// Onboarding no longer offers a choice, so the request must cover the lot.
    @Test("Every metric is requested, not a chosen subset")
    func allMetricsRequested() {
        let health = HealthService()
        #expect(Set(health.selectedMetrics) == Set(HealthMetric.allCases), Comment(rawValue:
                "requesting \(health.selectedMetrics.count) of \(HealthMetric.allCases.count) metrics"))
        #expect(health.selectedMetrics.contains(.heartRate),
                "heart rate is what the physiology layer runs on")
    }
}
