import SwiftUI

/// L3 — the end-of-session reflection.
///
/// Feeling saves the moment it is tapped, performance is optional and never
/// blocks the save, and a note is never required. Nothing here defaults to a
/// middle value: an unanswered scale stays unanswered.
struct ReflectionView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID

    @State private var feeling: Int?
    @State private var performance: Int?
    @State private var note = ""

    private var session: Session? { store.sessions.first { $0.id == sessionId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Reflection", onClose: { save(); dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let session {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.activityName(session.activityId)).textStyle(.stepName)
                            Text("\(session.startAt.formatted(.dateTime.hour().minute())) · \(formatMinutes(session.durationMinutes))")
                                .textStyle(.label)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    HRule()

                    RatingScale(value: $feeling, kind: .feeling)

                    // Performance stays on screen rather than behind a disclosure.
                    // It is still optional — nothing is preselected and the save
                    // path does not care whether it was answered.
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HRule()
                        RatingScale(
                            value: $performance,
                            kind: .performance,
                            caption: "Optional — how it went and how it felt aren't the same thing."
                        )
                        .padding(.top, Space.xs)
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("A note — optional")
                        TextField("Anything worth remembering?", text: $note, axis: .vertical)
                            .textStyle(.bodyLarge)
                            .tint(.orange)
                            .padding(.vertical, Space.sm)
                            .overlay(alignment: .bottom) { HRule(color: .ink) }
                    }
                }
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            VStack(spacing: 0) {
                HRule()
                HStack {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .foregroundStyle(Color.muted)
                        .frame(minHeight: Space.tapTarget)
                    Spacer()
                    DirectionalLink(title: "Save", arrow: "→") { save(); dismiss() }
                }
                .pageGutter()
            }
        }
        .surface(.canvas)
        .onAppear {
            if let existing = store.reflection(for: sessionId) {
                feeling = existing.feelingScore
                performance = existing.performanceScore
                note = existing.note ?? ""
            }
        }
    }

    private func save() {
        store.saveReflection(sessionId: sessionId, feeling: feeling, performance: performance, note: note)
    }
}
