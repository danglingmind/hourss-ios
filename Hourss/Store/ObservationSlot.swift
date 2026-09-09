import Foundation

/// Whether this person has paid, and what the slot on Today should therefore say.
///
/// Both halves live here because they are one decision seen from two sides: the
/// entitlement is meaningless without a surface that varies on it, and the
/// surface cannot be built or tested without an entitlement to vary on.

/// What a member is entitled to.
///
/// Recommendations and, later, a day plan are the paid capabilities. Nothing
/// about a person's own record sits behind this: export, deletion and every
/// privacy setting are free, permanently, and that rule is older than this type.
enum Tier: String, Codable, CaseIterable {
    case free, member

    var isEntitled: Bool { self == .member }
}

/// What the single observation slot on Today is showing.
///
/// The slot has always held one thing. This enumerates what that thing can be,
/// in the order the specification gives, so the precedence is a value somebody
/// can test rather than a chain of `if` statements inside a view body.
enum SlotContent: Equatable {
    /// A paid member with something that survived. Highest precedence.
    case recommendation(id: UUID)

    /// A session logged today that carries no feeling score.
    ///
    /// Deliberately above the upgrade prompt: asking somebody to pay before
    /// asking for the rating the engine runs on has the product's own dependency
    /// backwards.
    case unfinishedReflection(sessionId: UUID)

    /// A free member for whom a recommendation would exist. The count is what
    /// membership buys, and it is the number of recommendations that would be
    /// produced — not the number of surviving claims, since naming claims that
    /// would not become recommendations for this person is the same mis-selling
    /// one step removed.
    case upgradePrompt(count: Int)

    /// The strongest visible insight. Unchanged behaviour.
    case leadObservation(id: UUID)

    /// Not enough history yet. `days` counts distinct calendar days carrying at
    /// least one rated session, because days are what the engine counts — six
    /// sessions on one Tuesday are one day of evidence about Tuesdays.
    ///
    /// This is a floor and never a forecast. Copy rendering this must not carry a
    /// date, a remaining count, or any word implying that reaching the floor
    /// produces a recommendation.
    case evidenceProgress(days: Int)

    /// The floor is met, nothing has survived, and there is no insight to fall
    /// back to.
    ///
    /// A state the engine is entitled to hold forever. Copy here may not suggest
    /// something is being withheld, nor that more logging will change the answer,
    /// because for a person whose days genuinely are flat it will not.
    case stillLooking

    /// Nothing to say. The slot renders nothing rather than filling itself.
    case none
}

/// Distinct days carrying a rated session, which is the unit the engine counts in.
///
/// Twelve is the smallest history in which a comparison whose two sides fall on
/// different days could clear the engine's six-day minimum on each side. Splits
/// *within* a day — time of day, duration — can qualify sooner, and the surface
/// does not model that: arriving early is a pleasant surprise, arriving late
/// against a stated date is a broken promise, and only one of those is worth
/// avoiding.
enum EvidenceFloor {
    static let days = 12
}
