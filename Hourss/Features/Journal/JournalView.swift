import SwiftUI

/// J1 — the archive. A list of logged days with a quiet summary each, plus a
/// filter by activity. Days with no logs are simply absent rather than rendered
/// as empty cells; the record is a record, not a grid to fill in.
struct JournalView: View {
    @Environment(HourssStore.self) private var store
    @State private var activityFilter: UUID?
    @State private var selectedDay: Date?

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
        .navigationDestination(item: $selectedDay) { DayDetailView(day: $0) }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("\(store.loggedDays.count) days recorded")
                .padding(.top, Space.md)

            HeatCalendar(feelingByDay: store.meanFeelingByDay) { day in
                selectedDay = day
            }
            .padding(.vertical, Space.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                UnderlinePicker(
                    options: [(nil, "All")] + store.pickableActivities.map { (Optional($0.id), $0.name) },
                    selection: $activityFilter,
                    identifierPrefix: "filter"
                )
                .padding(.vertical, Space.xs)
            }
            .scrollClipDisabled()

            HRule()
        }
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
                SegmentStrip(segments: sessions.map { session in
                    SegmentStrip.Segment(
                        id: session.id,
                        weight: Double(max(1, session.durationMinutes)),
                        color: store.feeling(for: session.id).map(Feeling.fillColor(forRating:))
                            ?? Color.ink.opacity(0.1)
                    )
                })
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
