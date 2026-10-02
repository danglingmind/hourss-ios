import Foundation

/// The two sections of the Tests screen that are not the record: what is on offer,
/// and what is running.
///
/// **A value layer rather than strings inside a view body, for the reason
/// `ExperimentHistory.Entry` and `SlotCopy` are.** Every rule these two sections
/// have to keep is a statement about strings — the empty states promise nothing, no
/// section counts anything, every accessibility label opens with its subject — and a
/// `body` that exists only once a screen has been mounted cannot be asserted
/// against.
///
/// **Neither section is a second copy of a card.** Today owns the proposal card and
/// the active card: both are built by `ObservationSlotView` out of `ExperimentCopy`,
/// both carry the premise, the caveat and the controls, and both are where a
/// decision is actually made. What is here is an index — the change, carried
/// verbatim, and one line saying where it is dealt with. A sentence phrased twice in
/// two files is how a claim and its card drift apart, which is the mistake this
/// codebase documents most often, so this file authors nothing that
/// `ObservationSlotView` already says and quotes `proposal.change` and
/// `experiment.change` rather than describing them.
///
/// **Not `@MainActor`.** An `enum` beside the view rather than a static helper *on*
/// it, so nothing infers main-actor isolation from a SwiftUI type and traps at
/// runtime when a suite that is not on the main actor calls it. This project has
/// shipped that bug twice, and it looks like a shrinking test count rather than like
/// a crash.
enum TestsScreen {

    // MARK: - Section headings

    /// Three fixed headings, in the order the screen draws them.
    ///
    /// **Fixed, and not varied to report the state.** `HealthConnectionView` sets the
    /// precedent for an eyebrow that states what it heads — "Connected" / "Not
    /// connected" — and it is the right precedent for one section standing alone. It
    /// is the wrong one for three in a column: two of these three are empty on most
    /// days, so a state-carrying heading would leave somebody reading NOTHING ON
    /// OFFER / NOTHING RUNNING / FINISHED, which is a screen that opens by listing
    /// what it does not have. The headings say what the three states of a test are,
    /// the bodies say which of them this person is in, and the order never moves.
    static let offerEyebrow = "On offer"
    static let runningEyebrow = "Running"
    static let finishedEyebrow = "Finished"

    // MARK: - On offer

    /// Where an offer is taken on.
    ///
    /// **This is the whole of what the section adds, and it is deliberately a place
    /// rather than a control.** The decision belongs to the card and the sheet it
    /// raises, where the premise, the caveat and the randomised option have room to
    /// be read; a second "Start this" here would be the same commitment offered
    /// twice, in less context, by a screen that cannot show the reasoning. Naming the
    /// tab is the link — this screen is pushed from You and has no route into
    /// Today's stack, and inventing one so a record could change tabs under somebody
    /// is a worse answer than a sentence.
    ///
    /// Two forms because only one test runs at a time, which the plural says in
    /// passing: a list of three offers with "you can start one of these" is the
    /// one-at-a-time rule stated where somebody is looking at three of them.
    static func offerDirection(count: Int) -> String {
        // Worded to point rather than to offer, and that is not fussiness: the
        // earlier version read "You can start this one from Today", which is fine
        // English and contains the card's own button word for word. A line on an
        // index that echoes the control it is pointing at reads as a control, and
        // this screen deliberately has none — the decision is made on the card,
        // where the premise and the caveat are. The test pins it.
        count == 1
            ? "Today is where you take this one on."
            : "Today is where you take one of these on."
    }

    /// Nothing on offer, and no test running either.
    ///
    /// **States the absence and stops.** No "yet", no "soon", no "check back" —
    /// `ObservationSlotView`'s own empty state names the reason and
    /// `ExperimentHistory.emptyLead` follows it: for somebody whose record never
    /// produces a testable split, "yet" is a promise in one syllable that the app
    /// cannot keep. The absence is the one thing this line knows for certain.
    static let offerEmpty = "Nothing is on offer."

