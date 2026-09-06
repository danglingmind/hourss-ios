import SwiftUI

/// Feeling is recorded on a 1–5 scale, Draining → Energizing.
///
/// The spec is emphatic that absence of a rating means *unknown*, never 3, so
/// nothing in this type imputes a value. Every score here is an `Int` the user
/// actually chose; anywhere a rating may be missing, the model uses `Int?`.
enum Feeling {
    static func label(forRating rating: Int) -> String {
        switch rating {
        case 1: "Draining"
        case 2: "Depleting"
        case 3: "Neutral"
        case 4: "Steady"
        default: "Energizing"
        }
    }

    /// 1–5 rating expressed on the 0–100 scale the readings display.
    static func score(forRating rating: Int) -> Int { rating * 20 - 10 }

    static func fillColor(forRating rating: Int) -> Color {
        switch rating {
        case 1, 2: .drainingFill
        case 3: .restorativeFill
        default: .lime
        }
    }

    static func fillColor(forScore score: Int) -> Color {
        switch score {
        case ..<40: .drainingFill
        case 40..<60: .restorativeFill
        default: .lime
        }
    }

    static func describe(score: Int) -> String {
        switch score {
        case ..<40: "draining"
        case 40..<60: "mixed"
        case 60..<80: "steady"
        default: "energizing"
        }
    }
}

/// Where a session came from. Health import is out of scope for the shell but
/// stays in the model so provenance is never ambiguous.
enum SessionSource: String, Codable {
    case manual
    case health
}

/// Time-of-day buckets used by the pattern engine.
enum TimeBucket: String, CaseIterable, Identifiable {
    case morning, midday, afternoon, evening

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "Morning"
        case .midday: "Midday"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    /// morning 05–11 · midday 11–14 · afternoon 14–18 · evening 18–05
    static func bucket(forHour hour: Int) -> TimeBucket {
        switch hour {
        case 5..<11: .morning
        case 11..<14: .midday
        case 14..<18: .afternoon
        default: .evening
        }
    }
}

enum DurationBucket: String, CaseIterable, Identifiable {
    case short, medium, long, extended

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: "Under 30 min"
        case .medium: "30–89 min"
        case .long: "90–179 min"
        case .extended: "180 min or more"
        }
    }

    static func bucket(forMinutes minutes: Int) -> DurationBucket {
        switch minutes {
        case ..<30: .short
        case 30..<90: .medium
        case 90..<180: .long
        default: .extended
        }
    }
}

/// What someone wants to improve, in their own order.
///
/// Ordered, not just selected — the position carries meaning, so the engine can
/// weight what it surfaces rather than only what it computes. Each case maps to
/// signals Hourss can actually observe; a priority the app has no way to see would
/// be a promise it cannot keep.
enum Priority: String, CaseIterable, Identifiable, Codable {
    case focus, energy, sleep, movement, calm, balance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .energy: "Energy"
        case .sleep: "Sleep"
        case .movement: "Movement"
        case .calm: "Calm"
        case .balance: "Balance"
        }
    }

    /// What Hourss watches for this — kept concrete so the choice is informed.
    var basis: String {
        switch self {
        case .focus: "When deep work holds up"
        case .energy: "What gives energy back"
        case .sleep: "How mornings follow nights"
        case .movement: "What moving changes"
        case .calm: "What quiet time sits next to"
        case .balance: "Workdays against the rest"
        }
    }

    /// Observation types this priority cares about. Used to weight the feed, so a
    /// stated priority changes what surfaces first rather than only being stored.
    var insightTypes: Set<InsightType> {
        switch self {
        case .focus: [.bestTimeWindow, .durationSweetSpot, .fragmentation]
        case .energy: [.activityEnergizer, .activityDrain, .performanceFeelingSplit]
        case .sleep: [.sleepContext]
        case .movement: [.bodyContext]
        case .calm: [.bodyContext, .emergingChange]
        case .balance: [.workdayContrast, .drainingTimeWindow]
        }
    }
}

enum InsightStatus: String, Codable {
    case candidate, visible, saved, hidden, expired
}

/// The ten observation types in V1.
enum InsightType: String, Codable {
    case bestTimeWindow, drainingTimeWindow, activityEnergizer, activityDrain
    case performanceFeelingSplit, durationSweetSpot, fragmentation
    case workdayContrast, sleepContext, emergingChange
    /// Beyond the PRD's ten: the same association shape as sleepContext, over the
    /// other body signals.
    case bodyContext

    var group: String {
        switch self {
        case .bestTimeWindow, .drainingTimeWindow: "Timing"
        case .activityEnergizer, .activityDrain, .durationSweetSpot: "Activities"
        case .performanceFeelingSplit, .fragmentation, .workdayContrast, .sleepContext, .emergingChange: "Energy"
        case .bodyContext: "Body"
        }
    }
}

/// Confidence gates the language an observation is allowed to use. Anything below
/// 50 is internal and never surfaces.
enum Confidence {
    case strong, emerging, watching, internalOnly

    static func band(_ value: Int) -> Confidence {
        switch value {
        case 80...: .strong
        case 65..<80: .emerging
        case 50..<65: .watching
        default: .internalOnly
        }
    }

    var label: String {
        switch self {
        case .strong: "Strong pattern"
        case .emerging: "Emerging pattern"
        case .watching: "Still watching"
        case .internalOnly: "Not enough yet"
        }
    }
}

enum InsightFeedback: String, Codable {
    case resonated, notMe, hide, experimentStarted, experimentCompleted
}
