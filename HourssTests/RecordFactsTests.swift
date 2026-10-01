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
        // The spent key carries a revision, so the stored entry names *which*
        // session holds the record. The subject and kind are still the whole of
        // its identity for variety purposes — see `pair(ofKey:)`.
        #expect(DailyFact.key(for: fact).hasPrefix("record.length.best#"), Comment(rawValue:
            "keyed \(DailyFact.key(for: fact))"))
        #expect(DailyFact.pair(ofKey: DailyFact.key(for: fact)) == "record.length.best")
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
        // A weekend contrast, because the Health half of this fixture has to
        // produce a fact for the comparison to mean anything. It used to be a
        // three-day cycle of 7, 8 and 9 hours, which carried no pattern at all and
        // yielded exactly one fact: the totals card. That card has been removed, so
        // the fixture now has to contain something a generator can find.
        let calendar = Calendar.current
        let health = HealthDigest.pool(from: [
            .sleepHours: Dictionary(uniqueKeysWithValues: (0..<40).map { offset in
                let day = calendar.startOfDay(for: Date().addingTimeInterval(-Double(offset) * 86_400))
                let weekday = calendar.component(.weekday, from: day)
                return (day, weekday == 1 || weekday == 7 ? 8.6 : 7.0)
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

/// The half that has to keep growing after it has been read once.
@Suite("Record facts as the record changes")
struct RecordFactRevisionTests {

    private let activity = UUID()
    private func name(_: UUID) -> String { "Deep work" }

    private func session(minutes: Int, hoursAgo: Int) -> Session {
        let start = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return Session(activityId: activity, startAt: start,
                       endAt: start.addingTimeInterval(Double(minutes) * 60))
    }

    private func scratch() -> UserDefaults {
        UserDefaults(suiteName: "record-revision-\(UUID().uuidString)")!
    }

    private func day(_ back: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -back,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    /// The whole point of the record half: beating your own longest stretch is
    /// news, and a key that ignored which session held it would have said so once
    /// and then never again.
    @Test("Beating a record makes it a fact again")
    func beatingARecordIsANewFact() throws {
        let base = (1...5).map { session(minutes: 20 * $0, hoursAgo: $0 * 5) }
        let before = try #require(
            RecordFacts.pool(sessions: base, activityName: name)
                .first { $0.subject.key == "record.length" })

        let beaten = base + [session(minutes: 400, hoursAgo: 2)]
        let after = try #require(
            RecordFacts.pool(sessions: beaten, activityName: name)
                .first { $0.subject.key == "record.length" })

        #expect(DailyFact.key(for: before) != DailyFact.key(for: after), Comment(rawValue:
            "both keyed \(DailyFact.key(for: before)) — the new record could never be shown"))
    }

    /// And the converse, which is what stops it becoming a nag: rebuilding the
    /// pool over an unchanged record has to produce the same key.
    @Test("An unchanged record is the same fact")
    func unchangedRecordIsTheSameFact() throws {
        let sessions = (1...6).map { session(minutes: 20 * $0, hoursAgo: $0 * 5) }
        let first = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)
        let second = try #require(RecordFacts.pool(sessions: sessions, activityName: name).first)
        #expect(DailyFact.key(for: first) == DailyFact.key(for: second))
    }

    /// Two facts about different longest sessions are still one topic and one
    /// shape, so the variety rules must treat them as a repeat even though they
    /// are distinct entries in the spent list.
    @Test("A revision does not buy a second turn at the same topic")
    func revisionsShareAVarietyPair() {
        let a = "record.length.best#one"
        let b = "record.length.best#two"
        #expect(DailyFact.pair(ofKey: a) == DailyFact.pair(ofKey: b))
        #expect(DailyFact.pair(ofKey: a) == "record.length.best")
        #expect(DailyFact.base(ofKey: a) == "record.length.best")
    }

    /// The kind still has to be readable off the end once a revision is attached,
    /// which is why the discriminator uses a separator the key never otherwise
    /// contains.
    @Test("A revision does not break the parse")
    func revisionSurvivesParsing() throws {
        let parts = try #require(DailyFact.parts(ofKey: "record.length.best#ABC-123"))
        #expect(parts.subject == "record.length")
        #expect(parts.kind == "best")

        let health = try #require(DailyFact.parts(ofKey: "steps.drift"))
        #expect(health.subject == "steps" && health.kind == "drift")
    }

    /// A record holder that has already been shown is not shown again, and the
    /// dispenser moves on to something else rather than repeating itself.
    @Test("A spent record fact is not dispensed twice")
    func spentRecordFactIsNotRepeated() throws {
        let sessions = (1...6).map { session(minutes: 20 * $0, hoursAgo: $0 * 5) }
        let record = RecordFacts.pool(sessions: sessions, activityName: name)
        #expect(record.count > 1, "this test needs more than one record fact to be meaningful")

        let dispenser = DailyFact(defaults: scratch())
        let first = try #require(dispenser.fact(for: day(1), record: record, from: []))
        let second = try #require(dispenser.fact(for: day(0), record: record, from: []))
        #expect(DailyFact.key(for: first) != DailyFact.key(for: second))
    }
}

