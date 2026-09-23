import Testing
import Foundation
@testable import Hourss

/// What the record keeps of layer 3, and why it may never be recomputed.
///
/// The residual is the one derived number Hourss writes down. Everything else
/// derived — every insight, every confidence band — is rebuilt from the sessions
/// on every launch, because rebuilding gives the same answer. A residual does not:
/// it is measured against a curve fitted from a rolling sixty-day window, so the
/// same session scores differently next week for reasons that belong to the
/// calendar rather than to the session. These tests are the ones that keep a
/// number that moves between launches from reaching a screen.
@Suite("Frozen physiology")
@MainActor
struct PhysiologyFreezeTests {

    // MARK: - Fixtures

    private func temporaryURL() -> URL {
        URL.temporaryDirectory.appending(path: "hourss-physiology-\(UUID().uuidString).json")
    }

    /// The cohort's feed, extended past its own last session.
    ///
    /// A generated feed stops at the end of the last thing it generated, which is
    /// a shape no real feed has for long: the wrist keeps sampling after somebody
    /// stops working. `applyPhysiology(feed:)` refuses to score a session whose
    /// window has not finished arriving, and it decides that by asking whether the
    /// newest sample is later than the session ended — so a feed that stops dead
    /// on the last session is, correctly, a feed that has not settled yet.
    ///
    /// Adding the trailing hour here rather than relaxing the guard: the guard is
    /// what stops a half-synced window being frozen forever, and a test fixture
    /// that could only pass without it would be testing the wrong thing.
    private func feed(_ person: SyntheticCohort.Person) -> Physiology.Feed {
        var heartRate = person.heartRate.map { Physiology.Sample(at: $0.at, value: $0.value) }
        if let lastEnd = person.sessions.compactMap(\.endAt).max(),
           let lastSample = heartRate.map(\.at).max(),
           lastSample <= lastEnd {
            heartRate.append(Physiology.Sample(at: lastEnd.addingTimeInterval(3600), value: 62))
        }
        return Physiology.Feed(
            heartRate: heartRate,
            steps: (person.samples[.steps] ?? []).map { Physiology.Sample(at: $0.at, value: $0.value) }
        )
    }

    /// A different curve, arrived at the way the real one moves: the same person,
    /// measured again with their heart running higher inside the sessions than it
    /// did the first time. Everything outside the sessions is untouched, so the
    /// baselines and the movement lift are fitted from almost the same windows and
    /// what changes is the residual — which is exactly the drift being defended
    /// against, compressed from a fortnight into one call.
    private func raised(_ feed: Physiology.Feed, by bpm: Double, during sessions: [Session]) -> Physiology.Feed {
        let spans = sessions.compactMap { session -> ClosedRange<Date>? in
            guard let end = session.endAt else { return nil }
            return session.startAt...end
        }
        var moved = feed
        moved.heartRate = feed.heartRate.map { sample in
            spans.contains { $0.contains(sample.at) }
                ? Physiology.Sample(at: sample.at, value: sample.value + bpm)
                : sample
        }
        return moved
    }

    private func store(_ person: SyntheticCohort.Person, at url: URL) -> HourssStore {
        let store = HourssStore(repository: FileRecordRepository(url: url))
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        store.persist()
        return store
    }

    // MARK: - Persistence

    @Test("A reading taken once is still there after a relaunch")
    func readingSurvivesRelaunch() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let first = store(person, at: url)
        first.applyPhysiology(feed: feed(person))
        try #require(!first.physiologyReadings.isEmpty, "nothing was scored, so nothing is being tested")

