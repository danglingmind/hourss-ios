import Foundation

/// Mirrors the `activities` table.
struct Activity: Identifiable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var sortOrder: Int
    var isFavorite: Bool
    var isArchived: Bool = false

    init(id: UUID = UUID(), name: String, category: String, sortOrder: Int, isFavorite: Bool = true) {
        self.id = id
        self.name = name
        self.category = category
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
    }

    /// The starter set offered during onboarding.
    static let defaults: [Activity] = [
        Activity(name: "Deep work", category: "work", sortOrder: 0),
        Activity(name: "Meetings", category: "work", sortOrder: 1),
        Activity(name: "Admin", category: "work", sortOrder: 2),
        Activity(name: "Learning", category: "growth", sortOrder: 3),
        Activity(name: "Creative", category: "growth", sortOrder: 4),
        Activity(name: "Exercise", category: "body", sortOrder: 5),
        Activity(name: "Social", category: "life", sortOrder: 6),
        Activity(name: "Personal / Rest", category: "life", sortOrder: 7),
    ]
}

/// Mirrors the `sessions` table. `endAt` is nil while a session is running.
struct Session: Identifiable, Hashable {
    let id: UUID
    var activityId: UUID
    var startAt: Date
    var endAt: Date?
    var source: SessionSource
    var note: String?
    var intention: String?

    init(
        id: UUID = UUID(),
        activityId: UUID,
        startAt: Date,
        endAt: Date? = nil,
        source: SessionSource = .manual,
        note: String? = nil,
        intention: String? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.startAt = startAt
        self.endAt = endAt
        self.source = source
        self.note = note
        self.intention = intention
    }

    var isRunning: Bool { endAt == nil }

    var durationSeconds: Int {
        Int((endAt ?? Date()).timeIntervalSince(startAt))
    }

    var durationMinutes: Int { durationSeconds / 60 }

    var timeBucket: TimeBucket {
        TimeBucket.bucket(forHour: Calendar.current.component(.hour, from: startAt))
    }

    var durationBucket: DurationBucket {
        DurationBucket.bucket(forMinutes: durationMinutes)
    }

    /// Validity rules from the spec: under 5 minutes or over 16 hours is excluded
    /// from pattern computation.
    var isEligibleForPatterns: Bool {
        guard !isRunning else { return false }
        return durationMinutes >= 5 && durationSeconds <= 16 * 3600
    }
}

/// Mirrors `session_reflections`. Both scores are optional on purpose — an
/// unanswered scale is unknown, not neutral.
struct Reflection: Identifiable, Hashable {
    var id: UUID { sessionId }
    let sessionId: UUID
    var feelingScore: Int?
    var performanceScore: Int?
    var note: String?
    var submittedAt: Date
}

/// Mirrors the `insights` table. `evidence` carries the numbers shown on the
/// detail screen so a claim and its support can never drift apart.
struct Insight: Identifiable, Hashable {
    let id: UUID
    var type: InsightType
    var statement: String
    var evidence: Evidence
    var confidence: Int
    var status: InsightStatus
    var generatedAt: Date
    var caveat: String
    var experiment: String?

    var band: Confidence { Confidence.band(confidence) }

    struct Evidence: Hashable {
        /// e.g. "Before 11am"
        var comparisonLabel: String
        var comparisonValue: Double
        var comparisonCount: Int
        /// e.g. "After 11am"
        var baselineLabel: String
        var baselineValue: Double
        var baselineCount: Int
        var windowDescription: String
        /// Sessions the claim was computed from, shown in full on the detail screen.
        var sessionIds: [UUID]

        /// The evidence sentence in the spec's format:
        /// "4.2 vs 3.4 after lunch; 9 vs 8 sessions, past 6 weeks".
        var summary: String {
            String(
                format: "%.1f vs %.1f · %d vs %d sessions, %@",
                comparisonValue, baselineValue, comparisonCount, baselineCount, windowDescription
            )
        }
    }
}

/// Mirrors the `profiles` table.
struct Profile {
    var displayName: String = ""
    var timezone: String = TimeZone.current.identifier
    var weekStart: Int = 2
    var workdays: Set<Int> = [2, 3, 4, 5, 6]
    var goals: Set<Intent> = []
    var reflectionHour: Int = 20
    var quietMode: Bool = false
    var logPrompts: Bool = true
    var weeklyReflection: Bool = true
}
