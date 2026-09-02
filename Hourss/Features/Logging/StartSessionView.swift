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

    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }

    /// Now, rounded down to the grid, so the readouts land on tidy times.
    private var nowMinutes: Double {
        let elapsed = Date().timeIntervalSince(startOfDay) / 60
        return (elapsed / Self.stepMinutes).rounded(.down) * Self.stepMinutes
    }

    /// Enough of the day has to have passed for a past slot to exist at all.
    private var canLogPast: Bool { nowMinutes >= Self.stepMinutes }

    private var latestStart: Double { max(0, nowMinutes - Self.stepMinutes) }

    /// A slot can never run past the current moment.
    private var maxDuration: Double {
        max(Self.stepMinutes, min(Self.maxDurationMinutes, nowMinutes - startMinutes))
    }

    private var slotStart: Date { startOfDay.addingTimeInterval(startMinutes * 60) }
    private var slotEnd: Date { slotStart.addingTimeInterval(durationMinutes * 60) }

    private var overlapping: [Session] {
        store.sessionsOverlapping(start: slotStart, end: slotEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Start a session", onClose: { dismiss() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    modePicker
                    if mode == .past { timeSlot }
                    activityPicker
                    intentionField
                    footnote
                }
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            footer
        }
        .surface(.canvas)
        .onAppear {
            selectedActivityId = store.pickableActivities.first?.id
            resetSlotToLastHour()
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

    /// The slot itself: a readout, then one slider for when it began and one for
    /// how long it ran.
    @ViewBuilder
    private var timeSlot: some View {
        if canLogPast {
            VStack(alignment: .leading, spacing: Space.md) {
                HRule()

                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("The slot")
                    Text("\(slotStart.formatted(.dateTime.hour().minute())) – \(slotEnd.formatted(.dateTime.hour().minute()))")
                        .textStyle(.dayNumeral)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(formatMinutes(Int(durationMinutes)))
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("Started at")
                    EditorialSlider(
                        value: $startMinutes,
                        range: 0...max(Self.stepMinutes, latestStart),
                        step: Self.stepMinutes,
                        lowLabel: startOfDay.formatted(.dateTime.hour().minute()),
                        highLabel: startOfDay.addingTimeInterval(latestStart * 60).formatted(.dateTime.hour().minute()),
                        spokenValue: { minutes in
                            startOfDay.addingTimeInterval(minutes * 60)
                                .formatted(.dateTime.hour().minute())
                        }
                    )
                    .accessibilityLabel("Start time")
                    .accessibilityIdentifier("slot-start")
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    Eyebrow("For how long")
                    EditorialSlider(
                        value: $durationMinutes,
                        range: Self.stepMinutes...maxDuration,
                        step: Self.stepMinutes,
                        lowLabel: formatMinutes(Int(Self.stepMinutes)),
                        highLabel: formatMinutes(Int(maxDuration)),
                        spokenValue: { formatMinutes(Int($0)) }
                    )
                    .accessibilityLabel("Duration")
                    .accessibilityIdentifier("slot-duration")
                }

                if let clash = overlapping.first {
                    // Not an error — the spec leaves overlapping sessions out of
                    // pattern work, so this says what will happen rather than
                    // refusing the entry.
                    Text("Overlaps \(store.activityName(clash.activityId)) — kept, but left out of patterns.")
                        .textStyle(.label)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("overlap-note")
                }

                HRule()
            }
        }
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
            HStack {
                Spacer()
                DirectionalLink(title: mode == .now ? "Start" : "Log it", arrow: "→", action: save)
                    .disabled(selectedActivityId == nil)
            }
            .pageGutter()
        }
    }

    // MARK: - Actions

    private func resetSlotToLastHour() {
        // The hour just gone is the one most likely to be missing.
        durationMinutes = min(60, max(Self.stepMinutes, nowMinutes))
        startMinutes = max(0, nowMinutes - durationMinutes)
        durationMinutes = min(durationMinutes, maxDuration)
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
