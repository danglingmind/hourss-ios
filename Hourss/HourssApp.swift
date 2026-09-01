import SwiftUI
import UIKit

@main
struct HourssApp: App {
    @State private var store = HourssStore()

    init() { FontAudit.run() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(.orange)
        }
    }
}

/// Bundled fonts fail *silently*: a wrong PostScript name falls back to the system
/// font, and the app still looks plausible while being entirely off-system. This
/// asserts the three families registered, so the failure is loud in debug.
enum FontAudit {
    static func run() {
        #if DEBUG
        let required = [
            "DMSans-Regular", "DMSans-Medium", "DMSans-Bold",
            "DMMono-Regular", "DMMono-Medium",
            "InstrumentSerif-Regular", "InstrumentSerif-Italic",
        ]
        let missing = required.filter { UIFont(name: $0, size: 12) == nil }
        if missing.isEmpty {
            print("[Hourss] fonts ok — \(required.count) faces registered")
        } else {
            assertionFailure("[Hourss] missing bundled fonts: \(missing.joined(separator: ", "))")
        }
        #endif
    }
}
