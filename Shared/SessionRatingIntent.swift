import ActivityKit
import AppIntents
import Foundation

/// The one button in the Dynamic Island.
///
/// `openAppWhenRun` is the point of the whole simplification: stopping brings the
/// app forward, where the reflection sheet is already waiting. Rating from a
/// lock-screen button was possible but never good — five tap targets at 30pt, no
/// room for a note, and a second question that could not be reached without
/// re-opening the Island. The app does that job properly.
@available(iOS 17.0, *)
struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let isDiscoverable: Bool = false
    static let openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveSessionBridge.shared.stop()
        await LiveActivityMutation.endAll()
        return .result()
    }
}

/// Ends the running Live Activity.
///
/// `ActivityKit.` is spelled out because the app target has its own `Activity`
/// model — a thing you can log — which shadows ActivityKit's.
enum LiveActivityMutation {
    static func endAll() async {
        for activity in ActivityKit.Activity<HourssActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// Where the intent lands.
///
/// Compiled into both targets but only ever performed in the app, which installs
/// the handler at launch. In the widget process it stays nil and nothing happens —
/// which is correct, not a failure.
actor LiveSessionBridge {
    static let shared = LiveSessionBridge()

    private var onStop: (@Sendable () async -> Void)?

    func install(stop: @escaping @Sendable () async -> Void) {
        onStop = stop
    }

    func stop() async { await onStop?() }
}
