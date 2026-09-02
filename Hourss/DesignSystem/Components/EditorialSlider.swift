import SwiftUI

/// A flat slider.
///
/// `Slider` gives you a rounded capsule track and a circular thumb, and this
/// system sets every radius to zero and defines no shadows — so the control is
/// rebuilt from rectangles. The whole track is draggable, which lets the thumb be
/// what the system would want it to be: a rule, not a knob.
struct EditorialSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Mono captions at each end, in the same idiom as the rating scale.
    var lowLabel: String?
    var highLabel: String?
    /// What VoiceOver reads for the current value.
    var spokenValue: (Double) -> String

    @Environment(\.surface) private var surface

    private let trackHeight: CGFloat = 30
    /// The marker overhangs the track so it reads as a tick rather than a fill edge.
    private let markerOverhang: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = fraction(for: value)

                ZStack(alignment: .leading) {
                    DataBar(fraction: fraction, height: trackHeight)

                    Rectangle()
                        .fill(surface.foreground)
                        .frame(width: 2, height: trackHeight + markerOverhang * 2)
                        // Keep the marker inside the track at both extremes.
                        .offset(x: min(max(0, width * fraction - 1), width - 2))
                }
                .frame(height: geo.size.height, alignment: .center)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            update(toX: gesture.location.x, width: width)
                        }
                )
            }
            .frame(height: max(Space.tapTarget, trackHeight + markerOverhang * 2))

            if lowLabel != nil || highLabel != nil {
                HStack {
                    Text(lowLabel ?? "").textStyle(.label).foregroundStyle(surface.secondary)
                    Spacer()
                    Text(highLabel ?? "").textStyle(.label).foregroundStyle(surface.secondary)
                }
            }
        }
        // Stand in a real `Slider` for assistive tech. Hand-rolling the adjustable
        // action would leave the control reporting as a generic element, so
        // VoiceOver would not offer its swipe-to-adjust rotor and automation could
        // not drive it either — the visual rebuild should not cost the semantics.
        .accessibilityRepresentation {
            Slider(value: $value, in: safeRange, step: step)
                .accessibilityValue(spokenValue(value))
        }
    }

    /// `Slider` traps on an empty range, which a duration bound can collapse to
    /// when almost none of the day has passed.
    private var safeRange: ClosedRange<Double> {
        range.upperBound > range.lowerBound
            ? range
            : range.lowerBound...(range.lowerBound + max(step, 1))
    }

    private func fraction(for value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / span))
    }

    private func update(toX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(1, max(0, Double(x / width)))
        value = snap(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return min(range.upperBound, max(range.lowerBound, raw)) }
        let stepped = (raw / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }
}

/// Two or more text options with a 2pt accent underline on the active one.
///
/// The Journal filters already worked this way; pulling it out means the session
/// sheet's mode switch reads identically rather than inventing a second idiom —
/// and it keeps both away from the pills the design system rules out.
struct UnderlinePicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var identifierPrefix: String?

    @Environment(\.surface) private var surface

    var body: some View {
        HStack(spacing: Space.md) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .textStyle(.action)
                        .foregroundStyle(isSelected ? surface.foreground : surface.secondary)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isSelected ? Color.orange : .clear)
                                .frame(height: 2)
                                .offset(y: 6)
                        }
                        .frame(minHeight: Space.tapTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifierPrefix.map { "\($0)-\(option.title)" } ?? option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }
}
