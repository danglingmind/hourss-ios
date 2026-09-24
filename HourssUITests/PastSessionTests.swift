import XCTest

/// Logging an hour that already happened. The honest case is the common one —
/// you were too busy to log it while it was going on.
@MainActor
final class PastSessionTests: XCTestCase {

    private var app: XCUIApplication!

    private func launchToToday() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithHistory()
        // launch() returns when the process is up, which is before the first
        // frame. Saying so here means a launch that never lands fails as a
        // launch, rather than as whatever query happens to run next.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")

        app.descendants(matching: .any)["Start"].firstMatch.tapWhenReady()
        // Health is asked for at beat two and there is no way past it but through.
        app.descendants(matching: .any)["health-connect"].firstMatch.tapWhenReady()
        // Beat 3 ranks priorities and gates Continue on at least one.
        app.descendants(matching: .any)["priority-focus"].firstMatch.tapWhenReady()

        // "Continue" is the same element on four consecutive beats, so waiting
        // for it to exist again cannot tell a beat that moved from a tap the
        // transition swallowed. The header counts the beats; wait on that.
        // Beat 7 is the account gate, which the launch argument has already
        // been through, so it carries an ordinary Continue like the rest.
        for beat in 4...9 {
            app.descendants(matching: .any)["Continue"].firstMatch.tapWhenReady()
            XCTAssertTrue(app.staticTexts["\(beat) / 9"].waitForExistence(timeout: UITest.timeout),
                          "Onboarding did not reach beat \(beat)")
        }

        app.buttons["Skip for now"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
    }

    private func openSheet() {
        app.descendants(matching: .any)["tab-log"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: UITest.timeout))
    }

    /// A test that failed because the app was gone is not the same news as a
    /// test that failed on what it asserted, and in a report the two look
    /// alike. The unit tests are hosted in this same app, so another run
    /// sharing this simulator terminates it out from under us — which no
    /// amount of waiting here can survive, and which should not be mistaken
    /// for a regression.
    override func tearDown() {
        if testRun?.hasSucceeded == false, let app, app.state != .runningForeground {
            XCTContext.runActivity(named: "The app was not running when this test ended — check whether another run was sharing this simulator") { _ in }
        }
        super.tearDown()
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
        XCTAssertFalse(app.descendants(matching: .any)["slot-picker"].firstMatch.exists,
                       "The time slot should stay out of the way until it is asked for")
        attach("24-start-session-now")
    }

    /// Switching to past time reveals the slot, pre-set to the hour just gone.
    func testPastModeShowsAnHourLongSlot() {
        launchToToday()
        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tapWhenReady()

        XCTAssertTrue(app.descendants(matching: .any)["slot-picker"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "No slot picker")
        XCTAssertTrue(app.descendants(matching: .any)["preset-60"].firstMatch.exists,
                      "No one-hour preset")
        XCTAssertTrue(app.staticTexts["1h"].exists, "The slot should default to an hour")
        XCTAssertTrue(app.descendants(matching: .any)["Log it"].firstMatch.exists,
                      "The action should say what it does in this mode")
        attach("25-start-session-past")
    }

    /// A preset sets the slot in one tap, and the readout follows.
    ///
    /// This replaced two sliders. The common case for backdating is always the
    /// same shape — something that ended just now and ran about so long — and it
    /// used to take two drags on a sixty-four-step track to say so.
    func testPresetsChangeTheSlot() {
        launchToToday()
        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tapWhenReady()

        let half = app.descendants(matching: .any)["preset-30"].firstMatch
        XCTAssertTrue(half.waitForExistence(timeout: UITest.timeout), "No half-hour preset")
        half.tapWhenReady()

        XCTAssertTrue(app.staticTexts["30m"].waitForExistence(timeout: UITest.timeout),
                      "Tapping the half-hour preset did not update the readout")
        XCTAssertFalse(app.staticTexts["1h"].exists, "The old duration is still showing")
        attach("26-start-session-slot-adjusted")

        // And back out. Each preset is a whole slot rather than a nudge, so the
        // readout has to land exactly on the one that was asked for.
        app.descendants(matching: .any)["preset-120"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["2h"].waitForExistence(timeout: UITest.timeout),
                      "Tapping the two-hour preset did not update the readout")
    }

    /// The whole point: a past slot becomes a real, rated session in the record.
    func testLoggingPastTimeLandsInTheRecordWithARating() throws {
        // The default slot is the hour just gone, and this asserts it appears on
        // *Today*. Within an hour of midnight the hour just gone is yesterday, so
        // the session lands correctly and correctly does not show here — the test
        // is wrong at that moment, not the app. Skipped rather than made
        // insensitive: asserting it reaches the record via the Journal would pass
        // at midnight and stop checking the thing this test is named for.
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        try XCTSkipIf(hour == 0 && minute < 55,
                      "Within the first hour of the day the last hour belongs to yesterday")

        launchToToday()

        // Today is still drawing itself when the tab bar appears, and a count
        // taken then is a count of the rows drawn so far.
        let rows = app.descendants(matching: .any).matching(identifier: "timeline-row")
        _ = rows.waitUntilCountSettles()
        let rowsBefore = rows.count

        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["slot-picker"].firstMatch.waitForExistence(timeout: UITest.timeout))
        app.descendants(matching: .any)["Exercise"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Log it"].firstMatch.tapWhenReady()

        // The spec asks for the reflection immediately after a backdated save.
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: UITest.timeout),
                      "Saving a past session did not raise the reflection sheet")
        attach("27-past-session-reflection")
        app.descendants(matching: .any)["feeling-5"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Save"].firstMatch.tapWhenReady()
        dismissDayContextCardIfShown()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
        _ = rows.waitUntilCountSettles()
        let rowsAfter = rows.count
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
        app.descendants(matching: .any)["Deep work"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Start"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: UITest.timeout))

        openSheet()
        app.descendants(matching: .any)["mode-Log past time"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["slot-picker"].firstMatch.waitForExistence(timeout: UITest.timeout))
        app.descendants(matching: .any)["Admin"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Log it"].firstMatch.tapWhenReady()

        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: UITest.timeout))
        app.descendants(matching: .any)["feeling-2"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Save"].firstMatch.tapWhenReady()

        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.staticTexts["NOW"].exists,
                      "Backdating stopped the session that was still running")
    }

    /// Saving the first rating of a day can raise a one-fact card over the
    /// reflection, and the reflection is not dismissed until it is acknowledged.
    ///
    /// Conditional, and it has to be. The card only appears when Apple Health has
    /// a settled deviation to report, which a simulator with no Health data never
    /// does — and it appears at most once per calendar day, so the second test to
    /// run on the same device would not see it either. Asserting on it here would
    /// be asserting on the machine rather than on the app; what this guards is
    /// only that the suite still gets past the reflection when it does appear.
    private func dismissDayContextCardIfShown() {
        let card = app.descendants(matching: .any)["day-context-card"].firstMatch
        guard card.waitForExistence(timeout: UITest.settle) else { return }
        app.descendants(matching: .any)["Done"].firstMatch.tapWhenReady()
    }

}
