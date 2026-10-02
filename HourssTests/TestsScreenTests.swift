import Foundation
import Testing
@testable import Hourss

/// The two sections the Tests screen gained when the record stopped being a screen
/// of its own: what is on offer, and what is running.
///
/// The record's own rules are pinned by `ExperimentHistoryTests` and did not move.
/// What is checked here is everything the move could have broken and everything the
/// two new sections could get wrong — a second wording of a card, a count, an empty
/// state that promises something, a label that opens with a figure, and a progress
/// line that borrows the active card's phrasing for a different number.
///
/// **Not `@MainActor`, and that is checked rather than assumed.** `TestsScreen` is an
/// `enum` beside the view rather than a static helper *on* it, so nothing infers
/// main-actor isolation from a SwiftUI type. This project has twice shipped a static
/// helper on a `View` that was isolated by inference, called it from a suite that was
/// not, and watched the test host trap at runtime — which looks like a shrinking test
/// count and not like a crash.
@Suite("Tests screen")
struct TestsScreenTests {

    private static let start = Date(timeIntervalSince1970: 1_767_225_600)

    private let change = "Put one block in your morning on most days this fortnight."
    private let caveat = "Time of day travels with whatever you tend to schedule then."

    private func day(_ offset: Int, from base: Date = TestsScreenTests.start) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
    }

    private func proposal(_ id: String = "time.morning.vs.rest.feeling",
                          standing: ExperimentDesign.Standing = .lead,
                          change: String? = nil) -> ExperimentDesign.Proposal {
        ExperimentDesign.Proposal(
            hypothesisId: id, outcome: .feeling, type: .bestTimeWindow, standing: standing,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            context: nil,
            change: change ?? self.change,
            caveat: caveat,
            priority: .focus, priorityRank: 0, evidenceDays: 20,
            figure: 4.1, baselineFigure: 3.5)
    }

    private func experiment(startedAt: Date,
                            windowDays: Int = Experiment.defaultWindowDays) -> Experiment {
        Experiment(
            hypothesisId: "time.morning.vs.rest.feeling", outcome: .feeling,
            startedAt: startedAt, windowDays: windowDays,
            focusLabel: "Morning", baselineLabel: "The rest of your day",
            premise: "Your morning sessions have felt more energizing.",
            change: change, caveat: caveat)
    }

    // MARK: - On offer

    @Test("An offer is the change the card shows, and never a second wording of it")
    func offerCarriesTheChange() throws {
        let one = proposal()
        let offer = try #require(TestsScreen.offers(from: [one], isEntitled: true).first)
        // Word for word. A proposal somebody accepts has to be the proposal they
        // were shown, and a screen that paraphrased it would be a second place for
        // the same claim to drift from.
        #expect(offer.subject == one.change)
        #expect(offer.id == one.id)
    }

    @Test("Every offer is listed, in the order the engine ranked them")
    func everyOfferIsListed() {
        let ranked = [proposal("a", change: "First change."),
                      proposal("b", change: "Second change."),
                      proposal("c", change: "Third change.")]
        let offers = TestsScreen.offers(from: ranked, isEntitled: true)
        // Showing one of three under a heading that says "on offer" would be a
        // selection the reader cannot see being made — the same argument that keeps
        // abandoned tests in the record.
        #expect(offers.map(\.subject) == ranked.map(\.change))
    }

    /// A confirmed-standing proposal is members-only, and `canSeeProposal` is what
    /// withholds it on Today. A paywall one surface enforces and another forgets is
    /// not a paywall.
    @Test("A members-only offer is withheld from a free reader and shown to a member")
    func membershipIsFilteredTheSameWayTodayFiltersIt() {
        let confirmed = proposal(standing: .confirmed)
        #expect(confirmed.requiresMembership)
        #expect(TestsScreen.offers(from: [confirmed], isEntitled: false).isEmpty)
        #expect(TestsScreen.offers(from: [confirmed], isEntitled: true).count == 1)

        // A lead and a starter are free, for the reason `Proposal` records: they are
        // the first and the only things the app can offer early on.
        for standing in [ExperimentDesign.Standing.lead, .starter] {
            let free = proposal(standing: standing)
            #expect(!free.requiresMembership)
            #expect(TestsScreen.offers(from: [free], isEntitled: false).count == 1)
        }
    }

    @Test("The direction names where an offer is taken on, and says one at a time")
    func theDirectionNamesTheOnePlaceItHappens() {
        let one = TestsScreen.offerDirection(count: 1)
        let several = TestsScreen.offerDirection(count: 3)
        // Today is where the card and its sheet are. Naming the place is the link:
        // this screen is pushed from You and has no route into Today's stack.
        #expect(one.contains("Today"))
        #expect(several.contains("Today"))
        // The plural says the one-at-a-time rule in passing, which is where somebody
        // looking at three offers needs it.
        #expect(several.contains("one of these"))
        #expect(one != several)
        // Neither is a control, and neither repeats the card's own button.
        for text in [one, several] {
            #expect(!text.lowercased().contains(ExperimentCopy.startTitle.lowercased()))
        }
    }

    // MARK: - Running

    @Test("Only a running test fills the running section")
    func onlyAnActiveTestIsRunning() throws {
        #expect(TestsScreen.running(nil, on: Self.start) == nil)

        let active = experiment(startedAt: Self.start)
        #expect(active.phase == .active)
        let running = try #require(TestsScreen.running(active, on: day(3)))
        #expect(running.subject == change)
        #expect(running.id == active.id)

        // Everything that has stopped being open belongs to the record below, and a
        // row in two sections at once is one state drawn twice.
        var stopped = experiment(startedAt: Self.start)
        stopped.abandonedAt = day(5)
        #expect(TestsScreen.running(stopped, on: day(6)) == nil)

        var settled = experiment(startedAt: Self.start)
        settled.settlement = Experiment.Settlement(
            verdict: .heldUp, adherenceDays: 9, baselineDays: 12,
            focusFigure: 4.2, baselineFigure: 3.4, delta: 0.4,
            intervalLow: 0.1, intervalHigh: 0.7, settledAt: settled.endsAt())
        #expect(TestsScreen.running(settled, on: day(20)) == nil)
    }

    @Test("How far in it is, counted from the first day of the window")
    func progressIsAPositionInTheWindow() throws {
        let active = experiment(startedAt: Self.start)
        let firstDay = try #require(TestsScreen.running(active, on: Self.start))
        #expect(firstDay.progress == "Day one of this test.")

        let sixthDay = try #require(TestsScreen.running(active, on: day(5)))
        #expect(sixthDay.progress == "Day six of this test.")
    }

    /// Settling runs on the next launch or foreground, so a window that closed while
    /// the phone was down stays open on the record until somebody picks it up. "Day
    /// fourteen of this test" three days after it ended would be the one line on the
    /// screen that was false.
    @Test("A window that has run out says so rather than counting past its end")
    func aClosedWindowSaysSo() throws {
        let active = experiment(startedAt: Self.start)
        let after = try #require(TestsScreen.running(active, on: day(17)))
        #expect(after.progress == TestsScreen.runningClosed)

        // And it is carefully not a verdict: the window closing and the figures
        // being read are two events, and this is the first.
        let flat = TestsScreen.runningClosed.lowercased()
        for verdict in [Experiment.Verdict.heldUp, .didNotHoldUp, .cannotTell] {
            #expect(!flat.contains(ExperimentCopy.verdictTitle(verdict).lowercased()))
        }
    }

    /// The register the rest of the app reads in. A drawn window is twenty-eight days
    /// long, so a spelling table that stopped at twelve would have switched from "day
    /// twelve" to "day 13" halfway through every drawn month.
    @Test("The day is spelled for every day of the longest window the app offers")
    func theDayIsSpelledAllTheWayThrough() throws {
        let window = Experiment.randomisedWindowDays
        let active = experiment(startedAt: Self.start, windowDays: window)
        for offset in 0..<window {
            let running = try #require(TestsScreen.running(active, on: day(offset)))
            #expect(NarrationGuard.figures(in: running.progress).isEmpty,
                    Comment(rawValue: "a numeral reached the progress line: \(running.progress)"))
        }
    }

    /// The active card already says "nine days of it so far", and that number is
    /// adherence — the days that carried the change. This one is a position in the
    /// window. Two different quantities in the same phrasing would read as one fact
    /// and disagree, which is the drift this codebase documents most often.
    @Test("Progress does not borrow the active card's phrasing for a different number")
    func progressDoesNotBorrowTheCardsWords() throws {
        let running = try #require(TestsScreen.running(experiment(startedAt: Self.start),
                                                      on: day(5)))
        let flat = running.progress.lowercased()
        for borrowed in ["so far", "days of it", "adherence", "you are testing"] {
            #expect(!flat.contains(borrowed),
                    Comment(rawValue: "'\(borrowed)' in: \(running.progress)"))
        }
    }

    /// `evidenceProgress` must never forecast, and the slot's sweep bans the words
    /// that make a count read as a deadline. A deadline is the shape that turns a
    /// count into something to defend, whichever state shows it.
    @Test("Nothing in the running section is a countdown")
    func nothingCountsDown() throws {
        let active = experiment(startedAt: Self.start)
        var lines = [TestsScreen.runningEmpty, TestsScreen.runningClosed]
        for offset in [0, 5, 13, 20] {
            if let running = TestsScreen.running(active, on: day(offset)) {
                lines.append(running.progress)
            }
        }
        for text in lines {
            let flat = text.lowercased()
            for banned in ["days left", "days to go", "until", "remaining", "deadline"] {
                #expect(!flat.contains(banned),
                        Comment(rawValue: "'\(banned)' in: \(text)"))
            }
        }
        // And the window it prints is both of its ends, which is the record's form
        // for the same fact rather than a count towards one of them.
        let running = try #require(TestsScreen.running(active, on: day(5)))
        #expect(running.window.contains("–"))
    }

    // MARK: - Nothing is counted

    /// `RecordFacts` argues this at length and `abandonExperiment` keeps no tally: a
    /// number whose only use is a reproach does not get computed. The two new
    /// sections had their own chance to invent one — how many offers are waiting, how
    /// many tests somebody has taken on — and take neither.
    @Test("Nothing the screen writes for itself counts anything")
    func nothingIsCounted() {
        for text in TestsScreen.authored {
            #expect(NarrationGuard.figures(in: text).isEmpty,
                    Comment(rawValue: "the screen's own copy quoted a figure: \(text)"))
            let flat = text.lowercased()
            for tally in ["out of", "success", "rate", "streak", "record of", "in a row",
                          "so far", "total", "times", "two", "three"] {
                #expect(!flat.contains(tally), Comment(rawValue: "'\(tally)' in: \(text)"))
            }
        }
    }

    // MARK: - The empty states

    @Test("Both new empty states promise nothing")
    func theEmptyStatesPromiseNothing() {
        for text in [TestsScreen.offerEmpty, TestsScreen.offerEmptyWhileRunning,
                     TestsScreen.runningEmpty] {
            let flat = text.lowercased()
            // "Yet" is a promise in one syllable, and for somebody whose record
            // never produces a testable split it is one the app cannot keep.
            // `stillLookingCopy` is the house precedent and this is the same ban.
            for word in ["yet", "soon", "will", "coming", "once you", "start by",
                         "check back", "keep logging"] {
                #expect(!flat.contains(word),
                        Comment(rawValue: "the empty state said '\(word)': \(text)"))
            }
        }
    }

    /// `experimentProposals` returns nothing at all while a test is active, and that
    /// is a refusal rather than a shortage — two concurrent changes make both
    /// unreadable, which is `acceptExperiment`'s hard invariant. "Nothing is on
    /// offer" directly above somebody's own running test would report the wrong one
    /// of the two.
    @Test("Nothing on offer mid-test says why, and the plain version does not")
    func theOfferEmptyStateExplainsARefusalButNotAShortage() {
        #expect(TestsScreen.offerEmptyWhileRunning.lowercased().contains("running"))
        #expect(!TestsScreen.offerEmpty.lowercased().contains("running"))
        #expect(TestsScreen.offerEmpty != TestsScreen.offerEmptyWhileRunning)
        // Still an absence rather than an explanation of the engine: no maths, no
        // mention of hypotheses or windows.
        for text in [TestsScreen.offerEmpty, TestsScreen.offerEmptyWhileRunning] {
            #expect(text.split(separator: ".").count == 1, "one short sentence each")
        }
    }

    // MARK: - Accessibility

    @Test("Every label leads with the subject, never with a figure")
    func labelsLeadWithTheSubject() throws {
        let offer = try #require(TestsScreen.offers(from: [proposal()], isEntitled: true).first)
        #expect(offer.accessibilityLabel.hasPrefix(offer.subject))

        let running = try #require(TestsScreen.running(experiment(startedAt: Self.start),
                                                       on: day(5)))
        #expect(running.accessibilityLabel.hasPrefix(running.subject))
        // Belt and braces for the rule itself: if a digit appears, the subject is
        // already behind it.
        for label in [offer.accessibilityLabel, running.accessibilityLabel] {
            if let digit = label.firstIndex(where: \.isNumber) {
                #expect(label.distance(from: label.startIndex, to: digit) >= running.subject.count)
            }
        }
        // And how far in it is, and which window, are both spoken — so a VoiceOver
        // reader gets what a sighted one gets rather than the subject alone.
        #expect(running.accessibilityLabel.contains(running.progress))
        #expect(running.accessibilityLabel.contains(TestsScreen.spoken(Self.start)))
    }

    // MARK: - The sweep

    /// Mirrors the sweep `ExperimentHistoryTests` runs over the record's own strings.
    /// Only what this file authored is swept: both changes and everything
    /// `ExperimentCopy` writes are answered for where they are written, and
    /// re-sweeping a carried string here would only teach somebody to weaken the
    /// sweep.
    @Test("Every string the screen authored is allowed on screen")
    func authoredCopyPassesTheGuard() {
        for text in TestsScreen.authored {
            if let offence = NarrationGuard.offence(in: text) {
                Issue.record("\"\(text)\" broke a rule that still applies: \(offence)")
            }
        }
    }

    @Test("The three sections are headed, distinctly, in one order")
    func theThreeSectionsAreHeaded() {
        let headings = [TestsScreen.offerEyebrow,
                        TestsScreen.runningEyebrow,
                        TestsScreen.finishedEyebrow]
        #expect(Set(headings).count == 3)
        for heading in headings {
            #expect(!heading.isEmpty)
            // Fixed, not state-carrying. Two of the three are empty on most days, and
            // headings that reported that would open the screen by listing what it
            // does not have.
            #expect(!heading.lowercased().contains("nothing"))
            #expect(!heading.lowercased().contains("no "))
        }
    }
}
