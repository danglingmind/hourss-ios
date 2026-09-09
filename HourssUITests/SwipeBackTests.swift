import XCTest

/// Every detail screen hides the system back button in favour of its own header,
/// which is exactly what makes UIKit drop the interactive pop gesture. These tests
/// prove the gesture is back on each pushed screen, and that it does not fire at
/// the root of a stack where there is nothing to pop.
@MainActor
final class SwipeBackTests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Setup

    /// Launches and walks past onboarding. Called at the top of each test rather
    /// than from `setUp`, which XCTest keeps nonisolated.
    ///
    /// The old version fired four blind taps at Continue with nothing between them.
    /// Each beat is a state change the app has to finish first — the Health beat
    /// awaits a read of a year of history before it advances — so on a loaded
    /// machine a tap arrived before its screen, was dropped, and the flow stalled
    /// several beats back. The header's "n / 7" counter is the app's own statement
    /// of which beat it is on, so each tap waits for that number to move before the
    /// next one is sent.
    private func launchPastOnboarding() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        tapID("Start")
        reachBeat(2)
        // Health is asked for at beat two and there is no way past it but through.
        tapID("health-connect")
        reachBeat(3)
        // Beat 3 ranks priorities and gates Continue on at least one.
        tapID("priority-focus")
        for beat in 4...7 {
            tapID("Continue")
            reachBeat(beat)
        }
        tapID("Skip for now")

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
    }

    private func reachBeat(_ number: Int) {
        XCTAssertTrue(app.staticTexts["\(number) / 7"].waitForExistence(timeout: UITest.timeout),
                      "Onboarding never reached beat \(number)")
    }

    // MARK: - Helpers

    /// A drag from the very left edge, which is what the pop recogniser listens for.
    private func swipeFromLeftEdge() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Waits for the pushed screen to arrive *and* stop moving, then drags.
    ///
    /// The destination exists and is hittable well before it has finished sliding
    /// in, and an edge drag begun against a moving view is absorbed by the
    /// transition instead of starting a pop — which reads exactly like a gesture
    /// that was never installed. The marker is something only the destination
    /// owns, so its arrival is still asserted here rather than assumed.
    private func swipeBack(from marker: XCUIElement) {
        XCTAssertTrue(marker.waitForExistence(timeout: UITest.timeout), "The pushed screen never appeared")
        marker.waitUntilStill()
        swipeFromLeftEdge()
    }

    private func tapID(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: UITest.timeout), "Could not find '\(identifier)'")
        element.tapWhenReady()
    }

    // MARK: - Tests

    func testSwipeBackFromInsightDetail() {
        launchPastOnboarding()
        tapID("tab-patterns")
        tapID("lead-insight")

        swipeBack(from: app.staticTexts["An observation, not a rule."])

        XCTAssertTrue(
            app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: UITest.timeout),
            "Edge swipe did not pop the insight detail"
        )
    }

    func testSwipeBackFromDayDetail() {
        launchPastOnboarding()
        tapID("tab-journal")
        let days = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
        XCTAssertTrue(days.waitForFirstMatch(), "The journal listed no days to open")
        days.element(boundBy: 0).tapWhenReady()

        swipeBack(from: app.staticTexts["Journal"])

        XCTAssertTrue(
            app.staticTexts["JOURNAL"].waitForExistence(timeout: UITest.timeout),
            "Edge swipe did not pop the day detail"
        )
    }

    func testSwipeBackFromSettingsScreens() {
        launchPastOnboarding()
        tapID("tab-you")

        tapID("row-preferences")
        swipeBack(from: app.staticTexts["Quiet mode"])
        XCTAssertTrue(
            app.descendants(matching: .any)["row-preferences"].firstMatch.waitForExistence(timeout: UITest.timeout),
            "Edge swipe did not pop Preferences"
        )

        tapID("row-privacy")
        swipeBack(from: app.staticTexts["Export everything"])
        XCTAssertTrue(
            app.descendants(matching: .any)["row-privacy"].firstMatch.waitForExistence(timeout: UITest.timeout),
            "Edge swipe did not pop Privacy & data"
        )
    }

    /// At the root there is nothing to pop. Without a delegate saying so, the
    /// gesture still fires and can wedge the navigation controller.
    func testSwipingAtStackRootIsHarmless() {
        launchPastOnboarding()
        tapID("tab-patterns")

        swipeBack(from: app.descendants(matching: .any)["lead-insight"].firstMatch)

        XCTAssertTrue(
            app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: UITest.timeout),
            "Swiping at the stack root left Patterns in a broken state"
        )
        // And the screen is still live afterwards.
        tapID("lead-insight")
        XCTAssertTrue(app.staticTexts["An observation, not a rule."].waitForExistence(timeout: UITest.timeout))
    }
}
