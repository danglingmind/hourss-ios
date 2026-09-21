import SwiftUI

/// Two values on concentric semicircular tracks — the shape a comparison takes
/// wherever `ComparisonMark` draws one.
///
/// **Why arcs rather than the bars this replaced.** Two stacked horizontal bars
/// are the most literal way to draw a comparison and the easiest to ignore: they
/// sit at the same weight as the body text around them and read as punctuation
/// rather than as the finding. An arc is the one mark in this app that owns
/// vertical space, and owning vertical space is the whole point — the comparison
/// *is* the fact, and it was being drawn as a footnote to itself.
///
/// **Why concentric and not one track split in two.** A split track says the two
/// values are shares of something. They are not: "weekends" and "weekdays" are
/// two independent means of the same measurement, and drawing them as slices of a
/// single arc would assert a part-to-whole relationship the data does not carry.
/// Two tracks each showing their own fraction of their own sweep says the true
/// thing instead.
///
/// **Why the different radii do not distort it.** A reader compares these by
/// angular extent, not by drawn length. The same fraction subtends the same angle
/// at any radius, so the inner ring is not quietly penalised for being the
/// shorter curve — which is exactly what would happen if these were two bars of
/// different lengths, or two arcs read as arc length.
///
/// **Why there is no figure in the middle.** Every surface that draws this
/// already states its own headline number immediately above — `HealthFactRow`
/// sets `fact.figure` at display size, `InsightDetailView` leads with the claim.
/// A number in the well would be that number a second time. The alternative, a
/// derived "difference", would be a new user-facing string that has to clear the
/// no-claims rules to say something the two readings below already say.
struct ComparisonArc: View {
    let rows: [ComparisonMark.Row]
    let scaleMax: Double
    /// Formats a row's value for the reading beneath. Passed in so this view
    /// never invents a unit — the caller owns what the number means.
    let format: (Double) -> String
    /// What VoiceOver says for one reading. Also the caller's, so the spoken form
    /// cannot drift from the one the bars used before this replaced them.
    let spoken: (ComparisonMark.Row) -> String

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 until the arcs have drawn themselves in.
    @State private var progress: CGFloat = 0

    /// Thick enough to read as a meter rather than as a hairline. The bars this
    /// replaces topped out at `DataBar.evidence` (22pt tall); an 11pt stroke on a
    /// curve carries comparable weight while occupying the vertical space that
    /// makes it look at.
    private static let lineWidth: CGFloat = 11
    /// Clear air between the rings, so two values never read as one thick band.
    private static let ringGap: CGFloat = 7
    /// Past this the mark stops being a mark and starts being a hero.
    private static let maxRadius: CGFloat = 96

    var body: some View {
        VStack(spacing: Space.md) {
            arcs
            readings
        }
        .onAppear(perform: draw)
    }

    // MARK: - The arcs

    private var arcs: some View {
        GeometryReader { geo in
            let outer = radius(forWidth: geo.size.width)
            let inner = outer - Self.lineWidth - Self.ringGap

            ZStack {
                ring(radius: outer, row: rows.first)
                ring(radius: inner, row: rows.count > 1 ? rows[1] : nil)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .frame(height: Self.maxRadius + Self.lineWidth / 2)
        .frame(maxWidth: .infinity)
        // The readings below say everything these draw, and the chart descriptor
        // on `ComparisonMark` carries the values for a VoiceOver reader who wants
        // to walk them. A third spoken copy would just be the same numbers again.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func ring(radius: CGFloat, row: ComparisonMark.Row?) -> some View {
        if let row {
            ZStack {
                // The track, always whole. Without it a short value reads as a
                // small object rather than as a small share of something.
                Semicircle(radius: radius)
                    .stroke(surface.track, style: stroke)

                Semicircle(radius: radius)
                    .trim(from: 0, to: fraction(of: row.value) * progress)
                    .stroke(fill(for: row), style: stroke)
            }
        }
    }

    private var stroke: StrokeStyle {
        // Round caps are a deliberate exception in a system that is otherwise
        // square everywhere — every `DataBar` is a `Rectangle`. A butt cap on a
        // curve reads as a slice cut out of a disc; a round one reads as a
        // measurement that stopped where it stopped, which is what this is.
        StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
    }

    private func fill(for row: ComparisonMark.Row) -> Color {
        row.highlighted ? .lime : surface.ruleColor
    }

    /// Clamped, because a caller's `scaleMax` is a presentation choice and a
    /// value above it must not wrap the arc back past its own start.
    private func fraction(of value: Double) -> CGFloat {
        guard scaleMax > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / scaleMax)))
    }

    /// Shrink to fit a narrow column rather than overflow it.
    private func radius(forWidth width: CGFloat) -> CGFloat {
        min(Self.maxRadius, max(0, (width - Self.lineWidth) / 2))
    }

    // MARK: - The readings

    /// Label, swatch and value for each ring, in ring order.
    ///
    /// The values are here and not in the arcs because colour must never carry
    /// the meaning alone — the same rule `DayTimeline` follows when it puts the
    /// score and its wording beside the bar rather than inside it. The swatch is
    /// a tie-back to its ring, never the information itself, which is why the
    /// reading is still complete when it is ignored.
    private var readings: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(rows) { row in
                HStack(spacing: Space.xs) {
                    Rectangle()
                        .fill(fill(for: row))
                        .frame(width: 8, height: 8)
                    Text(row.label).textStyle(.body)
                    Spacer(minLength: Space.xs)
                    Text(format(row.value)).textStyle(.label)
                    if let count = row.count {
                        Text("· \(count)")
                            .textStyle(.label)
                            .foregroundStyle(surface.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken(row))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reveal

    /// The arcs draw themselves round rather than being wiped across.
    ///
    /// `RevealOnAppear` masks left-to-right, which is the gesture a bar makes and
    /// the wrong one here — it would sweep a straight edge across a curve. So the
    /// trim is animated from the inside and the surfaces that draw this opt out
    /// of the shared modifier. Reduce Motion lands on the drawn state directly,
    /// per the same rule the wipe follows.
    private func draw() {
        guard progress == 0 else { return }
        if reduceMotion {
            progress = 1
        } else {
            withAnimation(.easeOut(duration: Motion.reveal)) { progress = 1 }
        }
    }
}

/// The upper half of a circle, seated on the bottom edge of its rect.
///
/// Drawn from 180° to 360° so `trim(from:to:)` fills left to right, which is the
/// direction every other mark in this app grows in.
private struct Semicircle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: max(0, radius),
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        return path
    }
}
