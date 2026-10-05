import XCTest

/// The announcement as somebody meets it on the launch after a question opened.
///
/// **What only a device run can check.** The unit suite asserts every word, that the
/// sheet is the same shape either way, and that it fires once and never again. What
/// it cannot see is whether the thing actually arrives in front of somebody — the
/// announcement is raised at the end of `HourssApp`'s launch task and presented by
/// `RootView`, behind onboarding, the account gate and the Health screen, and every
/// one of those links is invisible to a unit test. It also cannot see the reveal, or
/// whether a VoiceOver reader gets each block's heading before its content.
///
/// **Both halves are run, and that is the point of running this at all.** A question
/// that found something and a question that found nothing are supposed to arrive in
/// the same sheet at the same weight, and nobody can check that by looking at one of
/// them. `PRD-LOCKS.md` §8 says the design has to be good at the empty one rather
/// than apologise for it; these two tests are where that is looked at.
///
/// The strings and launch arguments are duplicated from `AnnouncementCopy` and
/// `DebugFixture` rather than shared, for the reason `UITestSupport` records: a UI
/// test drives the app from another process and cannot import its types. If the
/// wording changes this fails loudly, which is the right failure for a screen whose
/// entire risk is its words.
@MainActor
final class QuestionAnnouncementUITests: XCTestCase {

    private var app: XCUIApplication!

    /// `Eyebrow` uppercases, so this is how the four headings reach the screen.
    private let headings = ["THE QUESTION", "WHAT IT FOUND", "WHY NOW", "BEAR IN MIND"]

    /// - Parameter found: whether the withheld question is one the engine published a
    ///   claim for. The fixture withholds the other kind by default, because a
    ///   non-answer is the common case and the one worth reviewing.
    private func launch(found: Bool) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-hourss-seed-fixture",
            "-hourss-skip-onboarding",
            found ? "-hourss-fixture-question-found" : "-hourss-fixture-question-opened",
            "-hourss-debug-no-notifications",
            "-hourss-debug-account", "Ren",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")
    }

    /// The sheet's own title, waited for.
    ///
    /// The header rather than the container's identifier: `Eyebrow` renders a static
    /// text, which is queryable without depending on whether a plain `VStack` reaches
    /// the accessibility tree as an element of its own. It is also the one string on
    /// the screen that says what the sheet *is*, so waiting on it is waiting on the
    /// thing under test.
    @discardableResult
    private func sheet() -> XCUIElement {
        let title = app.staticTexts["A QUESTION OPENED"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: UITest.timeout),
                      "No announcement arrived on a launch that had one to make")
        return title
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The case the design has to be good at: the question opened and found nothing.
    func testAQuestionThatFoundNothingArrivesWithItsAnswer() {
        launch(found: false)
        sheet()

        // The answer is on the sheet, not behind a tap. A reveal that deferred it
        // would be the slot machine `PRD-LOCKS.md` §2 forbids by name.
        XCTAssertTrue(app.staticTexts["Checked, and both kinds of day came out alike."]
                        .waitForExistence(timeout: UITest.timeout),
                      "The non-answer was not carried on the sheet")
        for heading in headings {
            XCTAssertTrue(app.staticTexts[heading].firstMatch.exists,
                          "The sheet is missing its \(heading) section")
        }
        attach("announcement-nothing-found")
    }

    /// The other half, which has to weigh the same.
    func testAQuestionThatFoundSomethingArrivesInTheSameSheet() {
        launch(found: true)
        sheet()

        for heading in headings {
            XCTAssertTrue(app.staticTexts[heading].firstMatch.exists,
                          "The sheet is missing its \(heading) section")
        }
        // Same four sections, same single control, and no extra ceremony: nothing
        // that reads as a reward, and no second control offering to do something
        // about it.
        XCTAssertFalse(app.staticTexts["Checked, and both kinds of day came out alike."].exists,
                       "A question with a claim is reporting a non-answer")
        attach("announcement-claim")
    }

    /// The whole of what it asks of anybody.
    func testTheOneControlEndsIt() {
        launch(found: false)
        let title = sheet()

        let close = app.descendants(matching: .any)["acknowledge-opened-question"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: UITest.timeout),
                      "The announcement has no way out")
        XCTAssertTrue(close.label.contains("Got it"),
                      "The control is not the app's own word for ending a result: \(close.label)")
        close.tapWhenReady()
        XCTAssertTrue(title.waitUntilGone(), "The announcement would not close")
    }

    /// A reader who cannot see the sheet gets each block subject-first, which is the
    /// standing rule and the reason no label here opens with a figure.
    func testEachBlockSpeaksItsSubjectFirst() {
        launch(found: false)
        sheet()

        let question = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The question")).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: UITest.timeout),
                      "The question block has no readout of its own")
        XCTAssertTrue(question.label.contains("against"),
                      "The readout did not say what was compared: \(question.label)")

        let found = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "What it found")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: UITest.timeout),
                      "The answer block has no readout of its own")
        XCTAssertTrue(found.label.contains("came out alike"),
                      "The answer was not spoken: \(found.label)")
    }

    /// Reduce Motion lands on the finished state, as everything else here does: the
    /// reveal is `revealsOnAppear`, which draws nothing when it is on.
    func testReduceMotionLandsOnTheFinishedSheet() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-hourss-seed-fixture",
            "-hourss-skip-onboarding",
            "-hourss-fixture-question-opened",
            "-hourss-debug-no-notifications",
            "-hourss-debug-account", "Ren",
            "-UIAccessibilityReduceMotionEnabled", "1",
        ]
        app.launch()
        sheet()

        XCTAssertTrue(app.staticTexts["Checked, and both kinds of day came out alike."]
                        .waitForExistence(timeout: UITest.timeout),
                      "Reduce Motion did not land on the finished sheet")
        attach("announcement-reduce-motion")
    }
}
