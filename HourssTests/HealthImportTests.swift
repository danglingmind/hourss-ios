import Testing
import Foundation
@testable import Hourss

/// Reading sessions out of Apple Health.
///
/// Two things are being defended here and they pull in opposite directions. The
/// importer has to run on every launch and produce the same record every time —
/// Health backfills sleep stages for hours after a night, so "the same night"
/// arrives repeatedly with slightly different edges. And it must never put a row
/// on somebody's record that competes with, or overrules, one they put there
/// themselves.
@Suite("Importing from Health")
@MainActor
struct HealthImportTests {

    // MARK: - Fixtures

    private static let calendar = Calendar(identifier: .gregorian)

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(
            calendar: calendar, timeZone: .current,
            year: 2026, month: 3, day: day, hour: hour, minute: minute
        ).date!
    }

    private static func span(_ from: Date, _ to: Date) -> HealthImport.Span {
        HealthImport.Span(start: from, end: to)
    }

    // MARK: - Workouts

    @Test("A workout becomes one session, named by the identifier Health gave it")
    func workoutsBecomeCandidates() {
        let id = UUID()
        let candidates = HealthImport.candidates(workouts: [
            HealthImport.Workout(id: id, span: Self.span(Self.at(10, 7), Self.at(10, 8)))
        ])

        #expect(candidates.count == 1)
        #expect(candidates[0].kind == .workout)
        #expect(candidates[0].externalId == "health.workout.\(id.uuidString)")
        #expect(candidates[0].startAt == Self.at(10, 7))
    }

    /// A watch logs a four-minute "workout" for the walk to the car. Importing it
    /// puts a row on the record that no observation can ever be computed from.
    @Test("Workouts too short to mean anything are left out")
    func shortWorkoutsAreDropped() {
        let candidates = HealthImport.candidates(workouts: [
            HealthImport.Workout(id: UUID(), span: Self.span(Self.at(10, 7), Self.at(10, 7, 4)))
        ])
        #expect(candidates.isEmpty)
    }

    // MARK: - Sleep

    /// Health records stages, not nights: core, deep, REM and brief waking arrive
    /// as a dozen samples with gaps between them.
    @Test("Stage samples across one night become a single night")
    func stagesMergeIntoOneNight() {
        let candidates = HealthImport.candidates(sleep: [
            Self.span(Self.at(10, 23, 40), Self.at(11, 1, 30)),
            Self.span(Self.at(11, 1, 35), Self.at(11, 4, 0)),
            Self.span(Self.at(11, 4, 20), Self.at(11, 7, 10)),
        ], calendar: Self.calendar)

        #expect(candidates.count == 1)
        #expect(candidates[0].startAt == Self.at(10, 23, 40))
        #expect(candidates[0].endAt == Self.at(11, 7, 10))
    }

    /// The decision the user made: a night belongs to the morning it ends on.
    @Test("A night that crosses midnight is filed under the morning it ended on")
    func nightsAreFiledUnderTheWakeDay() {
        let candidates = HealthImport.candidates(sleep: [
            Self.span(Self.at(10, 23, 40), Self.at(11, 7, 10))
        ], calendar: Self.calendar)

        #expect(candidates[0].externalId == "health.sleep.2026-03-11",
                "The night of the 10th into the 11th is the 11th's night")
    }

    @Test("A real break splits one block into two")
    func longGapsSplitBlocks() {
        let blocks = HealthImport.merge([
            Self.span(Self.at(10, 1), Self.at(10, 6)),
            // Two hours later: an afternoon nap, not the same night.
            Self.span(Self.at(10, 14), Self.at(10, 15, 30)),
        ])
        #expect(blocks.count == 2)
    }

    /// One Rest row per day, so the Journal reads as "this is the night you had"
    /// rather than as a list of everything the watch noticed.
    @Test("Only the longest block of a day survives")
    func onlyTheMainSleepOfADaySurvives() {
        let candidates = HealthImport.candidates(sleep: [
            Self.span(Self.at(10, 23), Self.at(11, 7)),        // the night — 8h
            Self.span(Self.at(11, 14), Self.at(11, 15, 30)),   // a nap — 90m
        ], calendar: Self.calendar)

        #expect(candidates.count == 1)
        #expect(candidates[0].endAt == Self.at(11, 7))
    }

    @Test("A few minutes of dozing is not a night")
    func veryShortSleepIsDropped() {
        let candidates = HealthImport.candidates(sleep: [
            Self.span(Self.at(10, 14), Self.at(10, 14, 20))
        ], calendar: Self.calendar)
        #expect(candidates.isEmpty)
    }

    // MARK: - Landing on the record

    private func makeStore() -> HourssStore {
        HourssStore(repository: InMemoryRecordRepository())
    }

    private static func sleepCandidate(
        id: String = "health.sleep.2026-03-11",
        from: Date = at(10, 23, 30),
        to: Date = at(11, 7, 0)
    ) -> HealthImport.Candidate {
        HealthImport.Candidate(kind: .sleep, externalId: id, startAt: from, endAt: to)
    }

    private static func workoutCandidate(
        id: String = "health.workout.1",
        from: Date = at(11, 17, 0),
        to: Date = at(11, 18, 0)
    ) -> HealthImport.Candidate {
        HealthImport.Candidate(kind: .workout, externalId: id, startAt: from, endAt: to)
    }

    @Test("Imported blocks land on the right activities")
    func importedBlocksUseTheStarterActivities() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate(), Self.workoutCandidate()])

        #expect(store.sessions.count == 2)
        let names = Set(store.sessions.map { store.activityName($0.activityId) })
        #expect(names == ["Personal / Rest", "Exercise"])
        // Computed outside the macro: `allSatisfy` is `rethrows`, and `#expect`
        // cannot prove a rethrowing call non-throwing from inside its expansion.
        let allImported = store.sessions.allSatisfy(\.isImported)
        #expect(allImported)
    }

    /// The whole requirement: this runs on every launch.
    @Test("Importing the same night twice does not write it twice")
    func importingIsIdempotent() {
        let store = makeStore()
        #expect(store.importFromHealth([Self.sleepCandidate()]) == 1)
        #expect(store.importFromHealth([Self.sleepCandidate()]) == 0)
        #expect(store.sessions.count == 1)
    }

    /// Health keeps backfilling stage samples for hours after a night, so the same
    /// night genuinely arrives with different edges.
    @Test("A night whose edges moved is corrected in place, not duplicated")
    func movedBoundsUpdateInPlace() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate()])

        store.importFromHealth([Self.sleepCandidate(from: Self.at(10, 23, 10), to: Self.at(11, 7, 25))])

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].startAt == Self.at(10, 23, 10))
        #expect(store.sessions[0].endAt == Self.at(11, 7, 25))
    }

    /// Of the two tellings of one hour, theirs is the one with an intention and a
    /// rating on it.
    @Test("An imported workout never lands on top of one somebody logged")
    func overlapsWithHandLoggedSessionsAreSkipped() {
        let store = makeStore()
        let exercise = store.activities.first { $0.name == "Exercise" }!
        store.logPastSession(activityId: exercise.id, startAt: Self.at(11, 17, 10), endAt: Self.at(11, 17, 50))

        let added = store.importFromHealth([Self.workoutCandidate()])

        #expect(added == 0)
        #expect(store.sessions.count == 1)
    }

    @Test("Something deleted does not come back on the next launch")
    func deletedImportsStayDeleted() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate()])
        store.deleteSession(store.sessions[0].id)

        #expect(store.importFromHealth([Self.sleepCandidate()]) == 0)
        #expect(store.sessions.isEmpty)
    }

    @Test("A deletion is remembered across launches")
    func deletedImportsSurviveARelaunch() {
        let repository = InMemoryRecordRepository()
        let first = HourssStore(repository: repository)
        first.importFromHealth([Self.sleepCandidate()])
        first.deleteSession(first.sessions[0].id)

        let second = HourssStore(repository: repository)
        #expect(second.importFromHealth([Self.sleepCandidate()]) == 0)
    }

    // MARK: - How the record reads afterwards

    @Test("A night is listed under the morning it ended on")
    func sleepIsListedOnTheWakeDay() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate()])

        #expect(store.sessions(on: Self.at(11, 12)).count == 1, "The 11th had a night")
        #expect(store.sessions(on: Self.at(10, 12)).isEmpty, "The 10th did not")
    }

    /// The decision the user made: prompt for workouts, never for sleep.
    @Test("The reflection prompt asks about an imported workout and never about a night")
    func onlyWorkoutsJoinTheReflectionQueue() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate(), Self.workoutCandidate()])

        let unrated = store.unratedSessions(on: Self.at(11, 12))
        #expect(unrated.count == 1)
        #expect(unrated[0].healthKind == .workout)
    }

    /// The same night is already in the engine as daily context, and must not also
    /// stand as a session — one night cannot be evidence for itself twice.
    @Test("An imported night is not evidence; an imported workout can be")
    func sleepIsNeverPatternEvidence() {
        let store = makeStore()
        store.importFromHealth([Self.sleepCandidate(), Self.workoutCandidate()])

        let sleep = store.sessions.first { $0.healthKind == .sleep }!
        let workout = store.sessions.first { $0.healthKind == .workout }!
        #expect(sleep.isEligibleForPatterns == false)
        #expect(workout.isEligibleForPatterns)
    }
}

