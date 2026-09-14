import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// How a multi-factor finding is turned into a sentence.
///
/// Single factors do not need this. `HypothesisRegistry` writes "Your morning
/// sessions have felt more energizing than the rest of your day lately" from a
/// template with one hole in it, and that reads well because there is only one
/// thing to say and one place to say it.
///
/// A conjunction is a different shape of problem. "Deep work, in the morning,
/// after a good night's sleep" draws three factors from three families in an
/// order nothing in the data fixes, and each family wants a different grammatical
/// slot — an activity is a noun, an hour is a prepositional phrase, a health
/// split is a fronted adverbial. Templating the product of those either explodes
/// combinatorially or collapses into "Deep work + morning + sleep", which is a
/// database row read aloud. So the model is asked, and it is asked about this
/// and nothing else.
///
/// Three properties are load-bearing and the file is arranged around them.
///
/// **The model never touches a number.** `NarrationTemplate.Parts` hands it
/// phrases; every count, every day and every window comes out of the evidence
/// record and is concatenated on afterwards. A small model given a figure to
/// carry will carry the wrong one confidently, and a wrong figure in a sentence
/// about somebody's own record is worse than no sentence.
///
/// **The template is the product, not the error path.** Apple Intelligence needs
/// an iPhone 15 Pro or newer, so most people will never see a generated word.
/// `NarrationTemplate.sentence` is written to be shipped on its own, every
/// `UnavailableReason` lands on it in silence, and narration is polish laid over
/// something already finished.
///
/// **Nothing waits for it.** `NarrationStore.sentence` answers from the template
/// synchronously and the refinement, if it ever arrives, replaces the string in
/// place.
///
/// The BRD constraints in §1 are not style. The Health screen promises "Read
/// only. Nothing is ever written back, and nothing leaves your phone", which is
/// why this is on-device at all; no causation, no medical or psychological
/// claim, no population comparison and no instruction are why `NarrationGuard`
/// exists and why it runs at runtime rather than only in tests.

// MARK: - Evidence

/// One multi-factor finding, flattened into everything a sentence needs and
/// nothing it could get wrong.
///
/// Extracted on whatever thread holds the findings and `Sendable` thereafter,
/// because `InteractionFinding` is not — `Factor` carries a closure over the
/// record and must not cross into a generation task.
struct NarrationEvidence: Sendable, Equatable {

    /// One factor, with its display label already resolved.
    ///
    /// The label is resolved here rather than in the template because an
    /// activity's `Factor.value` is a slug — `HypothesisRegistry.slug` is lossy
    /// on purpose, so "deep-work" cannot be turned back into "Deep work" without
    /// the record that produced it.
    struct Term: Sendable, Equatable {
        let family: Factor.Family
        let value: String
        /// The person's own name for an activity; the raw value otherwise.
        let label: String
    }

    let findingId: String
    /// Sorted by factor key, which is the order `InteractionCandidates.partition`
    /// conditions on. The first term is therefore the one the interaction was
    /// measured *about*, and the contrast sentence names it.
    let terms: [Term]
    let outcome: Outcome
    /// Direction of the conjunction against everything outside it.
    let isHigher: Bool
    /// Sessions in the conjunction itself — the group the claim is about.
    let sessionCount: Int
    /// Distinct days those sessions fall on. Sessions are not the unit of
    /// evidence anywhere else in the engine and they are not the unit here.
    let dayCount: Int
    let windowDays: Int

    var isMultiFactor: Bool { terms.count >= 2 }
}

extension NarrationEvidence {