/// The generator that was argued against and built anyway.
///
/// These tests are the written form of the concessions listed above
/// `RecordFacts.daysInARow`: the number is the longest run and not the current
/// one, it is arithmetic over the record and nothing else, and the sentence says
/// what happened and stops. A change that makes any of them fail is a change to
/// the decision, not to the code.
@Suite("Days in a row")
struct RecordStreakTests {

    private let activity = UUID()
    private func name(_: UUID) -> String { "Deep work" }

    private let calendar = Calendar.current

    /// A fixed calendar day, so nothing here depends on when the suite runs.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func session(on day: Date, minutes: Int = 30,
                         kind: HealthKind? = nil) -> Session {
        Session(
            activityId: activity,
            startAt: day,
            endAt: day.addingTimeInterval(Double(minutes) * 60),
            healthKind: kind
        )
    }

    private func streak(_ sessions: [Session]) -> HealthDigest.Fact? {
        RecordFacts.pool(sessions: sessions, activityName: name)
            .first { $0.subject.key == "record.daysInARow" }
    }

    /// The arithmetic, with a gap in it. Five days in the record, three of them
    /// touching, and the answer is three rather than five.
    @Test("A gap ends a run")
    func gapEndsARun() throws {
        let sessions = [
            session(on: date(2026, 1, 5)),
            session(on: date(2026, 1, 6)),
            session(on: date(2026, 1, 7)),
            session(on: date(2026, 1, 10)),
            session(on: date(2026, 1, 11)),
        ]
        let fact = try #require(streak(sessions))

        #expect(fact.figure == "3 days", Comment(rawValue: "figure was \(fact.figure)"))
        #expect(fact.sentence.contains("out of 5 days"), Comment(rawValue: fact.sentence))
        #expect(fact.kind == .best)
        #expect(fact.strength == 0.05)
        #expect(fact.subject.healthGroup == nil)
        #expect(fact.subject.title == "Days in a row")
    }

    /// Everything on one day is one day. A record with no second day in it has no
    /// run to report, and reporting "1 day in a row" would be the app filling
    /// silence with arithmetic.
    @Test("A record held on a single day yields no run")
    func singleDayYieldsNothing() {
        let day = date(2026, 3, 2)
        let sessions = (0..<5).map { session(on: day.addingTimeInterval(Double($0) * 3600)) }
        #expect(streak(sessions) == nil)
    }

    /// And the same when the days never touch: five days apiece, every one of
    /// them alone.
    @Test("Days that never touch yield no run")
    func scatteredDaysYieldNothing() {
        let sessions = [1, 3, 5, 7, 9].map { session(on: date(2026, 4, $0)) }
        #expect(streak(sessions) == nil)
    }

    /// A month boundary is not a gap. January has 31 days, February follows it,
    /// and a run across the join is one run.
    @Test("A run crosses a month boundary")
    func runCrossesAMonthBoundary() throws {
        let sessions = [
            session(on: date(2026, 1, 30)),
            session(on: date(2026, 1, 30, hour: 15)),
            session(on: date(2026, 1, 31)),
            session(on: date(2026, 2, 1)),
            session(on: date(2026, 2, 2)),
        ]
        let fact = try #require(streak(sessions))

        #expect(fact.figure == "4 days", Comment(rawValue: "figure was \(fact.figure)"))
        // Four distinct days out of five sessions: two on the 30th are one day.
        #expect(fact.sentence.contains("out of 4 days"), Comment(rawValue: fact.sentence))
    }

    /// The same across the end of a year, which is the boundary any arithmetic
    /// on month numbers gets wrong.
    @Test("A run crosses a year boundary")
    func runCrossesAYearBoundary() throws {
        let sessions = [
            session(on: date(2025, 12, 30)),
            session(on: date(2025, 12, 31)),
            session(on: date(2026, 1, 1)),
            session(on: date(2026, 1, 2)),
            session(on: date(2026, 1, 3)),
        ]
        let fact = try #require(streak(sessions))
        #expect(fact.figure == "5 days", Comment(rawValue: "figure was \(fact.figure)"))
    }

    /// Nights are the watch's record, not the person's, and a run of them would
    /// be a run of days somebody wore a charged watch.
    @Test("Imported sleep does not build or extend a run")
    func sleepDoesNotCount() throws {
        let logged = [
            session(on: date(2026, 5, 4)),
            session(on: date(2026, 5, 5)),
            session(on: date(2026, 5, 6)),
            session(on: date(2026, 5, 20)),
            session(on: date(2026, 5, 22)),
        ]
        // A night on each of the days that would have joined the run to the
        // stragglers, if nights counted.
        let nights = (7...19).map {
            session(on: date(2026, 5, $0, hour: 1), minutes: 7 * 60, kind: .sleep)
        }
        let fact = try #require(streak(logged + nights))

        #expect(fact.figure == "3 days", Comment(rawValue:
            "reported \(fact.figure) — nights nobody logged are in the run"))
        #expect(fact.sentence.contains("out of 5 days"), Comment(rawValue: fact.sentence))
    }

    /// The point of a revision: a longer run is news, and a key that ignored the
    /// number would have said "three" once and never mentioned four.
    @Test("A longer run is a new fact")
    func longerRunIsANewFact() throws {
        let base = (5...7).map { session(on: date(2026, 6, $0)) }
            + [session(on: date(2026, 6, 12)), session(on: date(2026, 6, 20))]
        let before = try #require(streak(base))

        let grown = base + [session(on: date(2026, 6, 8))]
        let after = try #require(streak(grown))

        #expect(before.figure == "3 days")
        #expect(after.figure == "4 days")
        #expect(DailyFact.key(for: before) != DailyFact.key(for: after), Comment(rawValue:
            "both keyed \(DailyFact.key(for: before)) — the longer run could never be shown"))
    }

    /// And the converse, which is what stops it nagging: logging more without
    /// beating the run is the same fact, and a run of equal length appearing
    /// again is the same number.
    @Test("A run that has not grown is the same fact")
    func unchangedRunIsTheSameFact() throws {
        let base = (5...7).map { session(on: date(2026, 7, $0)) }
            + [session(on: date(2026, 7, 12)), session(on: date(2026, 7, 20))]
        let before = try #require(streak(base))

        // Another three in a row, later on. Same number, so nothing new is said.
        let repeated = base + (14...16).map { session(on: date(2026, 7, $0)) }
        let after = try #require(streak(repeated))

        #expect(after.figure == "3 days")
        #expect(DailyFact.key(for: before) == DailyFact.key(for: after), Comment(rawValue:
            "\(DailyFact.key(for: before)) became \(DailyFact.key(for: after)) — "
            + "an unchanged run would be dispensed twice"))
    }

    /// The copy sweep. The objection this generator was built over was about what
    /// a streak makes an app say, so this is the test that holds the concession:
    /// no instruction, no second person imperative, nothing about tomorrow or
    /// about continuing, and not the word that carries the thing somebody loses.
    @Test("The sentence states a count and stops")
    func copyIsAStatementOfWhatHappened() throws {
        let sessions = (5...9).map { session(on: date(2026, 8, $0)) }
        let fact = try #require(streak(sessions))
        let words = "\(fact.subject.title) \(fact.figure) \(fact.sentence)".lowercased()

        for banned in [
            // The vocabulary lists the narration guard sweeps for.
            "because", "causes", "leads to", "makes you", "due to", "results in",
            "average", "most people", "typical", "normal", "everyone",
            "stress", "mood", "healthy", "energy level",
            "you should", "should", "try", "consider", "aim for", "aim to",
            "avoid", "make sure", "keep doing", "stick to", "start doing",
            "remember to", "be sure", "ensure", "recommend", "suggest",
            // And what this fact in particular could reach for.
            "streak", "tomorrow", "today", "so far today", "keep it up",
            "keep going", "don't break", "do not break", "goal", "target",
            "continue", "maintain", "on track", "in a row now", "current",
            "next", "still", "again", "best yet", "congratulations", "well done",
        ] {
            #expect(!words.contains(banned), Comment(rawValue: "\"\(words)\" contains \"\(banned)\""))
        }

        // No second person imperative: the sentence talks about a record, and the
        // only "you" it is allowed is the possessive naming whose record it is.
        #expect(fact.sentence.contains("your record"), Comment(rawValue: fact.sentence))
        #expect(!fact.sentence.lowercased().contains("you have to"))
        #expect(!fact.sentence.lowercased().contains("you can"))
    }

    /// Determinism, which for this generator also means the clock cannot reach
    /// it: the same record in any order gives the same number, and nothing about
    /// the number is relative to now.
    @Test("The same record gives the same run in any order")
    func runIsDeterministic() throws {
        let sessions = [
            session(on: date(2026, 9, 3)),
            session(on: date(2026, 9, 4)),
            session(on: date(2026, 9, 5)),
            session(on: date(2026, 9, 9)),
            session(on: date(2026, 9, 10)),
            session(on: date(2026, 9, 14)),
        ]
        let forwards = try #require(streak(sessions))
        let backwards = try #require(streak(sessions.reversed()))
        let shuffled = try #require(streak(sessions.shuffled()))

        for other in [backwards, shuffled] {
            #expect(forwards.figure == other.figure)
            #expect(forwards.sentence == other.sentence)
            #expect(forwards.revision == other.revision)
            #expect(DailyFact.key(for: forwards) == DailyFact.key(for: other))
        }
    }

    /// A new topic widens the rotation, which is the reason a fourth generator
    /// was worth having at all — the variety axis is the topic and the shape.
    @Test("The run is its own topic in the rotation")
    func runIsItsOwnVarietyPair() throws {
        let sessions = (5...9).map { session(on: date(2026, 10, $0)) }
        let fact = try #require(streak(sessions))

        #expect(DailyFact.pair(of: fact) == "record.daysInARow.best")
        #expect(DailyFact.parts(ofKey: DailyFact.key(for: fact))?.subject == "record.daysInARow")
        #expect(DailyFact.parts(ofKey: DailyFact.key(for: fact))?.kind == "best")
    }
}

