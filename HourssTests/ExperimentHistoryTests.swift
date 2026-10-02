import Foundation
import Testing
@testable import Hourss

/// The record of what somebody has tested: what reaches it, in what order, and the
/// three things it must never become — a scoreboard, a second wording of a result,
/// or a list where the successes are easier to find than the rest.
///
/// **Not `@MainActor`, and that is checked rather than assumed.** `ExperimentHistory`
/// is an `enum` beside the view rather than a static helper *on* it, so nothing
/// infers main-actor isolation from a SwiftUI type. This project has twice shipped a
/// static helper on a `View` that was isolated by inference, called it from a suite
/// that was not, and watched the test host trap at runtime — which looks like a
/// shrinking test count and not like a crash.
@Suite("Experiment history")
struct ExperimentHistoryTests {

    /// Every verdict, written out.
    ///
    /// `Experiment.Verdict` is not `CaseIterable` and `Hourss/Model/` is not this
    /// change's to edit, so the set is listed here — and `verdictListIsComplete`
    /// below is what keeps the list honest rather than hopeful.
    private let verdicts: [Experiment.Verdict] = [.heldUp, .didNotHoldUp, .cannotTell]

    private let change = "Put one block in your morning on most days this fortnight."
    private let caveat = "Time of day travels with whatever you tend to schedule then."

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func experiment(startedAt: Date, change: String? = nil) -> Experiment {
        Experiment(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: .feeling, startedAt: startedAt,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            change: change ?? self.change, caveat: caveat)
    }

    private func settlement(_ verdict: Experiment.Verdict, at settledAt: Date) -> Experiment.Settlement {
        Experiment.Settlement(
            verdict: verdict, adherenceDays: 9, baselineDays: 12,
            focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
            intervalLow: 0.1, intervalHigh: 0.7, settledAt: settledAt)
    }

    private func settled(_ verdict: Experiment.Verdict, startedAt: Date) -> Experiment {
        var e = experiment(startedAt: startedAt)
        e.settlement = settlement(verdict, at: e.endsAt())
        return e
    }

    private func acknowledged(_ verdict: Experiment.Verdict, startedAt: Date) -> Experiment {
        var e = settled(verdict, startedAt: startedAt)
        e.acknowledgedAt = e.endsAt()
        return e
    }

    private func abandoned(startedAt: Date, stoppedAt: Date) -> Experiment {
        var e = experiment(startedAt: startedAt)
        e.abandonedAt = stoppedAt
        return e
    }

    // MARK: The set under test

    @Test("The verdict list this suite checks is the whole set")
    func verdictListIsComplete() {
        // A fourth verdict is a compile error in this switch rather than a verdict
        // the rest of the suite silently stops checking. `Verdict: CaseIterable`
        // would do this in one word and belongs in the model; this is the version
        // available from here.
        let indexed = verdicts.map { verdict -> Int in
            switch verdict {
            case .heldUp: 0
            case .didNotHoldUp: 1
            case .cannotTell: 2
            }
        }
        #expect(Set(indexed).count == verdicts.count)
        #expect(indexed.sorted() == Array(0..<verdicts.count))
    }

    // MARK: What reaches the record

    /// The reason the screen exists: acknowledging dismisses the card, not the
    /// result.
    @Test("An acknowledged result is still in the record")
    func acknowledgedStays() {
        let e = acknowledged(.heldUp, startedAt: day(-40))
        #expect(e.phase == .acknowledged)
        let entries = ExperimentHistory.entries(from: [e])
        #expect(entries.count == 1)
        #expect(entries.first?.subject == change)
    }

    @Test("A running fortnight is not in the record")
    func activeIsExcluded() {
        // Today owns the active card and shows it every day of the window. A row
        // with no outcome at the top of a list of outcomes would be the one entry
        // here making a promise.
        let running = experiment(startedAt: day(-3))
        #expect(running.phase == .active)
        #expect(ExperimentHistory.entries(from: [running]).isEmpty)
    }

    @Test("Newest first, across both kinds of ending")
    func newestFirst() {
        let old = settled(.heldUp, startedAt: day(-60))
        let middle = abandoned(startedAt: day(-40), stoppedAt: day(-33))
        let recent = settled(.cannotTell, startedAt: day(-20))

        let entries = ExperimentHistory.entries(from: [old, middle, recent])
        #expect(entries.map(\.id) == [recent.id, middle.id, old.id])
    }