    /// Refuses a single-factor finding by returning nil.
    ///
    /// This is where "narrate conjunctions only" is enforced, rather than in the
    /// store or the model call, so that no path into generation can be opened
    /// later that skips the check. A one-factor conjunction is a well-formed
    /// value — `Conjunction` does not forbid it — and it is precisely the thing
    /// the registry already phrases better than any model would.
    init?(finding: InteractionFinding, observations: [EngineObservation]) {
        let factors = finding.conjunction.factors.sorted { $0.key < $1.key }
        guard factors.count >= 2 else { return nil }

        let terms = factors.map { factor in
            Term(family: factor.family,
                 value: factor.value,
                 // An activity factor matches a row if and only if the row carries
                 // that name, so the first match is the name.
                 label: factor.family == .activity
                     ? (observations.first(where: factor.matches)?.activityName ?? factor.value)
                     : factor.value)
        }

        let focus = Set(finding.focusSessionIds)
        let days = Set(observations.filter { focus.contains($0.sessionId) }.map(\.day))

        self.init(
            findingId: finding.conjunction.id,
            terms: terms,
            outcome: finding.conjunction.outcome,
            // `combined` rather than `lift`. The contract reserves the combined
            // comparison for the evidence line and the lift for the gate, and the
            // sign the reader needs is "against everything else", which is what
            // combined measures. The lift is one-sided by construction — it is
            // never negative in a reportable finding — so reading direction off it
            // would report "more energizing" about a conjunction that ran down.
            isHigher: finding.interaction.combined.delta > 0,
            sessionCount: finding.focusSessionIds.count,
            dayCount: days.count,
            windowDays: finding.windowDays
        )
    }
}

// MARK: - The template

/// The sentence most people will read, assembled from tables.
///
/// Written first and written to be good on its own. Everything the model is later
/// allowed to do is a rearrangement of the phrases this produces.
enum NarrationTemplate {

    /// The pieces, before they are a sentence.
    ///
    /// Separated out because the model is handed exactly these and nothing else.
    /// A piece that is not here is a piece the model cannot mention, which is how
    /// "do not extrapolate unobserved factors" is enforced by construction rather
    /// than by asking nicely.
    struct Parts: Sendable, Equatable {
        /// Fronted adverbial from the health factors: "On days after a longer
        /// night". Empty when the conjunction has no health term.
        let lead: String
        /// "your Deep work sessions in the morning" — always lower case, because
        /// whether it opens the sentence depends on whether `lead` does.
        let subject: String
        /// "have felt" or "have run".
        let verb: String
        /// "more energizing", "more draining", "stronger", "weaker".
        let direction: String
        /// The conditioning factor named on its own: "deep work".
        let leadingCondition: String
        /// The whole of §8.4's sample limit, figures included. Ours, never the
        /// model's.
        let limit: String

        /// Every phrase the model is shown. Also the whitelist of figures it is
        /// allowed to echo back — "90 to 179 minutes" carries digits that belong
        /// to the record.
        var supplied: [String] { [lead, subject, direction, leadingCondition] }
    }

    static func parts(for evidence: NarrationEvidence) -> Parts {
        let health = evidence.terms.filter { $0.family == .health }
        let lead = health.isEmpty
            ? ""
            : "On days " + health.map(healthPhrase).joined(separator: " and ")

        // The activity, where there is one, is the noun; everything else hangs off
        // it. Where there is not, "your sessions" carries the qualifiers instead —
        // uniform, and grammatical for every combination the factor families can
        // produce.
        let activity = evidence.terms.first { $0.family == .activity }
        let noun = activity.map { "your \($0.label) sessions" } ?? "your sessions"

        // Length before hour before workday, which is the order that reads: "your
        // sessions of 90 to 179 minutes in the morning on workdays". Any other
        // order puts a prepositional phrase between a noun and the phrase that
        // modifies it.
        let qualifiers = [Factor.Family.duration, .time, .workday]
            .compactMap { family in evidence.terms.first { $0.family == family } }
            .map(qualifierPhrase)

        return Parts(
            lead: lead,
            subject: ([noun] + qualifiers).joined(separator: " "),
            verb: evidence.outcome == .heartRateResidual ? "have run" : "have felt",
            direction: direction(evidence),
            leadingCondition: standalonePhrase(evidence.terms[0]),
            limit: limit(evidence)
        )
    }

