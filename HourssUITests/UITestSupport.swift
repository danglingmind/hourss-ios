import XCTest

/// Waits shared by the UI suite.
///
/// These tests are run while other work has the machine — another test bundle,
/// a build — and a simulator sharing a saturated CPU takes an order of
/// magnitude longer to lay out a screen than an idle one. Timeouts sized
/// against an idle machine turn that into a red suite, which is worse than a
/// slow one: nobody can tell a regression from a busy laptop, and the whole
/// suite becomes advisory. So there is one budget here rather than a scatter of
/// per-call guesses, sized so that only a screen which is genuinely stuck ever
/// reaches it.
enum UITest {
    static let timeout: TimeInterval = 60

    /// A much shorter budget for the checks that only refine an action rather
    /// than decide it. Every hittability or frame check costs a full
    /// accessibility snapshot, and on a machine slow enough to need these waits
    /// one snapshot can itself take ten seconds — so the refinements have to be
    /// bounded well inside the budget they are meant to protect.
    static let settle: TimeInterval = 8
}

extension XCUIElement {

    /// Exists, and has either arrived on screen or stopped moving.
    ///
    /// Existence is the cheap part — XCTest has a native wait for it. Everything
    /// after it is charged a full accessibility snapshot per look, so the
    /// refinement gets the short budget: on a saturated machine an unbounded
    /// "wait until hittable" spends the whole timeout on bookkeeping and then
    /// reports a control that was on screen the entire time as missing.
    @discardableResult
    func waitUntilReady(timeout: TimeInterval = UITest.timeout) -> Bool {
        guard waitForExistence(timeout: timeout) else { return false }
        return isHittable || waitUntilStill(timeout: UITest.settle)
    }

    /// Strictly on screen and touchable — for the assertions that are *about*
    /// being visible, where the looser reading above would give the answer away.
    @discardableResult
    func waitUntilHittable(timeout: TimeInterval = UITest.timeout) -> Bool {
        wait(NSPredicate(format: "exists == true AND isHittable == true"), timeout)
    }

    /// The frame has stopped moving: two samples, a second apart, that agree.
    ///
    /// Coordinate gestures are measured against the frame, so one computed
    /// while a sheet is still sliding up lands at the wrong fraction of a
    /// control that has since moved. Unlike `waitUntilReady` this says nothing
    /// about whether the element is on screen, so it is safe in front of an
    /// assertion about visibility.
    @discardableResult
    func waitUntilStill(timeout: TimeInterval = UITest.timeout) -> Bool {
        var previous: CGRect?
        let stopped = NSPredicate { element, _ in
            guard let element = element as? XCUIElement, element.exists else {
                previous = nil
                return false
            }
            let current = element.frame
            defer { previous = current }
            return previous == current
        }
        return wait(stopped, timeout)
    }

    /// Wait for the control, then tap it.
    ///
    /// Existence is what is asserted. Hittability is deliberately not: a control
    /// inside a scroll view can sit legitimately below the fold, and `tap()`
    /// scrolls it into view itself and fails loudly if it truly cannot deliver
    /// the event. What must never happen is a tap synthesised into a screen that
    /// is still moving, which is what the settle below is for.
    func tapWhenReady(timeout: TimeInterval = UITest.timeout,
                      file: StaticString = #filePath,
                      line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: timeout),
                      "The control never appeared — the screen was not ready for it",
                      file: file, line: line)
        if !isHittable {
            _ = waitUntilStill(timeout: UITest.settle)
        }
        tap()
    }

    /// For asserting an absence that a redraw has to catch up with: waiting for
    /// the element to go is not the assertion, it only stops the assertion
    /// racing the frame that removes it.
    @discardableResult
    func waitUntilGone(timeout: TimeInterval = UITest.timeout) -> Bool {
        wait(NSPredicate(format: "exists == false"), timeout)
    }

    private func wait(_ predicate: NSPredicate, _ timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIElementQuery {

    /// Waits for the query to find something. Counting matches straight after a
    /// screen appears counts whatever has been drawn so far.
    @discardableResult
    func waitForFirstMatch(timeout: TimeInterval = UITest.timeout) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the number of matches to stop changing, for the counts that are
    /// compared before and after an action: a list still filling in gives a
    /// smaller "before" than the same list gives later.
    @discardableResult
    func waitUntilCountSettles(timeout: TimeInterval = UITest.timeout) -> Bool {
        var previous: Int?
        let settled = NSPredicate { query, _ in
            guard let query = query as? XCUIElementQuery else { return false }
            let current = query.count
            defer { previous = current }
            return previous == current
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIApplication {

    /// Launch with generated history in place.
    ///
    /// The app starts empty now — a first run has nothing in it, and that is a
    /// state the product has to be good at rather than one it hides behind
    /// invented sessions. So a test that needs a populated app has to ask.
    ///
    /// The string is duplicated from `DebugFixture.launchArgument` rather than
    /// shared, because a UI test drives the app from another process and cannot
    /// import its types. If it ever changes, it changes in two places, and the
    /// tests that need history will fail loudly rather than quietly walking an
    /// empty app.
    func launchWithHistory() {
        launchArguments += ["-hourss-seed-fixture"]
        launch()
    }
}
