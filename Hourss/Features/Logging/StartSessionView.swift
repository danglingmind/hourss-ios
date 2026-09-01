import SwiftUI

/// L1 — start a session. Favourites first, an optional intention, and a start
/// time that defaults to now.
struct StartSessionView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedActivityId: UUID?
    @State private var intention = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Start a session", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("What are you doing with this hour?")
                        VStack(spacing: 0) {
                            HRule()
                            ForEach(store.pickableActivities) { activity in
                                SelectableChip(
                                    title: activity.name,
                                    isSelected: selectedActivityId == activity.id
                                ) {
                                    selectedActivityId = activity.id
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("Intention — optional")
                        TextField("What would make this hour worth it?", text: $intention, axis: .vertical)
                            .textStyle(.bodyLarge)
                            .tint(.orange)
                            .padding(.vertical, Space.sm)
                            .overlay(alignment: .bottom) { HRule(color: .ink) }
                    }

                    Text("Starts now — \(Date().formatted(.dateTime.hour().minute())).")
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            footer
        }
        .surface(.canvas)
        .onAppear { selectedActivityId = store.pickableActivities.first?.id }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HRule()
            HStack {
                Spacer()
                DirectionalLink(title: "Start", arrow: "→") {
                    guard let id = selectedActivityId else { return }
                    store.startSession(activityId: id, intention: intention.isEmpty ? nil : intention)
                    dismiss()
                }
                .disabled(selectedActivityId == nil)
            }
            .pageGutter()
        }
    }
}

/// Sheets get a rule and a plain text close, not a grabber-and-capsule chrome.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow(title)
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .textStyle(.action)
                    .foregroundStyle(Color.muted)
                    .frame(minHeight: Space.tapTarget)
            }
            .pageGutter()
            .padding(.top, Space.sm)
            HRule()
        }
    }
}
