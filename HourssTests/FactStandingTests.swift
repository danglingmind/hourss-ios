import Testing
import SwiftUI
import Foundation
@testable import Hourss

/// Which facts were hard to come by, and what the row does about it.
///
/// The classification is the assertable part. Whether 40pt above a card reads as
/// "this one took something" is a judgement to be made on a device and cannot be
/// pinned here; whether the four facts that only exist because somebody logged
/// are the four the row treats as earned is arithmetic, and it is the thing that
/// would break silently. A new generator added to `RecordFacts` with a `.health`
/// subject, or a `HealthDigest` generator that reached for `.best`, would both
/// render perfectly and quietly put the wrong card in the wrong tier.
@Suite("Fact standing")
@MainActor
struct FactStandingTests {

    // MARK: - Fixtures

    private let activity = UUID()
    private func name(_: UUID) -> String { "Deep work" }

    private func session(minutes: Int, hoursAgo: Int) -> Session {
        let start = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return Session(
            activityId: activity,
            startAt: start,
            endAt: start.addingTimeInterval(Double(minutes) * 60)
        )
    }

    /// Enough logged, and spread over enough days, for all four record
    /// generators to fire.
    private func recordFacts() -> [HealthDigest.Fact] {
        let sessions = (1...8).map { session(minutes: 25 * $0, hoursAgo: $0 * 19) }
        return RecordFacts.pool(sessions: sessions, feeling: { _ in 4 }, activityName: name)
    }

    /// A year of plausible readings for every metric a digest generator reads,
    /// so the facts under test are the ones the app would build.
    private func healthFacts() -> [HealthDigest.Fact] {
        func year(_ value: @escaping (Bool) -> Double) -> [Date: Double] {
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
        return HealthDigest.pool(from: [
            .sleepHours: year { $0 ? 8.6 : 7.0 },
            .hrv: year { $0 ? 64 : 58 },
            .restingHeartRate: year { $0 ? 55 : 58 },
            .respiratoryRate: year { $0 ? 16.1 : 14.5 },
            .steps: year { $0 ? 11_000 : 8_500 },
            .daylightMinutes: year { $0 ? 95 : 42 },
            .mindfulMinutes: year { $0 ? 14 : 9 },
            .activeEnergy: year { $0 ? 620 : 480 },
        ])
    }

    // MARK: - The classification

    @Test("Everything from the record is earned")
    func recordFactsAreEarned() {
        let facts = recordFacts()
        #expect(!facts.isEmpty, "no record facts to check")
        for fact in facts {
            #expect(fact.standing == .earned,
                    Comment(rawValue: "ambient: \(fact.subject.key) — \(fact.sentence)"))
        }
    }

