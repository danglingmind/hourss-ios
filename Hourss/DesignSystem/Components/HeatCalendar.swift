import SwiftUI

/// Six weeks of days, one square each, coloured by how that day felt.
///
/// The PRD asks J1 for "calendar heat / list of days"; this is the heat half.
/// Built as a grid of rectangles rather than a `Canvas`: 42 views costs nothing,
/// and the grid gives hit-testing and per-day VoiceOver for free, both of which a
/// `Canvas` would need rebuilt by hand.
struct HeatCalendar: View {
    /// Mean feeling 1–5 per day. A missing day is unlogged, not zero.
    let feelingByDay: [Date: Double]
    let onSelect: (Date) -> Void

    var weeks: Int = 6

    @Environment(\.surface) private var surface

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: 3) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .textStyle(.label)
                        .foregroundStyle(surface.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let mean = feelingByDay[calendar.startOfDay(for: day)]
        let isFuture = day > Date()

        return Button {
            if mean != nil { onSelect(day) }
        } label: {
            Rectangle()
                .fill(fill(for: mean, isFuture: isFuture))
                .aspectRatio(1, contentMode: .fit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(mean == nil)
        .accessibilityLabel(label(for: day, mean: mean))
    }

    private func fill(for mean: Double?, isFuture: Bool) -> Color {
        if isFuture { return .clear }
        guard let mean else { return Color.ink.opacity(0.06) }
        return Feeling.fillColor(forRating: Int(mean.rounded()))
    }

    private func label(for day: Date, mean: Double?) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard let mean else { return "\(date), nothing logged" }
        return "\(date), felt \(Feeling.label(forRating: Int(mean.rounded())).lowercased())"
    }

    /// The grid runs whole weeks so columns line up under their weekday, starting
    /// on the user's own first day of the week.
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: today),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start
        else { return [] }

        var result: [Date] = []
        var cursor = weekStart
        while cursor <= endOfCurrentWeek {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var endOfCurrentWeek: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.dateInterval(of: .weekOfYear, for: today).map {
            calendar.date(byAdding: .day, value: -1, to: $0.end) ?? today
        } ?? today
    }

    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
