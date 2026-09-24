import SwiftUI

/// Choosing a past slot by pointing at it on the day, rather than describing it
/// with two sliders.
///
/// **What this replaces, and why.** The slot used to be two coupled controls: a
/// slider for the start and another for the duration, where moving the first
/// changed what the second could say. Four things were wrong with that at once.
/// Two controls set one thing. Sixteen hours across a phone's width is sixty-four
/// quarter-hour steps at about five points each, which is not a distance a thumb
/// can aim. Neither control was the thing being chosen — a block of time on a
/// particular afternoon — so the person had to translate "that meeting after
/// lunch" into two positions and then read the result back to check. And the
/// sessions already in the record were invisible until you landed on one, at
/// which point the sheet told you that you had collided with something it could
/// have shown you all along.
///
/// So: the day itself, with what is already on it drawn in, and a drag that marks
/// out the part you mean. The same shape `DayHours` draws on Today, which is
/// deliberate — somebody who has looked at their day on that screen should
/// recognise this one without being told it is the same picture.
///
/// **Occupied time refuses the drag rather than warning about it.** A slot that
/// cannot be dragged over an existing session cannot overlap one, so the note
/// that used to appear after the fact has nothing left to say. That is the whole
/// of the indicator somebody asked for: not a warning about a collision, but a
/// drag that cannot reach one.
struct SlotPicker: View {
    /// Midnight of the day being drawn.
    let day: Date
    /// What is already logged, as spans within that day.
    let logged: [DateInterval]
    /// Beyond this, nothing has happened yet. Dragging stops here.
    let now: Date

    @Binding var start: Date
    @Binding var end: Date

    /// Quarter hours, matching the grid the whole sheet works in.
    var step: TimeInterval = 15 * 60

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hours = 24
    private static let trackHeight: CGFloat = 44

    private var dayEnd: Date { day.addingTimeInterval(TimeInterval(Self.hours) * 3600) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(surface.track)

                    ForEach(Array(logged.enumerated()), id: \.offset) { _, span in
                        block(span, in: geo.size.width)
                            .fill(surface.ruleColor)
                    }

                    // Beyond now, drawn as hatching rather than left blank: an
                    // empty afternoon that cannot be chosen looks the same as one
                    // that can, and somebody would drag at it before learning
                    // otherwise.
                    if now < dayEnd {
                        block(DateInterval(start: now, end: dayEnd), in: geo.size.width)
                            .fill(surface.ruleColor.opacity(0.28))
                    }

                    block(DateInterval(start: start, end: end), in: geo.size.width)
                        .fill(Color.lime)
                        .overlay {
                            block(DateInterval(start: start, end: end), in: geo.size.width)
                                .stroke(surface.foreground, lineWidth: 2)
                        }
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
        .accessibilityElement()
        .accessibilityLabel("Slot on the day")
        .accessibilityValue("\(clock(start)) to \(clock(end))")
        // Adjustable rather than a drag target: a blind reader cannot aim at a
        // strip, and the increment is the same quarter hour the drag snaps to.
        .accessibilityAdjustableAction { direction in
            let delta: TimeInterval = direction == .increment ? step : -step
            let moved = start.addingTimeInterval(delta)
            let length = end.timeIntervalSince(start)
            // Through the same clamp the drag uses, so the two cannot disagree
            // about what is reachable. A shift that would land on an occupied
            // hour returns nil and the slot stays where it was.
            guard let clamped = Self.clamp(
                DateInterval(start: moved, duration: length),
                within: day, to: dayEnd, logged: logged, now: now
            ), clamped.duration == length else { return }
            start = clamped.start
            end = clamped.end
        }
    }

    // MARK: - Drawing

    private func block(_ span: DateInterval, in width: CGFloat) -> Path {
        let total = dayEnd.timeIntervalSince(day)
        let x = CGFloat(max(0, span.start.timeIntervalSince(day)) / total) * width
        let w = CGFloat(min(total, span.end.timeIntervalSince(day)) / total) * width - x
        return Path(CGRect(x: x, y: 0, width: max(0, w), height: Self.trackHeight))
    }

    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(["00", "06", "12", "18"], id: \.self) { mark in
                Text(mark)
                    .textStyle(.label)
                    .foregroundStyle(surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .trailing) {
            Text("24").textStyle(.label).foregroundStyle(surface.tertiary)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Dragging

    /// Where the drag began, so the slot grows from there in either direction.
    @State private var anchor: Date?

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let touched = snapped(date(atX: gesture.location.x, width: width))
                let from = anchor ?? touched
                if anchor == nil { anchor = touched }

                // A tap, or a drag that has not yet moved a whole step, means the
                // default length rather than a zero-length slot.
                let lower = min(from, touched)
                let upper = max(from, touched)
                let proposed = upper > lower
                    ? DateInterval(start: lower, end: upper)
                    : DateInterval(start: lower, duration: step * 4)

                apply(proposed)
            }
            .onEnded { _ in anchor = nil }
    }

    private func apply(_ proposed: DateInterval) {
        guard let clamped = Self.clamp(proposed, within: day, to: dayEnd, logged: logged, now: now) else { return }
        start = clamped.start
        end = clamped.end
    }

    /// Clamps a proposed slot to the free time around where it was drawn.
    ///
    /// **This is the whole of the no-overlap guarantee**, which is why it is a
    /// static function over values rather than three methods reading properties.
    /// The sheet used to accept an overlapping slot and print a note about it
    /// afterwards; that note is gone, because a slot growing toward an existing
    /// session now stops at its edge and a drag across the whole afternoon lands
    /// against whatever is already there. A bug here is therefore not a cosmetic
    /// one — it is an overlapping session written to the record with nothing left
    /// to catch it.
    ///
    /// Nil when there is no room at all, which leaves the previous slot standing:
    /// a drag that starts inside an occupied hour should do nothing, not collapse
    /// the selection to a point.
    /// `nonisolated` on purpose. `SlotPicker` is a `View`, so the whole type is
    /// inferred `@MainActor`, and a static function on it inherits that even
    /// though it touches nothing isolated — pure arithmetic over four values.
    /// Called from a test that is not on the main actor it then traps at runtime
    /// rather than failing to compile, which crashes the test host and restarts
    /// it, and xcodebuild goes on to report the partial totals from before the
    /// crash as if they were the run. Marking it what it actually is costs
    /// nothing and removes the whole class of that.
    nonisolated static func clamp(
        _ proposed: DateInterval,
        within day: Date,
        to dayEnd: Date,
        logged: [DateInterval],
        now: Date
    ) -> DateInterval? {
        // Anything the proposed start already sits inside has no free room around
        // it to grow into.
        guard !logged.contains(where: { $0.start <= proposed.start && proposed.start < $0.end }) else { return nil }

        let nextBlock = logged.map(\.start).filter { $0 >= proposed.start }.min() ?? dayEnd
        let previousEnd = logged.map(\.end).filter { $0 <= proposed.start }.max() ?? day

        let ceiling = min(nextBlock, now)
        let lower = max(previousEnd, max(day, proposed.start))
        let upper = min(ceiling, proposed.end)
        guard upper > lower else { return nil }
        return DateInterval(start: lower, end: upper)
    }

    private func date(atX x: CGFloat, width: CGFloat) -> Date {
        let total = dayEnd.timeIntervalSince(day)
        let fraction = min(1, max(0, Double(x / max(1, width))))
        return day.addingTimeInterval(total * fraction)
    }

    private func snapped(_ date: Date) -> Date {
        let elapsed = date.timeIntervalSince(day)
        return day.addingTimeInterval((elapsed / step).rounded() * step)
    }

    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}