    /// The whole narration, without a model.
    ///
    /// Three sentences, and each does one job. The claim says what the
    /// combination has looked like against the rest of the record. The contrast
    /// says the conditional thing the lift gate actually tested — that the
    /// leading factor does not read this way outside the combination — because
    /// without it a conjunction is indistinguishable from its strongest part, and
    /// that confusion is the whole failure mode layer 2.5 exists to avoid. The
    /// limit carries the sample, per §8.4, attached to the sentence rather than
    /// behind a tap.
    static func sentence(for evidence: NarrationEvidence) -> String {
        compose(parts(for: evidence))
    }

    static func compose(_ parts: Parts) -> String {
        let opening = parts.lead.isEmpty
            ? capitalisingFirst(parts.subject)
            : parts.lead + ", " + parts.subject
        let claim = "\(opening) \(parts.verb) \(parts.direction) than the rest of your sessions."
        let contrast = "The same is not true of \(parts.leadingCondition) elsewhere in your record."
        return claim + " " + contrast + " " + parts.limit
    }

    // MARK: Copy

    /// Mirrors `HypothesisRegistry.direction`, which is private to that file.
    ///
    /// Duplicated rather than shared because the two read their direction from
    /// different quantities — a single factor from its own δ, a conjunction from
    /// the combined comparison — and a shared helper would hide that the inputs
    /// are not the same kind of number. The words must match, and the test that
    /// they do is cheaper than the coupling.
    ///
    /// No size word, for the reason the registry gives: "clearly" and "slightly"
    /// would be a second opinion about the interval the confidence band already
    /// reports.
    private static func direction(_ evidence: NarrationEvidence) -> String {
        switch evidence.outcome {
        case .feeling: evidence.isHigher ? "more energizing" : "more draining"
        case .performance: evidence.isHigher ? "stronger" : "weaker"
        // Undirected on purpose. A heart rate above what movement explains is not
        // "worse", and saying so would be a medical claim.
        case .heartRateResidual: evidence.isHigher ? "higher" : "lower"
        }
    }

    /// §8.4's sample limit: how many sessions, over how many distinct days, in a
    /// window described no more generously than the evidence supports.
    private static func limit(_ evidence: NarrationEvidence) -> String {
        let sessions = evidence.sessionCount == 1 ? "1 session" : "\(evidence.sessionCount) sessions"
        let days = evidence.dayCount == 1 ? "1 distinct day" : "\(evidence.dayCount) distinct days"
        return "Observed across \(sessions) over \(days), \(Engine.describe(windowDays: evidence.windowDays))."
    }

    /// A factor as a phrase that attaches to "your sessions".
    private static func qualifierPhrase(_ term: NarrationEvidence.Term) -> String {
        switch term.family {
        case .time:
            switch TimeBucket(rawValue: term.value) {
            case .morning: "in the morning"
            case .midday: "at midday"
            case .afternoon: "in the afternoon"
            case .evening: "in the evening"
            case nil: "in the \(term.value)"
            }
        case .duration:
            "of " + lengthPhrase(term)
        case .workday:
            term.value == "non" ? "on your days off" : "on workdays"
        // Neither reaches here: the activity is the noun and health is fronted.
        case .activity, .health:
            ""
        }
    }

    /// `DurationBucket.label` is written for a chip — "90–179 min" — and an en
    /// dash inside a sentence reads as a subtraction. Prose forms, here, because
    /// `Enums.swift` belongs to the model layer and its labels are used on screen.
    private static func lengthPhrase(_ term: NarrationEvidence.Term) -> String {
        switch DurationBucket(rawValue: term.value) {
        case .short: "under 30 minutes"
        case .medium: "30 to 89 minutes"
        case .long: "90 to 179 minutes"
        case .extended: "three hours or more"
        case nil: term.value
        }
    }

