import SwiftUI

/// T1, T2 and T3 are one screen in three states, driven by what the store holds:
/// nothing logged yet, a session running, or a day with a record.
struct TodayView: View {
    @Environment(HourssStore.self) private var store
    let onLog: () -> Void

    @State private var selectedSessionId: UUID?

    /// The recommendation layer's output, cached.
    ///
    /// Held here rather than read from the store because building it runs the
    /// engine — findings, the correction, the bootstrap — and a view body is
    /// re-evaluated on every keystroke elsewhere in the app. Recomputed when the
    /// record it rests on changes, and no more often.
    @State private var recommendations: [Recommendation] = []

    /// Today's one fact from this person's own Health history, or nil.
    ///
    /// Deliberately a sibling of the observation slot rather than another case
    /// inside it. The slot is engine output gated on logged evidence, and its
    /// precedence table would let a fact outrank the unfinished-reflection
    /// prompt — the only route from this screen to rating a session that was
    /// actually logged. A fact costs nothing to show and must never be able to
    /// cost that.
    ///
    /// Cached here for the same reason the recommendations are: resolving it runs
    /// the four digest generators across a year of history, and a view body is
    /// re-evaluated far more often than a year of history changes.
    @State private var dailyFact: HealthDigest.Fact?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var todaysSessions: [Session] { store.sessions(on: today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                dateHeading

                if let running = store.runningSession {
                    ActiveSessionPanel(session: running)          // T2
                }

                // Above both branches rather than inside the logged one. The whole
                // point of the daily fact is that it costs nothing: it is already
                // true about this person and needs no session, no rating and no
                // streak. Putting it under the timeline would make the one thing
                // here that asks nothing of them available only to people who had
                // already given something.
                dailyFactRow

                if todaysSessions.isEmpty {
                    emptyState                                     // T1
                } else {
                    DayTimeline(                                   // T3
                        sessions: todaysSessions,
                        day: today,
                        selectedSessionId: $selectedSessionId
                    )
                    ObservationSlotView(
                        state: store.slotState(on: today, recommendations: recommendations),
                        recommendations: recommendations
                    )
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationDestination(for: AllFactsRoute.self) { _ in AllFactsView() }
        .onAppear {
            if selectedSessionId == nil { selectedSessionId = todaysSessions.last?.id }
        }
        // The layer runs whether or not this person can see its output: the
        // upgrade prompt names how many recommendations they would get, so the
        // count only exists if the count was computed.
        .task(id: recommendationInputs) {
            recommendations = store.slotRecommendations()
        }
        // The dispenser decides whether this is a day that spends a fact; asking
        // it more than once a day is free, which is why the whole of its memory
        // sits in defaults rather than in this view's lifetime.
        .task(id: dailyFactInputs) {
            dailyFact = DailyFact().fact(for: today, from: HealthDigest.pool(from: store.healthByDay))
        }
    }

    /// The fact, when there is one. No empty state and no placeholder: a day with
    /// nothing left to say is a day this row does not exist, which is quieter than
    /// a box explaining its own absence and is the only honest shape once the
    /// pool runs out.
    @ViewBuilder
    private var dailyFactRow: some View {
        if let fact = dailyFact {
            VStack(alignment: .leading, spacing: 0) {
                HRule()
                HealthFactRow(fact: fact, identifier: "today-fact")

                // Under the fact rather than beside it. The one-a-day pacing is
                // the default because it is what keeps the first week from being
                // silent, but it is a courtesy and not a lock, and somebody who
                // wants the whole list is asking about their own history.
                NavigationLink(value: AllFactsRoute()) {
                    HStack(spacing: 6) {
                        Text("View all").textStyle(.action)
                        Text("↘").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                    }
                    .frame(minHeight: Space.tapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("view-all-facts")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
            HRule()
        }
        .background(Color.canvas)
    }

    private var dateHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date().formatted(.dateTime.weekday(.wide)))
                .textStyle(.dayNumeral)
            Text(Date().formatted(.dateTime.day().month(.wide)))
                .textStyle(.dayNumeral)
                .foregroundStyle(Color.muted)

            if !todaysSessions.isEmpty {
                Text(daySummary(minutes: store.totalLoggedMinutes(on: today), sessionCount: todaysSessions.count))
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .padding(.top, Space.xs)
            }
        }
        .padding(.top, Space.md)
    }

    /// T1 — nothing logged yet. An invitation, not an empty-state illustration.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HRule()
            DisplayHeadline([
                Text("Nothing logged").styled(.sectionTitle),
                Text("yet ").styled(.sectionTitle).then(Text("today.").styled(.emphasis(42))),
            ], style: .sectionTitle)
            .padding(.top, Space.sm)

            Text("Whatever you're doing right now is enough.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 320, alignment: .leading)

            VStack(spacing: 0) {
                HRule()
                ForEach(store.pickableActivities.prefix(4)) { activity in
                    Button {
                        store.startSession(activityId: activity.id)
                    } label: {
                        HStack {
                            Text(activity.name).textStyle(.stepName)
                            Spacer()
                            Text("↗").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        }
                        .frame(minHeight: Space.tapTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    HRule()
                }
            }
            .padding(.top, Space.sm)
        }
    }

    /// What the daily fact rests on. The day itself is in here so an app left
    /// open overnight hands out tomorrow's fact tomorrow rather than at the next
    /// cold launch; the two health counts catch a sync that changed what the
    /// history holds.
    private var dailyFactInputs: [Int] {
        [Int(today.timeIntervalSinceReferenceDate),
         store.healthByDay.count,
         store.healthByDay.values.reduce(0) { $0 + $1.count }]
    }

    /// What the slot rests on, reduced to something cheap to compare. The engine
    /// is deterministic over the record, so nothing else can move its answer.
    private var recommendationInputs: [Int] {
        [store.sessions.count, store.reflections.count, store.profile.priorities.count,
         store.healthByDay.count, store.physiologyReadings.count]
    }
}

/// T2 — a running session. Elapsed time, the activity's own mark, and a discreet
/// stop. There is no pause in V1.
private struct ActiveSessionPanel: View {
    @Environment(HourssStore.self) private var store
    let session: Session

    private var glyph: ActivityGlyph.Kind {
        .forActivity(named: store.activityName(session.activityId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .center, spacing: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Eyebrow("Now", color: .subtleOnDark)
                    Text(store.activityName(session.activityId)).textStyle(.stepName)

                    if let intention = session.intention, !intention.isEmpty {
                        Text(intention).textStyle(.body).foregroundStyle(Color.mutedOnDark)
                    }

                    TimelineView(.periodic(from: session.startAt, by: 1)) { context in
                        Text(elapsed(at: context.date))
                            .font(.custom("DMMono-Medium", fixedSize: 34))
                            .monospacedDigit()
                            .foregroundStyle(Color.lime)
                            .accessibilityLabel("Running for \(elapsedSpoken(at: context.date))")
                    }
                    .padding(.top, Space.xs)
                }

                Spacer(minLength: Space.sm)

                // The only thing on this screen that moves other than the clock,
                // and it is deliberately the slower of the two: the number is the
                // information, the mark is company for it.
                AnimatedActivityGlyph(kind: glyph, size: 64, color: .lime)
                    .accessibilityHidden(true)
            }

            HRule(color: .forestRule)

            if let reason = store.live?.unavailableReason {
                Text(reason)
                    .textStyle(.label)
                    .foregroundStyle(Color.mutedOnDark)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live-activity-unavailable")
            }

            Button {
                store.stopSession(session.id)
            } label: {
                HStack(spacing: 6) {
                    Text("Stop and reflect").textStyle(.action)
                    Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                }
                .frame(minHeight: Space.tapTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stop-session")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(Color.forest)
        .surfaceContent(.forest)
    }

    private func elapsedSeconds(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(session.startAt)))
    }

    private func elapsed(at date: Date) -> String {
        let total = elapsedSeconds(at: date)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func elapsedSpoken(at date: Date) -> String {
        let minutes = elapsedSeconds(at: date) / 60
        return minutes < 1 ? "less than a minute" : "\(minutes) minutes"
    }
}

func formatMinutes(_ minutes: Int) -> String {
    guard minutes > 0 else { return "under a minute" }
    let hours = minutes / 60
    let mins = minutes % 60
    if hours == 0 { return "\(mins)m" }
    return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
}

/// Compact form for the places where the long phrasing would not fit.
func formatMinutesShort(_ minutes: Int) -> String {
    minutes > 0 ? formatMinutes(minutes) : "<1m"
}

/// The line under a day's date. Leads with the total, unless there isn't one yet.
func daySummary(minutes: Int, sessionCount: Int) -> String {
    let noun = sessionCount == 1 ? "session" : "sessions"
    guard minutes > 0 else { return "\(sessionCount) \(noun) logged" }
    return "\(formatMinutes(minutes)) logged across \(sessionCount) \(noun)"
}
