import SwiftUI

/// "HOURSS" with the separated orange dot at the upper right.
struct Wordmark: View {
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Text("HOURSS").textStyle(.wordmark)
            Text("●")
                .font(.custom("DMSans-Bold", fixedSize: 7))
                .foregroundStyle(.orange)
                .offset(y: 1)
        }
        .accessibilityElement()
        .accessibilityLabel("Hourss")
    }
}

/// 11pt mono, uppercase, +0.05em. The system's only label idiom.
struct Eyebrow: View {
    let text: String
    var color: Color?
    @Environment(\.surface) private var surface

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .textStyle(.eyebrow)
            .foregroundStyle(color ?? surface.secondary)
    }
}

/// A 2pt rule in the foreground colour, for a break between sections.
///
/// **Why a second weight exists.** `HRule` was doing two different jobs at one
/// weight across ninety call sites: separating a heading from the thing it heads,
/// and separating two rows of a list. Both read identically, so a screen arrived
/// as one undifferentiated stack of things with no way to tell which lines were
/// structure and which were punctuation. The eye had nothing to rank.
///
/// Two points and full-strength ink rather than the rule grey, because the
/// difference has to survive a glance — 1pt against 1.5pt in the same colour is a
/// distinction only a designer with a loupe would find, and the whole point is
/// that nobody should have to look for it.
///
/// **Use it sparingly.** A screen with six section rules has six sections and no
/// hierarchy again. If two blocks belong to the same idea, `HRule` between them
/// is the honest mark.
struct SectionRule: View {
    @Environment(\.surface) private var surface

    var body: some View {
        Rectangle()
            .fill(surface.foreground)
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

/// A 1pt rule. Hierarchy in this system comes from lines, not surfaces, so this
/// is doing the job a card border would do elsewhere.
///
/// The lighter of the two weights, and the default: this separates items that
/// belong to the same idea. `SectionRule` separates the ideas.
struct HRule: View {
    var color: Color?
    @Environment(\.surface) private var surface

    init(color: Color? = nil) { self.color = color }

    var body: some View {
        Rectangle()
            .fill(color ?? surface.ruleColor)
            .frame(height: 1)
    }
}

/// Bold text plus an oversized orange arrow. The token file explicitly bans
/// filled capsules here — the shift on press is the entire affordance.
/// One filled action per screen, and never a second.
///
/// **This overrules a standing rule, deliberately.** `DirectionalLink`'s note
/// below records that the token file bans filled capsules and that the press
/// shift is the entire affordance. That held while every action on a screen was
/// equal; it stopped holding once screens had a single obvious next step buried
/// among links of identical weight. Starting a session, stopping one and saving
/// a rating were all bold 14pt text with a small arrow, so nothing on the screen
/// looked more tappable than the prose beside it.
///
/// **Not a capsule.** A full-width rectangle, because the ban on rounded
/// geometry is a separate rule and is not the one being overruled — the only
/// curve in this app is `ComparisonArc`'s stroke caps.
///
/// **Ground-aware.** Forest on canvas, lime on forest: a forest-filled block on
/// the running-session panel would have been a dark rectangle on a dark panel.
/// The fill is always the surface's opposite rather than a fixed colour.
///
/// **One per screen is the whole discipline.** Two filled blocks are two primary
/// actions, which is no primary action and a louder screen than before. If a
/// second one ever appears, this component is not the thing that failed.
struct PrimaryAction: View {
    let title: String
    var arrow: String = "→"
    let action: () -> Void

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    /// The fill, and the text that survives on it.
    private var fill: Color { surface == .canvas ? .forest : .lime }
    private var ink: Color { surface == .canvas ? .paperOnDark : .ink }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Text(title).textStyle(.action)
                Text(arrow).font(.custom("DMSans-Bold", fixedSize: 18))
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: Space.tapTarget + 6)
            .background(fill)
            .opacity(isEnabled ? (pressed ? 0.82 : 1) : 0.35)
            // No shift. A block that moves under the thumb reads as dragging
            // rather than as pressing; the dimming is what a filled surface has
            // instead, and it is the same gesture in the vocabulary a fill owns.
            .animation(Motion.animation(reduced: reduceMotion, duration: Motion.fast), value: pressed)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
    }
}

struct DirectionalLink: View {
    let title: String
    var arrow: String = "↘"
    var color: Color?
    let action: () -> Void

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).textStyle(.action)
                Text(arrow)
                    .font(.custom("DMSans-Bold", fixedSize: 18))
                    .foregroundStyle(.orange)
            }
            .foregroundStyle(color ?? surface.foreground)
            .opacity(isEnabled ? 1 : 0.35)
            .offset(x: pressed ? 3 : 0)
            .animation(Motion.animation(reduced: reduceMotion, duration: Motion.fast), value: pressed)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if isEnabled { pressed = true } }
                .onEnded { _ in pressed = false }
        )
    }
}

/// A selection dot.
///
/// This was two glyphs — "●" and "○" — swapped in place, and they are different
/// sizes in the typeface, so selecting one never actually filled the ring it
/// replaced. One circle that fills is what the interaction was always describing.
struct SelectionDot: View {
    let isSelected: Bool
    var size: CGFloat = 15

    @Environment(\.surface) private var surface

    var body: some View {
        Circle()
            .fill(isSelected ? Color.orange : .clear)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.orange : surface.ruleColor, lineWidth: 1.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Display type needs *negative* leading (line-height 0.91 and 0.90), which
/// SwiftUI's `lineSpacing` cannot express — it clamps at zero. The landing page
/// already hard-breaks these headlines, so each line becomes its own `Text` in a
/// `VStack`, where negative spacing is legal.
struct DisplayHeadline: View {
    let lines: [Text]
    var style: TypeStyle = .display
    var alignment: HorizontalAlignment = .leading

    init(_ lines: [Text], style: TypeStyle = .display, alignment: HorizontalAlignment = .leading) {
        self.lines = lines
        self.style = style
        self.alignment = alignment
    }

    /// Convenience for headlines with no inline emphasis.
    init(_ plain: [String], style: TypeStyle = .display, alignment: HorizontalAlignment = .leading) {
        self.init(plain.map { Text($0).styled(style) }, style: style, alignment: alignment)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: style.stackedLineSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                line.fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
