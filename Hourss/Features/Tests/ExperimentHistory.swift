import Foundation

/// What this person has tested, and what came of each one.
///
/// **Why the record exists.** A settled result claims Today's slot exactly once
/// and acknowledging it gives the slot up — which is correct for the card and
/// leaves nowhere to look afterwards. The record itself was never the thing
/// missing: `Experiment` writes down what was agreed to *in the words it was
/// agreed to*, and `Settlement` freezes the figures at the instant the window
/// closed, both for reasons that are explicitly about the record outliving the
/// screen that first showed it. Only the screen was missing, and until it exists
/// nobody can reasonably run a third experiment, because the first two are gone.
///
/// **Why this is not a row in the Patterns feed.** Patterns is mined evidence: the
/// engine tested sixty hypotheses, the correction decided which of them survived,
/// and every row there is recomputed from the sessions underneath it. An experiment
/// is the opposite on both counts — one prediction fixed in writing before the
/// window opened, and a figure deliberately frozen because re-deriving it next month
/// against a rolling baseline would hand back a different number for a fortnight
/// that has not changed. `BACKLOG.md` already refuses to let a settled experiment
/// feed rung 4, on the grounds that mixing pre-registered and mined evidence inside
/// one correction is exactly the confusion the correction exists to prevent; putting
/// the two in one feed is that same confusion moved to the surface, where the person
/// reading would be the one expected to keep them apart.
///
/// **That is an argument about the feed, not about the door.** It used to be written
/// here as "why it is reached from You and not from Patterns", and the second half
/// did not follow from the first: a screen *pushed* from Patterns is not a row in
/// the feed, keeps its own frozen figures, and goes nowhere near the correction. The
/// part that was really doing the work was that You is where the app states what
/// this person has done, and a fortnight they agreed to and lived through is such a
/// statement. True of the record; not true of the offer section that now sits above
/// it on the same screen. `TestsView` and `PatternsView.testsEntry` carry where the
/// door ended up and why.
///
/// **It is now one section of three rather than a screen of its own.** `TestsView`
/// holds what is on offer, what is running and everything finished, because the
/// three states of one feature living in three places meant none of them was the
/// feature. Nothing below changed in the move: the record is still the only one of
/// the three with a list in it, and every rule it keeps is a rule about this list.
///
/// **What it must not become.** Nothing here is counted. There is no "two of three
/// held up", no rate and no streak: `abandonExperiment` keeps no tally on purpose,
/// because a number whose only use is a reproach does not get computed, and a list
/// that totals its own verdicts is that number assembled by the reader instead.
enum ExperimentHistory {

    // MARK: - One entry

    /// One row, as the exact strings that will be drawn.
    ///
    /// A value rather than a view body, for the reason `SlotCopy` is one: the three
    /// rules this screen has to keep — the three verdicts at one weight, nothing
    /// counted, the subject named first — are all statements about strings, and a
    /// `body` that exists only once a screen has been mounted cannot be asserted
    /// against.
    ///
    /// **Four fields, the same four for every entry.** A stopped experiment fills
    /// them with different words rather than leaving one out. An entry that was
    /// structurally shorter than its neighbours would be the quiet half of the
    /// dishonesty this whole feature is guarding against, and it would land on
    /// `cannotTell` first — the verdict with the least to say and the most to lose
    /// from being drawn smaller.
    struct Entry: Identifiable, Equatable {
        let id: UUID

        /// What was tested: the change, in the words the person accepted. Read off
        /// the experiment rather than the registry, because the registry's wording
        /// may have moved since and what somebody agreed to includes what they were
        /// told they were agreeing to.
        let subject: String

        /// What happened, as a phrase — never only as a colour or a position.
        /// `ExperimentCopy.verdictTitle` for anything with a verdict.
        let standing: String

        /// Where the figures landed, or, for an entry with no verdict, why there are
        /// none. `ExperimentCopy.result` writes every settled one; this file does not
        /// write a second phrasing of a result that already has one.
        let report: String

        /// When, as the fortnight it covered rather than the day it closed. A record
        /// of a window should say which window — the same argument `DESIGN.md` makes
        /// for a session row showing both of its ends.
        let window: String

        /// Subject first, figures last, which is the rule `TitledFigure` and the
        /// Patterns evidence readout were both corrected to follow.
        let accessibilityLabel: String
    }

    // MARK: - Authored copy

    /// The eyebrow on an experiment that was stopped early.
    ///
    /// **Authored here and not in `ExperimentCopy`, which is where it belongs.**
    /// Every sentence an experiment puts on screen is supposed to live in one file
    /// so that one sweep can see all of them, and nothing there said that a test was
    /// stopped — `stopTitle` is the control that stops one, which is a different
    /// string with a different job.
    ///
    /// **They live there now**, and these two forward to them so this file keeps the
    /// names its own tests and rows already use without owning a second copy of the
    /// words.
    static let stoppedStanding = ExperimentCopy.stoppedStanding

    /// Plain, and carefully not a verdict. Nothing was read, so there is nothing to
    /// report about the change — a sentence implying it failed would be a conclusion
    /// the window never reached, and stopping is free and uncounted.
    ///
    /// **Says nothing about how long the window was.** Experiments come in two
    /// lengths now: a chosen fortnight and a drawn month. Every sentence this file
    /// authors is therefore silent about the number of days, and the row's own date
    /// range says which window it was. Hard-coding "fortnight" into shared copy is
    /// how a true sentence becomes a false one when a second shape arrives.
    static let stoppedReport = ExperimentCopy.stoppedReport

