import Foundation
@testable import Hourss

/// Measures what a confidence band is worth, against data whose truth is known.
///
/// **The gap.** `Engine.confidence` maps an interval to a number between 28 and 96,
/// and `Confidence.band` cuts that at 80, 65 and 50 into "Strong pattern",
/// "Emerging pattern" and "Still watching". The ordering is defensible — a tighter
/// interval further from zero should score higher — but **nothing has ever been
/// measured about what those words are worth.** The weights 0.72/0.28 and the three
/// boundaries were chosen, not derived. The engine document raises it as §10.4.
///
/// **What this measures and what it cannot.** Trials are generated with a known
/// answer: half carry a real difference, half are noise. Each is compared by the
/// real `Statistics.compare` and scored by the real `Engine.confidence`, and a band's
/// *hit rate* is the share of its visible claims that were both real and pointed the
/// right way.
///
/// Three limits, all of which belong beside any number this produces:
///
/// - **It measures the generator's world, not the one people live in.** Ratings here
///   are drawn from a clamped normal with a planted shift. Real ratings are not, and
///   a hit rate measured here is "how often the engine recovers an effect of the kind
///   we chose to plant".
/// - **It is conditional on the mix.** A hit rate is `P(real | band)`, which depends
///   on how many trials carried a real effect at all. At `realShare` of one half the
///   number is a statement about a world where half of all questions have an answer.
///   A different mix moves every figure.
/// - **It says nothing about a single claim.** A band is a property of a population
///   of claims. Nobody's own morning is 83% true.
enum ConfidenceCalibration {

    struct Trial {
        let confidence: Int
        /// Whether a real difference was planted at all.
        let hadEffect: Bool
        /// Whether the engine would have shown this as a claim.
        let visible: Bool
        /// Planted, and pointing the way the comparison says.
        let correct: Bool
    }

    struct BandResult {
        let band: Confidence
        let claims: Int
        let hits: Int
        var hitRate: Double { claims == 0 ? 0 : Double(hits) / Double(claims) }
    }

    /// Run `trials` comparisons and score each one.
    ///
    /// - Parameters:
    ///   - days: distinct days on each side, the unit the bootstrap clusters on.
    ///   - realShare: how many trials carry a planted difference.
    ///   - effect: the range a planted difference is drawn from, in rating points.
    static func run(
        trials: Int,
        days: Int = 14,
        realShare: Double = 0.5,
        effect: ClosedRange<Double> = 0.3...1.5,
        seed: UInt64 = 0xCA11B2A7,
        resamples: Int = 600
    ) -> [Trial] {
        var rng = SyntheticCohort.Seeded(seed: seed)
        let anchor = Date(timeIntervalSince1970: 1_767_225_600)
        let calendar = Calendar.current

        return (0..<trials).map { _ in
            let hadEffect = Double.random(in: 0...1, using: &rng) < realShare
            let size = hadEffect ? Double.random(in: effect, using: &rng) : 0
            let sign: Double = Double.random(in: 0...1, using: &rng) < 0.5 ? -1 : 1
            let shift = size * sign

            var focus: [Statistics.Observation] = []
            var baseline: [Statistics.Observation] = []
            for day in 0..<days {
                let at = calendar.date(byAdding: .day, value: -day, to: anchor)!
                // One to three sessions a side a day, so the day clustering has
                // something to do — a trial with one session per day would make the
                // bootstrap's whole reason for existing invisible.
                for _ in 0..<Int.random(in: 1...3, using: &rng) {
                    focus.append(.init(day: at, value: rating(3.2 + shift, &rng)))
                }
                for _ in 0..<Int.random(in: 1...3, using: &rng) {
                    baseline.append(.init(day: at, value: rating(3.2, &rng)))
                }
            }

            let comparison = Statistics.compare(focus: focus, baseline: baseline,
                                                resamples: resamples)
            let confidence = Engine.confidence(comparison)
            let band = Confidence.band(confidence)
            let visible = band != .internalOnly

            return Trial(
                confidence: confidence,
                hadEffect: hadEffect,
                visible: visible,
                // Right about *something*: a difference was planted and the
                // comparison points the way it was planted. A claim in the wrong
                // direction is a miss, not a half-hit — it is the failure the old
                // engine shipped and the one that matters most.
                correct: hadEffect && (comparison.delta > 0) == (shift > 0)
            )
        }
    }

    /// Hit rate per visible band, strongest first.
    static func bands(_ trials: [Trial]) -> [BandResult] {
        [Confidence.strong, .emerging, .watching].map { band in
            let mine = trials.filter { $0.visible && Confidence.band($0.confidence) == band }
            return BandResult(band: band, claims: mine.count,
                              hits: mine.filter(\.correct).count)
        }
    }

    /// A rating on the 1–5 scale: a shifted normal, clamped and rounded the way a
    /// person's tap would be.
    private static func rating(_ centre: Double, _ rng: inout SyntheticCohort.Seeded) -> Double {
        let value = centre + SyntheticCohort.gaussian(&rng, sd: 0.75)
        return Double(max(1, min(5, Int(value.rounded()))))
    }
}

extension Confidence: Equatable {}
