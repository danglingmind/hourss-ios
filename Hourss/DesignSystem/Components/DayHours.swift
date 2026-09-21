import SwiftUI

/// Twenty-four cells, one per hour, filled where the day has something in it.
///
/// **What this is for.** The timeline beneath it is a list: it says what happened
/// and in what order, and answers "when" only by making you read every row's
/// clock. The question this answers instead is the one a list is worst at —
/// *which hours of my day are actually accounted for* — and it answers it without
/// being read, because an unlogged hour is a gap you can see from across the room.
///
/// **Why this is not `SegmentStrip`.** That mark packs sessions end to end in
/// proportion to their length, which makes a shape of the day but carries no
/// clock position at all: three hours logged at 09:00 and three logged at 21:00
/// draw identically. Here position *is* the information, so the axis is fixed at
/// midnight-to-midnight and the gaps are real.
///
/// **Why hours rather than a continuous track.** At phone width a day is about
/// 340 points, so a 25-minute session on a continuous scale is six points wide and
/// reads as a speck or as nothing. Rounding to the hour makes the shortest thing
/// anybody logs still visible, and "which hour" is the resolution the question is
/// asked at anyway.
struct DayHours: View {
    let sessions: [Session]
    /// Start of the day being drawn. Passed rather than derived, because a
    /// session imported from Health can begin the evening before the day it is
    /// filed under and there would be nothing to clamp it against.
    let day: Date
    /// How each session felt, 1–5, or nil where it was never rated.
    let feeling: (Session) -> Int?
    /// What to call a session out loud. Supplied rather than read, because the
    /// activity list lives on the store and this is a design-system view.
    let name: (Session) -> String
    /// A filled hour was tapped. Selects that session in the list beneath, so the
    /// strip and the rows are two views of one thing rather than two controls.
    var onSelect: (Session) -> Void = { _ in }
    /// An empty hour was tapped, and it carries the hour's start.
    var onFill: (Date) -> Void = { _ in }

    /// Matched to `DataBar.reading`, the height of the energy bar on every row
    /// below. The strip is the same measurement at the scale of a day, and a
    /// different weight would have said otherwise.
    var height: CGFloat = DataBar.reading

    @Environment(\.surface) private var surface

    private static let hours = 24

