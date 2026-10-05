import SwiftUI

/// How a `HealthDigest.Fact` is drawn, wherever it is drawn.
///
/// **Title, then figure, then sentence.** The row names the metric first, sets
/// the figure under the name, and keeps the sentence muted below it — the three
/// steps `TitledFigure` owns, at the three sizes it owns them at. The mark is
/// company for the number rather than the information itself, which is why it is
/// still the only part that animates in.
///
/// **This reverses what the row used to argue, deliberately.** The previous
/// version put the figure on top, on this reasoning, kept here rather than
/// deleted because it is the thing being overruled:
///
/// > The figure carries the fact and the sentence explains it, so the figure is
/// > set at display size and the sentence is muted underneath — the reverse of a
/// > dashboard, where the number is a label on a chart.
///
/// Every clause of that is right about a chart and wrong about a card. A chart
/// arrives with axes, a legend and a title standing around its number, so the
/// number really is the only part not already on screen and really does deserve
/// the emphasis. A card has nothing but what is printed on it. Leading with
/// "12%" therefore put the one element that cannot be understood alone in the
/// position the eye lands on first, and made the subject cost a full sentence to
/// recover — every time, on a screen people open daily. The figure has not been
/// demoted below the prose; it is still set larger than the sentence and still
/// carries the fact. It has only stopped arriving before the thing it measures.
///
/// **Where the title comes from, and why nothing is authored here.** It is
/// `fact.metric.title` — "Time asleep", "Heart rate variability", "Steps" — the
/// same strings the consent list shows before the OS dialog, which means they
/// have already been through the phrasing rules and are already the words this
/// person agreed to share. Writing a second set of names here would be two
/// vocabularies for one metric, and the copy sweeps could not tell which was
/// authoritative. Nothing else joins the title either: not `fact.kind`, not the
/// direction, not a qualifier. A name is not a claim, and anything appended to
/// it might be.
///
/// Extracted from the onboarding proof screen when Today started showing a fact
/// a day from the same pool. One treatment, not two: these are the same object
/// seen in two places, and a person who meets a weekday rhythm in onboarding
/// should recognise the next one without being told it is the same kind of
/// thing.
///
/// **One treatment, two amounts of room.** The sentence above still holds: there
/// is one row, one order, one type scale and one rule. What varies is the space
/// the row is given, and only that — see `HealthDigest.Fact.Standing`. A fact
/// from somebody's own log did not exist before they logged; a fact read off a
/// watch was true on the morning they installed this. Those are not the same
/// thing to have, and until now they were the same thing to look at.
///
/// **What was rejected, so it is not tried again as if new.** Varying the type
/// scale was the obvious move and the ramp will not take it: `TitledFigure` is
/// 34 / 26 / 16, each step about a third down from the last, and the sans sizes
/// below 34 are 26, 23, 18 and 16. Any quieter three-step ladder lands on pairs
/// 2 or 3pt apart, which stops reading as rank, or pushes the sentence into
/// `.label` — 11pt mono, the register this app uses for metadata and not for
/// prose. So a second scale would have had to invent sizes, and inventing sizes
/// to express rarity is how a type ramp becomes a set of one-offs. A badge, a
/// second rule weight, a tint and a background were all excluded before that, by
/// `DESIGN.md` — the 2pt `SectionRule` was built for exactly this problem, at
/// nine places, and reverted.
struct HealthFactRow: View {
    let fact: HealthDigest.Fact
    /// Stagger position for the mark's reveal. Rows shown together number
    /// themselves; a row shown alone leaves it at zero.
    var revealIndex: Int = 0
    /// Named by the surface rather than by this view, so a test can tell an
    /// onboarding fact from a daily one.
    var identifier: String

    /// The three lines the row prints, assembled once.
    ///
    /// Exposed rather than inlined into `body` so a test can assert what a reader
    /// actually gets — that the title is the metric's own name and that the
    /// spoken label leads with it — without rendering anything. `body` and the
    /// accessibility label then cannot disagree, because there is only one of
    /// these to disagree with.
    var titled: TitledFigure {
        TitledFigure(title: fact.subject.title, figure: fact.figure, detail: fact.sentence)
    }

    /// Room above and below the card, from what the fact cost to have.
    ///
    /// Exposed for the same reason `titled` is: it is the whole of the visual
    /// distinction between a fact somebody earned and a fact their watch already
    /// knew, and a test that can only assert "the row renders" would not catch it
    /// going back to one value for both.
    var room: CGFloat { fact.standing.room }

