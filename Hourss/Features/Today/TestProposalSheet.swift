import SwiftUI

/// Agreeing to a test, as a decision rather than as a tap.
///
/// **What this replaced and why that was wrong.** Accepting a proposal used to be
/// a `DirectionalLink` on the band on Today, weighing exactly as much as "Add how
/// it felt" — bold 14pt text and a small arrow. One tap fixed a hypothesis, fixed
/// both arms, fixed the window, and locked out every other test for a fortnight,
/// and the only thing the reader had been told was the change and its premise.
/// Taking on a test is the most important thing this app asks anybody to do and it
/// was also the quietest thing on the screen.
///
/// **Borrowed from research consent, deliberately.** Joining a study is a short
/// sequence of plain screens — what this is, what you would do, how long, what is
/// measured, then agree — and it feels significant *because* it is a sequence
/// rather than a button. Nothing is hidden and nothing is long. The four questions
/// here are in that order and the controls are at the end of them, which is the
/// one structural decision in this file: see `controls` for why they are not
/// pinned.
///
/// **Not a single string is written here.** Every sentence comes from
/// `ExperimentCopy.sheet(for:)`, assembled as a value before anything renders, so
/// one copy sweep sees all of them — including the two gate labels and the three
/// verdicts, which are the two places this screen could most easily start lying.
/// `ExperimentCopy` documents that rule at length; this file is the largest thing
/// that has ever had to obey it. The two marks obey it too: `SpanBar` and
/// `StageList` are handed their labels and format nothing.
///
/// **Two standing rules are suspended here, and `DESIGN.md` records both as
/// decisions.** The owner looked at this screen on device and asked for the section
/// headings in orange and the rules gone, which reverses *Orange is a signal, not
/// decoration* and *Hierarchy comes from lines, not surfaces* — on this screen, on
/// trial, pending the same treatment elsewhere. What replaced the seven `HRule`s is
/// `Space.lg` between sections against `Space.xs` under a heading, plus a heading
/// the eye can land on from a thumb's distance. Nothing else was invented: no badge,
/// no border, no second rule weight, no new type size, and the two marks are
/// `DataBar` and a square.
///
/// **One line is still drawn, inside `SheetHeader`.** It closes the fixed title band
/// against the scrolling region below it, which is the sheet's frame rather than its
/// hierarchy — the thing the instruction was about was the seven rules ranking the
/// content. It is also shared with the session sheet and the reflection sheet, which
/// are not part of this trial, so removing it here would mean either changing all
/// three or giving a shared component a parameter for one screen. Worth raising with
/// the owner; not worth deciding alone.
struct TestProposalSheet: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let proposal: ExperimentDesign.Proposal

    /// The experiment this sheet started, once it has started one.
    ///
    /// **Held here rather than read back off the store**, because the sheet needs to
    /// confirm *the thing it just created* and `store.activeExperiment` is a query
    /// that would also answer for a window somebody else's tap opened. It is the
    /// return value of the accept that owns this screen or it is nothing.
    @State private var started: Experiment?

    /// When the window would start, read once.
    ///
    /// The "how long" span needs a far end, which is this plus the window, and
    /// `copy` is a computed property evaluated on every pass of `body`. Reading the
    /// clock there would read it dozens of times for one decision and let the drawn
    /// span shift under a redraw — one read per decision is a rule this codebase has
    /// already paid for breaking. `@State` is initialised when the sheet's storage
    /// is created, which is once per presentation.
    @State private var now = Date()

    private var copy: ExperimentCopy.ProposalSheet {
        ExperimentCopy.sheet(for: proposal, now: now)
    }

    /// The ground this sheet paints, named once rather than read from the
    /// environment.
    ///
    /// **It cannot be read.** This view is the one applying `.surface(.canvas)`, so
    /// `@Environment(\.surface)` here would report whatever its *presenter* set —
    /// the same trap `ObservationSlotView.surface` documents. Going through
    /// `Surface` rather than naming `Color.ink` and `Color.muted` is the point:
    /// `Surface.swift` exists so nothing hardcodes a pairing the design system did
    /// not sanction, and three places on Today were doing exactly that until a card
    /// turned forest and the grey landed on dark green.
    private let ground: Surface = .canvas

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The standing is the sheet's own title, which is why there is no second
            // heading under it. A lead that did not announce itself as a lead would
            // be a claim, and the honest label is the only thing between the two —
            // so it belongs in the one place on this screen that cannot be scrolled
            // away from.
            //
            // It stays in the quiet register while the seven section headings below
            // it went orange. That is the distinction the colour is being asked to
            // draw here: orange marks a question this sheet answers, and the title
            // is not one of them — it is what the sheet is about. `SheetHeader` is
            // also shared with two other sheets, and this trial is for one screen.
            SheetHeader(title: started == nil ? copy.standing : ExperimentCopy.activeStanding,
                        onClose: { dismiss() })

            ScrollView {
                if let started {
                    confirmation(started)
                } else {
                    offer
                }
            }
        }
        .surface(.canvas)
        // Stated rather than taken from iOS, so the sheet's own container is on the
        // same token as the blocks inside it. `RootView` sets this at both of its
        // presentation sites; this sheet sets it on itself instead, because three
        // screens raise it and a radius repeated three times is a radius that can be
        // forgotten at one of them.
        .presentationCornerRadius(Radius.block)
        // Agreeing replaces the whole sheet. Keyed on the experiment's identity
        // rather than on a bool so a future second transition reads as one movement;
        // Reduce Motion lands on the finished state.
        .animation(Motion.content(reduced: reduceMotion), value: started?.id)
    }

    // MARK: - The offer

    /// Four questions, three terms, then the controls.
    ///
    /// **Three gaps and no lines, which is the half of this screen that changed.**
    /// Every section used to open with an `HRule`; the owner asked for them gone, so
    /// the ranking is carried by space and by the heading's colour instead. The three
    /// steps are `Space.lg` between sections, `Space.sm` between two parts of one
    /// answer, and `Space.xs` between a heading and the thing it heads — each
    /// plainly larger than the next, or the screen reads as one list of fifteen
    /// lines. Space is the lever `DESIGN.md` nominates for exactly this and it is now
    /// the only one on this screen.
    private var offer: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // The first section is the change, and it is the only one set large. The
            // index rather than a flag on the section itself: the order *is* the
            // design, `orderedSections` owns it, and a second place saying which one
            // leads is a second place for the two to disagree.
            ForEach(Array(copy.orderedSections.enumerated()), id: \.offset) { index, part in
                section(part, lead: index == 0)
            }

            controls
        }
        .pageGutter()
        .padding(.top, Space.lg)
        .padding(.bottom, Space.xl)
    }

    /// One block: its heading, then its parts.
    ///
    /// - Parameter lead: the change, which is the only part there is anything to do
    ///   about and the one sentence set large. `.sectionLead` at 23pt rather than
    ///   `.sectionTitle` at 40pt: the 40pt step exists for hard-broken screen
    ///   titles through `DisplayHeadline`, never for a sentence that wraps, and
    ///   setting a wrapping instruction there would be a new use of a token rather
    ///   than a use of the ramp. What makes it read large here is that it is alone
    ///   under one heading with `Space.lg` on both sides, which is the same answer
    ///   `roomAbove` gives on Today.
    @ViewBuilder
    private func section(_ part: ExperimentCopy.ProposalSheet.Section, lead: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(part.heading)

            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(Array(part.parts.enumerated()), id: \.offset) { _, piece in
                    view(for: piece, lead: lead)
                }
            }
        }
        // Spoken as one block with its heading first, so the subject arrives before
        // anything else and no label opens with a figure. The marks are hidden from
        // VoiceOver individually and speak through this: `Section.spoken` carries the
        // span's two ends and each gate's state in words, so a reader who cannot see
        // either drawing loses nothing.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(part.spoken)
    }

    /// One part of an answer, in the register its own case names.
    ///
    /// **Nothing here counts.** The previous version decided a line's weight from
    /// its index and from how many lines the section had — first line primary, the
    /// rest quiet, unless there were more than two and then all of them primary,
    /// which was the only way the three verdicts came out equal. Every one of those
    /// branches was a guess about content from a view that cannot see it, and the
    /// first new line in any section would have broken one of them. The case says
    /// what the thing is; this draws it.
    @ViewBuilder
    private func view(for part: ExperimentCopy.ProposalSheet.Part, lead: Bool) -> some View {
        switch part {
        case .line(let text):
            Text(text)
                .textStyle(lead ? .sectionLead : .body)
                .foregroundStyle(ground.foreground)
                .fixedSize(horizontal: false, vertical: true)

        case .quiet(let text):
            Text(text)
                .textStyle(.body)
                .foregroundStyle(ground.secondary)
                .fixedSize(horizontal: false, vertical: true)

        // A verdict and its gloss. `.action` is the app's one bold idiom and it is
        // bold at 14pt against body at 16pt — the name reads as a sub-heading
        // without a new type size being invented for it, which is the thing two
        // reverted visual changes were both about. All three get it identically:
        // "It did not hold up" set a shade quieter than "It held up" is the first
        // step to not reporting a null, and there is a test pinning that elsewhere.
        case .titled(let title, let detail):
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .textStyle(.action)
                    .foregroundStyle(ground.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .textStyle(.body)
                    .foregroundStyle(ground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .span(let from, let to):
            SpanBar(start: from, end: to)

        case .stages(let stages):
            StageList(stages: stages.map { .init(label: $0.label, cleared: $0.cleared) })
        }
    }

    // MARK: - Deciding

    /// Start, the harder second offer, and no.
    ///
    /// **Not pinned to the bottom, and that is the structural decision.** Every
    /// other sheet in this app pins its `PrimaryAction` above the home indicator,
    /// which is right for saving a rating: the reader already knows what they are
    /// doing and the control should be under their thumb. It is wrong here. A start
    /// button visible on arrival means a fortnight can be agreed to without the
    /// four answers above having been scrolled past, which is the one thing this
    /// sheet was built to stop — the old card could be accepted without reading
    /// anything and that is what made it a tap instead of a decision.
    ///
    /// **One filled control, and it is the ordinary offer.** `PrimaryAction`'s own
    /// rule is one per screen and never a second, so the drawn window is a
    /// `DirectionalLink` beneath it rather than a competing block. That is also the
    /// right ranking: the simpler test is the one most people should take, and
    /// somebody who will not commit to particular days should still be able to run
    /// the test they were offered.
    ///
    /// **The decline carries its own meaning now, and that is why it has no
    /// paragraph.** It read "Not this one" over two sentences explaining that one
    /// question was being refused and the feature was not; the owner could not tell
    /// what it did without reading them. "Don't offer this test again" says the scope
    /// and the permanence in the label, which is where a permanent act belongs — see
    /// `ExperimentCopy.declineTitle`. The two rules that used to fence this group off
    /// from the sections above are gone with everything else; `Space.md` between the
    /// three controls and `Space.lg` above them does the separating.
    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PrimaryAction(title: copy.startTitle) { accept() }
                .accessibilityIdentifier("accept-experiment")

            if let randomised = copy.randomised {
                VStack(alignment: .leading, spacing: Space.xs) {
                    DirectionalLink(title: randomised.title, arrow: "→") { acceptDrawn() }
                        .accessibilityIdentifier("randomise-experiment")

                    Text(randomised.ask)
                        .textStyle(.body)
                        .foregroundStyle(ground.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(randomised.title). \(randomised.ask)")
            }

            // One quiet line, and still permanent. An offer with only a yes is not
            // an offer, and a visible no is safe to give here because the label says
            // what it refuses: one test, not the feature.
            DirectionalLink(title: copy.declineTitle, arrow: "→") { decline() }
                .accessibilityIdentifier("decline-experiment")
        }
    }

    // MARK: - After agreeing

    /// What was started, when it closes, and the drawn days if there are any.
    ///
    /// The change is repeated verbatim rather than summarised: it is the one thing
    /// to hold in your head for a fortnight, and this is the last screen on which
    /// it is the only thing present. A drawn window's day list is read here for the
    /// first time, in the moment it was drawn.
    ///
    /// **No span mark here, and the closing sentence is why.** `ExperimentCopy
    /// .started` already names the length and the date this window closes on, from
    /// the window's real start rather than from the sheet's guess — drawing the span
    /// again beside it would be those two facts twice, which is the mistake
    /// *Comparisons are arcs* records about putting a figure in the well. The rule
    /// that used to sit above "Got it" is gone, like the rest of them.
    private func confirmation(_ experiment: Experiment) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(experiment.change)
                    .textStyle(.sectionLead)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ExperimentCopy.started(experiment))
                    .textStyle(.body)
                    .foregroundStyle(ground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let days = ExperimentCopy.assignedDays(for: experiment) {
                    Text(days)
                        .textStyle(.body)
                        .foregroundStyle(ground.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenConfirmation(experiment))

            // "Got it", which is the word a finished result already closes with.
            // Nothing is being agreed to here — the agreement happened on the tap
            // that produced this screen — so the control only has to end it.
            PrimaryAction(title: ExperimentCopy.acknowledgeTitle) { dismiss() }
                .accessibilityIdentifier("acknowledge-proposal")
        }
        .pageGutter()
        .padding(.top, Space.lg)
        .padding(.bottom, Space.xl)
    }

    private func spokenConfirmation(_ experiment: Experiment) -> String {
        "\(ExperimentCopy.activeStanding). \(experiment.change) "
            + ExperimentCopy.started(experiment)
            + (ExperimentCopy.assignedDays(for: experiment).map { " \($0)" } ?? "")
    }

    // MARK: - Acts

    /// Take the ordinary offer.
    ///
    /// A nil return dismisses rather than reporting anything. It can only happen
    /// when a window is already running, which is also the state in which no
    /// proposal is offered anywhere — so the screen behind this one has already
    /// stopped showing the thing that raised it, and an error about a card that is
    /// no longer there would be the app explaining its own staleness.
    private func accept() {
        guard let experiment = store.acceptExperiment(proposal) else { return dismiss() }
        started = experiment
    }

    private func acceptDrawn() {
        guard let experiment = store.acceptRandomisedExperiment(proposal) else { return dismiss() }
        started = experiment
    }

    private func decline() {
        store.declineExperiment(proposal)
        dismiss()
    }
}
