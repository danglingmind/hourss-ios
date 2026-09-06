import SwiftUI

/// Port of the `motion` block: 160ms fast, 200ms default, ease-out.
///
/// Every animation in the app routes through `Motion.animation(reduced:)` so the
/// system principle — "respect prefers-reduced-motion by removing nonessential
/// transition" — holds in one place instead of per call site.
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
}
