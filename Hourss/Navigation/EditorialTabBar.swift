import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    /// **Tests is a tab, and it took the slot the `+` used to hold.**
    ///
    /// A test is the only thing this app does that answers a question rather than
    /// describing one: every unmeasured source ends in a fortnight, and the verdict
    /// at the end of it is the product. It lived two taps down, behind a row at the
    /// foot of Patterns, which was right while a test was a thing you did *about* a
    /// claim and wrong the moment it became the point.
    ///
    /// Five even slots now, and the `+` moved to the corner of every screen's
    /// header — see `ScreenHeader`. That corner was already judged "the most
    /// valuable position on the screen" when Today took its date out of it, and the
    /// other three were still spending it on the page's own name, which the bar
    /// below announces with an orange rule at the same moment.
    case today, patterns, tests, journal, you

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// A hand-built tab bar.
///
/// The design system bans pills, dense menus and outlined CTAs, defines no shadows
/// and puts every rounded corner on one token — none of which survives a stock
/// `TabView` under iOS 26's Liquid Glass chrome, which brings its own radius, its
/// own translucency and its own shadow. So this is flat: mono labels, a hairline
/// rule, the centred `+` that the spec makes the primary log action, and an orange
/// rule under whichever tab you are on.
///
/// Blocks here round on `Radius.block` now — the bar's `+` does. Hand-building the
/// bar is still what makes that a choice rather than a default.
struct EditorialTabBar: View {
    @Binding var selection: Tab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Thick enough to be a mark rather than a second hairline, thin enough that
    /// it is still a rule. The gutter mark in `DayTimeline` is 3pt because it is
    /// vertical and short; the same weight run across a whole tab reads as a bar.
    private static let underline: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            HRule(color: .rule)
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { tabButton($0) }
            }
            .frame(height: 54)
            // Inside the frame and outside the padding, so the overlay measures
            // exactly the width the five slots divide up.
            .overlay(alignment: .topLeading) { selectionRule }
            .padding(.horizontal, Space.xs)
        }
        .background(Color.canvas)
        // Five fixed slots cannot grow indefinitely: past this size the labels
        // truncate to "PATT…". Narrower than it was, since the five now divide the
        // whole bar rather than what a 60pt `+` left them — the cap is the same and
        // matters a little more. Content still scales all the way up; only the
        // chrome is capped, and VoiceOver reads the full name regardless.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    /// The selected tab's mark: an orange rule the width of its slot, sitting on
    /// the bottom edge of the row.
    ///
    /// It slides rather than reappears. Position is computed from the bar's own
    /// width instead of `matchedGeometryEffect` because the interesting part of
    /// this animation is the part with no tab under it — see `offset(tabWidth:)`.
    ///
    /// The text still goes ink-on-selected, muted otherwise. The rule is the loud
    /// half of the pair, not the only half: colour never carries state alone here,
    /// and a 2pt line is exactly the thing a person with a red-green deficiency or
    /// a dimmed screen can still lose.
    private var selectionRule: some View {
        GeometryReader { proxy in
            let tabWidth = proxy.size.width / CGFloat(Tab.allCases.count)
            Rectangle()
                .fill(Color.orange)
                .frame(width: tabWidth, height: Self.underline)
                .offset(
                    x: offset(tabWidth: tabWidth),
                    y: proxy.size.height - Self.underline
                )
                .animation(Motion.travel(reduced: reduceMotion), value: selection)
        }
        .allowsHitTesting(false)
        // The tab buttons already carry `.isSelected`; a second announcement of
        // the same fact is noise.
        .accessibilityHidden(true)
    }

    /// Distance from the bar's leading edge to the leading edge of `selection`'s
    /// slot.
    ///
    /// **This used to be four paragraphs.** The `+` sat in the middle and the rule
    /// had to travel straight through the region it occupied, which was allowed only
    /// because the lime block's lower edge cleared the bottom 2pt the rule lives in —
    /// and the alternatives, jumping the gap or fading across it, both put a
    /// discontinuity in the one motion whose job is to be followed by the eye. With
    /// the `+` in the header there is no gap, no exception and no argument: five even
    /// slots, and the rule moves by one of them.
    private func offset(tabWidth: CGFloat) -> CGFloat {
        CGFloat(Tab.allCases.firstIndex(of: selection) ?? 0) * tabWidth
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selection = tab
        } label: {
            Text(tab.title)
                .textStyle(.eyebrow)
                .foregroundStyle(selection == tab ? Color.ink : Color.muted)
                .frame(maxWidth: .infinity)
                .frame(height: Space.tapTarget)
                .contentShape(.rect)
                // A colour crossfade, not a journey: the ease-out token is right
                // here and the spring is not.
                .animation(Motion.animation(reduced: reduceMotion, duration: Motion.fast), value: selection)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityLabel(tab.rawValue.capitalized)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

}
