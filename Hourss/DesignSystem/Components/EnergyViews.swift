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
