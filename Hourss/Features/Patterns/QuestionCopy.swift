import Foundation

/// What a question on the Patterns screen says about itself.
///
/// **A question is open or it is not, and that is the whole ladder.** The design
/// started with three states — open, close, far — and a separate "worth testing"
/// section beside them, which is four things for a reader to tell apart. Two of
/// those four turned out to be the same thing:
///
/// A **lead** is a question that cleared its gate, was measured, and did not
/// separate. That is not a third kind of card. It is what an *open* card says when
/// the answer is nothing, which `PRD-LOCKS.md` §2 insists is the common case and the
/// one the design has to be good at. Giving it its own section said the opposite —
/// that a measured non-answer belongs somewhere other than with the answers.
///
/// So: **open** (measured, with the finding or the absence of one) and **waiting**
/// (not measured, with what it is waiting for). Close and far are both waiting, told
/// apart by their sentence rather than by their state, because "two more afternoon
/// days" is a task somebody finishes this week and "you have not logged an evening"
/// is not the same sentence at all.
///
/// **Nothing here promises a finding.** A question that opens may say nothing stood
/// out, and a line that implied otherwise would make the screen a slot machine that
/// mostly pays nothing — the first empty card then teaches somebody the whole thing
/// is a tease. Every sentence below names what is missing or what was found, and
/// never what might be.
enum QuestionCopy {

    /// What a question that cannot be asked yet is waiting for.
    ///
    /// Named in days on the side that is short, because days are the unit the gate
    /// is in and the unit somebody can act in. Never a percentage and never a bar
    /// toward a total — `PRD-LOCKS.md` §6 refuses a completion measure, since
    /// somebody whose days are genuinely flat will open many of these and find
    /// nothing in most, and that is the engine being right.
    static func waiting(_ question: Engine.Pending) -> String {
        let hypothesis = question.hypothesis
        let focusShort = question.focusDays < question.gate
        let label = focusShort ? hypothesis.focusLabel : hypothesis.baselineLabel

        // Never happened at all. A different gap from being short of one, and the
        // sentence says so rather than quoting a number somebody cannot act on by
        // doing more of what they are already doing.
        if focusShort && question.focusDays == 0 {
            return "No \(noun(for: hypothesis, label: label, plural: true)) yet."
        }
        if !focusShort && question.baselineDays == 0 {
            return "Everything you have rated is in one place, so there is nothing to compare."
        }

        let short = question.gate - (focusShort ? question.focusDays : question.baselineDays)
        let days = short == 1 ? "day" : "days"
        return focusShort
            ? "\(short) more \(days) with \(noun(for: hypothesis, label: label))."
            : "\(short) more \(days) with something other than \(noun(for: hypothesis, label: label))."
    }

    /// What a side *is*, as a noun phrase a sentence can be built around.
    ///
    /// **One phrasing does not fit the families.** "In your morning" reads correctly
    /// and "in your 180 min or more" does not — a duration bucket is a property of a
    /// session rather than a place in the day, and an activity is a name rather than
    /// either. Written as one template it produced "Nothing logged in your 180 min or
    /// more yet", which is the kind of sentence that tells a reader the app is not
    /// paying attention.
    ///
    /// Keyed off the id's own family, which is the registry's own spelling and the
    /// only thing that distinguishes `sleepContext` from `bodyContext` either.
    /// - Parameter plural: "No **sessions in your evening** yet" against "3 more days
    ///   with **a session in your evening**". One form cannot serve both — written
    ///   with only the singular it produced "No a session in your evening yet", and
    ///   the test for it hedged with an `||` rather than failing, which is how a
    ///   sentence like that survives.
    private static func noun(for hypothesis: Hypothesis, label: String,
                             plural: Bool = false) -> String {
        let one = plural ? "sessions" : "a session"
        switch hypothesis.id.split(separator: ".").first.map(String.init) {
        case "time":      return "\(one) in your \(label.lowercased())"
        case "duration":  return "\(one) of \(label.lowercased())"
        case "activity":  return "\(one) of \(label)"
        case "workday":   return "\(one) on \(label.lowercased())"
        // Health splits on the day rather than the session, so the thing that is
        // missing is a *day* of that kind with something rated on it.
        case "health":    return plural ? "rated days \(label.lowercased())"
                                        : "a rated day \(label.lowercased())"
        default:          return "\(one) in \(label.lowercased())"
        }
    }

    /// What an open question says when the comparison did not separate.
    ///
    /// Deliberately not "nothing yet": for somebody whose days genuinely are flat it
    /// will never be anything else, and "yet" is a promise in one syllable that the
    /// engine cannot keep. `ObservationSlotView.stillLookingCopy` settles the same
    /// point in the same words.
    static let noSeparation = "Measured, and the two sides came out alike."

    /// The heading above questions that cannot be asked yet.
    static let waitingHeading = "Waiting on"

    /// The one line that stands in for every waiting question whose gap is total.
    ///
    /// **It names the question's shape, not the person's.** "Things you have not
    /// logged" was the first draft and it puts the gap on the reader, which is one
    /// short step from a list of errands — and `PRD-LOCKS.md` §6 refuses that shape
    /// by name, because ordering or framing these as tasks is how a record becomes a
    /// chore. A side with nothing in it is a fact about the comparison. It is also
    /// the actual reason these fold and the ones above them do not: there is no
    /// number to print, so there is nothing to read.
    ///
    /// **It says what is inside.** A fold whose label is a count — or worse, a
    /// chevron — is a box the reader has to open to learn anything, and a count is
    /// the figure this whole feature refuses to compute. This says the kind of thing
    /// in there, and by contrast with the rows above it ("3 more days with a session
    /// of Creative") it says how they differ: those are short by an amount, these
    /// have not started.
    ///
    /// **Twenty-eight characters, and that is a constraint rather than a
    /// coincidence.** It is set at `.action`, which scales from `.subheadline`, so at
    /// `AccessibilityL` it is roughly 30pt bold in a 357pt column — about twenty
    /// characters to the line. Two lines is the budget; a fold whose own label runs
    /// to four has not shortened anything.
    static let foldedHeading = "Questions with an empty side"

    /// What opening and closing the fold do, for somebody who cannot see the arrow.
    ///
    /// "Shows" and "hides", not "reveals" — a reveal is the slot-machine word, and
    /// nothing is being uncovered here. The rows were always going to say what they
    /// say; the list was simply long.
    static let foldOpenHint = "Shows those questions."
    static let foldCloseHint = "Hides those questions."
}
