import SwiftUI

/// The vertical timeline, ported from the landing page's signal section.
///
/// Selection behaves as the design system specifies: inactive rows sit at 0.53
/// opacity, the active row shifts 4pt right, and the reading below updates to
/// match. Colour never carries the meaning alone — the score and its wording sit
/// beside the bar.
struct DayTimeline: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sessions: [Session]
    @Binding var selectedSessionId: UUID?

    private var selected: Session? {
        sessions.first { $0.id == selectedSessionId } ?? sessions.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HRule()

            VStack(spacing: 2) {
                ForEach(sessions) { session in
                    row(session)
                }
            }
            .animation(Motion.animation(reduced: reduceMotion), value: selectedSessionId)

            if let selected {
                EnergyReading(
                    score: store.feeling(for: selected.id).map(Feeling.score(forRating:)),
                    caption: store.activityName(selected.activityId),
                    note: note(for: selected)
                )
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
                Text(session.startAt.formatted(.dateTime.hour().minute()))
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 74, alignment: .leading)

                EnergyBar(score: feeling.map(Feeling.score(forRating:)))
                    .frame(width: 92)

                Text(session.intention ?? store.activityName(session.activityId))
                    .textStyle(.body)
                    .lineLimit(1)
                    .padding(.leading, Space.sm)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
            .frame(minHeight: Space.tapTarget)
            .opacity(isSelected ? 1 : 0.53)
            .offset(x: isSelected ? 4 : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timeline-row")
        .accessibilityLabel(accessibilityLabel(session, feeling: feeling))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(_ session: Session, feeling: Int?) -> String {
        let time = session.startAt.formatted(.dateTime.hour().minute())
        let name = session.intention ?? store.activityName(session.activityId)
        let felt = feeling.map { ", felt \(Feeling.label(forRating: $0).lowercased())" } ?? ", not rated"
        return "\(time), \(name), \(formatMinutes(session.durationMinutes))\(felt)"
    }

    /// The note the user wrote, or a plain description of the session. Never a
    /// verdict on it.
    private func note(for session: Session) -> String {
        if let note = store.reflection(for: session.id)?.note ?? session.note, !note.isEmpty {
            return note
        }
        let length = formatMinutesShort(session.durationMinutes)
        guard let feeling = store.feeling(for: session.id) else {
            return "\(length). You haven't said how this one felt."
        }
        return "\(length), \(Feeling.label(forRating: feeling).lowercased())."
    }
}
