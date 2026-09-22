import SwiftUI

/// What the first rating of the day gives back: one fact about the day itself.
///
/// **The governing rule: this card is byte-identical whatever was rated.** It
/// does not mention the rating, does not name the session, and does not change
/// between a 5 and a 2. It is shown *after* a rating only because that is when
/// somebody is looking; it is not *about* the rating.
///
/// That is a correctness rule, not a matter of taste. The obvious version —
/// "You rated this 5/5. You slept 8h 02m, your longest in eleven days." — is a
/// claim that a relationship exists between the two numbers, and it breaks three
/// written rules at once:
///
/// * **n = 1.** Every sanctioned juxtaposition in this app aggregates over days;
///   `RegistryTests` requires health copy to begin "On days " — plural, because
///   one day is an anecdote and the whole engine exists to not ship anecdotes.
/// * **Cause-shaped grammar.** Putting the rating first and the health reading
///   after it places the reading in the explanatory slot, which is exactly what
///   `HealthMetric.caveat` warns is unwarranted ("Quiet time may follow a good
///   day as easily as cause one").
/// * **A missing caveat.** `EngineContracts` calls the caveat "never optional"
///   for anything built on a health metric, and a test enforces it.
///
/// So the card states a figure and a superlative inside the person's own record,
/// and stops. A superlative about somebody's own history is not a population
/// comparison and needs no cohort — "your longest night in eleven days" is
/// arithmetic on their own nights.
struct DayContextCard: View {

    /// The two things this card can be, and never both at once.
    ///
    /// Either-or is the load-bearing part. A milestone is about the rating and a
    /// standout is about the day, and a card carrying both would be pairing a
    /// rating with something measured separately from it — the exact
    /// juxtaposition the rule above forbids, arrived at by addition rather than
    /// by phrasing. An enum makes that unrepresentable instead of relying on
    /// nobody putting the two in the same `VStack`.
    enum Content: Equatable {
        /// A superlative about the day, which the rating cannot move.
        case health(DayDeviation.Standout)
        /// A rating that beat everything logged before it. One measurement, so
        /// no relationship is asserted — see `RatingMilestone`.
        case milestone(RatingMilestone)
    }

    let content: Content
    let onDismiss: () -> Void

    /// The three lines the card leads with.
    ///
    /// The title is new and everything about it is old: it is the metric's own
    /// name, routed through `DayContextCopy` like every other word the card can
    /// say so the copy sweep in `DayDeviationTests` covers it too. The figure
    /// used to sit at the top alone, which is the failure `TitledFigure`
    /// documents — "8h 02m" is not a fact about sleep until something on screen
    /// says sleep, and the only thing that did was the sentence underneath.
    ///
    /// It carries no new dependency on the rating, because `DayDeviation.Standout`
    /// has never carried one. The card's governing rule survives by the same
    /// mechanism as before: there is nothing here for a score to change.
    ///
    /// Not private, so a test can read the spoken order without rendering the
    /// card — the order is the whole point of the change.
    var titled: TitledFigure {
        TitledFigure(
            title: DayContextCopy.title(content),
            figure: DayContextCopy.figure(content),
            detail: DayContextCopy.sentence(content)
        )
    }

