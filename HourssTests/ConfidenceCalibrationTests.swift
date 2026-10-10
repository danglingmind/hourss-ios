import Foundation
import Testing
@testable import Hourss

/// What a confidence band is actually worth, measured.
///
/// `Engine.confidence` maps an interval to a number and `Confidence.band` cuts it at
/// 80, 65 and 50. The ordering was defensible and **nothing about what those words
/// are worth had ever been measured** — the engine document's §10.4. This is the
/// measurement.
///
/// **Read `ConfidenceCalibration`'s own note before quoting any figure here.** These
/// hit rates are measured in the generator's world, they are conditional on how many
/// of the simulated questions had an answer at all, and none of them says anything
/// about a single claim. They are a property of a population of claims.
@Suite("Confidence calibration")
struct ConfidenceCalibrationTests {

    /// The regimes worth checking, hardest last. The easy ones are not interesting —
    /// with generous effects every band is right essentially always, because the
    /// gates upstream refuse nearly everything false before confidence is consulted.
    private static let regimes: [(name: String, effect: ClosedRange<Double>,
                                  realShare: Double, days: Int)] = [
        ("ordinary", 0.3...1.5, 0.5, 14),
        ("tiny effects", 0.05...0.35, 0.5, 14),
        ("tiny effects, rarely real", 0.05...0.35, 0.2, 14),
        ("small effects, thin record", 0.1...0.5, 0.3, 8),
        ("mostly noise", 0.2...0.8, 0.1, 14),
    ]

    private func measure(_ regime: (name: String, effect: ClosedRange<Double>,
                                    realShare: Double, days: Int),
                         trials: Int = 800) -> [ConfidenceCalibration.Trial] {
        ConfidenceCalibration.run(trials: trials, days: regime.days,
                                  realShare: regime.realShare, effect: regime.effect,
                                  resamples: 600)
    }

    /// **The strongest property the engine has, and the one it was rebuilt for.**
    ///
    /// The old engine's third failure was a claim that pointed the wrong way — *"on
    /// days after a shorter night, your sessions have felt better"*, in a person where
    /// the opposite was planted. Across every regime below, over four thousand
    /// trials, the current engine makes no such claim at all. A wrong-direction claim
    /// is worse than a false one: a person can discount "no pattern here", and cannot
    /// discount being told the opposite of their own truth.
    @Test("No claim ever points the wrong way")
    func neverBackwards() {
        for regime in Self.regimes {
            let backwards = measure(regime).filter { $0.visible && $0.hadEffect && !$0.correct }
            #expect(backwards.isEmpty, Comment(rawValue:
                "\(regime.name): \(backwards.count) claims pointed the wrong way"))
        }
    }

    /// The bands are ordered by how often they are right, which is what the number
    /// claims about itself and had never been checked.
    @Test("A stronger band is at least as often right as a weaker one")
    func bandsAreOrdered() {
        for regime in Self.regimes {
            let bands = ConfidenceCalibration.bands(measure(regime))
            let rates = bands.filter { $0.claims >= 5 }.map(\.hitRate)
            for (stronger, weaker) in zip(rates, rates.dropFirst()) {
                // A tolerance, because these are samples: a band holding eight claims
                // moves by twelve points when one of them changes.
                #expect(stronger >= weaker - 0.15, Comment(rawValue:
                    "\(regime.name): \(bands.map { "\($0.band.label) \($0.hits)/\($0.claims)" })"))
            }
        }
    }

    /// What "Strong pattern" is worth, stated as a floor it must keep.
    @Test("A strong claim is right at least nine times in ten")
    func strongHoldsUp() {
        for regime in Self.regimes {
            let strong = ConfidenceCalibration.bands(measure(regime))
                .first { $0.band == .strong }
            guard let strong, strong.claims >= 5 else { continue }
            #expect(strong.hitRate >= 0.88, Comment(rawValue:
                "\(regime.name): strong was right \(strong.hits)/\(strong.claims)"))
        }
    }

    /// **Where the engine's mistakes live, pinned so nobody promotes this band.**
    ///
    /// Measured: "Still watching" runs from 93% right when half the questions have an
    /// answer down to 45% when one in ten does, and essentially every false claim the
    /// engine makes lands in it. That is not a defect — it is the weakest thing the
    /// app is willing to show, and it says so in its own name. It is recorded as a
    /// test so that any later change giving this band a more confident voice, or
    /// folding it into "Emerging", has to argue with a number first.
    @Test("The weakest band is where the mistakes are")
    func watchingCarriesTheErrors() {
        // The regime where the prior is thinnest, which is where a weak band is
        // least worth trusting.
        let trials = measure(Self.regimes.last!)
        let bands = ConfidenceCalibration.bands(trials)
        let watching = bands.first { $0.band == .watching }
        let stronger = bands.filter { $0.band != .watching }

        guard let watching, watching.claims >= 5 else { return }
        let falseClaims = trials.filter { $0.visible && !$0.correct }
        let inWatching = falseClaims.filter { Confidence.band($0.confidence) == .watching }

        #expect(Double(inWatching.count) / Double(max(falseClaims.count, 1)) >= 0.7,
                Comment(rawValue: "false claims by band: \(bands.map { "\($0.band.label) \($0.claims - $0.hits)" })"))
        for band in stronger where band.claims >= 5 {
            #expect(band.hitRate > watching.hitRate - 0.01)
        }
    }

    /// Nothing false gets through at any volume when the question genuinely has an
    /// answer most of the time — which is the ordinary case, and the one the gates
    /// upstream are tuned for.
    @Test("In the ordinary case almost nothing false is shown")
    func theOrdinaryCaseIsClean() {
        let trials = measure(Self.regimes[0])
        let shown = trials.filter(\.visible)
        let fromNoise = shown.filter { !$0.hadEffect }
        #expect(Double(fromNoise.count) / Double(shown.count) < 0.05, Comment(rawValue:
            "\(fromNoise.count) of \(shown.count) shown claims came from pure noise"))
    }
}
