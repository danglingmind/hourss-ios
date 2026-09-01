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

/// Goals a person can pick during onboarding. 1–3 selections personalise the
/// language and ranking weights.
enum Intent: String, CaseIterable, Identifiable {
    case focus, energy, balance, recovery, curiosity

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .focus: "Understand when focused work holds up."
        case .energy: "See what gives energy back and what takes it."
        case .balance: "Notice how work and the rest of life trade off."
        case .recovery: "Find what actually restores you."
        case .curiosity: "Just build a record and see what shows up."
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

    var group: String {
        switch self {
        case .bestTimeWindow, .drainingTimeWindow: "Timing"
        case .activityEnergizer, .activityDrain, .durationSweetSpot: "Activities"
        case .performanceFeelingSplit, .fragmentation, .workdayContrast, .sleepContext, .emergingChange: "Energy"
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
