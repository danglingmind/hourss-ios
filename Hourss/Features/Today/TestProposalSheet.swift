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
/// one copy sweep sees all of them — including the three "how it decided" lines
/// and the three verdicts, which are the two places this screen could most easily
/// start lying. `ExperimentCopy` documents that rule at length; this file is the
/// largest thing that has ever had to obey it.
///
/// **Nothing new was invented to draw it.** `HRule`, `Eyebrow`, the existing type
/// ramp, `Space`, `Radius.block` through `blockSurface` inside `PrimaryAction`,
/// and `SheetHeader` — the same sheet frame the reflection and the session sheet
/// use. No colour, badge, border, second rule weight or type size: two visual
/// changes have been reverted whole in this project and `DESIGN.md` records both.
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

    private var copy: ExperimentCopy.ProposalSheet { ExperimentCopy.sheet(for: proposal) }

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
    /// `Space.lg` between sections and `Space.xs` inside one: the gap that separates
    /// two answers has to be plainly larger than the gap between a heading and the
    /// thing it heads, or the screen reads as one list of eleven lines. Space is the
    /// lever `DESIGN.md` nominates for exactly this and it is the only one used
    /// here — every rule on the screen is `HRule` at 1pt.
    private var offer: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            section(copy.whatYouWouldDo, lead: true)

            ForEach(Array(copy.orderedSections.dropFirst().enumerated()), id: \.offset) { _, part in
                section(part, lead: false)
            }

            controls
        }
        .pageGutter()
        .padding(.top, Space.md)
        .padding(.bottom, Space.xl)
    }

    /// One block: its heading, then its lines.
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
            HRule()
            Eyebrow(part.heading)
            ForEach(Array(part.lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .textStyle(lead ? .sectionLead : .body)
                    // The first line of a block is the answer and the rest qualify
                    // it, which is the order the band on Today reads in too. On the
                    // one block with five lines — the three verdicts between their
                    // preamble and their closing line — every line is primary,
                    // because a verdict set quieter than its neighbours is the thing
                    // this section exists to prevent.
                    .foregroundStyle(index == 0 || part.lines.count > 2
                                     ? ground.foreground : ground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Spoken as one block with its heading first, so the subject arrives before
        // anything else and no label opens with a figure.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(part.spoken)
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
    /// **The ask finally has room to be read.** On the card it was 11pt mono under
    /// a link on a crowded band — the register `HealthFactRow` names for metadata
    /// and not for prose — and it is the paragraph that has to earn four weeks of
    /// somebody's life, including days they would rather not. Here it is body text.
    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HRule()

            PrimaryAction(title: copy.startTitle) { accept() }
                .accessibilityIdentifier("accept-experiment")
                .padding(.top, Space.xs)

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
            // an offer, and a visible no is only safe to give because `declineNote`
            // says what it refuses: one question, not the feature.
            VStack(alignment: .leading, spacing: Space.xs) {
                HRule()
                DirectionalLink(title: copy.declineTitle, arrow: "→") { decline() }
                    .accessibilityIdentifier("decline-experiment")

                Text(copy.declineNote)
                    .textStyle(.body)
                    .foregroundStyle(ground.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(copy.declineTitle). \(copy.declineNote)")
        }
    }

    // MARK: - After agreeing

    /// What was started, when it closes, and the drawn days if there are any.
    ///
    /// The change is repeated verbatim rather than summarised: it is the one thing
    /// to hold in your head for a fortnight, and this is the last screen on which
    /// it is the only thing present. A drawn window's day list is read here for the
    /// first time, in the moment it was drawn.
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

            HRule()

            // "Got it", which is the word a finished result already closes with.
            // Nothing is being agreed to here — the agreement happened on the tap
            // that produced this screen — so the control only has to end it.
            PrimaryAction(title: ExperimentCopy.acknowledgeTitle) { dismiss() }
                .accessibilityIdentifier("acknowledge-proposal")
        }
        .pageGutter()
        .padding(.top, Space.md)
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
