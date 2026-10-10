import SwiftUI

/// Tests — one screen that is the feature.
///
/// **Why it exists.** A proposal was a card on Today, a running test was another
/// card on Today, and everything finished was two taps deep inside You. Three states
/// of one thing in three places, and none of the three was the feature: nowhere in
/// the app could somebody see what they had been offered, what they had taken on and
/// what had come of it as one subject. This screen is that place, in that order —
/// what could be started, what is running, what finished.
///
/// **Why it is not a tab.** The app has five destinations and a sixth would be the
/// wrong one. Two of these three sections are empty on most days, by construction
/// rather than by accident: `experimentProposals` returns nothing while a test is
/// active, and the active test is nothing for the fortnight before somebody accepts
/// one. A tab is paid for every day it is on screen, and a tab that says "nothing is
/// on offer, nothing is running" on most of them teaches people to stop opening it —
/// which is the opposite of what the PRD wants from making a test feel like
/// something.
///
/// The feature's daily presence belongs on Today and now has it: the proposal card,
/// the active card, and the strip under the header. That is where somebody is
/// *doing* a test. This screen is where they can see the whole of it.
///
/// **Why it is reached from Patterns and not from You.** It was pushed from You, on
/// the grounds that You is where the app states what this person has done and a
/// fortnight they agreed to and lived through is such a statement. That is true of
/// the record and only of the record. The section above it is an *offer* — a thing
/// to do about a claim, which nobody has done yet — and a settings list is the wrong
/// shelf for that; the record was dragging the rest of the feature onto it. Patterns
/// is where the claims are, and since it started grouping by what somebody said
/// mattered, every group there ends with the one thing to try for that priority and
/// raises the same sheet Today raises. The relationship was already being stated on
/// that screen several times over while the way in was on another one.
/// `PatternsView.testsEntry` carries the argument for the position it took there,
/// and `ExperimentHistory` keeps the half of the old argument that survives — which
/// is about why a settled result is not a row in the Patterns *feed*, and is not
/// about where the feature is reached from.
///
/// **Not a column of cards, and that did not stop being true.** Today's settled
/// result is a forest block because it is the rarest thing the app can show and
/// appears exactly once; `ObservationSlotView.isCarded` states the rule it is
/// applying — a palette where four things are emphasised differently is a palette
/// where nothing is, and a card that is emphatic every other week is just the house
/// style. A *list* of settled results is by definition not rare, and identical fills
/// behind three different verdicts invite the fill to be read as a status colour it
/// is not: the moment a reader starts looking for the green ones the record has
/// become a scoreboard.
///
/// **Space is the lever, as `DESIGN.md` nominated**, and nothing visual was invented
/// to carry the two new sections. No colour, badge, border, second rule weight or
/// type size: three sections, each a heading over ruled rows, each row with
/// `Space.md` of vertical room, built from `Eyebrow`, `HRule`, `Space` and the
/// existing type ramp. Two visual changes have been reverted whole in this project
/// and the conclusion recorded after the first was that the lever is probably space.
/// Giving one section more room than another would also have been a ranking, and the
/// ranking here is the order.
///
/// **Nothing is counted, in any of the three.** No "two of five held up", no rate,
/// no streak, and no count of how many offers are waiting either — `RecordFacts`
/// argues this at length and `abandonExperiment` keeps no tally on purpose, because
/// a number whose only use is a reproach does not get computed. A list that totals
/// its own verdicts is that number assembled by the reader instead.
struct TestsView: View {
    /// Raises the log sheet from the header's `+`.
    var onLog: () -> Void = {}

