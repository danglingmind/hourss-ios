import SwiftUI

/// The horizontal energy bar from the landing page's timeline.
///
/// Colour is derived from the feeling score rather than from row position (the web
/// page keys it off CSS child index, which does not generalise). It is never the
/// only carrier of meaning — the score and its wording always travel with it,
/// per the system's `colorIndependence` rule.
struct EnergyBar: View {
    /// 0–100. Nil renders an empty track, meaning "not rated" — never a middle value.
    let score: Int?
    var height: CGFloat = DataBar.reading

    var body: some View {
        DataBar(
            fraction: score.map { Double($0) / 100 },
            fill: score.map(Feeling.fillColor(forScore:)) ?? .lime,
            height: height
        )
    }
}

/// The score readout beside a timeline: the session's own name, then its score,
/// then a human observation rather than a verdict.
///
/// This used to set the score as a 58pt serif numeral over an 11pt mono caption.
/// The caption was already above the number, so the reading order was right and
/// the *weight* was wrong: at five times the size, the numeral was the only thing
/// the eye landed on, and it was the one element that could not be understood on
/// its own — "87" is not a reading until you know it is about a run. So the
/// activity's name takes the top step and the score takes the second, via
/// `TitledFigure`, which is where the app's three-step hierarchy lives.
///
/// Nothing is lost by dropping the lime numeral: the numeral was always lime
/// regardless of score, so its colour never carried a value. The score's own
/// wording still travels with it in `note`, per `colorIndependence`.
struct EnergyReading: View {
    let score: Int?
    let caption: String
    let note: String

    /// Subject, figure, detail. The title is the activity's own name — nothing
    /// new is written here, so nothing here has to clear the phrasing rules.
    private var figure: TitledFigure {
        TitledFigure(
            title: caption,
            figure: score.map { "\($0)/100" } ?? "Not rated",
            detail: note
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HRule()
            figure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }

    /// The same order the layout reads in, with the score spelled out rather than
    /// punctuated: "87/100" is announced as "87 slash 100" by some voices, and the
    /// feeling word has to be spoken because the bar beside it cannot be.
    ///
    /// Built here rather than taken from `TitledFigure.spoken` only because of
    /// those two substitutions; the order is identical either way.
    var spoken: String {
        score.map { "\(caption). \($0) out of 100, \(Feeling.describe(score: $0)). \(note)" }
            ?? "\(caption). Not rated. \(note)"
    }
}

/// A 1–5 rating scale. Flat segments, no pills, and no pre-selection: an
/// unanswered scale must stay unanswered rather than defaulting to the middle.
///
/// The two scales in the app measure different things, so each carries its own
/// endpoint wording and per-step labels — a performance question read out as
/// "Draining → Energizing" would be telling the user the wrong thing.
struct RatingScale: View {
    @Binding var value: Int?
    var kind: Kind = .feeling
    /// Shown under the scale in mono. Used to mark a scale as optional.
    var caption: String?

