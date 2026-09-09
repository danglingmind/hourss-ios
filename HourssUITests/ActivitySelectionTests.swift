import XCTest

/// The activity starter set arrives fully selected, so tapping every row turns
/// them all *off*. With zero activities kept there is nothing to pick anywhere:
/// the first-log step is blank, Today loses its quick-start rows, and the + picker
/// has no rows and a permanently disabled Start — the app can no longer log
/// anything at all. These tests pin that door shut.
@MainActor
final class ActivitySelectionTests: XCTestCase {

    private var app: XCUIApplication!

    /// The standalone Activities step is gone — the starter set now lives on the
    /// final onboarding beat, where picking one starts a session rather than
    /// curating a list. The "keep at least one" gate went with it, so what remains
    /// worth guarding is the invariant underneath it: no picker may ever be empty,
    /// because an empty picker is a dead end with no route back to logging.
    private func launchToStartBeat() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithHistory()
        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        app.descendants(matching: .any)["health-connect"].firstMatch.tap()
        // Beat 3 ranks priorities and gates Continue on at least one.
        let focus = app.descendants(matching: .any)["priority-focus"].firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 10))
        focus.tap()
        for _ in 0..<4 {
            let next = app.descendants(matching: .any)["Continue"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            next.tap()
        }
        XCTAssertTrue(app.buttons["Skip for now"].firstMatch.waitForExistence(timeout: 10))
    }

    /// The final beat offers the whole starter set.
    func testStartBeatOffersTheStarterSet() {
        launchToStartBeat()
        for activity in ["Deep work", "Meetings", "Admin", "Learning", "Creative", "Exercise", "Social", "Personal / Rest"] {
            XCTAssertTrue(app.descendants(matching: .any)[activity].firstMatch.exists,
                          "\(activity) is missing from the starter set")
        }
    }

    /// Picking one there starts a session and lands in the app.
    func testPickingAnActivityStartsASession() {
        launchToStartBeat()
        app.descendants(matching: .any)["Exercise"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: 5),
                      "Picking an activity should have started it running")
        XCTAssertTrue(app.staticTexts["Exercise"].exists)
    }

    /// The log picker always has rows to choose from.
    func testLogPickerIsNeverEmpty() {
        launchToStartBeat()
        app.buttons["Skip for now"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["tab-log"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Deep work"].firstMatch.exists,
                      "The picker has no rows to choose from")

        app.descendants(matching: .any)["Deep work"].firstMatch.tap()
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: 5), "Start did nothing")
    }
}
