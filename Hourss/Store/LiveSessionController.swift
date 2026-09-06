import ActivityKit
import Foundation
import Observation

/// Runs the Live Activity for the session in progress.
///
/// Note the `ActivityKit.` qualifications: Hourss has its own `Activity` model
/// (a thing you can log), which shadows ActivityKit's inside this target.
///
/// Everything the Island shows comes from here, and everything it *does* comes
/// back through `LiveSessionBridge` — the intents behind the Island's buttons run
/// in this process, so a rating tapped on the lock screen lands in the same store
/// the app is showing, not a copy.
@Observable
@MainActor
final class LiveSessionController {

    private var activity: ActivityKit.Activity<HourssActivityAttributes>?
    private weak var store: HourssStore?

    /// Why the Island is not showing, when it is not showing. `Activity.request`
    /// used to be wrapped in `try?`, which meant a refusal on device looked
    /// identical to everything working — nothing appeared and nothing said why.
    private(set) var unavailableReason: String?

    /// Live Activities are off in a simulator's Settings by default and unavailable
    /// entirely on some devices; nothing here should fail loudly when that is so.
    var isSupported: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func attach(to store: HourssStore) {
        self.store = store
        Task {
            // Live Activities outlive the app. A session stopped in a previous run
            // leaves one behind, frozen at its final elapsed time — which looks
            // exactly like a timer that has stopped counting. Adopt the one that
            // matches a session still running, and clear the rest.
            await reconcileOrphans(store: store)
            await LiveSessionBridge.shared.install(
                stop: { [weak self] in await self?.stopFromIsland() }
            )
        }
    }

    /// Reattaches to a live activity that still has a running session behind it,
    /// and dismisses any that do not.
    private func reconcileOrphans(store: HourssStore) async {
        let runningStart = store.runningSession?.startAt
        activity = ActivityKit.Activity<HourssActivityAttributes>.activities.first { candidate in
            guard candidate.content.state.endedAt == nil, let runningStart else { return false }
            return abs(runningStart.timeIntervalSince(candidate.attributes.startedAt)) < 1
        }
        await Self.endActivities(except: activity?.id)
    }

    /// Nonisolated on purpose: `Activity.end` is nonisolated, and a handle picked
    /// up inside a `@MainActor` method would have to be sent across an actor
    /// boundary, which Swift 6 refuses. Enumerating here keeps them off the main
    /// actor entirely.
    nonisolated private static func endActivities(except keepID: String?) async {
        for existing in ActivityKit.Activity<HourssActivityAttributes>.activities where existing.id != keepID {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Lifecycle

    func start(session: Session, activityName: String) {
        guard isSupported else {
            unavailableReason = "Live Activities are turned off for Hourss in Settings."
            return
        }
        unavailableReason = nil

        let attributes = HourssActivityAttributes(
            activityName: activityName,
            glyphID: ActivityGlyph.Kind.forActivity(named: activityName).rawValue,
            startedAt: session.startAt
        )

        // Request first, then clear everything *else*. Tearing down beforehand
        // races: the teardown is async, so it can land after the new request and
        // dismiss the activity that was just created — which shows up as no Island
        // at all rather than as an error.
        let started: ActivityKit.Activity<HourssActivityAttributes>?
        do {
            started = try ActivityKit.Activity.request(
                attributes: attributes,
                content: .init(state: .init(), staleDate: nil)
            )
        } catch {
            started = nil
            unavailableReason = "Couldn't start the Live Activity: \(error.localizedDescription)"
            print("[Hourss] Live Activity request failed: \(error)")
        }
        activity = started
        Task { await Self.endActivities(except: started?.id) }
    }

    /// Ends everything this app has running, including activities left by an
    /// earlier launch that `activity` knows nothing about.
    func endAll() {
        activity = nil
        Task { await Self.endActivities(except: nil) }
    }

    private func stopFromIsland() {
        guard let store, let running = store.runningSession else { return }
        store.stopSession(running.id)
    }
}
