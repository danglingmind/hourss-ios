import Foundation

/// A question the engine could not ask, now asked, said once.
///
/// **You unlock a question, not an answer.** `PRD-LOCKS.md` §2 makes this the thing
/// the whole feature turns on, and everything in this file is downstream of it. A
/// question clears its gate when six distinct days exist on each side of it; what
/// happens next is that the comparison *runs*, and the overwhelmingly common
/// result is that the two sides came out alike. So the sheet this builds is the
/// same sheet either way — same sections, same weight, same single control —
/// carrying whichever answer there was, including none. A reveal that was bigger
/// when it had a finding would make the app a slot machine that mostly pays
/// nothing, and the first empty one would teach somebody that the whole thing is a
/// tease.
///
/// **It carries the answer rather than promising it.** There is no "see what we
/// found" and nothing to tap through to. Deferring the answer to a second tap is
/// the slot machine in its purest form, and it is forbidden by name.
///
/// The value is built once, when the announcement is raised, and holds every
/// sentence the sheet will show — so one sweep sees all of them and none is
/// authored in a view body. `ExperimentCopy.ProposalSheet` makes the same split for
/// the same reason and documents it at length.
struct QuestionAnnouncement: Identifiable, Equatable {

    /// The question that opened, by the only name that is stable across runs.
    ///
    /// `id` is this and nothing else, so `sheet(item:)` can raise it and so two
    /// announcements can never be taken for one. It is also the key written into the
    /// record, which is what makes "once per question, ever" a fact about the file
    /// rather than about this launch.
    let hypothesisId: String
    var id: String { hypothesisId }

    /// Every sentence the sheet shows.
    let sheet: AnnouncementCopy.Sheet

    init(question: Hypothesis, claim: Insight?) {
        hypothesisId = question.id
        sheet = AnnouncementCopy.sheet(for: question, claim: claim)
    }
}

// MARK: - Detection

extension QuestionAnnouncement {

    /// What one launch does about everything that can now be asked.
    ///
    /// Separated from the store so it can be reasoned about and tested without a
    /// record, a repository or an engine run: the whole decision is two sets and an
    /// order.
    struct Detection: Equatable {
        /// The one question to raise, or none.
        let opened: String?
        /// Every key that counts as told from here on, to be written down before
        /// anything is shown.
        let told: Set<String>
    }

    /// The one question to announce, and what to write down.
    ///
    /// - Parameter answerable: every question the engine could test on this run, in
    ///   the registry's own order. **Not sorted by anything.** Ordering by how
    ///   close, how surprising or how strong would make this a ranking of payouts,
    ///   which is `PRD-LOCKS.md` §6's refusal; the registry's order is stable
    ///   between runs and means nothing, which is exactly what is wanted of it.
    /// - Parameter told: keys already announced, or nil when no baseline has ever
    ///   been taken.
    ///
    /// **Nil told is the first run, and it says nothing.** On it, everything
    /// answerable opens at once — a new install with a history behind it, or the
    /// first launch of the build that added this — and an announcement about one of
    /// fifteen simultaneous openings would mean nothing at all. So the first run
    /// absorbs the lot and speaks on the next one.
    ///
    /// **One at a time, and no backlog.** When several open together only the first
    /// is announced and the rest are marked told with it. The alternative is a queue
    /// drip-fed over the following launches, which is the thing §5 refuses — a queue
    /// teaches somebody to dismiss without reading — just spread thin enough to be
    /// harder to see. Nothing is lost by absorbing them: every one of those
    /// questions is open on the Patterns screen the moment it clears its gate, with
    /// its answer beside it, whether or not a sheet said so.
    ///
    /// **`told` only ever grows.** A question that stops being answerable — a
    /// session deleted, a rating removed — and later clears its gate again must not
    /// announce a second time, so keys are never taken back out.
    static func detect(answerable: [String], told: Set<String>?) -> Detection {
        let everything = (told ?? []).union(answerable)
        guard let told else { return Detection(opened: nil, told: everything) }
        return Detection(opened: answerable.first { !told.contains($0) }, told: everything)
    }
}

// MARK: - The words

/// Every sentence the announcement puts on screen.
///
/// **Here rather than in the sheet, so that one sweep sees all of it.** A string
/// authored in a view body is a string no test can find, and this is a screen whose
/// risk is entirely in its words: a single line implying that opening a question
/// pays out a finding makes the feature worse than nothing. The tests walk
/// `Sheet.authoredStrings`.
///
/// **What is carried rather than written.** The answer, when there is one, is the
/// feed's own sentence for that claim — `hypothesis.phrase`, through `Insight
/// .statement` — and the limit is the hypothesis's own caveat. Both are reproduced
/// untouched, because a second wording for one finding is the drift the engine is
/// built to prevent, and because a reader may already have met them on Patterns.
/// The answer when there is none is `QuestionCopy.noSeparation`, which is phase 2's
/// settled wording for exactly this fact and is not re-said here in other words.
enum AnnouncementCopy {

