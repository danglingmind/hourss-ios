import SwiftUI

/// J2 — one day in full. The same timeline component Today uses, so a past day and
/// the current one read identically.
struct DayDetailView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @State private var selectedSessionId: UUID?

    private var sessions: [Session] { store.sessions(on: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.wide))).textStyle(.dayNumeral)
                    Text(day.formatted(.dateTime.day().month(.wide)))
                        .textStyle(.dayNumeral)
                        .foregroundStyle(Color.muted)
                    Text(daySummary(minutes: store.totalLoggedMinutes(on: day), sessionCount: sessions.count))
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .padding(.top, Space.xs)
                }
                .padding(.top, Space.md)

                DayTimeline(sessions: sessions, selectedSessionId: $selectedSessionId)

                if let id = selectedSessionId, let session = sessions.first(where: { $0.id == id }) {
                    sessionActions(session)
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Text("←").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                            Text("Journal").textStyle(.action)
                        }
                        .frame(minHeight: Space.tapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("back")
                    Spacer()
                }
                .pageGutter()
                HRule()
            }
            .background(Color.canvas)
        }
        .onAppear { selectedSessionId = sessions.first?.id }
    }

    private func sessionActions(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HRule()
            HStack(spacing: Space.lg) {
                Button(store.feeling(for: session.id) == nil ? "Add how it felt" : "Edit reflection") {
                    store.pendingReflectionSessionId = session.id
                }
                .buttonStyle(.plain)
                .textStyle(.action)
                .frame(minHeight: Space.tapTarget)

                Button("Delete") {
                    store.deleteSession(session.id)
                    selectedSessionId = sessions.first?.id
                }
                .buttonStyle(.plain)
                .textStyle(.action)
                .foregroundStyle(Color.orange)
                .frame(minHeight: Space.tapTarget)
            }
        }
    }
}