    /// The eyebrow says which question the card is answering.
    ///
    /// "Today" for a standout, because that is the window it is a superlative
    /// over. A milestone is not about today at all — it is about the whole
    /// record — and labelling it "Today" would have narrowed a claim that is
    /// deliberately wider.
    private var eyebrow: String {
        switch content {
        case .health: "Today"
        case .milestone: "In your record"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Space.md) {
                Eyebrow(eyebrow)

                titled
                    .accessibilityElement(children: .combine)
                    // Subject, then number, then sentence — the order the block
                    // is printed in, so a reader is never handed a figure before
                    // the thing it measures.
                    .accessibilityLabel(titled.spoken)

                // Health only, and the asymmetry is the rule rather than an
                // oversight. `EngineContracts` calls the caveat never optional
                // for anything built on a health metric, because a health number
                // invites a medical reading it cannot support. A milestone is
                // arithmetic on the person's own ratings — there is no metric
                // behind it and no second variable to be cautious about, which is
                // why `RecordFacts` ships its superlatives without one either.
                // Inventing a caveat here would mean authoring one beside a
                // sentence, which is the drift the note below warns against.
                if case .health(let standout) = content {
                    HRule()

                    // Straight from the metric, never written here. A caveat
                    // authored beside a particular sentence drifts from the one
                    // the engine shows for the same metric, and then the app is
                    // quietly making two different promises about one number.
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Bear in mind")
                        Text(standout.metric.caveat)
                            .textStyle(.label)
                            .foregroundStyle(Color.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Bear in mind: \(standout.metric.caveat)")
                }
            }
            .pageGutter()

            Spacer(minLength: 0)

            // One way out, and it is the only control on the card. Hierarchy here
            // is a rule and a figure — `Primitives` is explicit that this system
            // has no card surface to put things on.
            VStack(spacing: 0) {
                HRule()
                HStack {
                    Spacer()
                    DirectionalLink(title: "Done", arrow: "→", action: onDismiss)
                }
                .pageGutter()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .surface(.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day-context-card")
    }
}

/// Every word the card can say.
///
/// Pure and separate from the view so the copy can be swept by a test rather
/// than read by a person. The sweep is the point: the banned-word list is long,
/// the failure it prevents is a sentence that quietly claims causation, and
/// nobody catches that reliably by eye at review time.
enum DayContextCopy {

    /// What the card is about, which is a metric name and nothing more.
    ///
    /// Straight from `HealthMetric.title` — the same strings the consent list
    /// shows — rather than authored here. That is what makes adding a line to
    /// this card safe: a name states no relationship, so it cannot be causal,
    /// clinical, population-relative or instructional, and it cannot leak a
    /// prior. It is still routed through this enum and still swept, because the
    /// rule is that *every* word the card says is swept, and an exemption is the
    /// kind of thing that quietly grows.
    static func title(_ content: DayContextCard.Content) -> String {
        switch content {
        case .health(let standout): standout.metric.title
        // The same register as a metric name: a noun for what was measured. Kept
        // identical to `HealthDigest.RecordTopic.ratings.title` would be better
        // still, but that case does not exist — a ratings superlative cannot live
        // in the dispensed pool at all, for the reason `RatingMilestone` gives.
        case .milestone: "How sessions felt"
        }
    }

    /// The figure, in the metric's own unit. Deliberately its own formatter
    /// rather than a widened `HealthDigest.difference`, which is private and
    /// phrases *differences between two groups* — a different sentence, and the
    /// two should be free to diverge.
    static func figure(_ content: DayContextCard.Content) -> String {
        switch content {
        case .milestone(let milestone): return "\(milestone.rating) / 5"
        case .health(let standout): return healthFigure(standout)
        }
    }

    private static func healthFigure(_ standout: DayDeviation.Standout) -> String {
        switch standout.metric {
        case .sleepHours:
            // Hours and minutes, because nobody reads "8.03 hours" as a night.
            let minutes = Int((standout.value * 60).rounded())
            guard minutes >= 60 else { return "\(minutes)m" }
            return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
        case .respiratoryRate:
            // A breathing rate moves in tenths; rounding to whole breaths would
            // make two visibly different days print the same number.
            return "\(String(format: "%.1f", standout.value)) \(standout.metric.shortUnit)"
        default:
            return "\(Int(standout.value.rounded())) \(standout.metric.shortUnit)"
        }
    }

    /// The one sentence, which is a superlative inside the person's own record
    /// and nothing else.
    ///
    /// Only direction words — longer, shorter, higher, lower, faster, slower.
    /// Never better or worse: the README is explicit that this app does not know
    /// which direction of a metric is the good one, and saying so would be a
    /// medical opinion it has no basis for.
    static func sentence(_ content: DayContextCard.Content) -> String {
        switch content {
        case .health(let standout):
            return "\(superlative(standout)) in \(spelled(standout.spanDays)) days."
        case .milestone(let milestone):
            // Names what it beat, for the same reason every other superlative
            // here does: a reader told "the highest so far" with no sample in
            // front of them will assume a longer record than exists.
            return "\(milestone.name) is the highest you have rated anything, "
                + "out of \(milestone.beatCount) rated sessions."
        }
    }

    private static func superlative(_ standout: DayDeviation.Standout) -> String {
        switch standout.metric {
        case .sleepHours:
            standout.isHigh ? "Your longest night" : "Your shortest night"
        case .hrv:
            standout.isHigh ? "Your highest heart rate variability" : "Your lowest heart rate variability"
        case .restingHeartRate:
            standout.isHigh ? "Your highest resting heart rate" : "Your lowest resting heart rate"
        case .respiratoryRate:
            standout.isHigh ? "Your fastest breathing" : "Your slowest breathing"
        // Unreachable: `DayDeviation.eligibleMetrics` is the only source of
        // standouts. Present because the switch is exhaustive, and phrased so it
        // could not accidentally ship a verdict if that ever changed.
        default:
            standout.isHigh ? "Your highest \(standout.metric.plainName)" : "Your lowest \(standout.metric.plainName)"
        }
    }

    /// Small numbers read as words in a sentence and as data in digits. The card
    /// is a sentence, and the span is never smaller than seven.
    private static func spelled(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                     "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
                     "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        return words.indices.contains(count) ? words[count] : "\(count)"
    }
}
