import XCTest

/// The question map on Patterns, on a device, at the size that breaks layouts.
///
/// **What only a device run can check.** The unit suite pins the split, every word
/// on the lid and the absence of any figure on it. What it cannot see is whether the
/// map is reachable at all on a screen whose length is the reason the fold exists,
/// whether `.action` and `.label` still fit once they have scaled from
/// `.subheadline` and `.caption`, whether the rows the lid reveals land under it
/// rather than off the bottom, and whether a reader who cannot see the arrow is told
/// what the control does. Those are the assertions here.
///
/// **Why the seeded fixture rather than day one.** Patterns only draws the question
/// map once it is past warm-up — `isWarmingUp` is "no visible insights" — so a
/// day-one record shows the coverage readout and no questions at all. Six weeks of
/// history is the shortest record that reaches the map.
///
/// **Two of these skip on the current fixture, loudly, and that is the finding
/// rather than a hole in the test.** The seeded record mints thirty-four
/// hypotheses, twenty-seven of which have already cleared their gates, so the whole
/// waiting list is seven questions across three priorities and no priority holds
/// more than one whose side has never happened. The fold's threshold is two, so the
/// lid is never drawn, so there is nothing on screen to tap. The state it is written
/// for is an ordinary one — somebody past warm-up who has never logged an evening, a
/// night or a long session — and it is simply not a state `DebugFixture` produces.
/// `PRD-LOCKS.md` §10 item 18 is the item that closes this; until it does, these
/// skip with the reason named rather than passing on an absence, which is the
/// failure mode `PatternsLeadTests` records about a test that hedged with an `||`.
///
/// The lid's wording is duplicated from `QuestionCopy.foldedHeading` rather than
/// shared, for the reason `UITestSupport` records about the launch arguments: a UI
/// test drives the app from another process and cannot import its types. If the
/// wording changes this fails loudly, which is the right failure — the whole
/// argument for this label is that it says what is inside.
@MainActor
final class QuestionMapUITests: XCTestCase {

    private var app: XCUIApplication!

    private let lidLabel = "Questions with an empty side"

    /// Straight to Patterns with six weeks in place.
    ///
    /// Onboarding is skipped by argument rather than walked, as `TestsScreenUITests`
    /// does and for the same reason: nine beats of tapping in front of an assertion
    /// is nine ways for it to fail as something it is not.
    private func launchToPatterns(contentSize: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launchArguments += [
            "-hourss-seed-fixture",
            "-hourss-skip-onboarding",
            "-hourss-debug-no-notifications",
            "-hourss-debug-account", "Ren",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")
        app.descendants(matching: .any)["tab-patterns"].firstMatch.tapWhenReady()
    }

    /// Scrolls until the element can be tapped. The map is below the claims, the
    /// leads and the proposal by design, and how far below depends on how many
    /// priorities this profile ranked — so this walks rather than guessing a number
    /// of swipes, as the tests entry already has to.
    private func scrollTo(_ element: XCUIElement, timeout: TimeInterval = UITest.timeout) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable
    }

