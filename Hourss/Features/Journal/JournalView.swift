import SwiftUI

/// J1 — the archive. A list of logged days with a quiet summary each, plus a
/// filter by activity. Days with no logs are simply absent rather than rendered
/// as empty cells; the record is a record, not a grid to fill in.
struct JournalView: View {
    @Environment(HourssStore.self) private var store
    @State private var activityFilter: UUID?

    private var days: [Date] {
        store.loggedDays.filter { day in
            guard let filter = activityFilter else { return true }
            return store.sessions(on: day).contains { $0.activityId == filter }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                filters

                ForEach(days, id: \.self) { day in
                    NavigationLink(value: day) {
                        DayRow(day: day, activityFilter: activityFilter)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("day-\(day.timeIntervalSince1970)")
                    HRule()
                }

                if days.isEmpty {
                    Text("Nothing logged under this filter yet.")
                        .textStyle(.body)
                        .foregroundStyle(Color.muted)
                        .padding(.vertical, Space.lg)
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Journal")
        }
        .navigationDestination(for: Date.self) { DayDetailView(day: $0) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("\(store.loggedDays.count) days recorded")
                .padding(.top, Space.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.md) {
                    filterButton(title: "All", id: nil)
                    ForEach(store.pickableActivities) { activity in
                        filterButton(title: activity.name, id: activity.id)
                    }
                }
                .padding(.vertical, Space.xs)
            }
            .scrollClipDisabled()

            HRule()
        }
    }

    private func filterButton(title: String, id: UUID?) -> some View {
        let isSelected = activityFilter == id
        return Button {
            activityFilter = id
        } label: {
            Text(title)
                .textStyle(.action)
                .foregroundStyle(isSelected ? Color.ink : Color.muted)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? Color.orange : .clear)
                        .frame(height: 2)
                        .offset(y: 6)
                }
                .frame(minHeight: Space.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// One day, summarised: the date, the total, and a compact strip of the day's
/// feelings so the shape of it reads at a glance.
private struct DayRow: View {
    @Environment(HourssStore.self) private var store
    let day: Date
    let activityFilter: UUID?

    private var sessions: [Session] { store.sessions(on: day) }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.day().month(.abbreviated)))
                    .textStyle(.stepName)
                    .lineLimit(1)
                    .fixedSize()
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: Space.xs) {
                GeometryReader { geo in
                    let gaps = CGFloat(max(0, sessions.count - 1)) * 2
                    let available = max(0, geo.size.width - gaps)
                    let total = max(1, sessions.reduce(0) { $0 + max(1, $1.durationMinutes) })
                    HStack(spacing: 2) {
                        ForEach(sessions) { session in
                            Rectangle()
                                .fill(store.feeling(for: session.id).map(Feeling.fillColor(forRating:)) ?? Color.ink.opacity(0.1))
                                .frame(width: available * CGFloat(max(1, session.durationMinutes)) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 18)
                Text(summary)
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.tapTarget)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(summary)")
    }

    private var summary: String {
        let total = formatMinutesShort(sessions.reduce(0) { $0 + $1.durationMinutes })
        let names = Set(sessions.map { store.activityName($0.activityId) })
            .sorted()
            .prefix(3)
            .joined(separator: ", ")
        return "\(total) · \(names)"
    }
}
