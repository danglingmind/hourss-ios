import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today, patterns, journal, you

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

/// A hand-built tab bar.
///
/// The design system bans pills, dense menus and outlined CTAs, sets every corner
/// radius to zero and defines no shadows — none of which survives a stock
/// `TabView` under iOS 26's Liquid Glass chrome. So this is flat: mono labels, a
/// hairline rule, the centred `+` that the spec makes the primary log action, and
/// an orange rule under whichever tab you are on.
struct EditorialTabBar: View {
    @Binding var selection: Tab
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The `+` is the one slot that does not grow: four tabs share what is left.
    private static let logSlot: CGFloat = 60
    /// Thick enough to be a mark rather than a second hairline, thin enough that
    /// it is still a rule. The gutter mark in `DayTimeline` is 3pt because it is
    /// vertical and short; the same weight run across a whole tab reads as a bar.
    private static let underline: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            HRule(color: .rule)
            HStack(spacing: 0) {
                tabButton(.today)
                tabButton(.patterns)
                logButton
                tabButton(.journal)
                tabButton(.you)
            }
            .frame(height: 54)
            // Inside the frame and outside the padding, so the overlay measures
            // exactly the width the five slots divide up.
            .overlay(alignment: .topLeading) { selectionRule }
            .padding(.horizontal, Space.xs)
        }
        .background(Color.canvas)
        // Five fixed slots cannot grow indefinitely: past this size the labels
        // truncate to "PATT…". Content still scales all the way up — only the
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
            let tabWidth = max(0, (proxy.size.width - Self.logSlot) / 4)
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
    /// slot. Journal and You sit one `+` further along than their index suggests.
    ///
    /// Travel is continuous in x, including across the middle — Patterns to
    /// Journal takes the rule straight through the region the `+` occupies. That
    /// is allowed because the two never share any pixels: the lime square is 38pt
    /// tall inside a 44pt button inside a 54pt row, so its lower edge is 8pt above
    /// the row's, and the rule lives in the 2pt at the very bottom. The line
    /// passes below the `+`, not behind it or through it.
    ///
    /// The alternatives both cost more than they save. Skipping the middle — the
    /// rule jumping the 60pt gap — puts a discontinuity in the one motion whose
    /// whole job is to be followed by the eye. Fading or contracting while
    /// crossing means the mark is absent at the exact moment the reader is looking
    /// for where it went. A rule in flight is not read as underlining whatever it
    /// is momentarily over: it is read as being on its way, which is precisely the
    /// thing the animation exists to say. Nothing ever comes to rest there,
    /// because the `+` opens a sheet and is never a selection.
    private func offset(tabWidth: CGFloat) -> CGFloat {
        let index = CGFloat(Tab.allCases.firstIndex(of: selection) ?? 0)
        let crossedTheMiddle = selection == .journal || selection == .you
        return index * tabWidth + (crossedTheMiddle ? Self.logSlot : 0)
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

    /// The persistent log action. A filled lime square rather than a floating
    /// circle — the system's only shape is the rectangle.
    private var logButton: some View {
        Button(action: onLog) {
            Text("+")
                .font(.custom("DMSans-Medium", fixedSize: 26))
                .foregroundStyle(Color.ink)
                .frame(width: 46, height: 38)
                .background(Color.lime)
                .frame(width: Self.logSlot, height: Space.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-log")
        .accessibilityLabel("Log a session")
    }
}
