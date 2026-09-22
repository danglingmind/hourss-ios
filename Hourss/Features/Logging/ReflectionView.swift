import SwiftUI

/// L3 — the end-of-session reflection.
///
/// Feeling saves the moment it is tapped, performance is optional and never
/// blocks the save, and a note is never required. Nothing here defaults to a
/// middle value: an unanswered scale stays unanswered.
///
/// The first rating of each day also gets something back — see `DayContextCard`,
/// which this view raises over itself rather than presenting.
struct ReflectionView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID

    @State private var feeling: Int?
    @State private var performance: Int?
    @State private var note = ""

    /// The day's fact, once it has been earned. Held here rather than in the
    /// store because of the ordering problem described on `rate()`.
    @State private var card: DayContextCard.Content?
    @State private var hasSaved = false

    private var session: Session? { store.sessions.first { $0.id == sessionId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Reflection", onClose: { finish() })

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if let session {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.activityName(session.activityId)).textStyle(.stepName)
                            Text("\(session.startAt.formatted(.dateTime.hour().minute())) · \(formatMinutes(session.durationMinutes))")
                                .textStyle(.label)
                                .foregroundStyle(Color.muted)
                        }
                    }

                    HRule()

                    RatingScale(value: $feeling, kind: .feeling)

                    // Performance stays on screen rather than behind a disclosure.
                    // It is still optional — nothing is preselected and the save
                    // path does not care whether it was answered.
                    VStack(alignment: .leading, spacing: Space.sm) {
                        HRule()
                        RatingScale(
                            value: $performance,
                            kind: .performance,
                            caption: "Optional — a different question."
                        )
                        .padding(.top, Space.xs)
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Eyebrow("A note — optional")
                        TextField("Anything worth remembering?", text: $note, axis: .vertical)
                            .textStyle(.bodyLarge)
                            .tint(.orange)
                            .padding(.vertical, Space.sm)
                            .overlay(alignment: .bottom) { HRule(color: .ink) }
                    }
                }
                .pageGutter()
                .padding(.vertical, Space.md)
            }

            VStack(spacing: 0) {
                HRule()
                HStack {
                    Button("Skip") { dismiss() }
                        .buttonStyle(.plain)
                        .textStyle(.action)
                        .foregroundStyle(Color.muted)
                        .frame(minHeight: Space.tapTarget)
                    Spacer()
                    DirectionalLink(title: "Save", arrow: "→") { rate() }
                }
                .pageGutter()
            }
        }
        .surface(.canvas)
        // An overlay, not a sheet and not a second screen.
        //
        // `store.saveReflection` clears `pendingReflectionSessionId`, which *is*
        // the `.sheet(item:)` binding this view is presented through
        // (`RootView.swift:92`). Saving therefore tears this view down in the same
        // runloop pass, and anything presented *from* here goes with it. So the
        // card is drawn over the reflection inside the one sheet that is already
        // on screen, and the save is what waits instead — see `rate()`.
        .overlay {
            if let card {
                DayContextCard(content: card) { finish() }
                    .transition(.opacity)
            }
        }
        // While the card is up the rating is recorded in `@State` and nowhere
        // else. A swipe-down here would lose it, so there isn't one; the card's
        // own "Done" is the way out. `onDisappear` below is the belt to this
        // braces, for the dismissals iOS does not ask permission for.
        .interactiveDismissDisabled(card != nil)
        .onDisappear {
            if card != nil { commit() }
        }
        .onAppear {
            if let existing = store.reflection(for: sessionId) {
                feeling = existing.feelingScore
                performance = existing.performanceScore
                note = existing.note ?? ""
            }
        }
    }

    /// Save was tapped. Either the day owes a card, or this is over.
    ///
    /// The card is decided *before* the save rather than after it, and the save
    /// is deferred until the card is done with. That inversion is forced: the
    /// store clears the sheet's own binding as part of saving, so a card raised
    /// after a save would be raised onto a view that no longer exists.
    ///
    /// Three conditions, all necessary. A feeling must actually have been
    /// recorded — a Skip, or a save carrying only a note, has not rated anything
    /// and gets nothing back. It must be the first rating of the calendar day.
    /// And there must be something true to say, which most days there is not.
    private func rate() {
        guard let feeling else {
            finish()
            return
        }

        // A milestone first, and not subject to the once-a-day gate.
        //
        // The gate exists so a card does not appear on every rating. A milestone
        // cannot: it requires a rating strictly above everything logged before
        // it, so on a five-point scale it is rare by construction and gets rarer
        // the longer somebody uses the app. Gating it would mean earning the one
        // moment the record can produce and then not being told, because a sleep
        // figure had already used the slot that morning.
        if let milestone = RatingMilestone.earned(
            by: sessionId,
            rating: feeling,
            sessions: store.sessions,
            feeling: { store.feeling(for: $0) },
            activityName: store.activityName
        ) {
            // Still marks the day, so a milestone in the morning does not leave a
            // health card to arrive in the afternoon. One card a day either way;
            // which one it is depends on what there was to say.
            store.markContextCardShown()
            card = .milestone(milestone)
            return
        }

        guard store.isContextCardDue,
              let standout = DayDeviation.standout(on: Date(), history: store.healthByDay)
        else {
            finish()
            return
        }
        // Claimed only now, with a card in hand. Claiming it at the check above
        // would spend the day's one card on a day that had no fact in it.
        store.markContextCardShown()
        card = .health(standout)
    }

    private func finish() {
        commit()
        dismiss()
    }

    /// Idempotent, because there are now two paths into it — the button and
    /// `onDisappear` — and the second one must not re-stamp a reflection the
    /// first one already wrote.
    private func commit() {
        guard !hasSaved else { return }
        hasSaved = true
        store.saveReflection(sessionId: sessionId, feeling: feeling, performance: performance, note: note)
    }
}
