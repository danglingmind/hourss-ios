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
                rate: { [weak self] scale, score in await self?.rate(scale: scale, score: score) },
                stop: { [weak self] in await self?.stopFromIsland() },
                save: { [weak self] in await self?.saveFromIsland() }
            )
        }
    }

    /// Reattaches to a live activity that still has a running session behind it,
    /// and dismisses any that do not.
    private func reconcileOrphans(store: HourssStore) async {
        let runningStart = store.runningSession?.startAt
        activity = ActivityKit.Activity<HourssActivityAttributes>.activities.first { candidate in
            guard candidate.content.state.isRunning, let runningStart else { return false }
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

    /// Moves the Island into its stopped state, where the two scales appear.
    func markStopped(at date: Date) {
        update { state in state.endedAt = date }
    }

    /// Ends everything this app has running, including activities left by an
    /// earlier launch that `activity` knows nothing about.
    func endAll() {
        activity = nil
        Task { await Self.endActivities(except: nil) }
    }

    /// Ends the Live Activity. Called once the reflection is saved, or when the
    /// session goes away.
    func end() {
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate)
        }
        self.activity = nil
    }

    private func update(_ change: (inout HourssActivityAttributes.ContentState) -> Void) {
        guard let activity else { return }
        var state = activity.content.state
        change(&state)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    // MARK: - Coming back from the Island

    private func rate(scale: String, score: Int) {
        var latest: HourssActivityAttributes.ContentState?
        update { state in
            // Tapping the selected score clears it, matching the app's scales —
            // a rating given by accident can be taken back.
            if scale == "feeling" {
                state.feeling = (state.feeling == score) ? nil : score
            } else {
                state.performance = (state.performance == score) ? nil : score
            }
            latest = state
        }

        // There is no Save step in the Island — the spec has a tapped score save
        // immediately — so write it through as it is tapped.
        guard let latest, let store,
              let sessionId = store.pendingReflectionSessionId ?? store.sessions.last?.id
        else { return }
        store.saveReflection(
            sessionId: sessionId,
            feeling: latest.feeling,
            performance: latest.performance,
            note: nil
        )

        // Dismissal is the intent's job (`LiveActivityMutation.endIfBothAnswered`).
        // Doing it here as well would only work when the app happened to be
        // running, which is exactly the case that does not need help.
    }

    private func stopFromIsland() {
        guard let store, let running = store.runningSession else { return }
        store.stopSession(running.id)
    }

    private func saveFromIsland() {
        guard let store, let activity else { return }
        let state = activity.content.state
        guard let sessionId = store.pendingReflectionSessionId ?? store.sessions.last?.id else { return }

        store.saveReflection(
            sessionId: sessionId,
            feeling: state.feeling,
            performance: state.performance,
            note: nil
        )
        update { $0.isSaved = true }
        // Leave the confirmation up briefly so the tap has a visible result.
        Task {
            try? await Task.sleep(for: .seconds(2))
            end()
        }
    }
}