    private var waitingRows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "waiting-row")
    }

    /// The lid, or nothing. `settle` rather than the full budget because on this
    /// fixture the expected answer is that it is absent, and spending a minute
    /// establishing that on every run is a minute per skip.
    private func lidOrSkip() throws -> XCUIElement {
        let lid = app.descendants(matching: .any)["folded-questions"].firstMatch
        guard lid.waitForExistence(timeout: UITest.settle) else {
            throw XCTSkip(
                "No priority on the seeded fixture holds two questions with an empty "
                    + "side, so no lid is drawn. This needs a DebugFixture that "
                    + "produces a lopsided record — past warm-up, with a time bucket "
                    + "and a duration nobody has logged — which is PRD-LOCKS §10 "
                    + "item 18.")
        }
        XCTAssertTrue(scrollTo(lid),
                      "The lid exists but never came into reach — the map is below the "
                          + "claims by design, so this is a screen that cannot be "
                          + "scrolled to its own foot")
        return lid
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: The map, whatever the record

    /// `PRD-LOCKS.md` §10 item 16, on the part of the map every record reaches.
    ///
    /// The waiting rows are two steps of type each — the question at `.body`, what it
    /// is short of at `.label` — and at `AccessibilityL` both have roughly doubled.
    /// What would go wrong is a row whose second line is clipped or pushed off the
    /// reading column, which no unit test can see.
    func testTheWaitingRowsAreReadableAtAccessibilityL() {
        launchToPatterns(contentSize: "UICTContentSizeCategoryAccessibilityL")

        let rows = waitingRows
        XCTAssertTrue(rows.waitForFirstMatch(timeout: UITest.timeout),
                      "Patterns drew no waiting questions at all, so the map is not on "
                          + "the screen this test is about")
        XCTAssertTrue(scrollTo(rows.element(boundBy: 0)),
                      "The first waiting question never came into reach at "
                          + "accessibility type sizes")
        attach("map-waiting-accessibilityL")

        // Inside the reading column, both edges. A row that has overflowed its gutter
        // is a row whose longer sentence is being cut off rather than wrapped.
        for index in 0..<min(rows.count, 4) {
            let row = rows.element(boundBy: index)
            guard row.exists else { continue }
            XCTAssertGreaterThanOrEqual(row.frame.minX, 0,
                                        "A waiting row starts off the left edge")
            XCTAssertLessThanOrEqual(row.frame.maxX, app.frame.width,
                                     "A waiting row runs past the right edge, so its "
                                         + "sentence is clipped rather than wrapped")
            // Both lines present. One line at this size would mean the shortfall
            // sentence has been dropped, which is the whole content of the row.
            XCTAssertTrue(row.label.contains(". "),
                          "A waiting row speaks as '\(row.label)' — the question and "
                              + "what it is waiting for should arrive as one element "
                              + "with both halves in it")
        }
    }

    // MARK: The fold itself

    /// The whole claim: the list is shorter folded, and one tap makes it longer
    /// without going anywhere.
    func testTheFoldShortensTheListAndOpensInPlace() throws {
        launchToPatterns()
        let lid = try lidOrSkip()

        _ = waitingRows.waitUntilCountSettles(timeout: UITest.settle)
        let folded = waitingRows.count
        attach("map-folded")

        lid.tapWhenReady()
        _ = waitingRows.waitUntilCountSettles(timeout: UITest.settle)
        XCTAssertGreaterThan(waitingRows.count, folded, "Tapping the lid revealed nothing")
        attach("map-open")

        // In place, not pushed: the tab is still Patterns and the lid is still on
        // screen above its rows. A navigation would have taken both away, and that is
        // the shape this design rejected.
        XCTAssertTrue(app.descendants(matching: .any)["tab-patterns"].firstMatch.exists,
                      "The lid navigated somewhere instead of opening in place")
        XCTAssertTrue(lid.exists,
                      "The lid disappeared when it opened, so the rows it revealed have "
                          + "nothing standing over them saying what they are")

        // And it folds again. A lid that only opens is a lid somebody cannot undo.
        lid.tapWhenReady()
        _ = waitingRows.waitUntilCountSettles(timeout: UITest.settle)
        XCTAssertEqual(waitingRows.count, folded, "The lid would not close again")
    }

    /// Item 16 again, for the one line the fold adds. A lid whose own label wraps to
    /// four lines has not shortened the section it covers.
    func testTheLidStaysReadableAtAccessibilityL() throws {
        launchToPatterns(contentSize: "UICTContentSizeCategoryAccessibilityL")
        let lid = try lidOrSkip()
        attach("map-lid-accessibilityL")

        // Two lines of `.action` at this size, plus the tap target, is the budget.
        // Measured against the screen rather than against a constant, so it does not
        // go stale on another device: a third of the screen's height spent on one
        // control's label is well past anything that could be called a fold.
        XCTAssertLessThan(lid.frame.height, app.frame.height / 3,
                          "The lid is \(lid.frame.height)pt tall at AccessibilityL — "
                              + "its label has wrapped past the two lines it is "
                              + "written to fit")
        XCTAssertLessThanOrEqual(lid.frame.maxX, app.frame.width,
                                 "The lid's label runs past the right edge")

        let folded = waitingRows.count
        lid.tapWhenReady()
        _ = waitingRows.waitUntilCountSettles(timeout: UITest.settle)
        XCTAssertGreaterThan(waitingRows.count, folded,
                             "The lid revealed nothing at accessibility type sizes")
        attach("map-open-accessibilityL")
    }

    /// A reader who cannot see the arrow has to be told what the control does, and
    /// what is behind it, without tapping it.
    func testTheLidSpeaksForItself() throws {
        launchToPatterns()
        let lid = try lidOrSkip()

        // The label is the whole affordance for a spoken reader: the arrow is the only
        // thing that distinguishes open from closed visually, and it is not spoken. So
        // the label has to name the kind of thing inside.
        XCTAssertTrue(lid.label.contains(lidLabel),
                      "The lid speaks as '\(lid.label)', which does not say what is "
                          + "behind it")
        XCTAssertFalse(lid.label.contains(where: \.isNumber),
                       "A figure reached the spoken form of the lid: '\(lid.label)'")
    }
}
