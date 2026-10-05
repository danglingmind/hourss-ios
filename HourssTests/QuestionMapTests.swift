import Foundation
import Testing
import UIKit
@testable import Hourss

/// That the map of questions is a map and not a wall — and that making it one
/// introduced no score, no order and no promise.
///
/// **Not `@MainActor`, deliberately, and that is part of the assertion.**
/// `PatternsView.partition` is `nonisolated` because it filters a value type and
/// touches nothing on the main actor; a suite that reached it only by being
/// `@MainActor` itself would hide a later change that made it touch the store. The
/// one test here that does build a store is marked individually. The hazard this
/// project has hit twice — a static helper on a SwiftUI `View` inheriting the
/// view's isolation, compiling, then trapping at runtime and looking like a
/// shrinking test count — is the reason both halves are spelled out rather than
/// left to inference.
@Suite("Question map")
struct QuestionMapTests {

    private func pending(id: String, focusLabel: String, baselineLabel: String = "The rest",
                         focusDays: Int, baselineDays: Int) -> Engine.Pending {
        Engine.Pending(
            hypothesis: Hypothesis(
                id: id, type: .bestTimeWindow, outcome: .feeling,
                focusLabel: focusLabel, baselineLabel: baselineLabel,
                focus: { _ in true }, baseline: { _ in false },
                phrase: { _ in "" }, caveat: ""
            ),
            focusDays: focusDays, baselineDays: baselineDays
        )
    }

    /// Short by a countable amount. Stays printed.
    private func close(_ id: String, _ label: String) -> Engine.Pending {
        pending(id: id, focusLabel: label, focusDays: 4, baselineDays: 20)
    }

    /// One side has never happened. Goes behind the fold.
    private func far(_ id: String, _ label: String) -> Engine.Pending {
        pending(id: id, focusLabel: label, focusDays: 0, baselineDays: 20)
    }

    // MARK: What folds and what does not

