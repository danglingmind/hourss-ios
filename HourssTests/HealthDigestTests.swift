import Testing
import Foundation
@testable import Hourss

/// The onboarding proof beat.
///
/// It used to rank candidate facts by effect size, which guarantees leading with
/// the most obvious true thing about somebody — the obvious things are obvious
/// *for* being large. On a real year of Health history that read as accurate and
/// unremarkable, which is the worst outcome for a screen whose whole job is to be
/// worth continuing past.
@Suite("Onboarding digest")
@MainActor
struct HealthDigestTests {

    /// A year of days, with a value the caller decides per day.
    private func year(_ value: (Date, Bool) -> Double) -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var out: [Date: Double] = [:]
        for offset in 0..<365 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            out[day] = value(day, weekday == 1 || weekday == 7)
        }
        return out
    }

    @Test("The most predictable fact there is does not lead")
    func sleepingInAtWeekendsDoesNotLead() throws {
        // Everyone sleeps longer at weekends, and it is a large effect. Alongside
        // it, a smaller weekend contrast in a signal nobody has expectations about.
        let digest = HealthDigest.build(from: [
            .sleepHours: year { _, weekend in weekend ? 8.6 : 7.0 },
            .respiratoryRate: year { _, weekend in weekend ? 16.1 : 14.5 },
        ])
        let lead = try #require(digest.facts.first)
        #expect(lead.metric != .sleepHours, Comment(rawValue:
                "led with \"\(lead.sentence)\" — the one thing everybody already knows"))
    }

    @Test("Sleeping less at weekends outranks sleeping more")
    func directionViolationLeads() {
        // Scored directly rather than through `build`, which keeps only one fact
        // per health group and so would never return both to compare.
        let ordinary = contrast(.sleepHours, raised: true, strength: 0.17)
        let unusual = contrast(.sleepHours, raised: false, strength: 0.17)
        #expect(HealthDigest.surprise(of: unusual) > HealthDigest.surprise(of: ordinary),
                Comment(rawValue: "ordinary \(HealthDigest.surprise(of: ordinary)) vs " +
                        "against-the-grain \(HealthDigest.surprise(of: unusual))"))
    }

    /// A weekend contrast with a chosen direction and size.
    private func contrast(_ metric: HealthMetric, raised: Bool, strength: Double) -> HealthDigest.Fact {
        HealthDigest.Fact(
            figure: "", sentence: "", group: metric.group, kind: .contrast,
            mark: .none, strength: strength, metric: metric, raised: raised
        )
    }

    @Test("A large obvious effect cannot outrank a small surprising one")
    func sizeCannotBuyTheLead() throws {
        // 23% at weekends against 5%, and the small one should still win.
        let digest = HealthDigest.build(from: [
            .steps: year { _, weekend in weekend ? 11_000 : 8_500 },
            .respiratoryRate: year { _, weekend in weekend ? 15.9 : 14.5 },
        ])
        let lead = try #require(digest.facts.first)
        #expect(lead.metric == .respiratoryRate, Comment(rawValue:
                "led with \"\(lead.sentence)\" on size alone"))
    }

    @Test("A signal with no folk expectation is neither promoted nor punished")
    func unknownMetricsAreNeutral() {
        let digest = HealthDigest.build(from: [
            .mindfulMinutes: year { _, weekend in weekend ? 14 : 9 },
        ])
        // Nothing asserted about order here — only that a metric absent from the
        // prior table still produces a fact rather than being filtered out.
        #expect(!digest.isEmpty)
    }

    @Test("Ranking is deterministic")
    func rankingIsStable() {
        let values: [HealthMetric: [Date: Double]] = [
            .sleepHours: year { _, weekend in weekend ? 8.3 : 7.1 },
            .steps: year { _, weekend in weekend ? 10_400 : 8_100 },
            .hrv: year { _, weekend in weekend ? 56 : 49 },
        ]
        let first = HealthDigest.build(from: values).facts.map(\.sentence)
        let second = HealthDigest.build(from: values).facts.map(\.sentence)
        #expect(first == second)
    }

    @Test("No fact compares the person to anyone else")
    func noPopulationComparison() {
        let forbidden = ["average", "most people", "normal", "typical", "than others",
                         "compared to", "population", "benchmark"]
        let digest = HealthDigest.build(from: [
            .sleepHours: year { _, weekend in weekend ? 8.4 : 7.0 },
            .steps: year { _, weekend in weekend ? 10_800 : 8_200 },
            .restingHeartRate: year { _, weekend in weekend ? 55 : 60 },
        ])
        for fact in digest.facts {
            let text = (fact.sentence + " " + fact.figure).lowercased()
            for word in forbidden {
                #expect(!text.contains(word), Comment(rawValue:
                        "\"\(fact.sentence)\" contains \"\(word)\""))
            }
        }
    }
}
