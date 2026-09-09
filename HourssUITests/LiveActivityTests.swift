import XCTest

/// The Dynamic Island can only be seen from outside the app, so these tests start
/// a session, send the app to the background, and read SpringBoard.
///
/// **What SpringBoard actually exposes.** The Island itself has no identifier, but
/// its compact presentation renders the session clock as a plain static text, and
/// its expanded presentation exposes the activity's name and a real "Stop and
/// reflect" button. That is enough to tell a running activity from a frozen one
/// from none at all, so these tests read those elements instead of photographing
/// the screen and hoping. The screenshots are still attached, but they are no
/// longer the only evidence — a test in this file was deleted for passing while
/// its taps landed on the home screen, and nothing here can pass that way now.
@MainActor
final class LiveActivityTests: XCTestCase {

    private var app: XCUIApplication!
    private lazy var springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// The compact Island clock reads `m:ss`. A status-bar clock in a 24-hour
    /// locale has the same shape, so status-bar matches are subtracted rather than
    /// assumed away.
    private static let clockShaped = NSPredicate(format: "label MATCHES %@", "[0-9]{1,2}:[0-9]{2}")

    // MARK: - Waiting

    /// Polls a condition that is not about one element, so `UITest`'s waits cannot
    /// express it. Everything else here goes through those.
    @discardableResult
    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(UITest.timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    @discardableResult
    private func tap(_ identifier: String) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: UITest.timeout), "Never saw '\(identifier)'")
        element.tapWhenReady()
        return element
    }

    // MARK: - Getting to a running session

    /// Walks onboarding beat by beat.
    ///
    /// The old version fired four blind taps at Continue with nothing between them.
    /// Each beat is a state change the app has to finish first — the Health beat in
    /// particular awaits a read of a year of history before it advances — so on a
    /// loaded machine a tap arrived before its screen and was dropped, the flow
    /// stalled several beats back, and the failure surfaced much later as
    /// "priority-focus never appeared". The header's "n / 7" counter is the app's
    /// own statement of which beat it is on, so each tap waits for that number to
    /// move before the next one is sent.
    private func walkOnboarding() {
        tap("Start")
        reachBeat(2)
        // Health is asked for at beat two and there is no way past it but through.
        tap("health-connect")
        reachBeat(3)
        // Beat 3 ranks priorities and gates Continue on at least one.
        tap("priority-focus")
        for beat in 4...7 {
            tap("Continue")
            reachBeat(beat)
        }
        tap("Skip for now")
    }

    private func reachBeat(_ number: Int) {
        XCTAssertTrue(app.staticTexts["\(number) / 7"].waitForExistence(timeout: UITest.timeout),
                      "Onboarding never reached beat \(number)")
    }

    private func launchAndStartASession(named activity: String) {
        continueAfterFailure = false
        app = XCUIApplication()
        // The launch is also what gives each test its own starting state: nothing
        // is persisted across launches, so the app finds no session matching a Live
        // Activity a previous test left running and ends every one it finds.
        app.launchWithHistory()
        walkOnboarding()

        tap("tab-log")
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: UITest.timeout))
        tap(activity)
        tap("Start")
        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: UITest.timeout))
    }

    /// Whether the Island can render at all is a device setting, not a behaviour of
    /// this app. When the app itself reports the request was refused there is
    /// nothing to assert against, and skipping says so out loud rather than passing
    /// on an empty screen — which is the failure mode that got a test here deleted.
    private func skipIfLiveActivityRefused() throws {
        let refused = app.descendants(matching: .any)["live-activity-unavailable"].firstMatch
        try XCTSkipIf(refused.exists, "The app reported no Live Activity: \(refused.label)")
    }

    // MARK: - Reading the Island

    /// Labels of every Island clock currently on screen.
    private func islandClocks() -> [String] {
        let statusBarClocks = springboard.statusBars.staticTexts.matching(Self.clockShaped)
            .allElementsBoundByIndex.map { "\($0.frame)" }
        return springboard.staticTexts.matching(Self.clockShaped)
            .allElementsBoundByIndex
            .filter { !statusBarClocks.contains("\($0.frame)") }
            .map(\.label)
    }

    @discardableResult
    private func waitForIslandClocks(_ count: Int, _ message: String) -> [String] {
        var seen: [String] = []
        waitUntil {
            seen = islandClocks()
            return seen.count == count
        }
        XCTAssertEqual(seen.count, count, "\(message) — saw \(seen)")
        return seen
    }

    private func attach(_ name: String, _ screenshot: XCUIScreenshot) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Tests

    /// Starting a session must not throw or wedge the app, whether or not Live
    /// Activities are permitted on this device.
    func testStartingASessionSurvivesLiveActivityRequest() {
        launchAndStartASession(named: "Exercise")

        // The one delay in this file that is not standing in for a condition: the
        // point is to give a crash time to happen and then find the panel still
        // standing. Three seconds rather than two because a loaded machine takes
        // longer to fall over, not because it takes longer to succeed.
        sleep(3)
        XCTAssertTrue(app.staticTexts["Exercise"].exists, "The session did not survive the Live Activity request")
        XCTAssertTrue(app.descendants(matching: .any)["stop-session"].firstMatch.waitUntilHittable(),
                      "The stop control never became usable")
    }

    /// The Island is the whole reason for backgrounding, so read it rather than
    /// only photographing it: a compact clock is proof an activity is live.
    func testIslandWhileBackgrounded() throws {
        launchAndStartASession(named: "Deep work")
        try skipIfLiveActivityRefused()

        XCUIDevice.shared.press(.home)
        waitForIslandClocks(1, "Backgrounding the app left no Live Activity in the Island")
        attach("34-island-backgrounded", springboard.screenshot())
    }

    /// The timer has to actually advance.
    ///
    /// It once appeared frozen because a Live Activity from an *earlier launch*
    /// survived — activities outlive the app, and a stopped one sits there showing
    /// its final elapsed time forever. Two photographs nine seconds apart used to
    /// be the whole evidence, which left a human to compare them. The compact clock
    /// is readable, so the reading is the assertion now, and the wait is on the
    /// reading changing rather than on a fixed nine seconds.
    func testCompactTimerAdvances() throws {
        launchAndStartASession(named: "Deep work")
        try skipIfLiveActivityRefused()

        XCUIDevice.shared.press(.home)
        let early = waitForIslandClocks(1, "No Live Activity clock appeared in the Island").first
        attach("40-timer-early", springboard.screenshot())

        var later: String?
        waitUntil {
            later = islandClocks().first
            return later != nil && later != early
        }
        attach("41-timer-later", springboard.screenshot())

        XCTAssertNotNil(later, "The Island clock disappeared while the session was still running")
        XCTAssertNotEqual(later, early,
                          "The Island clock never advanced — a stale activity shows a frozen time")
    }

    /// An activity left behind by a process that is gone must not survive the next
    /// launch.
    ///
    /// The premise the old version rested on was wrong. Stopping a session inside
    /// the app already ends its activity, so quitting afterwards left no orphan to
    /// clear, and the test ended on `XCTAssertTrue(springboard.exists)` — true on
    /// any screen, including one where nothing had happened. It could not have
    /// failed. A real orphan needs the app killed with the session *still running*,
    /// which is what this does, and the Island is read at each step: the activity
    /// has to be there after the kill and gone after the relaunch. Take the app's
    /// reconciliation away and this turns red.
    func testStaleActivityIsClearedOnRelaunch() throws {
        launchAndStartASession(named: "Admin")
        try skipIfLiveActivityRefused()

        XCUIDevice.shared.press(.home)
        waitForIslandClocks(1, "The running session put no clock in the Island")

        // Killed mid-session. The activity belongs to the system rather than to the
        // process, so it stays behind — that is the orphan.
        app.terminate()
        waitForIslandClocks(1, "The activity did not outlive the app, so there is no orphan to clear")
        attach("42-orphan-after-kill", springboard.screenshot())

        // Nothing is persisted across launches, so the relaunched app finds no
        // session matching the orphan and has to end it.
        app = XCUIApplication()
        app.launchWithHistory()
        XCTAssertTrue(app.descendants(matching: .any)["Start"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "The app did not come back up")

        XCUIDevice.shared.press(.home)
        waitForIslandClocks(0, "A stale Live Activity survived the relaunch")
        attach("43-after-relaunch", springboard.screenshot())
    }

    /// Long-presses the Island to open the expanded view and taps its Stop button.
    ///
    /// The press and the tap used to be normalised coordinates against the whole
    /// screen, which is exactly how a test here once passed while hitting wallpaper.
    /// Both are elements now: the press targets the compact clock's own frame — the
    /// only addressable part of the collapsed Island — and Stop is the real button
    /// the expanded presentation publishes, so a miss fails instead of landing on
    /// the home screen. The assertion that matters is still on this side of the
    /// handoff: the app comes forward with the reflection up.
    func testExpandedIslandAndStopHandsOffToTheApp() throws {
        launchAndStartASession(named: "Deep work")
        try skipIfLiveActivityRefused()

        XCUIDevice.shared.press(.home)
        waitForIslandClocks(1, "No Live Activity clock appeared in the Island")
        let clock = springboard.staticTexts.matching(Self.clockShaped).firstMatch
        // The pill animates in and the press is measured against its frame, so a
        // press sent mid-animation lands beside it.
        clock.waitUntilStill()
        attach("35-island-compact", springboard.screenshot())

        clock.press(forDuration: 1.2)

        // The expanded presentation does have a queryable end state after all — its
        // contents only exist once it is open — so this needs no delay.
        XCTAssertTrue(springboard.descendants(matching: .any)["Deep work"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "The long press did not expand the Island")
        let stop = springboard.buttons["Stop and reflect"].firstMatch
        XCTAssertTrue(stop.waitUntilHittable(), "The expanded Island never offered a tappable Stop button")
        attach("36-island-expanded", springboard.screenshot())

        stop.tap()

        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: UITest.timeout),
                      "Stopping from the Island should open the app on the reflection")
        attach("37-after-stop", springboard.screenshot())
    }

    /// Stopping from inside the app must move the Island into its rating state
    /// without leaving the app in a bad place.
    func testStoppingMovesToReflection() {
        launchAndStartASession(named: "Learning")

        tap("stop-session")
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitForExistence(timeout: UITest.timeout),
                      "Stopping did not raise the reflection")
        tap("feeling-4")
        tap("Save")

        // The sheet has to be gone before "nothing is running" means anything —
        // otherwise this reads Today through a reflection that is still dismissing.
        XCTAssertTrue(app.staticTexts["REFLECTION"].waitUntilGone(),
                      "The reflection never dismissed after saving")
        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.staticTexts["NOW"].exists, "A session is still shown as running")
    }
}
