import SwiftUI

/// What this person has tested, and what came of each one.
///
/// **Why this screen exists.** A settled result claims Today's slot exactly once
/// and acknowledging it gives the slot up — which is correct for the card and
/// leaves nowhere to look afterwards. The record itself was never the thing
/// missing: `Experiment` writes down what was agreed to *in the words it was
/// agreed to*, and `Settlement` freezes the figures at the instant the window
/// closed, both for reasons that are explicitly about the record outliving the
/// screen that first showed it. Only the screen was missing, and until it exists
/// nobody can reasonably run a third experiment, because the first two are gone.
///
/// **Why it is on You and not on Patterns.** Patterns is mined evidence: the engine
/// tested sixty hypotheses, the correction decided which of them survived, and
/// every row there is recomputed from the sessions underneath it. An experiment is
/// the opposite on both counts — one prediction fixed in writing before the window
/// opened, and a figure deliberately frozen because re-deriving it next month
/// against a rolling baseline would hand back a different number for a fortnight
/// that has not changed. `BACKLOG.md` already refuses to let a settled experiment
/// feed rung 4, on the grounds that mixing pre-registered and mined evidence inside
/// one correction is exactly the confusion the correction exists to prevent; putting
/// the two in one feed is that same confusion moved to the surface, where the person
/// reading would be the one expected to keep them apart. You is where the app states
/// what this person has *done* — its header already counts their sessions and their
/// days — and a fortnight somebody agreed to and lived through belongs there.
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
    /// so that one sweep can see all of them, and nothing there says that a test was
    /// stopped — `stopTitle` is the control that stops one, which is a different
    /// string with a different job. These are swept by this feature's own suite in
    /// the meantime; they should move the next time that file is open.
    static let stoppedStanding = "Stopped"

    /// Plain, and carefully not a verdict. Nothing was read, so there is nothing to
    /// report about the change — a sentence implying it failed would be a conclusion
    /// the window never reached, and stopping is free and uncounted.
    ///
    /// **Says nothing about how long the window was.** Experiments come in two
    /// lengths now: a chosen fortnight and a drawn month. Every sentence this file
    /// authors is therefore silent about the number of days, and the row's own date
    /// range says which window it was. Hard-coding "fortnight" into shared copy is
    /// how a true sentence becomes a false one when a second shape arrives.
    static let stoppedReport = "This one was stopped early, so it has no result."

    static let emptyEyebrow = "Nothing tested"

    /// **No "yet" and no "soon".** `ObservationSlotView`'s own empty state sets the
    /// precedent and names the reason: for somebody who never accepts a proposal,
    /// "yet" is a promise in one syllable that the app cannot keep. So this states
    /// the absence, which is the one thing it knows for certain, and stops.
    ///
    /// "Finished" rather than "run", because somebody mid-fortnight is standing in
    /// front of this screen with a test in progress and "you have not run a test"
    /// would be false to them.
    static let emptyLead = "You have not finished a test."

    /// What a test is, so the empty screen is informative rather than apologetic —
    /// and the equal-weight principle stated in the one place somebody reads before
    /// they have any results to read it against.
    static let emptySupport = "A test is one change, agreed to before it starts. "
        + "A finished one is kept here with what it settled at, whether it held up or not."

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
    static let footnote = "Each of these was one change you agreed to before it started, "
        + "measured against your own days. A finished test says where the figures landed "
        + "and stops there."

    /// Everything this file wrote, for its own sweep. The carried strings —
    /// `ExperimentCopy.result`, `verdictTitle`, and the frozen change — are swept
    /// where they are written and are deliberately not re-swept here.
    static let authored = [stoppedStanding, stoppedReport,
                           emptyEyebrow, emptyLead, emptySupport, footnote]

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
    /// **A running experiment is out.** Today owns the active card and shows it every
    /// day of the fortnight; a row with no outcome sitting at the top of a list of
    /// outcomes would be the one entry here making a promise.
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
        let window = "\(short(experiment.startedAt)) – \(short(ended))"
        let spokenWindow = "\(spoken(experiment.startedAt)) to \(spoken(ended))"

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

    /// "14 Sep", the format the Journal rows and the evidence list already use.
    private static func short(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Spelled out for VoiceOver, which reads an abbreviated month as an
    /// abbreviation.
    private static func spoken(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }
}

// MARK: - The screen

