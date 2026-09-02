import ActivityKit
import AppIntents
import Foundation

/// The buttons inside the Dynamic Island.
///
/// `LiveActivityIntent` runs in the *app's* process, not the widget's — iOS wakes
/// the app in the background to perform it. That is what lets a rating tapped from
/// the Island reach the real store instead of a copy the app would later ignore.
@available(iOS 17.0, *)
struct RateSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Rate session"
    static let isDiscoverable: Bool = false

    /// Which scale is being answered.
    @Parameter(title: "Scale")
    var scale: String

    @Parameter(title: "Score")
    var score: Int

    init() {}

    init(scale: String, score: Int) {
        self.scale = scale
        self.score = score
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityMutation.apply { state in
            // Tapping the selected score clears it, matching the app's scales.
            if scale == "feeling" {
                state.feeling = (state.feeling == score) ? nil : score
            } else {
                state.performance = (state.performance == score) ? nil : score
            }
        }
        await LiveSessionBridge.shared.rate(scale: scale, score: score)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityMutation.apply { state in
            if state.endedAt == nil { state.endedAt = Date() }
        }
        await LiveSessionBridge.shared.stop()
        return .result()
    }
}

@available(iOS 17.0, *)
struct SaveSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Save reflection"
    static let isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await LiveActivityMutation.apply { $0.isSaved = true }
        await LiveSessionBridge.shared.save()
        return .result()
    }
}

/// Updates the running Live Activity in place.
///
/// `ActivityKit.` is spelled out because the app target has its own `Activity`
/// model — a thing you can log — which shadows ActivityKit's.
enum LiveActivityMutation {
    static func apply(_ change: @Sendable (inout HourssActivityAttributes.ContentState) -> Void) async {
        for activity in ActivityKit.Activity<HourssActivityAttributes>.activities {
            var state = activity.content.state
            change(&state)
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}

/// Where the intents land.
///
/// The intents are compiled into both targets but only ever *performed* in the
/// app, so the app installs the real handler at launch. In the widget process the
/// handlers stay nil and nothing happens — which is correct, not a failure.
actor LiveSessionBridge {
    static let shared = LiveSessionBridge()

    private var onRate: (@Sendable (String, Int) async -> Void)?
    private var onStop: (@Sendable () async -> Void)?
    private var onSave: (@Sendable () async -> Void)?

    func install(
        rate: @escaping @Sendable (String, Int) async -> Void,
        stop: @escaping @Sendable () async -> Void,
        save: @escaping @Sendable () async -> Void
    ) {
        onRate = rate
        onStop = stop
        onSave = save
    }

    func rate(scale: String, score: Int) async { await onRate?(scale, score) }
    func stop() async { await onStop?() }
    func save() async { await onSave?() }
}