    /// The fragment that follows "On days ".
    ///
    /// The high side is `HealthMetric.higherPhrase` verbatim, so a conjunction and
    /// the single-factor claim underneath it cannot describe the same split in two
    /// different ways. The low side is *not* `lowerPhrase`: that property is
    /// elliptical by design — "when it ran lower" — because the registry only ever
    /// uses it in a sentence where the metric has already been named. Standing
    /// alone at the front of a sentence it has no antecedent, so narration needs
    /// its own full forms.
    private static func healthPhrase(_ term: NarrationEvidence.Term) -> String {
        guard let metric = metric(in: term) else { return term.value }
        guard !isHighSide(term) else { return metric.higherPhrase }
        switch metric {
        case .sleepHours: return "after a shorter night"
        case .hrv: return "when your heart rate variability ran lower"
        case .restingHeartRate: return "when your resting heart rate ran lower"
        case .respiratoryRate: return "when your breathing ran slower"
        case .heartRate: return "when your heart rate ran lower"
        case .workoutMinutes: return "after a shorter workout"
        case .steps: return "when you walked less"
        case .activeEnergy: return "when you moved less"
        case .exerciseMinutes: return "after less exercise"
        case .mindfulMinutes: return "after less quiet time"
        case .daylightMinutes: return "after less time outside"
        }
    }

    /// A factor named on its own, for the contrast sentence. Always fits the frame
    /// "The same is not true of ___ elsewhere in your record", which takes the
    /// agreement off the noun and puts it on "is" — otherwise every family would
    /// need its own verb.
    private static func standalonePhrase(_ term: NarrationEvidence.Term) -> String {
        switch term.family {
        case .activity: term.label.lowercased()
        case .time: "your \(term.value) sessions"
        case .duration: "your sessions of " + lengthPhrase(term)
        case .workday: term.value == "non" ? "your days off" : "your workdays"
        case .health: "days " + healthPhrase(term)
        }
    }

    /// A health factor's value is `metric.high` or `metric.low`, and a metric's
    /// own raw value may itself contain dots.
    private static func metric(in term: NarrationEvidence.Term) -> HealthMetric? {
        HealthMetric(rawValue: term.value.split(separator: ".").dropLast().joined(separator: "."))
    }

    private static func isHighSide(_ term: NarrationEvidence.Term) -> Bool {
        term.value.split(separator: ".").last == "high"
    }

    private static func capitalisingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - The guard

/// A sweep for the vocabulary the BRD forbids, run on every generated string
/// before anybody sees it.
///
/// In the app, not only in the tests. A test tells us the rule held on the
/// examples we thought of; this is what holds it on a sentence written on
/// somebody's phone at two in the morning about a combination of factors nobody
/// on the team has seen. A trip discards the generation and the template is used
/// instead — silently, with no apology and no diagnostic, because a person should
/// never learn that their phone tried to say something and was stopped.
///
/// Matching is on whole words after punctuation is flattened, which is the
/// difference between rejecting "try" and rejecting "Carpentry". Phrases match
/// the same way, so "burn-out" and "burn out" are one entry.
enum NarrationGuard {

    /// Which rule a string broke. Named so a test can assert the category rather
    /// than the word, and so the categories stay traceable to §1 of ENGINE.md.
    enum Offence: Equatable, Sendable {
        /// "No causal claims. Associations only."
        case causal(String)
        /// "No medical or psychological claims."
        case clinical(String)
        /// "No population comparison."
        case population(String)
        /// "No instruction." Recommendations are a separate tier with its own
        /// voice; narration describes and stops.
        case instruction(String)
        /// A figure the evidence record does not contain. The model is told to
        /// write none; this is what happens when it does anyway.
        case invention(String)
    }

    /// Causation, in the forms a small model reaches for.
    static let causal = [
        "because", "cause", "causes", "caused", "causing", "causal",
        "leads to", "lead to", "led to", "makes you", "make you", "made you",
        "makes your", "make your", "due to", "owing to", "thanks to",
        "results in", "result in", "resulting in", "responsible for",
        "the reason", "explains why", "which is why", "so that", "drives",
        "driving", "triggers", "trigger", "boosts", "boost", "improves",
        "improve", "helps", "help", "hurts", "harms", "effect of", "impact of",
        "influences", "influence"
    ]