/// The record, as a ruled list.
///
/// **Not a column of forest cards, deliberately.** Today's settled result is filled
/// because it is the rarest thing the app can show and appears exactly once;
/// `ObservationSlotView` states the rule it is applying — a card that is emphatic
/// every other week is just the house style, and a palette where four things are
/// emphasised differently is a palette where nothing is. A list of settled results
/// is by definition not rare, so three identical forest blocks would spend the
/// app's one emphasis on its most predictable screen and say nothing by it. Worse,
/// identical fills behind three different verdicts invite the fill to be read as a
/// status colour it is not, and the moment a reader starts looking for the green
/// ones the list has become a scoreboard.
///
/// **Space is the lever, as `DESIGN.md` nominated.** The separation between records
/// is `Space.md` of vertical room inside each row rather than a second rule weight
/// or a new colour — the two visual changes this project has reverted whole were a
/// 2pt `SectionRule` and a full-bleed canvas, and the conclusion recorded after the
/// first was that the lever is probably space. `HRule`, `Eyebrow`, `Space` and the
/// existing type ramp are the whole of what this screen is built from.
struct ExperimentHistoryView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cheap enough to read in a body, unlike the Patterns lead section: this is a
    /// filter and a sort over stored values and runs no engine, so there is nothing
    /// here to cache and nothing a re-evaluation can cost.
    private var entries: [ExperimentHistory.Entry] {
        ExperimentHistory.entries(from: store.experiments)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([
                    Text("What you").styled(.sectionTitle),
                    Text("tested.").styled(.emphasis(42)),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                if entries.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
    }

    private var list: some View {
        let rows = entries
        return VStack(alignment: .leading, spacing: 0) {
            HRule()
            ForEach(rows) { entry in
                row(entry)
                HRule()
            }

            Text(ExperimentHistory.footnote)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.sm)
        }
        // The one state change this screen has: settling runs on returning to the
        // foreground, so a window that closed while the phone was down adds a row
        // under somebody already looking at the list. `content` is the token for a
        // set of things being replaced rather than one object travelling, and
        // Reduce Motion lands on the finished list with no transition at all.
        .animation(Motion.content(reduced: reduceMotion), value: rows.count)
        // `children: .contain` so the identifier resolves to a container. Without it
        // the rows stay independent elements, the identifier lands on nothing a
        // query can find, and a UI test reports the list absent while it is plainly
        // on screen — the same trap `PatternsView`'s lead section documents.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("experiment-history")
    }

    /// One record: what was tested, what happened, when.
    ///
    /// **The subject is on the top step and the verdict on the second.** Today's card
    /// puts the verdict in the eyebrow and is right to — there is one card, the
    /// person knows what they agreed to, and the answer is the only news. A list
    /// inverts that: a column that opens every row with IT HELD UP / IT DID NOT HOLD
    /// UP is a column of verdicts to be scanned and compared, which is a scoreboard
    /// however carefully each one is worded. Leading with the change makes each row a
    /// commitment with its outcome attached, which is what the record actually is —
    /// and it is the same correction `EvidenceReadout` made on Patterns, where the
    /// line named its subject four words after its figure.
    ///
    /// **All three verdicts are drawn by this one function.** There is no branch on
    /// the verdict anywhere in this file: same eyebrow position, same type ramp, same
    /// room, same order. The only thing that differs between a result that held up
    /// and one that did not is the sentence, which is the distinction surviving
    /// greyscale and VoiceOver both.
    private func row(_ entry: ExperimentHistory.Entry) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(entry.subject)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow(entry.standing)
                Text(entry.report)
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 11pt mono — the register `HealthFactRow` names for metadata rather than
            // for prose, which is what a date is.
            Text(entry.window)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityIdentifier("history-row")
    }

    /// Somebody who has tested nothing.
    ///
    /// Three lines in the shape `stillLookingCopy` already uses — eyebrow, lead,
    /// support — and no illustration. A placeholder drawing on this screen would be
    /// decoration standing where a record goes, and the one true thing to say is
    /// short enough to say.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(ExperimentHistory.emptyEyebrow)
            Text(ExperimentHistory.emptyLead)
                .textStyle(.sectionLead)
                .fixedSize(horizontal: false, vertical: true)
            Text(ExperimentHistory.emptySupport)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ExperimentHistory.emptyLead) \(ExperimentHistory.emptySupport)")
        .accessibilityIdentifier("experiment-history-empty")
    }
}