    /// **No "yet" and no "soon".** `ObservationSlotView`'s own empty state sets the
    /// precedent and names the reason: for somebody who never accepts a proposal,
    /// "yet" is a promise in one syllable that the app cannot keep. So this states
    /// the absence, which is the one thing it knows for certain, and stops.
    ///
    /// "Finished" rather than "run", because somebody mid-fortnight is standing in
    /// front of this screen with a test in progress and "you have not run a test"
    /// would be false to them — and now doubly so, because the running one is three
    /// inches further up the same screen.
    ///
    /// **The eyebrow that used to sit above this is gone.** It read "Nothing tested",
    /// which was the heading of a screen whose whole content was this absence. The
    /// absence is one section of three now and the section has a heading of its own,
    /// so the old one would have stacked a second 11pt mono line directly under the
    /// first and said the same thing twice.
    static let emptyLead = "You have not finished a test."

    /// What a test is, so the empty screen is informative rather than apologetic —
    /// and the equal-weight principle stated in the one place somebody reads before
    /// they have any results to read it against.
    static let emptySupport = "A test is one change, agreed to before it starts. "
        + "A finished one is kept here with how it went, whether it held up or not."

    /// The limit on what any of these results can mean, said once for the screen.
    ///
    /// **Why once and not per row.** Today's settled card carries `experiment.caveat`
    /// and drops it for `cannotTell`, because there is nothing to qualify about a
    /// window that could not be read and attaching a caveat there would imply a
    /// finding nobody made. That asymmetry is right on a card shown alone and wrong
    /// in a list: it would draw two of the three verdicts one line taller than the
    /// third, which is the structural inequality this screen is specifically built to
    /// avoid. So the rows carry the same four things each, and the limit common to
    /// all of them sits under the list — where `PatternsView` already puts
    /// "Observations, not rules".
    ///
    /// The per-experiment caveat is not lost: it stays frozen on the record, and the
    /// card that made the claim is where it was shown.
    static let footnote = "Each of these was one change you agreed to before it "
        + "started, checked against your own days. A finished test says how it went "
        + "and stops there."

    /// Everything this file wrote, for its own sweep. The carried strings —
    /// `ExperimentCopy.result`, `verdictTitle`, and the frozen change — are swept
    /// where they are written and are deliberately not re-swept here.
    static let authored = [stoppedStanding, stoppedReport,
                           emptyLead, emptySupport, footnote]

    // MARK: - Building the record

    /// Every experiment with something to report, newest first.
    ///
    /// **Abandoned experiments are in, and that is a decision.** They carry no
    /// verdict, so there is genuinely nothing to report about the change — which is
    /// the argument for leaving them out, and it is a good one. It loses to a simpler
    /// one: a record of what somebody has done that silently drops the parts they
    /// stopped is not a record, it is a selection, and the person cannot tell it has
    /// been made. Somebody who started three tests and finished one would open this
    /// screen and find a history in which they only ever started one. Keeping them is
    /// also the cheaper mistake of the two — an entry nobody needed, against an entry
    /// that was edited out.
    ///
    /// What stops a stopped entry reading as a fourth verdict is that it says in
    /// plain words that it has no result, and that nothing anywhere counts these.
    ///
    /// **A running experiment is out of this list, and is its own section now.** It
    /// used to be excluded on the grounds that a row with no outcome at the top of a
    /// list of outcomes would be the one entry here making a promise. That argument
    /// is unchanged and is why the running test is drawn above the list rather than
    /// in it: it has a heading saying what it is, it has no verdict slot to leave
    /// blank, and nothing about it can be mistaken for a result.
    /// - Parameter experiments: already filtered and ordered by
    ///   `HourssStore.concludedExperiments`, which is where that rule lives now —
    ///   "newest first, excluding what is still running" is a statement about the
    ///   record rather than about this screen. Passing an unordered list still works
    ///   and still sorts, so a test can hand it any order and assert the result.
    static func entries(from experiments: [Experiment], calendar: Calendar = .current) -> [Entry] {
        experiments
            .filter { $0.phase != .active }
            .sorted { concluded($0, calendar: calendar) > concluded($1, calendar: calendar) }
            .map { entry(for: $0, calendar: calendar) }
    }

    /// The day an experiment stopped being open, whichever way it stopped.
    ///
    /// One date for both kinds, because the list is one chronology. `settledAt` rather
    /// than `endsAt` would sort by the launch that happened to close the window,
    /// which can be days late — settling runs on the next foreground, not at the
    /// closing instant.
    static func concluded(_ experiment: Experiment, calendar: Calendar = .current) -> Date {
        experiment.abandonedAt ?? experiment.endsAt(calendar: calendar)
    }

    private static func entry(for experiment: Experiment, calendar: Calendar) -> Entry {
        let ended = concluded(experiment, calendar: calendar)
        let window = "\(TestsScreen.short(experiment.startedAt)) – \(TestsScreen.short(ended))"
        let spokenWindow = "\(TestsScreen.spoken(experiment.startedAt)) to \(TestsScreen.spoken(ended))"

        let standing: String
        let report: String
        if let settlement = experiment.settlement {
            standing = ExperimentCopy.verdictTitle(settlement.verdict)
            report = ExperimentCopy.result(for: experiment, settlement: settlement)
        } else {
            standing = stoppedStanding
            report = stoppedReport
        }

        return Entry(
            id: experiment.id,
            subject: experiment.change,
            standing: standing,
            report: report,
            window: window,
            // The change leads. A label that opened with the verdict would make the
            // row's identity the answer rather than the question, and a reader
            // moving down the list by ear would hear three verdicts before learning
            // what any of them was about.
            accessibilityLabel: "\(experiment.change) \(standing). \(report) \(spokenWindow)."
        )
    }
}