    /// Settling runs on the next launch or foreground, not at the closing instant,
    /// so a window that closed while the phone was off can be stamped days late.
    @Test("Order follows the window that closed, not the launch that noticed")
    func orderIgnoresTheLateSettling() {
        var first = experiment(startedAt: day(-60))
        // Closed long ago, noticed today.
        first.settlement = settlement(.heldUp, at: Date())
        let second = settled(.didNotHoldUp, startedAt: day(-20))

        let entries = ExperimentHistory.entries(from: [first, second])
        #expect(entries.map(\.id) == [second.id, first.id],
                "a late settling must not reorder the record")
    }

    // MARK: The three verdicts

    /// The equal-weight rule, as the list's version of the test already pinning it
    /// for Today's card.
    @Test("The three verdicts are built identically and each names itself")
    func verdictsAreEqual() {
        let built = verdicts.map { verdict in
            (verdict, ExperimentHistory.entries(
                from: [settled(verdict, startedAt: day(-30))]).first)
        }

        for (verdict, entry) in built {
            guard let entry else {
                Issue.record("\(verdict) produced no entry at all")
                continue
            }
            // Same four fields filled, every time. An entry that was structurally
            // shorter than its neighbours would land on `cannotTell` first — the
            // verdict with the least to say and the most to lose from being drawn
            // smaller.
            #expect(!entry.subject.isEmpty)
            #expect(!entry.standing.isEmpty)
            #expect(!entry.report.isEmpty)
            #expect(!entry.window.isEmpty)
            // The verdict is a phrase, so colour and position are never carrying it.
            #expect(entry.standing == ExperimentCopy.verdictTitle(verdict))
            // Every entry says what was tested, whichever way it went.
            #expect(entry.subject == change)
        }

        // And the three say different things, so "identical structure" is not
        // "indistinguishable".
        let standings = built.compactMap { $0.1?.standing }
        #expect(Set(standings).count == verdicts.count)
    }

    /// A result phrased twice in two places is how a claim and its card drift apart,
    /// which is the mistake this codebase documents most often.
    @Test("The report is the wording the result already has, never a second one")
    func noSecondWording() {
        for verdict in verdicts {
            let e = settled(verdict, startedAt: day(-30))
            guard let settlement = e.settlement,
                  let entry = ExperimentHistory.entries(from: [e]).first else {
                Issue.record("\(verdict) produced no entry")
                continue
            }
            #expect(entry.report == ExperimentCopy.result(for: e, settlement: settlement))
            #expect(entry.standing == ExperimentCopy.verdictTitle(settlement.verdict))
        }
    }

    // MARK: Stopped experiments

    @Test("A stopped experiment is kept, and is plainly not a verdict")
    func stoppedIsKeptAndIsNotAVerdict() {
        let e = abandoned(startedAt: day(-30), stoppedAt: day(-24))
        guard let entry = ExperimentHistory.entries(from: [e]).first else {
            Issue.record("a stopped experiment was dropped from the record")
            return
        }
        // Kept, because a record that silently drops what somebody stopped is a
        // selection they cannot see being made.
        #expect(entry.subject == change)
        #expect(entry.standing == ExperimentHistory.stoppedStanding)
        // And never dressed as a fourth verdict: none of the three verdict phrases
        // appears anywhere in it.
        let text = (entry.standing + " " + entry.report).lowercased()
        for verdict in verdicts {
            #expect(!text.contains(ExperimentCopy.verdictTitle(verdict).lowercased()),
                    Comment(rawValue: "a stopped entry borrowed a verdict's words: \(text)"))
        }
        // No figures, because nothing was read.
        #expect(NarrationGuard.figures(in: entry.report).isEmpty)
    }

    // MARK: Nothing is counted

    /// `RecordFacts` argues this at length and `abandonExperiment` keeps no tally: a
    /// number whose only use is a reproach does not get computed. A list that totals
    /// its own verdicts is that number assembled by the reader instead.
    @Test("Nothing the screen writes for itself counts anything")
    func nothingIsCounted() {
        for text in ExperimentHistory.authored {
            #expect(NarrationGuard.figures(in: text).isEmpty,
                    Comment(rawValue: "the screen's own copy quoted a figure: \(text)"))
            let flat = text.lowercased()
            for tally in ["out of", "success", "rate", "streak", "record of", "in a row",
                          "so far", "total", "times"] {
                #expect(!flat.contains(tally),
                        Comment(rawValue: "'\(tally)' in: \(text)"))
            }
        }
    }

    /// The whole record, from a mixed history, and no aggregate anywhere in it.
    @Test("A mixed history produces rows and nothing above them")
    func noAggregateAcrossAMixedHistory() {
        let history = [
            settled(.heldUp, startedAt: day(-80)),
            settled(.heldUp, startedAt: day(-60)),
            settled(.didNotHoldUp, startedAt: day(-40)),
            settled(.cannotTell, startedAt: day(-20)),
            abandoned(startedAt: day(-10), stoppedAt: day(-4)),
        ]
        let entries = ExperimentHistory.entries(from: history)
        #expect(entries.count == history.count, "one row each, and nothing merged")

        // Two of these held up. Nothing the screen writes says two, or says it in
        // words, or ranks the held-up ones above the rest — the order is the
        // chronology and only the chronology.
        let screen = ExperimentHistory.authored.joined(separator: " ").lowercased()
        for count in ["2", "two", "3", "three", "half", "most of"] {
            #expect(!screen.contains(count), Comment(rawValue: "'\(count)' reached the screen"))
        }
        #expect(entries.map(\.id) == history.reversed().map(\.id))
    }

    // MARK: Accessibility

    @Test("Every label leads with what was tested, never with a figure")
    func labelsLeadWithTheSubject() {
        let history = verdicts.map { settled($0, startedAt: day(-30)) }
            + [abandoned(startedAt: day(-30), stoppedAt: day(-26))]

        for entry in ExperimentHistory.entries(from: history) {
            #expect(entry.accessibilityLabel.hasPrefix(entry.subject),
                    Comment(rawValue: "label did not open with the subject: \(entry.accessibilityLabel)"))
            // Belt and braces for the rule itself: if a digit appears, the subject
            // is already behind it.
            if let digit = entry.accessibilityLabel.firstIndex(where: \.isNumber) {
                #expect(entry.accessibilityLabel.distance(from: entry.accessibilityLabel.startIndex,
                                                          to: digit) >= entry.subject.count)
            }
            // And the verdict is spoken, so a VoiceOver reader gets the same
            // distinction a sighted one does.
            #expect(entry.accessibilityLabel.contains(entry.standing))
        }
    }

    // MARK: The empty state

    @Test("Somebody who has tested nothing has an empty record")
    func emptyRecord() {
        #expect(ExperimentHistory.entries(from: []).isEmpty)
        // Including somebody mid-fortnight, which is why the lead says "finished"
        // rather than "run".
        #expect(ExperimentHistory.entries(from: [experiment(startedAt: day(-2))]).isEmpty)
        #expect(ExperimentHistory.emptyLead.contains("finished"))
    }

    @Test("The empty state promises nothing")
    func emptyStatePromisesNothing() {
        let text = (ExperimentHistory.emptyEyebrow + " " + ExperimentHistory.emptyLead
                    + " " + ExperimentHistory.emptySupport).lowercased()
        // "Yet" is a promise in one syllable, and for somebody who never accepts a
        // proposal it is one the app cannot keep. `stillLookingCopy` is the house
        // precedent and this is the same ban.
        for word in ["yet", "soon", "will", "coming", "once you", "start by", "check back"] {
            #expect(!text.contains(word), Comment(rawValue: "the empty state said '\(word)': \(text)"))
        }
        // It still says what a test is, and says the quiet half out loud.
        #expect(text.contains("one change"))
        #expect(text.contains("held up or not"))
        // And no window length, because there are two of them — a chosen fortnight
        // and a drawn month — and shared copy that names one is false about the
        // other.
        #expect(!text.contains("fortnight"))
        #expect(!text.contains("four weeks"))
    }

    // MARK: The sweep

    /// Mirrors the sweep `ExperimentStandingCopyTests` runs over the eyebrows. Only
    /// the strings this screen authored are swept: `ExperimentCopy.result` and the
    /// frozen change are answered for where they are written, and re-sweeping a
    /// carried string here would only teach somebody to weaken the sweep.
    @Test("Every string the screen authored is allowed on screen")
    func authoredCopyPassesTheGuard() {
        for text in ExperimentHistory.authored {
            // Strictly nil, not "nil or instruction". `ExperimentCopy` is the only
            // file permitted to instruct and this is not it — nothing on this screen
            // asks anybody to do anything, because everything on it has happened.
            if let offence = NarrationGuard.offence(in: text) {
                Issue.record("\"\(text)\" broke a rule that still applies: \(offence)")
            }
        }
    }
}