/// The three generators added after the first four, and the one that was removed
/// to make room for them.
///
/// Every suite here holds the same five properties per generator, because they are
/// the five ways a record fact goes wrong: the arithmetic, the minimum below which
/// it says nothing, the revision changing when the answer changes *and not when it
/// has not*, determinism, and the copy. The third of those is the one that bites
/// in production — a revision that moves too eagerly turns a fact into a card
/// somebody sees every day, and one that never moves shows it once and never
/// again.
@Suite("Facts the record grew")
struct RecordGrowthTests {

    private let calendar = Calendar.current

    private let work = UUID()
    private let reading = UUID()

    /// Two activities, named the way a person would. Deliberately ordinary words:
    /// the copy sweep below reads the whole sentence, and the sentence contains a
    /// name the *person* chose rather than one the app wrote — "Carpentry" would
    /// be refused by a naive substring search for "try", which is the exact
    /// failure `NarrationGuard.flatten` exists to prevent.
    private func name(_ id: UUID) -> String { id == reading ? "Reading" : "Deep work" }

    /// A fixed instant, so nothing here depends on when the suite runs.
    private func at(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int = 9, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: hour, minute: minute))!
    }

    private func session(_ start: Date, minutes: Int = 30,
                         activity: UUID? = nil, kind: HealthKind? = nil) -> Session {
        Session(activityId: activity ?? work, startAt: start,
                endAt: start.addingTimeInterval(Double(minutes) * 60),
                healthKind: kind)
    }

    /// One fact out of the pool, by subject. Every session is rated, because the
    /// one generator that needs ratings should not be the reason another suite's
    /// fixture has to carry them.
    private func recordFact(_ key: String, _ sessions: [Session]) -> HealthDigest.Fact? {
        RecordFacts.pool(sessions: sessions, feeling: { _ in 3 },
                         activityName: name, calendar: calendar)
            .first { $0.subject.key == key }
    }

    // MARK: - A week's total

    /// Seven days apart, so these are four distinct weeks wherever the suite runs
    /// — `firstWeekday` is Monday in much of Europe, Sunday in the US and Saturday
    /// in parts of the Gulf, and only "seven days apart" is true under all of them. Two
    /// sessions on *one day* are always in one week; two on consecutive days are
    /// not, which is why the fuller week is made fuller that way.
    private var fourWeeks: [Session] {
        [
            session(at(2026, 1, 7), minutes: 30),
            session(at(2026, 1, 14, 9), minutes: 60),
            session(at(2026, 1, 14, 14), minutes: 90),
            session(at(2026, 1, 21), minutes: 45),
            session(at(2026, 1, 28), minutes: 20),
        ]
    }

    @Test("The fullest week is the one reported")
    func fullestWeekWins() throws {
        let fact = try #require(recordFact("record.weekTotal", fourWeeks))

        // The week's sum — 60 + 90 — rather than its longest session or the
        // record's total, which are the two numbers this could have been.
        #expect(fact.figure == "2h 30m", Comment(rawValue: "figure was \(fact.figure)"))
        #expect(fact.sentence.contains("out of 4 weeks"), Comment(rawValue: fact.sentence))
        #expect(fact.kind == .best)
        #expect(fact.strength == 0.05)
        #expect(fact.subject.healthGroup == nil)
        #expect(fact.subject.title == "A week's total")
    }

    /// Below the floor nothing is said, and the rest of the pool is unaffected —
    /// a generator declining is not the pool failing.
    @Test("Two weeks is not enough for a fullest week")
    func twoWeeksSayNothing() {
        let sessions = (0..<3).map { session(at(2026, 2, 3, 9 + $0), minutes: 30) }
            + (0..<2).map { session(at(2026, 2, 10, 9 + $0), minutes: 45) }
        #expect(recordFact("record.weekTotal", sessions) == nil)
        #expect(recordFact("record.length", sessions) != nil, "the rest of the pool went with it")
    }

    /// Nights are the watch's record. A fortnight of them in one week must not
    /// make that week the fullest, and must not count as a week at all.
    @Test("Imported nights do not fill a week")
    func nightsDoNotFillAWeek() throws {
        let nights = (20...23).map {
            session(at(2026, 1, $0, 1), minutes: 7 * 60, kind: .sleep)
        }
        let fact = try #require(recordFact("record.weekTotal", fourWeeks + nights))

        #expect(fact.figure == "2h 30m", Comment(rawValue:
            "reported \(fact.figure) — nights nobody logged are in the total"))
        #expect(fact.sentence.contains("out of 4 weeks"), Comment(rawValue: fact.sentence))
    }

    @Test("A different week taking the lead is a new fact")
    func newLeadingWeekIsANewFact() throws {
        let before = try #require(recordFact("record.weekTotal", fourWeeks))
        let after = try #require(recordFact("record.weekTotal",
                                      fourWeeks + [session(at(2026, 1, 21, 11), minutes: 200)]))

        #expect(before.figure == "2h 30m")
        #expect(after.figure == "4h 5m", Comment(rawValue: "figure was \(after.figure)"))
        #expect(DailyFact.key(for: before) != DailyFact.key(for: after), Comment(rawValue:
            "both keyed \(DailyFact.key(for: before)) — the new fullest week could never be shown"))
    }

    /// The nag test, and the reason the revision names the week rather than its
    /// total. The leading week is usually the one somebody is standing in, so its
    /// total grows every time they log; if that counted as a new answer this card
    /// would arrive on six consecutive days.
    @Test("The leading week getting fuller is the same fact")
    func fullerLeadingWeekIsTheSameFact() throws {
        let before = try #require(recordFact("record.weekTotal", fourWeeks))
        let after = try #require(recordFact("record.weekTotal",
                                      fourWeeks + [session(at(2026, 1, 14, 17), minutes: 25)]))

        #expect(after.figure == "2h 55m", Comment(rawValue: "figure was \(after.figure)"))
        #expect(DailyFact.key(for: before) == DailyFact.key(for: after), Comment(rawValue:
            "\(DailyFact.key(for: before)) became \(DailyFact.key(for: after)) — "
            + "the same week would be announced again every time it grew"))
    }

    @Test("The same record gives the same week in any order")
    func weekIsDeterministic() throws {
        let forwards = try #require(recordFact("record.weekTotal", fourWeeks))
        for other in [Array(fourWeeks.reversed()), fourWeeks.shuffled()] {
            let fact = try #require(recordFact("record.weekTotal", Array(other)))
            #expect(fact.figure == forwards.figure)
            #expect(fact.sentence == forwards.sentence)
            #expect(fact.revision == forwards.revision)
        }
    }

    // MARK: - Kinds of activity

    /// Reading arrives third but is the newest *kind*, because what is compared is
    /// the first session of each activity and not the last. The two Deep work
    /// sessions after it are the part a naive "most recent session" would get
    /// wrong.
    private var twoActivities: [Session] {
        [
            session(at(2026, 3, 2), activity: work),
            session(at(2026, 3, 3), activity: work),
            session(at(2026, 3, 4), activity: reading),
            session(at(2026, 3, 5), activity: work),
            session(at(2026, 3, 6), activity: reading),
        ]
    }

    @Test("The newest kind of activity is the one named")
    func newestActivityWins() throws {
        let fact = try #require(recordFact("record.activities", twoActivities))

        #expect(fact.figure == "2", Comment(rawValue: "figure was \(fact.figure)"))
        #expect(fact.sentence == "Reading is the newest of the 2 kinds of activity "
                + "in your record, across 5 sessions.", Comment(rawValue: fact.sentence))
        #expect(fact.kind == .best)
        #expect(fact.strength == 0.05)
        #expect(fact.subject.healthGroup == nil)
        #expect(fact.subject.title == "Kinds of activity")
    }

    @Test("One kind of activity is not a newest kind")
    func oneActivitySaysNothing() {
        let sessions = (2...6).map { session(at(2026, 4, $0), activity: work) }
        #expect(recordFact("record.activities", sessions) == nil)
        #expect(recordFact("record.length", sessions) != nil, "the rest of the pool went with it")
    }

    /// Grouped by id, so renaming an activity is not trying a new one. The
    /// sentence changes, because it names what the activity is called now; the
    /// fact does not, because nothing about the record did.
    @Test("Renaming an activity is not a new kind")
    func renamingIsNotANewKind() throws {
        let sessions = twoActivities
        let renamed = reading
        let before = try #require(
            RecordFacts.pool(sessions: sessions, activityName: name, calendar: calendar)
                .first { $0.subject.key == "record.activities" })
        let after = try #require(
            RecordFacts.pool(sessions: sessions,
                             activityName: { $0 == renamed ? "Books" : "Deep work" },
                             calendar: calendar)
                .first { $0.subject.key == "record.activities" })

        #expect(after.sentence.hasPrefix("Books"), Comment(rawValue: after.sentence))
        #expect(DailyFact.key(for: before) == DailyFact.key(for: after), Comment(rawValue:
            "\(DailyFact.key(for: before)) became \(DailyFact.key(for: after)) — "
            + "a rename would be announced as a new kind of activity"))
    }

    @Test("A kind the record has never held is a new fact")
    func aNewKindIsANewFact() throws {
        let before = try #require(recordFact("record.activities", twoActivities))
        let third = UUID()
        let after = try #require(recordFact("record.activities",
                                      twoActivities + [session(at(2026, 3, 7), activity: third)]))

        #expect(before.figure == "2")
        #expect(after.figure == "3")
        #expect(DailyFact.key(for: before) != DailyFact.key(for: after))
    }

    @Test("More of what is already there is the same fact")
    func moreOfTheSameKindsIsTheSameFact() throws {
        let before = try #require(recordFact("record.activities", twoActivities))
        let after = try #require(recordFact("record.activities", twoActivities + [
            session(at(2026, 3, 8), activity: reading),
            session(at(2026, 3, 9), activity: work),
        ]))
        #expect(DailyFact.key(for: before) == DailyFact.key(for: after))
    }

    @Test("The newest kind is the same in any order")
    func activitiesAreDeterministic() throws {
        let forwards = try #require(recordFact("record.activities", twoActivities))
        for other in [Array(twoActivities.reversed()), twoActivities.shuffled()] {
            let fact = try #require(recordFact("record.activities", Array(other)))
            #expect(fact.sentence == forwards.sentence)
            #expect(fact.revision == forwards.revision)
        }
    }

    /// Two activities first logged in the same second. Which one is "newest" is
    /// arbitrary, and the only thing that matters is that it is arbitrary the same
    /// way every run — a tie resolved by the order the store happened to hand the
    /// rows over would make this card flicker between two names on relaunch.
    @Test("A tie in first sessions resolves the same way every run")
    func firstSessionTiesAreStable() throws {
        // Both activities enter the record in the same second, so the tie is
        // between the two *first* sessions and not between two sessions of one
        // activity.
        let moment = at(2026, 5, 11, 10)
        let sessions = [
            session(moment, activity: work),
            session(moment, activity: reading),
            session(at(2026, 5, 12), activity: reading),
            session(at(2026, 5, 13), activity: work),
            session(at(2026, 5, 14), activity: work),
        ]
        let forwards = try #require(recordFact("record.activities", sessions))
        let backwards = try #require(recordFact("record.activities", Array(sessions.reversed())))
        #expect(forwards.sentence == backwards.sentence)
        #expect(forwards.revision == backwards.revision)
    }

    // MARK: - Earliest start

    /// The earliest *clock time*, which is not the earliest session: the record
    /// opens on the 6th at 09:15 and the answer is on the 7th at 06:12.
    private var fiveMornings: [Session] {
        [
            session(at(2026, 4, 6, 9, 15)),
            session(at(2026, 4, 7, 6, 12)),
            session(at(2026, 4, 8, 7, 40)),
            session(at(2026, 4, 9, 22, 5)),
            session(at(2026, 4, 10, 8, 0)),
        ]
    }

    /// The clock the generator formats with. Built here the same way rather than
    /// hardcoded, because "6:12 AM" is one locale's spelling of it and a test that
    /// pinned the string would fail in another region while the app was right. The
    /// arithmetic is pinned by the revision instead, which is minutes after
    /// midnight and the same number everywhere.
    private var clock: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened,
                         calendar: calendar, timeZone: calendar.timeZone)
    }

    @Test("The earliest start is the one reported")
    func earliestStartWins() throws {
        let fact = try #require(recordFact("record.earliestStart", fiveMornings))

        #expect(fact.revision == "372", Comment(rawValue:
            "revision was \(fact.revision ?? "nil") — 6:12 is 372 minutes after midnight"))
        #expect(fact.figure == at(2026, 4, 7, 6, 12).formatted(clock),
                Comment(rawValue: "figure was \(fact.figure)"))
        #expect(fact.figure != at(2026, 4, 6, 9, 15).formatted(clock),
                Comment(rawValue: "reported the first session rather than the earliest one"))
        #expect(fact.sentence.contains("out of 5 days"), Comment(rawValue: fact.sentence))
        #expect(fact.kind == .best)
        #expect(fact.strength == 0.05)
        #expect(fact.subject.healthGroup == nil)
        #expect(fact.subject.title == "Earliest start")
    }

    @Test("Two days is not enough for an earliest start")
    func twoDaysSayNothing() {
        let sessions = [at(2026, 5, 4, 7), at(2026, 5, 4, 9), at(2026, 5, 4, 11),
                        at(2026, 5, 5, 6), at(2026, 5, 5, 8)].map { session($0) }
        #expect(recordFact("record.earliestStart", sessions) == nil)
        #expect(recordFact("record.length", sessions) != nil, "the rest of the pool went with it")
    }

    /// Nights start at one in the morning and nobody logged them, so they would
    /// hold this record permanently if they counted.
    @Test("An imported night is never the earliest start")
    func nightsAreNotStarts() throws {
        let night = session(at(2026, 4, 8, 1, 5), minutes: 7 * 60, kind: .sleep)
        let fact = try #require(recordFact("record.earliestStart", fiveMornings + [night]))
        #expect(fact.revision == "372", Comment(rawValue:
            "revision was \(fact.revision ?? "nil") — the night is holding the record"))
    }

    @Test("An earlier start is a new fact")
    func anEarlierStartIsANewFact() throws {
        let before = try #require(recordFact("record.earliestStart", fiveMornings))
        let after = try #require(recordFact("record.earliestStart",
                                      fiveMornings + [session(at(2026, 4, 11, 5, 30))]))

        #expect(after.revision == "330")
        #expect(DailyFact.key(for: before) != DailyFact.key(for: after), Comment(rawValue:
            "both keyed \(DailyFact.key(for: before)) — the earlier start could never be shown"))
    }

    /// Both halves of "has not changed": a later start is not news, and neither is
    /// a second session at the same minute months later. The revision names the
    /// minute rather than the session precisely so the second case stays quiet.
    @Test("A start that does not beat it is the same fact")
    func aLaterStartIsTheSameFact() throws {
        let before = try #require(recordFact("record.earliestStart", fiveMornings))

        let laterOne = try #require(recordFact("record.earliestStart",
                                         fiveMornings + [session(at(2026, 4, 11, 11, 0))]))
        #expect(DailyFact.key(for: before) == DailyFact.key(for: laterOne))

        let matched = try #require(recordFact("record.earliestStart",
                                        fiveMornings + [session(at(2026, 7, 2, 6, 12))]))
        #expect(DailyFact.key(for: before) == DailyFact.key(for: matched), Comment(rawValue:
            "\(DailyFact.key(for: before)) became \(DailyFact.key(for: matched)) — "
            + "matching your earliest start would be announced as beating it"))
    }

    @Test("The earliest start is the same in any order")
    func earliestStartIsDeterministic() throws {
        let forwards = try #require(recordFact("record.earliestStart", fiveMornings))
        for other in [Array(fiveMornings.reversed()), fiveMornings.shuffled()] {
            let fact = try #require(recordFact("record.earliestStart", Array(other)))
            #expect(fact.figure == forwards.figure)
            #expect(fact.sentence == forwards.sentence)
            #expect(fact.revision == forwards.revision)
        }
    }

    // MARK: - The pool as a whole

    /// A record with something for every generator: four days with two of them
    /// consecutive, three weeks, two activities, two parts of the day, and a
    /// rating on everything.
    private var completeRecord: [Session] {
        [
            session(at(2026, 1, 5, 9), minutes: 30, activity: work),
            session(at(2026, 1, 6, 9, 30), minutes: 45, activity: work),
            session(at(2026, 1, 6, 15), minutes: 60, activity: reading),
            session(at(2026, 1, 14, 10), minutes: 90, activity: work),
            session(at(2026, 1, 21, 16), minutes: 120, activity: reading),
        ]
    }

    private func wholePool() -> [HealthDigest.Fact] {
        RecordFacts.pool(sessions: completeRecord, feeling: { _ in 4 },
                         activityName: name, calendar: calendar)
    }

    /// The guard against a generator silently stopping. Each of these returns nil
    /// below its own minimum, so a change that moved a floor or a filter would
    /// show up as a quietly shorter pool rather than as a failure anywhere else.
    @Test("Every generator fires on a record that has something for all of them")
    func allSevenFire() {
        #expect(Set(wholePool().map(\.subject.key)) == [
            "record.length", "record.coverage", "record.dayTotal", "record.daysInARow",
            "record.weekTotal", "record.activities", "record.earliestStart",
        ], Comment(rawValue: "produced \(wholePool().map(\.subject.key))"))
    }

    /// Seven topics, seven variety pairs, and therefore seven distinct days of
    /// rotation. A new topic that collided with an existing pair would be added to
    /// the pool and then suppressed by the dispenser, which is the failure mode
    /// that looks like the generator not working.
    @Test("Each topic is its own pair in the rotation")
    func topicsAreDistinctPairs() {
        let pairs = wholePool().map(DailyFact.pair(of:))
        #expect(Set(pairs).count == pairs.count, Comment(rawValue: "pairs: \(pairs)"))
        for fact in wholePool() {
            let key = DailyFact.key(for: fact)
            #expect(DailyFact.parts(ofKey: key)?.kind == "best", Comment(rawValue: key))
            #expect(DailyFact.parts(ofKey: key)?.subject == fact.subject.key, Comment(rawValue: key))
        }
    }

    /// What the whole exercise was for: seven days of record facts before the
    /// Health pool is touched at all, where there used to be four.
    @Test("The dispenser hands out every record fact before reaching for Health")
    func sevenDaysOfRecordFacts() throws {
        let defaults = UserDefaults(suiteName: "record-growth-\(UUID().uuidString)")!
        let dispenser = DailyFact(defaults: defaults)
        let record = wholePool()

        var seen: Set<String> = []
        for day in (0..<record.count).reversed() {
            let fact = try #require(dispenser.fact(
                for: Calendar.current.date(byAdding: .day, value: -day,
                                           to: Calendar.current.startOfDay(for: Date()))!,
                record: record, from: []))
            seen.insert(DailyFact.key(for: fact))
        }
        #expect(seen.count == record.count, Comment(rawValue:
            "\(seen.count) distinct facts over \(record.count) days"))
    }

    /// The copy sweep, run through the guard the narration layer uses rather than
    /// a list copied into this file — the lists live in one place and this cannot
    /// drift from them.
    ///
    /// Every digit run is passed as allowed, because the invention rule is about a
    /// model writing a number the evidence does not contain and nothing here is
    /// written by a model: every figure in a record fact is arithmetic over the
    /// person's own rows. What is being swept for is the other four rules — no
    /// causation, nothing clinical, no comparison with anybody else, no
    /// instruction.
    @Test("Nothing a record fact says breaks the narration rules")
    func copyPassesTheNarrationGuard() {
        for fact in wholePool() {
            let text = "\(fact.subject.title). \(fact.figure). \(fact.sentence)"
            let figures = NarrationGuard.figures(in: text)
            #expect(NarrationGuard.offence(in: text, allowingFigures: figures) == nil,
                    Comment(rawValue: "\(text) — "
                        + "\(String(describing: NarrationGuard.offence(in: text, allowingFigures: figures)))"))
        }
    }

    /// And the words the guard has no entry for, because they are specific to this
    /// file: the vocabulary of a thing somebody is holding and could drop. The
    /// streak note above `RecordFacts.daysInARow` is the argument; this is the
    /// sweep that holds every fact in the pool to it, not just that one.
    @Test("No record fact asks anything of the reader")
    func copyAsksForNothing() {
        for fact in wholePool() {
            let words = "\(fact.subject.title) \(fact.figure) \(fact.sentence)".lowercased()
            for banned in [
                "streak", "tomorrow", "today", "keep it up", "keep going",
                "don't break", "do not break", "goal", "target", "continue",
                "maintain", "on track", "current", "so far this", "best yet",
                "congratulations", "well done", "you could", "you can", "you have to",
                // Relational vocabulary, which is the line the whole file rests on.
                "when you", "on days", "after a", "correlat", "linked", "unusually",
            ] {
                #expect(!words.contains(banned), Comment(rawValue: "\"\(words)\" contains \"\(banned)\""))
            }
        }
    }
}

