import Foundation
import Testing
@testable import Hourss

/// That a question which clears its gate is announced once, with its answer on it.
///
/// The two halves this suite is actually guarding are the two the feature can fail
/// at silently. **Once, ever** — a sheet that comes back is a sheet somebody learns
/// to dismiss without reading, and nothing on screen would ever reveal that it had
/// happened. **The answer, carried** — including when the answer is that nothing
/// separated, which is the common case, and which has to arrive in the same sheet at
/// the same weight or the feature becomes the slot machine `PRD-LOCKS.md` §2
/// forbids.
///
/// `@MainActor` on the suite rather than `nonisolated` on anything it calls: the
/// store is `@MainActor`, and this project has twice watched a `nonisolated` helper
/// compile and then trap at runtime, which reads as a shrinking test count rather
/// than as a crash.
@Suite("Questions that open")
@MainActor
struct QuestionAnnouncementTests {

    private func temporaryURL() -> URL {
        URL.temporaryDirectory.appending(path: "hourss-announce-\(UUID().uuidString).json")
    }

    /// A person with a history, past onboarding, written to disk.
    ///
    /// Persisted deliberately: half of what is under test here only exists across a
    /// relaunch, and assigning to `sessions` does not write anything by itself.
    ///
    /// **One rebuild, not two.** `applyHealthContext` ends by rebuilding, so calling
    /// `rebuildInsights()` after it runs the whole engine — two bootstraps at two
    /// thousand resamples and the interaction search — a second time for the same
    /// answer. At three stores a test that is most of this suite's running time, and
    /// a suite that gets materially slower is the signal this project uses to catch
    /// exactly that mistake.
    ///
    /// - Parameter health: whether the daily context is applied, which is what makes
    ///   the `health.*` family exist at all. Off by default, because most of what is
    ///   under test here is about questions the sessions alone produce and health is
    ///   another rebuild.
    private func store(_ person: SyntheticCohort.Person,
                       health: Bool = false,
                       at url: URL? = nil) -> HourssStore {
        let store = HourssStore(repository: url.map { FileRecordRepository(url: $0) }
                                ?? InMemoryRecordRepository())
        store.hasCompletedOnboarding = true
        store.profile.priorities = [.focus, .energy, .balance]
        store.activities = person.activities
        store.sessions = person.sessions
        store.reflections = person.reflections
        if health {
            store.applyHealthContext(person.healthByDay)
        } else {
            store.rebuildInsights()
        }
        store.persist()
        return store
    }

    /// One answerable question held back, which is the record somebody has the
    /// morning after a gate cleared.
    private func withhold(_ id: String, in store: HourssStore) {
        store.seedAnnouncedQuestions(Set(store.answerableHypotheses).subtracting([id]))
    }

    /// An answerable question the engine published a claim for, or did not.
    private func answerable(in store: HourssStore, claimed: Bool) -> String? {
        store.answerableHypotheses.first { id in
            store.insights.contains { $0.id == Engine.identity(of: id) } == claimed
        }
    }

    // MARK: - The decision, on its own

    @Test("A first run takes a baseline and says nothing")
    func firstRunIsSilent() {
        // Everything opens at once on a first run — a new install with a history
        // behind it, or the first launch of the build that added this — and an
        // announcement about one of fifteen simultaneous openings would mean
        // nothing. So the first run absorbs the lot.
        let detection = QuestionAnnouncement.detect(answerable: ["a", "b"], told: nil)
        #expect(detection.opened == nil)
        #expect(detection.told == ["a", "b"])
    }

    @Test("One at a time, and the rest are not held over")
    func noQueue() {
        // Three open together. One is announced and the other two are marked told
        // with it, rather than drip-fed over the next three launches — which is the
        // queue §5 refuses, just spread thin enough to be harder to see. Nothing is
        // lost: all three are open on Patterns with their answers beside them.
        let detection = QuestionAnnouncement.detect(answerable: ["a", "b", "c"], told: [])
        #expect(detection.opened == "a")
        #expect(detection.told == ["a", "b", "c"])
    }

    @Test("A key is never taken back out")
    func keysOnlyGrow() {
        // A session deleted can make an answerable question unanswerable again. When
        // it later re-opens it must not announce a second time.
        let detection = QuestionAnnouncement.detect(answerable: [], told: ["a"])
        #expect(detection.opened == nil)
        #expect(detection.told == ["a"])
    }

