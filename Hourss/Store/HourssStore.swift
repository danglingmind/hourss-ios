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

    /// An hour somebody tapped in a day's hour strip that had nothing in it, and
    /// therefore wants filling.
    ///
    /// Carried on the store rather than passed down because the logging sheet is
    /// raised by `RootView` and the tap happens several views inside it — the
    /// same shape `NotificationService.pendingLogRequest` already uses for a tap
    /// on a reminder, and for the same reason.
    var pendingLogSlot: Date?

    func requestLog(at slotStart: Date) { pendingLogSlot = slotStart }
    func consumeLogSlot() { pendingLogSlot = nil }

    /// Mirrors the running session into the Dynamic Island. Optional so tests and
    /// previews can run the store without ActivityKit.
    var live: LiveSessionController?

    /// Starts empty.
    ///
    /// A first run has nothing in it, and that is the state the app has to be
    /// good at rather than one it hides behind generated history. Fixture data
    /// exists only in DEBUG builds and only when a launch argument asks for it.
    private let repository: RecordRepository
    /// Suspends writing while a batch of changes lands, so loading the record
    /// does not save it straight back, field by field.
    private var isRestoring = false

    /// Health identifiers the person has deleted, so the importer does not put
    /// them back on the next launch.
    private var removedImports: Set<String> = []

    init(repository: RecordRepository? = nil) {
        #if DEBUG
        if DebugFixture.isRequested {
            // Generated history goes nowhere near the real record. A UI test
            // that logs a session would otherwise write it to the same file the
            // app uses, so one test's leftovers would arrive in the next run and
            // in anybody's app on the same device.
            self.repository = repository ?? InMemoryRecordRepository()
            DebugFixture.seed(into: self)
            return
        }
        #endif
        self.repository = repository ?? FileRecordRepository()
        restore()
    }

    // MARK: - Persistence

    /// Read the record back.
    ///
    /// A failure here is not fatal and must not be: a record that cannot be
    /// decoded is a bug to fix, not a reason to refuse to open. Starting empty
    /// loses the history, which is bad; refusing to launch loses it too and takes
    /// the app with it.
    private func restore() {
        isRestoring = true
        defer { isRestoring = false }

        guard let record = try? repository.load() else { return }
        activities = record.activities.isEmpty ? Activity.defaults : record.activities
        sessions = record.sessions
        reflections = record.reflections
        profile = record.profile
        hasCompletedOnboarding = record.hasCompletedOnboarding
        removedImports = Set(record.removedImports ?? [])
        // Before the rebuild below, not after: a residual is an input to an
        // observation, and restoring it afterwards would leave the first rebuild
        // of every launch running on a record with no heart rate in it.
        physiologyReadings = Dictionary(
            (record.physiology ?? []).map { ($0.sessionId, $0.reading) },
            uniquingKeysWith: { first, _ in first }
        )

        // Insights are derived rather than stored, so they are recomputed here
        // and only the part that belongs to the person — saved, hidden — is
        // restored onto them.
        rebuildInsights()
        for (id, status) in record.insightStatus {
            guard let index = insights.firstIndex(where: { $0.id == id }) else { continue }
            insights[index].status = status
        }
    }

    /// Write the record out.
    ///
    /// Every mutation calls this. The whole record is a few hundred kilobytes
    /// after a year, so rewriting it costs less than tracking what changed, and
    /// the tracking is where this kind of code usually goes wrong.
    func persist() {
        guard !isRestoring else { return }
        var record = Record()
        record.activities = activities
        record.sessions = sessions
        record.reflections = reflections
        record.profile = profile
        record.hasCompletedOnboarding = hasCompletedOnboarding
        record.removedImports = removedImports.isEmpty ? nil : removedImports.sorted()
        record.physiology = physiologyReadings.isEmpty ? nil : physiologyReadings
            .map { Physiology.StoredReading(sessionId: $0.key, reading: $0.value) }
            .sorted { $0.sessionId.uuidString < $1.sessionId.uuidString }
        record.insightStatus = Dictionary(
            insights.filter { $0.status == .saved || $0.status == .hidden }
                .map { ($0.id, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
        try? repository.save(record)
    }

    // MARK: - Lookups

    var runningSession: Session? { sessions.first(where: \.isRunning) }

    func activity(_ id: UUID) -> Activity? { activities.first { $0.id == id } }

    func activityName(_ id: UUID) -> String { activity(id)?.name ?? "Session" }

    func reflection(for sessionId: UUID) -> Reflection? { reflections[sessionId] }

    func feeling(for sessionId: UUID) -> Int? { reflections[sessionId]?.feelingScore }

    /// Completed sessions on a given day, oldest first.
    ///
    /// Filed by `recordDay` rather than by start time, which is the same thing for
    /// everything except an imported night — that belongs to the morning it ended
    /// on, not to the evening it began in.
    func sessions(on day: Date) -> [Session] {
        let cal = Calendar.current
        return sessions
            .filter { !$0.isRunning && cal.isDate($0.recordDay, inSameDayAs: day) }
            .sorted { $0.startAt < $1.startAt }
    }

    func totalLoggedMinutes(on day: Date) -> Int {
        sessions(on: day).reduce(0) { $0 + $1.durationMinutes }
    }

    /// Days that have at least one session, newest first.
    var loggedDays: [Date] {
        let days = Set(sessions.filter { !$0.isRunning }.map(\.recordDay))
        return days.sorted(by: >)
    }

    /// Mean feeling per day, for the heat calendar. Days with sessions but no
    /// ratings are absent rather than zero — unrated stays unknown.
    var meanFeelingByDay: [Date: Double] {
        var totals: [Date: (sum: Int, count: Int)] = [:]
        for session in sessions where !session.isRunning {
            guard let rating = feeling(for: session.id) else { continue }
            let day = session.recordDay
            let current = totals[day] ?? (0, 0)
            totals[day] = (current.sum + rating, current.count + 1)
        }
        return totals.mapValues { Double($0.sum) / Double($0.count) }
    }

    /// Sessions that ended without a feeling rating. Drives the "complete a missing
    /// reflection" prompt on Today.
    ///
    /// Imported nights never appear here. An imported workout does: it is a thing
    /// somebody did and may well have an opinion about, and a rating on it is
    /// evidence the engine can actually use. A night is not rated in that sense,
    /// and queueing one every single morning would turn a prompt that means
    /// something into one people learn to dismiss without reading.
    func unratedSessions(on day: Date) -> [Session] {
        sessions(on: day).filter { feeling(for: $0.id) == nil && $0.healthKind != .sleep }
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
        persist()
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
        persist()
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
            persist()
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
            persist()
    }

    func deleteSession(_ id: UUID) {
        // Noted before the removal, because afterwards there is nothing left to
        // ask which Health block this was.
        if let externalId = sessions.first(where: { $0.id == id })?.externalId {
            removedImports.insert(externalId)
        }
        sessions.removeAll { $0.id == id }
        reflections[id] = nil
        // The residual goes with the session. It is keyed by an id that will never
        // be handed out again, so leaving it behind would grow the record by a row
        // nothing can ever look up.
        physiologyReadings[id] = nil
            persist()
    }

    // MARK: - The day's context card

    private static let contextCardDayKey = "hourss.reflection.lastContextCardDay"

    /// Whether today's first rating still owes a context card.
    ///
    /// Persisted as a day stamp rather than derived from the reflections, and the
    /// reason is directly above: `saveReflection` re-stamps `submittedAt` on every
    /// save. Counting today's reflections would therefore count an edit to a
    /// reflection written three weeks ago as today's first rating, and the card
    /// would reappear every time somebody tidied their journal.
    ///
    /// A day string rather than a `Date` because the question is "is this the same
    /// calendar day", and comparing stored instants means re-deciding that in the
    /// reader. `UserDefaults`, following `Membership`: a scalar that has to survive
    /// a launch and belongs to nothing else.
    var isContextCardDue: Bool {
        UserDefaults.standard.string(forKey: Self.contextCardDayKey) != Self.dayStamp(Date())
    }

    /// Claims the day. Called when a card is actually shown, never when one is
    /// merely considered — a day with no standout in it must not burn the slot
    /// and leave somebody with nothing.
    func markContextCardShown(on day: Date = Date()) {
        UserDefaults.standard.set(Self.dayStamp(day), forKey: Self.contextCardDayKey)
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: - Health import

    /// Put Health's own record of the last six weeks onto ours.
    ///
    /// Idempotent, which is the whole requirement: this runs on every launch and
    /// after every connection, and the same night must not become a second row
    /// because Health backfilled one more stage sample into it. Identity comes
    /// from `externalId` alone — a candidate already on the record is updated in
    /// place rather than added, so a block whose bounds moved converges on the
    /// truth instead of duplicating.
    ///
    /// Nothing imported ever competes with something already there. A workout that
    /// overlaps a session somebody logged by hand is the same hour told twice, and
    /// of the two tellings theirs is the one with an intention and a rating on it.
    @discardableResult
    func importFromHealth(_ candidates: [HealthImport.Candidate]) -> Int {
        var added = 0
        var changed = false
        var skippedForOverlap = 0

        for candidate in candidates {
            // Deleted once is deleted. The importer does not get a second opinion.
            guard !removedImports.contains(candidate.externalId) else { continue }

            if let index = sessions.firstIndex(where: { $0.externalId == candidate.externalId }) {
                guard sessions[index].startAt != candidate.startAt
                        || sessions[index].endAt != candidate.endAt else { continue }
                sessions[index].startAt = candidate.startAt
                sessions[index].endAt = candidate.endAt
                changed = true
                continue
            }

            guard sessionsOverlapping(start: candidate.startAt, end: candidate.endAt).isEmpty else {
                skippedForOverlap += 1
                continue
            }

            sessions.append(Session(
                activityId: importActivityId(for: candidate.kind),
                startAt: candidate.startAt,
                endAt: candidate.endAt,
                source: .health,
                healthKind: candidate.kind,
                externalId: candidate.externalId
            ))
            added += 1
        }

        #if DEBUG
        // The overlap count is the one that answers the question people actually
        // ask, which is why fewer things arrived than Health shows.
        print("[Hourss.import] \(candidates.count) candidates → \(added) added, \(skippedForOverlap) already covered by a logged session")
        #endif

        guard added > 0 || changed else { return 0 }
        sessions.sort { $0.startAt < $1.startAt }
        // An imported workout can be rated later and become evidence, so the feed
        // is rebuilt rather than left to catch up whenever something else happens
        // to touch it.
        rebuildInsights()
        persist()
        return added
    }

    /// Which activity an imported block is filed under.
    ///
    /// By name, against the starter set, because that is what the person sees and
    /// what they would expect a workout to land in. Creating the activity when it
    /// is genuinely absent is the one alternative to importing nothing and leaving
    /// somebody to work out why — and the starter set always contains both, so in
    /// practice this only fires for a record edited beyond what any screen in the
    /// app can currently do.
    private func importActivityId(for kind: HealthKind) -> UUID {
        let name = switch kind {
        case .workout: "Exercise"
        case .sleep: "Personal / Rest"
        }

        if let existing = activities.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }

        let created = Activity(
            name: name,
            category: kind == .workout ? "body" : "life",
            sortOrder: (activities.map(\.sortOrder).max() ?? 0) + 1
        )
        activities.append(created)
        return created.id
    }

    // MARK: - The account

    /// Take the name Apple just shared, if there is nowhere else it has come from.
    ///
    /// Only fills a blank. Apple's name is a starting value, not the authority on
    /// what somebody wants to be called, and overwriting an existing one would
    /// undo a decision every time a credential was re-authorized.
    func adoptDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profile.displayName.isEmpty, !trimmed.isEmpty else { return }
        profile.displayName = trimmed
        persist()
    }

    /// Erase everything Hourss holds about this person, at their request.
    ///
    /// The whole record, not a flag over it. Hourss has no server, so this *is*
    /// the deletion — there is no copy elsewhere to reconcile with — and anything
    /// left behind would be data somebody has explicitly asked to be rid of.
    ///
    /// Onboarding is reset with the rest. The alternative drops them into an app
    /// with no activities, no priorities and no history, which is a broken app
    /// rather than a fresh one.
    func deleteEverything() {
        sessions = []
        reflections = [:]
        insights = []
        interactions = []
        engineObservations = []
        activities = Activity.defaults
        profile = Profile()
        healthByDay = [:]
        physiologyReadings = [:]
        pendingReflectionSessionId = nil
        hasCompletedOnboarding = false
        removedImports = []
        live?.endAll()
        persist()
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
    ///
    /// Restored from the record rather than recomputed, and frozen once written —
    /// see `applyPhysiology(_:)`.
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

    /// Take readings for sessions that do not have one yet, and only those.
    ///
    /// **The first non-nil reading for a session wins, and is never recomputed.**
    /// This reverses what this method used to do — replace the lot on every read —
    /// and the reason is the one written on `Record.physiology`: the residual is
    /// measured against a curve fitted from a rolling sixty-day window, so the same
    /// session scores differently next week for reasons that have nothing to do
    /// with the session. Somebody who saw "9 bpm above expected" on Tuesday and "4"
    /// on Friday, for a meeting that happened once, has been shown a number that is
    /// about our arithmetic rather than about their morning. Freezing is what makes
    /// the figure showable at all.
    ///
    /// Two consequences that read as surprising and are deliberate:
    ///
    /// - An empty dictionary changes nothing. Disconnecting Health stops the app
    ///   reading, and "no data removed unless the user chooses" — a frozen residual
    ///   is part of the record now, like the session it belongs to, not a cache of
    ///   something HealthKit still holds. This is where it parts company with
    ///   `applyHealthContext`, which clears on disconnect precisely because that
    ///   context *is* re-readable and so would linger as a stale claim.
    /// - A session with no stored reading stays eligible forever. Nil is not a
    ///   decision that there is nothing to find; it is four different "not yet"s
    ///   (too few samples, a spoiled lead-in, no curve, an unseen pace), and three
    ///   of them resolve on their own as history accumulates.
    func applyPhysiology(_ readings: [UUID: Physiology.Reading]) {
        // Sorted, so that what lands is the same on every run. The dictionary is
        // keyed by id and the writes below are order-independent today, but a
        // rebuild reading it is not, and unordered iteration is how determinism
        // stops being a property of this store one small change from now.
        let arriving = readings
            .filter { physiologyReadings[$0.key] == nil }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        guard !arriving.isEmpty else { return }

        for (id, reading) in arriving { physiologyReadings[id] = reading }
        // Rebuilt before the write, so the statuses `persist` reads are the ones
        // belonging to the claims that survived this rebuild rather than the
        // previous one's.
        rebuildInsights()
        persist()
    }

    /// Sessions that could still gain a reading, oldest first.
    ///
    /// Three filters, each cutting out something that can never produce one:
    ///
    /// - Not eligible for patterns — running, sleep, under five minutes — is a
    ///   session the analyzer will not score under any circumstances.
    /// - Already frozen, by the rule above.
    /// - Older than the feed. `HealthService.physiologyDays` is how far back the
    ///   read reaches, so a session that has fallen out the back of that window has
    ///   no samples to be scored from and will never have any again. Without this
    ///   filter every foreground would find the same permanently unscorable
    ///   sessions and pay for a sixty-day refit to learn nothing — which is exactly
    ///   the cost the skip below exists to avoid.
    func sessionsAwaitingPhysiology(now: Date = Date(), calendar: Calendar = .current) -> [Session] {
        let horizon = calendar.date(byAdding: .day, value: -HealthService.physiologyDays, to: now)
            ?? .distantPast
        return sessions
            .filter { $0.isEligibleForPatterns && physiologyReadings[$0.id] == nil && $0.startAt >= horizon }
            .sorted { ($0.startAt, $0.id.uuidString) < ($1.startAt, $1.id.uuidString) }
    }

    /// Score the sessions that are still waiting for a reading, against a movement
    /// curve fitted from the feed.
    ///
    /// One place, so the three screens that connect Health cannot drift into
    /// applying daily context and forgetting physiology — which is exactly what
    /// happened while `applyPhysiology` had no caller and the layer sat built,
    /// tested, and unreachable.
    ///
    /// The curve is still fitted from *everything* the feed covers, including
    /// sessions that already have a frozen reading: the fit is a description of the
    /// person, and thinning it to the unscored sessions would make the curve worse
    /// for no gain. Only the scoring is narrowed.
    ///
    /// A session with no reading stays absent rather than arriving as zero. Zero
    /// is a real value here — a heart rate exactly where movement predicts — and
    /// must not be how "we could not tell" is spelled.
    func applyPhysiology(feed: Physiology.Feed) {
        // An empty feed is a read that found nothing, not a finding that there is
        // nothing. It used to clear everything; now it leaves the record alone, or
        // one launch with Health switched off in Settings would erase a year of
        // frozen residuals that cannot be recomputed.
        guard !feed.isEmpty else { return }
        let pending = sessionsAwaitingPhysiology()
        // The whole point of freezing: in the steady state there is nothing here,
        // and the sixty-day fit below — which runs on the main actor — never
        // happens. See `PhysiologyCatchUp`, which asks the same question before it
        // even goes to HealthKit.
        guard !pending.isEmpty else { return }

        // Nothing is scored until its window has finished arriving.
        //
        // This is the failure the freeze rule creates and does not solve on its
        // own. A watch hands heart rate to the phone in batches minutes behind the
        // wrist, so a session opened a minute after it ended may have only the
        // five samples that clear the floor rather than the forty it will have by
        // the hour. Frozen, that thin reading is the one shown forever — and it is
        // not merely noisier. Samples arrive in time order, so a half-synced
        // window is the *first half of the session*, which moves the median rather
        // than widening its error bar. The catch-up trigger makes this more likely
        // rather than less, because it gets a read in early.
        //
        // A settling delay would be the obvious fix and would be a guess. The feed
        // answers it exactly: if the newest heart-rate sample the phone holds is
        // later than the session ended, then everything inside that window which
        // is ever going to arrive has arrived. Sessions failing this stay pending
        // and are scored on a later pass, which is what `nil` already means here.
        let newestSample = feed.heartRate.map(\.at).max()
        let analyzer = Physiology.Analyzer(
            feed: feed, sessions: sessions, workdays: profile.workdays
        )
        var readings: [UUID: Physiology.Reading] = [:]
        for session in pending {
            guard let end = session.endAt, let newestSample, newestSample >= end else { continue }
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
    /// Conjunctions that survived every gate, strongest first.
    ///
    /// Separate from `insights` rather than folded into them, because they are a
    /// different kind of claim with a different correction behind it, and mixing
    /// the two would make the feed's ordering meaningless — a permutation p and a
    /// bootstrap interval are not comparable quantities.
    private(set) var interactions: [InteractionFinding] = []

    /// The rows the last rebuild ran on.
    ///
    /// Kept because narration needs them to name a factor in the person's own
    /// words — "your Deep work sessions", not "activity.deep-work" — and
    /// recomputing them in a view body would rebuild every row on every redraw.
    private(set) var engineObservations: [EngineObservation] = []

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

        engineObservations = rows
        let input = EngineInput(observations: rows, priorities: profile.priorities)

        // Interactions run off the same rows and the same main effects the feed
        // is built from, so a conjunction can never rest on evidence the feed
        // would not also accept. Recomputed here rather than lazily: the search
        // is bounded by `InteractionBudget` precisely so it can be afforded on
        // every rebuild rather than becoming a thing that runs sometimes.
        let mainEffectFindings = Engine.applyingCorrection(to: Engine.findings(for: input))
        let candidates = InteractionCandidates.findings(
            for: input,
            mainEffects: InteractionCandidates.mainEffects(from: mainEffectFindings)
        )
        interactions = InteractionCorrection
            .permutationFDR(to: candidates, observations: rows)
            .findings
            .filter(\.isReportable)
            .sorted { $0.interaction.lift > $1.interaction.lift }

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
            persist()
    }

    func sessions(for insight: Insight) -> [Session] {
        insight.evidence.sessionIds.compactMap { id in sessions.first { $0.id == id } }
            .sorted { $0.startAt > $1.startAt }
    }

    // MARK: - Warm-up state

    /// Sessions eligible for pattern work.
    ///
    /// Not a measure of readiness, and no longer displayed as one. Readiness is
    /// `ratedDayCount` against `EvidenceFloor`, because days are the unit the
    /// engine works in — it wants six distinct days on each side of a comparison
    /// and never counts sessions at all. A session total against a threshold of
    /// twelve told somebody they were most of the way to something that was not
    /// being measured.
    var eligibleSessionCount: Int { sessions.filter(\.isEligibleForPatterns).count }

    var isWarmingUp: Bool { visibleInsights.isEmpty }

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
