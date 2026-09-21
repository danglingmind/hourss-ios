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
            // Named before counted, like every other figure in the app. Same
            // words, and no size hierarchy to fix here — an eyebrow sets its
            // number at the same 11pt as its noun, so the flip is about the
            // reading order alone.
            Eyebrow("Days recorded · \(store.loggedDays.count)")
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

/// One day, summarised: the date, a compact strip of the day's feelings so the
/// shape of it reads at a glance, then what was done and how long it took.
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

                // What was done, then how long it took — the reverse of the old
                // "1h 30m · Running, Yoga", where the first thing in the row's
                // only sentence was a duration belonging to nothing named yet.
                //
                // Two texts rather than one interpolation so the names can
                // truncate without taking the total with them: the total is the
                // shorter half and the one a single line can always afford. This
                // is the same left-subject / right-figure idiom the coverage rows
                // on Patterns use, which is why it is not a `TitledFigure` — the
                // row's own subject is the date at the head of it, and a second
                // 34pt title inside a list row would compete with it.
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(summary.names)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                    Spacer(minLength: Space.xs)
                    Text(summary.total)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.tapTarget)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(day.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(summary.spoken)"
        )
    }

    private var summary: DaySummaryLine {
        DaySummaryLine(
            activityNames: sessions.map { store.activityName($0.activityId) },
            minutes: sessions.reduce(0) { $0 + $1.durationMinutes }
        )
    }
}

/// The two halves of a day row's summary, in reading order.
///
/// A value rather than one interpolated string because the order is the point: a
/// row that opens with "1h 30m" has put a figure in front of everything that
/// would explain it, and a test can only hold that line if the halves are
/// separable. Both halves are drawn from what is already on the row — activity
/// names and a duration — so no new copy exists here to phrase wrongly.
struct DaySummaryLine: Equatable {
    /// Up to three distinct activity names, alphabetical.
    let names: String
    /// The day's logged total.
    let total: String

    init(activityNames: [String], minutes: Int) {
        names = Set(activityNames).sorted().prefix(3).joined(separator: ", ")
        total = formatMinutesShort(minutes)
    }

    /// Subject before figure, the same way the row is laid out.
    var spoken: String { "\(names), \(total)" }
}
