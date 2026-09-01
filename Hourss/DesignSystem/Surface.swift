import SwiftUI

/// The palette resolves into three surface modes. Screens declare their mode and
/// read text, rule and secondary colors from it, so nothing hardcodes a pairing
/// the design system did not sanction.
enum Surface {
    case canvas
    case forest
    case lime

    var background: Color {
        switch self {
        case .canvas: .canvas
        case .forest: .forest
        case .lime: .lime
        }
    }

    /// Primary copy. Token rule: ink on canvas, paperOnDark on forest, ink on lime.
    var foreground: Color {
        switch self {
        case .canvas: .ink
        case .forest: .paperOnDark
        case .lime: .ink
        }
    }

    var secondary: Color {
        switch self {
        case .canvas: .muted
        case .forest: .mutedOnDark
        case .lime: .limeText
        }
    }

    var tertiary: Color {
        switch self {
        case .canvas: .tertiaryOnCanvas
        case .forest: .subtleOnDark
        case .lime: .limeText
        }
    }

    var ruleColor: Color {
        switch self {
        case .canvas: .rule
        case .forest: .forestRule
        case .lime: .ink.opacity(0.25)
        }
    }

    /// Track behind an energy bar.
    var track: Color {
        switch self {
        case .canvas: .ink.opacity(0.08)
        case .forest: .forestRaised
        case .lime: .ink.opacity(0.12)
        }
    }
}

private struct SurfaceKey: EnvironmentKey {
    static let defaultValue: Surface = .canvas
}

extension EnvironmentValues {
    var surface: Surface {
        get { self[SurfaceKey.self] }
        set { self[SurfaceKey.self] = newValue }
    }
}

extension View {
    /// Paints the surface edge-to-edge and publishes it to descendants.
    func surface(_ surface: Surface) -> some View {
        self
            .environment(\.surface, surface)
            .foregroundStyle(surface.foreground)
            .background(surface.background.ignoresSafeArea())
    }
}