    /// Bodies and minds as states or diagnoses. "Intensity" and "energy levels"
    /// are on this list by name in §1; the rest are the neighbourhood they live
    /// in.
    static let clinical = [
        "stress", "stressed", "stressful", "anxiety", "anxious", "depression",
        "depressed", "mood", "moods", "energy levels", "energy level",
        "intensity", "intense", "burnout", "burn out", "burnt out", "fatigue",
        "fatigued", "exhaustion", "exhausted", "mental health", "wellness",
        "diagnosis", "diagnose", "symptom", "symptoms", "disorder", "insomnia",
        "cortisol", "adrenaline", "sleep deprived", "sleep deprivation",
        "overtrained", "overtraining", "healthy", "unhealthy"
    ]

    /// Anybody other than the person reading. A record is compared only with
    /// itself.
    static let population = [
        "average", "averages", "most people", "other people", "others",
        "everyone", "anyone else", "normal", "typical", "typically",
        "population", "peers", "compared with people", "than most",
        "benchmark", "the norm", "norms", "studies", "research",
        "people who", "for people"
    ]

    /// Advice. The paid tier says what held up; the free tier proposes a test;
    /// narration does neither.
    static let instruction = [
        "you should", "should", "try", "trying", "make sure", "consider",
        "aim to", "aim for", "avoid", "prioritise", "prioritize", "schedule",
        "rescheduling", "reschedule", "recommend", "recommended", "advice",
        "advise", "suggest", "suggests", "suggestion", "keep doing",
        "start doing", "stick to", "lean into", "plan to", "be sure", "ensure",
        "worth doing", "could try", "why not", "let us", "remember to"
    ]

    /// Whether a generated string may be shown.
    ///
    /// - Parameter allowingFigures: digit runs that came out of the evidence
    ///   record — "30 to 89 minutes" is the app's own phrase and the model is
    ///   allowed to repeat it. Anything else numeric is an invention, and
    ///   inventing a count in a sentence about somebody's own history is the
    ///   single worst thing this layer could do.
    static func accepts(_ text: String, allowingFigures: Set<String> = []) -> Bool {
        offence(in: text, allowingFigures: allowingFigures) == nil
    }

    static func offence(in text: String, allowingFigures: Set<String> = []) -> Offence? {
        let padded = " " + flatten(text) + " "

        // Cheapest and most consequential first.
        for run in figures(in: text) where !allowingFigures.contains(run) {
            return .invention(run)
        }
        if let word = causal.first(where: { padded.contains(" \($0) ") }) { return .causal(word) }
        if let word = clinical.first(where: { padded.contains(" \($0) ") }) { return .clinical(word) }
        if let word = population.first(where: { padded.contains(" \($0) ") }) { return .population(word) }
        if let word = instruction.first(where: { padded.contains(" \($0) ") }) { return .instruction(word) }
        return nil
    }

    /// Every run of digits in a string, as it appears.
    static func figures(in text: String) -> Set<String> {
        var out: Set<String> = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                out.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { out.insert(current) }
        return out
    }

    /// Lower case, every non-alphanumeric run reduced to one space.
    ///
    /// Which is what makes the match a word match: "Carpentry" flattens to
    /// "carpentry" and never contains " try ", where a naive substring search
    /// would refuse somebody's own activity name. Hyphens and apostrophes become
    /// spaces so "burn-out" and "burn out" are the same entry.
    private static func flatten(_ text: String) -> String {
        var out = ""
        var pendingSpace = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(character)
            } else {
                pendingSpace = true
            }
        }
        return out
    }
}

// MARK: - Availability

enum Narration {

    /// Whether there is a model to ask.
    ///
    /// Mirrored into our own type rather than passed around as
    /// `SystemLanguageModel.Availability` so this layer can be exercised for every
    /// reason in a test. The simulator reports exactly one of them and a device
    /// reports whichever it happens to be in; neither lets us check that all four
    /// land on the template.
    enum Availability: Sendable, Equatable {
        case ready
        case unavailable(Reason)

