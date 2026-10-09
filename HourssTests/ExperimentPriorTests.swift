import Foundation
import Testing
@testable import Hourss

/// The prior-led proposal, and the framing rule that is the whole of its licence.
///
/// **Why this file is the largest test file in the feature for the smallest amount of
/// code.** `PRD-VITALS.md` §9 reverses `NarrationGuard`'s population ban in one
/// function. That ban is the reason this app can claim to be about you, and the only
/// thing standing between the reversal and a population claim is the wording of two
/// sentences. Wording erodes — somebody adds "so" to make it read better, somebody
/// drops the second sentence to make the card shorter, somebody puts the share in to
/// make it feel grounded — and every one of those edits looks like an improvement at
/// the moment it is made. So the framing carries more tests than the feature does:
/// one per required part, one per forbidden link word, one per forbidden verdict, and
/// the pins that make the exemption useless to anything but a correctly framed
/// premise.
struct ExperimentPriorTests {

    // MARK: Fixtures

    /// Somebody who has just finished onboarding: priorities stated, the default
    /// picker, nothing logged, no Health. The case this whole source exists for.
    static let activities = Activity.defaults

    static func offers(_ priorities: [Priority],
                       activities: [Activity] = Self.activities,
                       measured: Set<String> = [],
                       excluding: Set<String> = []) -> [ExperimentDesign.Proposal] {
        ExperimentPriors.offers(for: priorities, activities: activities,
                                measured: measured, excluding: excluding)
    }

    /// Every premise this source can put on a screen, for the whole priority list.
    static var everyPremise: [String] {
        var out = offers(Priority.allCases).map(\.premise)
        // And the arms a priority cannot reach today, so a row added to the table
        // tomorrow is swept by everything below rather than by nothing.
        for band in TimeBucket.allCases {
            for priority in Priority.allCases {
                if let text = ExperimentCopy.priorPremise(.band(band, priority)) { out.append(text) }
            }
        }
        for activity in Activity.defaults {
            if let text = ExperimentCopy.priorPremise(.activity(activity.name)) { out.append(text) }
        }
        if let text = ExperimentCopy.priorPremise(.daysOff) { out.append(text) }
        return out
    }

