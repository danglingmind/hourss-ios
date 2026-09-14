import Foundation

/// The shapes layer 2.5 is assembled from.
///
/// Layer 2 asks whether one slice of somebody's record differs from the rest.
/// This asks whether two slices *together* differ from what either does alone —
/// "deep work in the morning" rather than "deep work" and "mornings".
///
/// The whole difficulty is that a conjunction search finds things. Given four
/// families and a handful of values each, the number of cells is large, most of
/// them are small, and the smallest ones show the biggest apparent effects. Every
/// structure below exists to refuse rather than to discover.

/// One condition a session either meets or does not.
struct Factor {
    enum Family: String, CaseIterable {
        case time, activity, duration, workday, health
    }
    let family: Family
    /// The slice, as it appears in an id: a bucket's raw value, an activity's
    /// slug, a metric name with a direction.
    let value: String
    let matches: @Sendable (EngineObservation) -> Bool

    var key: String { "\(family.rawValue).\(value)" }
}

/// Two or three factors, taken together.
struct Conjunction {
    let factors: [Factor]
    let outcome: Outcome

    /// Stable and order-independent, so the same conjunction found two ways is
    /// one insight rather than two, and saved state survives recomputation as it
    /// does for single factors.
    var id: String {
        "complex." + factors.map(\.key).sorted().joined(separator: ".")
            + ".vs.rest." + outcome.rawValue
    }

    func matches(_ observation: EngineObservation) -> Bool {
        factors.allSatisfy { $0.matches(observation) }
    }
}

/// Whether a conjunction says anything its parts do not.
///
/// **This is the definition the specification left open, and it is not the one it
/// proposed.** The draft subtracted the strongest single-factor δ from the
/// conjunction's δ — but those two are measured against different baselines, so
/// the difference mixes a change of baseline with a change of effect.
///
/// What isolates an interaction is a conditional contrast: the effect of A among
/// sessions that are B, against the effect of A among sessions that are not B. If
/// A does the same thing either way, there is no interaction however large A is.
///
/// ```
/// within    = δ( A∩B  vs ¬A∩B  )
/// without   = δ( A∩¬B vs ¬A∩¬B )
/// lift      = within − without
/// ```
///
/// Measured on the cohort in rating units, this separates a real conjunction from
/// a confounded one by 1.27 against 0.06, where the draft's formula managed 0.60
/// against −0.28. Both discriminate; this one discriminates further, and means
/// something on its own.
///
/// The cost is that it needs **all four cells**. A person who only ever does
/// Creative work in the morning has no ¬B cell, so their interaction is not
/// estimable — and an interaction that cannot be estimated cannot be claimed,
/// which is `isEstimable == false` and a refusal rather than a zero.
struct InteractionLift {
    let within: Statistics.Comparison
    let without: Statistics.Comparison
    let lift: Double

    /// All four cells carried enough distinct days to be compared.
    let isEstimable: Bool

    /// The conjunction against everything outside it. Reported for the evidence
    /// line, never for the gate: this is the quantity that makes a confounded
    /// conjunction look strong.
    let combined: Statistics.Comparison

    /// Cliff's δ is bounded at ±1, so a difference of two δs runs −2…2 and the
    /// negligible threshold does not transfer unexamined. The engine agent
    /// measures the cohort's spurious lift in these units before this is fixed.
    static let minimumLift = 0.147
}

/// A conjunction, tested.
struct InteractionFinding {
    let conjunction: Conjunction
    let interaction: InteractionLift
    let focusSessionIds: [UUID]
    let baselineSessionIds: [UUID]
    let windowDays: Int

    /// Set by the correction step. Interactions are corrected separately from
    /// main effects and under a procedure valid for dependent tests, because the
    /// same sessions appear in a dozen cells.
    var survivesCorrection: Bool?

    /// Everything that must hold. Ordered cheapest first.
    var isReportable: Bool {
        interaction.isEstimable
            && interaction.combined.isReportable
            && interaction.lift >= InteractionLift.minimumLift
            && (survivesCorrection ?? false)
    }
}

/// How many candidates a run is allowed to test.
///
/// Not an optimisation. Every additional hypothesis costs power under correction,
/// so an unbounded search makes the honest ones unreportable — the search space
/// is the enemy of the thing being searched for.
enum InteractionBudget {
    /// A cell and its three companions each need this many distinct days, which
    /// is what makes a three-way conjunction expensive rather than merely
    /// tempting.
    static let minimumDaysPerCell = 6
    /// Beyond this, the correction costs more than the discoveries are worth.
    /// Candidates are ranked by main-effect strength and the tail is dropped
    /// untested, which is a decision to look in fewer places rather than a
    /// decision to believe more easily.
    ///
    /// Thirty rather than sixty, and the difference is not cosmetic. A step-up
    /// procedure compares each p against `k/m · q`, so every extra candidate
    /// raises the bar for all of them. At sixty, the person carrying a genuine
    /// three-way interaction was refused outright — their best candidate holds a
    /// permutation p of 0.0060 whatever the budget, and what moved was the
    /// threshold it was measured against. At thirty they are found again, and
    /// neither negative gains a single claim.
    ///
    /// It costs the two-way person two of five admissions. Refusing a real
    /// finding entirely is the worse failure, so that is the trade taken.
    static let maximumCandidates = 30
}