/// The record written before any of this existed still has to open.
@Suite("Records from before the importer")
struct ImportSchemaTests {

    /// A synthesized `Codable` fails on a missing key for a non-optional property
    /// however sensible its default looks, so every field the importer added had
    /// to be optional. This is the assertion that says so.
    @Test("A session written before the importer decodes with its new fields empty")
    func oldSessionsStillDecode() throws {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "activityId": "3F2504E0-4F89-11D3-9A0C-0305E82C3302",
          "startAt": "2026-03-10T09:00:00Z",
          "endAt": "2026-03-10T10:30:00Z",
          "source": "manual"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: json)

        #expect(session.healthKind == nil)
        #expect(session.externalId == nil)
        #expect(session.isImported == false)
        #expect(session.durationMinutes == 90)
    }

    @Test("A record written before the importer decodes with no deletions remembered")
    func oldRecordsStillDecode() throws {
        // `reflections` and `insightStatus` are keyed by UUID, and Swift encodes a
        // dictionary whose key is not a String as a flat array of alternating
        // keys and values — so an empty one is `[]`, not `{}`.
        let json = """
        {
          "schemaVersion": 1,
          "activities": [],
          "sessions": [],
          "reflections": [],
          "profile": {
            "displayName": "", "timezone": "UTC", "priorities": [], "weekStart": 2,
            "workdays": [2, 3, 4, 5, 6], "reflectionHour": 20, "quietMode": false,
            "logPrompts": true, "weeklyReflection": true
          },
          "insightStatus": [],
          "hasCompletedOnboarding": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(Record.self, from: json)

        #expect(record.removedImports == nil)
        #expect(record.hasCompletedOnboarding)
        // `logPrompts` is in that JSON and no longer exists on `Profile`. An
        // unknown key decodes fine, where a missing one would not — which is the
        // whole reason the field was replaced rather than repurposed.
        #expect(record.profile.logReminder == nil)
        #expect(record.profile.logReminderFrequency == .off)
    }
}
