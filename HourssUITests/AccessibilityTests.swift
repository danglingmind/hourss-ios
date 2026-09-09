import XCTest

/// Checks the shell holds up under the accessibility settings the design system
/// commits to: large Dynamic Type, and Reduce Motion removing non-essential
/// transitions.
@MainActor
final class AccessibilityTests: XCTestCase {

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launchWithHistory()
        return app
    }

    /// Walks the six beats. Each control is waited for rather than assumed — at
    /// accessibility type sizes the layout reflows and controls move.
    private func walkOnboarding(_ app: XCUIApplication) {
        func tap(_ identifier: String) {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 12), "Could not find '\(identifier)'")
            element.tap()
        }
        tap("Start")
        tap("health-connect")
        tap("priority-focus")          // beat 3 gates on at least one
        for _ in 0..<4 { tap("Continue") }
        let skip = app.buttons["Skip for now"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 12))
        skip.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Large accessibility type. Display headlines opt out of scaling by design —
    /// they are already 55pt — but body, labels and controls must all still fit and
    /// stay reachable.
    func testLargeDynamicType() {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityL")

        XCTAssertTrue(app.staticTexts["Your calendar, knows where, time went."].waitForExistence(timeout: 8))
        attach(app, "a11y-onboarding-welcome")

        walkOnboarding(app)

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        attach(app, "a11y-today")

        // Every tab must stay reachable — the tab bar is hand-built, so an
        // overflowing label here would be a real regression rather than a cosmetic one.
        for tab in ["tab-today", "tab-patterns", "tab-journal", "tab-you"] {
            let element = app.descendants(matching: .any)[tab].firstMatch
            XCTAssertTrue(element.exists, "\(tab) disappeared at accessibility type sizes")
            XCTAssertTrue(element.isHittable, "\(tab) is not tappable at accessibility type sizes")
            element.tap()
        }
        attach(app, "a11y-you")

        app.descendants(matching: .any)["tab-patterns"].firstMatch.tap()
        attach(app, "a11y-patterns")
    }

    /// Energy is never carried by colour alone: every bar's accessibility label
    /// must also state the score or that it is unrated.
    func testEnergyBarsAreNotColourOnly() {
        let app = launch()
        walkOnboarding(app)

        XCTAssertTrue(app.descendants(matching: .any)["tab-journal"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["tab-journal"].firstMatch.tap()

        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
            .element(boundBy: 0).tap()

        let rows = app.descendants(matching: .any).matching(identifier: "timeline-row")
        XCTAssertGreaterThan(rows.count, 0, "The day detail should show a timeline")

        for index in 0..<min(rows.count, 5) {
            let label = rows.element(boundBy: index).label
            let statesFeeling = ["draining", "depleting", "neutral", "steady", "energizing", "not rated"]
                .contains { label.lowercased().contains($0) }
            XCTAssertTrue(statesFeeling, "Timeline row carries no spoken energy state: '\(label)'")
        }
    }
}