    /// The whole claim the fold makes about itself.
    @Test("The countable half stays on screen and the untouched half folds")
    func theActionableHalfIsPrinted() {
        let questions = [
            close("time.morning.vs.rest.feeling", "Morning"),
            far("time.evening.vs.rest.feeling", "Evening"),
            far("time.night.vs.rest.feeling", "Night"),
            close("duration.medium.vs.rest.feeling", "60–120 min"),
        ]
        let split = PatternsView.partition(questions)

        #expect(split.shown.map(\.hypothesis.focusLabel) == ["Morning", "60–120 min"])
        #expect(split.folded.map(\.hypothesis.focusLabel) == ["Evening", "Night"])
        // The two halves are the whole list and nothing is in both. A question that
        // vanished in the split would be a question the engine is watching and the
        // screen never names, which is worse than a wall.
        #expect(split.shown.count + split.folded.count == questions.count)
        #expect(Set(split.shown.map(\.hypothesis.id))
            .isDisjoint(with: Set(split.folded.map(\.hypothesis.id))))
    }

    /// A lid over one row spends the line it saves.
    @Test("A single untouched question is printed rather than folded")
    func oneIsNotWorthALid() {
        let one = PatternsView.partition([
            close("time.morning.vs.rest.feeling", "Morning"),
            far("time.evening.vs.rest.feeling", "Evening"),
        ])
        #expect(one.folded.isEmpty)
        #expect(one.shown.count == 2)

        // Two is the threshold, and from two upwards the fold pays for itself.
        let two = PatternsView.partition([
            far("time.evening.vs.rest.feeling", "Evening"),
            far("time.night.vs.rest.feeling", "Night"),
        ])
        #expect(two.shown.isEmpty)
        #expect(two.folded.count == 2)
    }

    /// `isUntouched` is either side, and the thinner side is not always the focus.
    @Test("A record with only one kind of thing in it folds too")
    func anEmptyBaselineIsAlsoUntouched() {
        // Everything rated is a morning, so the morning question has nothing on the
        // other side. "Everything you have rated is in one place" is a sentence about
        // something that has not happened, same as "no sessions in your evening yet",
        // and it belongs in the same place.
        let questions = [
            pending(id: "time.morning.vs.rest.feeling", focusLabel: "Morning",
                    focusDays: 20, baselineDays: 0),
            far("time.evening.vs.rest.feeling", "Evening"),
            close("duration.medium.vs.rest.feeling", "60–120 min"),
        ]
        let split = PatternsView.partition(questions)
        #expect(split.folded.count == 2)
        #expect(split.shown.map(\.hypothesis.focusLabel) == ["60–120 min"])
    }

    /// `PRD-LOCKS.md` §6, which the fold had every opportunity to break.
    @Test("Neither half is sorted, by closeness or by anything else")
    func nothingIsReordered() {
        // Deliberately out of any order a human would choose: the far ones are not
        // last, the close ones do not ascend, and a split that sorted either half
        // would make this list come back rearranged. Ordering by closeness turns the
        // screen into a list of things to go and log, which is how a record becomes a
        // chore.
        let questions = [
            pending(id: "a", focusLabel: "A", focusDays: 5, baselineDays: 20),
            far("b", "B"),
            pending(id: "c", focusLabel: "C", focusDays: 1, baselineDays: 20),
            far("d", "D"),
            pending(id: "e", focusLabel: "E", focusDays: 3, baselineDays: 20),
        ]
        let split = PatternsView.partition(questions)

        // Registry order, preserved inside each half.
        #expect(split.shown.map(\.hypothesis.id) == ["a", "c", "e"])
        #expect(split.folded.map(\.hypothesis.id) == ["b", "d"])

        // And the shortfalls prove it is not closeness: 4, 5, 3 is neither
        // ascending nor descending.
        #expect(split.shown.map(\.shortfall) == [1, 5, 3])
    }

    @Test("An empty list produces no fold, so a priority with nothing waiting grows no lid")
    func nothingWaitingIsNothing() {
        let split = PatternsView.partition([])
        #expect(split.shown.isEmpty)
        #expect(split.folded.isEmpty)
    }

    // MARK: The label on the lid

    /// A collapsed group that does not say what is in it is a mystery box.
    @Test("The fold names what is inside it")
    func theLabelIsNotAMysteryBox() {
        let label = QuestionCopy.foldedHeading
        // "Questions" — the same kind of row as the ones printed above it.
        #expect(label.lowercased().contains("question"))
        // And the gap, which is what distinguishes these from the printed ones: days
        // are missing, rather than the question being short by an amount. "Empty
        // side" said that in the engine's own terms — a question has two sides and
        // one of them has nothing on it — and a reader has no sides.
        #expect(label.lowercased().contains("missing"))
    }

    /// The line this feature is one word away from on either side.
    @Test("The fold quotes no figure, in any form")
    func noCountAnywhere() {
        // "4 more questions" is a fact about the screen and would have been legal.
        // "4 of 12 open" is a scoreboard and §6 forbids it. The distance between them
        // is one word, so the fold computes neither and the test pins that there is
        // no digit and no number-word on the lid at all.
        let authored = [QuestionCopy.foldedHeading,
                        QuestionCopy.foldOpenHint,
                        QuestionCopy.foldCloseHint,
                        QuestionCopy.waitingHeading]
        for line in authored {
            #expect(!line.contains { $0.isNumber },
                    Comment(rawValue: "a figure reached the fold: \(line)"))
            for word in ["one", "two", "three", "four", "five", "six", "seven",
                         "eight", "nine", "ten", "several", "many", "of 12",
                         "%", "left", "remaining", "complete", "progress"] {
                #expect(!line.lowercased().contains(word),
                        Comment(rawValue: "'\(word)' counted something: \(line)"))
            }
        }
    }

    /// §2: you unlock a question, not an answer.
    @Test("Nothing on the lid promises a finding, or that opening it is a reward")
    func theLidPromisesNothing() {
        for line in [QuestionCopy.foldedHeading,
                     QuestionCopy.foldOpenHint,
                     QuestionCopy.foldCloseHint] {
            let text = line.lowercased()
            // The first eight are the sweep `QuestionCopyTests` already runs on the
            // waiting sentences. The rest are specific to a control somebody taps:
            // a tap that "unlocks", "reveals" or offers "more" has been dressed as a
            // payout, and what is behind this one is a list of things that have not
            // happened.
            for promise in ["unlock", "reveal", "discover", "find out", "will show",
                            "waiting to", "coming", "soon", "see what", "explore",
                            "tap to", "locked", "hidden", "secret", "yet"] {
                #expect(!text.contains(promise),
                        Comment(rawValue: "'\(promise)' made the fold a payout: \(line)"))
            }
        }
    }

    /// `PRD-LOCKS.md` §10 item 16, for the one line the fold adds to the screen.
    ///
    /// **Measured in the real typeface at the real scaled size, not guessed from a
    /// character count.** The first draft of this test allowed forty characters on
    /// the reasoning that `.action` is about twenty to the line at `AccessibilityL`.
    /// That reasoning is right and the arithmetic behind it is exactly the kind
    /// nobody checks again — DM Sans Bold's advances are not uniform, the arrow and
    /// its 6pt gap come out of the same line, and `UIFontMetrics` decides the scale
    /// rather than a multiplier somebody wrote down. So this lays the string out and
    /// counts the lines.
    ///
    /// The fold's whole purpose is to make a section shorter. A lid whose own label
    /// runs to four lines has not shortened anything, which is why two is the budget
    /// rather than a round number.
    @Test("The lid's label lays out in two lines at AccessibilityL")
    func theLabelFitsTwoLines() throws {
        let style = TypeStyle.action
        // `relativeTo: .subheadline` is what `.action` scales on, so the metric has
        // to be the same one — asking `.body` for the scale would flatter it.
        #expect(style.relativeTo == .subheadline,
                Comment(rawValue: "`.action` stopped scaling on .subheadline, so this "
                        + "measures the wrong ramp"))
        let scaled = UIFontMetrics(forTextStyle: .subheadline)
            .scaledValue(for: style.size,
                         compatibleWith: UITraitCollection(preferredContentSizeCategory:
                                                            .accessibilityLarge))
        let font = try #require(UIFont(name: style.postScriptName, size: scaled),
                                "DM Sans Bold did not resolve, so this measured nothing")

        // The narrowest screen the app ships on, not the widest: 375pt less the 18pt
        // gutter on each side. `DirectionalLink` then puts the arrow on the same line
        // at a fixed 18pt with `Space.xs - 2` of spacing, and the label wraps inside
        // what is left.
        let arrow = ("↘" as NSString).size(withAttributes: [
            .font: UIFont(name: FontFamily.sans.postScriptName(weight: 700), size: 18)
                ?? .boldSystemFont(ofSize: 18),
        ]).width
        let column = 375 - 2 * Space.gutter - arrow - 6

        // The measurement proves it can fail before it is trusted. Without
        // `.usesLineFragmentOrigin` `boundingRect` measures one long line and every
        // label on earth passes — the same way a test that hedges with an `||`
        // passes, which this project has already been caught by once.
        let overlong = Self.lineCount(
            "Questions about the things in your record that have not happened yet",
            font: font, width: column)
        #expect(overlong > 2,
                Comment(rawValue: "the layout is not wrapping — a 67-character label "
                        + "measured \(overlong) lines, so this test cannot fail"))

        let lines = Self.lineCount(QuestionCopy.foldedHeading, font: font, width: column)
        #expect(lines <= 2,
                Comment(rawValue: "'\(QuestionCopy.foldedHeading)' lays out in \(lines) "
                        + "lines at \(Int(scaled))pt in a \(Int(column))pt column — a "
                        + "lid that tall has not shortened the section it covers"))
    }

    /// Lines the string takes at this font and width, by laying it out.
    ///
    /// `.usesLineFragmentOrigin` is the option that makes `boundingRect` wrap at all;
    /// without it the call measures one long line and every label passes.
    private static func lineCount(_ text: String, font: UIFont, width: CGFloat) -> Int {
        let height = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        return max(1, Int((height / font.lineHeight).rounded()))
    }

    /// The label stands over the rows while they are showing, so it cannot be the
    /// kind of label that changes into a control.
    @Test("One label, both states")
    func theNameDoesNotBecomeAControl() {
        // Whether the fold is open is not a parameter of the heading: there is one
        // string, and the arrow is what carries the state. If a second heading ever
        // appears here, the rows it reveals will have lost the only thing standing
        // over them saying what they are.
        #expect(QuestionCopy.foldOpenHint != QuestionCopy.foldedHeading)
        #expect(QuestionCopy.foldCloseHint != QuestionCopy.foldedHeading)
        // Hints are the only thing that differs by state, and they are spoken rather
        // than printed.
        #expect(QuestionCopy.foldOpenHint != QuestionCopy.foldCloseHint)
    }

    // MARK: On a real record

    /// The wall, measured on real records rather than on four hand-written rows.
    ///
    /// **Two people, because the fold does not bite equally.** Six weeks of varied
    /// history leaves most waiting questions merely *close* — the activity and health
    /// families are minted from what somebody actually logged, so their focus side is
    /// rarely empty. A short, lopsided record is where the untouched half dominates,
    /// and it is also where the screen can least afford a wall. Asserting the
    /// invariant on only the rich person would have let the fold rot untested, which
    /// is what the first draft of this test did.
    @Test("The fold never makes a priority taller, and the printed half is the countable half")
    @MainActor
    func theScreenGetsShorter() {
        var foldedSomewhere = false

        for person in [SyntheticCohort.afternoonSlump, SyntheticCohort.shortHistory] {
            let store = HourssStore(repository: InMemoryRecordRepository())
            store.profile.priorities = [.focus, .energy, .balance]
            store.activities = person.activities
            store.sessions = person.sessions
            store.reflections = person.reflections
            store.applyHealthContext(person.healthByDay)
            store.rebuildInsights()

            let all = Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                      priorities: store.profile.priorities))
            #expect(!all.isEmpty,
                    Comment(rawValue: "\(person.name) stopped producing waiting questions"))

            for priority in store.profile.priorities {
                let mine = all.filter { priority.insightTypes.contains($0.hypothesis.type) }
                guard !mine.isEmpty else { continue }
                let split = PatternsView.partition(mine)

                // The lid plus the printed rows is never taller than the unfolded
                // list. A section that grew would be a wall with a lid on it, which
                // is the one outcome this phase cannot have.
                let height = split.shown.count + (split.folded.isEmpty ? 0 : 1)
                #expect(height <= mine.count,
                        Comment(rawValue: "\(person.name)/\(priority.title) got taller: "
                                + "\(height) rows for \(mine.count) questions"))
                if !split.folded.isEmpty { foldedSomewhere = true }

                // Everything printed that is short by an amount carries that amount,
                // which is the claim "the close ones stay visible" rests on.
                for question in split.shown where !question.isUntouched {
                    #expect(question.shortfall >= 1)
                    #expect(QuestionCopy.waiting(question).contains { $0.isNumber })
                }
                // The one exception, by design: a lone untouched question is printed
                // rather than given a lid of its own. One, and only when nothing
                // folded — otherwise the split has leaked.
                let printedFar = split.shown.filter(\.isUntouched)
                #expect(printedFar.count <= 1,
                        Comment(rawValue: "\(person.name)/\(priority.title) printed "
                                + "\(printedFar.count) untouched questions"))
                if !printedFar.isEmpty { #expect(split.folded.isEmpty) }

                // Everything folded names an absence instead, and quotes no
                // shortfall — a number here would be one nobody can act on by doing
                // more of what they are already doing.
                for question in split.folded {
                    #expect(question.isUntouched)
                    #expect(!QuestionCopy.waiting(question).contains("more day"))
                }
            }
        }

        #expect(foldedSomewhere,
                Comment(rawValue: "neither cohort folded anything, so the fold is "
                        + "never exercised against a real record"))
    }
}