    /// Nothing on offer *because* one is already running.
    ///
    /// **The one branch in this section, and it exists to stop a true sentence
    /// reading as a false one.** `experimentProposals` returns nothing at all while a
    /// test is active, and that is a refusal rather than a shortage: two concurrent
    /// changes make both unreadable, which is `acceptExperiment`'s hard invariant.
    /// Somebody mid-test reading "Nothing is on offer" directly above their own
    /// running test would be told the app has found nothing, when what happened is
    /// that the app will not ask twice. Two sections which are never both full is
    /// worth one sentence explaining why.
    static let offerEmptyWhileRunning = "Nothing new while a test is running."

    /// One offer, as the exact strings that will be drawn.
    ///
    /// Two fields, not the record's four. There is no outcome, there is no window,
    /// and there is nothing to report — so rather than fill four slots with three
    /// absences this says the only two things that are true before a test starts.
    struct Offer: Identifiable, Equatable {
        let id: UUID
        /// `proposal.change`, carried. The change somebody accepts has to be word for
        /// word the change they were shown.
        let subject: String
        /// Subject first, always — the rule `TitledFigure` and the Patterns evidence
        /// readout were both corrected to follow.
        ///
        /// It is the subject and nothing else, because nothing else about an offer is
        /// true yet. The field is still here rather than collapsed into `subject`:
        /// the heading is read as its own element before the row, so anything added
        /// to a row later has somewhere to go that is behind the change rather than
        /// in front of it.
        let accessibilityLabel: String
    }

    /// What could be started now, in the order the engine ranked it.
    ///
    /// **Every offer, not just the first.** Today shows one card, because a feed that
    /// asked three times would be asking until somebody said yes. This is the one
    /// place in the app where the list itself is the answer to a question somebody
    /// came here with, and showing one of three while the heading says "on offer"
    /// would be the quiet kind of edit — a selection the reader cannot see being
    /// made, which is the argument that keeps abandoned tests in the record.
    ///
    /// **Membership is filtered here exactly as `canSeeProposal` filters it on
    /// Today.** A confirmed-standing proposal is members-only; drawing it on a second
    /// screen would hand a free reader the thing the slot withholds, and a paywall
    /// that one surface enforces and another forgets is not a paywall.
    ///
    /// - Parameter proposals: from `experimentProposals()`, which already returns
    ///   nothing while a test is active and already excludes anything declined or
    ///   tested.
    static func offers(from proposals: [ExperimentDesign.Proposal],
                       isEntitled: Bool) -> [Offer] {
        proposals
            .filter { isEntitled || !$0.requiresMembership }
            .map { Offer(id: $0.id,
                         subject: $0.change,
                         accessibilityLabel: $0.change) }
    }

    // MARK: - Running

    /// The test in progress, as the exact strings that will be drawn.
    struct Running: Equatable {
        let id: UUID
        /// `experiment.change`, carried — the words it was agreed to in, not the
        /// registry's current wording.
        let subject: String
        /// How far in it is.
        let progress: String
        /// Which window, as both its ends. The same form a finished row uses, because
        /// it is the same fact about the same kind of thing.
        let window: String
        let accessibilityLabel: String
    }

    /// No test running.
    static let runningEmpty = "No test is running."

    /// The window ran out and nothing has been frozen yet.
    ///
    /// A real state rather than a defensive one: settling runs on the next launch or
    /// foreground, so a window that closed while the phone was down is open on the
    /// record for as long as it takes somebody to pick the phone up. Saying "day
    /// twenty-eight of this test" for the three days after it ended would be the one
    /// line on this screen that was false.
    ///
    /// Carefully not a verdict, for the reason `stoppedReport` is not one: the window
    /// closing and the figures being read are two events, and this is the first.
    static let runningClosed = "This test has closed."