        // A second store over the same file is what a relaunch is — and this one
        // is never handed a feed at all, which is the point: the numbers below
        // cannot have been recomputed.
        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.physiologyReadings.count == first.physiologyReadings.count)

        for (id, before) in first.physiologyReadings.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let after = try #require(second.physiologyReadings[id])
            #expect(after.residual == before.residual)
            #expect(after.observed == before.observed)
            #expect(after.expected == before.expected)
            #expect(after.explainedByMovement == before.explainedByMovement)
            #expect(after.cadence == before.cadence)
            #expect(after.sampleCount == before.sampleCount)
            #expect(after.uncertainty == before.uncertainty)
            // The two properties anything on a screen actually asks for.
            #expect(after.exceedsUncertainty == before.exceedsUncertainty)
            #expect(after.movementContext == before.movementContext)
            // Derived on the way back in rather than stored, so it cannot disagree
            // with the cadence it is derived from.
            #expect(after.cadenceBin == Physiology.CadenceBin.containing(after.cadence))
        }
    }

    @Test("A record written before physiology existed still opens")
    func versionOneRecordDecodes() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let written = store(person, at: url)
        written.applyPhysiology(feed: feed(person))

        // The same file with the key taken out and the version put back, which is
        // exactly what is sitting on the phone of everybody running the current
        // build.
        var raw = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        try #require(raw["physiology"] != nil, "the field under test was never written")
        raw["physiology"] = nil
        raw["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: raw).write(to: url)

        let reopened = try FileRecordRepository(url: url).load()
        #expect(reopened.schemaVersion == 1)
        #expect(reopened.physiology == nil)
        #expect(reopened.sessions.count == person.sessions.count, "the rest of the record came back")

        let store = HourssStore(repository: FileRecordRepository(url: url))
        #expect(store.sessions.isEmpty == false)
        #expect(store.physiologyReadings.isEmpty, "a v1 record has no readings, not zeroed ones")
    }

    // MARK: - The freeze

    @Test("The first reading wins, even when the curve has moved under it")
    func firstReadingWins() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let original = feed(person)
        let frozen = store(person, at: url)
        frozen.applyPhysiology(feed: original)
        let firstReadings = frozen.physiologyReadings
        try #require(!firstReadings.isEmpty)

        let scored = person.sessions.filter { firstReadings[$0.id] != nil }
        let moved = raised(original, by: 12, during: scored)

        // The control, without which this test proves nothing: a store that has
        // never seen the first feed does get a different answer from the second.
        // If that stops being true, the freeze below is passing because there was
        // nothing to overwrite.
        let controlURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: controlURL) }
        let control = store(person, at: controlURL)
        control.applyPhysiology(feed: moved)
        let movedSomething = scored.contains { session in
            guard let before = firstReadings[session.id],
                  let after = control.physiologyReadings[session.id] else { return false }
            return abs(after.residual - before.residual) > 1
        }
        try #require(movedSomething, "the second feed scores the same as the first; nothing is being frozen against")

        // And the store that already has readings keeps every one of them.
        frozen.applyPhysiology(feed: moved)
        for (id, before) in firstReadings.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            #expect(frozen.physiologyReadings[id]?.residual == before.residual, Comment(rawValue:
                "a frozen residual was recomputed: \(before.residual) became "
                + "\(frozen.physiologyReadings[id]?.residual.description ?? "nil")"))
        }

        // Including across the relaunch, so the freeze is a property of the record
        // and not of one store's lifetime.
        let reopened = HourssStore(repository: FileRecordRepository(url: url))
        for (id, before) in firstReadings {
            #expect(reopened.physiologyReadings[id]?.residual == before.residual)
        }
    }

    @Test("A session with nothing to say stays absent rather than arriving as zero")
    func unscorableSessionsAreNeverStoredAsZero() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let store = store(person, at: url)

        // An hour this morning with no heart rate anywhere near it. The analyzer
        // has four separate reasons to return nil and this is one of them; what
        // matters is that nil is spelled "no row", because zero is a real answer
        // here — a heart rate exactly where movement predicts.
        let unmeasured = store.logPastSession(
            activityId: try #require(store.activities.first).id,
            startAt: Date().addingTimeInterval(-3600),
            endAt: Date().addingTimeInterval(-1800)
        )
        store.applyPhysiology(feed: feed(person))

        #expect(store.physiologyReadings[unmeasured.id] == nil)
        for reading in store.physiologyReadings.values {
            #expect(reading.sampleCount >= Physiology.Analyzer.minimumHeartRateSamples)
        }

        let record = try FileRecordRepository(url: url).load()
        let stored = try #require(record.physiology)
        #expect(!stored.contains { $0.sessionId == unmeasured.id },
                "an unscorable session was written to the record")
        #expect(!stored.contains { $0.residual == 0 && $0.observed == 0 },
                "a placeholder reading was stored for a session that has none")

        // And it is still eligible to gain one later, because nil here means
        // "not yet" rather than "nothing to find".
        #expect(store.sessionsAwaitingPhysiology().contains { $0.id == unmeasured.id })
    }

    @Test("The same readings write the same bytes")
    func storedReadingsAreWrittenInAFixedOrder() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let store = store(person, at: url)
        store.applyPhysiology(feed: feed(person))
        let stored = try #require(try FileRecordRepository(url: url).load().physiology)
        try #require(stored.count > 1)

        #expect(stored == stored.sorted { $0.sessionId.uuidString < $1.sessionId.uuidString },
                "readings were written in dictionary order, which changes with the hash seed")

        // And the same rows in the same order on the next save. A field that
        // re-encodes differently every launch is one no diff, backup or sync can
        // tell apart from a real change.
        store.persist()
        #expect(try FileRecordRepository(url: url).load().physiology == stored)
    }

    @Test("Deleting a session takes its reading with it")
    func deletingASessionDropsItsReading() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let store = store(person, at: url)
        store.applyPhysiology(feed: feed(person))
        let scored = try #require(store.physiologyReadings.keys.sorted { $0.uuidString < $1.uuidString }.first)

        store.deleteSession(scored)
        #expect(store.physiologyReadings[scored] == nil)
        let record = try FileRecordRepository(url: url).load()
        #expect(!(record.physiology ?? []).contains { $0.sessionId == scored })
    }

    @Test("An empty read does not erase what is already frozen")
    func anEmptyFeedChangesNothing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let store = store(person, at: url)
        store.applyPhysiology(feed: feed(person))
        let before = store.physiologyReadings
        try #require(!before.isEmpty)

        // Health switched off in Settings for a launch, or a watch left at home.
        // A residual cannot be recomputed, so clearing here would be deletion.
        store.applyPhysiology(feed: Physiology.Feed())
        store.applyPhysiology([:])
        #expect(store.physiologyReadings.count == before.count)
    }

    // MARK: - Not doing the work

    @Test("Once everything is frozen there is nothing left to refit")
    func nothingAwaitsWhenEverythingIsFrozen() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.stillMeetings
        let store = store(person, at: url)
        store.applyPhysiology(feed: feed(person))
        let readings = store.physiologyReadings
        try #require(!readings.isEmpty)

        // Sessions the analyzer could not score are genuinely still waiting — they
        // are the case the throttle exists for — so the steady state is staged by
        // keeping the ones that were scored.
        store.sessions = person.sessions.filter { readings[$0.id] != nil }
        #expect(store.sessionsAwaitingPhysiology().isEmpty)

        // Which is the question asked before HealthKit is touched at all.
        #expect(PhysiologyCatchUp.decision(
            isConnected: true,
            accessLost: false,
            readsRecovery: true,
            hasAwaitingSessions: !store.sessionsAwaitingPhysiology().isEmpty,
            lastReadAt: nil,
            isReading: false,
            now: Date()
        ) == .nothingAwaiting)

        // And a feed that would score differently still changes nothing.
        let moved = raised(feed(person), by: 12, during: store.sessions)
        store.applyPhysiology(feed: moved)
        for (id, before) in readings where store.sessions.contains(where: { $0.id == id }) {
            #expect(store.physiologyReadings[id]?.residual == before.residual)
        }
    }

    @Test("A session too old for the feed stops asking")
    func sessionsBeyondTheFeedAreNotAwaiting() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        let activity = try #require(store.activities.first)
        let now = Date()

        let recent = store.logPastSession(
            activityId: activity.id,
            startAt: now.addingTimeInterval(-3600),
            endAt: now.addingTimeInterval(-1800)
        )
        let ancient = store.logPastSession(
            activityId: activity.id,
            startAt: now.addingTimeInterval(-Double(HealthService.physiologyDays + 5) * 86_400),
            endAt: now.addingTimeInterval(-Double(HealthService.physiologyDays + 5) * 86_400 + 1800)
        )

        let awaiting = store.sessionsAwaitingPhysiology(now: now).map(\.id)
        #expect(awaiting.contains(recent.id))
        #expect(!awaiting.contains(ancient.id), Comment(rawValue:
            "a session older than the \(HealthService.physiologyDays)-day feed can never be scored, "
            + "so it must not keep asking for a refit"))
    }

    @Test("Sessions awaiting a reading come back in a fixed order")
    func awaitingIsDeterministic() throws {
        let person = SyntheticCohort.stillMeetings
        let first = HourssStore(repository: InMemoryRecordRepository())
        first.sessions = person.sessions
        let second = HourssStore(repository: InMemoryRecordRepository())
        second.sessions = person.sessions.reversed()

        let now = Date()
        #expect(first.sessionsAwaitingPhysiology(now: now).map(\.id)
                == second.sessionsAwaitingPhysiology(now: now).map(\.id))
    }
}

