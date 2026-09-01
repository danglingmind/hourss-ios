import XCTest

/// Every detail screen hides the system back button in favour of its own header,
/// which is exactly what makes UIKit drop the interactive pop gesture. These tests
/// prove the gesture is back on each pushed screen, and that it does not fire at
/// the root of a stack where there is nothing to pop.
@MainActor
final class SwipeBackTests: XCTestCase {

    private var app: XCUIApplication!

    /// Launches and walks past onboarding. Called at the top of each test rather
    /// than from `setUp`, which XCTest keeps nonisolated.
    private func launchPastOnboarding() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        for _ in 0..<3 { app.descendants(matching: .any)["Continue"].firstMatch.tap() }
        app.buttons["Skip for now"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
    }

    /// A drag from the very left edge, which is what the pop recogniser listens for.
    private func swipeFromLeftEdge() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func tapID(_ identifier: String) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Could not find '\(identifier)'")
        element.tap()
    }

    func testSwipeBackFromInsightDetail() {
        launchPastOnboarding()
        tapID("tab-patterns")
        tapID("lead-insight")
        XCTAssertTrue(app.staticTexts["An observation, not a rule."].waitForExistence(timeout: 5))

        swipeFromLeftEdge()

        XCTAssertTrue(
            app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: 5),
            "Edge swipe did not pop the insight detail"
        )
    }

    func testSwipeBackFromDayDetail() {
        launchPastOnboarding()
        tapID("tab-journal")
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
            .element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Journal"].waitForExistence(timeout: 5))

        swipeFromLeftEdge()

        XCTAssertTrue(
            app.staticTexts["JOURNAL"].waitForExistence(timeout: 5),
            "Edge swipe did not pop the day detail"
        )
    }

    func testSwipeBackFromSettingsScreens() {
        launchPastOnboarding()
        tapID("tab-you")

        tapID("row-preferences")
        XCTAssertTrue(app.staticTexts["Quiet mode"].waitForExistence(timeout: 5))
        swipeFromLeftEdge()
        XCTAssertTrue(
            app.descendants(matching: .any)["row-preferences"].firstMatch.waitForExistence(timeout: 5),
            "Edge swipe did not pop Preferences"
        )

        tapID("row-privacy")
        XCTAssertTrue(app.staticTexts["Export everything"].waitForExistence(timeout: 5))
        swipeFromLeftEdge()
        XCTAssertTrue(
            app.descendants(matching: .any)["row-privacy"].firstMatch.waitForExistence(timeout: 5),
            "Edge swipe did not pop Privacy & data"
        )
    }

    /// At the root there is nothing to pop. Without a delegate saying so, the
    /// gesture still fires and can wedge the navigation controller.
    func testSwipingAtStackRootIsHarmless() {
        launchPastOnboarding()
        tapID("tab-patterns")
        XCTAssertTrue(app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: 8))

        swipeFromLeftEdge()

        XCTAssertTrue(
            app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: 5),
            "Swiping at the stack root left Patterns in a broken state"
        )
        // And the screen is still live afterwards.
        tapID("lead-insight")
        XCTAssertTrue(app.staticTexts["An observation, not a rule."].waitForExistence(timeout: 5))
    }
}
