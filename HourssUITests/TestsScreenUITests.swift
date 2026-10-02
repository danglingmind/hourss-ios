import XCTest

/// The Tests screen, reached the way somebody would reach it.
///
/// **It used to be `ExperimentHistoryUITests`, and the record is still most of what
/// it checks.** The record became one section of three when the feature got a home,
/// so the assertions about rows, verdicts and counting are unchanged and the ones
/// about the screen holding all three states are new.
///
/// The accessibility assertions are the important ones here, as they are in
/// `HealthAndMarksTests`. This screen draws three verdicts with one function and
/// tells them apart by their words alone — no colour, badge or type size — so the
/// label on a row is the whole of what a VoiceOver reader and a greyscale reader
/// both get, and if it stops naming the verdict the distinction is gone for them.
@MainActor
final class TestsScreenUITests: XCTestCase {

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

    private func openTheTests() {
        app.descendants(matching: .any)["tab-you"].firstMatch.tapWhenReady()
        app.descendants(matching: .any)["row-tests"].firstMatch.tapWhenReady()
    }

    /// The whole reason the feature needed one home: all three states on one screen,
    /// in one order, whichever of them this person happens to be in.
    func testAllThreeSectionsAreOnTheScreenAtOnce() {
        launchToToday()
        openTheTests()

        for section in ["tests-on-offer", "tests-running", "tests-finished"] {
            let element = app.descendants(matching: .any)[section].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: UITest.timeout),
                          "The \(section) section is not on the screen")
        }
    }

    /// Two of the three are empty on most days, which is the common case and not a
    /// failure. The fixture seeds no running test, so this is the exact state a
    /// reader is in for most of a fortnight — and it has to read as a section with
    /// nothing in it rather than as a section that is missing.
    func testAnEmptySectionSaysSoInWords() {
        launchToToday()
        openTheTests()

        let empty = app.descendants(matching: .any)["tests-running-empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: UITest.timeout),
                      "With nothing running, the running section said nothing at all")
        // No "yet" and no "soon": for somebody who never accepts a proposal, that is
        // a promise the app cannot keep.
        for promise in ["YET", "SOON", "COMING"] {
            XCTAssertFalse(empty.label.uppercased().contains(promise),
                           "An empty section made a promise: \(empty.label)")
        }
    }

    /// The whole point of the record: a result outlives the card that showed it.
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

        openTheTests()

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
        openTheTests()

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

    /// An offer on this screen is one line and no controls. The decision belongs to
    /// the card and the sheet it raises, where the premise and the caveat have room
    /// to be read before somebody commits to a fortnight.
    func testAnOfferIsIndexedHereAndDecidedOnToday() {
        launchToToday()
        openTheTests()

        XCTAssertTrue(app.descendants(matching: .any)["tests-on-offer"].firstMatch
            .waitForExistence(timeout: UITest.timeout))

        let offers = app.descendants(matching: .any).matching(identifier: "offer-row")
        guard offers.count > 0 else { return }

        for control in ["open-proposal", "abandon-experiment", "acknowledge-experiment"] {
            XCTAssertFalse(app.descendants(matching: .any)[control].firstMatch.exists,
                           "The Tests screen is offering the card's control: \(control)")
        }
        for index in 0..<offers.count {
            let label = offers.element(boundBy: index).label
            XCTAssertFalse(label.isEmpty, "An offer row has no label")
            XCTAssertFalse(label.first?.isNumber ?? true,
                           "An offer's label opened with a figure: \(label)")
        }
    }

    /// Nothing totals anything — not a rate, not a streak, not "two of three", and
    /// not a count of what is waiting either.
    func testTheScreenCountsNothing() {
        launchToToday()
        openTheTests()

        XCTAssertTrue(app.descendants(matching: .any)["tests-finished"].firstMatch
            .waitForExistence(timeout: UITest.timeout))

        for tally in ["SUCCESS RATE", "HELD UP: ", "2 OF 3", "STREAK",
                      "3 TESTS", "2 OFFERS"] {
            XCTAssertFalse(app.staticTexts[tally].exists,
                           "The screen is keeping score: \(tally)")
        }
    }
}
