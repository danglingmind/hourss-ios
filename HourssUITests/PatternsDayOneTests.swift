import XCTest

/// Patterns on the first morning: nothing logged, Health in place.
///
/// **The state this file exists for could not be reached, and that is the bug it
/// locks.** Patterns used to be one `if/else` over the whole page — the warm-up
/// readout *or* the priority sections, never both — so somebody with nothing logged
/// got a sentence about their days coming out alike and no Focus, no Energy, no
/// Balance and no offer under any of them. Every per-priority section was written to
/// handle exactly that record, and none of them could be drawn on it.
///
/// A unit test can show the engine has something for each priority, and
/// `PatternsEmptyStateTests` does. What it cannot show is that the screen draws it,
/// because the thing that was wrong was a `ViewBuilder` branch. So this is a device
/// test, and the assertion is the one the unit suite structurally cannot make: the
/// coverage readout and the priority sections on screen at the same time.
///
/// **Why the day-one fixture.** `DebugFixture` seeds six weeks by default, which is
/// past warm-up and therefore the state that always worked. `-hourss-fixture-day-one`
/// keeps the Health history and drops every session, which is the first morning.
@MainActor
final class PatternsDayOneTests: XCTestCase {

    private var app: XCUIApplication!

    /// The fixture's own three, in its own order — `DebugFixture` line 198.
    /// Uppercased because `Eyebrow` uppercases, and duplicated rather than imported
    /// for the reason `UITestSupport` records: a UI test drives the app from another
    /// process and cannot import its types.
    private let priorities = ["FOCUS", "ENERGY", "BALANCE"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-hourss-seed-fixture",
            "-hourss-fixture-day-one",
            "-hourss-skip-onboarding",
            "-hourss-debug-no-notifications",
            "-hourss-debug-account", "Ren",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")
        app.descendants(matching: .any)["tab-patterns"].firstMatch.tapWhenReady()
    }

    /// Scrolls until the element can be tapped, walking rather than guessing a
    /// number of swipes — how far down a section sits depends on how many priorities
    /// the profile ranked, which is the same reason `QuestionMapUITests` walks.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, timeout: TimeInterval = UITest.timeout) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The preamble and the sections, together. Either one alone is the old screen.
    func testTheWarmUpReadoutAndThePrioritySectionsAreBothOnScreen() {
        let readout = app.staticTexts["Days with a rating"].firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: UITest.timeout),
                      "Day one should still show the coverage readout")
        attach("patterns-day-one-top")

        for title in priorities {
            let heading = app.staticTexts[title].firstMatch
            XCTAssertTrue(scrollTo(heading),
                          "\(title) has no section on Patterns, so this record has "
                              + "nothing to say about a priority the person ranked")
        }
        attach("patterns-day-one-sections")
    }

    /// And each of those sections carries the one thing this screen can offer early.
    ///
    /// Not asserted per priority: which priorities get an offer is the offer chain's
    /// business — `OfferChainTests` pins one per priority and the ordering between
    /// sources — and duplicating that rule here would make this file fail for a
    /// change in ranking rather than for a change in layout. What is asserted is that
    /// the sections reach the UI with something actionable in them at all, which is
    /// the thing that was broken.
    func testADayOneSectionOffersSomethingToDo() {
        let offers = app.descendants(matching: .any).matching(identifier: "open-proposal")
        let offer = offers.firstMatch
        XCTAssertTrue(scrollTo(offer),
                      "No priority section offered anything on day one, so the screen "
                          + "states a record and proposes nothing about it")
        attach("patterns-day-one-offer")
        XCTAssertGreaterThan(offers.count, 0)
    }

    /// The way into the tests feature survived the rearrangement.
    ///
    /// It was deliberately outside the old `if/else` so a warming-up record kept it.
    /// It is now below the sections rather than below a single sentence, which is a
    /// much longer scroll — so the thing worth checking is that it is still reachable.
    func testTheTestsEntryIsStillReachableBelowTheSections() {
        let row = app.descendants(matching: .any)["row-tests"].firstMatch
        XCTAssertTrue(scrollTo(row),
                      "The tests entry never came into reach — the sections now sit "
                          + "above it, so this is a screen that cannot be scrolled to "
                          + "its own foot")
    }
}
