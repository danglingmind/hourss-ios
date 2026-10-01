import SwiftUI

/// The one corner radius in the app.
///
/// **This reverses a standing rule, deliberately.** `hourss-ui-system.json` set
/// `radius.default: 0px` — *"the product relies on type and lines, not rounded
/// panels"* — and every block in Hourss was square because of it: `PrimaryAction`,
/// the tab bar's `+`, the preset chips, the forest panels, the sheets, and
/// `AppleSignInButton`, which is wrapped from UIKit specifically so that its
/// `cornerRadius` could be forced to zero. The owner has decided the blocks should
/// be rounded. That is a change of position, not drift, and it is recorded here so
/// the next person reading `DESIGN.md`'s history does not restore the old rule
/// thinking it was never retired.
///
/// **What did *not* change.** There are still no shadows, and lines and type still
/// carry the hierarchy — `HRule` is still doing the job a card border does
/// elsewhere. Radius alone moved. Rules, bars, hour cells, arcs and data marks stay
/// square: rounding the ends of a 2pt rule is a separate decision and nobody has
/// taken it.
///
/// **One token, and only one.** The whole point of the request was that the number
/// be tunable from one place, so no view may write a radius of its own and there is
/// deliberately no second token for "slightly different corners" — a block that
/// wants a different curve is a block that has stopped being part of the set.
///
/// **Why this file lives in `Shared/` rather than beside `Space`.** The Live
/// Activity is in the `HourssWidgets` target, which compiles `Shared/` and
/// `HourssWidgets/` and never sees `Hourss/DesignSystem/`. A token in `Spacing.swift`
/// would have forced the widget to hardcode its own copy, which is the one thing
/// this token exists to prevent. `Shared/HourssColor.swift` is the precedent: design
/// tokens both targets need live here.
enum Radius {
    /// Every filled or bordered surface that reads as a block: buttons, chips,
    /// panels, cards, the active-session panel, the Live Activity's stop control,
    /// and the sheets' own containers.
    ///
    /// 10pt against block heights of 44–50pt is about a fifth of the shorter side —
    /// unmistakably rounded at a glance, and still a long way from the filled
    /// capsule the token file banned for its own separate reasons. It is meant to be
    /// tuned; change it here and every block follows.
    static let block: CGFloat = 10
}

extension View {
    /// Paints a block component's own surface and clips it to `Radius.block`.
    ///
    /// Named rather than inlined for the same reason `pageGutter()` is: a call site
    /// that spells out `.rect(cornerRadius:)` is a call site that can be given a
    /// different number by somebody in a hurry, and then there are two radii in the
    /// app and no single place to tune.
    ///
    /// Circular corners, not `.continuous`. `AppleSignInButton` sits directly beside
    /// `PrimaryAction` on the sign-in screen and can only offer `CALayer.cornerRadius`,
    /// which is circular; matching it is worth more than the slightly smoother curve.
    ///
    /// This does not touch `contentShape`. Several of these blocks set their own, and
    /// the tappable area is left as the full rectangle on purpose — losing the four
    /// corners of a 44pt target buys nothing and costs taps at the edge.
    func blockSurface(_ fill: some ShapeStyle) -> some View {
        background(fill, in: .rect(cornerRadius: Radius.block))
    }
}
