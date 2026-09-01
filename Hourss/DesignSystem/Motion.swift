import SwiftUI

/// Port of the `motion` block: 160ms fast, 200ms default, ease-out.
///
/// Every animation in the app routes through `Motion.animation(reduced:)` so the
/// system principle — "respect prefers-reduced-motion by removing nonessential
/// transition" — holds in one place instead of per call site.
enum Motion {
    static let fast: Double = 0.16
    static let standard: Double = 0.20

    static func animation(reduced: Bool, duration: Double = standard) -> Animation? {
        reduced ? nil : .easeOut(duration: duration)
    }
}
