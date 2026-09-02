import XCTest

/// Logging an hour that already happened. The honest case is the common one —
/// you were too busy to log it while it was going on.
@MainActor
final class PastSessionTests: XCTestCase {

    private var app: XCUIApplication!

    private func launchToToday() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: 8))
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        for _ in 0..<3 { app.descendants(matching: .any)["Continue"].firstMatch.tap() }
        app.descendants(matching: .any)["health-skip"].firstMatch.tap()   // O6
        app.buttons["Skip for now"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
    }

    private func openSheet() {
        app.descendants(matching: .any)["tab-log"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: 5))
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The sheet still opens on "Start now", so the existing habit is unchanged.
    func testDefaultsToStartingNow() {
        launchToToday()
        openSheet()

        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.exists,
                      "The primary action should still read Start")
        XCTAssertFalse(app.descendants(matching: .any)["slot-start"].firstMatch.exists,
                       "The time slot should stay out of the way until it is asked for")
        attach("24-start-session-now")
    }

    /// Switching to past time reveals the slot, pre-set to the hour just gone.
    func testPastModeShowsAnHourLongSlot() {
        launchToToday()
        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["slot-start"].firstMatch.waitForExistence(timeout: 5),
                      "No start-time slider")
        XCTAssertTrue(app.descendants(matching: .any)["slot-duration"].firstMatch.exists,
                      "No duration slider")
        XCTAssertTrue(app.staticTexts["1h"].exists, "The slot should default to an hour")
        XCTAssertTrue(app.descendants(matching: .any)["Log it"].firstMatch.exists,
                      "The action should say what it does in this mode")
        attach("25-start-session-past")
    }

    /// The sliders move the slot, and the readout follows.
    func testSlidersChangeTheSlot() {
        launchToToday()
        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["slot-duration"].firstMatch.waitForExistence(timeout: 5))

        // Drive the real control rather than the accessibility proxy: the track is
        // draggable along its whole width, which is what a finger actually does.
        let duration = app.descendants(matching: .any)["slot-duration"].firstMatch
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.35)).tap()

        XCTAssertTrue(app.staticTexts["15m"].waitForExistence(timeout: 3),
                      "Dragging the duration slider to its minimum did not update the readout")
        XCTAssertFalse(app.staticTexts["1h"].exists, "The old duration is still showing")
        attach("26-start-session-slot-adjusted")

        // And back out to a longer slot.
        duration.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.35)).tap()
        XCTAssertFalse(app.staticTexts["15m"].exists, "The slider only moves one way")
    }

    /// The whole point: a past slot becomes a real, rated session in the record.
    func testLoggingPastTimeLandsInTheRecordWithARating() {
        launchToToday()

        let rowsBefore = app.descendants(matching: .any).matching(identifier: "timeline-row").count

        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["slot-start"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["Exercise"].firstMatch.tap()
        app.descendants(matching: .any)["Log it"].firstMatch.tap()

        // The spec asks for the reflection immediately after a backdated save.
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 8),
                      "Saving a past session did not raise the reflection sheet")
        attach("27-past-session-reflection")
        app.descendants(matching: .any)["feeling-5"].firstMatch.tap()
        app.descendants(matching: .any)["Save"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        let rowsAfter = app.descendants(matching: .any).matching(identifier: "timeline-row").count
        XCTAssertEqual(rowsAfter, rowsBefore + 1, "The backdated session is missing from Today")
        XCTAssertTrue(app.staticTexts["Exercise"].exists, "The logged activity is not in the record")

        // And it is a finished session, not a running one.
        XCTAssertFalse(app.staticTexts["NOW"].exists,
                       "Backdating should not leave a timer running")
        attach("28-today-after-past-session")
    }

    /// Backdating an earlier hour must not stop what you are doing right now.
    func testLoggingPastTimeLeavesARunningSessionAlone() {
        launchToToday()

        openSheet()
        app.descendants(matching: .any)["Deep work"].firstMatch.tap()
        app.descendants(matching: .any)["Start"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: 5))

        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["slot-start"].firstMatch.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["Admin"].firstMatch.tap()
        app.descendants(matching: .any)["Log it"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: 8))
        app.descendants(matching: .any)["feeling-2"].firstMatch.tap()
        app.descendants(matching: .any)["Save"].firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["NOW"].exists,
                      "Backdating stopped the session that was still running")
    }
}
