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
    /// separately from it. An enum with two cases is how that is made
    /// unrepresentable rather than merely avoided.
    @Test("A card is a milestone or a standout, never both")
    func contentIsExclusive() {
        let milestone = RatingMilestone(rating: 5, name: "Deep work", beatCount: 9)
        let standout = DayDeviation.Standout(
            metric: .sleepHours, value: 8.4, z: 2.1,
            daysSinceMoreExtreme: 11, historyDays: 200)

        let asMilestone = DayContextCard.Content.milestone(milestone)
        let asHealth = DayContextCard.Content.health(standout)
        #expect(asMilestone != asHealth)

        // A milestone card says nothing about sleep, and a health card says
        // nothing about a rating. Checked on the copy, because the copy is what
        // a person actually receives.
        let milestoneWords = [DayContextCopy.title(asMilestone),
                              DayContextCopy.figure(asMilestone),
                              DayContextCopy.sentence(asMilestone)].joined(separator: " ").lowercased()
        for word in ["night", "sleep", "heart", "breathing", "hrv"] {
            #expect(!milestoneWords.contains(word), Comment(rawValue:
                "\"\(milestoneWords)\" mentions \(word) — a health reading beside a rating"))
        }

        let healthWords = [DayContextCopy.title(asHealth),
                           DayContextCopy.figure(asHealth),
                           DayContextCopy.sentence(asHealth)].joined(separator: " ").lowercased()
        for word in ["rated", "rating", "/ 5", "out of 5"] {
            #expect(!healthWords.contains(word), Comment(rawValue:
                "\"\(healthWords)\" mentions \(word) — the standout must not move with a score"))
        }
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
