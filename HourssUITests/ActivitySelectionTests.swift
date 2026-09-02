import XCTest

/// The activity starter set arrives fully selected, so tapping every row turns
/// them all *off*. With zero activities kept there is nothing to pick anywhere:
/// the first-log step is blank, Today loses its quick-start rows, and the + picker
/// has no rows and a permanently disabled Start — the app can no longer log
/// anything at all. These tests pin that door shut.
@MainActor
final class ActivitySelectionTests: XCTestCase {

    private var app: XCUIApplication!

    private let starterActivities = [
        "Deep work", "Meetings", "Admin", "Learning",
        "Creative", "Exercise", "Social", "Personal / Rest",
    ]

    private func launchToActivities() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        app.descendants(matching: .any)["Continue"].firstMatch.tap()   // O2
        app.descendants(matching: .any)["Continue"].firstMatch.tap()   // O3
        XCTAssertTrue(app.descendants(matching: .any)["Deep work"].firstMatch.waitForExistence(timeout: 5))
    }

    private func deselectAll() {
        for name in starterActivities {
            app.descendants(matching: .any)[name].firstMatch.tap()
        }
    }

    /// Turning everything off must not let you walk into an empty first-log step.
    func testCannotContinuePastActivitiesWithNoneKept() {
        launchToActivities()
        deselectAll()

        XCTAssertTrue(
            app.staticTexts["Keep at least one — you can change these later."].exists,
            "No explanation shown when every activity is turned off"
        )

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "23-onboarding-activities-none-kept"
        shot.lifetime = .keepAlways
        add(shot)

        app.descendants(matching: .any)["Continue"].firstMatch.tap()

        // Still on the activities step, not stranded on a blank first-log screen.
        XCTAssertTrue(
            app.descendants(matching: .any)["Deep work"].firstMatch.exists,
            "Continue advanced past the activities step with nothing kept"
        )
    }

    /// Keeping a single activity is enough, and that is what the first-log step offers.
    func testKeepingOneActivityCarriesThrough() {
        launchToActivities()
        deselectAll()
        app.descendants(matching: .any)["Exercise"].firstMatch.tap()

        app.descendants(matching: .any)["Continue"].firstMatch.tap()
        app.descendants(matching: .any)["health-skip"].firstMatch.tap()   // O6

        XCTAssertTrue(
            app.descendants(matching: .any)["Exercise"].firstMatch.waitForExistence(timeout: 5),
            "The kept activity is missing from the first-log step"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["Deep work"].firstMatch.exists,
            "A discarded activity is still being offered"
        )
    }

    /// Even if zero favourites is reached some other way, no picker may be empty —
    /// an empty picker is a dead end with no route back to logging.
    func testLogPickerIsNeverEmpty() {
        launchToActivities()
        deselectAll()
        app.descendants(matching: .any)["Social"].firstMatch.tap()
        app.descendants(matching: .any)["Continue"].firstMatch.tap()
        app.descendants(matching: .any)["health-skip"].firstMatch.tap()   // O6
        app.buttons["Skip for now"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["tab-log"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: 5))
        // Match by identifier: a simple SwiftUI button absorbs its label, so the
        // row is a button named "Social", not a separate static text.
        XCTAssertTrue(app.descendants(matching: .any)["Social"].firstMatch.exists,
                      "The picker has no rows to choose from")

        // And Start actually works from here.
        app.descendants(matching: .any)["Social"].firstMatch.tap()
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: 5), "Start did nothing")
    }
}
