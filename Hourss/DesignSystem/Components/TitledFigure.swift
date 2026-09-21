import SwiftUI

/// Subject, then number, then meaning — the order somebody actually needs them.
///
/// **The problem this fixes.** Every readout in this app led with its figure, and
/// a figure alone says nothing: "12%" is not information until you know it is
/// about sleep, and the only way to find that out was to read the sentence
/// underneath. So the eye landed on the one element that could not be understood
/// on its own, and understanding cost a full sentence every time.
///
/// **Why the figure loses the top slot.** `HealthFactRow` used to argue the
/// reverse — the figure at display size, the sentence muted beneath, explicitly
/// "the reverse of a dashboard, where the number is a label on a chart". That
/// stance is right about a chart and wrong about a card: a chart has axes naming
/// its subject, and a card has nothing but what is printed on it. The number is
/// still the payload, and it is still set larger than the prose. It just no
/// longer arrives before the thing it measures.
///
/// **Three steps, not two.** 34 / 26 / 16 — each about a third up from the last,
/// which is far enough apart to read as rank rather than as three sizes that
/// happen to differ. The detail stays muted so the pair above it reads as one
/// unit.
struct TitledFigure: View {
    /// What this is about. A name, never a claim — the metric's own title, or the
    /// activity's, so nothing here has to clear the phrasing rules.
    let title: String
    /// The number that carries it, already formatted by whoever owns the units.
    let figure: String
    /// One sentence of meaning, or nil where the pair says enough by itself.
    var detail: String?

    @Environment(\.surface) private var surface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .textStyle(.dayNumeral)
                .fixedSize(horizontal: false, vertical: true)

            Text(figure)
                .textStyle(.stepName)
                .foregroundStyle(surface.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let detail {
                Text(detail)
                    .textStyle(.body)
                    .foregroundStyle(surface.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One spoken string for the whole block, in the same order it is read.
    ///
    /// Built here rather than at each call site so a reader never gets the number
    /// before the subject — the exact failure this component exists to fix, and
    /// the one that matters most when the layout is gone.
    var spoken: String {
        [title, figure, detail].compactMap { $0 }.joined(separator: ". ")
    }
}
