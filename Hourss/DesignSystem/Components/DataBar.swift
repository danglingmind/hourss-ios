import SwiftUI
import Accessibility

/// The one bar shape in the app.
///
/// Four separate `GeometryReader { ZStack { track; fill } }` implementations had
/// grown up at three different heights, two of them hardcoding their own track
/// colour instead of reading the surface. Everything routes through here now, so
/// a bar looks the same wherever it appears and a new mark costs a few lines.
struct DataBar: View {
    /// 0...1. `nil` renders the track alone — an unrated session is unknown, and
    /// unknown must not look like zero.
    let fraction: Double?
    var fill: Color = .lime
    var height: CGFloat = DataBar.reading

    @Environment(\.surface) private var surface

    /// Named heights, so the scale of a bar says what kind of bar it is.
    static let reading: CGFloat = 30    // a session's energy, beside the timeline
    static let evidence: CGFloat = 22   // a comparison on an insight
    static let strip: CGFloat = 18      // a day's shape in the journal
    static let progress: CGFloat = 8    // how far along something is

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(surface.track)
                if let fraction {
                    Rectangle()
                        .fill(fill)
                        .frame(width: geo.size.width * min(1, max(0, fraction)))
                }
            }
        }
        .frame(height: height)
    }
}

/// Proportional stacked segments — the shape of a day, or of a set.
///
/// Widths are weighted, so a 25-minute block reads as smaller than a two-hour one
/// rather than every session claiming equal space.
struct SegmentStrip: View {
    struct Segment: Identifiable {
        let id: UUID
        var weight: Double
        var color: Color

        init(id: UUID = UUID(), weight: Double, color: Color) {
            self.id = id
            self.weight = max(0.0001, weight)
            self.color = color
        }
    }

    let segments: [Segment]
    var height: CGFloat = DataBar.strip
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(0, segments.count - 1)) * spacing
            let available = max(0, geo.size.width - gaps)
            let total = max(0.0001, segments.reduce(0) { $0 + $1.weight })

            HStack(spacing: spacing) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: available * CGFloat(segment.weight / total))
                }
            }
        }
        .frame(height: height)
    }
}

/// Equal segments, some filled. Says how much of something is covered without
/// spending a sentence on it.
struct CoverageMark: View {
    /// One entry per segment; `true` means covered.
    let segments: [Bool]
    var fill: Color = .lime
    var height: CGFloat = DataBar.progress
    var spacing: CGFloat = 2

    @Environment(\.surface) private var surface

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, covered in
                Rectangle()
                    .fill(covered ? fill : surface.track)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
    }
}

/// Two or more labelled bars on a shared scale — the evidence behind a claim.
///
/// Carries an `AXChartDescriptor` so VoiceOver can walk the values rather than
/// hearing one summary string. That matters here: this mark replaces a sentence
/// that used to state the same numbers in prose, and the information cannot be
/// allowed to disappear along with the sentence.
struct ComparisonMark: View {
    struct Row: Identifiable {
        let id = UUID()
        var label: String
        var value: Double
        var count: Int?
        var highlighted: Bool
    }

    let rows: [Row]
    var scaleMax: Double = 5
    /// Spoken after the value, e.g. "4.6 out of 5".
    var unit: String = "out of 5"
    var title: String = "Average feeling"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label).textStyle(.body)
                        Spacer()
                        Text(String(format: "%.1f", row.value)).textStyle(.label)
                        if let count = row.count {
                            Text("· \(count)").textStyle(.label).foregroundStyle(Color.muted)
                        }
                    }
                    DataBar(
                        fraction: row.value / scaleMax,
                        fill: row.highlighted ? .lime : .rule,
                        height: DataBar.evidence
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spokenLabel(for: row))
            }
        }
        .accessibilityChartDescriptor(self)
    }

    private func spokenLabel(for row: Row) -> String {
        let base = "\(row.label): \(String(format: "%.1f", row.value)) \(unit)"
        guard let count = row.count else { return base }
        return "\(base), from \(count) sessions"
    }
}

extension ComparisonMark: AXChartDescriptorRepresentable {
    nonisolated func makeChartDescriptor() -> AXChartDescriptor {
        let categories = AXCategoricalDataAxisDescriptor(
            title: "Group",
            categoryOrder: rows.map(\.label)
        )
        let values = AXNumericDataAxisDescriptor(
            title: title,
            range: 0...scaleMax,
            gridlinePositions: [],
            valueDescriptionProvider: { String(format: "%.1f", $0) }
        )
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: false,
            dataPoints: rows.map { AXDataPoint(x: $0.label, y: $0.value) }
        )
        return AXChartDescriptor(
            title: title,
            summary: nil,
            xAxis: categories,
            yAxis: values,
            additionalAxes: [],
            series: [series]
        )
    }
}

/// Draws a mark in, once, the first time it appears.
///
/// A left-to-right wipe rather than a fade or a scale: it is the same gesture the
/// bar itself describes, so the motion reads as the data arriving rather than as
/// decoration. Works on any mark without the mark knowing about it, which is why
/// it is a mask and not a parameter threaded through `DataBar`.
///
/// The design system asks for motion that clarifies direction and for anything
/// non-essential to disappear under Reduce Motion — both hold here: with the
/// setting on, the mark is simply already drawn.
struct RevealOnAppear: ViewModifier {
    /// Position in the sequence, so several marks arrive one after another.
    var index: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: geo.size.width * progress)
                }
            }
            .onAppear {
                guard progress == 0 else { return }   // once, not on every redraw
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(
                        .easeOut(duration: Motion.reveal)
                        .delay(Double(index) * Motion.revealStagger)
                    ) {
                        progress = 1
                    }
                }
            }
    }
}

extension View {
    func revealsOnAppear(index: Int = 0) -> some View {
        modifier(RevealOnAppear(index: index))
    }
}