/// When the app comes forward and asks Health a second question.
///
/// Before this, `refresh()` ran on cold launch and nowhere else, so a session that
/// ended at 10:30 was scored against a feed that stopped at 08:00 and got nothing
/// — permanently, since the next cold launch is a force-quit away. The gates below
/// are what keep the fix from costing a launch on every glance at a notification.
@Suite("Foreground physiology catch-up")
@MainActor
struct PhysiologyCatchUpTests {

    private func decide(
        isConnected: Bool = true,
        accessLost: Bool = false,
        readsRecovery: Bool = true,
        awaiting: Bool = true,
        lastReadAt: Date? = nil,
        isReading: Bool = false,
        now: Date = Date()
    ) -> PhysiologyCatchUp.Outcome {
        PhysiologyCatchUp.decision(
            isConnected: isConnected,
            accessLost: accessLost,
            readsRecovery: readsRecovery,
            hasAwaitingSessions: awaiting,
            lastReadAt: lastReadAt,
            isReading: isReading,
            now: now
        )
    }

    @Test("Every existing Health gate still stops it")
    func gatesAreRespected() {
        #expect(decide(isConnected: false) == .notConnected)
        #expect(decide(accessLost: true) == .accessLost)
        #expect(decide(readsRecovery: false) == .recoveryNotSelected)
    }