    @Environment(\.surface) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Kind {
        case feeling
        case performance

        var title: String {
            switch self {
            case .feeling: "How did that feel?"
            case .performance: "How well did it go?"
            }
        }

        var lowLabel: String {
            switch self {
            case .feeling: "Draining"
            case .performance: "Not my best"
            }
        }

        var highLabel: String {
            switch self {
            case .feeling: "Energizing"
            case .performance: "Went well"
            }
        }

        var identifierPrefix: String {
            switch self {
            case .feeling: "feeling"
            case .performance: "performance"
            }
        }

        func label(forRating rating: Int) -> String {
            switch self {
            case .feeling:
                Feeling.label(forRating: rating)
            case .performance:
                switch rating {
                case 1: "Not my best"
                case 2: "Below par"
                case 3: "Fine"
                case 4: "Good"
                default: "Went well"
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(kind.title).textStyle(.sectionLead)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        // Tapping the selected step clears it, so a rating given by
                        // accident can be taken back rather than only changed.
                        value = (value == score) ? nil : score
                    } label: {
                        VStack(spacing: Space.xs) {
                            Rectangle()
                                .fill(value == score ? Feeling.fillColor(forRating: score) : surface.track)
                                .frame(height: 44)
                            Text("\(score)")
                                .textStyle(.label)
                                .foregroundStyle(value == score ? surface.foreground : surface.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(kind.identifierPrefix)-\(score)")
                    .accessibilityLabel("\(score), \(kind.label(forRating: score))")
                    .accessibilityAddTraits(value == score ? [.isSelected] : [])
                }
            }
            .animation(Motion.animation(reduced: reduceMotion), value: value)

            HStack {
                Text(kind.lowLabel).textStyle(.label).foregroundStyle(surface.secondary)
                Spacer()
                Text(kind.highLabel).textStyle(.label).foregroundStyle(surface.secondary)
            }

            if let caption {
                Text(caption)
                    .textStyle(.label)
                    .foregroundStyle(surface.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Flat selectable chips, used for onboarding intents and the activity picker.
/// Square corners — `radius.default` is 0 throughout this system.
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    /// Optional activity mark, shown ahead of the name so a list of eight is
    /// scannable by shape as well as by reading.
    var glyph: ActivityGlyph.Kind?
    let action: () -> Void

    init(title: String, isSelected: Bool, glyph: ActivityGlyph.Kind? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.glyph = glyph
        self.action = action
    }

    @Environment(\.surface) private var surface

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                if let glyph {
                    ActivityGlyph(
                        kind: glyph,
                        size: 14,
                        color: isSelected ? .ink : surface.secondary
                    )
                }
                Text(title)
            }
                .textStyle(.action)
                .foregroundStyle(isSelected ? Color.ink : surface.foreground)
                .padding(.horizontal, Space.sm)
                .frame(height: Space.tapTarget)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.lime : Color.clear)
                .overlay(alignment: .bottom) { HRule() }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - The movement-adjusted heart-rate reading

/// A residual that has earned the right to be on screen, reduced to the three
/// things any surface needs to say it.
///
/// **The failable init is the gate, and it is the whole point of the type.**
/// `Physiology.Reading.exceedsUncertainty` is documented as the line between a
/// finding and a number — "anything that does not is a number, not a finding,
/// and must not be shown as one" — and a rule enforced by everyone remembering
/// to write `if reading.exceedsUncertainty` is a rule that survives until the
/// third call site. There is no other way to make one of these, so a residual
/// inside its own error bar cannot reach a view, cannot reach `DayContextCard`,
/// and cannot be constructed by a future caller who has not read `Physiology`.
///
/// It also keeps `Physiology.Reading` out of the views entirely. The store's
/// `physiologyReadings` is the seam, the layer underneath it is free to change,
/// and the only thing the UI ever holds is three finished strings' worth of
/// state — which is also why this is `Equatable` and `Reading` need not be.
struct SessionResidual: Equatable {
    /// How far the heart rate ran from what was expected, in whole bpm, with no
    /// sign. The direction is a word, never a minus.
    let bpm: Int
    /// Which way. A bare direction and nothing more — see `ResidualCopy`.
    let isHigher: Bool
    /// The movement half, taken verbatim from `Physiology.CadenceBin.context`.
    /// Never re-worded here: that property exists precisely so the movement is
    /// stated without a cause being named, and a second vocabulary for the same
    /// idea is a second place for a verdict to creep in.
    let movementContext: String

    /// Nil unless there is a reading and it clears its own uncertainty.
    ///
    /// Takes an optional so every call site can pass a dictionary lookup
    /// straight in. The alternative — callers unwrapping first — puts a
    /// `reading != nil` check next to every gate and invites somebody to write
    /// only the first one.
    init?(_ reading: Physiology.Reading?) {
        guard let reading, reading.exceedsUncertainty else { return nil }
        // `uncertainty` is at least `1.5 + motion + thinness` before the person's
        // own scatter is added, so a residual that clears it never rounds to
        // zero. `max(1, …)` is here anyway because "0 bpm above expected" is a
        // sentence that contradicts itself, and it should not be one unlucky
        // change to the error bar away from shipping.
        self.bpm = max(1, Int(abs(reading.residual).rounded()))
        self.isHigher = reading.residual > 0
        self.movementContext = reading.movementContext
    }
}

/// Every word any surface may say about a residual.
///
/// Pure and separate from the views for the same reason `DayContextCopy` is: the
/// rules this copy has to clear are not the kind a reviewer reliably checks by
/// eye, and a sweep over a function is cheap. Both surfaces that show a residual
/// — the timeline's session detail and the post-rating card — route through
/// here, so there is one vocabulary to hold to the rules rather than two.
///
/// **What may not be said, and why it is not a matter of taste.**
/// `Outcome.heartRateResidual.higherIsBetter` is nil on purpose: a heart rate
/// above what movement explains is not "bad", and calling it so would be a
/// medical claim this app is not equipped or licensed to make. `Physiology`
/// states the same rule about its own output — "a number and a movement context,
/// never a judgement; nothing here may state or imply stress, intensity, effort,
/// or emotion". So the only direction words available are the bare ones: above,
/// below, higher, lower. Never better, worse, harder, easier, calm, strain,
/// effort, intense, stress, or recovery.
enum ResidualCopy {

    /// What this is about: the name of the thing measured, and nothing else.
    ///
    /// A noun states no relationship, so it cannot be causal, clinical or
    /// population-relative — the same reason `DayContextCopy.title` is a metric
    /// name rather than a sentence.
    static let title = "Heart rate"

    /// The figure, in the unit the number is actually in.
    ///
    /// "Expected" is `Reading.expected`'s own word, documented as "what this
    /// person's own cadence, hour and day type predict". It reads as a baseline
    /// rather than as a norm because the sentence underneath says whose baseline
    /// it is, and that pairing is why the figure can be this short.
    ///
    /// The direction is a word rather than a sign. A "+" would be the whole
    /// meaning carried by one glyph, which fails the same rule colour fails.
    static func figure(_ residual: SessionResidual) -> String {
        "\(residual.bpm) bpm \(residual.isHigher ? "above" : "below") expected"
    }

    /// The one sentence, which carries the two things the figure cannot: whose
    /// baseline this is, and how much movement there was.
    ///
    /// "Measured against your own pace and hour" is doing the load-bearing work.
    /// The curve is fitted per person and never across people, because a
    /// population curve would answer "is this person's heart rate high for a
    /// human" — a medical question this product does not ask. Saying so on the
    /// card is what stops a reader supplying the population comparison
    /// themselves.
    ///
    /// "Ran" matches the register `HypothesisRegistry` uses for this outcome and
    /// nothing else: `Narration` switches the verb to "have run" for
    /// `heartRateResidual` while every other outcome gets "have felt". A heart
    /// rate is a thing that ran. It is not a thing that was felt, and borrowing
    /// the feeling verb would quietly turn a measurement into a report of an
    /// inner state.
    ///
    /// The movement half is `Physiology.CadenceBin.context` verbatim.
    static func sentence(_ residual: SessionResidual) -> String {
        "Measured against your own pace and hour, your heart rate ran "
            + (residual.isHigher ? "higher" : "lower") + ", \(residual.movementContext)."
    }

    /// The caution that travels with the number.
    ///
    /// Not authored here. This is `HypothesisRegistry`'s caveat for
    /// `Outcome.heartRateResidual`, copied verbatim, for the reason
    /// `DayContextCard` already gives about health caveats: one authored beside a
    /// particular sentence drifts from the one the engine shows for the same
    /// number, and then the app is making two different promises about one thing.
    ///
    /// Duplicated rather than read from the registry because the registry holds
    /// it inside a `Hypothesis` literal that only exists once twelve scored
    /// sessions do, and a view cannot run the engine to find out what to say.
    /// `Narration.direction` duplicates `HypothesisRegistry.direction` for the
    /// same reason and states the deal plainly: the words must match, and the
    /// test that they do is cheaper than the coupling. `ResidualCopyTests` is
    /// that test.
    static let caveat = "Heart rate moves with more than effort — a warm room, caffeine, or talking will do it."
}

/// The residual for one session, under the reading it belongs to.
///
/// Takes an optional and draws nothing when it is nil, so the gate lives in one
/// place — `SessionResidual.init?` — rather than at every call site. A caller
/// cannot get this on screen for a residual inside its own error bar, because a
/// caller cannot make the value.
///
/// Built from `TitledFigure` like every other readout in the app, so a reader is
/// handed the subject before the number. "6 bpm above expected" is not a fact
/// about a heart rate until something on screen says heart rate.
struct ResidualReading: View {
    let residual: SessionResidual?

    init(_ residual: SessionResidual?) { self.residual = residual }

    /// Not private, so a test can read the spoken order without rendering.
    var titled: TitledFigure? {
        residual.map {
            TitledFigure(
                title: ResidualCopy.title,
                figure: ResidualCopy.figure($0),
                detail: ResidualCopy.sentence($0)
            )
        }
    }

    var body: some View {
        if let titled {
            VStack(alignment: .leading, spacing: Space.sm) {
                // A rule, because hierarchy in this system comes from lines. This
                // is a second, separately-measured reading sitting under the
                // first, and the line is what says so.
                HRule()
                titled
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // Subject, then number, then sentence — `TitledFigure.spoken`'s own
            // order, which is the order the block is printed in.
            .accessibilityLabel(titled.spoken)
            .accessibilityIdentifier("session-residual")
        }
    }
}
