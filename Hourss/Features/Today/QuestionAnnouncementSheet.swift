import SwiftUI

/// A question that could not be asked, announced once, with its answer on it.
///
/// **The same sheet whatever the answer was, and that is the honesty.** The
/// overwhelmingly common case is that the newly-answerable question found nothing
/// — `PRD-LOCKS.md` §8 names it as the risk and refuses to let the design
/// apologise for it — so there is no second layout, no quieter register and no
/// shorter reveal for an empty result. Four sections, one control, one movement,
/// identically. A sheet that was visibly bigger when it had a finding would teach
/// somebody that the ones without are failures, which is the opposite of what the
/// engine coming out alike means.
///
/// **A sheet rather than a toast**, because a toast is for something that does not
/// matter, and this is the app saying it can now answer a question about somebody's
/// own life.
///
/// **Not a single string is written here.** Every sentence comes from
/// `AnnouncementCopy.sheet(for:claim:)`, resolved into a value before anything
/// renders, so one sweep sees all of them — the rule `ExperimentCopy` documents at
/// length and the reason this screen's real risk, its words, is testable at all.
///
/// **The orange headings are not borrowed.** `TestProposalSheet` has section
/// headings in orange on the owner's instruction, on trial, on that screen; this
/// one keeps the standing rules — *Orange is a signal, not decoration* and
/// *Hierarchy comes from lines, not surfaces* — so its headings are ordinary
/// eyebrows over `HRule`s. A second screen adopting the trial would quietly end it
/// by making it the pattern, and nobody asked for that here. If the trial is
/// settled in orange's favour, this screen changes with everything else.
struct QuestionAnnouncementSheet: View {
    @Environment(\.dismiss) private var dismiss

    let announcement: QuestionAnnouncement

    private var copy: AnnouncementCopy.Sheet { announcement.sheet }

    /// The ground this sheet paints, named rather than read from the environment.
    ///
    /// It cannot be read: this view is the one applying `.surface(.canvas)`, so
    /// `@Environment(\.surface)` here would report whatever its presenter set — the
    /// trap `ObservationSlotView.surface` and `TestProposalSheet.ground` both
    /// document.
    private let ground: Surface = .canvas

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What this is, in the one place on the sheet that cannot be scrolled
            // away from: a question opened. Not a finding, not news, and nothing
            // that reads as a reward — `PRD-LOCKS.md` §2 is this line.
            SheetHeader(title: copy.standing, onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    // Four blocks, in the order `orderedSections` fixes: which
                    // question, what it found, why now, and the limit. The answer is
                    // second and not last — a sheet that explained the gate before
                    // saying what it found would be building up to a payout.
                    ForEach(Array(copy.orderedSections.enumerated()), id: \.offset) { index, part in
                        section(part, index: index)
                    }

                    // One control, and it decides nothing. The agreement, the
                    // refusal and the test all belong to other screens; this one
                    // only has to end.
                    PrimaryAction(title: copy.closeTitle) { dismiss() }
                        .accessibilityIdentifier("acknowledge-opened-question")
                }
                .pageGutter()
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
        }
        .surface(.canvas)
        // Stated rather than taken from iOS, so the sheet's own container is on the
        // same token as everything inside it, exactly as the other three sheets do.
        .presentationCornerRadius(Radius.block)
        .accessibilityIdentifier("question-announcement")
    }

    /// One block: its heading, a rule, then what it says.
    ///
    /// **The motion is `revealsOnAppear`, which is the app's existing reveal and the
    /// whole of what is used here.** It is `Motion.reveal` with `Motion
    /// .revealStagger` per index and it lands on the finished state under Reduce
    /// Motion — the three things this feature's rules ask for, already written,
    /// already tested, in the one place animations in this app are allowed to come
    /// from. The stagger is what makes the sheet read in the order §2 insists on:
    /// the question, then what it found, rather than all of it at once.
    ///
    /// Identical for every section, including the one carrying the answer, because
    /// an answer that arrived with more ceremony when there was something to say
    /// would be the tease the whole feature is built to avoid.
    private func section(_ part: AnnouncementCopy.Sheet.Section, index: Int) -> some View {
        // The first section is the question itself and is the only one set large.
        // Decided from the index rather than from a flag on the section, because the
        // order *is* the design and `orderedSections` owns it — a second place
        // naming the lead is a second place for the two to disagree.
        let lead = index == 0

        return VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(part.heading)
            HRule()

            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(Array(part.parts.enumerated()), id: \.offset) { _, piece in
                    view(for: piece, lead: lead)
                }
            }
            .padding(.top, Space.xs)
        }
        // Spoken as one block with its heading first, so the subject arrives before
        // anything else and no label opens with a figure. `Section.spoken` is
        // assembled in the copy layer with every other word on the screen.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(part.spoken)
        .revealsOnAppear(index: index)
    }

    /// One part of a section, in the register its own case names.
    ///
    /// Nothing here counts lines or infers weight from how many there are — the
    /// mistake `ExperimentCopy.ProposalSheet.Part` was created to end. The case says
    /// what the thing is; this draws it.
    @ViewBuilder
    private func view(for part: AnnouncementCopy.Sheet.Part, lead: Bool) -> some View {
        switch part {
        case .line(let text):
            // `.sectionLead` at 23pt for the question's own name, which is the one
            // thing on this sheet somebody should be able to read from a thumb's
            // distance. Everything else, the answer included, is body — and that is
            // the point: the question is what opened.
            Text(text)
                .textStyle(lead ? .sectionLead : .body)
                .foregroundStyle(ground.foreground)
                .fixedSize(horizontal: false, vertical: true)

        case .quiet(let text):
            Text(text)
                .textStyle(.body)
                .foregroundStyle(ground.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