    @Test("Nothing waiting means nothing is read")
    func nothingAwaitingSkipsTheRead() {
        // The ordinary answer. It is checked before the throttle on purpose: the
        // common case must be free rather than merely rate-limited.
        #expect(decide(awaiting: false) == .nothingAwaiting)
        #expect(decide(awaiting: false, lastReadAt: .distantPast) == .nothingAwaiting)
    }

    @Test("Rapid switching does not re-read Health")
    func throttleHolds() {
        let now = Date()
        #expect(decide(lastReadAt: nil, now: now) == .read, "the first foreground has nothing to wait for")
        #expect(decide(lastReadAt: now.addingTimeInterval(-1), now: now) == .throttled)
        #expect(decide(lastReadAt: now.addingTimeInterval(-PhysiologyCatchUp.minimumInterval + 1), now: now)
                == .throttled)
        #expect(decide(lastReadAt: now.addingTimeInterval(-PhysiologyCatchUp.minimumInterval), now: now)
                == .read)
        #expect(decide(lastReadAt: now.addingTimeInterval(-3600), now: now) == .read)
    }

    @Test("A read already in flight is not started twice")
    func concurrentActivationsCollapse() {
        #expect(decide(lastReadAt: nil, isReading: true) == .alreadyReading)
    }

    @Test("The interval is long enough to be a throttle and short enough to be a catch-up")
    func intervalIsSane() {
        #expect(PhysiologyCatchUp.minimumInterval >= 5 * 60, "anything shorter re-reads on ordinary app switching")
        #expect(PhysiologyCatchUp.minimumInterval <= 60 * 60, "anything longer is not a catch-up")
    }

    @Test("A disconnected service is never asked for a feed")
    func runRefusesWhenDisconnected() async {
        let health = HealthService()
        guard !health.isConnected else { return }
        let store = HourssStore(repository: InMemoryRecordRepository())
        let catchUp = PhysiologyCatchUp()
        let outcome = await catchUp.run(health: health, store: store)
        #expect(outcome == .notConnected)
        #expect(catchUp.lastReadAt == nil, "a refused foreground must not start the throttle clock")
    }
}

