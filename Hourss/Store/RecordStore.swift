import Foundation

/// Everything Hourss keeps between launches.
///
/// Deliberately small. Insights are absent because they are derived — the engine
/// recomputes them from these sessions on every launch, and storing a claim
/// alongside the data it came from is how the two drift apart. Health is absent
/// because HealthKit already holds it and re-reads it.
///
/// What survives of an insight is only what belongs to the person rather than to
/// the computation: whether they saved or hid it, keyed by the stable hypothesis
/// identity that made keying possible at all.
struct Record: Codable {
    /// Written on every save, read before anything else.
    ///
    /// Present from the first version, when it is useless, because the moment it
    /// is needed is the moment somebody already has a file without it. Migration
    /// then becomes a decision rather than a discovery.
    var schemaVersion: Int = Record.currentSchemaVersion
    static let currentSchemaVersion = 1

    var activities: [Activity] = []
    var sessions: [Session] = []
    var reflections: [UUID: Reflection] = [:]
    var profile: Profile = Profile()
    var insightStatus: [UUID: InsightStatus] = [:]
    var hasCompletedOnboarding = false

    /// Imported blocks the person deleted, by their Health identifier.
    ///
    /// Kept because the importer runs again on every launch, and without this the
    /// next run puts back exactly what somebody just threw away — which reads as
    /// the app overruling them, and is the fastest way to make an automatic
    /// feature feel like something being done *to* you.
    ///
    /// Optional so that records written before the importer existed still decode:
    /// a synthesized `Codable` fails on a missing key for a non-optional property
    /// however sensible its default looks.
    var removedImports: [String]?
}

/// Where the record lives.
///
/// A protocol with one implementation, which is usually a smell. It is here on
/// purpose: the record is a file today because the whole of it fits in memory and
/// nothing ever queries it, and both of those could stop being true. A database,
/// or CloudKit, would be another conformance and no change at any call site —
/// which is the difference between a migration and a rewrite.
protocol RecordRepository: Sendable {
    func load() throws -> Record
    func save(_ record: Record) throws
}

/// The record as a single JSON file.
///
/// Sessions are a few hundred bytes each, so a year of heavy logging is a few
/// hundred kilobytes and a decade is a few megabytes — small enough that reading
/// the lot at launch costs less than the animation covering it. A database would
/// be solving durability and migration here rather than volume, and both of those
/// are solved below.
struct FileRecordRepository: RecordRepository {
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL
    }

    /// Application Support rather than Documents: this is the app's own record
    /// rather than a document somebody manages, and Documents would expose it in
    /// Files for a person to rename or delete by accident.
    static var defaultURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL.documentsDirectory
        return base.appending(path: "hourss-record.json")
    }

    func load() throws -> Record {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            // A first run, which is not an error and must not read as one.
            return Record()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Record.self, from: data)
    }

    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        // ISO 8601 rather than the default seconds-since-2001. The record is
        // somebody's own history and should be legible if they ever open it, and
        // a date that reads as a date survives being looked at by another tool.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(record)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Atomic, so a crash during the write leaves the previous record intact
        // rather than half a file. Without this a badly-timed termination costs
        // somebody everything they have logged.
        try data.write(to: url, options: [.atomic])
    }
}

/// A repository that keeps the record in memory.
///
/// For tests, and for the fixture. Nothing here touches a disk, so a test can
/// exercise saving and loading without leaving anything behind or depending on
/// what a previous test left.
final class InMemoryRecordRepository: RecordRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var record: Record

    init(_ record: Record = Record()) { self.record = record }

    func load() throws -> Record {
        lock.withLock { record }
    }

    func save(_ record: Record) throws {
        lock.withLock { self.record = record }
    }
}
