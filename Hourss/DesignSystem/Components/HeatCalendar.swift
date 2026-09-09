import SwiftUI

/// A month, one square per day, coloured by how that day felt.
///
/// This was six rolling weeks ending on the current one, which looked like a
/// calendar and was not: the columns lined up under weekdays, but the squares
/// carried no dates and the block had no month boundaries in it, so a person
/// counting backwards to find last Tuesday had nothing to count with. It is now
/// an actual month — the first lands under its real weekday, every square says
/// which day it is, and the months either side are a tap away.
///
/// The heat is unchanged. A day's fill still says how it felt, which is the only
/// thing this component was ever really for.
///
/// Built from rectangles rather than a `Canvas`: forty-odd views cost nothing,
/// and the grid gives hit-testing and per-day VoiceOver for free, both of which a
/// `Canvas` would need rebuilt by hand.
struct HeatCalendar: View {
    /// Mean feeling 1–5 per day. A missing day is unlogged, not zero.
    let feelingByDay: [Date: Double]
    let onSelect: (Date) -> Void

    @Environment(\.surface) private var surface
    @State private var month: Date = Calendar.current.startOfMonth(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            header

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
                // Leading blanks so the first of the month sits under its own
                // weekday. Without them the grid is a list wearing seven columns.
                ForEach(0..<leadingBlanks, id: \.self) { index in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityHidden(true)
                        .id("blank-\(index)")
                }
                ForEach(daysInMonth, id: \.self) { day in
                    dayCell(day)
                }
            }
            .animation(.easeInOut(duration: Motion.standard), value: month)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            monthStep(-1, arrow: "←", label: "Previous month")
            Spacer(minLength: Space.sm)
            Text(month.formatted(.dateTime.month(.wide).year()))
                .textStyle(.stepName)
                .foregroundStyle(surface.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.sm)
            // Forward stops at the current month. There is nothing to show in a
            // month that has not happened, and letting somebody page into empty
            // grids implies the record might be there.
            monthStep(1, arrow: "→", label: "Next month")
                .disabled(isShowingCurrentMonth)
                .opacity(isShowingCurrentMonth ? 0.25 : 1)
        }
        .padding(.bottom, Space.xs)
    }

    private func monthStep(_ delta: Int, arrow: String, label: String) -> some View {
        Button {
            guard let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
            month = calendar.startOfMonth(for: next)
        } label: {
            Text(arrow)
                .textStyle(.action)
                .foregroundStyle(surface.foreground)
                .frame(width: 44, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(delta < 0 ? "calendar-previous" : "calendar-next")
    }

    // MARK: - Cells

    private func dayCell(_ day: Date) -> some View {
        let mean = feelingByDay[calendar.startOfDay(for: day)]
        let isFuture = day > calendar.startOfDay(for: Date())
        let isToday = calendar.isDateInToday(day)

        return Button {
            if mean != nil { onSelect(day) }
        } label: {
            ZStack {
                Rectangle().fill(fill(for: mean, isFuture: isFuture))
                Text("\(calendar.component(.day, from: day))")
                    .textStyle(.dayNumeral)
                    .foregroundStyle(numeral(for: mean, isFuture: isFuture))
                // Today is marked by a rule under the numeral rather than a ring:
                // the design system has no corner radius, and a square ring around
                // a square cell reads as a second cell.
                if isToday {
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(surface.foreground)
                            .frame(height: 1.5)
                            .padding(.horizontal, 5)
                            .padding(.bottom, 3)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(mean == nil)
        .accessibilityLabel(label(for: day, mean: mean))
        .accessibilityAddTraits(isToday ? [.isButton, .isSelected] : .isButton)
    }

    private func fill(for mean: Double?, isFuture: Bool) -> Color {
        if isFuture { return .clear }
        guard let mean else { return Color.ink.opacity(0.06) }
        return Feeling.fillColor(forRating: Int(mean.rounded()))
    }

    /// Numeral colour, chosen against the fill rather than assumed.
    ///
    /// Every feeling fill in the palette is light — lime, sage and the draining
    /// orange all sit well above ink — so a logged day takes ink. That is a real
    /// dependency on the palette rather than a coincidence: if a darker fill is
    /// ever added, this needs a case, or the numerals on it disappear the way the
    /// running activity name once did on dark green.
    private func numeral(for mean: Double?, isFuture: Bool) -> Color {
        if isFuture { return surface.tertiary.opacity(0.4) }
        return mean == nil ? surface.tertiary : .ink
    }

    private func label(for day: Date, mean: Double?) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let today = calendar.isDateInToday(day) ? "Today, " : ""
        guard let mean else { return "\(today)\(date), nothing logged" }
        return "\(today)\(date), felt \(Feeling.label(forRating: Int(mean.rounded())).lowercased())"
    }

    // MARK: - The month

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// How far the first of the month sits from the start of its week, in the
    /// person's own first-day-of-week.
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private var weekdayInitials: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

extension Calendar {
    /// Midnight on the first of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
