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

/// A 1pt rule. Hierarchy in this system comes from lines, not surfaces, so this
/// is doing the job a card border would do elsewhere.
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
