import SwiftUI
import UIKit

@main
struct HourssApp: App {
    @State private var store = HourssStore()
    @State private var health = HealthService()
    @State private var live = LiveSessionController()
    @State private var narration = NarrationStore()
    @State private var account = AccountService()
    /// The shared instance rather than a fresh one: iOS already holds it as the
    /// notification delegate, and a second object would answer a tap the first one
    /// received.
    @State private var notifications = NotificationService.shared

    /// The notification delegate is registered here, not in a view.
    ///
    /// A tap that launches Hourss from cold is delivered to whatever delegate
    /// exists at launch. Waiting for a view's `task` to run would mean the one
    /// case this feature exists for — the app was not open — is the case where the
    /// tap goes nowhere.
    init() {
        FontAudit.run()
        NotificationService.shared.startReceiving()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(health)
                .environment(narration)
                .environment(account)
                .environment(notifications)
                .tint(.orange)
                .task {
                    store.live = live
                    live.attach(to: store)
                    // Asks Apple whether the stored credential is still good, and
                    // starts listening for it being withdrawn while the app is
                    // open. Until it answers, the root shows neither the record
                    // nor the gate — see `AccountCheckView`.
                    await account.start()

                    // Health, on every launch rather than only when somebody
                    // visits the connection screen. The importer is what makes
                    // this matter: last night's sleep and this morning's run are
                    // already recorded, and reading them here is the difference
                    // between a Journal that fills itself and one that waits.
                    // Before the check below, and only meaningful once: people
                    // who connected Health before Hourss recorded connections
                    // would otherwise read as disconnected forever.
                    // Reminders are repeating alarms iOS already holds, so this
                    // schedules nothing new in the ordinary case. It is here to
                    // heal: permission revoked in Settings, a frequency changed on
                    // a launch that was killed before it wrote, requests dropped.
                    await notifications.apply(store.profile)

                    await health.restoreConnectionIfNeeded()

                    if health.isConnected {
                        await health.refresh()
                        await applyHealthRead(from: health, to: store)
                    }
                }
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