        /// Every reason is the same decision: use the template, say nothing.
        /// None of them is an error, and none of them is reported to anybody —
        /// most phones in the world are `.deviceNotEligible` and that is a fact
        /// about hardware, not a fault.
        enum Reason: Sendable, Equatable, CaseIterable {
            case deviceNotEligible
            case appleIntelligenceNotEnabled
            case modelNotReady
            /// A reason this build does not know about. `UnavailableReason` is not
            /// frozen, so a future case has to land somewhere, and it lands here
            /// on the template with everything else.
            case unrecognised
        }

        var isReady: Bool { self == .ready }

        static var current: Availability {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable(.deviceNotEligible)
                case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
                case .modelNotReady: return .unavailable(.modelNotReady)
                @unknown default: return .unavailable(.unrecognised)
                }
            }
            #else
            return .unavailable(.deviceNotEligible)
            #endif
        }
    }

    /// What the feed shows now, and whether anything may be asked of the model.
    struct Plan: Sendable, Equatable {
        /// Always the template, always complete, always immediately. The feed
        /// renders this; nothing waits.
        let sentence: String
        /// Whether a refinement is worth starting.
        let mayRefine: Bool
    }

    /// - Returns: nil for a single-factor finding, which this layer has nothing to
    ///   say about. `HypothesisRegistry` phrases those and phrases them well.
    static func plan(
        for finding: InteractionFinding,
        observations: [EngineObservation],
        availability: Availability = .current
    ) -> Plan? {
        guard let evidence = NarrationEvidence(finding: finding, observations: observations) else { return nil }
        return plan(for: evidence, availability: availability)
    }

    static func plan(for evidence: NarrationEvidence, availability: Availability = .current) -> Plan {
        Plan(sentence: NarrationTemplate.sentence(for: evidence),
             mayRefine: evidence.isMultiFactor && availability.isReady)
    }
}

// MARK: - The model

#if canImport(FoundationModels)

/// What the model is allowed to return.
///
/// Two phrases, and not a sentence with a figure in it. Guided generation
/// constrains the *shape*; the shape is chosen so that even a perfectly obedient
/// model has nowhere to put a number, and `NarrationGuard` catches the
/// disobedient one.
@Generable
struct NarratedFinding {
    @Guide(description: "One sentence: the combination of conditions, and how those sessions have felt set against the rest of the person's own record. Reuse the supplied phrases. No figures, no counts, no dates.")
    var claim: String

    @Guide(description: "One short sentence saying that the leading condition on its own, elsewhere in the record, has not read the same way. No figures.")
    var contrast: String
}

extension Narration {

    /// The rules, as the model receives them.
    ///
    /// Written as prohibitions with examples rather than as a tone brief, because
    /// the failures that matter here are specific words and a small model
    /// responds to a named word far better than to "be careful about causation".
    /// Every line maps to a row of ENGINE.md §1, and `NarrationGuard` enforces
    /// the same list afterwards — the instructions are where the good outcome
    /// comes from and the guard is where the guarantee comes from.
    static let instructions = """
        You write one or two short sentences describing a pattern in one person's \
        own record of their own sessions. You are given every piece of that pattern \
        already in words. Your whole job is to put those pieces into plain, calm \
        British English.

        Never say or imply that one thing caused another. These are associations \
        and nothing more. Do not write "because", "causes", "leads to", "makes", \
        "due to", "helps", "improves", "boosts", or "why".

        Never describe anybody's body or mind as being in a state. No stress, no \
        mood, no energy levels, no intensity, no fatigue, no health of any kind. \
        You are describing sessions, not a person.

        Never mention other people, averages, what is typical, or what is normal. \
        This person is set against their own record and nothing else.

        Never tell them to do anything. No "should", "try", "consider", "make \
        sure", "avoid". Advice is somebody else's job. You describe what the record \
        shows and then stop.

        Never write a figure of any kind — no counts, no percentages, no dates, no \
        durations you were not handed. Figures are added after you and any you \
        write will be wrong.

        Add no fact that is not among the pieces you were given. Use the person's \
        own name for their activity exactly as it is supplied to you.
        """