    @Environment(HourssStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Held in state and filled by a task rather than computed in `body`, because
    /// producing them runs the engine and the correction over sixty hypotheses.
    /// `PatternsView` and `InsightDetailView` already pay this on a screen somebody
    /// opened, and the comment there is the one that applies: a view body
    /// re-evaluates far more often than the engine should.
    @State private var proposals: [ExperimentDesign.Proposal] = []

    /// The offer whose sheet is up, if one is.
    ///
    /// The same sheet Today and Patterns raise, so agreeing here is one act with the
    /// same four answers read before it, and cannot produce a second experiment.
    @State private var sheetProposal: ExperimentDesign.Proposal?

    /// Whether the engine has answered yet.
    ///
    /// **Without it the offer section states something false for a moment.** The task
    /// runs after the first body, so an empty `proposals` means either "nothing on
    /// offer" or "not asked yet", and drawing "Nothing is on offer." for the second
    /// would have the screen contradict itself a second later in front of somebody
    /// watching. An empty band under the heading says nothing, which is the one thing
    /// that is true while the question is open — and it is not a third empty state,
    /// because it has no words in it.
    @State private var hasAsked = false

    /// One read of the clock per appearance, which is the rule this codebase has
    /// already paid for breaking. The only thing it decides is which day of its
    /// window a running test is on.
    @State private var now = Date()

    private var offers: [TestsScreen.Offer] {
        TestsScreen.offers(from: proposals, isEntitled: store.membership.isEntitled)
    }

    /// Cheap enough to read in a body, unlike the proposals: a `first(where:)` over
    /// stored values and some date arithmetic, running no engine.
    private var running: TestsScreen.Running? {
        TestsScreen.running(store.activeExperiment, on: now)
    }

    /// Also cheap: a filter and a sort over stored values, so there is nothing here
    /// to cache and nothing a re-evaluation can cost.
    private var entries: [ExperimentHistory.Entry] {
        ExperimentHistory.entries(from: store.experiments)
    }

    /// What would change the offers. The same list `PatternsView` watches, for the
    /// same reason: these are the inputs `ExperimentDesign` reads, and anything else
    /// changing is a re-run that could only return the same answer.
    private var offerInputs: [Int] {
        [store.sessions.count, store.reflections.count,
         store.healthByDay.count, store.physiologyReadings.count,
         store.experiments.count, store.declinedExperiments.count]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                // One line, not two. `DisplayHeadline` puts each element of its
                // array on its own row, so the two runs are concatenated into a
                // single `Text` rather than passed as a pair — the emphasis still
                // changes mid-phrase, the line break does not.
                //
                // Short enough to hold at one line where the other display headings
                // are not: "Still listening." and "Nothing stands apart." both need
                // the stack at `.emphasis(42)`, and this is seven characters shorter
                // than either.
                DisplayHeadline([
                    Text("Your ").styled(.sectionTitle)
                        + Text("tests.").styled(.emphasis(42)),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                onOffer
                inProgress
                finished
                whatYouGet
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        // Names the screen this was pushed from, which is now Patterns. A back
        // button that said "You" after a push from Patterns is the one thing on a
        // pushed screen a reader cannot talk themselves out of believing.
        // `ScreenHeader`, not `BackHeader`. This was a screen pushed from the foot
        // of Patterns and carried a back arrow to it; it is a root tab now, and
        // there is nothing behind it to go back to.
        .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Tests", onLog: onLog) }
        .sheet(item: $sheetProposal) { TestProposalSheet(proposal: $0) }
        .navigationBarBackButtonHidden()
        .task(id: offerInputs) {
            now = Date()
            proposals = store.experimentProposals()
            hasAsked = true
        }
        .accessibilityIdentifier("tests")
    }

    // MARK: - On offer

    /// What could be started now.
    ///
    /// **It summarises and links; it does not re-draw the card.** One line per offer,
    /// the change carried verbatim, and one quiet line saying where it is taken on.
    /// The premise, the context, the caveat, the randomised ask and both controls
    /// stay on Today, where the decision is made and where there is room to read the
    /// reasoning before making it. A second "Start this" here would be the same
    /// commitment offered twice with less in front of it.
    private var onOffer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(TestsScreen.offerEyebrow)
                .padding(.bottom, Space.xs)
            HRule()

            if offers.isEmpty {
                if hasAsked {
                    // The branch is `TestsScreen`'s and the reason is written there:
                    // "nothing is on offer" directly above somebody's own running
                    // test would report a shortage where the app made a refusal.
                    note(running == nil ? TestsScreen.offerEmpty
                                        : TestsScreen.offerEmptyWhileRunning)
                        .accessibilityIdentifier("tests-on-offer-empty")
                    HRule()
                }
            } else {
                ForEach(offers) { offer in
                    offerRow(offer)
                    HRule()
                }
                Text(TestsScreen.offerDirection(count: offers.count))
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)
            }
        }
        // `children: .contain` so the identifier resolves to a container. Without it
        // the rows stay independent elements, the identifier lands on nothing a query
        // can find, and a UI test reports the section absent while it is plainly on
        // screen — the trap `PatternsView`'s lead section documents.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tests-on-offer")
        // Offers arrive from the task after the screen is already up, which is the
        // "set of things being replaced" case `content` is the token for. Reduce
        // Motion lands on the finished list with no transition at all.
        .animation(Motion.content(reduced: reduceMotion), value: offers.count)
    }

