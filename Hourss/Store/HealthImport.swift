import Foundation

/// Blocks of time Apple Health already knows about, turned into sessions.
///
/// The point is friction. Two of the eight starter activities — Exercise and
/// Personal / Rest — are things a watch has already recorded precisely, and asking
/// somebody to log them again by hand is asking them to retype what their phone
/// can read. So Hourss reads them, and the Journal has something in it on the day
/// somebody installs the app rather than six weeks later.
///
/// Everything here is deliberately free of HealthKit types. The clustering below
/// is the only part with real judgement in it, and a rule about what counts as one
/// night's sleep should be testable without a device, a permission and a year of
/// somebody's real samples.
enum HealthImport {

    /// A stretch of time Health recorded, with nothing said about what it was.
    struct Span: Equatable, Sendable {
        let start: Date
        let end: Date

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// One workout, as Health identifies it.
    struct Workout: Equatable, Sendable {
        /// `HKWorkout.uuid`. Stable across reads, which is what makes importing
        /// twice safe.
        let id: UUID
        let span: Span
    }

    /// A block that is ready to become a session.
    struct Candidate: Equatable, Sendable {
        let kind: HealthKind
        /// What this block is called in Health. The whole of deduplication rests
        /// on it, so it has to name the same block on every read, forever.
        let externalId: String
        let startAt: Date
        let endAt: Date

        var duration: TimeInterval { endAt.timeIntervalSince(startAt) }
    }

    // MARK: - Thresholds

    /// How long a break has to be before it separates one sleep block from the
    /// next.
    ///
    /// Health does not record a night. It records stages — core, deep, REM, awake —
    /// as dozens of samples with gaps between them, and a rule that treated every
    /// gap as a new night would put twenty Rest rows on a Tuesday. Forty-five
    /// minutes is long enough to swallow ordinary waking in the night and short
    /// enough that an afternoon nap does not get glued onto the previous night.
    static let sleepGap: TimeInterval = 45 * 60

    /// The shortest sleep block worth a row of its own.
    static let minimumSleep: TimeInterval = 45 * 60

    /// The shortest workout worth a row of its own.
    ///
    /// Matches `Session.isEligibleForPatterns`, which drops anything under five
    /// minutes anyway. Importing them would put rows on the record that no
    /// observation can ever be computed from — a watch that logs a four-minute
    /// "workout" for a brisk walk to the car should not fill somebody's Journal.
    static let minimumWorkout: TimeInterval = 5 * 60

    // MARK: - Workouts

    /// Every workout long enough to be worth recording, one session each.
    static func candidates(workouts: [Workout]) -> [Candidate] {
        workouts
            .filter { $0.span.duration >= minimumWorkout }
            .sorted { $0.span.start < $1.span.start }
            .map { workout in
                Candidate(
                    kind: .workout,
                    externalId: "health.workout.\(workout.id.uuidString)",
                    startAt: workout.span.start,
                    endAt: workout.span.end
                )
            }
    }

    // MARK: - Sleep

    /// One Rest session per day: the night that ended that morning.
    ///
    /// Two decisions are baked in here. A night is filed under the morning it ends
    /// on, matching both how people speak about it and how `HealthService` already
    /// attributes sleep hours as daily context — so the same night never lands on
    /// two different days depending on which part of the app is asking.
    ///
    /// And only the longest block of a day survives. Naps are real and this
    /// discards them, which is a choice about clutter rather than about truth: the
    /// row is meant to read as "this is the night you had", and a Journal with a
    /// 50-minute Rest stub under a 7-hour one says something less clear than
    /// either would alone. It also buys the only genuinely stable identifier
    /// available — the day — since a block's own start moves whenever Health
    /// backfills another stage sample, and an identifier that moves is an
    /// identifier that duplicates.
    static func candidates(sleep spans: [Span], calendar: Calendar = .current) -> [Candidate] {
        let blocks = merge(spans).filter { $0.duration >= minimumSleep }

        var longestByMorning: [Date: Span] = [:]
        for block in blocks {
            let morning = calendar.startOfDay(for: block.end)
            if let existing = longestByMorning[morning], existing.duration >= block.duration { continue }
            longestByMorning[morning] = block
        }

        return longestByMorning
            .map { morning, block in
                Candidate(
                    kind: .sleep,
                    externalId: "health.sleep.\(Self.dayKey(morning, calendar: calendar))",
                    startAt: block.start,
                    endAt: block.end
                )
            }
            .sorted { $0.startAt < $1.startAt }
    }

    /// Collapse overlapping and near-adjacent spans into blocks.
    static func merge(_ spans: [Span]) -> [Span] {
        let ordered = spans.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = ordered.first else { return [] }

        var blocks: [Span] = []
        for span in ordered.dropFirst() {
            if span.start <= current.end.addingTimeInterval(sleepGap) {
                // `max` rather than the new end: stage samples are not guaranteed
                // to be nested or ordered by end, and one short sample arriving
                // inside a long one would otherwise truncate the block.
                current = Span(start: current.start, end: max(current.end, span.end))
            } else {
                blocks.append(current)
                current = span
            }
        }
        blocks.append(current)
        return blocks
    }

    /// A day as a sortable, locale-independent key.
    ///
    /// Not `Date.description` and not a localized format: this string is written
    /// into the record and has to mean the same thing after somebody flies to
    /// another timezone or changes their region.
    private static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}


/// Everything a Health read feeds, in one call.
///
/// Three things now depend on a read — daily context, per-session physiology, and
/// the importer — and they are applied together because the alternative has
/// already happened once here: `applyPhysiology` sat built, tested and uncalled
/// while two of the three screens that connect Health remembered only the other
/// one. A third thing to remember would not have survived either.
@MainActor
func applyHealthRead(from health: HealthService, to store: HourssStore) async {
    store.applyHealthContext(health.dailyValues)
    // The feed `refresh()` already read, rather than a second trip for the same
    // sixty days of heart rate.
    store.applyPhysiology(feed: health.physiology)
    store.importFromHealth(await health.readImportableSessions())
}
