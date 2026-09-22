import Testing
import Foundation
@testable import Hourss

/// What survives closing the app.
///
/// Until this existed, nothing did: every session, rating and priority lived in
/// memory, so the app walked somebody through onboarding on every launch and lost
/// whatever they had logged. These are the assertions that keep that from coming
/// back quietly.
@Suite("Persistence")
@MainActor
struct PersistenceTests {

    private func temporaryURL() -> URL {
        URL.temporaryDirectory.appending(path: "hourss-test-\(UUID().uuidString).json")
    }

    @Test("A logged session survives a relaunch")
    func sessionSurvives() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = HourssStore(repository: FileRecordRepository(url: url))
        let activity = try #require(first.activities.first)
        let session = first.startSession(activityId: activity.id)
        first.stopSession(session.id)
        first.saveReflection(sessionId: session.id, feeling: 4, performance: 3, note: "kept")

        // A second store over the same file is what a relaunch is.
        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.sessions.count == 1)
        #expect(second.reflections[session.id]?.feelingScore == 4)
        #expect(second.reflections[session.id]?.note == "kept")
    }

    @Test("Onboarding is not walked twice")
    func onboardingSurvives() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = HourssStore(repository: FileRecordRepository(url: url))
        #expect(first.hasCompletedOnboarding == false)
        first.hasCompletedOnboarding = true
        first.profile.priorities = [.focus, .energy]
        first.persist()

        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.hasCompletedOnboarding)
        #expect(second.profile.priorities == [.focus, .energy])
    }

    @Test("A deleted session stays deleted")
    func deletionSurvives() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = HourssStore(repository: FileRecordRepository(url: url))
        let activity = try #require(first.activities.first)
        let session = first.startSession(activityId: activity.id)
        first.stopSession(session.id)
        first.deleteSession(session.id)

        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.sessions.isEmpty)
    }

    @Test("A first run is not an error")
    func missingFileStartsEmpty() throws {
        let url = temporaryURL()
        let repository = FileRecordRepository(url: url)
        let record = try repository.load()
        #expect(record.sessions.isEmpty)
        #expect(record.hasCompletedOnboarding == false)
        #expect(record.schemaVersion == Record.currentSchemaVersion)
    }

    /// A record that cannot be read is a bug to fix, not a reason to refuse to
    /// open: starting empty loses the history, and refusing to launch loses it
    /// too and takes the app with it.
    @Test("An unreadable record does not stop the app opening")
    func corruptFileDoesNotCrash() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all".utf8).write(to: url)

        let store = HourssStore(repository: FileRecordRepository(url: url))
        #expect(store.sessions.isEmpty)
        #expect(store.activities.isEmpty == false, "the starter activities should still be there")
    }

    @Test("Insights are recomputed rather than stored, and their status is kept")
    func statusSurvivesWithoutStoringInsights() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let person = SyntheticCohort.afternoonSlump
        let first = HourssStore(repository: FileRecordRepository(url: url))
        first.activities = person.activities
        first.sessions = person.sessions
        first.reflections = person.reflections
        first.rebuildInsights()
        let target = try #require(first.insights.first)
        first.setStatus(.saved, for: target.id)

        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.insights.isEmpty == false, "insights should be recomputed on load")
        #expect(second.insights.first { $0.id == target.id }?.status == .saved)

        // And the claims themselves are not in the file.
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("\"statement\""), "an insight's text was written to disk")
    }

    @Test("The schema version is written from the first save")
    func schemaVersionIsPresent() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileRecordRepository(url: url).save(Record())
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\"schemaVersion\" : \(Record.currentSchemaVersion)"))
        #expect(Record.currentSchemaVersion == 2, "version 2 added the frozen physiology readings")
    }

    @Test("A record round-trips through the file unchanged")
    func roundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var record = Record()
        record.activities = Activity.defaults
        record.profile.priorities = [.sleep, .calm]
        record.profile.workdays = [2, 3, 4]
        record.hasCompletedOnboarding = true

        let repository = FileRecordRepository(url: url)
        try repository.save(record)
        let read = try repository.load()

        #expect(read.activities.map(\.name) == Activity.defaults.map(\.name))
        #expect(read.profile.priorities == [.sleep, .calm])
        #expect(read.profile.workdays == [2, 3, 4])
        #expect(read.hasCompletedOnboarding)
    }
}
