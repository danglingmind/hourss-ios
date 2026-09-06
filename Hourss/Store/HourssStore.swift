import SwiftUI
import Observation

/// In-memory store standing in for the Supabase-backed API.
///
/// Everything the shell shows flows through this one object, so starting a timer
/// on Today, stopping it, rating it, and finding it later in Journal are all the
/// same piece of state rather than three screens telling a similar story.
@Observable
@MainActor
final class HourssStore {
    var profile = Profile()
    var activities: [Activity] = Activity.defaults
    var sessions: [Session] = []
    var reflections: [UUID: Reflection] = [:]
    var insights: [Insight] = []
    var hasCompletedOnboarding = false

    /// Set when a session ends, to hand it straight to the reflection sheet.
    var pendingReflectionSessionId: UUID?

    /// Mirrors the running session into the Dynamic Island. Optional so tests and
    /// previews can run the store without ActivityKit.
    var live: LiveSessionController?

    init(seeded: Bool = true) {
        if seeded { MockData.seed(into: self) }
    }

    // MARK: - Lookups

    var runningSession: Session? { sessions.first(where: \.isRunning) }

    func activity(_ id: UUID) -> Activity? { activities.first { $0.id == id } }

    func activityName(_ id: UUID) -> String { activity(id)?.name ?? "Session" }

    func reflection(for sessionId: UUID) -> Reflection? { reflections[sessionId] }

    func feeling(for sessionId: UUID) -> Int? { reflections[sessionId]?.feelingScore }

    /// Completed sessions on a given day, oldest first.
    func sessions(on day: Date) -> [Session] {
        let cal = Calendar.current
        return sessions
            .filter { !$0.isRunning && cal.isDate($0.startAt, inSameDayAs: day) }
            .sorted { $0.startAt < $1.startAt }
    }

    func totalLoggedMinutes(on day: Date) -> Int {
        sessions(on: day).reduce(0) { $0 + $1.durationMinutes }
    }

    /// Days that have at least one session, newest first.
    var loggedDays: [Date] {
        let cal = Calendar.current
        let days = Set(sessions.filter { !$0.isRunning }.map { cal.startOfDay(for: $0.startAt) })
        return days.sorted(by: >)
    }

    /// Mean feeling per day, for the heat calendar. Days with sessions but no
    /// ratings are absent rather than zero — unrated stays unknown.
    var meanFeelingByDay: [Date: Double] {
        let calendar = Calendar.current
        var totals: [Date: (sum: Int, count: Int)] = [:]
        for session in sessions where !session.isRunning {
            guard let rating = feeling(for: session.id) else { continue }
            let day = calendar.startOfDay(for: session.startAt)
            let current = totals[day] ?? (0, 0)
            totals[day] = (current.sum + rating, current.count + 1)
        }
        return totals.mapValues { Double($0.sum) / Double($0.count) }
    }

    /// Sessions that ended without a feeling rating. Drives the "complete a missing
    /// reflection" prompt on Today.
    func unratedSessions(on day: Date) -> [Session] {
        sessions(on: day).filter { feeling(for: $0.id) == nil }
    }