    /// One offer: the change, and nothing else.
    ///
    /// Set at `.body` rather than at the card's lead emphasis, because the register
    /// here is a list and not a claim. The same step the record's subject sits on, so
    /// an offer and a finished test read as the same kind of thing at two ends of one
    /// life — which is the whole argument for them sharing a screen.
    private func offerRow(_ offer: TestsScreen.Offer) -> some View {
        Button {
            sheetProposal = proposals.first { $0.id == offer.id }
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(offer.subject)
                    .textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                // What it rests on, in the idiom the Patterns insight rows already
                // use: `.label` in orange, under the sentence it qualifies.
                Text(offer.basis)
                    .textStyle(.label)
                    .foregroundStyle(Color.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(offer.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("offer-row")
    }

    // MARK: - What a test gets you

    /// The three verdicts, once, for every test on this screen.
    ///
    /// **It used to sit inside each proposal sheet and it is the same words every
    /// time.** Nothing about which change is being offered alters what comes back at
    /// the end — "it held up", "it did not hold up", "not enough to tell" are fixed
    /// — so a reader who opened three sheets read them three times, and the sheet
    /// that is supposed to be about *one* decision spent a third of itself on
    /// something true of all of them.
    ///
    /// **At the foot, below everything it describes.** The same position and the
    /// same job as Patterns' "Not rules. Hourss only speaks up when the same thing
    /// keeps happening." — a standing note that qualifies the whole screen, placed
    /// where it cannot push the thing somebody came for down the page.
    ///
    /// The strings are `ExperimentCopy`'s, untouched, so the sweep that owns every
    /// experiment sentence still sees them and the verdict wording here cannot drift
    /// from the wording a result will actually use.
    private var whatYouGet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(ExperimentCopy.whatYouGetHeading)
                .padding(.bottom, Space.xs)
            HRule()

            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(Array(ExperimentCopy.whatYouGetParts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case let .line(text):
                        Text(text)
                            .textStyle(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    case let .quiet(text):
                        Text(text)
                            .textStyle(.label)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    case let .titled(title, detail):
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).textStyle(.action)
                            Text(detail)
                                .textStyle(.body)
                                .foregroundStyle(Color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    // Neither shape appears in `whatYouGetParts`; the switch is total
                    // so a later addition to it has to be drawn rather than dropped.
                    case .span, .stages:
                        EmptyView()
                    }
                }
            }
            .padding(.top, Space.sm)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tests-what-you-get")
    }

    // MARK: - Running

    /// The one in progress, with how far in it is.
    ///
    /// Named `inProgress` rather than `running` so it does not collide with the value
    /// it draws, which is the thing a reader of this file wants to find first.
    private var inProgress: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(TestsScreen.runningEyebrow)
                .padding(.bottom, Space.xs)
            HRule()

            if let running {
                runningRow(running)
            } else {
                note(TestsScreen.runningEmpty)
                    .accessibilityIdentifier("tests-running-empty")
            }
            HRule()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tests-running")
    }

    /// The running test, in the record row's shape minus the slot it has no answer
    /// for.
    ///
    /// Subject, then how far in, then the window as both its ends — which is the
    /// record row with the verdict eyebrow taken out rather than left blank. A row
    /// built to a different shape would be the one entry on this screen that looked
    /// like a different kind of thing, and what it actually is is the same thing
    /// earlier.
    private func runningRow(_ running: TestsScreen.Running) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(running.subject)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(running.progress)
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            // 11pt mono — the register `HealthFactRow` names for metadata rather than
            // for prose, which is what a date is.
            Text(running.window)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(running.accessibilityLabel)
        .accessibilityIdentifier("running-row")
    }

    // MARK: - Finished

    /// Everything concluded, newest first.
    ///
    /// Unchanged from the screen this used to be on its own, including both
    /// identifiers, because the rules it keeps are rules about a list of outcomes and
    /// the list did not change by acquiring two sections above it.
    private var finished: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(TestsScreen.finishedEyebrow)
                .padding(.bottom, Space.xs)
            if entries.isEmpty {
                HRule()
                empty
                HRule()
            } else {
                list
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tests-finished")
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
        // The one state change this section has: settling runs on returning to the
        // foreground, so a window that closed while the phone was down adds a row
        // under somebody already looking at the list — and takes the row above it out
        // of the running section in the same breath.
        .animation(Motion.content(reduced: reduceMotion), value: rows.count)
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
                Eyebrow(entry.standing, tone: .quiet)
                Text(entry.report)
                    .textStyle(.body)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    /// Somebody who has finished nothing.
    ///
    /// Two lines where the other two sections get one, and the asymmetry is the
    /// point: this is where what a test *is* gets explained, because on the day all
    /// three sections are empty it is the only section with anything to explain. No
    /// illustration — a placeholder drawing standing where a record goes is
    /// decoration in the one place the screen has nothing to decorate.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(ExperimentHistory.emptyLead)
                .textStyle(.sectionLead)
                .fixedSize(horizontal: false, vertical: true)
            Text(ExperimentHistory.emptySupport)
                .textStyle(.label)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ExperimentHistory.emptyLead) \(ExperimentHistory.emptySupport)")
        .accessibilityIdentifier("experiment-history-empty")
    }

    // MARK: - Shared

    /// An absence, in the register of a row.
    ///
    /// `Space.md` of vertical room, the same as a record row, so an empty section
    /// takes the shape of a section rather than collapsing into its own heading. One
    /// muted sentence: an absence is not the screen's subject and should not be set
    /// as though it were.
    private func note(_ text: String) -> some View {
        Text(text)
            .textStyle(.body)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(text)
    }
}
