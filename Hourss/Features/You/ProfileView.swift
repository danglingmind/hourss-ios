import SwiftUI

/// Y2 — the profile, and the three settings that actually change what Hourss says.
///
/// This row was disabled for a long time on the grounds that a profile needs an
/// account. It did not: everything here is local and was local all along, and two
/// of the three controls were already wired into the engine with no way for anyone
/// to reach them. Priorities weight which observations surface first, and workdays
/// decide which side of the workday contrast a session falls on — both set once
/// during onboarding and then frozen, under a screen that promised "you can change
/// this later."
///
/// What is deliberately *not* here is week start. It is in `Profile`, it is
/// `Codable`, and nothing reads it — so a control for it would be a switch wired
/// to nothing, which is the one thing this settings screen must never contain.
struct ProfileView: View {
    @Environment(HourssStore.self) private var store
    /// Read for one thing: the faint fill behind a day that is not a workday. The
    /// screen is canvas, but a literal grey here would be the one block in the app
    /// that could not move to another surface with the rest.
    @Environment(\.surface) private var surface

    /// The name is edited locally and committed on the way out.
    ///
    /// Every mutation on the store rewrites the whole record to disk. That is the
    /// right trade for a session or a rating — one write per real event — but a
    /// binding straight into the profile makes it one write per keystroke, so
    /// typing a name would rewrite the file a dozen times.
    @State private var name: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([
                    Text("Your").styled(.sectionTitle),
                    Text("profile.").styled(.emphasis(42)),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                nameField

                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow("What matters most")
                    Text("Tap up to three, in order. Hourss leads with what you put first.")
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    PriorityRanker(ranked: Binding(
                        get: { store.profile.priorities },
                        set: { updated in
                            store.profile.priorities = updated
                            // The ordering weight is applied when observations are
                            // built, not when they are read, so a re-rank that only
                            // saved would leave the feed in the old order until
                            // something else happened to rebuild it.
                            store.rebuildInsights()
                            store.persist()
                        }
                    ))
                }

                workdaysField

                Text("Priorities change the order of what Hourss shows you, never what it counts as true. Workdays decide which side of a weekday comparison a session falls on.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
        .onAppear { name = store.profile.displayName }
        .onDisappear(perform: commitName)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow("Name")
            TextField("What should Hourss call you?", text: $name)
                .textStyle(.bodyLarge)
                .tint(.orange)
                .textContentType(.name)
                .submitLabel(.done)
                .onSubmit(commitName)
                .padding(.vertical, Space.sm)
                .overlay(alignment: .bottom) { HRule(color: .ink) }
                .accessibilityIdentifier("profile-name")

            Text("Only ever shown to you, on this iPhone.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    /// Seven cells, in this calendar's own week order.
    ///
    /// Not hardcoded Monday-first: `firstWeekday` is a locale answer, and a week
    /// that starts on the wrong day is the kind of small wrongness that makes a
    /// person distrust the arithmetic behind it.
    ///
    /// **The strip was a strip, and is now seven blocks.** The cells used to sit at
    /// `spacing: 0` between a rule above and a rule below, which is why they were
    /// left square when every other block took `Radius.block`: rounding a flush row
    /// notches each seam where two fills meet and runs both rules across fourteen
    /// corners. The comment on `dayCell` named the condition for taking the token —
    /// gaps — and the owner asked for it after seeing the radius change on device.
    /// So the gap is `Space.xs` and the two rules are gone: a filled rounded cell
    /// with space on either side is already separated from its neighbour, and the
    /// rules were the top and bottom edges of a strip there no longer is.
    private var workdaysField: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Eyebrow("Workdays")

            HStack(spacing: Space.xs) {
                ForEach(Self.weekdaysInOrder, id: \.self) { weekday in
                    dayCell(weekday)
                }
            }

            Text(store.profile.workdays.isEmpty
                 ? "With no workdays set, Hourss cannot compare your working days to the rest."
                 : "Everything else counts as a day off.")
                .textStyle(.label)
                .foregroundStyle(store.profile.workdays.isEmpty ? Color.orange : Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One day, as a block: `Space.tapTarget` tall, an equal share of the row wide,
    /// and `Radius.block` through `blockSurface` like every other block in the app.
    ///
    /// **A day off has to be drawn.** The off state was `Color.clear` while the two
    /// rules were carrying the strip's shape, so once they went, every cell that is
    /// not a workday — and all seven, for somebody who has set none — would have been
    /// a letter floating in a gap with no block to round. `track` is
    /// the surface's own faint fill — the same thing `RatingScale` and `SelectableChip`
    /// paint behind an unselected segment — and with it an off day still reads as a
    /// cell you can tap rather than as an absence. Selection is still never carried
    /// by colour alone: the accessibility label says "a workday" or "a day off" in
    /// words, as it always did.
    private func dayCell(_ weekday: Int) -> some View {
        let isOn = store.profile.workdays.contains(weekday)

        return Button {
            toggleWorkday(weekday)
        } label: {
            Text(Self.initial(for: weekday))
                .textStyle(.action)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: Space.tapTarget)
                .blockSurface(isOn ? Color.lime : surface.track)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workday-\(weekday)")
        .accessibilityLabel("\(Self.fullName(for: weekday)): \(isOn ? "a workday" : "a day off")")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggleWorkday(_ weekday: Int) {
        if store.profile.workdays.contains(weekday) {
            store.profile.workdays.remove(weekday)
        } else {
            store.profile.workdays.insert(weekday)
        }
        // Workdays are read when observations are built, so every hypothesis that
        // splits on them is now computed against a different week.
        store.rebuildInsights()
        store.persist()
    }

    private func commitName() {
        store.profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.persist()
    }

    // MARK: - Weekday naming

    /// 1 is Sunday through 7 Saturday, rotated so the week starts where this
    /// calendar says it does.
    private static var weekdaysInOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private static func initial(for weekday: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
    }

    private static func fullName(for weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "Day \(weekday)"
    }
}
