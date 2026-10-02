import XCTest

/// The record of what has been tested, reached the way somebody would reach it.
///
/// The accessibility assertions are the important ones here, as they are in
/// `HealthAndMarksTests`. This screen draws three verdicts with one function and
/// tells them apart by their words alone — no colour, badge or type size — so the
/// label on a row is the whole of what a VoiceOver reader and a greyscale reader
/// both get, and if it stops naming the verdict the distinction is gone for them.
@MainActor
final class ExperimentHistoryUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Every verdict phrase, as `Eyebrow` uppercases them.
    ///
    /// Duplicated from `ExperimentCopy.verdictTitle` rather than shared, for the
    /// reason `UITestSupport` already records about the launch arguments: a UI test
    /// drives the app from another process and cannot import its types. If the
    /// wording changes this fails loudly, which is the right failure.
    private let verdicts = ["IT HELD UP", "IT DID NOT HOLD UP", "NOT ENOUGH TO TELL"]

    /// Straight to Today with history in place.
    ///
    /// Onboarding is skipped by argument rather than walked. The walk belongs to the
    /// tests that are about onboarding; this one is about a screen four taps past it,
    /// and nine beats of tapping in front of the assertion is nine ways for it to
    /// fail as something it is not. The strings are duplicated from `DebugFixture`
    /// and `AccountService` for the reason the shared helpers give.
    private func launchToToday() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-hourss-seed-fixture",
            "-hourss-skip-onboarding",
            "-hourss-debug-no-notifications",
            "-hourss-debug-account", "Ren",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: UITest.timeout),
                      "The app did not reach the foreground")
        XCTAssertTrue(app.descendants(matching: .any)["tab-you"].firstMatch
            .waitForExistence(timeout: UITest.timeout),
                      "The app did not land on the tabs")
    }

    private func openTheRecord() {
        app.descendants(matching: .any)["tab-you"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["row-tests"].firstMatch.tapWhenReady()
    }

    /// The whole point of the surface: a result outlives the card that showed it.
    func testASettledResultIsStillThereAfterTheCardIsGone() {
        launchToToday()

        // Acknowledge the fixture's settled result on Today, which is what gives up
        // the slot — and, before this screen existed, was the last anybody saw of it.
        let acknowledge = app.descendants(matching: .any)["acknowledge-experiment"].firstMatch
        XCTAssertTrue(acknowledge.waitForExistence(timeout: UITest.timeout),
                      "The fixture's settled result did not claim the slot on Today")
        acknowledge.tapWhenReady()
        XCTAssertTrue(acknowledge.waitUntilGone(),
                      "Acknowledging did not release the slot")

        openTheRecord()

        let list = app.descendants(matching: .any)["experiment-history"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: UITest.timeout),
                      "The record did not appear")

        let rows = app.descendants(matching: .any).matching(identifier: "history-row")
        XCTAssertTrue(rows.waitForFirstMatch(), "An acknowledged result left no record behind")
        XCTAssertFalse(app.descendants(matching: .any)["experiment-history-empty"].firstMatch.exists,
                       "The empty state is showing with a result in the record")
    }

    /// Colour is never the only carrier, and neither is position.
    func testEveryRowNamesItsVerdictInWords() {
        launchToToday()
        openTheRecord()

        let rows = app.descendants(matching: .any).matching(identifier: "history-row")
        XCTAssertTrue(rows.waitForFirstMatch(), "The record is empty on the fixture")
        rows.waitUntilCountSettles()

        for index in 0..<rows.count {
            let label = rows.element(boundBy: index).label
            let namesOutcome = (verdicts + ["STOPPED"]).contains { label.uppercased().contains($0) }
            XCTAssertTrue(namesOutcome,
                          "A row said what happened with something other than words: \(label)")
            // Subject first. A label that opened with a figure would be the readout
            // bug `TitledFigure` and the Patterns evidence line were both corrected
            // for, in the one place a reader cannot skip ahead.
            XCTAssertFalse(label.first?.isNumber ?? true,
                           "A row's label opened with a figure: \(label)")
        }
    }

    /// Nothing totals the verdicts — not a rate, not a streak, not "two of three".
    func testTheRecordCountsNothing() {
        launchToToday()
        openTheRecord()

        XCTAssertTrue(app.descendants(matching: .any)["experiment-history"].firstMatch
            .waitForExistence(timeout: UITest.timeout))

        for tally in ["SUCCESS RATE", "HELD UP: ", "2 OF 3", "STREAK"] {
            XCTAssertFalse(app.staticTexts[tally].exists,
                           "The record is keeping score: \(tally)")
        }
    }
}