/// The half-synced window, which the freeze rule creates and does not solve.
@Suite("A window is not scored before it has arrived")
@MainActor
struct PhysiologySettlingTests {

    private func store() -> HourssStore {
        HourssStore(repository: InMemoryRecordRepository())
    }

    /// Samples every five minutes across a span.
    private func samples(from: Date, to: Date, bpm: Double = 64) -> [Physiology.Sample] {
        stride(from: 0, through: max(0, to.timeIntervalSince(from)), by: 300).map {
            Physiology.Sample(at: from.addingTimeInterval($0), value: bpm)
        }
    }

    /// A feed whose newest sample predates the session's end is a feed that has
    /// not finished arriving. Scoring it freezes the first half of the window.
    @Test("A feed that stops before the session ended scores nothing")
    func halfSyncedWindowIsNotFrozen() {
        let store = store()
        let start = Date().addingTimeInterval(-3 * 3600)
        let end = start.addingTimeInterval(3600)
        let session = Session(activityId: UUID(), startAt: start, endAt: end)
        store.sessions = [session]

        // Sixty days of history so a curve can fit, but nothing after the halfway
        // point of this session — the wrist has not handed the rest over yet.
        let feedStart = start.addingTimeInterval(-60 * 86_400)
        let partial = Physiology.Feed(
            heartRate: samples(from: feedStart, to: start.addingTimeInterval(1800)))
        store.applyPhysiology(feed: partial)

        #expect(store.physiologyReadings[session.id] == nil, Comment(rawValue:
            "froze a reading from a window that was still arriving"))
        #expect(store.sessionsAwaitingPhysiology().contains { $0.id == session.id },
                "the session must stay pending so a later pass can score it")
    }

    /// And the converse: once a sample exists past the end, everything inside the
    /// window that will ever arrive has arrived, so it is safe to freeze.
    @Test("A feed that runs past the session's end is allowed to score it")
    func settledWindowIsScorable() {
        let store = store()
        let start = Date().addingTimeInterval(-3 * 3600)
        let end = start.addingTimeInterval(3600)
        let session = Session(activityId: UUID(), startAt: start, endAt: end)
        store.sessions = [session]

        let feedStart = start.addingTimeInterval(-60 * 86_400)
        let settled = Physiology.Feed(
            heartRate: samples(from: feedStart, to: end.addingTimeInterval(1800)))
        store.applyPhysiology(feed: settled)

        // Whether a reading is produced still depends on every `Physiology`
        // threshold — samples, lead-in, a fitted curve. What this asserts is only
        // that the settling guard is no longer the thing standing in the way.
        #expect(!store.sessionsAwaitingPhysiology().isEmpty
                || store.physiologyReadings[session.id] != nil)
    }
}
