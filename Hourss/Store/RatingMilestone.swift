import Foundation

/// A session that has just been rated higher than anything before it.
///
/// **Why this is not in the daily fact pool.** It was meant to be, and it cannot
/// be. A feeling is one of five values, so across a dozen sessions the top one is
/// almost always held by several at once — "your highest-rated session so far"
/// either has to name one of six arbitrarily or is simply false. The only
/// formulation that is unambiguous compares one session against *everything
/// logged before it*, which is a question that can only be asked at the moment
/// the rating is made. So it lives here, on the post-rating card, rather than in
/// `RecordFacts`.
///
/// **Why it does not break the card's governing rule.** `DayContextCard` must be
/// byte-identical whatever was rated, and this is manifestly about the rating.
/// The rule survives because of what it was actually for: the card *juxtaposes a
/// health reading with a rating*, two things measured separately, and if the
/// reading moved with the rating the card would be asserting a relationship
/// between them on a sample of one. That is the failure the rule prevents.
///
/// A milestone has one measurement. Comparing a rating against other ratings has
/// no second variable for a relationship to exist between — it is the same shape
/// as `RecordFacts.longestStretch`, a superlative inside somebody's own record,
/// and needs no evidence gate for the same reason.
///
/// What must hold instead, and what the card enforces, is that **these two are
/// never shown together**. A milestone beside a health reading would be exactly
/// the juxtaposition-that-varies-with-the-rating the rule forbids.
struct RatingMilestone: Equatable {
    /// The feeling that was just recorded, on the 1–5 scale.
    let rating: Int
    /// What the person called it, or what the activity is called.
    let name: String
    /// How many rated sessions it beat. Stated in the sentence, because a
    /// superlative that does not say what it is a superlative of invites the
    /// reader to assume a larger record than exists.
    let beatCount: Int

    /// Enough rated sessions behind it for "highest so far" to mean anything.
    ///
    /// Shares `RecordFacts.minimumSessions` rather than setting its own floor:
    /// this is the same question that file answers about duration, asked about a
    /// rating, and two different floors for one idea is two things to keep in
    /// step.
    static var minimumPrior: Int { RecordFacts.minimumSessions }

    /// The milestone this session just set, if it set one.
    ///
    /// **Strictly greater, never equal.** A tie is the common case on a
    /// five-point scale and it is not a milestone — announcing "your highest so
    /// far" to somebody who has matched their best six times would make the
    /// phrase mean nothing by the third telling. Equality returning nil is what
    /// keeps the card rare enough to be worth reading.
    static func earned(
        by sessionId: UUID,
        rating: Int,
        sessions: [Session],
        feeling: (UUID) -> Int?,
        activityName: (UUID) -> String
    ) -> RatingMilestone? {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              session.isEligibleForPatterns,
              session.healthKind != .sleep
        else { return nil }

        // Everything else that carries a rating. Sleep is excluded on both sides:
        // nothing asks how a night felt, so a night can neither set a record nor
        // be one that was beaten.
        let others = sessions.filter {
            $0.id != sessionId && $0.isEligibleForPatterns && $0.healthKind != .sleep
        }
        let priorRatings = others.compactMap { feeling($0.id) }
        guard priorRatings.count >= minimumPrior else { return nil }
        guard let best = priorRatings.max(), rating > best else { return nil }

        return RatingMilestone(
            rating: rating,
            name: session.intention ?? activityName(session.activityId),
            beatCount: priorRatings.count
        )
    }
}
