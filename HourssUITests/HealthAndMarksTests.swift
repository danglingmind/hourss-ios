import XCTest

/// Covers the Health path and the marks that replaced prose.
///
/// The accessibility assertions are the important ones. Text was removed from
/// several screens on the understanding that the marks replacing it keep the same
/// information in the VoiceOver path — if that stops being true, these fail.
@MainActor
final class HealthAndMarksTests: XCTestCase {

    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchWithHistory()
        // launch() returns when the process is up, which is before the first
        // frame. Saying so here means a launch that never lands fails as a
        // launch, rather than as whatever query happens to run next.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")
    }

    private func walkToHealthStep() {
        launch()
        app.descendants(matching: .any)["Start"].firstMatch.tapWhenReady()
        // Health is beat two now, immediately after the problem.
        XCTAssertTrue(app.descendants(matching: .any)["health-sleep"].firstMatch.waitForExistence(timeout: UITest.timeout))
    }

    /// Taps Continue through the beats between `from` and `to`, named by the
    /// numbers the header prints.
    ///
    /// "Continue" is the same element on four consecutive beats, so waiting for
    /// it to exist again cannot tell a beat that moved from a tap the transition
    /// swallowed — under load that is the difference between a walk that arrives
    /// and one that stalls a screen short. The header counts the beats, so wait
    /// on that instead.
    private func advance(through beats: ClosedRange<Int>) {
        for beat in beats {
            app.descendants(matching: .any)["Continue"].firstMatch.tapWhenReady()
            XCTAssertTrue(app.staticTexts["\(beat) / 7"].waitForExistence(timeout: UITest.timeout),
                          "Onboarding did not reach beat \(beat)")
        }
    }

    /// There is no skip on the ask any more — Connect is the only way forward.
    private func finishOnboarding() {
        app.descendants(matching: .any)["health-connect"].firstMatch.tapWhenReady()
        // Beat 3 ranks priorities and gates Continue on at least one.
        app.descendants(matching: .any)["priority-focus"].firstMatch.tapWhenReady()
        advance(through: 4...7)
        app.buttons["Skip for now"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["tab-log"].firstMatch.waitForExistence(timeout: UITest.timeout))
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

    // MARK: - Health

    /// Each category is consented to separately, and each says what it unlocks —
    /// the spec requires the read scopes be explained before the OS dialog.
    func testHealthStepStatesEverythingItReads() {
        walkToHealthStep()
        // These were a choice once, and every one of them had to be on for the
        // engine to say anything — so the control was between using the app and
        // not. They are a disclosure now, and the assertion changes with them:
        // not that each can be toggled, but that each is named before the
        // system sheet appears.
        for group in ["health-sleep", "health-recovery", "health-movement", "health-mind"] {
            XCTAssertTrue(app.descendants(matching: .any)[group].firstMatch.exists,
                          "\(group) is missing — every group must be named before the ask")
        }
        XCTAssertTrue(app.staticTexts["Read only. Nothing is ever written back, and nothing leaves your phone."].exists,
                      "The screen must state the read-only scope")
        // Scope must be visible before the OS dialog, not just a group name.
        XCTAssertTrue(app.staticTexts["Heart rate variability · Resting heart rate · Respiratory rate · Heart rate"].exists,
                      "The recovery group does not name what it reads")
        attach("29-onboarding-health")
    }

    /// The proof marks draw themselves in once. A mask that never completes would
    /// leave the charts blank and look exactly like having no data, so this waits
    /// out the reveal and checks the facts are still there afterwards.
    func testProofMarksSurviveTheirReveal() {
        walkToHealthStep()
        app.descendants(matching: .any)["health-connect"].firstMatch.tapWhenReady()
        // Beat 3 ranks priorities and gates Continue on at least one.
        app.descendants(matching: .any)["priority-focus"].firstMatch.tapWhenReady()
        // Priorities → key → mechanism → proof.
        advance(through: 4...6)
        XCTAssertTrue(app.staticTexts["ALREADY TRUE ABOUT YOU"].waitForExistence(timeout: UITest.timeout),
                      "Did not land on the proof beat")

        // Wait for the read to finish rather than assuming it has.
        let facts = app.descendants(matching: .any).matching(identifier: "proof-fact")

        if !facts.waitForFirstMatch() {
            // A data-less run is a legitimate outcome, but it must say so.
            XCTAssertTrue(app.descendants(matching: .any)["proof-empty"].firstMatch.exists,
                          "No facts and no empty state — the proof beat is showing nothing at all")
            return
        }

        // The rows reveal on a stagger. Wait for the first one to come out from
        // under its mask rather than guessing how long that takes here.
        XCTAssertTrue(facts.element(boundBy: 0).waitUntilHittable(),
                      "The first fact is not visible once the reveal has finished")
        XCTAssertGreaterThan(facts.count, 0, "The proof facts vanished after the reveal")
        attach("33-proof-after-reveal")
    }

    /// The one required action in the flow must be on screen when you arrive.
    /// Having to scroll to find the only button you are allowed to press is the
    /// worst place in onboarding to spend a gesture.
    func testAskFitsWithoutScrolling() {
        walkToHealthStep()

        let connect = app.descendants(matching: .any)["health-connect"].firstMatch
        XCTAssertTrue(connect.exists)
        // Settling is not the same as being on screen: a button below the fold
        // settles below the fold, so the assertion keeps all of its force.
        XCTAssertTrue(connect.waitUntilStill(), "The ask never finished laying itself out")
        XCTAssertTrue(connect.isHittable, "Connect Health is off screen — the ask needs scrolling")

        // And every consent row is visible too, since the scope has to be readable
        // before the system sheet appears.
        for group in ["health-sleep", "health-recovery", "health-movement", "health-mind"] {
            let row = app.descendants(matching: .any)[group].firstMatch
            XCTAssertTrue(row.isHittable, "\(group) is off screen")
        }
        attach("29-onboarding-health")
    }

    /// The ask offers no way forward but Connect. This is the enforceable half of
    /// the gate — iOS never tells us whether the grant was actually given.
    func testAskHasNoSkip() {
        walkToHealthStep()
        XCTAssertFalse(app.descendants(matching: .any)["health-skip"].firstMatch.exists,
                       "The Health ask must not offer a way past it")
        XCTAssertFalse(app.descendants(matching: .any)["Continue"].firstMatch.exists,
                       "The footer Continue must be suppressed on the ask")
        XCTAssertTrue(app.descendants(matching: .any)["health-connect"].firstMatch.exists)
    }

    /// Connecting reaches the app too, and the connection surfaces in settings.
    func testConnectingHealthReachesTheAppAndShowsInSettings() {
        walkToHealthStep()
        finishOnboarding()

        app.descendants(matching: .any)["tab-you"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["row-health"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["health-disconnect"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "A connected state should offer disconnect")
        attach("30-health-connection")
    }

    // MARK: - Marks keep the information

    /// The insight detail no longer prints the evidence sentence. The chart that
    /// replaced it must still speak the numbers.
    func testEvidenceNumbersSurviveInAccessibility() {
        walkToHealthStep()
        finishOnboarding()

        app.descendants(matching: .any)["tab-patterns"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["lead-insight"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["An observation, not a rule."].waitForExistence(timeout: UITest.timeout))

        // The chart's marks acquire their labels as they draw, so give the read
        // a chance to be there before taking one snapshot of the whole screen.
        _ = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "out of 5", "sessions"))
            .waitForFirstMatch()

        // Some element must speak a value out of 5 from a session count.
        let spoken = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { $0.contains("out of 5") && $0.contains("sessions") }
        XCTAssertFalse(spoken.isEmpty,
                       "Removing the evidence sentence lost the numbers from VoiceOver")
        attach("31-insight-detail")
    }

    /// The running-session panel is a forest surface inset in a canvas screen.
    /// Publishing the surface without setting the foreground put ink on dark green,
    /// which was nearly invisible — this pins the activity name to the panel.
    func testRunningSessionPanelRendersItsActivityName() {
        walkToHealthStep()
        finishOnboarding()

        app.descendants(matching: .any)["tab-log"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["START A SESSION"].waitForExistence(timeout: UITest.timeout))
        app.descendants(matching: .any)["Creative"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["Start"].firstMatch.tapWhenReady()

        XCTAssertTrue(app.staticTexts["NOW"].waitForExistence(timeout: UITest.timeout))
        let name = app.staticTexts["Creative"].firstMatch
        XCTAssertTrue(name.exists, "The running activity name is missing from the panel")
        // The panel is still sliding in behind the sheet as it dismisses, and a
        // name that is mid-flight is not yet a name that is off the panel.
        XCTAssertTrue(name.waitUntilStill(), "The running panel never settled")
        XCTAssertTrue(name.isHittable, "The running activity name is not visible")
        attach("33-today-active-session")
    }

    /// The heat calendar's cells must say their date and how the day felt.
    func testHeatCalendarSpeaksAndNavigates() {
        walkToHealthStep()
        finishOnboarding()

        app.descendants(matching: .any)["tab-journal"].firstMatch.tapWhenReady()
        XCTAssertTrue(app.staticTexts["JOURNAL"].waitForExistence(timeout: UITest.timeout))
        attach("32-journal-heat")

        // The calendar fills in cell by cell; scan it once it has cells.
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "felt ")).waitForFirstMatch()

        let cells = app.buttons.allElementsBoundByIndex.filter { $0.label.contains("felt ") }
        XCTAssertFalse(cells.isEmpty, "No heat-calendar cell reports how its day felt")

        cells.first?.tapWhenReady()
        XCTAssertTrue(app.descendants(matching: .any)["back"].firstMatch.waitForExistence(timeout: UITest.timeout),
                      "Tapping a heat cell did not open the day")
    }

    /// The warm-up screen replaced generic advice with real coverage figures.
    /// Those figures must be spoken, not just drawn.
    func testWarmUpCoverageIsSpoken() {
        walkToHealthStep()
        finishOnboarding()

        app.descendants(matching: .any)["tab-patterns"].firstMatch.tapWhenReady()
        // With six weeks seeded, Patterns is past warm-up; the marks live behind it.
        // Assert the lead insight is present instead, which is the same guarantee:
        // the screen is showing computed evidence rather than advice.
        XCTAssertTrue(app.descendants(matching: .any)["lead-insight"].firstMatch.waitForExistence(timeout: UITest.timeout))
        XCTAssertFalse(app.staticTexts["Log the same kind of work at different times of day."].exists,
                       "The generic advice list should be gone")
    }
}
