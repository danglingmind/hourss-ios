import SwiftUI

/// L1 and L2 in one sheet — start a session now, or record an hour that already
/// happened.
///
/// Backdating matters because the honest case is the common one: you were busy,
/// so you did not log it while it was happening. Forcing everything through a live
/// timer would quietly bias the record toward the hours calm enough to remember.
struct StartSessionView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Mode: Hashable { case now, past }

    @State private var mode: Mode = .now
    @State private var selectedActivityId: UUID?
    @State private var intention = ""

    /// Minutes from the start of today. The sliders work in minutes so both can
    /// snap to the same quarter-hour grid.
    @State private var startMinutes: Double = 0
    @State private var durationMinutes: Double = 60

    private static let stepMinutes: Double = 15
    /// The spec's upper bound on a valid session.
    private static let maxDurationMinutes: Double = 16 * 60

    /// The slot's origin, which is not midnight.
    ///
    /// It used to be. That confined a past slot to the calendar day, so in the
    /// first hour after midnight there was no room behind you to put one: at
    /// half past twelve the longest slot available was thirty minutes, and the
    /// session that ended at ten to midnight could not be recorded at all. The
    /// day boundary is a property of the calendar, not of when somebody stopped
    /// working, and the sheet had no business enforcing it.
    ///
    /// The window now runs back a full sixteen hours — the spec's own longest
    /// valid session — so the slot can reach across midnight and the arithmetic
    /// below stops depending on what time it happens to be.
    private var windowStart: Date {
        Date().addingTimeInterval(-Self.maxDurationMinutes * 60)
    }

    /// Now, rounded down to the grid, so the readouts land on tidy times.
    private var nowMinutes: Double {
        let elapsed = Date().timeIntervalSince(windowStart) / 60
        return (elapsed / Self.stepMinutes).rounded(.down) * Self.stepMinutes
    }

    /// Enough time has to sit behind the moment for a past slot to exist at all.
    private var canLogPast: Bool { nowMinutes >= Self.stepMinutes }

    private var latestStart: Double { max(0, nowMinutes - Self.stepMinutes) }

    /// A slot can never run past the current moment.
    private var maxDuration: Double {
        max(Self.stepMinutes, min(Self.maxDurationMinutes, nowMinutes - startMinutes))
    }

    private var slotStart: Date { windowStart.addingTimeInterval(startMinutes * 60) }
    private var slotEnd: Date { slotStart.addingTimeInterval(durationMinutes * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Start a session", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    modePicker
                    // The whole slot arrives or leaves when the mode changes, and
                    // everything under it moves to make room. Without this the
                    // sliders simply blinked into existence and the activity list
                    // jumped down the screen.
                    if mode == .past { timeSlot }
                    activityPicker
                    intentionField
                    footnote
                }
                .animation(Motion.content(reduced: reduceMotion), value: mode)
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            footer
        }
        .surface(.canvas)
        .onAppear {
            selectedActivityId = store.pickableActivities.first?.id
            resetSlotToLastHour()
            adoptPendingSlot()
        }
        .onChange(of: startMinutes) { _, _ in
            // Shortening the window from the left must not leave a slot that ends
            // in the future.
            durationMinutes = min(durationMinutes, maxDuration)
        }
    }

    // MARK: - Sections

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            UnderlinePicker(
                options: [(Mode.now, "Start now"), (Mode.past, "Log past time")],
                selection: $mode,
                identifierPrefix: "mode"
            )
            .disabled(!canLogPast && mode == .now)

            if !canLogPast {
                Text("Not much of today behind you yet.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    /// The slot: what to do about the hour just gone, or the day itself.
    ///
    /// Two ways in, because there are two cases and they are not the same size.
    /// The common one is the reason backdating exists at all — you were busy, so
    /// you did not log it while it was happening — and it is always the same
    /// shape: something that ended just now and ran for about so long. That is one
    /// tap. The other case is a gap from this morning, and for that you point at
    /// the day.
    @ViewBuilder
    private var timeSlot: some View {
        if canLogPast {
            VStack(alignment: .leading, spacing: Space.md) {
                HRule()

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("Just finished")
                    HStack(spacing: Space.xs) {
                        ForEach(Self.presets, id: \.self) { minutes in
                            presetChip(minutes)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("Or pick it on the day")
                    SlotPicker(
                        day: calendarDay,
                        logged: loggedSpans,
                        now: Date(),
                        start: Binding(get: { slotStart }, set: { moveSlot(start: $0) }),
                        end: Binding(get: { slotEnd }, set: { moveSlot(end: $0) })
                    )
                    .accessibilityIdentifier("slot-picker")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(slotStart.formatted(.dateTime.hour().minute())) – \(slotEnd.formatted(.dateTime.hour().minute()))")
                        .textStyle(.dayNumeral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(formatMinutes(Int(durationMinutes)))
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }

                HRule()
            }
        }
    }

    /// Lengths somebody actually reports having just finished. Anything else is
    /// what the strip is for.
    private static let presets = [30, 60, 90, 120]

    private func presetChip(_ minutes: Int) -> some View {
        // Selected when the slot already says exactly this: ending now, running
        // that long. So tapping one and then nudging the strip drops the
        // selection, which is correct — the chip is a shortcut to a slot, not a
        // mode the sheet is in.
        let isSelected = Int(durationMinutes) == minutes
            && abs(slotEnd.timeIntervalSince(nowOnGrid)) < 60

        return Button {
            setPreset(minutes)
        } label: {
            Text(formatMinutes(minutes))
                .textStyle(.action)
                .foregroundStyle(isSelected ? Color.ink : Color.muted)
                .frame(maxWidth: .infinity)
                .frame(height: Space.tapTarget)
                .background(isSelected ? Color.lime : Color.ink.opacity(0.05))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preset-\(minutes)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Now, snapped to the grid the slot works in.
    private var nowOnGrid: Date {
        windowStart.addingTimeInterval(nowMinutes * 60)
    }

    private var calendarDay: Date {
        Calendar.current.startOfDay(for: slotStart)
    }

    /// Everything already on the day being drawn, as spans.
    ///
    /// Read from the record rather than from the overlap check, because the point
    /// is to show what is there before anybody aims at it — the old note appeared
    /// only once a slot had already been dragged on top of something.
    private var loggedSpans: [DateInterval] {
        store.sessions(on: calendarDay).compactMap { session in
            guard let end = session.endAt, end > session.startAt else { return nil }
            return DateInterval(start: session.startAt, end: end)
        }
    }

    /// The last `minutes` before now, which is what "just finished" means.
    private func setPreset(_ minutes: Int) {
        durationMinutes = min(Double(minutes), Self.maxDurationMinutes)
        startMinutes = max(0, nowMinutes - durationMinutes)
        durationMinutes = min(durationMinutes, maxDuration)
    }

    /// The strip hands back dates; the sheet stores minutes from `windowStart`.
    private func moveSlot(start newStart: Date? = nil, end newEnd: Date? = nil) {
        let from = newStart ?? slotStart
        let to = newEnd ?? slotEnd
        guard to > from else { return }
        startMinutes = max(0, from.timeIntervalSince(windowStart) / 60)
        durationMinutes = max(Self.stepMinutes, to.timeIntervalSince(from) / 60)
    }

    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow(mode == .now ? "What are you doing with this hour?" : "What filled that time?")
            VStack(spacing: 0) {
                HRule()
                ForEach(store.pickableActivities) { activity in
                    SelectableChip(
                        title: activity.name,
                        isSelected: selectedActivityId == activity.id,
                        glyph: .forActivity(named: activity.name)
                    ) {
                        selectedActivityId = activity.id
                    }
                }
            }
        }
    }

    private var intentionField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Intention — optional")
            TextField(
                mode == .now ? "What would make this hour worth it?" : "What were you hoping to get to?",
                text: $intention,
                axis: .vertical
            )
            .textStyle(.bodyLarge)
            .tint(.orange)
            .padding(.vertical, Space.sm)
            .overlay(alignment: .bottom) { HRule(color: .ink) }
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if mode == .now, let running = store.runningSession {
            // There is no concurrent-session concept, so be explicit about what
            // starting another one does to the one already going.
            Text("Starting this closes out \(store.activityName(running.activityId)), running since \(running.startAt.formatted(.dateTime.hour().minute())).")
                .textStyle(.label)
                .foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("replaces-running-note")
        } else {
            Text(
                mode == .now
                    ? "Starts now — \(Date().formatted(.dateTime.hour().minute()))."
                    : "Already finished — we'll ask how it felt."
            )
            .textStyle(.label)
            .foregroundStyle(Color.muted)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HRule()
            PrimaryAction(title: mode == .now ? "Start" : "Log it", action: save)
                .disabled(selectedActivityId == nil)
                .pageGutter()
                .padding(.vertical, Space.xs)
        }
    }

    // MARK: - Actions

    private func resetSlotToLastHour() {
        // The hour just gone is the one most likely to be missing.
        durationMinutes = min(60, max(Self.stepMinutes, nowMinutes))
        startMinutes = max(0, nowMinutes - durationMinutes)
        durationMinutes = min(durationMinutes, maxDuration)
    }

    /// Takes up an empty hour somebody tapped in a day's hour strip.
    ///
    /// The tap already said both things this sheet opens by asking: that the time
    /// has passed, and which hour it was. So the mode switches itself and the
    /// slot lands on that hour rather than on the generic last-hour default.
    ///
    /// The hour can be out of reach. `windowStart` runs back sixteen hours — the
    /// longest session the spec allows — so an hour tapped on a day further back
    /// than that in the Journal cannot be expressed by these sliders at all. The
    /// mode still changes, because the tap still meant "this already happened",
    /// and the slot stays where `resetSlotToLastHour` left it rather than being
    /// clamped to a boundary that would read as a real answer.
    private func adoptPendingSlot() {
        guard let slot = store.pendingLogSlot else { return }
        store.consumeLogSlot()

        guard canLogPast else { return }
        mode = .past

        let offset = slot.timeIntervalSince(windowStart) / 60
        guard offset >= 0, offset <= latestStart else { return }

        startMinutes = (offset / Self.stepMinutes).rounded() * Self.stepMinutes
        durationMinutes = min(60, maxDuration)
    }

    private func save() {
        guard let id = selectedActivityId else { return }
        let trimmed = intention.isEmpty ? nil : intention

        switch mode {
        case .now:
            store.startSession(activityId: id, intention: trimmed)
        case .past:
            store.logPastSession(activityId: id, startAt: slotStart, endAt: slotEnd, intention: trimmed)
        }
        dismiss()
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
