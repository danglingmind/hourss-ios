import Testing
import SwiftUI
import Foundation
@testable import Hourss

/// Subject before number, everywhere a health figure is printed.
///
/// These are cheap assertions about an expensive-to-notice failure. A card that
/// leads with "12%" renders perfectly, passes every other test, and is simply
/// unreadable at a glance — you cannot tell by running the app that the number
/// arrived before its subject, because you already know what the screen is
/// about. So the order is pinned here instead, at the two places that print it
/// and in the component both of them route through.
@Suite("Titled figures")
@MainActor
struct TitledFigureTests {

    // MARK: - The component

    @Test("Spoken order is title, then figure, then detail")
    func spokenLeadsWithTheTitle() {
        let block = TitledFigure(title: "Time asleep", figure: "8h 02m",
                                 detail: "Your longest night in eleven days.")
        #expect(block.spoken == "Time asleep. 8h 02m. Your longest night in eleven days.")
    }

    /// The pair alone is a legitimate use, and it must not leave a dangling
    /// separator or a spoken string that starts with punctuation.
    @Test("A block with no detail speaks the pair and stops")
    func spokenWithoutDetail() {
        #expect(TitledFigure(title: "Steps", figure: "8,412").spoken == "Steps. 8,412")
    }

    // MARK: - Fact rows

    /// A year of plausible history for every metric a digest generator reads,
    /// so the facts under test are the ones the app would actually build rather
    /// than ones written to pass.
    private func realFacts() -> [HealthDigest.Fact] {
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

    @Test("Every fact row carries a title")
    func everyRowHasATitle() {
        let facts = realFacts()
        #expect(!facts.isEmpty, "no facts to check")
        for fact in facts {
            let row = HealthFactRow(fact: fact, identifier: "test-fact")
            #expect(!row.titled.title.isEmpty, Comment(rawValue: "untitled: \(fact.sentence)"))
        }
    }

    /// The title has to be the metric's own name — the string the consent list
    /// already shows — and not something composed for the row. A generated title
    /// would be new user-facing copy that no phrasing rule has been applied to,
    /// and it would drift from the name this person agreed to share.
    @Test("The title is the metric's own name, never generated text")
    func titleComesFromTheMetric() {
        for fact in realFacts() {
            let row = HealthFactRow(fact: fact, identifier: "test-fact")
            #expect(row.titled.title == fact.metric.title,
                    Comment(rawValue: "\"\(row.titled.title)\" is not \"\(fact.metric.title)\""))
        }
    }

    /// Nothing evaluative and nothing about the generator is allowed to ride
    /// along with the name. A name is not a claim; a name plus a qualifier can be.
    @Test("The title is only the name — no kind, no direction, no verdict")
    func titleCarriesNothingElse() {
        for metric in HealthMetric.allCases {
            let title = metric.title.lowercased()
            for word in ["rhythm", "contrast", "drift", "scale", "higher", "lower",
                         "up", "down", "good", "bad", "better", "worse", "unusual"] {
                #expect(!title.contains(word), Comment(rawValue: "\"\(title)\" contains \"\(word)\""))
            }
        }
    }

    /// The reader's case is the strict one: there is no layout to glance back at,
    /// so a label opening with the figure leaves the number attached to nothing
    /// until the sentence arrives.
    @Test("A fact row's spoken label leads with the title, not the figure")
    func rowSpeaksTheTitleFirst() {
        for fact in realFacts() {
            let spoken = HealthFactRow(fact: fact, identifier: "test-fact").titled.spoken
            #expect(spoken.hasPrefix(fact.metric.title),
                    Comment(rawValue: "spoken as \"\(spoken)\""))
            #expect(!spoken.hasPrefix(fact.figure),
                    Comment(rawValue: "led with the figure: \"\(spoken)\""))
            // The sentence is still in there — the label gained a subject rather
            // than trading the explanation for one.
            #expect(spoken.contains(fact.sentence))
            #expect(spoken.contains(fact.figure))
        }
    }

    // MARK: - The day context card

    @Test("The day context card speaks the metric name first")
    func cardSpeaksTheTitleFirst() {
        for metric in DayDeviation.eligibleMetrics {
            let standout = DayDeviation.Standout(
                metric: metric, value: metric == .sleepHours ? 8.03 : 58,
                z: 2.4, daysSinceMoreExtreme: 11, historyDays: 400)
            let card = DayContextCard(standout: standout, onDismiss: {})
            #expect(card.titled.spoken.hasPrefix(metric.title),
                    Comment(rawValue: "spoken as \"\(card.titled.spoken)\""))
            #expect(card.titled.spoken.contains(DayContextCopy.figure(standout)))
            #expect(card.titled.spoken.contains(DayContextCopy.sentence(standout)))
        }
    }

    /// The card is byte-identical whatever was rated. Nothing the new title adds
    /// may depend on the day, let alone on the score — so the whole spoken block
    /// for one metric and one value is the same string both directions apart from
    /// the superlative the sentence already carried.
    @Test("The card's title does not vary with the day")
    func cardTitleIsStable() {
        for metric in DayDeviation.eligibleMetrics {
            func card(z: Double) -> DayContextCard {
                DayContextCard(standout: DayDeviation.Standout(
                    metric: metric, value: 58, z: z,
                    daysSinceMoreExtreme: 11, historyDays: 400), onDismiss: {})
            }
            #expect(card(z: 2.4).titled.title == card(z: -2.4).titled.title)
            #expect(card(z: 2.4).titled.title == metric.title)
        }
    }
}
