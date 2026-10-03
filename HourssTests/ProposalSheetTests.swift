import Foundation
import Testing
@testable import Hourss

/// The accept sheet's words and its two marks, after the owner's reading on device.
///
/// **Why this suite exists at all.** The sheet is where somebody agrees to spend a
/// fortnight, and the redesign moved every one of its sentences: section 4 was
/// shortened, section 3 became a mark, the decline control took its paragraph into
/// its own label, and the drawn window's ask was cut by a third. The things that
/// must survive all of that are not layout facts — they are that all three verdicts
/// are still named in the result's own words before anybody taps, that a starter is
/// still shown a mark with nothing in it, and that nothing anywhere acquired a
/// second wording. None of those can be seen by looking at the screen.
@Suite("The accept sheet")
struct ProposalSheetTests {

    /// Fixed, because a span's far end is an arithmetic fact about its near one and
    /// a test that read the clock would assert against whatever today happened to be.
    ///
    /// Locale and zone are named for the reason `ExperimentAssignmentTests` names
    /// them: a bare `Calendar(identifier:)` formats through ICU's root locale, where
    /// October comes out as "M10" — which would have made the assertions below about
    /// a string no reader ever sees.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    /// Midnight UTC, so a day offset and a calendar day agree exactly.
    static let now = Date(timeIntervalSince1970: 1_767_225_600)   // Thu 1 Jan 2026

