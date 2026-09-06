import ActivityKit
import Foundation

/// What the Live Activity carries between the app and the Dynamic Island.
///
/// Deliberately almost empty. The Island now exists only while a session is
/// running — stopping ends it and hands off to the app for the reflection — so
/// there is no rating, no stopped state, and nothing to keep in sync.
struct HourssActivityAttributes: ActivityAttributes {

    /// Fixed for the life of the session.
    let activityName: String
    /// Which mark to draw. Stored as the raw value so the widget need not know how
    /// activity names map to glyphs.
    let glyphID: String
    let startedAt: Date

    struct ContentState: Codable, Hashable {
        /// Set only in the instant between stopping and the activity ending, so
        /// the timer freezes rather than ticking on during the handoff.
        var endedAt: Date?
    }
}