    /// Room above the band for the moving time, whether or not there is one to
    /// show — reserved unconditionally so a day in the Journal and today do not
    /// sit at different heights in the same scroll view.
    private static let markHeight: CGFloat = 15
    private static let markGap: CGFloat = 3
    /// Roughly what "10:16 AM" occupies at 11pt mono. Used only to keep the
    /// label from running off either end — never to centre it, which a zero-width
    /// frame does exactly regardless of how many characters the time has.
    private static let markWidth: CGFloat = 62
    /// How far the now line stands proud of the band, top and bottom.
    private static let nowOverhang: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: Self.markGap) {
                    nowMark(width: geo.size.width)
                    band(width: geo.size.width)
                }
            }
            .frame(height: Self.markHeight + Self.markGap + height)

            axis
        }
    }

    // MARK: - The band

    private func band(width: CGFloat) -> some View {
        // No spacing between cells: one continuous band, so three hours logged in
        // a row read as one block of time rather than three tallies of it. The
        // hour boundaries come back as rules drawn over the top, which divide the
        // day without breaking it into pieces.
        HStack(spacing: 0) {
            ForEach(0..<Self.hours, id: \.self) { hour in
                cell(hour)
            }
        }
        .frame(height: height)
        .overlay { hourTicks }
        .overlay(alignment: .leading) { nowLine(width: width) }
    }

    /// A hairline at every hour boundary except the two ends.
    ///
    /// Twenty-three of them, so the five between 00 and 06 are countable and an
    /// hour can be aimed at rather than guessed at. Ink rather than the canvas
    /// colour: a gap-coloured tick would read as the band being cut up again,
    /// which is the thing the continuous band was for.
    private var hourTicks: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.hours, id: \.self) { hour in
                Rectangle()
                    .fill(.clear)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        if hour > 0 {
                            Rectangle()
                                .fill(Color.ink.opacity(0.14))
                                .frame(width: 1)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Now

    /// Where in the day this moment sits, or nil on any day but today.
    private func nowFraction(at date: Date) -> Double? {
        guard Calendar.current.isDate(day, inSameDayAs: date) else { return nil }
        let elapsed = date.timeIntervalSince(day) / (TimeInterval(Self.hours) * 3600)
        return min(1, max(0, elapsed))
    }

    /// The bold line, standing taller than the band it crosses.
    ///
    /// The overhang is not decoration. `Color.orange` is #E65837 and
    /// `Color.drainingFill` is #E66645 — near enough the same hue that a draining
    /// session and this marker are one colour at a glance, and an hour block is
    /// exactly the band's height. Running a few points past both edges makes it
    /// a line laid across the day rather than another thing logged in it, which
    /// is a difference of shape and survives the colours being close.
    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.periodic(from: day, by: 60)) { context in
            if let fraction = nowFraction(at: context.date) {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2, height: height + Self.nowOverhang * 2)
                    .offset(x: fraction * width - 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The clock, above the line and travelling with it.
    ///
    /// Clamped at both ends: near midnight the label would otherwise hang off the
    /// edge of the strip, and a time you cannot read is worse than one that has
    /// stopped tracking for the last few points of the day.
    private func nowMark(width: CGFloat) -> some View {
        TimelineView(.periodic(from: day, by: 60)) { context in
            ZStack(alignment: .leading) {
                Color.clear
                if let fraction = nowFraction(at: context.date) {
                    Text(context.date.formatted(.dateTime.hour().minute()))
                        .textStyle(.label)
                        .foregroundStyle(Color.orange)
                        .fixedSize()
                        // Zero width, so the text centres itself on the line and
                        // overflows both ways. Guessing the string's width put
                        // "5:13 PM" fifteen points left of the line it belongs to.
                        .frame(width: 0)
                        .offset(x: min(max(Self.markWidth / 2, fraction * width),
                                       max(Self.markWidth / 2, width - Self.markWidth / 2)))
                        .accessibilityLabel("Now, \(context.date.formatted(.dateTime.hour().minute()))")
                }
            }
        }
        .frame(height: Self.markHeight)
    }

    private func cell(_ hour: Int) -> some View {
        Button {
            if let session = session(inHour: hour) {
                onSelect(session)
            } else {
                onFill(start(ofHour: hour))
            }
        } label: {
            Rectangle()
                .fill(color(forHour: hour))
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                // Cells are flush, so there is no dead ground between two hours
                // to miss into. The target is the band itself: about 14 × 30pt,
                // which is under the 44pt this system asks for and is the known
                // cost of putting a whole day on one row. Nothing here pads it
                // out — an earlier version of this comment claimed it did, which
                // was not true and is the kind of claim that stops anybody
                // checking. Widening it means fewer hours or a drag gesture, and
                // a drag loses the per-hour VoiceOver labels below.
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel(forHour: hour))
    }

    /// Five marks: the four quarters, and the end of the day.
    ///
    /// Each of the first four takes a quarter of the width and is leading-aligned,
    /// which puts 06 at 25%, 12 at 50% and 18 at 75% — exactly where those hours
    /// begin. 24 is the right-hand edge rather than the start of anything, so it
    /// is laid over the trailing end instead of taking a share of the row.
    private var axis: some View {
        HStack(spacing: 0) {
            ForEach(["00", "06", "12", "18"], id: \.self) { mark in
                Text(mark)
                    .textStyle(.label)
                    .foregroundStyle(surface.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .trailing) {
            Text("24")
                .textStyle(.label)
                .foregroundStyle(surface.tertiary)
        }
        .accessibilityHidden(true)
    }

    private func start(ofHour hour: Int) -> Date {
        day.addingTimeInterval(TimeInterval(hour) * 3600)
    }

    // MARK: - Filling

    /// Which session gives this hour its colour.
    ///
    /// Something logged always beats sleep read from a watch, however little of
    /// the hour it took. A night covers seven or eight hours of most days, so
    /// ranking purely by overlap would bury every early-morning session under it —
    /// a half-hour of work at six in the morning is the single most interesting
    /// thing that strip could tell somebody, and it would be the one thing it hid.
    /// Sleep is the ground the day sits on rather than a thing done in it, which
    /// is the same reason nothing else in the app asks how a night felt.
    ///
    /// Below that, the larger share of the hour wins, and ties resolve to the
    /// earlier start so the strip is identical between runs.
    private func session(inHour hour: Int) -> Session? {
        let hourStart = day.addingTimeInterval(TimeInterval(hour) * 3600)
        let hourEnd = hourStart.addingTimeInterval(3600)

        return sessions
            .compactMap { session -> (session: Session, overlap: TimeInterval)? in
                let overlap = overlap(of: session, from: hourStart, to: hourEnd)
                return overlap > 0 ? (session, overlap) : nil
            }
            .min { a, b in
                let aSleep = a.session.healthKind == .sleep
                let bSleep = b.session.healthKind == .sleep
                if aSleep != bSleep { return !aSleep }
                if a.overlap != b.overlap { return a.overlap > b.overlap }
                return a.session.startAt < b.session.startAt
            }?
            .session
    }

    /// Seconds of `session` that fall inside the window, after clamping the
    /// session to the day it is filed under.
    ///
    /// The clamp is not defensive tidying. A night read from Health is attributed
    /// to the morning it ended on, so it genuinely starts before this day began,
    /// and an unclamped span would claim hours that belong to yesterday.
    private func overlap(of session: Session, from windowStart: Date, to windowEnd: Date) -> TimeInterval {
        let dayEnd = day.addingTimeInterval(TimeInterval(Self.hours) * 3600)
        let start = max(session.startAt, day)
        let end = min(session.startAt.addingTimeInterval(TimeInterval(session.durationSeconds)), dayEnd)
        guard end > start else { return 0 }

        return max(0, min(end, windowEnd).timeIntervalSince(max(start, windowStart)))
    }

    /// Three states, and they have to stay three.
    ///
    /// An hour that was logged but never rated must not fall back to the empty
    /// track the way a `DataBar` does — here that would make "I did something and
    /// said nothing about it" and "I did nothing" the same mark, which is the one
    /// distinction this whole strip exists to draw. So unrated takes the rule
    /// colour: plainly filled, plainly not a feeling.
    private func color(forHour hour: Int) -> Color {
        guard let session = session(inHour: hour) else { return surface.track }
        guard let rating = feeling(session) else { return surface.ruleColor }
        return Feeling.fillColor(forRating: rating)
    }

    // MARK: - Spoken

    /// What one hour says when it is reached.
    ///
    /// Per hour rather than one summary for the strip, because each hour is now a
    /// control and a summary would name twenty-four things while offering one
    /// action. The name of what is in the hour has to be here: an hour that is
    /// only ever distinguished by its fill is distinguished by colour alone.
    private func spokenLabel(forHour hour: Int) -> String {
        let time = clock(hour)
        guard let session = session(inHour: hour) else {
            return "\(time), nothing logged. Log this hour."
        }
        let title = session.intention ?? name(session)
        guard let rating = feeling(session) else {
            return "\(time), \(title), not rated."
        }
        return "\(time), \(title), felt \(Feeling.label(forRating: rating).lowercased())."
    }

    private func clock(_ hour: Int) -> String {
        start(ofHour: hour).formatted(.dateTime.hour().minute())
    }
}