    private func proposal(
        standing: ExperimentDesign.Standing = .confirmed,
        context: String? = nil,
        outcome: Outcome = .feeling,
        type: InsightType = .bestTimeWindow
    ) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: outcome, type: type,
            standing: standing,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            context: context,
            change: "Log one session in your morning on most days, for two weeks.",
            caveat: "Time of day travels with whatever you tend to schedule then.",
            priority: .focus, priorityRank: 0, evidenceDays: 20,
            figure: 4.1, baselineFigure: 3.5)
    }

    private func sheet(_ standing: ExperimentDesign.Standing = .confirmed,
                       context: String? = nil,
                       outcome: Outcome = .feeling) -> ExperimentCopy.ProposalSheet {
        ExperimentCopy.sheet(for: proposal(standing: standing, context: context,
                                           outcome: outcome),
                             now: Self.now, calendar: Self.calendar)
    }

    // MARK: - The sequence

    /// The order is the design, and it is the one thing about this screen that a
    /// redesign is most likely to disturb by accident: "what you get at the end" has
    /// to arrive before the terms and before the controls, because the whole purpose
    /// of naming the three verdicts up front is that a null in a fortnight is not a
    /// surprise.
    @Test("Seven headings, in the order a consent flow reads in")
    func theOrder() {
        #expect(sheet().orderedSections.map(\.heading) == [
            ExperimentCopy.whatYouWouldDoHeading,
            ExperimentCopy.whyThisOneHeading,
            ExperimentCopy.howItDecidedHeading,
            ExperimentCopy.whatYouGetHeading,
            ExperimentCopy.howLongHeading,
            ExperimentCopy.whatIsMeasuredHeading,
            ExperimentCopy.limitHeading,
        ])
    }

    @Test("A residual window drops What is measured and keeps the order of the rest")
    func residualDropsOneSection() {
        let headings = sheet(.confirmed, outcome: .heartRateResidual)
            .orderedSections.map(\.heading)
        #expect(!headings.contains(ExperimentCopy.whatIsMeasuredHeading))
        #expect(headings.firstIndex(of: ExperimentCopy.whatYouGetHeading)!
                < headings.firstIndex(of: ExperimentCopy.howLongHeading)!)
    }

    @Test("Nothing on the sheet is blank")
    func nothingEmpty() {
        for section in sheet(.starter, context: "Your sleep reads shorter on Tuesdays.")
            .orderedSections {
            #expect(!section.heading.isEmpty)
            #expect(!section.parts.isEmpty, "\(section.heading) has no parts")
            for line in section.lines {
                #expect(!line.trimmingCharacters(in: .whitespaces).isEmpty,
                        Comment(rawValue: "\(section.heading) has an empty line"))
            }
        }
    }

    // MARK: - Section 4, which is the point of the sheet

    @Test("All three verdicts are named before anybody agrees, in the result's own words")
    func allThreeVerdicts() {
        let parts = sheet().whatYouGet.parts
        let titled: [(String, String)] = parts.compactMap {
            if case .titled(let title, let detail) = $0 { return (title, detail) }
            return nil
        }
        // Three, and named by `verdictTitle` so the sheet and the result cannot
        // drift. Order is the result screen's, so the one that held up is not the
        // one at the bottom.
        #expect(titled.map(\.0) == [
            ExperimentCopy.verdictTitle(.heldUp),
            ExperimentCopy.verdictTitle(.didNotHoldUp),
            ExperimentCopy.verdictTitle(.cannotTell),
        ])
        for (title, gloss) in titled {
            #expect(!gloss.isEmpty, Comment(rawValue: "\(title) has no gloss"))
        }
    }

    /// The formatting half of the redesign, asserted as a structural fact rather
    /// than by looking at it: a verdict set in a quieter register than its
    /// neighbours is the thing this section exists to prevent, and the old view
    /// achieved equality only by a rule about line counts that would have broken on
    /// the next line added.
    @Test("The three verdicts are drawn by one case with no branch between them")
    func verdictsAreEqual() {
        let kinds = sheet().whatYouGet.parts.map { part -> String in
            switch part {
            case .line: "line"
            case .quiet: "quiet"
            case .titled: "titled"
            case .span: "span"
            case .stages: "stages"
            }
        }
        // Preamble, three verdicts, closing line. The three in the middle are the
        // same case as each other and a different case from everything around them.
        #expect(kinds == ["line", "titled", "titled", "titled", "quiet"])
    }

    /// Shortened on the owner's reading — and this is the ceiling, so that the next
    /// person who adds a clause has to decide to raise it.
    @Test("Section 4 is shorter than the paragraph it replaced")
    func sectionFourIsShort() {
        let words = sheet().whatYouGet.lines
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).count
        // It was ninety-five. Seventy-three is where it landed; the ceiling leaves
        // room for a word, not for a sentence.
        #expect(words <= 75, Comment(rawValue: "section 4 is \(words) words"))
        // And it did not get short by dropping a verdict.
        #expect(words >= 40)
    }

    /// The one thing the brief said must not change. A null is not softened, not
    /// hedged, not called unlikely, and the closing line still gives the reason a
    /// test with only one possible answer would not be worth running.
    @Test("Nothing in section 4 makes a null sound unlikely or apologetic")
    func theNullIsNotSoftened() {
        let text = sheet().whatYouGet.lines.joined(separator: " ").lowercased()
        for hedge in ["unlikely", "rarely", "rare", "hopefully", "probably", "usually",
                      "most likely", "don't worry", "do not worry", "unfortunately",
                      "sorry", "fail", "failure", "only if", "chance"] {
            #expect(!text.contains(hedge),
                    Comment(rawValue: "section 4 softened the null with '\(hedge)'"))
        }
        // The argument, not merely the disclaimer: "all three are results" without
        // the second clause is an apology.
        #expect(text.contains("all three are results"))
        #expect(text.contains("would not be worth running"))
    }

    @Test("Section 4 names no direction and no figure")
    func noDirectionInTheGlosses() {
        // A residual window's better side is resolved per person, so a sheet
        // promising "higher" would be wrong for half of them.
        let glosses = [ExperimentCopy.heldUpGloss, ExperimentCopy.didNotHoldUpGloss,
                       ExperimentCopy.cannotTellGloss].joined(separator: " ").lowercased()
        for word in ["higher", "lower", "better", "worse", "more", "improve"] {
            #expect(!glosses.contains(word),
                    Comment(rawValue: "a verdict gloss named a direction: '\(word)'"))
        }
        #expect(NarrationGuard.figures(in: glosses).isEmpty)
    }

    // MARK: - Section 3, which is now a mark

    private func stages(_ standing: ExperimentDesign.Standing)
        -> [ExperimentCopy.ProposalSheet.Stage] {
        for part in sheet(standing).howItDecided.parts {
            if case .stages(let stages) = part { return stages }
        }
        Issue.record("no stages drawn for \(standing)")
        return []
    }

    @Test("Each standing clears a different number of gates")
    func gatesPerStanding() {
        #expect(stages(.confirmed).map(\.cleared) == [true, true])
        #expect(stages(.lead).map(\.cleared) == [true, false])
        // The case that decided the shape of the mark.
        #expect(stages(.starter).map(\.cleared) == [false, false])
    }

    /// A starter has compared nothing, so the mark has to draw nothing — and the
    /// words beside it have to say so rather than leaving two empty boxes to be
    /// interpreted.
    @Test("A starter's mark draws no fill, and the line under it says why")
    func starterDrawsNothing() throws {
        #expect(stages(.starter).allSatisfy { !$0.cleared })
        let note = try #require(ExperimentCopy.howItDecidedNote(.starter))
        #expect(note.lowercased().contains("nothing you have logged"))
        #expect(note.lowercased().contains("measured against anything"))
    }

    /// Two filled marks beside their own labels is the complete statement for a
    /// confirmed claim. A sentence restating it would be the section saying one
    /// thing twice in two registers, which is the drift `ExperimentCopy` exists to
    /// stop.
    @Test("A confirmed claim needs no sentence under its mark")
    func confirmedHasNoNote() {
        #expect(ExperimentCopy.howItDecidedNote(.confirmed) == nil)
        #expect(sheet(.confirmed).howItDecided.parts.count == 1)
        #expect(sheet(.lead).howItDecided.parts.count == 2)
        #expect(sheet(.starter).howItDecided.parts.count == 2)
    }

    /// Fill and colour do not reach VoiceOver, so each gate's state is a word as
    /// well as a mark. This is the half of "colour is never the only carrier" that a
    /// screenshot cannot show.
    @Test("Every gate speaks its own state")
    func gatesSpeakTheirState() {
        for standing in ExperimentDesign.Standing.allCases {
            for stage in stages(standing) {
                #expect(stage.spoken.hasPrefix(stage.label),
                        "a gate's readout did not lead with its subject")
                let state = stage.cleared
                    ? ExperimentCopy.ProposalSheet.Stage.doneWord
                    : ExperimentCopy.ProposalSheet.Stage.pendingWord
                #expect(stage.spoken.contains(state),
                        Comment(rawValue: "\(standing) gate did not say '\(state)'"))
            }
        }
    }

    /// The clause that is a standing rule of the whole app, not a nicety of this
    /// screen: a person is only ever measured against their own history. It was in
    /// all three of the sentences the mark replaced, and it had to land somewhere.
    @Test("The first gate still says nobody else was involved")
    func stillNobodyElse() {
        #expect(ExperimentCopy.comparedStage.lowercased().contains("nobody else"))
        #expect(ExperimentCopy.comparedStage.lowercased().contains("your own record"))
    }

    @Test("Neither gate explains the arithmetic")
    func noMaths() {
        let labels = (ExperimentCopy.comparedStage + " " + ExperimentCopy.correctedStage)
            .lowercased()
        for word in ["interval", "bootstrap", "resample", "confidence", "significance",
                     "p-value", "correction", "percent"] {
            #expect(!labels.contains(word),
                    Comment(rawValue: "a gate label reached for '\(word)'"))
        }
    }

    // MARK: - How long, which is now a span

    @Test("How long is the length, with the window drawn under it")
    func theSpan() {
        let parts = sheet().howLong.parts
        guard case .line(let length) = parts.first else {
            Issue.record("How long did not lead with its length")
            return
        }
        #expect(length == "Two weeks")
        guard parts.count == 2, case .span(let from, let to) = parts[1] else {
            Issue.record("How long did not draw a span")
            return
        }
        #expect(from == ExperimentCopy.spanStart)
        #expect(to == ExperimentCopy.spanEnd(from: Self.now, calendar: Self.calendar))
        // 1 January plus a fortnight, named the way a reader meets it.
        #expect(to == "Thu 15 Jan")
    }

    /// The drift this would have been: the sheet predicts a closing date from now,
    /// the confirmation states one from the window's real start, and they were two
    /// `DateFormatter`s with the same pattern written out twice. One function
    /// formats both.
    @Test("The span's far end and the confirmation's closing date are one string")
    func theTwoDatesAgree() {
        let experiment = Experiment(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: .feeling,
            startedAt: Self.now,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: proposal().premise, change: proposal().change,
            caveat: proposal().caveat)
        let predicted = ExperimentCopy.spanEnd(windowDays: experiment.windowDays,
                                               from: Self.now, calendar: Self.calendar)
        #expect(ExperimentCopy.started(experiment, calendar: Self.calendar)
            .contains(predicted))
    }

    @Test("A window length is spelled once, and the span agrees with the caveat")
    func oneSpelling() {
        // "Two weeks" here and "two weeks" in `randomisedCaveat` come from `span`,
        // which is the whole reason that function is internal.
        #expect(ExperimentCopy.howLong(windowDays: Experiment.defaultWindowDays) == "Two weeks")
        #expect(ExperimentCopy.howLong(windowDays: Experiment.randomisedWindowDays)
                == "Four weeks")
    }

    // MARK: - One mark per question

    /// A diagram per section would be the failure mode of this whole exercise, so
    /// the count is pinned: two marks on the sheet, each answering a different
    /// question, and nothing else drawn.
    @Test("The sheet draws exactly two marks")
    func twoMarks() {
        var spans = 0
        var stageLists = 0
        for section in sheet().orderedSections {
            for part in section.parts {
                if case .span = part { spans += 1 }
                if case .stages = part { stageLists += 1 }
            }
        }
        #expect(spans == 1)
        #expect(stageLists == 1)
    }

    // MARK: - The controls

    /// The label was "Not this one" with two sentences underneath explaining it. A
    /// control that cannot be undone has to say what it does in its own words.
    @Test("The decline control says what it refuses, and has no paragraph")
    func theDecline() {
        let title = ExperimentCopy.declineTitle
        #expect(title == "Don't offer this test again")
        // Scope and permanence, both in the label.
        #expect(title.lowercased().contains("this test"))
        #expect(title.lowercased().contains("again"))
        // And the paragraph is gone from the sheet rather than merely unused.
        let strings = sheet().allStrings
        #expect(!strings.contains { $0.contains("Anything else that comes up still will") })
        #expect(!strings.contains("Not this one"))
        #expect(sheet().controlStrings.contains(title))
    }

    @Test("The drawn offer still states the mechanism and the reason")
    func theDrawnAsk() {
        let ask = ExperimentCopy.randomisedAsk(
            windowDays: Experiment.randomisedWindowDays,
            assignedDays: Experiment.randomisedWindowDays / 2)
        // Shorter, and neither half was lost: what the app does, and what it buys.
        #expect(ask.split(whereSeparator: \.isWhitespace).count <= 36)
        #expect(ask.contains("14"))
        #expect(ask.contains("28"))
        #expect(ask.lowercased().contains("you would rather not"))
        #expect(ask.lowercased().contains("did not pick"))
        // The verdict's own word, so the ask and the result name one outcome.
        #expect(ask.contains("held up"))
        // And it still promises nothing about the change.
        for claim in ["will work", "proves", "guarantee", "better"] {
            #expect(!ask.lowercased().contains(claim),
                    Comment(rawValue: "the drawn ask claimed '\(claim)'"))
        }
    }

    @Test("Three controls, and the drawn one is absent where the days cannot be drawn")
    func theControls() {
        #expect(sheet().randomised?.title == ExperimentCopy.randomiseTitle)
        let notDrawable = ExperimentCopy.sheet(
            for: proposal(standing: .confirmed, outcome: .feeling, type: .workdayContrast),
            now: Self.now, calendar: Self.calendar)
        #expect(notDrawable.randomised == nil)
        #expect(notDrawable.controlStrings
            == [ExperimentCopy.startTitle, ExperimentCopy.declineTitle])
    }

    // MARK: - The sweep

    /// What `authoredStrings` is for, asserted against the thing that used to break
    /// it: it was a hand-written list of appends, one per field, and a section
    /// gaining a part did not gain a sweep.
    @Test("Carried sentences are subtracted and everything else is swept")
    func theSweepSeesEverything() {
        let context = "Your sleep reads 48m shorter on Tuesdays than Saturdays."
        let value = sheet(.starter, context: context)
        let authored = Set(value.authoredStrings)

        // The proposal's own four sentences are swept where they are built.
        for carried in [proposal().change, proposal().premise, proposal().caveat, context] {
            #expect(!authored.contains(carried),
                    Comment(rawValue: "a carried sentence was swept twice: \(carried)"))
            #expect(value.allStrings.contains(carried),
                    Comment(rawValue: "a carried sentence never reached the screen"))
        }

        // Everything the redesign added is in it.
        for authoredString in [ExperimentCopy.verdictPreamble, ExperimentCopy.heldUpGloss,
                               ExperimentCopy.didNotHoldUpGloss, ExperimentCopy.cannotTellGloss,
                               ExperimentCopy.verdictClosing, ExperimentCopy.declineTitle,
                               ExperimentCopy.verdictTitle(.heldUp),
                               ExperimentCopy.verdictTitle(.didNotHoldUp),
                               ExperimentCopy.verdictTitle(.cannotTell)] {
            #expect(authored.contains(authoredString),
                    Comment(rawValue: "not swept: \(authoredString)"))
        }

        // Both marks' labels too, which is the thing most likely to end up authored
        // in a view and invisible to this. A mark contributes one composed string
        // per row — a gate's label with its state, and the span's two ends as the
        // one phrase they are read as — so the assertion is containment rather than
        // membership.
        let joined = value.allStrings.joined(separator: " | ")
        for label in [ExperimentCopy.comparedStage, ExperimentCopy.correctedStage,
                      ExperimentCopy.spanStart,
                      ExperimentCopy.spanEnd(from: Self.now, calendar: Self.calendar),
                      ExperimentCopy.ProposalSheet.Stage.pendingWord] {
            #expect(joined.contains(label), Comment(rawValue: "not swept: \(label)"))
        }
    }

    /// The sweep itself. `instruction` is excluded and only `instruction`, as
    /// everywhere else in this feature: this sheet's whole content is an instruction
    /// about a fortnight. Causal, clinical and population offences fail here exactly
    /// as they do in narration — and the date formatter's own output is swept too,
    /// because a weekday name is the one string in this feature the app does not
    /// write.
    @Test("No sentence on the sheet makes a causal, clinical or population claim")
    func copyPassesTheGuard() {
        var strings: [String] = []
        for standing in ExperimentDesign.Standing.allCases {
            for outcome in [Outcome.feeling, .performance, .heartRateResidual] {
                strings += ExperimentCopy.sheet(
                    for: proposal(standing: standing,
                                  context: "Your sleep reads 48m shorter on Tuesdays.",
                                  outcome: outcome),
                    now: Self.now, calendar: Self.calendar).authoredStrings
            }
            for stage in stages(standing) { strings.append(stage.spoken) }
        }
        strings.append(ExperimentCopy.ProposalSheet.Stage.doneWord)
        strings.append(ExperimentCopy.ProposalSheet.Stage.pendingWord)
        strings.append(ExperimentCopy.spanStart)
        // Every day of a month, so a weekday or month name that offends is caught
        // whichever day somebody opens the sheet on.
        for offset in 0..<31 {
            let day = Self.calendar.date(byAdding: .day, value: offset, to: Self.now)!
            strings.append(ExperimentCopy.spanEnd(from: day, calendar: Self.calendar))
        }

        for text in strings {
            let offence = NarrationGuard.offence(
                in: text, allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }

    /// Readouts name their subject first — the rule `DESIGN.md` records, and the
    /// reason no label on this screen opens with a figure. Every block is spoken as
    /// one element, so there are exactly seven readouts and each has to lead with
    /// its own heading.
    @Test("Every block's readout leads with its heading")
    func readoutsNameTheirSubject() {
        for section in sheet(.lead).orderedSections {
            #expect(section.spoken.hasPrefix(section.heading),
                    Comment(rawValue: "\(section.heading) did not lead its own readout"))
            let first = section.spoken.first.map(String.init) ?? ""
            #expect(Int(first) == nil, "a readout opened with a figure")
        }
    }
}
