import SwiftUI

/// Port of the `spacing` and `layout` blocks. Page gutter uses the mobile value
/// (18pt), since every iPhone falls below the system's 700px breakpoint.
enum Space {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 16
    static let md: CGFloat = 24
    static let lg: CGFloat = 40
    static let xl: CGFloat = 64
    static let xxl: CGFloat = 96
    static let xxxl: CGFloat = 150

    static let gutter: CGFloat = 18

    /// Minimum tap target, per the design system's responsive rules.
    static let tapTarget: CGFloat = 44
}

extension View {
    /// The standard page gutter. Named rather than inlined so the reading column
    /// stays consistent across every screen.
    func pageGutter() -> some View { padding(.horizontal, Space.gutter) }
}
