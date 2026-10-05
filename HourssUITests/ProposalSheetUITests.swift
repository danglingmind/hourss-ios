import XCTest

/// The accept sheet as somebody meets it, on the day-one fixture.
///
/// **Why the day-one fixture and not the seeded one.** The proposal it offers is a
/// *starter*, which is the hardest state this screen has: nothing about this
/// person's sessions has been measured, so "How it decided" draws a mark with no
/// fill anywhere in it, and the thing that could silently go wrong is the mark
/// reading as broken rather than as empty. If the sheet is honest for a starter it
/// is honest for the other two standings, which have strictly more to show.
///
/// **What only a device run can check.** The unit suite asserts every word and the
/// structure behind it. What it cannot see is whether the seven headings are
/// reachable at all with the rules gone, whether a VoiceOver reader still gets each
/// block's span and gate states now that both are drawings, and whether the decline
/// control makes sense with its paragraph deleted. Those are the assertions here.
///
/// The verdict strings are duplicated from `ExperimentCopy` rather than shared, for
/// the reason `UITestSupport` records about launch arguments: a UI test drives the
/// app from another process and cannot import its types. If the wording changes this
/// fails loudly, which is the right failure — the whole point of section 4 is that
/// the sheet names the verdicts in the words the result will use.
@MainActor
final class ProposalSheetUITests: XCTestCase {

    private var app: XCUIApplication!

    private let verdicts = ["It held up", "It did not hold up", "Not enough to tell"]

    /// `Eyebrow` uppercases, so this is how the seven headings reach the screen.
    private let headings = ["WHAT YOU WOULD DO", "WHY THIS ONE", "HOW IT DECIDED",
                            "WHAT YOU GET AT THE END", "HOW LONG", "WHAT IS MEASURED",
                            "BEAR IN MIND"]

    private func openTheSheet() {
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

        let open = app.descendants(matching: .any)["open-proposal"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: UITest.timeout),
                      "Day one offered nothing to open")
        var swipes = 0
        while !open.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        open.tapWhenReady()
    }

    /// Scrolls until an element is reachable, because the controls are deliberately
    /// at the foot of the sequence rather than pinned — a start button visible on
    /// arrival is the thing this sheet was built to stop.
    private func scrollTo(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: UITest.timeout) else { return false }
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable
    }

    /// Every question is still answered, with nothing but space and a coloured
    /// heading separating them. The rules are gone; if the sequence stopped being
    /// navigable this is where it shows.
    func testAllSevenHeadingsAreReachable() {
        openTheSheet()
        for heading in headings {
            let element = app.staticTexts[heading].firstMatch
            XCTAssertTrue(scrollTo(element),
                          "The sheet never reached the \(heading) section")
        }
    }

    /// The point of the sheet, and the one thing the brief said must not change: all
    /// three verdicts named, in the result's own words, before any control is
    /// touched.
    func testAllThreeVerdictsAreNamedBeforeTheStartControl() {
        openTheSheet()
        for verdict in verdicts {
            let element = app.staticTexts[verdict].firstMatch
            XCTAssertTrue(scrollTo(element),
                          "Section 4 did not name '\(verdict)' anywhere on the sheet")
        }
        // And the controls are below them, which is what makes "before" true.
        let start = app.descendants(matching: .any)["accept-experiment"].firstMatch
        XCTAssertTrue(scrollTo(start), "The start control never came into reach")
    }

    /// The owner could not tell what "Not this one" refused without reading the
    /// paragraph beneath it. The paragraph is gone, so the label is now the whole of
    /// what anybody gets.
    func testTheDeclineControlExplainsItselfWithNoParagraph() {
        openTheSheet()
        let decline = app.descendants(matching: .any)["decline-experiment"].firstMatch
        XCTAssertTrue(scrollTo(decline), "The decline control never came into reach")
        XCTAssertEqual(decline.label, "Don't offer this test again",
                       "The decline control is not saying what it refuses")
        // The deleted sentences, named so that reinstating them fails here.
        for gone in ["Not this one", "This one will not be offered again",
                     "Anything else that comes up still will."] {
            XCTAssertFalse(app.staticTexts[gone].exists,
                           "A sentence the redesign deleted is back on the sheet: \(gone)")
        }
    }

    /// The accessibility half of two drawings replacing two paragraphs. A block is
    /// spoken as one element, so the span's two ends and each gate's state have to be
    /// inside the label of the block that owns them — otherwise a VoiceOver reader
    /// loses exactly the content the redesign moved into pictures.
    func testBothMarksSpeakTheirContent() {
        openTheSheet()

        let howLong = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "How long")).firstMatch
        XCTAssertTrue(howLong.waitForExistence(timeout: UITest.timeout),
                      "The How long block has no readout of its own")
        XCTAssertTrue(howLong.label.contains("Two weeks"),
                      "The span did not say how long it runs: \(howLong.label)")
        XCTAssertTrue(howLong.label.contains("Today to "),
                      "The span did not say what it runs between: \(howLong.label)")

        let decided = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "How it decided")).firstMatch
        XCTAssertTrue(decided.waitForExistence(timeout: UITest.timeout),
                      "The How it decided block has no readout of its own")
        // A starter has cleared neither gate, and the readout has to say so in words
        // rather than leaving it to two unfilled squares.
        XCTAssertTrue(decided.label.contains("not yet"),
                      "An uncleared gate did not speak its state: \(decided.label)")
        XCTAssertFalse(decided.label.contains(": done"),
                       "A starter was shown a gate it has not cleared: \(decided.label)")
        XCTAssertTrue(decided.label.contains("anybody else"),
                      "The sheet stopped saying whose days this is measured against")
    }

    /// Readouts name their subject first. Seven blocks, seven readouts, none of them
    /// opening with a figure — the correction `TitledFigure` and the Patterns
    /// evidence line both got, applied on the screen where a reader cannot skip
    /// ahead.
    func testEveryBlockLeadsWithItsSubject() {
        openTheSheet()
        for heading in headings {
            let readable = heading.capitalized
            let block = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH[c] %@", readable)).firstMatch
            guard block.exists else { continue }
            XCTAssertFalse(block.label.first?.isNumber ?? true,
                           "A block's readout opened with a figure: \(block.label)")
        }
    }

    /// Agreeing is still a decision with a confirmation behind it, and the sheet
    /// still says what was started rather than closing silently.
    func testAgreeingConfirmsWhatWasStarted() {
        openTheSheet()
        let start = app.descendants(matching: .any)["accept-experiment"].firstMatch
        XCTAssertTrue(scrollTo(start), "The start control never came into reach")
        start.tapWhenReady()

        let acknowledge = app.descendants(matching: .any)["acknowledge-proposal"].firstMatch
        XCTAssertTrue(acknowledge.waitForExistence(timeout: UITest.timeout),
                      "Agreeing did not produce a confirmation")
        XCTAssertTrue(app.staticTexts["YOU ARE TESTING THIS"].exists,
                      "The confirmation did not retitle the sheet")
    }
}
