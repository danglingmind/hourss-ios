import SwiftUI

/// Port of the `motion` block: 160ms fast, 200ms default, ease-out — plus one
/// spring, for the case the ease-out tokens get wrong (see `travel`).
///
/// Every animation in the app routes through this type so the system principle —
/// "respect prefers-reduced-motion by removing nonessential transition" — holds
/// in one place instead of per call site. Both entry points return an optional
/// `Animation` and both return `nil` when Reduce Motion is on: the finished state
/// arrives directly, never a shortened version of the transition.
enum Motion {
    static let fast: Double = 0.16
    static let standard: Double = 0.20

    /// A one-time reveal, for a mark drawing itself the first time it appears.
    ///
    /// Longer than the interaction tokens on purpose: those confirm a tap and must
    /// feel instant, while this is a chart being drawn and needs long enough to be
    /// read as drawing rather than as a flicker. Still ease-out, still small, and
    /// still nothing when Reduce Motion is on.
    static let reveal: Double = 0.55
    /// Gap between successive marks, so three facts arrive as three, not as one.
    static let revealStagger: Double = 0.12

    static func animation(reduced: Bool, duration: Double = standard) -> Animation? {
        reduced ? nil : .easeOut(duration: duration)
    }

    /// A mark travelling from one place on screen to another.
    ///
    /// The ease-out tokens above are for things that appear, recolour or shift by
    /// a few points — a curve that starts at full speed and decays is right when
    /// the eye has nothing to track. A rule crossing the width of the tab bar is
    /// the opposite case: it is one object moving a long way, the eye follows it,
    /// and an ease-out arrives by slowing to a crawl over the last third, which
    /// reads as the line being dragged rather than thrown.
    ///
    /// So: a spring, tuned against the system tab bar's own transition. `response`
    /// is the half-period — 0.32s is quick enough that the line is already there
    /// when the new screen paints. `dampingFraction` 0.8 leaves roughly 1.5% of
    /// overshoot, a point or two at this travel distance: enough that the line
    /// settles rather than stopping dead, not enough to read as a wobble.
    static let springResponse: Double = 0.32
    static let springDamping: Double = 0.80

    static func travel(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: springResponse, dampingFraction: springDamping)
    }

    /// Content changing under a control somebody just used.
    ///
    /// A third token rather than reusing either of the two above, because this is
    /// a third thing. `animation` is for something recolouring or shifting a few
    /// points; `travel` is for one object the eye follows across a distance. This
    /// is a *set* of things being replaced by a different set — a filter narrowing
    /// a list, a picker swapping a form, a selection moving to another row — where
    /// nothing travels and the change lands all at once.
    ///
    /// An ease-out is wrong for that in the same way it was wrong for the tab
    /// rule: content that arrives by decelerating to a stop reads as *loading*,
    /// and nothing here is loading. A spring lands. This one is softer than
    /// `travel` — a longer half-period and heavier damping, so a list settles
    /// rather than snapping, and with no overshoot at all, because rows that
    /// spring past their resting position and come back read as bouncy where the
    /// tab rule's tiny overshoot reads as alive.
    ///
    /// Nil under Reduce Motion, like everything else here: the new content is
    /// simply already there.
    static func content(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.38, dampingFraction: 1.0)
    }
}