/// The totals card, and the keys it left behind.
///
/// `HealthDigest.scale` summed a metric over the whole history — "2.4 million
/// steps across 365 days" — and was removed for being arithmetic rather than an
/// observation. These tests are not about the sum; they are about the string
/// `steps.scale`, which is sitting in `UserDefaults` on every phone that ever saw
/// that card and must keep meaning what it meant.
@Suite("The retired totals card")
struct RetiredScaleTests {

    private func year(_ value: (Bool) -> Double) -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var out: [Date: Double] = [:]
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            out[day] = value(weekday == 1 || weekday == 7)
        }
        return out
    }

    /// Three generators per metric now, and none of them a total. A cumulative
    /// metric is where a total would appear if one came back.
    @Test("No fact in the pool is a total")
    func poolHoldsNoTotals() {
        let pool = HealthDigest.pool(from: [
            .steps: year { $0 ? 11_000 : 8_500 },
            .sleepHours: year { $0 ? 8.6 : 7.0 },
        ])
        #expect(!pool.isEmpty)
        for fact in pool {
            #expect(HealthDigest.kindKey(fact.kind) != "scale", Comment(rawValue: fact.sentence))
            // The sum's own phrasing, which is the thing that read as arithmetic.
            #expect(!fact.sentence.contains("across 365 days"), Comment(rawValue: fact.sentence))
        }
    }

    /// No live kind may mint the retired spelling. If one ever did, every phone
    /// carrying a spent `steps.scale` would treat the new card as already shown
    /// and never display it — missing for existing users, present for new ones.
    @Test("No kind spells itself scale")
    func scaleIsNotMintedAgain() {
        for kind in [HealthDigest.Fact.Kind.rhythm, .contrast, .drift, .best] {
            #expect(HealthDigest.kindKey(kind) != "scale")
        }
    }

    /// A key written before the removal still parses into the subject and kind it
    /// named. It matches nothing live, which is correct — the fact it named is
    /// gone — and it must not be mistaken for anything else.
    @Test("A spent totals key still means what it meant")
    func storedKeysKeepTheirMeaning() throws {
        let parts = try #require(DailyFact.parts(ofKey: "steps.scale"))
        #expect(parts.subject == "steps")
        #expect(parts.kind == "scale")
        #expect(DailyFact.pair(ofKey: "steps.scale") == "movement.scale")

        // And it blocks nothing it should not: a spent total does not suppress the
        // live facts about the same metric.
        let defaults = UserDefaults(suiteName: "retired-scale-\(UUID().uuidString)")!
        defaults.set(["steps.scale"], forKey: "hourss.dailyFact.spent")
        let pool = HealthDigest.pool(from: [.steps: year { $0 ? 11_000 : 8_500 }])
        #expect(!pool.isEmpty)
        let fact = try #require(DailyFact(defaults: defaults)
            .fact(for: Calendar.current.startOfDay(for: Date()), from: pool))
        #expect(DailyFact.key(for: fact) != "steps.scale")
    }
}