    // MARK: - Once, ever

    @Test("Nothing is announced on the launch that takes the baseline")
    func baselineSaysNothing() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        #expect(store.announcedHypotheses == nil, "a fresh record has no baseline")
        #expect(!store.answerableHypotheses.isEmpty, "this cohort should answer something")

        store.announceOpenedQuestion()

        #expect(store.openedQuestion == nil)
        #expect(store.announcedHypotheses == Set(store.answerableHypotheses))
    }

    /// `PRD-LOCKS.md` §10 item 14, pinned.
    @Test("An announcement never fires twice for one question")
    func neverTwice() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = store(SyntheticCohort.afternoonSlump, at: url)
        first.announceOpenedQuestion()                       // the baseline
        let opened = try #require(first.answerableHypotheses.first)
        withhold(opened, in: first)

        first.announceOpenedQuestion()
        #expect(first.openedQuestion?.hypothesisId == opened)

        // Again, in the same launch. `rebuildInsights` runs many times over one
        // launch and the announcement has to survive that; the keys are spent before
        // the sheet is raised, which is the whole of the mechanism.
        first.openedQuestion = nil
        first.announceOpenedQuestion()
        #expect(first.openedQuestion == nil, "the same question was announced twice in one launch")

        // And on the next launch, which is the half that only the file can answer.
        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.announcedHypotheses?.contains(opened) == true)
        second.announceOpenedQuestion()
        #expect(second.openedQuestion == nil, "the same question was announced again on relaunch")
    }

    @Test("An empty baseline is not a missing one, so the first question to open still speaks")
    func emptyBaselineIsNotMissing() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // A new person: past onboarding, nothing logged, nothing answerable. The
        // baseline is taken and it is empty.
        let first = HourssStore(repository: FileRecordRepository(url: url))
        first.hasCompletedOnboarding = true
        first.persist()
        first.announceOpenedQuestion()
        #expect(first.openedQuestion == nil)
        #expect(first.announcedHypotheses == [])

        // Weeks later. Had the empty baseline been written as a missing key — which
        // is what every other array on the record does with empty — this launch
        // would read as another first run and swallow the first question this person
        // ever opened, which is the one the feature exists for.
        let second = HourssStore(repository: FileRecordRepository(url: url))
        #expect(second.announcedHypotheses == [], "an empty baseline read as a missing one")

        let person = SyntheticCohort.afternoonSlump
        second.activities = person.activities
        second.sessions = person.sessions
        second.reflections = person.reflections
        second.rebuildInsights()
        second.announceOpenedQuestion()
        #expect(second.openedQuestion != nil, "the first question ever to open was swallowed")
    }

    @Test("Nothing is announced, and nothing spent, before onboarding is finished")
    func silentBehindTheGate() {
        let store = store(SyntheticCohort.afternoonSlump)
        store.hasCompletedOnboarding = false

        store.announceOpenedQuestion()

        #expect(store.openedQuestion == nil)
        // Not spent, which matters more than not shown: `RootView` keeps onboarding,
        // the account gate and the Health screen in front of the tabs, so a sheet
        // raised behind any of them would be a key burned on something nobody saw.
        #expect(store.announcedHypotheses == nil)
    }

    @Test("Only a question that cleared its gate is ever announced")
    func nothingUnderPoweredLeaks() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let opened = try #require(store.answerableHypotheses.first)
        withhold(opened, in: store)
        store.announceOpenedQuestion()

        let announcement = try #require(store.openedQuestion)
        #expect(store.answerableHypotheses.contains(announcement.hypothesisId))

        let waiting = Engine.pending(for: EngineInput(observations: store.engineObservations,
                                                      priorities: store.profile.priorities))
        #expect(!waiting.contains { $0.hypothesis.id == announcement.hypothesisId },
                "a question that cannot be asked was announced as open")
    }

    // MARK: - The answer, carried

    @Test("A question that found something carries the feed's own sentence")
    func carriesTheClaim() throws {
        let store = store(SyntheticCohort.morningDeepWork)
        let claimed = try #require(answerable(in: store, claimed: true),
                                   "this cohort should publish at least one claim")
        withhold(claimed, in: store)
        store.announceOpenedQuestion()

        let sheet = try #require(store.openedQuestion?.sheet)
        let insight = try #require(store.insights.first { $0.id == Engine.identity(of: claimed) })
        // The feed's own wording, reproduced rather than rewritten: a second sentence
        // for one finding is the drift the engine is built to prevent, and the reader
        // may already have met this one on Patterns.
        #expect(sheet.found.lines == [insight.statement])
        #expect(sheet.limit.lines == [insight.caveat])
    }

    @Test("A question that found nothing says so, in phase 2's own words")
    func carriesTheNonAnswer() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let quiet = try #require(answerable(in: store, claimed: false),
                                 "most answerable questions should publish nothing")
        withhold(quiet, in: store)
        store.announceOpenedQuestion()

        let sheet = try #require(store.openedQuestion?.sheet)
        // Not a second phrasing for the same fact. "Measured, and the two sides came
        // out alike" is what an open question says on Patterns when nothing
        // separated, and it is what it says here.
        #expect(sheet.found.lines == [QuestionCopy.noSeparation])
    }

    /// The §2 invariant, as structure rather than as a reading of the words.
    @Test("The sheet is the same sheet whether it found something or nothing")
    func sameWeightEitherWay() throws {
        let found = store(SyntheticCohort.morningDeepWork)
        let claimed = try #require(answerable(in: found, claimed: true))
        withhold(claimed, in: found)
        found.announceOpenedQuestion()

        let empty = store(SyntheticCohort.afternoonSlump)
        let quiet = try #require(answerable(in: empty, claimed: false))
        withhold(quiet, in: empty)
        empty.announceOpenedQuestion()

        let withFinding = try #require(found.openedQuestion?.sheet)
        let withNothing = try #require(empty.openedQuestion?.sheet)

        // Same header, same sections, same headings, same single control. A reveal
        // that was bigger when it had a finding would teach somebody that the ones
        // without are failures.
        #expect(withFinding.standing == withNothing.standing)
        #expect(withFinding.closeTitle == withNothing.closeTitle)
        #expect(withFinding.orderedSections.map(\.heading)
                    == withNothing.orderedSections.map(\.heading))
        #expect(withFinding.found.parts.count == withNothing.found.parts.count)
        #expect(withFinding.orderedSections.count == 4)
    }

    @Test("No sentence on the sheet counts anything")
    func nothingIsScored() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        for id in store.answerableHypotheses {
            let question = try #require(
                HypothesisRegistry.hypotheses(for: store.engineObservations)
                    .first { $0.id == id })
            let sheet = AnnouncementCopy.sheet(for: question, claim: nil)

            // No score, no streak, no "x of 60" — `PRD-LOCKS.md` §6. The only figures
            // allowed anywhere here are the gate itself, in days — what the question
            // was waiting for, rather than progress through a list — and whatever
            // numbers the registry's own labels carry, since a duration bucket is
            // named "90–179 min" and the sentence has to be able to say it.
            let permitted = Set([String(question.minimumDays)])
                .union(NarrationGuard.figures(in: question.focusLabel))
                .union(NarrationGuard.figures(in: question.baselineLabel))
            for text in sheet.authoredStrings {
                #expect(NarrationGuard.figures(in: text).subtracting(permitted).isEmpty,
                        "a figure that is neither the gate nor a label reached the sheet: \(text)")
            }
            #expect(!sheet.spoken.lowercased().contains(" of 60"))
            #expect(!sheet.spoken.lowercased().contains("streak"))
        }
    }

    // MARK: - The words

    @Test("Every authored sentence passes the narration guard")
    func copyPassesTheNarrationGuard() throws {
        for person in [SyntheticCohort.afternoonSlump, SyntheticCohort.morningDeepWork] {
            // Health on, so the sweep sees the `health.*` family's sentences too —
            // the ones built around a metric's own label, which is where a wording
            // mistake is most likely to go unnoticed.
            let store = store(person, health: true)
            let registry = HypothesisRegistry.hypotheses(for: store.engineObservations)
            for id in store.answerableHypotheses {
                guard let question = registry.first(where: { $0.id == id }) else { continue }
                let claim = store.insights.first { $0.id == Engine.identity(of: id) }
                let sheet = AnnouncementCopy.sheet(for: question, claim: claim)

                for text in sheet.authoredStrings {
                    let offence = NarrationGuard.offence(
                        in: text, allowingFigures: NarrationGuard.figures(in: text))
                    #expect(offence == nil, "\(String(describing: offence)) in: \(text)")
                }
            }
        }
    }

    /// The grammar, family by family, because one template does not fit them — the
    /// lesson `QuestionCopy.noun` learned twice and recorded both times.
    @Test("What was compared reads as a sentence, in every family")
    func comparisonGrammar() throws {
        let store = store(SyntheticCohort.morningDeepWorkAfterSleep)
        let registry = HypothesisRegistry.hypotheses(for: store.engineObservations)
        #expect(!registry.isEmpty)

        var familiesSeen: Set<String> = []
        for question in registry {
            let line = AnnouncementCopy.comparison(for: question)
            familiesSeen.insert(String(question.id.split(separator: ".").first ?? ""))

            #expect(line.hasSuffix("."), "no full stop: \(line)")
            #expect(line.contains("against"), "nothing is being compared: \(line)")
            #expect(!line.contains("  "), "a doubled space: \(line)")
            #expect(!line.lowercased().contains("your your"), "a doubled word: \(line)")
            #expect(!line.lowercased().contains("a sessions"), "a plural behind an article: \(line)")
            #expect(line.first?.isUppercase == true, "does not open a sentence: \(line)")
        }

        // The cohort has to actually exercise the families, or the loop above is a
        // loop over nothing — which is how the "No a session in your evening yet"
        // sentence survived its own test once already.
        #expect(familiesSeen.isSuperset(of: ["time", "duration", "activity", "workday"]))
    }

    @Test("A time question names the day rather than the session's length")
    func timeFamilyWording() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let morning = try #require(
            HypothesisRegistry.hypotheses(for: store.engineObservations)
                .first { $0.id.hasPrefix("time.morning") })

        #expect(AnnouncementCopy.comparison(for: morning)
                    == "Your morning sessions, against the rest of your day.")
    }

    @Test("A duration question is a length, never a place in the day")
    func durationFamilyWording() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let duration = try #require(
            HypothesisRegistry.hypotheses(for: store.engineObservations)
                .first { $0.id.hasPrefix("duration.") })

        let line = AnnouncementCopy.comparison(for: duration)
        // "Your 180 min or more sessions" is the sentence this phrasing exists to
        // avoid: a duration is a property of a session, not somewhere it happened.
        #expect(line.hasPrefix("Your sessions of "))
        #expect(line.hasSuffix("against your other lengths."))
    }

    /// Both of these were found by reading the sentences the cohorts actually
    /// produce, and neither would have failed a test written from the template.
    @Test("An activity is named the way the registry names it, not pluralised twice")
    func activityFamilyWording() throws {
        let store = store(SyntheticCohort.afternoonSlump)
        let meetings = try #require(
            HypothesisRegistry.hypotheses(for: store.engineObservations)
                .first { $0.id == "activity.meetings.vs.rest.feeling" })

        // "Your Meetings sessions" is what the possessive template produced, and
        // several of the default activities are plural already. "Your time in
        // Meetings" is the registry's own construction for this family.
        #expect(AnnouncementCopy.comparison(for: meetings)
                    == "Your time in Meetings, against everything else you log.")
    }

    @Test("A label's acronym survives being dropped into a sentence")
    func acronymsSurvive() throws {
        // Health on, because this family only exists once the daily context does.
        let store = store(SyntheticCohort.morningDeepWorkAfterSleep, health: true)
        let hrv = try #require(
            HypothesisRegistry.hypotheses(for: store.engineObservations)
                .first { $0.id.hasPrefix("health.hrv") })

        // `lowercased()` over the whole label gave "Days with higher hrv", which is
        // the kind of sentence that tells a reader the app is not paying attention.
        #expect(AnnouncementCopy.comparison(for: hrv)
                    == "Days with higher HRV, against days with lower HRV.")
        #expect(AnnouncementCopy.inSentence("Higher resting HR") == "higher resting HR")
    }

    @Test("Why now names the gate in days and promises nothing")
    func whyNowIsTheGate() {
        let line = AnnouncementCopy.whyNow(gate: 6)
        #expect(line.contains("6 days of each kind"))
        // Not "and here is what we found", not "keep going". It states what was
        // missing and that it is no longer missing.
        #expect(NarrationGuard.offence(in: line, allowingFigures: ["6"]) == nil)
    }

    // MARK: - What is written down

    @Test("The record holds question keys, sorted, and no sentences")
    func onlyKeysAreStored() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = store(SyntheticCohort.morningDeepWork, at: url)
        let claimed = try #require(answerable(in: store, claimed: true))
        withhold(claimed, in: store)
        store.announceOpenedQuestion()
        let announcement = try #require(store.openedQuestion)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("announcedHypotheses"))
        #expect(raw.contains(claimed))

        // The answer is derived from the record on every run, like every other claim
        // in this app, so no sentence the sheet showed is in the file — the same
        // assertion `PersistenceTests` makes about an insight's statement, for the
        // same reason. The question's own label is not checked, because that is a
        // carried word and for an activity it is the person's own name for their own
        // activity, which is in the record by right.
        let sentences = announcement.sheet.found.lines
            + announcement.sheet.limit.lines
            + announcement.sheet.question.parts.dropFirst().flatMap(\.strings)
            + [announcement.sheet.whyNow.lines].flatMap { $0 }
        for line in sentences {
            #expect(!raw.contains(line), "a sentence from the sheet was written to disk: \(line)")
        }

        // Sorted, because the record is encoded with `.sortedKeys` so that the same
        // state produces the same bytes, and a set's iteration order would defeat
        // that on every save.
        let reread = try FileRecordRepository(url: url).load()
        let keys = try #require(reread.announcedHypotheses)
        #expect(keys == keys.sorted())
    }

    @Test("A record written before schema 5 still decodes")
    func olderRecordsDecode() throws {
        var record = Record()
        record.announcedHypotheses = ["time.morning.vs.rest.feeling"]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(record)
        let parsed = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(parsed as? [String: Any])
        object.removeValue(forKey: "announcedHypotheses")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let read = try decoder.decode(Record.self, from: stripped)

        // A synthesized `Codable` fails on a missing key for a non-optional property
        // however sensible its default looks, and every record written before this
        // field existed is missing it.
        #expect(read.announcedHypotheses == nil)
    }

    // MARK: - Reachable in the simulator

    /// **A card nobody can get to is a card nobody reviews**, and that has cost this
    /// project twice. The two fixture arguments withhold one answerable question each
    /// — one the engine published a claim for, one it did not — so this asserts that
    /// the fixture actually *has* both kinds to withhold. An argument that silently
    /// does nothing is the failure mode, and it would not show up anywhere else: the
    /// app would simply launch with no sheet, which is also what a working day looks
    /// like.
    @Test("Both halves of the announcement are reachable on the fixture")
    func fixtureReachesBothHalves() throws {
        let store = HourssStore(repository: InMemoryRecordRepository())
        DebugFixture.seed(into: store)
        store.hasCompletedOnboarding = true

        let quiet = try #require(answerable(in: store, claimed: false),
                                 "the fixture has no question that found nothing to announce")
        #expect(answerable(in: store, claimed: true) != nil,
                "the fixture has no question with a claim to announce")

        // And the path the fixture takes produces a real sheet, from real detection
        // over a real record, rather than an announcement assembled by hand.
        withhold(quiet, in: store)
        store.announceOpenedQuestion()
        let announcement = try #require(store.openedQuestion)
        #expect(announcement.hypothesisId == quiet)
        #expect(announcement.sheet.found.lines == [QuestionCopy.noSeparation])
    }

    @Test("Erasing the record erases what has been announced")
    func deletionResets() {
        let store = store(SyntheticCohort.afternoonSlump)
        store.announceOpenedQuestion()
        #expect(store.announcedHypotheses != nil)

        store.deleteEverything()

        // Back to nil rather than to empty: an erased record is a first run, and the
        // run after it takes its baseline in silence like any other first run.
        #expect(store.announcedHypotheses == nil)
        #expect(store.openedQuestion == nil)
    }
}
