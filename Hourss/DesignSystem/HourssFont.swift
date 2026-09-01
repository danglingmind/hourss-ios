import SwiftUI
import UIKit

/// Port of the `typography` block in `hourss-ui-system.json`.
///
/// Two porting notes worth keeping in mind when editing this file:
///
/// 1. The design system's `700px` mobile breakpoint sits below every iPhone width,
///    so the *mobile* column of `hourssapp/src/style.css` is the default here.
///    Where a size differs from the desktop token, the token value is noted inline.
/// 2. `clamp()` display sizes resolve to their floor on iPhone — `7.7vw` of a 390pt
///    screen is ~30pt, well under the 55px floor — so `display` is a flat 55pt.
enum FontFamily {
    case sans, mono, serif

    func postScriptName(weight: Int, italic: Bool = false) -> String {
        switch self {
        case .sans:
            switch weight {
            case ...400: "DMSans-Regular"
            case 401...599: "DMSans-Medium"
            default: "DMSans-Bold"
            }
        case .mono:
            weight >= 500 ? "DMMono-Medium" : "DMMono-Regular"
        case .serif:
            italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        }
    }
}

struct TypeStyle {
    var family: FontFamily
    var weight: Int
    var size: CGFloat
    /// Multiplier of the font size, matching the CSS `line-height` values.
    var lineHeight: CGFloat
    /// Expressed in `em`, matching the CSS `letter-spacing` values.
    var trackingEm: CGFloat
    var italic: Bool = false
    var uppercase: Bool = false
    /// Dynamic Type ramp. Display sizes opt out — they are already enormous and
    /// scaling them further breaks the editorial line breaks.
    var relativeTo: Font.TextStyle?

    var postScriptName: String { family.postScriptName(weight: weight, italic: italic) }

    var font: Font {
        if let relativeTo {
            .custom(postScriptName, size: size, relativeTo: relativeTo)
        } else {
            .custom(postScriptName, fixedSize: size)
        }
    }

    var tracking: CGFloat { size * trackingEm }

    /// The font's own line height, which SwiftUI's `lineSpacing` adds *on top of*.
    var naturalLineHeight: CGFloat {
        UIFont(name: postScriptName, size: size)?.lineHeight ?? size * 1.2
    }

    /// Space to add between wrapped lines to reach `lineHeight`. Clamped at zero:
    /// SwiftUI cannot express negative leading on a wrapping `Text`.
    var lineSpacing: CGFloat { max(0, size * lineHeight - naturalLineHeight) }

    /// The true delta, which *can* be negative. `DisplayHeadline` uses this to set
    /// `VStack` spacing, where negative values are legal.
    var stackedLineSpacing: CGFloat { size * lineHeight - naturalLineHeight }
}

extension TypeStyle {
    static let display = TypeStyle(family: .sans, weight: 500, size: 55, lineHeight: 0.91, trackingEm: -0.065, relativeTo: nil)
    static let sectionTitle = TypeStyle(family: .sans, weight: 500, size: 40, lineHeight: 0.90, trackingEm: -0.065, relativeTo: nil)
    /// Desktop token is 27px; the mobile override is 23px.
    static let sectionLead = TypeStyle(family: .sans, weight: 400, size: 23, lineHeight: 1.08, trackingEm: -0.04, relativeTo: .title3)
    static let body = TypeStyle(family: .sans, weight: 400, size: 16, lineHeight: 1.4, trackingEm: -0.015, relativeTo: .body)
    static let bodyLarge = TypeStyle(family: .sans, weight: 400, size: 18, lineHeight: 1.35, trackingEm: -0.025, relativeTo: .body)
    static let eyebrow = TypeStyle(family: .mono, weight: 500, size: 11, lineHeight: 1.2, trackingEm: 0.05, uppercase: true, relativeTo: .caption)
    static let label = TypeStyle(family: .mono, weight: 400, size: 11, lineHeight: 1.0, trackingEm: 0, relativeTo: .caption)
    static let action = TypeStyle(family: .sans, weight: 700, size: 14, lineHeight: 1.2, trackingEm: 0, relativeTo: .subheadline)

    /// Italic serif, used sparingly inside a larger sans sentence.
    /// Size is contextual — it should match the sans text it sits within.
    static func emphasis(_ size: CGFloat) -> TypeStyle {
        TypeStyle(family: .serif, weight: 400, size: size, lineHeight: 1.0, trackingEm: -0.045, italic: true, relativeTo: nil)
    }

    // Derived styles used by more than one screen.
    static let wordmark = TypeStyle(family: .sans, weight: 700, size: 17, lineHeight: 1.0, trackingEm: -0.07, relativeTo: nil)
    static let stepName = TypeStyle(family: .sans, weight: 500, size: 26, lineHeight: 1.0, trackingEm: -0.045, relativeTo: .title2)
    /// The large `/100` numeral in an energy reading. Serif, upright, not italic.
    static let readingScore = TypeStyle(family: .serif, weight: 400, size: 58, lineHeight: 0.9, trackingEm: -0.06, relativeTo: nil)
    static let dayNumeral = TypeStyle(family: .sans, weight: 500, size: 34, lineHeight: 0.95, trackingEm: -0.055, relativeTo: nil)
}

extension View {
    func textStyle(_ style: TypeStyle) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension Text {
    /// Applies a style to a `Text` while keeping it concatenable, which is how
    /// mixed sans / italic-serif sentences are built.
    func styled(_ style: TypeStyle) -> Text {
        self.font(style.font).tracking(style.tracking)
    }

    /// Joins two styled runs into one line. `Text + Text` is deprecated as of
    /// iOS 26; interpolation is the replacement and preserves each run's own font.
    func then(_ other: Text) -> Text {
        Text("\(self)\(other)")
    }
}
