import XCTest

/// The account beat is a gate, and this is the only test that can see it.
///
/// Every other UI test launches with `-hourss-debug-account` and walks straight
/// through, because the Apple sheet belongs to another process and wants a real
/// Apple ID. That bypass is necessary and it is also a hole: with every test
/// signed in, nothing at all would notice if the gate stopped gating. So this one
/// launches without it and asserts the two things that make it a gate — the sheet
/// is offered, and there is no way onward.
@MainActor
final class AccountGateTests: XCTestCase {

    private var app: XCUIApplication!

    private func tapID(_ identifier: String) {
        app.descendants(matching: .any)[identifier].firstMatch.tapWhenReady()
    }

    private func reachBeat(_ number: Int) {
        XCTAssertTrue(app.staticTexts["\(number) / 9"].waitForExistence(timeout: UITest.timeout),
                      "Onboarding never reached beat \(number)")
    }

    /// Walks to beat seven signed out, which is as far as anyone can get.
    private func launchToTheGate() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithHistorySignedOut()

        tapID("Start")
        reachBeat(2)
        tapID("health-connect")
        reachBeat(3)
        tapID("priority-focus")
        for beat in 4...7 {
            tapID("Continue")
            reachBeat(beat)
        }
    }

    func testTheAccountBeatOffersAppleAndNothingElse() {
        launchToTheGate()

        // The button is the assertion. It is the only control the beat has, so its
        // presence says the beat arrived and says it more precisely than a wrapper
        // identifier would — which is just as well, since a wrapper identifier
        // would overwrite this one.
        let button = app.descendants(matching: .any)["sign-in-with-apple"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: UITest.timeout),
                      "The one control this screen exists for is missing")
        XCTAssertTrue(button.isHittable, "The button is on screen but cannot be tapped")
    }

    /// The whole claim of a hard gate: signed out, beat seven has no exit.
    ///
    /// Asserted as an absence rather than by trying to tap something, because the
    /// failure being guarded against is a Continue quietly reappearing — a tap
    /// test would pass just as happily by finding nothing to tap.
    func testThereIsNoWayPastTheGateWithoutSigningIn() {
        launchToTheGate()
        _ = app.descendants(matching: .any)["sign-in-with-apple"].firstMatch.waitForExistence(timeout: UITest.timeout)

        XCTAssertFalse(app.descendants(matching: .any)["Continue"].firstMatch.exists,
                       "The account beat must not offer a way forward to somebody who has not signed in")
        XCTAssertFalse(app.buttons["Skip for now"].firstMatch.exists,
                       "The last beat's skip must not be reachable from behind the gate")
        XCTAssertFalse(app.descendants(matching: .any)["account-signed-in"].firstMatch.exists,
                       "Nobody is signed in, so nothing may say they are")
    }
}
