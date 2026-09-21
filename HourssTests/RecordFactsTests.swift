import Testing
import Foundation
@testable import Hourss

/// The half of the fact pool that grows.
@Suite("Facts from the record")
struct RecordFactsTests {

    private let activity = UUID()
    private func name(_: UUID) -> String { "Deep work" }

    private func session(minutes: Int,
                         hoursAgo: Int,
                         kind: HealthKind? = nil,
                         intention: String? = nil) -> Session {
        let start = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return Session(
            activityId: activity,
            startAt: start,
            endAt: start.addingTimeInterval(Double(minutes) * 60),
            intention: intention,
            healthKind: kind
        )
    }

    /// Five is the floor, and four is not four-fifths of a fact. A superlative
    /// over a sample that has not had the chance to be beaten says nothing.
    @Test("A record too thin for a superlative produces none")
    func thinRecordSaysNothing() {
        let sessions = (1...RecordFacts.minimumSessions - 1).map {
            session(minutes: 30 * $0, hoursAgo: $0 * 5)
        }
        #expect(RecordFacts.pool(sessions: sessions, activityName: name).isEmpty)
    }

    @Test("The longest stretch is the one reported")
    func longestWins() throws {
        let sessions = [
            session(minutes: 30, hoursAgo: 40),
            session(minutes: 155, hoursAgo: 30),
            session(minutes: 45, hoursAgo: 20),
            session(minutes: 60, hoursAgo: 10),
            session(minutes: 25, hoursAgo: 5),
        ]
        let fact = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)

        #expect(fact.figure == "2h 35m", Comment(rawValue: "figure was \(fact.figure)"))
        #expect(fact.sentence.contains("out of 5 sessions"), Comment(rawValue: fact.sentence))
        #expect(fact.kind == .best)
        if case .record(let topic) = fact.subject {
            #expect(topic == .length)
        } else {
            Issue.record("subject was not a record subject")
        }
    }

    /// A night is always the longest thing in a day and nobody logged it.
    /// Reporting it would credit the watch's work to the person, and would say
    /// the same thing every time it fired.
    @Test("Imported sleep is never the longest stretch")
    func sleepIsExcluded() throws {
        let logged = (1...5).map { session(minutes: 20 * $0, hoursAgo: $0 * 5) }
        let night = session(minutes: 7 * 60 + 30, hoursAgo: 60, kind: .sleep)
        let fact = try #require(RecordFacts.pool(sessions: logged + [night], activityName: name).first)

        #expect(fact.figure == "1h 40m", Comment(rawValue:
            "reported \(fact.figure) — the night, which nobody logged"))
        #expect(fact.sentence.contains("out of 5 sessions"), Comment(rawValue: fact.sentence))
    }

    /// The sentence names what the person called it, not what the activity is
    /// called, when they said something.
    @Test("An intention is used ahead of the activity's name")
    func intentionWins() throws {
        var sessions = (1...4).map { session(minutes: 10 * $0, hoursAgo: $0 * 5) }
        sessions.append(session(minutes: 200, hoursAgo: 2, intention: "Write the hard thing"))
        let fact = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)

        #expect(fact.sentence.hasPrefix("Write the hard thing"), Comment(rawValue: fact.sentence))
    }

    /// Determinism is a tested property of the Health pool and this one is sorted
    /// into the same list, so an exact tie cannot be resolved by luck.
    @Test("An exact tie resolves the same way every run")
    func tiesAreStable() throws {
        let sessions = [
            session(minutes: 90, hoursAgo: 30),
            session(minutes: 90, hoursAgo: 10),
            session(minutes: 20, hoursAgo: 8),
            session(minutes: 20, hoursAgo: 6),
            session(minutes: 20, hoursAgo: 4),
        ]
        let first = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)
        let second = try #require(RecordFacts.pool(sessions: sessions.reversed(), activityName: name).first)
        #expect(first.sentence == second.sentence)
        #expect(first.figure == second.figure)
    }

    /// The rule the whole file rests on: a superlative reports one row, so it
    /// asserts no relationship and needs no evidence gate. Anything comparative
    /// would belong to the engine instead.
    @Test("Nothing in a record fact claims a relationship")
    func noRelationalLanguage() {
        let sessions = (1...6).map { session(minutes: 15 * $0, hoursAgo: $0 * 4) }
        for fact in RecordFacts.pool(sessions: sessions, activityName: name) {
            let words = "\(fact.figure) \(fact.sentence)".lowercased()
            for banned in ["because", "causes", "leads to", "makes you", "due to",
                           "when you", "on days", "after a", "correlat", "linked",
                           "average", "most people", "typical", "normal",
                           "you should", "try ", "unusually"] {
                #expect(!words.contains(banned), Comment(rawValue: "\"\(words)\" contains \"\(banned)\""))
            }
        }
    }

    /// A record subject has no `HealthGroup`, and that is what keeps it out of
    /// the consent scope and out of the engine's factor space.
    @Test("A record fact belongs to no Health group")
    func noHealthGroup() throws {
        let sessions = (1...6).map { session(minutes: 15 * $0, hoursAgo: $0 * 4) }
        let fact = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)
        #expect(fact.subject.healthGroup == nil)
        #expect(fact.subject.key == "record.length")
        #expect(DailyFact.key(for: fact) == "record.length.best")
    }

    /// The key format has three components for a record fact and two for a
    /// Health one, so the dispenser has to read the kind off the end. Splitting
    /// from the front silently disabled variety control for record facts.
    @Test("A record key is taken apart from the end")
    func keysSplitFromTheEnd() throws {
        let health = try #require(DailyFact.parts(ofKey: "steps.drift"))
        #expect(health.subject == "steps" && health.kind == "drift")

        let record = try #require(DailyFact.parts(ofKey: "record.length.best"))
        #expect(record.subject == "record.length" && record.kind == "best")

        #expect(DailyFact.pair(ofKey: "record.length.best") == "record.length.best")
    }

    /// Record facts are offered ahead of Health facts because they are the ones
    /// that exist as a result of logging. Ranked together they would sort last
    /// and arrive five weeks late.
    @Test("The record is offered before the watch")
    func recordLeads() throws {
        let sessions = (1...6).map { session(minutes: 15 * $0, hoursAgo: $0 * 4) }
        let record = RecordFacts.pool(sessions: sessions, activityName: name)
        let health = HealthDigest.pool(from: [
            .sleepHours: Dictionary(uniqueKeysWithValues: (0..<40).map {
                (Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double($0) * 86_400)),
                 Double(7 + ($0 % 3)))
            }),
        ])
        #expect(!record.isEmpty && !health.isEmpty, "both pools need content for this to mean anything")

        let defaults = UserDefaults(suiteName: "record-leads-\(UUID().uuidString)")!
        let chosen = try #require(DailyFact(defaults: defaults)
            .fact(for: Calendar.current.startOfDay(for: Date()), record: record, from: health))
        #expect(chosen.subject.healthGroup == nil, Comment(rawValue:
            "led with \"\(chosen.sentence)\" — a Health fact ahead of the record"))
    }
}
