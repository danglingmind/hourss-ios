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
        TitledFigure(title: fact.metric.title, figure: fact.figure, detail: fact.sentence)
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
            if case .comparison = fact.mark {
                mark
            } else {
                mark.revealsOnAppear(index: revealIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.md)
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
                title: "Comparison"
            )
        case .none:
            EmptyView()
        }
    }
}
