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
/// hairline rule, and the centred `+` that the spec makes the primary log action.
struct EditorialTabBar: View {
    @Binding var selection: Tab
    let onLog: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .padding(.horizontal, Space.xs)
        }
        .background(Color.canvas)
        // Five fixed slots cannot grow indefinitely: past this size the labels
        // truncate to "PATT…". Content still scales all the way up — only the
        // chrome is capped, and VoiceOver reads the full name regardless.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
                .frame(width: 60, height: Space.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-log")
        .accessibilityLabel("Log a session")
    }
}
