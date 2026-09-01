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

    /// Sessions that ended without a feeling rating. Drives the "complete a missing
    /// reflection" prompt on Today.
    func unratedSessions(on day: Date) -> [Session] {
        sessions(on: day).filter { feeling(for: $0.id) == nil }
    }

    var favoriteActivities: [Activity] {
        activities.filter { $0.isFavorite && !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var favoriteCount: Int { favoriteActivities.count }

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
        return session
    }

    /// Ends a session and queues its reflection.
    func stopSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].endAt = Date()
        pendingReflectionSessionId = id
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
        if pendingReflectionSessionId == sessionId { pendingReflectionSessionId = nil }
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        reflections[id] = nil
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].isFavorite.toggle()
    }

    // MARK: - Insights

    /// Ranked, user-visible observations: strongest confidence first, hidden ones
    /// dropped, and anything below the internal threshold never surfaced.
    var visibleInsights: [Insight] {
        insights
            .filter { $0.status != .hidden && $0.status != .expired && $0.band != .internalOnly }
            .sorted { $0.confidence > $1.confidence }
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
}
