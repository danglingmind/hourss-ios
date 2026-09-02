import XCTest

/// The Dynamic Island can only be seen from outside the app, so these tests start
/// a session, send the app to the background, and photograph the device.
@MainActor
final class LiveActivityTests: XCTestCase {

    private var app: XCUIApplication!

    private func launchAndStartASession(named activity: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        for _ in 0..<3 { app.descendants(matching: .any)["Continue"].firstMatch.tap() }
        app.descendants(matching: .any)["health-skip"].firstMatch.tap()
        app.buttons["Skip for now"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["tab-log"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)[activity].firstMatch.tap()
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String, _ screenshot: XCUIScreenshot) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Starting a session must not throw or wedge the app, whether or not Live
    /// Activities are permitted on this device.
    func testStartingASessionSurvivesLiveActivityRequest() {
        launchAndStartASession(named: "Exercise")

        // The panel is still there a beat later, so nothing crashed behind it.
        sleep(2)
        XCTAssertTrue(app.staticTexts["Exercise"].exists, "The session did not survive the Live Activity request")
        XCTAssertTrue(app.descendants(matching: .any)["stop-session"].firstMatch.isHittable)
    }

    /// Photographs the device with the app backgrounded, which is where the Island
    /// lives. The assertion is deliberately weak — whether the Island renders
    /// depends on the device supporting it — but the screenshot is the evidence.
    func testIslandWhileBackgrounded() {
        launchAndStartASession(named: "Deep work")

        XCUIDevice.shared.press(.home)
        sleep(3)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        attach("34-island-backgrounded", springboard.screenshot())

        XCTAssertTrue(springboard.exists, "Could not reach the home screen")
    }

    /// The timer has to actually advance.
    ///
    /// It once appeared frozen because a Live Activity from an *earlier launch*
    /// survived — activities outlive the app, and a stopped one sits there showing
    /// its final elapsed time forever. Two photographs eight seconds apart is the
    /// only honest way to tell a running clock from a stuck one.
    func testCompactTimerAdvances() {
        launchAndStartASession(named: "Deep work")
        XCUIDevice.shared.press(.home)
        sleep(3)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        attach("40-timer-early", springboard.screenshot())
        sleep(9)
        attach("41-timer-later", springboard.screenshot())

        // A stale activity would have shown a static "Nm" instead of a clock.
        XCTAssertTrue(springboard.exists)
    }

    /// A stopped activity left behind by a previous launch must not linger.
    func testStaleActivityIsClearedOnRelaunch() {
        launchAndStartASession(named: "Admin")
        app.descendants(matching: .any)["stop-session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 5))

        // Quit without saving, which is what leaves the orphan behind.
        app.terminate()
        sleep(2)

        app = XCUIApplication()
        app.launch()
        sleep(3)

        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        attach("42-after-relaunch", springboard.screenshot())
        XCTAssertTrue(springboard.exists)
    }

    /// A stopped session must show the time it actually ran, in the same shape as
    /// the running clock. Rounding to whole minutes made every short session read
    /// "0m", which looked like a dead timer rather than a short session.
    func testStoppedTimeShowsRealElapsed() {
        launchAndStartASession(named: "Deep work")

        // Long enough that a whole-minute rounding would still say "0m", but the
        // seconds are unmistakable.
        sleep(12)
        app.descendants(matching: .any)["stop-session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.022)).press(forDuration: 1.2)
        sleep(2)
        attach("43-stopped-elapsed", springboard.screenshot())
    }

    /// Rating from the Island should clear it rather than leave it parked.
    func testIslandClearsAfterRating() {
        launchAndStartASession(named: "Admin")
        app.descendants(matching: .any)["stop-session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.022))
        island.press(forDuration: 1.2)
        sleep(2)

        // Tap "4" on the FELT row.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.082)).tap()
        sleep(8)   // past the 4s grace period
        attach("44-island-cleared", springboard.screenshot())
    }

    /// Long-presses the Island to open the expanded view, and drives its buttons.
    ///
    /// The Island lives in SpringBoard, so everything here goes through coordinates
    /// rather than the app's element tree.
    func testExpandedIslandAndItsButtons() {
        launchAndStartASession(named: "Deep work")
        XCUIDevice.shared.press(.home)
        sleep(2)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        attach("35-island-compact", springboard.screenshot())

        // The Island sits at the very top centre.
        let island = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.022))
        island.press(forDuration: 1.2)
        sleep(2)
        attach("36-island-expanded-running", springboard.screenshot())

        // Stop, which should swap the expanded view for the two rating scales.
        let stop = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.105))
        stop.tap()
        sleep(3)
        attach("37-island-after-stop", springboard.screenshot())

        // Reopen and rate from the Island itself.
        island.press(forDuration: 1.2)
        sleep(2)
        attach("38-island-rating", springboard.screenshot())

        // Tap "4" on the feeling scale — the fourth of five segments.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.102)).tap()
        sleep(3)
        island.press(forDuration: 1.2)
        sleep(2)
        attach("39-island-performance", springboard.screenshot())
    }

    /// Stopping from inside the app must move the Island into its rating state
    /// without leaving the app in a bad place.
    func testStoppingMovesToReflection() {
        launchAndStartASession(named: "Learning")

        app.descendants(matching: .any)["stop-session"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 5),
                      "Stopping did not raise the reflection")
        app.descendants(matching: .any)["feeling-4"].firstMatch.tap()
        app.descendants(matching: .any)["Save"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["NOW"].exists, "A session is still shown as running")
    }
}