    /// The running test, or nil when there is none.
    ///
    /// **What it does not say, and why.** Not the adherence count, not the days
    /// remaining, not whether today is one of a drawn window's days. All three are on
    /// Today — the card writes the first two and the running strip under the header
    /// writes the third — and all three are the live, daily half of the feature,
    /// which is Today's job. Repeating them a third time would put three numbers
    /// about one test on two screens, where the only thing keeping them equal is that
    /// nobody edited one of them.
    ///
    /// **So the one figure here means one thing and appears nowhere else.** "Day six"
    /// is a position in a window. It is not adherence, which is a different number
    /// the card already phrases as "six days of it so far" — and had this section
    /// borrowed that phrasing for a different quantity, the two would read as the same
    /// fact and disagree.
    ///
    /// **A position in a window is not a deadline.** The slot's copy sweep bans "days
    /// left", "days to go" and "until" because a deadline is the shape that turns a
    /// count into something to defend. A count that only goes up, with both ends of
    /// the window printed under it, is the fact without the shape.
    ///
    /// - Parameter now: passed in, never read here. One read of the clock per
    ///   decision is a rule this codebase has already paid for breaking.
    static func running(_ experiment: Experiment?, on now: Date,
                        calendar: Calendar = .current) -> Running? {
        guard let experiment, experiment.phase == .active else { return nil }

        let ended = experiment.endsAt(calendar: calendar)
        let window = "\(short(experiment.startedAt)) – \(short(ended))"
        let spokenWindow = "\(spoken(experiment.startedAt)) to \(spoken(ended))"

        let progress: String
        if experiment.hasClosed(at: now, calendar: calendar) {
            progress = runningClosed
        } else {
            let elapsed = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: experiment.startedAt),
                to: calendar.startOfDay(for: now)).day ?? 0
            // Clamped at both ends. A clock that has gone backwards is not a reason
            // to print "day zero", and the closed case above has already taken the
            // top end.
            let day = min(max(elapsed, 0) + 1, experiment.windowDays)
            progress = "Day \(spelled(day)) of this test."
        }

        return Running(
            id: experiment.id,
            subject: experiment.change,
            progress: progress,
            window: window,
            accessibilityLabel: "\(experiment.change) \(progress) \(spokenWindow).")
    }

    // MARK: - The sweep

    /// Every string this file wrote, for `NarrationGuard`. The carried ones — both
    /// changes, and everything `ExperimentCopy` writes — are swept where they are
    /// written, and re-sweeping a carried string here would only teach somebody to
    /// weaken the sweep.
    ///
    /// Both forms of `offerDirection`, because a sweep that saw one of two branches
    /// is a sweep somebody would trust for both.
    static let authored = [offerEyebrow, runningEyebrow, finishedEyebrow,
                           offerDirection(count: 1), offerDirection(count: 2),
                           offerEmpty, offerEmptyWhileRunning,
                           runningEmpty, runningClosed]

    // MARK: - Formatting

    /// "14 Sep", the format the Journal rows, the evidence list and the record all
    /// use. Shared with `ExperimentHistory` so a running window and a finished one
    /// cannot be printed two ways on one screen.
    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Spelled out for VoiceOver, which reads an abbreviated month as an
    /// abbreviation.
    static func spoken(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide))
    }

    /// Counts are spelled in prose and set as numerals in a figure, which is the
    /// register the rest of the app reads in.
    ///
    /// **Through twenty-eight, where the two existing copies of this helper stop at
    /// twelve.** They are both private to files this change does not own, and both
    /// count things that are small by construction. A window is not: a drawn one is
    /// `Experiment.randomisedWindowDays` long, so a list ending at twelve would have
    /// switched from "day twelve" to "day 13" halfway through every drawn month —
    /// one sentence changing register mid-window, for no reason a reader could see.
    private static func spelled(_ n: Int) -> String {
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve", "thirteen",
                     "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                     "nineteen", "twenty"]
        if units.indices.contains(n) { return units[n] }
        if n <= 28 { return "twenty-\(units[n - 20])" }
        return "\(n)"
    }
}
