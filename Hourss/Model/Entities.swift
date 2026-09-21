import Foundation

/// Mirrors the `activities` table.
struct Activity: Identifiable, Hashable, Codable {
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
struct Session: Identifiable, Hashable, Codable {
    let id: UUID
    var activityId: UUID
    var startAt: Date
    var endAt: Date?
    var source: SessionSource
    var note: String?
    var intention: String?

    /// Which kind of Health block this was imported from, and nil for anything a
    /// person logged themselves.
    var healthKind: HealthKind?

    /// What this block is called in Health, so a second import recognises it.
    ///
    /// Both of these are optional, and that is what makes them safe to add: a
    /// synthesized `Codable` fails on a missing key for a non-optional property
    /// however tidy its default looks, so every record written before today would
    /// stop decoding. An optional decodes as nil instead, which is the truth about
    /// a session logged before Hourss could import anything.
    var externalId: String?

    init(
        id: UUID = UUID(),
        activityId: UUID,
        startAt: Date,
        endAt: Date? = nil,
        source: SessionSource = .manual,
        note: String? = nil,
        intention: String? = nil,
        healthKind: HealthKind? = nil,
        externalId: String? = nil
    ) {
        self.id = id
        self.activityId = activityId
        self.startAt = startAt
        self.endAt = endAt
        self.source = source
        self.note = note
        self.intention = intention
        self.healthKind = healthKind
        self.externalId = externalId
    }

    /// Hourss put this on the record by reading Health, rather than the person
    /// putting it there.
    var isImported: Bool { source == .health }

    var isRunning: Bool { endAt == nil }

    var durationSeconds: Int {
        Int((endAt ?? Date()).timeIntervalSince(startAt))
    }

    var durationMinutes: Int { durationSeconds / 60 }

    var timeBucket: TimeBucket {
        TimeBucket.bucket(forHour: Calendar.current.component(.hour, from: startAt))
    }

    /// The day this session is filed under in Today and the Journal.
    ///
    /// Start time for everything a person logged, because that is when they were
    /// doing it. Sleep is the exception and has to be: a night runs from 23:40 to
    /// 07:10 and belongs to the morning it ends on — which is how people speak
    /// about it, and already how `HealthService` attributes sleep hours as daily
    /// context. Filing it by its start would put the same night on a different day
    /// depending on which part of the app was asking.
    var recordDay: Date {
        let calendar = Calendar.current
        if healthKind == .sleep, let endAt {
            return calendar.startOfDay(for: endAt)
        }
        return calendar.startOfDay(for: startAt)
    }

    var durationBucket: DurationBucket {
        DurationBucket.bucket(forMinutes: durationMinutes)
    }

    /// Validity rules from the spec: under 5 minutes or over 16 hours is excluded
    /// from pattern computation.
    ///
    /// Imported sleep is excluded outright, and not because of its length. The
    /// engine already reads every night as daily context through
    /// `HealthMetric.sleepHours` — it is one of the things observations are
    /// computed *against* — so admitting the same night a second time as a session
    /// would let one night stand on both sides of a comparison and appear to
    /// corroborate itself. A workout is not in that position: the daily context is
    /// about the day, while a rated workout session is a real answer about how that
    /// particular block felt, which is exactly what the engine is short of.
    var isEligibleForPatterns: Bool {
        guard !isRunning, healthKind != .sleep else { return false }
        return durationMinutes >= 5 && durationSeconds <= 16 * 3600
    }
}

/// Mirrors `session_reflections`. Both scores are optional on purpose — an
/// unanswered scale is unknown, not neutral.
struct Reflection: Identifiable, Hashable, Codable {
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
struct Profile: Codable {
    var displayName: String = ""
    var timezone: String = TimeZone.current.identifier
    /// In the person's own order, most important first.
    var priorities: [Priority] = []
    var weekStart: Int = 2
    var workdays: Set<Int> = [2, 3, 4, 5, 6]
    var reflectionHour: Int = 20
    var quietMode: Bool = false
    var weeklyReflection: Bool = true

    /// How often to ask what you are doing.
    ///
    /// Optional because it replaced `logPrompts`, a boolean that was never wired
    /// to anything: a record written before this existed has no value here, and
    /// nil has to mean "never chose" rather than silently becoming a schedule
    /// somebody did not agree to. `logPrompts` itself is simply gone — an unknown
    /// key decodes fine, where a missing one would not.
    var logReminder: LogReminderFrequency?

    /// What the app acts on. Nobody is sent notifications they did not pick.
    var logReminderFrequency: LogReminderFrequency { logReminder ?? .off }
}