    @Test("Everything read off a watch is ambient")
    func healthFactsAreAmbient() {
        let facts = healthFacts()
        #expect(!facts.isEmpty, "no health facts to check")
        for fact in facts {
            #expect(fact.standing == .ambient,
                    Comment(rawValue: "earned: \(fact.subject.key) — \(fact.sentence)"))
        }
    }

    /// The brief for this distinction named two signals — `kind == .best` and a
    /// `.record` subject — and the row trusts only the second. They agree on
    /// every fact either generator currently produces, and this is where that
    /// stops being a coincidence nobody checked. If a generator ever makes them
    /// disagree, this fails and somebody decides which one meant it.
    @Test("Earned and `.best` are the same set")
    func kindAgreesWithSubject() {
        for fact in recordFacts() + healthFacts() {
            #expect((fact.kind == .best) == (fact.standing == .earned),
                    Comment(rawValue: "\(fact.subject.key) is \(fact.kind) but \(fact.standing)"))
        }
    }

    /// Nothing in the pool may be unclassified. `standing` is total over
    /// `Subject`, so this is really a guard on a third source arriving: a pool
    /// that grows a tier the row has no treatment for should fail here rather
    /// than quietly render as a health fact.
    @Test("Every fact in the whole pool lands in one of the two tiers")
    func poolIsFullyClassified() {
        let pool = recordFacts() + healthFacts()
        let earned = pool.filter { $0.standing == .earned }
        let ambient = pool.filter { $0.standing == .ambient }
        #expect(earned.count + ambient.count == pool.count)
        #expect(!earned.isEmpty && !ambient.isEmpty, "one tier was empty, so nothing is being compared")
        // The asymmetry is the point of the whole exercise: the earned tier is
        // small and the ambient one is not. If they ever come out level, space
        // spent on rarity is space spent on nothing.
        #expect(earned.count < ambient.count,
                Comment(rawValue: "\(earned.count) earned vs \(ambient.count) ambient"))
    }

    // MARK: - What the row does with it

    @Test("An earned fact is given more room than an ambient one")
    func earnedGetsMoreRoom() {
        #expect(HealthDigest.Fact.Standing.earned.room > HealthDigest.Fact.Standing.ambient.room)
    }

    /// Both values are tokens from `Space`, which is the restraint the whole
    /// change rests on. A bespoke 28 or 32 would differentiate the cards just as
    /// well and would be the first spacing in the app that belongs to one
    /// component.
    @Test("Both amounts of room are existing spacing tokens")
    func roomUsesTokens() {
        let tokens: Set<CGFloat> = [Space.xs, Space.sm, Space.md, Space.lg, Space.xl]
        #expect(tokens.contains(HealthDigest.Fact.Standing.earned.room))
        #expect(tokens.contains(HealthDigest.Fact.Standing.ambient.room))
    }

    /// The common case got quieter rather than the rare case only getting
    /// louder. Stated as a test because it is the argument for the change being
    /// shippable at all: dozens of cards lose 8pt a side and a handful gain 16pt
    /// a side, so Today is shorter on most days rather than taller.
    @Test("The ambient card is quieter than what both cards used to get")
    func ambientIsQuieterThanBefore() {
        #expect(HealthDigest.Fact.Standing.ambient.room < Space.md)
        #expect(HealthDigest.Fact.Standing.earned.room > Space.md)
    }

    @Test("The row's room is the standing's room, for every fact in the pool")
    func rowUsesTheStandingsRoom() {
        for fact in recordFacts() + healthFacts() {
            let row = HealthFactRow(fact: fact, identifier: "test-fact")
            #expect(row.room == fact.standing.room,
                    Comment(rawValue: "\(fact.subject.key): \(row.room) vs \(fact.standing.room)"))
        }
    }

    /// Record facts carry no mark, so the stack must not hold a gap open for
    /// one. This is the half of the change that is a fix rather than a decision:
    /// the cards with the least to draw were the cards reserving space for a
    /// mark that never arrives.
    @Test("An earned fact draws no mark, so it reserves no gap for one")
    func earnedFactsDrawNoMark() {
        for fact in recordFacts() {
            #expect(!HealthFactRow(fact: fact, identifier: "test-fact").drawsMark,
                    Comment(rawValue: "\(fact.subject.key) carries a mark"))
        }
    }

    /// Asserts the predicate tracks the fact's own `mark` rather than its
    /// standing — every health generator currently carries one, and confusing the
    /// two is how a rhythm strip would silently vanish if one stopped.
    @Test("Drawing a mark follows the mark, not the standing")
    func markFollowsTheMark() {
        for fact in healthFacts() {
            let row = HealthFactRow(fact: fact, identifier: "test-fact")
            switch fact.mark {
            case .weekdayRhythm, .comparison:
                #expect(row.drawsMark, Comment(rawValue: "\(fact.subject.key) lost its mark"))
            case .none:
                #expect(!row.drawsMark, Comment(rawValue: "\(fact.subject.key) gained a mark"))
            }
        }
    }

    // MARK: - What did not change

    /// The accessibility label still leads with the subject and still comes from
    /// the one place that assembles it. Standing is a layout decision and must
    /// not reach a spoken string — there is no way to say "this one was harder to
    /// come by" that clears the comparison rules, and nothing here tries.
    @Test("Standing changes no word a reader or VoiceOver gets")
    func standingIsSilent() {
        for fact in recordFacts() + healthFacts() {
            let row = HealthFactRow(fact: fact, identifier: "test-fact")
            #expect(row.titled.spoken.hasPrefix(fact.subject.title),
                    Comment(rawValue: "spoken label did not lead with the subject: \(row.titled.spoken)"))
            #expect(row.titled.title == fact.subject.title)
            #expect(row.titled.figure == fact.figure)
            #expect(row.titled.detail == fact.sentence)
        }
    }
}
