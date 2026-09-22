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
    /// Throttled catch-up for sessions that ended while the app was away.
    @State private var catchUp = PhysiologyCatchUp()

    /// Watched only for the return to `.active`. See `catchUp` below for what that
    /// does and, far more often, does not do.
    @Environment(\.scenePhase) private var scenePhase

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
                    // Stamped before the first await, so the scene going active a
                    // moment later does not send the catch-up to HealthKit for the
                    // sixty days this task is already reading.
                    catchUp.markRead()
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
                // The one thing a cold launch cannot do: score a session that
                // ended after it.
                //
                // A session logged at 10:30 is scored against whatever feed was
                // read when the app opened at 08:00, which contains no heart rate
                // from 10:30 — so it gets nothing, and until somebody force-quits
                // and reopens, it keeps getting nothing. Nothing else in the app
                // observes the scene, and nothing anywhere asks HealthKit a second
                // question in a session's life; this is the whole of the fix.
                //
                // `.active` rather than a background task or an observer query:
                // the residual is only ever looked at inside the app, so reading
                // it on the way in is both the earliest moment it can matter and
                // the last moment it is free.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await catchUp.run(health: health, store: store) }
                }
        }
    }
}

/// Re-reads Health when the app comes forward, and — almost always — does not.
///
/// The read this guards is not small: sixty days of heart rate is tens of
/// thousands of samples, and `applyPhysiology(feed:)` refits the whole movement
/// curve on the main actor. That is a launch-time cost, and moving it onto every
/// return from the app switcher would be paying a launch for every glance at a
/// notification. Three gates stand in front of it, in increasing order of what
/// they cost to ask:
///
/// 1. **The existing Health gates**, unchanged and not bypassed: not connected,
///    access lost, or `.recovery` deselected each mean the read would return an
///    empty feed anyway, and `accessLost` in particular must keep its own route
///    back — `ReconnectHealthView` asks, this does not ask on its behalf.
/// 2. **Is anything actually waiting?** With readings frozen, the steady state is
///    that every eligible session already has one and there is nothing to compute.
///    This is a scan of an array in memory, and it is the answer on the
///    overwhelming majority of foregrounds, so the common case costs nothing at
///    all.
/// 3. **The throttle**, for the case where something *is* waiting and cannot be
///    scored — a session in an exercise lead-in, or one the watch has not synced
///    yet. Without it, that session is permanently "awaiting" and every app switch
///    pays for the full read to rediscover that it still cannot be scored.
@MainActor
@Observable
final class PhysiologyCatchUp {

    /// Fifteen minutes.
    ///
    /// Bounded below by what a person does: switching between Hourss and a message
    /// happens several times a minute, and anything under a minute or two would
    /// re-read for every one of them. Bounded above by what the watch does: heart
    /// rate reaches the phone's HealthKit in batches, minutes behind the wrist, so
    /// the first read after a session ends is the one most likely to find too few
    /// samples — and the interval is how long that session then waits for its
    /// second chance. Fifteen minutes is four reads an hour at the very worst, and
    /// a session that ends mid-morning is scored well before anybody looks at their
    /// day.
    static let minimumInterval: TimeInterval = 15 * 60

    /// Why a foreground did or did not go to HealthKit. Returned rather than
    /// logged, so a test can assert the skip rather than the absence of a symptom.
    enum Outcome: Equatable {
        case notConnected
        case accessLost
        case recoveryNotSelected
        /// Every eligible session already carries a frozen reading. The ordinary
        /// answer, and the cheap one.
        case nothingAwaiting
        case throttled
        case alreadyReading
        case read
    }

    private(set) var lastReadAt: Date?
    private var isReading = false

    /// Records that a read has just happened elsewhere — the cold launch — so the
    /// throttle counts from it.
    func markRead(at now: Date = Date()) { lastReadAt = now }

    /// The whole policy, as a function of values.
    ///
    /// Separated from the read because a test that has to connect HealthKit to
    /// find out whether the throttle holds is a test that will not be written, and
    /// the gates are the part that has to be right. Every branch here is reachable
    /// from a unit test with no HealthKit, no simulator permission sheet, and no
    /// UserDefaults left flipped for whatever runs next.
    static func decision(
        isConnected: Bool,
        accessLost: Bool,
        readsRecovery: Bool,
        hasAwaitingSessions: Bool,
        lastReadAt: Date?,
        isReading: Bool,
        now: Date
    ) -> Outcome {
        guard isConnected else { return .notConnected }
        guard !accessLost else { return .accessLost }
        guard readsRecovery else { return .recoveryNotSelected }
        guard hasAwaitingSessions else { return .nothingAwaiting }
        if let lastReadAt, now.timeIntervalSince(lastReadAt) < minimumInterval { return .throttled }
        // Two activations while the first read is still in flight is an ordinary
        // thing for a scene to do, and both would otherwise start their own sixty
        // days of HealthKit.
        guard !isReading else { return .alreadyReading }
        return .read
    }

    @discardableResult
    func run(health: HealthService, store: HourssStore, now: Date = Date()) async -> Outcome {
        let outcome = Self.decision(
            isConnected: health.isConnected,
            accessLost: health.accessLost,
            readsRecovery: health.selectedGroups.contains(.recovery),
            hasAwaitingSessions: !store.sessionsAwaitingPhysiology(now: now).isEmpty,
            lastReadAt: lastReadAt,
            isReading: isReading,
            now: now
        )
        guard outcome == .read else { return outcome }

        isReading = true
        lastReadAt = now
        defer { isReading = false }

        // The same pair the cold launch runs, in the same order and through the
        // same function: daily context, physiology and the importer are applied
        // together or they drift, which `applyHealthRead` exists to prevent.
        await health.refresh()
        await applyHealthRead(from: health, to: store)
        return .read
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
