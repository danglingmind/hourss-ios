import ActivityKit
import Foundation

/// What the Live Activity carries between the app and the Dynamic Island.
///
/// Kept deliberately small: ActivityKit budgets these payloads tightly, and every
/// field here has to survive being encoded, sent to a separate process, and
/// rendered without the app running.
struct HourssActivityAttributes: ActivityAttributes {

    /// Fixed for the life of the session.
    let activityName: String
    /// Which mark to draw. Stored as the raw value so the widget need not know how
    /// activity names map to glyphs.
    let glyphID: String
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        /// Nil while running. Set when stopped, which is what turns the expanded
        /// view into the two rating scales.
        var endedAt: Date?
        var feeling: Int?
        var performance: Int?
        var isSaved: Bool = false

        var isRunning: Bool { endedAt == nil }
    }
}
