import XCTest

/// Drives the shell end to end.
///
/// Two jobs at once: prove the core loop works (start a session, stop it, rate it,
/// find it again in the record), and capture every screen along the way for the
/// demo. Elements are addressed by accessibility identifier rather than by visible
/// text, so copy edits do not break the walkthrough.
@MainActor
final class DemoWalkthroughTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotIndex = 0

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithHistory()
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        shotIndex += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = String(format: "%02d-%@", shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func tapID(_ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: UITest.timeout), "Could not find '\(identifier)'")
        element.tapWhenReady()
        return element
    }

    private func exists(_ identifier: String) -> Bool {
        app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: UITest.timeout)
    }

    private func rows() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "timeline-row")
    }

    // MARK: - The walkthrough

    func testFullDemoWalkthrough() throws {
        launch()
        // 1 — the human problem
        XCTAssertTrue(app.staticTexts["Your calendar, knows where, time went."].waitForExistence(timeout: UITest.timeout))
        capture("onboarding-1-problem")
        tapID("Start")

        // 2 — the promise, and the Health ask. No skip: Connect is the only exit.
        XCTAssertTrue(app.descendants(matching: .any)["health-sleep"].firstMatch.waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.descendants(matching: .any)["health-skip"].firstMatch.exists,
                       "The ask must not offer a way past it")
        capture("onboarding-2-promise")
        // Connecting awaits a read of a year of history before the beat advances,
        // so the next screen can be seconds away on a loaded machine.
        tapID("health-connect")

        // 3 — priorities, in the person's own order
        XCTAssertTrue(app.descendants(matching: .any)["priority-focus"].firstMatch.waitForExistence(timeout: UITest.timeout))
        capture("onboarding-3-priorities")
        tapID("priority-sleep")
        tapID("priority-focus")
        capture("onboarding-3-priorities-ranked")
        tapID("Continue")

        // 4 — the key
        XCTAssertTrue(app.staticTexts["Compared, only to you."].waitForExistence(timeout: UITest.timeout))
        capture("onboarding-4-key")
        tapID("Continue")

        // 5 — the mechanism
        XCTAssertTrue(app.staticTexts["One tap., One question."].waitForExistence(timeout: UITest.timeout))
        capture("onboarding-5-mechanism")
        tapID("Continue")

        // 6 — the proof: real facts from Health, or an honest empty state.
        //
        // The beat has a third state the old check did not allow for: it says so
        // while the read is still running. A machine slow enough to still be
        // reading here failed on "neither facts nor empty" — a true reading of a
        // screen that had not finished answering. Waiting for the read to land is
        // not the assertion; it only stops the assertion racing it.
        XCTAssertTrue(app.descendants(matching: .any)["proof-loading"].firstMatch.waitUntilGone(),
                      "The proof beat never finished reading Health")
        capture("onboarding-6-proof")
        let hasFacts = app.descendants(matching: .any).matching(identifier: "proof-fact").count > 0
        let admitsEmpty = app.descendants(matching: .any)["proof-empty"].firstMatch.exists
        XCTAssertTrue(hasFacts || admitsEmpty,
                      "The proof beat must either show facts or say it has none")
        tapID("Continue")

        // 7 — the account. The gate, walked already signed in: the Apple sheet is
        // another process and wants a real Apple ID, so a UI test can only ever
        // see this side of it.
        XCTAssertTrue(app.descendants(matching: .any)["account-signed-in"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "The account beat never appeared after the proof")
        capture("onboarding-7-account")
        tapID("Continue")

        // 8 — reminders. The frequency rows are real state, so the walk picks one
        // rather than accepting the default silently.
        XCTAssertTrue(app.descendants(matching: .any)["reminder-everyTwoHours"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "The reminders beat never appeared")
        capture("onboarding-8-reminders")
        tapID("reminder-everyThreeHours")
        tapID("Continue")

        // 9 — start
        capture("onboarding-9-start")
        tapID("Skip for now")

        // Today. Which of T1/T3 renders depends on the hour: the seeded moments sit
        // at fixed clock times, so early in the day the record is legitimately
        // empty and T1 is the correct screen.
        XCTAssertTrue(exists("tab-log"), "Did not reach the main app")
        // A count taken the instant Today appears is a reading of however much of
        // the timeline had rendered by then, which on a loaded machine is not all
        // of it — and this number is half of the comparison at the end.
        rows().waitUntilCountSettles()
        let sessionsBefore = rows().count
        capture(sessionsBefore == 0 ? "today-empty" : "today-record")

        // Tapping a timeline row updates the reading beside it.
        if sessionsBefore > 0 {
            rows().element(boundBy: 0).tapWhenReady()
            capture("today-timeline-selection")
        }

        // --- Core loop: start → stop → rate → lands in the record ---

        // L1 — Start a session
        tapID("tab-log")
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: UITest.timeout))
        capture("logging-start")
        tapID("Learning")
        tapID("Start")

        // T2 — a session is now running
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: UITest.timeout), "Active session panel did not appear")
        // Purely for the screenshot: a clock reading 0:00 is a poor demo frame.
        // Nothing below depends on how long this is.
        sleep(3)
        capture("today-active-session")

        // Stopping raises the reflection sheet.
        tapID("stop-session")

        // L3 — Reflection
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: UITest.timeout))
        capture("logging-reflection")
        tapID("feeling-4")
        // Performance is visible without disclosure, and still optional.
        XCTAssertTrue(app.staticTexts["How well did it go?"].exists, "The performance scale should be visible without tapping anything")
        tapID("performance-5")
        capture("logging-reflection-rated")
        tapID("Save")

        // Back on Today with one more session than we started with. The new row
        // lands as the sheet finishes dismissing, so the count is allowed to settle
        // first — a row that never arrives still fails the comparison.
        XCTAssertTrue(exists("tab-log"))
        rows().waitUntilCountSettles()
        XCTAssertEqual(rows().count, sessionsBefore + 1, "The rated session did not land in Today's timeline")
        capture("today-after-logging")

        // The reading beside the timeline reflects the rating we just gave.
        XCTAssertTrue(app.staticTexts["Learning"].firstMatch.exists, "The logged activity is missing from the record")

        // Patterns — P2 then P3
        tapID("tab-patterns")
        XCTAssertTrue(exists("lead-insight"), "Patterns should have observations from the seeded history")
        capture("patterns-list")
        app.swipeUp()
        capture("patterns-list-feed")
        app.swipeDown()

        tapID("lead-insight")
        XCTAssertTrue(app.staticTexts["An observation, not a rule."].waitForExistence(timeout: UITest.timeout))
        capture("patterns-detail")
        app.swipeUp()
        capture("patterns-detail-evidence")
        app.swipeUp()
        capture("patterns-detail-sessions")
        tapID("back")

        // Journal — J1 then J2
        tapID("tab-journal")
        XCTAssertTrue(app.staticTexts["JOURNAL"].waitForExistence(timeout: UITest.timeout))
        capture("journal-list")

        let days = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'day-'"))
        XCTAssertTrue(days.waitForFirstMatch(), "The journal listed no days to open")
        // Sessions Hourss imported from Health are marked wherever they appear,
        // and a night is the imported thing every day has.
        //
        // Every day but one. A night is filed under the morning it ended, so the
        // current day only has one once somebody has woken up on it — before
        // then the most recent night belongs to yesterday, and the fixture no
        // longer pretends otherwise by seeding a sleep that ends hours from now.
        // So the check walks back until it finds a day with a night rather than
        // assuming the newest one has it.
        var foundImport = false
        for index in 0..<min(3, days.count) {
            days.element(boundBy: index).tapWhenReady()
            if app.staticTexts["Health"].firstMatch.waitForExistence(timeout: UITest.settle) {
                foundImport = true
                capture("journal-day-detail")
                tapID("back")
                break
            }
            tapID("back")
            _ = days.waitForFirstMatch()
        }
        XCTAssertTrue(foundImport, "No recent day marks its imported session")

        // You — Y1, Y2, Y3, Y6
        //
        // Nothing in this list is greyed out any more, so the walk opens the two
        // rows that used to say "needs an account" as well as the ones that
        // always worked.
        tapID("tab-you")
        XCTAssertTrue(app.staticTexts["MEMBERSHIP"].waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.staticTexts["NOT IN THIS BUILD"].exists,
                       "Profile and Account are built — nothing is left standing in for them")
        capture("you-settings")

        tapID("row-profile")
        XCTAssertTrue(app.staticTexts["WORKDAYS"].waitForExistence(timeout: UITest.timeout))
        capture("you-profile")
        tapID("back")

        tapID("row-account")
        XCTAssertTrue(app.descendants(matching: .any)["sign-out"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "The account screen must offer a way out of it")
        capture("you-account")
        tapID("back")

        tapID("row-preferences")
        XCTAssertTrue(app.staticTexts["Quiet mode"].waitForExistence(timeout: UITest.timeout))
        capture("you-preferences")
        tapID("back")

        tapID("row-privacy")
        XCTAssertTrue(app.staticTexts["Export everything"].waitForExistence(timeout: UITest.timeout))
        XCTAssertTrue(app.descendants(matching: .any)["delete-everything"].firstMatch.exists,
                      "Deletion is required of anything offering sign-in, and Hourss has nowhere else to do it")
        capture("you-privacy")
    }
}