    /// What the sheet is, in the header. Not a prize and not news: a question that
    /// could not be asked can be asked now, which is what "opened" has meant on the
    /// Patterns screen since phase 2 — open or waiting, and nothing else.
    static let standing = "A question opened"

    /// Section 1. Which question, by the name the Patterns row already gives it.
    static let questionHeading = "The question"
    /// Section 2. The answer, immediately, whatever it is.
    static let foundHeading = "What it found"
    /// Section 3. Why this arrived today and not last week.
    static let whyNowHeading = "Why now"
    /// The app's existing word for a caveat, reused rather than renamed, for the
    /// reason `ExperimentCopy.limitHeading` gives: four screens head a limit with
    /// this and a fifth name for one thing would be a fifth thing to recognise.
    static let limitHeading = "Bear in mind"

    /// The one control. Deliberately the same word a finished test closes with —
    /// nothing is being decided here, so the control only has to end it — and
    /// deliberately not "see the question", which would imply this sheet held
    /// something back.
    static let closeTitle = "Got it"

    /// Why the app can ask this now and could not before.
    ///
    /// The gate in days, which is the unit it is actually in and the unit somebody
    /// can act in — the same choice `QuestionCopy.waiting` makes for the other half
    /// of this pair. Nothing about how many questions are open, how many are left,
    /// or how far through anything this is: a count would be the one number
    /// `PRD-LOCKS.md` §6 refuses, because somebody whose days are genuinely flat
    /// will open many of these and find nothing in most, and that is the engine
    /// being right rather than progress through a list.
    static func whyNow(gate: Int) -> String {
        "This comparison needs \(gate) days on each side, and both sides have them now."
    }

    /// What was compared with what, as a noun phrase rather than a claim.
    ///
    /// **Keyed off the registry's own family, because one template does not fit
    /// them.** "Your morning sessions" reads correctly and "your 180 min or more
    /// sessions" does not — a duration is a property of a session, an activity is a
    /// name, and a health split is about the day rather than the session at all.
    /// `QuestionCopy.noun` was written twice before it got this right and its
    /// comment records both wrong sentences; this is the same lesson applied to the
    /// same labels.
    ///
    /// The baseline side is named too, which the Patterns row does not need to do —
    /// it has a section and a neighbour for context. A sheet that arrives unbidden
    /// has neither, and "the two sides came out alike" is not a sentence anybody can
    /// read without knowing which two.
    static func comparison(for question: Hypothesis) -> String {
        let focus = inSentence(question.focusLabel)
        let baseline = inSentence(question.baselineLabel)
        switch question.id.split(separator: ".").first.map(String.init) {
        case "time":
            return "Your \(focus) sessions, against the rest of your day."
        case "duration":
            return "Your sessions of \(focus), against your other lengths."
        // **"Your time in Meetings", not "your Meetings sessions".** An activity is a
        // name somebody chose and several of the defaults are already plural, so the
        // possessive template produced "Your Meetings sessions" and "Your Social
        // sessions". The registry's own phrasing for this family says "your time in
        // Meetings", which is the construction that works whatever the name is, so it
        // is the one used here — and the name keeps its own capitals, because it is
        // theirs.
        case "activity":
            return "Your time in \(question.focusLabel), against everything else you log."
        // The focus is an activity name here too, and for the same reason.
        case "physiology":
            return "Your time in \(question.focusLabel), against \(baseline)."
        case "workday":
            return "Your \(focus), against your \(baseline)."
        // A health question splits the day, not the session, so what it compares is
        // days and the sentence has to say so.
        case "health":
            return "Days with \(focus), against days with \(baseline)."
        // The residual calibration, whose two sides are a position against this
        // person's own usual rather than a thing they did.
        case "residual":
            return "Sessions where your heart rate ran \(focus), "
                + "against the ones where it ran \(baseline)."
        default:
            return "\(question.focusLabel), against \(baseline)."
        }
    }

    /// A headline-cased label, dropped into the middle of a sentence.
    ///
    /// **The first character only, never `lowercased()`.** The registry's labels are
    /// written as headings — "Longer nights", "Higher HRV", "Higher resting HR" — and
    /// lowercasing the lot produced "Days with higher hrv" and "days with lower
    /// resting hr", which is the kind of sentence that tells a reader the app is not
    /// paying attention. Only the opening letter is sentence case; an acronym
    /// somebody's watch gave its own name keeps it.
    static func inSentence(_ label: String) -> String {
        guard let first = label.first else { return label }
        return first.lowercased() + label.dropFirst()
    }

