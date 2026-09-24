import SwiftUI

/// The vertical timeline, ported from the landing page's signal section.
///
/// Selection is an orange rule in the gutter, full-strength times, and everything
/// unselected dropped to 0.42. The system's original spec — 0.53 opacity and a
/// 4pt shift — was too quiet to find: on a day holding two rows there is nothing
/// for the dimming to be read against, and the shift moved the list on every tap
/// without ever saying which row had won. Colour still never carries the meaning
/// alone: the score and its wording sit beside the bar, and the reading below
/// names the session it belongs to.
struct DayTimeline: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sessions: [Session]
    /// Start of the day these sessions belong to. Only the hour strip needs it —
    /// the rows carry their own clocks — but it has to come from the caller,
    /// because a night read from Health starts before the day it is filed under.
    let day: Date
    @Binding var selectedSessionId: UUID?

    private var selected: Session? {
        sessions.first { $0.id == selectedSessionId } ?? sessions.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HRule()

            // Above the rows, because it answers a question the rows cannot: the
            // list says what happened, and this says which of the day's hours are
            // spoken for at all. The gaps are the part worth seeing.
            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow("Hours logged")
                DayHours(
                    sessions: sessions,
                    day: day,
                    feeling: { store.feeling(for: $0.id) },
                    name: { store.activityName($0.activityId) },
                    onSelect: { selectedSessionId = $0.id },
                    onFill: { store.requestLog(at: $0) }
                )
            }

            VStack(spacing: 2) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
            .animation(Motion.content(reduced: reduceMotion), value: selectedSessionId)

            if let selected {
                EnergyReading(
                    score: store.feeling(for: selected.id).map(Feeling.score(forRating:)),
                    caption: store.activityName(selected.activityId),
                    note: note(for: selected)
                )

                // The same session's heart rate, when there is a reading for it
                // that clears its own error bar. Nil the rest of the time, and
                // `ResidualReading` draws nothing — which is most of the time,
                // because a window needs enough samples, a clean lead-in and a
                // fitted curve before it produces anything at all.
                //
                // Here rather than at the rating moment, and the reason is the
                // watch. watchOS hands heart-rate samples to the phone
                // opportunistically, so the window that closed a minute ago
                // usually has nothing in it yet; anything shown at the tap would
                // be empty for most people most of the time and would look
                // broken rather than absent. This surface makes no promise about
                // when: it shows the reading for whichever session is selected,
                // whenever the samples have arrived, attached to the session it
                // is about.
                ResidualReading(SessionResidual(store.physiologyReadings[selected.id]))
            }
        }
    }

    private func row(_ session: Session) -> some View {
        let isSelected = selected?.id == session.id
        let feeling = store.feeling(for: session.id)

        return Button {
            selectedSessionId = session.id
        } label: {
            HStack(spacing: 0) {
                // The selected row's own mark, in the gutter.
                //
                // Opacity and a 4pt shift were the whole affordance, and on a day
                // with two rows there is nothing to compare the dimming against —
                // a single unselected row just looks like a row. A rule is the
                // system's own device for weight, and this is the first thing in
                // the app to use orange as a signal rather than as an arrow: it
                // marks the one row the reading underneath belongs to.
                Rectangle()
                    .fill(isSelected ? Color.orange : .clear)
                    .frame(width: 3)
                    .padding(.trailing, Space.xs)

                // Both ends, stacked. One time said when something started and
                // left "for how long" to be inferred from a bar, which is the one
                // question a record of your hours should never make you estimate.
                // Stacked rather than "9:00 – 10:30" on one line because a
                // twelve-hour locale spends a third of the row on that string and
                // takes it from the activity's name.
                VStack(alignment: .leading, spacing: 2) {
                    Text(clock(session.startAt))
                        .textStyle(.label)
                        // Full strength on the selected row. The times are the
                        // one column where dimming reads as "unimportant" rather
                        // than "not this one".
                        .foregroundStyle(isSelected ? Color.ink : Color.muted)
                    // Dropped when both ends land in the same minute — a session
                    // stopped seconds after it began printing its own clock twice
                    // looks like a fault in the row rather than a very short
                    // session, which is all it is.
                    if clock(end(of: session)) != clock(session.startAt) {
                        Text(clock(end(of: session)))
                            .textStyle(.label)
                            .foregroundStyle(Color.tertiaryOnCanvas)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                .frame(width: 74, alignment: .leading)

                EnergyBar(score: feeling.map(Feeling.score(forRating:)))
                    .frame(width: 92)

                Text(session.intention ?? store.activityName(session.activityId))
                    .textStyle(.body)
                    .lineLimit(1)
                    .padding(.leading, Space.sm)

                // Marked, always. A row Hourss put there by reading a watch is a
                // different kind of claim from one somebody logged, and a record
                // that does not say which is which is asking to be trusted about
                // something it has not disclosed. The mono label is the same idiom
                // as the time column beside it, so it reads as metadata rather
                // than as a badge.
                if session.isImported {
                    Text("Health")
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, Space.xs)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
            .frame(minHeight: Space.tapTarget)
            // Pushed further than the system's 0.53, and the 4pt shift is gone:
            // the rule in the gutter already says which row this is, and two
            // devices moving at once made the list twitch on every tap.
            .opacity(isSelected ? 1 : 0.42)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline-row")
        .accessibilityLabel(accessibilityLabel(session, feeling: feeling))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Where a session finished. A running one has no `endAt` yet, and
    /// `durationSeconds` already answers that by measuring to now.
    private func end(of session: Session) -> Date {
        session.endAt ?? session.startAt.addingTimeInterval(TimeInterval(session.durationSeconds))
    }

    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func accessibilityLabel(_ session: Session, feeling: Int?) -> String {
        let start = clock(session.startAt)
        let finish = clock(end(of: session))
        let time = start == finish ? start : "\(start) to \(finish)"
        let name = session.intention ?? store.activityName(session.activityId)
        let felt = feeling.map { ", felt \(Feeling.label(forRating: $0).lowercased())" } ?? ", not rated"
        let origin = session.isImported ? ", read from Health" : ""
        return "\(time), \(name), \(formatMinutes(session.durationMinutes))\(origin)\(felt)"
    }

    /// The note the user wrote, or a plain description of the session. Never a
    /// verdict on it.
    private func note(for session: Session) -> String {
        if let note = store.reflection(for: session.id)?.note ?? session.note, !note.isEmpty {
            return note
        }
        let length = formatMinutesShort(session.durationMinutes)

        // A night is never asked about, so it must not be described as an
        // unanswered question. Saying "you haven't said how this felt" about
        // something the app deliberately never prompts for reads as a reproach for
        // an omission that is Hourss's own choice.
        if session.healthKind == .sleep {
            return "\(length) asleep, read from Health."
        }

        guard let feeling = store.feeling(for: session.id) else {
            return session.isImported
                ? "\(length), read from Health. You haven't said how this one felt."
                : "\(length). You haven't said how this one felt."
        }
        return "\(length), \(Feeling.label(forRating: feeling).lowercased())."
    }
}
