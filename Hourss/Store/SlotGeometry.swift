import Foundation

/// Where a past slot is allowed to sit, and what happens when you try to put it
/// somewhere it is not.
///
/// **Pure, and separate from the view, because it is the guarantee.** The log
/// sheet used to accept a slot lying on top of an existing session and print a
/// note about the collision afterwards. That note is gone, so nothing warns
/// anybody now — which is only an improvement if a slot genuinely cannot get
/// there. The first version of this lived inside the picker and guarded exactly
/// one of the five paths that write a slot, so tapping a preset, or merely
/// opening the sheet, could land on top of something. Everything goes through
/// `place` now, and `place` is a function over values that a test can call
/// directly.
enum SlotGeometry {

    /// The grid the whole sheet works on.
    static let step: TimeInterval = 15 * 60

    /// Which end of the slot a drag is moving.
    enum Edge { case start, end }

    /// The free stretch containing a moment, bounded by whatever is logged either
    /// side of it and by the ends of the window it sits in.
    ///
    /// Nil when the moment is inside something already logged, or after `now` —
    /// there is no free room at a moment that is already spoken for, and a drag
    /// that reaches one should do nothing rather than jump somewhere it can fit.
    static func gap(
        containing moment: Date,
        in window: DateInterval, logged: [DateInterval]
    ) -> DateInterval? {
        guard moment >= window.start, moment < window.end else { return nil }
        guard !logged.contains(where: { $0.start <= moment && moment < $0.end }) else { return nil }

        let upper = logged.map(\.start).filter { $0 > moment }.min() ?? window.end
        let lower = logged.map(\.end).filter { $0 <= moment }.max() ?? window.start
        guard upper > lower else { return nil }
        return DateInterval(start: lower, end: min(upper, window.end))
    }

    /// Every free stretch of the window, earliest first.
    static func freeGaps(in window: DateInterval, logged: [DateInterval]) -> [DateInterval] {
        let ceiling = window.end
        guard ceiling > window.start else { return [] }

        var gaps: [DateInterval] = []
        var cursor = window.start
        for block in logged.sorted(by: { $0.start < $1.start }) {
            if block.start > cursor { gaps.append(DateInterval(start: cursor, end: min(block.start, ceiling))) }
            cursor = max(cursor, block.end)
            if cursor >= ceiling { break }
        }
        if cursor < ceiling { gaps.append(DateInterval(start: cursor, end: ceiling)) }
        return gaps.filter { $0.duration >= step }
    }

    /// Puts a slot of `length` around `moment`, inside whatever room there is.
    ///
    /// Used by everything that positions a whole slot rather than dragging one
    /// end: the presets, the sheet's own default, and the hour tapped on Today's
    /// strip. Each of those used to write the slot straight out, which is how a
    /// preset could land on an existing session.
    static func place(
        length: TimeInterval,
        around moment: Date,
        endingAt anchorEnd: Bool = true,
        in window: DateInterval, logged: [DateInterval]
    ) -> DateInterval? {
        // The room is measured from just inside the slot rather than from its
        // outer edge, because a slot that ends exactly where a session begins is
        // legal and `gap(containing:)` would refuse the shared instant.
        let probe = anchorEnd ? moment.addingTimeInterval(-1) : moment

        // Falling back rather than refusing when the moment itself is spoken for.
        //
        // The preset case makes this necessary: "the last hour" tapped at noon,
        // with something already logged from a quarter past eleven, has no room
        // where it was asked for. Returning nothing means a button that visibly
        // does nothing, which reads as broken. The nearest free room in the
        // direction the slot was growing is what somebody meant — an hour, as
        // late as one will fit.
        let room: DateInterval
        if let here = gap(containing: probe, in: window, logged: logged) {
            room = here
        } else {
            let free = freeGaps(in: window, logged: logged)
            guard let fallback = anchorEnd
                ? free.last(where: { $0.end <= probe })
                : free.first(where: { $0.start >= probe })
            else { return nil }
            room = fallback
        }

        let wanted = min(length, room.duration)
        guard wanted >= step else { return nil }

        if anchorEnd {
            let end = min(moment, room.end)
            let start = max(room.start, end.addingTimeInterval(-wanted))
            return DateInterval(start: start, end: end)
        }
        // Shortened to the room rather than slid back into it: the moment is
        // where somebody pointed, and moving it to preserve a requested length
        // would answer a question they did not ask.
        let start = max(moment, room.start)
        return DateInterval(start: start, end: min(room.end, start.addingTimeInterval(wanted)))
    }

    /// Moves one end of an existing slot, leaving the other where it is.
    ///
    /// This is what dragging a handle does, and it is why the picker no longer
    /// keeps an anchor. The old drag decided a slot from where the finger went
    /// down and where it is now, so dragging back across a logged session made
    /// the proposed start land inside it, the clamp refuse, and then — one step
    /// further — the whole selection reappear on the far side of the block.
    /// Moving one named end cannot do that: the other end never moves, so there
    /// is nothing for the slot to jump over.
    static func resize(
        _ slot: DateInterval, edge: Edge, to moment: Date,
        in window: DateInterval, logged: [DateInterval]
    ) -> DateInterval? {
        // The room is measured around the end that is staying put, so a handle
        // dragged into an occupied hour stops at its boundary rather than
        // finding a different gap to live in.
        let fixed = edge == .start ? slot.end.addingTimeInterval(-1) : slot.start
        guard let room = gap(containing: fixed, in: window, logged: logged) else {
            return nil
        }

        switch edge {
        case .start:
            let lowest = room.start
            let highest = slot.end.addingTimeInterval(-step)
            guard highest >= lowest else { return nil }
            return DateInterval(start: min(max(moment, lowest), highest), end: slot.end)
        case .end:
            let lowest = slot.start.addingTimeInterval(step)
            let highest = room.end
            guard highest >= lowest else { return nil }
            return DateInterval(start: slot.start, end: max(min(moment, highest), lowest))
        }
    }

    /// Shifts a whole slot by a number of steps, keeping its length.
    ///
    /// What the stepper buttons do, and the accessible way to move a slot at all:
    /// a strip is not something a blind reader can aim at, and a quarter hour is
    /// three and a half points wide even for somebody who can see it.
    static func nudge(
        _ slot: DateInterval, edge: Edge, by steps: Int,
        in window: DateInterval, logged: [DateInterval]
    ) -> DateInterval? {
        let moved = (edge == .start ? slot.start : slot.end)
            .addingTimeInterval(Double(steps) * step)
        return resize(slot, edge: edge, to: moved, in: window, logged: logged)
    }

    /// A moment snapped to the grid, measured from the window's own origin.
    static func snap(_ moment: Date, from origin: Date) -> Date {
        let elapsed = moment.timeIntervalSince(origin)
        return origin.addingTimeInterval((elapsed / step).rounded() * step)
    }
}