    /// Activities the person has kept. Nothing sets `isFavorite` today: the
    /// onboarding step that curated the list folded into the final beat, where
    /// picking one starts a session instead. The distinction stays because
    /// `pickableActivities` depends on it and a curation surface belongs in You.
    var favoriteActivities: [Activity] {
        activities.filter { $0.isFavorite && !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// What every activity picker renders.
    ///
    /// Falls back to the whole set when nothing is kept. An empty picker is a dead
    /// end — no rows to choose, so no session can be started, so there is no way
    /// back to a usable app. Onboarding stops you reaching zero in the first place;
    /// this makes sure that even if it happens some other way, logging still works.
    var pickableActivities: [Activity] {
        let kept = favoriteActivities
        guard kept.isEmpty else { return kept }
        return activities.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Mutations

    /// Starts a session now. Any already-running session is closed first — the
    /// spec has no concept of two concurrent sessions.
    @discardableResult
    func startSession(activityId: UUID, intention: String? = nil) -> Session {
        if let running = runningSession { stopSession(running.id) }
        let session = Session(activityId: activityId, startAt: Date(), intention: intention)
        sessions.append(session)
        live?.start(session: session, activityName: activityName(activityId))
        return session
    }

    /// Records an hour that already happened, for when someone was too busy to log
    /// it at the time.
    ///
    /// Unlike `startSession` this does not touch a running session — backdating an
    /// earlier block should not stop the thing you are doing right now. The spec
    /// asks for the reflection immediately, so it is queued the same way stopping
    /// a live session does.
    @discardableResult
    func logPastSession(activityId: UUID, startAt: Date, endAt: Date, intention: String? = nil) -> Session {
        let session = Session(
            activityId: activityId,
            startAt: startAt,
            endAt: max(endAt, startAt.addingTimeInterval(60)),
            intention: intention
        )
        sessions.append(session)
        sessions.sort { $0.startAt < $1.startAt }
        pendingReflectionSessionId = session.id
        return session
    }

    /// Completed sessions that overlap a proposed slot.
    ///
    /// Overlapping sessions are dropped from pattern computation, so it is worth
    /// telling someone before they create one rather than silently discounting it
    /// later.
    func sessionsOverlapping(start: Date, end: Date) -> [Session] {
        sessions.filter { session in
            guard let sessionEnd = session.endAt else { return false }
            return session.startAt < end && start < sessionEnd
        }
    }

    /// Ends a session and queues its reflection.
    func stopSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].endAt = Date()
        pendingReflectionSessionId = id
        // The Island's whole job was the running session. Reflection happens in
        // the app, so there is nothing left for it to show.
        live?.endAll()
    }

    /// Saves a reflection. A nil feeling is preserved as "unanswered" rather than
    /// being coerced to a neutral score.
    func saveReflection(sessionId: UUID, feeling: Int?, performance: Int?, note: String?) {
        reflections[sessionId] = Reflection(
            sessionId: sessionId,
            feelingScore: feeling,
            performanceScore: performance,
            note: note?.isEmpty == true ? nil : note,
            submittedAt: Date()
        )
        if pendingReflectionSessionId == sessionId {
            pendingReflectionSessionId = nil
        }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        reflections[id] = nil
    }


    // MARK: - Insights

    /// Ranked, user-visible observations: strongest confidence first, hidden ones
    /// dropped, and anything below the internal threshold never surfaced.
    var visibleInsights: [Insight] {
        insights
            .filter { $0.status != .hidden && $0.status != .expired && $0.band != .internalOnly }
            .sorted { lhs, rhs in
                // Confidence still decides, but a stated priority breaks toward
                // what the person said they cared about. Weighting rather than
                // filtering: an observation is not less true for being about
                // something they did not rank.
                let lhsWeight = Double(lhs.confidence) + priorityBoost(for: lhs.type)
                let rhsWeight = Double(rhs.confidence) + priorityBoost(for: rhs.type)
                return lhsWeight > rhsWeight
            }
    }

    /// Up to 12 points for a first priority, tapering to 4 for a third — enough to
    /// reorder observations of similar strength, never enough to float a weak one
    /// above a strong one.
    func priorityBoost(for type: InsightType) -> Double {
        guard let rank = profile.priorities.firstIndex(where: { $0.insightTypes.contains(type) }) else { return 0 }
        return max(0, 12 - Double(rank) * 4)
    }

    /// Health context, kept so a rebuild triggered by anything else does not
    /// silently drop it.
    private(set) var healthByDay: [HealthMetric: [Date: Double]] = [:]
    /// Per-session heart-rate readings from the physiology layer, when available.
    private(set) var physiologyReadings: [UUID: Physiology.Reading] = [:]

    /// Recomputes observations with Health context folded in.
    ///
    /// Insights are derived, not authored, so connecting or disconnecting Health
    /// simply rebuilds them — which is also how a sleep-context observation
    /// disappears again on disconnect, rather than lingering as a stale claim.
    func applyHealthContext(_ healthByDay: [HealthMetric: [Date: Double]]) {
        self.healthByDay = healthByDay
        rebuildInsights()
    }

    func applyPhysiology(_ readings: [UUID: Physiology.Reading]) {
        physiologyReadings = readings
        rebuildInsights()
    }

    /// Score every eligible session against a movement curve fitted from the feed.
    ///
    /// One place, so the three screens that connect Health cannot drift into
    /// applying daily context and forgetting physiology — which is exactly what
    /// happened while `applyPhysiology` had no caller and the layer sat built,
    /// tested, and unreachable.
    ///
    /// A session with no reading stays absent rather than arriving as zero. Zero
    /// is a real value here — a heart rate exactly where movement predicts — and
    /// must not be how "we could not tell" is spelled.
    func applyPhysiology(feed: Physiology.Feed) {
        guard !feed.isEmpty else {
            applyPhysiology([:])
            return
        }
        let analyzer = Physiology.Analyzer(
            feed: feed, sessions: sessions, workdays: profile.workdays
        )
        var readings: [UUID: Physiology.Reading] = [:]
        for session in sessions where session.isEligibleForPatterns {
            if let reading = analyzer.reading(for: session) {
                readings[session.id] = reading
            }
        }
        applyPhysiology(readings)
    }

    /// Rebuild every observation from the current records.
    ///
    /// The status of an insight belongs to the person, not to the computation, so
    /// saved and hidden survive the rebuild and are carried across by id. That is
    /// only possible because an insight's identity now derives from the hypothesis
    /// that produced it rather than from a fresh UUID — the old engine minted new
    /// ones on every rebuild, so granting Health access quietly emptied whatever
    /// someone had saved.
    ///
    /// A status is only carried forward if the claim is still being made. An
    /// observation that no longer survives its own evidence should not come back
    /// wearing a badge from when it did.
    func rebuildInsights() {
        let carried = Dictionary(
            insights.filter { $0.status == .saved || $0.status == .hidden }
                .map { ($0.id, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )

        let rows = ObservationBuilder.rows(
            sessions: sessions,
            reflections: reflections,
            activities: activities,
            healthByDay: healthByDay,
            residuals: physiologyReadings,
            workdays: profile.workdays
        )

        insights = Engine.run(
            EngineInput(observations: rows, priorities: profile.priorities)
        ).map { insight in
            guard let status = carried[insight.id] else { return insight }
            var restored = insight
            restored.status = status
            return restored
        }
    }

    func setStatus(_ status: InsightStatus, for id: UUID) {
        guard let index = insights.firstIndex(where: { $0.id == id }) else { return }
        insights[index].status = status
    }

    func sessions(for insight: Insight) -> [Session] {
        insight.evidence.sessionIds.compactMap { id in sessions.first { $0.id == id } }
            .sorted { $0.startAt > $1.startAt }
    }

    // MARK: - Warm-up state

    /// Sessions eligible for pattern work, and how far off the first observation is.
    var eligibleSessionCount: Int { sessions.filter(\.isEligibleForPatterns).count }

    /// The spec gates the first observation behind a meaningful body of evidence.
    static let sessionsNeededForPatterns = 12

    var isWarmingUp: Bool { visibleInsights.isEmpty }

    var warmUpProgress: Double {
        min(1, Double(eligibleSessionCount) / Double(Self.sessionsNeededForPatterns))
    }

    /// Which times of day you have actually logged in. A pattern needs contrast,
    /// so logging only mornings tells the engine less than it looks like.
    var timeBucketsCovered: [Bool] {
        let logged = Set(sessions.filter(\.isEligibleForPatterns).map(\.timeBucket))
        return TimeBucket.allCases.map { logged.contains($0) }
    }

    /// Share of finished sessions that carry a feeling. Unrated sessions are
    /// dropped from every comparison, so this is the number that gates insights.
    var ratedShare: Double {
        let finished = sessions.filter { !$0.isRunning }
        guard !finished.isEmpty else { return 0 }
        let rated = finished.filter { feeling(for: $0.id) != nil }.count
        return Double(rated) / Double(finished.count)
    }

    /// Weeks between the first and most recent logged session, capped at six —
    /// the window every observation is computed over.
    var weeksOfHistory: Double {
        guard let first = sessions.map(\.startAt).min(),
              let last = sessions.map(\.startAt).max() else { return 0 }
        return min(6, last.timeIntervalSince(first) / (7 * 24 * 3600))
    }
}