    /// Whether anything follows the figure.
    ///
    /// Checked before the mark enters the stack rather than left to `EmptyView`,
    /// because `revealsOnAppear` wraps it in a `ModifiedContent` and a stack's
    /// spacing is then being reserved for a subview that draws nothing. Every
    /// `.earned` fact is in exactly that position — every `RecordFacts` generator
    /// sets `.none`, because a superlative over the record has no second value to
    /// draw against — so the cards with the least to draw were the ones holding a
    /// gap open for a mark that never arrives.
    var drawsMark: Bool {
        switch fact.mark {
        case .weekdayRhythm, .comparison: true
        case .none: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            titled

            // Only the mark draws in. Wiping the sentence too would make the
            // screen feel like it was loading rather than like it was showing you
            // something.
            //
            // A comparison is exempt because it arrives as an arc, and the shared
            // wipe is a left-to-right rectangular mask — it would drag a straight
            // edge across a curve. `ComparisonArc` animates its own trim instead,
            // which is the same gesture in the shape the mark actually has.
            if drawsMark {
                if case .comparison = fact.mark {
                    mark
                } else {
                    mark.revealsOnAppear(index: revealIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, room)
        .overlay(alignment: .bottom) { HRule() }
        .accessibilityElement(children: .combine)
        // Subject first here for the same reason it is first on screen, and it
        // matters more here: a reader has no layout to glance back at, so a label
        // that opened with the figure left the number unattached to anything
        // until the sentence arrived.
        .accessibilityLabel(titled.spoken)
        .accessibilityIdentifier(identifier)
    }

    /// Lime at this person's high end, rule at their low end.
    private func rhythmColor(_ normalised: Double) -> Color {
        switch normalised {
        case ..<0.34: .rule
        case ..<0.67: .restorativeFill
        default: .lime
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch fact.mark {
        case .weekdayRhythm(let values):
            // Equal widths, varying colour. Weighting the widths compressed the
            // week into seven near-identical blocks; the extremes carry it better.
            HStack(spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Rectangle()
                        .fill(rhythmColor(value))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 16)
        case .comparison(let highLabel, let high, let lowLabel, let low):
            ComparisonMark(
                rows: [
                    .init(label: highLabel, value: high, count: nil, highlighted: true),
                    .init(label: lowLabel, value: low, count: nil, highlighted: false),
                ],
                scaleMax: max(high, low) * 1.15,
                unit: "",
                title: "Set against"
            )
        case .none:
            EmptyView()
        }
    }
}

/// How much it cost this person to have the card at all.
///
/// **Derived, never stored.** The pool already carries everything needed to tell
/// these apart, and a `rarity` field on `Fact` would be a presentation decision
/// kept in the type the engine's factor space and the consent screen both read
/// from. `subject` is the discriminator because it is the one that cannot be
/// wrong: a fact about a `RecordTopic` could not have been computed before
/// somebody logged, whatever its `kind` says. `kind == .best` agrees with it on
/// every fact the two generators currently produce, and a test pins that, but
/// `kind` is about the shape of the claim and `subject` is about where it came
/// from — and where it came from is the question being asked here.
///
/// **Only two cases, deliberately.** The real ordering of what is hard to come
/// by runs conjunction → pattern → record fact → health fact, and this row draws
/// the bottom two of those four. The top two are `InteractionSection` and the
/// insight surfaces, which are different components with different owners; a
/// four-case enum here would be two cases this file can never reach, read as a
/// promise that the whole ladder is handled when half of it is elsewhere.
extension HealthDigest.Fact {

    enum Standing {
        /// Exists because somebody logged. Every `RecordFacts` generator produces
        /// one of these, and not one of them exists on the morning of install.
        case earned
        /// Read off a watch and already true before Hourss was opened. Several
        /// generators over eleven metrics, so there are dozens of them and all of
        /// them exist on day one.
        case ambient

        /// Room above and below the card, and the whole of the distinction.
        ///
        /// **Why space and nothing else.** `DESIGN.md` records two visual changes
        /// that were reverted whole — a second rule weight at 2pt, and a
        /// full-bleed day canvas — and closes the first with the conclusion that
        /// "the lever is probably space rather than more lines". A badge, a
        /// border, a second accent or a second type scale would each be a new
        /// kind of mark in a system whose hierarchy is one rule weight and the
        /// type ramp. Two existing spacing tokens are not a new kind of anything.
        ///
        /// 40 and 16 rather than, say, 28 and 20: both are `Space` tokens with a
        /// rung between them, which is what makes the difference legible as rank
        /// rather than as two paddings that happen to differ. The pair is also
        /// deliberately asymmetric about today's 24 — the common case gets
        /// *quieter* by 8pt a side, so the change removes space from thirty-seven
        /// cards and spends it on four, instead of adding it everywhere.
        var room: CGFloat {
            switch self {
            case .earned: Space.lg
            case .ambient: Space.sm
            }
        }
    }

    var standing: Standing {
        switch subject {
        case .record: .earned
        case .health: .ambient
        }
    }
}