    /// The refinement, or nil.
    ///
    /// Nil for every reason there is: no model, the wrong kind of finding, a
    /// throw, or a generation that failed the guard. The caller keeps the
    /// template and nobody is told.
    static func refine(
        _ evidence: NarrationEvidence,
        availability: Availability = .current
    ) async -> String? {
        guard evidence.isMultiFactor, availability.isReady else { return nil }

        let parts = NarrationTemplate.parts(for: evidence)
        // Figures the model is permitted to echo: whatever the app's own phrases
        // already contain, such as the "30" and "89" in a length. Everything
        // numeric outside this set is an invention.
        let permitted = parts.supplied.reduce(into: Set<String>()) {
            $0.formUnion(NarrationGuard.figures(in: $1))
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let generated = try await session.respond(to: prompt(parts), generating: NarratedFinding.self).content
            let body = generated.claim.trimmingCharacters(in: .whitespacesAndNewlines)
                + " " + generated.contrast.trimmingCharacters(in: .whitespacesAndNewlines)

            guard NarrationGuard.accepts(body, allowingFigures: permitted) else { return nil }
            // The limit is concatenated rather than requested. It is the one
            // sentence in the narration that carries the sample, §8.4 requires it
            // on every sentence, and it is the last place a model may be involved.
            return body + " " + parts.limit
        } catch {
            return nil
        }
    }

    static func prompt(_ parts: NarrationTemplate.Parts) -> String {
        """
        The pieces of this pattern, in the person's own terms:

        Which sessions: \(parts.subject)
        On which days: \(parts.lead.isEmpty ? "every day in the record" : parts.lead)
        How those sessions have compared with the rest of their record: \
        \(parts.verb) \(parts.direction)
        The leading condition, named on its own: \(parts.leadingCondition)

        Write the claim and the contrast. Use only these pieces.
        """
    }
}

#else

extension Narration {
    static let instructions = ""
    /// Narration is unreachable without the framework, and the template is
    /// already the whole product.
    static func refine(_ evidence: NarrationEvidence, availability: Availability = .current) async -> String? { nil }
}

#endif

// MARK: - The store

/// Holds whatever narration has arrived, and answers from the template until it
/// does.
///
/// The asymmetry is the point. `sentence(for:)` is synchronous and total — it
/// always has an answer, on the first frame, on every device. `refine(_:)` is
/// fire-and-forget and may never complete. A feed reads the first and calls the
/// second, and on the large majority of phones the second does nothing at all.
@MainActor
@Observable
final class NarrationStore {

    /// Narration by finding id. Written once per finding, never cleared: the
    /// generated sentence is about an evidence record that does not change, and
    /// a sentence that flickered back to the template on a redraw would look like
    /// the app changing its mind about somebody's history.
    private(set) var refined: [String: String] = [:]

    private var inFlight: Set<String> = []
    private let availability: Narration.Availability

    init(availability: Narration.Availability = .current) {
        self.availability = availability
    }

    /// What to render, now.
    func sentence(for evidence: NarrationEvidence) -> String {
        refined[evidence.findingId] ?? NarrationTemplate.sentence(for: evidence)
    }

    /// Ask for a better sentence, if there is a model and one has not been asked
    /// for already. Returns immediately either way.
    func refine(_ evidence: NarrationEvidence) {
        guard evidence.isMultiFactor,
              availability.isReady,
              refined[evidence.findingId] == nil,
              inFlight.insert(evidence.findingId).inserted
        else { return }

        let availability = self.availability
        Task {
            let text = await Narration.refine(evidence, availability: availability)
            self.inFlight.remove(evidence.findingId)
            guard let text else { return }
            self.refined[evidence.findingId] = text
        }
    }
}
