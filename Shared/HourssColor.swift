import SwiftUI

/// Direct port of the `color` block in `Hourss-docs/hourss-ui-system.json`.
///
/// Three colors used by the landing page were never tokenized (`drainingFill`,
/// `restorativeFill`, `tertiaryOnCanvas`); they are folded in here so the palette
/// is complete. `mutedOnDark` fixes the token file's `#AEBcb2` casing.
extension Color {
    // Canvas surface
    static let canvas = Color(hex: 0xF4F0E8)
    static let ink = Color(hex: 0x17211E)
    static let muted = Color(hex: 0x61706A)
    static let rule = Color(hex: 0xB6B5AB)
    static let tertiaryOnCanvas = Color(hex: 0x69736E)

    // Forest surface
    static let forest = Color(hex: 0x1C302A)
    static let forestRaised = Color(hex: 0x284139)
    static let forestRule = Color(hex: 0x506158)
    static let paperOnDark = Color(hex: 0xECF0E6)
    static let mutedOnDark = Color(hex: 0xAEBCB2)
    static let subtleOnDark = Color(hex: 0x8B9C91)

    // Accents
    static let lime = Color(hex: 0xBBD96C)
    static let orange = Color(hex: 0xE65837)
    static let limeText = Color(hex: 0x526237)

    // Energy fills
    static let drainingFill = Color(hex: 0xE66645)
    static let restorativeFill = Color(hex: 0x9BC4AB)

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