    /// Whole-word containment, matched the way `NarrationGuard` matches: every run of
    /// punctuation reduced to one space, so "two weeks would say." contains "would say"
    /// and "Carpentry" does not contain "try". Reimplemented here rather than reached
    /// for because `NarrationGuard.flatten` is private, and a sweep's own matcher is
    /// not something a test should be able to loosen.
    static func says(_ text: String, _ phrase: String) -> Bool {
        var flattened = ""
        var pendingSpace = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSpace && !flattened.isEmpty { flattened.append(" ") }
                pendingSpace = false
                flattened.append(character)
            } else {
                pendingSpace = true
            }
        }
        return (" " + flattened + " ").contains(" " + phrase.lowercased() + " ")
    }

    // MARK: The premise, verbatim

    /// The sentence `PRD-VITALS.md` §9 writes out, produced by the app.
    ///
    /// Pinned verbatim rather than by its parts, and this is the one assertion in the
    /// suite that is allowed to be brittle. §9's example is the specification; if the
    /// app stops producing it, that is a decision somebody should have to make on
    /// purpose in front of this line.
    @Test("A focus-led proposal states the premise §9 specifies, word for word")
    func theFocusPremiseIsTheSpecifiedOne() throws {
        let proposal = try #require(Self.offers([.focus]).first)
        #expect(proposal.premise == "Mornings suit focused work for a lot of people. "
                + "Nobody knows yet whether they suit you — two weeks would say.")
    }

    @Test("An activity-led proposal names the activity and asks about this person")
    func theActivityPremiseAsks() throws {
        let proposal = try #require(Self.offers([.energy]).first)
        #expect(proposal.premise == "Exercise suits a lot of people. "
                + "Nobody knows yet whether it suits you — two weeks would say.")
    }

    @Test("A days-off proposal states the contrast as an expectation about people")
    func theDaysOffPremiseAsks() throws {
        let proposal = try #require(Self.offers([.balance]).first)
        #expect(proposal.premise == "Days off read differently from working days for a lot "
                + "of people. Nobody knows yet whether yours do — two weeks would say.")
    }

    /// The window length is spelled, by the same function the change uses, so the two
    /// sentences on one card name one commitment — and so no digit reaches a premise.
    @Test("The premise names the window in the words the change uses")
    func thePremiseSpellsItsWindow() {
        for premise in Self.everyPremise {
            #expect(premise.contains(ExperimentCopy.span(Experiment.defaultWindowDays)),
                    Comment(rawValue: "did not name the window: \(premise)"))
            #expect(premise.rangeOfCharacter(from: .decimalDigits) == nil,
                    Comment(rawValue: "a digit reached a premise: \(premise)"))
        }
    }

    // MARK: The three parts

    /// Part 1, part 2 and part 3, present in every premise the app can produce.
    @Test("Every premise carries all three of §9's parts")
    func everyPremiseHasAllThreeParts() {
        for premise in Self.everyPremise {
            #expect(NarrationGuard.populationNamed.contains { Self.says(premise, $0) },
                    Comment(rawValue: "part 1 missing: \(premise)"))
            #expect(NarrationGuard.notKnownOfYou.contains { Self.says(premise, $0) },
                    Comment(rawValue: "part 2 missing: \(premise)"))
            #expect(NarrationGuard.settledByTheTest.contains { Self.says(premise, $0) },
                    Comment(rawValue: "part 3 missing: \(premise)"))
            #expect(Self.says(premise, "you") || Self.says(premise, "your")
                    || Self.says(premise, "yours"),
                    Comment(rawValue: "not addressed to this person: \(premise)"))
        }
    }

    /// A premise missing part 1 is refused.
    ///
    /// **The part being tested is "named explicitly".** The doctored string below says
    /// the same thing in the passive voice, which is exactly the erosion §9 names: a
    /// reader must not have to work out whose fact this is. It carries parts 2 and 3
    /// intact and is still refused, which is the whole assertion.
    @Test("A premise that does not name whose fact it is fails its sweep")
    func partOneIsRequired() {
        let passive = "It is known that mornings suit focused work. "
            + "Nobody knows yet whether they suit you — two weeks would say."
        #expect(NarrationGuard.priorPremiseOffence(in: passive)
                == .framing("whose fact this is"))
        // And the guard it bypasses would have let that one through, which is why the
        // framing check cannot be delegated to `offence`.
        #expect(NarrationGuard.offence(in: passive) == nil)
    }

    /// A premise missing part 2 is refused, and this is the part doing the work: what
    /// is left without it is a population claim with a decoration on it.
    @Test("A premise that does not say it is unknown of this person fails its sweep")
    func partTwoIsRequired() {
        let decorated = "Mornings suit focused work for a lot of people. "
            + "Two weeks of your own would say more."
        #expect(NarrationGuard.priorPremiseOffence(in: decorated)
                == .framing("that it is not known of them"))
    }

    /// A premise that states the expectation and the unknown but never says a
    /// fortnight would answer it has made the first part an answer rather than a
    /// question.
    @Test("A premise that does not say the test would settle it fails its sweep")
    func partThreeIsRequired() {
        let unanswerable = "Mornings suit focused work for a lot of people. "
            + "Nobody knows yet whether they suit you."
        #expect(NarrationGuard.priorPremiseOffence(in: unanswerable)
                == .framing("that the test would settle it"))
    }

    /// Part 2 in words but not about the reader. "Nobody knows yet whether they suit
    /// anybody" has the vocabulary of the rule and none of its content.
    @Test("A premise not addressed to this person fails its sweep")
    func theReaderIsRequired() {
        let unaddressed = "Mornings suit focused work for a lot of people. "
            + "Nobody knows yet whether they suit anybody — two weeks would say."
        #expect(NarrationGuard.priorPremiseOffence(in: unaddressed)
                == .framing("said to this person"))
    }

    // MARK: The link word, which is how this erodes

    /// One test per link word, on both sides: no premise the app produces contains it,
    /// and a premise that did would be refused.
    ///
    /// **This is the single likeliest failure and it is one word wide.** "A lot of
    /// people find mornings suit focused work, so give yours a fortnight" differs from
    /// the allowed sentence by two letters and is the claim the population ban exists
    /// to stop — the moment the expectation becomes a reason to *act* rather than a
    /// reason to *ask*. `NarrationGuard.causal` cannot hold the bare conjunctions,
    /// because "so" on a list applied to every string in the app would reject ordinary
    /// prose; `populationLinks` holds them for the one sentence where the thing being
    /// linked is a fact about other people.
    @Test("No link word joins the fact to the change",
          arguments: NarrationGuard.populationLinks)
    func noLinkWordReachesAPremise(link: String) {
        for premise in Self.everyPremise {
            #expect(!Self.says(premise, link),
                    Comment(rawValue: "\"\(link)\" reached a premise: \(premise)"))
        }
        let linked = "Mornings suit focused work for a lot of people, \(link) "
            + "nobody knows yet whether they suit you — two weeks would say."
        #expect(NarrationGuard.priorPremiseOffence(in: linked) != nil,
                Comment(rawValue: "\"\(link)\" passed the sweep"))
    }

    /// The four words §9 names, plus the neighbourhood they live in. "Should" was
    /// already on `instruction`; "best", "optimal", "ideal" and "most efficient" are
    /// judgements rather than instructions and nothing in the app had needed to refuse
    /// them before this phase.
    @Test("No verdict reaches a premise", arguments: NarrationGuard.priorPremiseVerdicts)
    func noVerdictReachesAPremise(verdict: String) {
        for premise in Self.everyPremise {
            #expect(!Self.says(premise, verdict),
                    Comment(rawValue: "\"\(verdict)\" reached a premise: \(premise)"))
        }
        let judged = "Mornings are the \(verdict) time for focused work for a lot of people. "
            + "Nobody knows yet whether they suit you — two weeks would say."
        #expect(NarrationGuard.priorPremiseOffence(in: judged) != nil,
                Comment(rawValue: "\"\(verdict)\" passed the sweep"))
    }

    @Test("§9's own four words are refused by name")
    func theNamedVerdictsAreRefused() {
        for word in ["should", "best", "optimal", "ideal", "most efficient"] {
            let text = "Mornings suit focused work \(word) for a lot of people. "
                + "Nobody knows yet whether they suit you — two weeks would say."
            #expect(NarrationGuard.priorPremiseOffence(in: text) != nil,
                    Comment(rawValue: "\"\(word)\" passed the sweep"))
        }
    }

    /// Comparing *them* to people is a different act and still forbidden outright.
    /// These never reach `priorPremiseOffence` in production — nothing builds a premise
    /// from them — and they are refused there anyway, because the lift is for naming
    /// people and never for ranking this person among them.
    @Test("A premise that calls this person usual or unusual is refused")
    func noComparisonOfThisPerson() {
        for text in ["Like a lot of people, your mornings are typical. "
                        + "Nobody knows yet whether they suit you — two weeks would say.",
                     "Unlike most, a lot of people suit mornings. "
                        + "Nobody knows yet whether they suit you — two weeks would say.",
                     "Your mornings run normal for a lot of people. "
                        + "Nobody knows yet whether they suit you — two weeks would say."] {
            #expect(NarrationGuard.priorPremiseOffence(in: text) != nil,
                    Comment(rawValue: "a comparison of this person passed: \(text)"))
        }
    }

    // MARK: No number from the table

    /// Checklist items 9 and 16: no `share` reaches any string.
    ///
    /// **Structural, not vigilant.** `Surprise.expectedRaised` returns keys and no
    /// figures, so this source has no number to spend even if it wanted one. The
    /// assertion is the belt: every digit run is refused by the premise's own sweep,
    /// and every rendering a share could plausibly take as words is on
    /// `priorPremisePrecision`.
    @Test("No prior's number, in digits or in words, reaches any string on an offer")
    func noShareReachesAString() {
        var strings: [String] = []
        for proposal in Self.offers(Priority.allCases) {
            strings += [proposal.premise, proposal.change, proposal.caveat,
                        proposal.focusLabel, proposal.baselineLabel]
            if let context = proposal.context { strings.append(context) }
        }
        for premise in Self.everyPremise {
            #expect(premise.rangeOfCharacter(from: .decimalDigits) == nil,
                    Comment(rawValue: "a digit reached a premise: \(premise)"))
            for word in NarrationGuard.priorPremisePrecision {
                #expect(!Self.says(premise, word),
                        Comment(rawValue: "\"\(word)\" reached a premise: \(premise)"))
            }
        }
        // Every share in the table, in the shapes a careless `String(describing:)` or
        // a percentage would produce. None of them may appear anywhere on an offer.
        for text in strings {
            for rendering in Self.everyShareRendering {
                #expect(!text.contains(rendering),
                        Comment(rawValue: "\"\(rendering)\" reached a string: \(text)"))
            }
        }
    }

    /// The shares the table holds, as digits. Written out rather than read from
    /// `Surprise.priors`, which is private — and private is the reason this test can
    /// only check renderings rather than the values. Covers every share in the file at
    /// the time of writing, including all six pairings.
    static let everyShareRendering: [String] = {
        let shares = [0.56, 0.58, 0.60, 0.62, 0.66, 0.68, 0.70, 0.74, 0.76, 0.78, 0.82, 0.85]
        return shares.flatMap { share -> [String] in
            let whole = Int((share * 100).rounded())
            return ["\(share)", "\(whole)%", "\(whole) percent"]
        }
    }()

    // MARK: The exemption, and how narrowly it is scoped

    /// The premise needs the lift, which is what makes the lift load-bearing rather
    /// than decorative.
    ///
    /// **If this test fails because the premise no longer trips `.population`, the
    /// premise has stopped naming whose fact it is** — §9's first part — and the right
    /// fix is the premise, never this assertion. The four phrases a premise may use are
    /// on `NarrationGuard.population` precisely so that this is true: without them
    /// there, any string in the app could say "a lot of people" and clear every sweep
    /// in the suite.
    @Test("Every premise is refused by the sweep every other string in the app passes")
    func thePremiseNeedsTheLift() {
        for premise in Self.everyPremise {
            switch NarrationGuard.offence(in: premise) {
            case .population:
                continue
            case let other:
                Issue.record(Comment(rawValue: "a premise cleared the population ban, so "
                    + "the ban is not doing anything: \(premise) → "
                    + "\(String(describing: other))"))
            }
        }
    }

    /// And the lift is the only thing that lets it through.
    @Test("The one exempt sweep accepts every premise the app produces")
    func theLiftAcceptsEveryPremise() {
        for premise in Self.everyPremise {
            #expect(NarrationGuard.priorPremiseOffence(in: premise) == nil,
                    Comment(rawValue: "the premise failed its own sweep: \(premise)"))
        }
    }

    /// The property that makes the exemption safe to have at all: it is useless for
    /// anything except a correctly framed premise.
    ///
    /// Nothing can route a population claim through `priorPremiseOffence`, because a
    /// string that names people and is not a premise fails it as surely as it fails
    /// `offence`. That is why §9's "lifted in exactly one function" is enforceable: the
    /// function cannot be misused by its one caller or by a second one.
    @Test("The exempt sweep is not a bypass for anything that is not a premise")
    func theLiftIsNotABypass() {
        for text in ["A lot of people feel better in the morning.",
                     "Mornings suit focused work for a lot of people.",
                     "A lot of people do their best work early, so start earlier.",
                     "Deep work suits mornings for a lot of people. Yours read 4.2.",
                     "A lot of people sleep badly, which is why your mornings drag."] {
            #expect(NarrationGuard.priorPremiseOffence(in: text) != nil,
                    Comment(rawValue: "a population claim cleared the exempt sweep: \(text)"))
        }
    }

    /// Checklist item 10: nowhere but a proposal's premise.
    ///
    /// Every other string on a prior-led offer goes through the sweep every string in
    /// the app goes through, with `instruction` excluded as it is everywhere in this
    /// feature and nothing else excluded — so a population word in a change, a caveat,
    /// a label or the quiet second line fails here.
    @Test("No field of a prior-led offer but the premise may name people")
    func onlyThePremiseNamesPeople() {
        for proposal in Self.offers(Priority.allCases) {
            var strings = [proposal.change, proposal.caveat,
                           proposal.focusLabel, proposal.baselineLabel]
            if let context = proposal.context { strings.append(context) }
            if let ask = proposal.randomisedAsk { strings.append(ask) }
            for text in strings {
                let offence = NarrationGuard.offence(
                    in: text, allowingFigures: NarrationGuard.figures(in: text))
                switch offence {
                case .none, .instruction: continue
                case .some(let found):
                    Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
                }
            }
        }
    }

    /// Nothing else in the app clears a sweep including `.population`.
    ///
    /// **Where the rest of that claim is enforced.** Every copy surface in this app is
    /// already swept by a test that treats a `.population` offence as a failure:
    /// `ExperimentDesignTests.copyPassesTheGuard` over everything `ExperimentCopy` can
    /// produce and every starter, `ProposalSheetTests` over the accept sheet,
    /// `RecordFactsTests` over the record facts, `NarrationTests` over generated and
    /// templated narration, `TestsScreenTests`, `ExperimentHistoryTests`,
    /// `ResidualCopyTests`, `RandomisedCardTests`, `DayDeviationTests` and
    /// `QuestionAnnouncementTests` over theirs. Those are the census; this is the one
    /// string that had to be carved out of it, swept here instead, and what this test
    /// adds is the carve-out's own boundary: the premise-adjacent copy that a careless
    /// edit would be most likely to widen.
    @Test("The copy next to the premise still cannot name people")
    func theNeighbouringCopyIsUnchanged() {
        var strings: [String] = []
        for type in [InsightType.bestTimeWindow, .durationSweetSpot, .activityEnergizer,
                     .workdayContrast, .sleepContext, .bodyContext] {
            strings.append(ExperimentCopy.starterUnknown(
                type: type, focusLabel: "Morning", baselineLabel: "Rest of the day",
                metric: .sleepHours))
            if let change = ExperimentCopy.change(
                type: type, focusLabel: "Morning", metric: .sleepHours) {
                strings.append(change)
            }
        }
        for standing in ExperimentDesign.Standing.allCases {
            strings.append(ExperimentCopy.eyebrow(for: standing))
        }
        for text in strings {
            let offence = NarrationGuard.offence(
                in: text, allowingFigures: NarrationGuard.figures(in: text))
            switch offence {
            case .none, .instruction: continue
            case .some(let found):
                Issue.record("\"\(text)\" broke a rule that still applies: \(found)")
            }
        }
    }

    /// A person's own activity name goes into a premise, so the fail-closed path is
    /// not theoretical. An activity carrying a clinical word or a figure produces no
    /// premise and therefore no offer, rather than a sentence this app may not say.
    @Test("An activity name that cannot be framed produces no premise")
    func abadNameProducesNoPremise() {
        #expect(ExperimentCopy.priorPremise(.activity("Stress relief")) == nil)
        #expect(ExperimentCopy.priorPremise(.activity("Sprint 3")) == nil)
        #expect(ExperimentCopy.priorPremise(.activity("Exercise")) != nil)
    }

    // MARK: The pairings

    /// Phase 4, items 14 and 16: `activity × band`, keyed on the id grammar.
    @Test("A pairing is keyed as the two keys it joins")
    func aPairingIsKeyedOnTheIdGrammar() {
        #expect(Surprise.pairKey(activity: "deep-work", band: .morning)
                == "activity.deep-work.timeOfDay.morning")
        #expect(Surprise.hasExpectation(of: Surprise.pairKey(activity: "deep-work",
                                                            band: .morning)))
        #expect(Surprise.hasExpectation(of: Surprise.pairKey(activity: "deep-work",
                                                            band: .afternoon)))
        // Midday has no pairing for the same reason it has no row of its own.
        #expect(!Surprise.hasExpectation(of: Surprise.pairKey(activity: "deep-work",
                                                             band: .midday)))
        // An activity the table says nothing about stays neutral, pairing or not.
        #expect(!Surprise.hasExpectation(of: Surprise.pairKey(activity: "hedge-trimming",
                                                             band: .morning)))
    }

    /// The case that makes a pairing worth a key: it points where its own band does
    /// not. `timeOfDay.evening` expects a session to read below, so an evening could
    /// never be asked about on the band alone — and the belief about creative work in
    /// an evening runs the other way.
    @Test("A pairing can make a band askable that the band's own row cannot")
    func aPairingOverridesItsBand() {
        #expect(Surprise.expectedRaised(among: ["timeOfDay.evening"]).isEmpty)
        #expect(Surprise.expectedRaised(
            among: [Surprise.pairKey(activity: "creative", band: .evening)])
                == ["activity.creative.timeOfDay.evening"])
        // And the other way: deep work in an afternoon is refused where the plain
        // afternoon row would have been refused too, so the pairing never opens a
        // question the table expects a sour answer to.
        #expect(Surprise.expectedRaised(
            among: [Surprise.pairKey(activity: "deep-work", band: .afternoon)]).isEmpty)
    }

    /// Most expected first, with a deterministic tie-break, and no share in sight.
    @Test("Expectations come back strongest first and never carry their number")
    func expectationsAreOrderedWithoutLeakingAShare() {
        let ordered = Surprise.expectedRaised(among: [
            "activity.social", "workday.non", "activity.exercise",
            "timeOfDay.afternoon", "activity.hedge-trimming",
        ])
        // 0.85, then 0.78, then 0.60. The afternoon points downwards and the invented
        // activity has no row, so neither is returned at all.
        #expect(ordered == ["workday.non", "activity.exercise", "activity.social"])
    }

    /// Phase 4 changed no ordering of anything measured, which is the reason it needed
    /// no existing test to move.
    ///
    /// A `Pattern` carries one family, so a two-family key cannot be built from a
    /// finding and `expectedness` can never reach a pairing row. "Deep work" as a
    /// plain activity is absent from the table and scores exactly one bit, exactly as
    /// it did before the pairings were added.
    @Test("Pairings are unreachable from a finding")
    func pairingsAreUnreachableFromAFinding() {
        let deepWork = Surprise.Pattern(family: .activity, subject: "deep-work", raised: true)
        #expect(Surprise.expectedness(of: deepWork) == 0.5)
        // The band row is reached and the pairing is not. Asserted as "more ordinary
        // than neutral" rather than against a literal: the table's values were
        // coarsened to three levels in `PRD-HOURS.md` phase 5, because two decimals
        // claimed a precision nobody had measured, and a test pinned to the old
        // hundredth would fail for that honesty rather than for a change of
        // behaviour. What this test is about is which row is found, not what is in it.
        let morning = Surprise.Pattern(family: .timeOfDay, subject: "morning", raised: true)
        let score = Surprise.expectedness(of: morning)
        #expect(score > 0.5, Comment(rawValue: "the band row was not reached: \(score)"))
        #expect(score < 1)
    }

    // MARK: The offer

    /// One offer per priority that has an expectation behind it, in the person's own
    /// order, with the rank they stated.
    @Test("One offer per priority, in the person's own order")
    func oneOfferPerPriority() {
        let proposals = Self.offers([.energy, .balance, .focus])
        #expect(proposals.map(\.priority) == [.energy, .balance, .focus])
        #expect(proposals.map(\.priorityRank) == [0, 1, 2])
        #expect(proposals.map(\.type) == [.activityEnergizer, .workdayContrast, .bestTimeWindow])
    }

    /// The three priorities that ask only about body associations get nothing here, and
    /// the comment on `candidates` is the argument: the change for one is responsive
    /// scheduling keyed to a Health reading, which this source has no Health history
    /// for, and the only other sentence available would be an instruction about the
    /// body, which this app does not give at any confidence.
    @Test("A priority with no expectation this source can act on is offered nothing")
    func bodyPrioritiesAreNotServed() {
        #expect(Self.offers([.sleep]).isEmpty)
        #expect(Self.offers([.movement]).isEmpty)
        #expect(Self.offers([.calm]).isEmpty)
    }

    @Test("Nothing stated, nothing offered")
    func noPrioritiesNoOffers() {
        #expect(Self.offers([]).isEmpty)
    }

    /// Needs neither Health nor a single logged session — which is the whole point of
    /// the phase. An empty picker costs only the activity arm.
    @Test("An offer arrives with no Health and nothing logged")
    func itNeedsNothingButAPriority() throws {
        let proposal = try #require(Self.offers([.focus], activities: []).first)
        #expect(proposal.standing == .starter)
        #expect(proposal.evidenceDays == 0)
        #expect(proposal.figure == 0)
        #expect(proposal.baselineFigure == 0)
        // Free, for the reason a starter is free: it is the only thing the app can
        // offer on day one.
        #expect(!proposal.requiresMembership)
        #expect(proposal.isStarter)
    }

    /// The id is the registry's, not this file's. A hand-typed id drifting by one
    /// character would settle every one of these as "cannot tell" two weeks later, on
    /// somebody else's phone, silently — the failure `ExperimentStarters` takes its ids
    /// from the registry to avoid, and this source reuses that blueprint rather than
    /// repeating the risk.
    @Test("Every offer is keyed to a hypothesis the registry will mint")
    func everyOfferIsKeyedToTheRegistry() {
        let registered = Set(HypothesisRegistry.hypotheses(for: []).map(\.id))
        for proposal in Self.offers([.focus, .balance]) {
            #expect(registered.contains(proposal.hypothesisId),
                    Comment(rawValue: "not in the registry: \(proposal.hypothesisId)"))
        }
    }

    /// The change is the measured path's sentence, unaltered. Two wordings of one
    /// change would mean the day-one offer and the day-twelve offer proposing the same
    /// fortnight in two voices.
    @Test("The change is the one the measured path asks for")
    func theChangeIsShared() throws {
        let proposal = try #require(Self.offers([.focus]).first)
        #expect(proposal.change == ExperimentCopy.change(
            type: .bestTimeWindow, focusLabel: "Morning", metric: nil))
    }

    /// Stands down once the engine can read the question for itself. Saying "nobody
    /// knows yet whether mornings suit you" about a split the engine has read twelve
    /// days of is the app contradicting itself in public.
    @Test("A measured question is not asked again")
    func measuredQuestionsStandDown() throws {
        let proposal = try #require(Self.offers([.focus]).first)
        #expect(Self.offers([.focus], measured: [proposal.hypothesisId]).isEmpty)
        #expect(Self.offers([.focus], excluding: [proposal.hypothesisId]).isEmpty)
    }

    /// Two priorities never produce two offers for one hypothesis.
    @Test("One hypothesis is offered once")
    func idsAreNotRepeated() {
        let proposals = Self.offers(Priority.allCases)
        #expect(Set(proposals.map(\.hypothesisId)).count == proposals.count)
    }

    /// The activity named is one they can choose. An archived activity is not one, and
    /// a picker the table says nothing about leaves the energy arm empty rather than
    /// reaching for a name nobody has.
    @Test("An offer never names an activity the person does not have")
    func activitiesComeFromTheirPicker() throws {
        var archived = Activity(name: "Exercise", category: "body", sortOrder: 0)
        archived.isArchived = true
        let own = [archived, Activity(name: "Social", category: "life", sortOrder: 1)]
        let proposal = try #require(Self.offers([.energy], activities: own).first)
        #expect(proposal.focusLabel == "Social")

        #expect(Self.offers([.energy], activities: [
            Activity(name: "Hedge trimming", category: "life", sortOrder: 0)
        ]).isEmpty)
    }

    /// The quiet second line is the absence, narrowed from "nobody knows" to something
    /// a reader can check against their own record.
    @Test("The offer carries the specific absence under the premise")
    func theContextNarrowsThePremise() throws {
        let proposal = try #require(Self.offers([.focus]).first)
        #expect(proposal.context == "Nothing you have logged says yet whether your morning "
                + "feels any different from the rest of your day.")
    }
}