    // MARK: - The sheet

    /// Every sentence the sheet shows, assembled before anything draws it.
    ///
    /// A value rather than a view body, for the reason this file exists: a struct is
    /// swept and asserted against, a `body` can only be looked at. The same split
    /// `ExperimentCopy.ProposalSheet` and `SlotCopy` already make.
    struct Sheet: Equatable {

        /// One thing a section says, in the register its own case names.
        ///
        /// Two cases rather than a flat `[String]`, for the reason `ExperimentCopy
        /// .ProposalSheet.Part` has five: a view that decides a line's weight by
        /// counting the lines breaks the moment a section gains one. The case says
        /// what the thing is and the sheet draws it.
        enum Part: Equatable {
            /// The answer to the section's question.
            case line(String)
            /// A sentence qualifying it, set in the quiet register.
            case quiet(String)

            var strings: [String] {
                switch self {
                case .line(let text), .quiet(let text): [text]
                }
            }
        }

        struct Section: Equatable {
            let heading: String
            let parts: [Part]

            var lines: [String] { parts.flatMap(\.strings) }

            /// What VoiceOver reads for the block.
            ///
            /// Heading first, so the subject arrives before anything else — the rule
            /// `DESIGN.md` records as *Readouts name their subject first*, and the
            /// reason no label here opens with a figure.
            var spoken: String { ([heading] + lines).joined(separator: ". ") }
        }

        /// What this is, in the header.
        let standing: String

        /// Section 1. The question's own name, then what it compares.
        let question: Section
        /// Section 2. The answer. A claim, or that the two sides came out alike.
        let found: Section
        /// Section 3. The gate, now cleared.
        let whyNow: Section
        /// Section 4. The hypothesis's own caveat, carried.
        let limit: Section

        let closeTitle: String

        /// Sentences this file carries rather than writes: the feed's own claim, or
        /// phase 2's settled wording for a non-answer, the caveat, and the question's
        /// own label. Named so `authoredStrings` can subtract them — they are swept
        /// where they are written, and sweeping them again here would make this file
        /// answerable for wording it only reproduces.
        ///
        /// The label matters most of the four. For the activity and physiology
        /// families it is **a word this person typed** — their own name for their own
        /// activity — and no sweep can be answerable for that. The comparison
        /// sentence embeds it, so what the sweep sees of that sentence is the app's
        /// own labels around somebody else's noun, which is the same bargain
        /// `ExperimentCopy.premise` strikes and the reason it is carried there too.
        let carried: [String]

        /// In the order they are read. The answer is second and not last, because a
        /// sheet that explained the gate before saying what it found would be
        /// building up to a payout.
        var orderedSections: [Section] { [question, found, whyNow, limit] }

        /// Everything that reaches the screen, carried sentences included.
        var allStrings: [String] {
            [standing] + orderedSections.flatMap { [$0.heading] + $0.lines } + [closeTitle]
        }

        /// Strings this file is answerable for.
        var authoredStrings: [String] {
            let borrowed = Set(carried)
            return allStrings.filter { !borrowed.contains($0) }
        }

        /// What the whole sheet reads as, for a test that wants to look at it as a
        /// reader would rather than field by field.
        var spoken: String {
            ([standing] + orderedSections.map(\.spoken) + [closeTitle])
                .joined(separator: " ")
        }
    }

    /// The sheet for one question that opened.
    ///
    /// - Parameter claim: the insight the engine published for it, if it published
    ///   one. **Nil is the ordinary case and is not a failure.** It means the
    ///   comparison ran and the two sides did not pull apart, which is a result; the
    ///   sheet says so in the words phase 2 settled on and in the same shape it uses
    ///   for a claim. The caveat comes from the insight when there is one, because
    ///   that copy carries the uneven-coverage addendum the raw hypothesis caveat
    ///   does not.
    static func sheet(for question: Hypothesis, claim: Insight?) -> Sheet {
        let answer = claim?.statement ?? QuestionCopy.noSeparation
        let limit = claim?.caveat ?? question.caveat

        return Sheet(
            standing: standing,
            question: .init(heading: questionHeading,
                            // The name first, in the words the Patterns row already
                            // uses for this question, so the two screens cannot
                            // disagree about what it is called.
                            parts: [.line(question.focusLabel),
                                    .quiet(comparison(for: question))]),
            found: .init(heading: foundHeading, parts: [.line(answer)]),
            whyNow: .init(heading: whyNowHeading,
                          parts: [.line(whyNow(gate: question.minimumDays))]),
            limit: .init(heading: limitHeading, parts: [.line(limit)]),
            closeTitle: closeTitle,
            carried: [answer, limit, question.focusLabel]
        )
    }
}
