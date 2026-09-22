import Testing
import Foundation
@testable import Hourss

/// A rating that beat everything before it.
@Suite("Rating milestones")
struct RatingMilestoneTests {

    private let activity = UUID()
    private func name(_: UUID) -> String { "Deep work" }

    private func session(hoursAgo: Int,
                         minutes: Int = 60,
                         kind: HealthKind? = nil,
                         intention: String? = nil) -> Session {
        let start = Date().addingTimeInterval(-Double(hoursAgo) * 3600)
        return Session(activityId: activity, startAt: start,
                       endAt: start.addingTimeInterval(Double(minutes) * 60),
                       intention: intention, healthKind: kind)
    }

    /// Ratings keyed by session, so a test reads as the record it describes.
    private func rater(_ ratings: [UUID: Int]) -> (UUID) -> Int? { { ratings[$0] } }

    @Test("A rating above everything before it earns a milestone")
    func beatingTheRecordEarnsOne() throws {
        let prior = (1...6).map { session(hoursAgo: $0 * 5) }
        let subject = session(hoursAgo: 1)
        let ratings = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, 3) })

        let milestone = try #require(RatingMilestone.earned(
            by: subject.id, rating: 5,
            sessions: prior + [subject],
            feeling: rater(ratings), activityName: name))

        #expect(milestone.rating == 5)
        #expect(milestone.name == "Deep work")
        #expect(milestone.beatCount == 6)
    }

    /// The common case on a five-point scale, and the reason equality returns
    /// nothing: "your highest so far" told six times means nothing by the third.
    @Test("Matching your best is not a milestone")
    func tyingDoesNotCount() {
        let prior = (1...6).map { session(hoursAgo: $0 * 5) }
        let subject = session(hoursAgo: 1)
        let ratings = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, 5) })

        #expect(RatingMilestone.earned(
            by: subject.id, rating: 5,
            sessions: prior + [subject],
            feeling: rater(ratings), activityName: name) == nil)
    }

    @Test("A record too thin to have been beaten earns nothing")
    func thinRecordEarnsNothing() {
        let prior = (1...RatingMilestone.minimumPrior - 1).map { session(hoursAgo: $0 * 5) }
        let subject = session(hoursAgo: 1)
        let ratings = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, 2) })

        #expect(RatingMilestone.earned(
            by: subject.id, rating: 5,
            sessions: prior + [subject],
            feeling: rater(ratings), activityName: name) == nil)
    }

    /// Unrated sessions are not a record to beat. Somebody with twenty logged
    /// sessions and two ratings has two ratings.
    @Test("Only rated sessions count toward the floor")
    func unratedSessionsDoNotCount() {
        let prior = (1...10).map { session(hoursAgo: $0 * 5) }
        let subject = session(hoursAgo: 1)
        // Two of ten carry a rating.
        let ratings = [prior[0].id: 2, prior[1].id: 3]

        #expect(RatingMilestone.earned(
            by: subject.id, rating: 5,
            sessions: prior + [subject],
            feeling: rater(ratings), activityName: name) == nil)
    }

    /// Nothing asks how a night felt, so a night can neither set a record nor be
    /// one that was beaten.
    @Test("Sleep is on neither side of the comparison")
    func sleepIsExcluded() throws {
        let prior = (1...6).map { session(hoursAgo: $0 * 5) }
        let night = session(hoursAgo: 40, minutes: 450, kind: .sleep)
        let subject = session(hoursAgo: 1)

        var ratings = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, 3) })
        // A rating on a night, which the app never asks for but which must not
        // be able to block a real milestone if it somehow exists.
        ratings[night.id] = 5

        let milestone = try #require(RatingMilestone.earned(
            by: subject.id, rating: 4,
            sessions: prior + [night, subject],
            feeling: rater(ratings), activityName: name))
        #expect(milestone.beatCount == 6, Comment(rawValue:
            "counted \(milestone.beatCount) — the night was included"))

        // And a night cannot itself earn one.
        #expect(RatingMilestone.earned(
            by: night.id, rating: 5,
            sessions: prior + [night],
            feeling: rater(ratings), activityName: name) == nil)
    }

    @Test("An intention is used ahead of the activity's name")
    func intentionWins() throws {
        let prior = (1...6).map { session(hoursAgo: $0 * 5) }
        let subject = session(hoursAgo: 1, intention: "Write the hard thing")
        let ratings = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, 2) })

        let milestone = try #require(RatingMilestone.earned(
            by: subject.id, rating: 5,
            sessions: prior + [subject],
            feeling: rater(ratings), activityName: name))
        #expect(milestone.name == "Write the hard thing")
    }

    // MARK: - The card's rule

    /// The rule is that the card never pairs a rating with something measured
    /// separately from it. An enum whose cases are mutually exclusive is how that
    /// is made unrepresentable rather than merely avoided.
    ///
    /// Each arm added is one more pairing the sweep has to rule out, so the sweep
    /// is written as every arm against every other arm's vocabulary rather than
    /// as a list of pairs. The residual arm is the one worth being careful about:
    /// it is measured over the very session that was just rated, so it is the
    /// closest the card comes to the failure it exists to prevent, and the only
    /// thing keeping it honest is that its copy never mentions the rating and
    /// never moves with it.
    @Test("A card is a milestone, a standout or a residual, never two")
    func contentIsExclusive() throws {
        let milestone = RatingMilestone(rating: 5, name: "Deep work", beatCount: 9)
        let standout = DayDeviation.Standout(
            metric: .sleepHours, value: 8.4, z: 2.1,
            daysSinceMoreExtreme: 11, historyDays: 200)
        let residual = try #require(SessionResidual(Physiology.Reading(
            windowId: UUID(), observed: 76, expected: 70, explainedByMovement: 1,
            residual: 6, cadence: 4, cadenceBin: .minimal,
            sampleCount: 22, uncertainty: 3)))

        let asMilestone = DayContextCard.Content.milestone(milestone)
        let asHealth = DayContextCard.Content.health(standout)
        let asResidual = DayContextCard.Content.residual(residual)
        #expect(asMilestone != asHealth)
        #expect(asMilestone != asResidual)
        #expect(asHealth != asResidual)

        /// Everything one arm prints, as one lowercased string. The copy is what
        /// a person actually receives, so the copy is what gets swept.
        func words(_ content: DayContextCard.Content) -> String {
            [DayContextCopy.title(content),
             DayContextCopy.figure(content),
             DayContextCopy.sentence(content)].joined(separator: " ").lowercased()
        }

        // The vocabulary that belongs to each arm and must not appear in either
        // of the others. A card carrying two of these would be asserting a
        // relationship between two separately-measured things on a sample of one.
        let vocabulary: [(name: String, content: DayContextCard.Content, words: [String])] = [
            ("the rating", asMilestone, ["rated", "rating", "/ 5", "out of 5"]),
            // "heart" is deliberately not here: a resting-heart-rate standout is
            // a legitimate health card, and the residual arm is separated from it
            // by "expected" and "movement" instead.
            ("the day", asHealth, ["night", "sleep", "breathing", "hrv", "longest", "shortest"]),
            ("the body's own reading", asResidual, ["expected", "movement", "bpm above", "bpm below"]),
        ]

        for subject in vocabulary {
            for other in vocabulary where other.name != subject.name {
                let printed = words(other.content)
                for word in subject.words {
                    #expect(!printed.contains(word), Comment(rawValue:
                        "the \(other.name) card says \"\(printed)\" — \"\(word)\" belongs to "
                            + "\(subject.name), and the two must never share a card"))
                }
            }
        }
    }

    /// The residual card must be byte-identical whatever was rated, which is the
    /// card's governing rule stated for the one arm that is measured over the
    /// same session as the rating. Heart rate is not an input to the rating
    /// scale, so there is nothing here for a score to change — and the way that
    /// stays true is that the score is not reachable from a `SessionResidual` at
    /// all.
    @Test("A residual card cannot vary with the score")
    func residualCardDoesNotMoveWithTheRating() throws {
        let residual = try #require(SessionResidual(Physiology.Reading(
            windowId: UUID(), observed: 76, expected: 70, explainedByMovement: 1,
            residual: 6, cadence: 4, cadenceBin: .minimal,
            sampleCount: 22, uncertainty: 3)))
        let content = DayContextCard.Content.residual(residual)
        let printed = [DayContextCopy.title(content),
                       DayContextCopy.figure(content),
                       DayContextCopy.sentence(content)].joined(separator: " ")

        // Nothing in the printed card names a session either. The doc says the
        // card "does not name the session", and an activity name would make it a
        // sentence about the thing that was just rated.
        for leak in ["Deep work", "session", "Session"] {
            #expect(!printed.contains(leak), Comment(rawValue: "\"\(printed)\" names \(leak)"))
        }
    }

    /// `EngineContracts` calls the caveat never optional for anything built on a
    /// health metric. Both body arms are; the milestone is arithmetic on the
    /// person's own ratings and is not.
    /// `@MainActor` because it builds the card, and a SwiftUI view is not safe
    /// to initialise anywhere else.
    @Test("Body readings carry a caveat and a milestone does not")
    @MainActor
    func caveatFollowsTheMeasurement() throws {
        let residual = try #require(SessionResidual(Physiology.Reading(
            windowId: UUID(), observed: 76, expected: 70, explainedByMovement: 1,
            residual: 6, cadence: 4, cadenceBin: .minimal,
            sampleCount: 22, uncertainty: 3)))

        #expect(DayContextCard(content: .residual(residual), onDismiss: {}).caveat
            == ResidualCopy.caveat)
        #expect(DayContextCard(
            content: .health(DayDeviation.Standout(
                metric: .sleepHours, value: 8.4, z: 2.1,
                daysSinceMoreExtreme: 11, historyDays: 200)),
            onDismiss: {}).caveat == HealthMetric.sleepHours.caveat)
        #expect(DayContextCard(
            content: .milestone(RatingMilestone(rating: 5, name: "Deep work", beatCount: 9)),
            onDismiss: {}).caveat == nil)
    }

    /// The same sweep the health card's copy is held to, applied to the arm that
    /// was added. A superlative over one person's own ratings asserts no
    /// relationship, and the copy has to keep it that way.
    @Test("Milestone copy claims no relationship")
    func milestoneCopyIsClean() {
        for rating in 2...5 {
            let content = DayContextCard.Content.milestone(
                RatingMilestone(rating: rating, name: "Deep work", beatCount: 12))
            let words = [DayContextCopy.title(content),
                         DayContextCopy.figure(content),
                         DayContextCopy.sentence(content)].joined(separator: " ").lowercased()

            for banned in ["because", "causes", "caused", "due to", "leads to",
                          "makes you", "results in", "the reason", "explains why",
                          "which is why", "drives", "triggers", "boosts", "improves",
                          "helps", "effect of", "impact of", "influences",
                          "stress", "mood", "energy levels", "fatigue", "healthy",
                          "average", "most people", "others", "normal", "typical",
                          "benchmark", "the norm", "studies", "research",
                          "you should", "consider ", "avoid", "prioritise",
                          "recommend", "make sure", "aim to",
                          "unusually", "rare", "unlike most",
                          "yet", "soon", "more data", "unlock", "locked"] {
                #expect(!words.contains(banned), Comment(rawValue:
                    "\"\(words)\" contains \"\(banned)\""))
            }
            // No verdicts on the rating itself. The app does not know whether a
            // 5 is good, only that it is the highest this person has recorded.
            for verdict in ["good", "bad", "better", "worse", "great", "poor"] {
                #expect(!words.contains(verdict), Comment(rawValue:
                    "\"\(words)\" contains the verdict \"\(verdict)\""))
            }
        }
    }
}
