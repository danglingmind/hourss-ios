import SwiftUI

/// The day, with what is already on it, and a slot you move by its two ends.
///
/// **Why handles rather than a drag across the strip.** The first version worked
/// the way a selection rectangle does: press somewhere, drag, and the slot is
/// whatever lies between the two points. Three things went wrong with that at
/// once, and all three were reported the same day.
///
/// It was ambiguous. One drag had to mean both ends, so there was no way to move
/// one of them without redrawing the other from scratch.
///
/// It jumped. Dragging back across an existing session put the proposed start
/// inside it, which the clamp refused, and then one step further the whole
/// selection reappeared on the far side of the block. Nothing was wrong with the
/// clamp; the interaction was asking it a question with two answers.
///
/// And a quarter hour is three and a half points. A day across a phone is about
/// fourteen points to the hour, which is a fine scale to *read* and no scale at
/// all to *aim at* — a fingertip covers forty minutes. That is not a bug to fix,
/// it is what putting a whole day on one line costs, so the strip is for placing
/// and `SlotStepper` underneath it is for landing.
///
/// **Occupied time is unreachable rather than warned about.** Everything here
/// goes through `SlotGeometry`, which is now also what the presets and the
/// sheet's default use. The first version guarded the drag and only the drag, so
/// a preset could land straight on top of a session — the overlap note had been
/// deleted on the strength of a guarantee that covered one path in five.
struct SlotPicker: View {
    /// The stretch the strip draws, which is the stretch a slot may sit in.
    ///
    /// **Not the calendar day, deliberately.** Keying this to midnight put back a
    /// bug the sheet had already fixed once: at half past midnight the day is
    /// thirty minutes old, so there was nowhere to log the evening that had just
    /// finished. `StartSessionView`'s own note on its window says it plainly —
    /// the day boundary is a property of the calendar rather than of when
    /// somebody stopped working, and this control has no business enforcing it.
    ///
    /// It is also a third narrower than a day, which the scale needed: sixteen
    /// hours across a phone is about twenty-one points to the hour rather than
    /// fourteen.
    let window: DateInterval
    let logged: [DateInterval]

    @Binding var start: Date
    @Binding var end: Date

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackHeight: CGFloat = 52

    @State private var dragging: SlotGeometry.Edge?

    private var slot: DateInterval {
        DateInterval(start: start, end: max(end, start.addingTimeInterval(60)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(surface.track)

                    ForEach(Array(logged.enumerated()), id: \.offset) { _, span in
                        rect(span, in: geo.size.width).fill(surface.ruleColor)
                    }

                    // Nothing is drawn for "the future" any more: the window ends
                    // at now, so there is none of it on screen to mistake for
                    // free time.
                    rect(slot, in: geo.size.width).fill(Color.lime)
                    handle(at: start, in: geo.size.width)
                    handle(at: end, in: geo.size.width)
                }
                .frame(height: Self.trackHeight)
                .contentShape(.rect)
                .gesture(drag(width: geo.size.width))
                .animation(Motion.content(reduced: reduceMotion), value: start)
                .animation(Motion.content(reduced: reduceMotion), value: end)
            }
            .frame(height: Self.trackHeight)

            axis
        }
        // One element, and deliberately not adjustable: a strip cannot be aimed
        // at without sight, and the steppers below are a better control for
        // everyone rather than an accessible alternative to this one.
        .accessibilityElement()
        .accessibilityLabel("The hours behind you, with this slot on them")
        .accessibilityValue("\(clock(start)) to \(clock(end))")
    }

    // MARK: - Drawing

    private func x(of moment: Date, in width: CGFloat) -> CGFloat {
        let total = window.duration
        return CGFloat(min(1, max(0, moment.timeIntervalSince(window.start) / total))) * width
    }

    private func rect(_ span: DateInterval, in width: CGFloat) -> Path {
        let from = x(of: span.start, in: width)
        let to = x(of: span.end, in: width)
        return Path(CGRect(x: from, y: 0, width: max(0, to - from), height: Self.trackHeight))
    }

    /// A grip standing proud of the track at both ends, so each reads as
    /// something to take hold of rather than as where a fill happens to stop.
    private func handle(at moment: Date, in width: CGFloat) -> some View {
        Rectangle()
            .fill(surface.foreground)
            .frame(width: 4, height: Self.trackHeight + 12)
            .offset(x: min(max(0, x(of: moment, in: width) - 2), width - 4))
            .allowsHitTesting(false)
    }

    /// Real clock times rather than 00/06/12/18, because the window no longer
    /// starts at midnight and labelling it as though it did would be a lie in the
    /// one place somebody looks to orient themselves.
    private var axis: some View {
        // Three leading marks and one trailing, not four and one: a twelve-hour
        // clock reads "12:41 AM" at ten characters, and five of those across a
        // phone put the last leading label straight through the trailing one.
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { third in
                Text(clock(window.start.addingTimeInterval(window.duration * Double(third) / 3)))
                    .textStyle(.label)
                    .foregroundStyle(surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .trailing) {
            Text(clock(window.end))
                .textStyle(.label)
                .foregroundStyle(surface.tertiary)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Dragging

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                // Decided once, from where the finger went down, and held for the
                // rest of the gesture. Deciding per event is what let one drag
                // change its mind about which end it was moving halfway across.
                let edge = dragging ?? nearerEdge(toX: gesture.startLocation.x, width: width)
                if dragging == nil { dragging = edge }

                let moment = SlotGeometry.snap(date(atX: gesture.location.x, width: width),
                                               from: window.start)
                guard let moved = SlotGeometry.resize(
                    slot, edge: edge, to: moment, in: window, logged: logged
                ) else { return }

                start = moved.start
                end = moved.end
            }
            .onEnded { _ in dragging = nil }
    }

    private func nearerEdge(toX x: CGFloat, width: CGFloat) -> SlotGeometry.Edge {
        abs(x - self.x(of: start, in: width)) <= abs(x - self.x(of: end, in: width)) ? .start : .end
    }

    private func date(atX x: CGFloat, width: CGFloat) -> Date {
        return window.start.addingTimeInterval(
            window.duration * min(1, max(0, Double(x / max(1, width)))))
    }

    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

/// Fifteen minutes at a time, on whichever end is named.
///
/// The strip cannot be aimed at to the quarter hour and nothing will make it so
/// while it shows a whole day. This is where a slot is actually landed once the
/// strip has put it roughly where it goes — and it is the only part of the
/// control that works without sight.
struct SlotStepper: View {
    let title: String
    let value: Date
    let onStep: (Int) -> Void

    @Environment(\.surface) private var surface

    var body: some View {
        HStack(spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(title)
                Text(value.formatted(.dateTime.hour().minute()))
                    .textStyle(.stepName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.xs)
            button("−", steps: -1)
            button("+", steps: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted(.dateTime.hour().minute()))
        .accessibilityAdjustableAction { onStep($0 == .increment ? 1 : -1) }
    }

    private func button(_ glyph: String, steps: Int) -> some View {
        Button { onStep(steps) } label: {
            Text(glyph)
                .font(.custom("DMSans-Medium", fixedSize: 22))
                .foregroundStyle(surface.foreground)
                .frame(width: Space.tapTarget, height: Space.tapTarget)
                .background(Color.ink.opacity(0.05))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}
