import SwiftUI

/// Where the daily fact goes to be read all at once.
///
/// **Why this exists at all, given the rationing.** Today hands out one fact a
/// day on purpose: a year of somebody's history is the only thing this app can
/// say before it has watched them log anything, and spending it in one sitting is
/// how the first week ends up silent. That reasoning is about the *default*, not
/// about withholding. Somebody who wants the whole list has asked a plain
/// question about their own data and there is no honest reason to answer it with
/// a drip feed — the facts were true before Hourss sorted them, and pacing them
/// is a courtesy rather than a rule.
///
/// So the rationing stays where it earns its keep, on the screen people open
/// without being asked, and this is the door out of it.
struct AllFactsView: View {
    @Environment(HourssStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Resolved off the body for the same reason Today resolves it off the body:
    /// building the pool runs four generators across a year of readings.
    @State private var facts: [HealthDigest.Fact] = []
    @State private var todaysKey: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.md) {
                heading

                if facts.isEmpty {
                    empty
                } else {
                    // Grouped by topic rather than run as one ranked list.
                    //
                    // The pool is four generators against eleven metrics, and the
                    // metrics inside a group are correlated by construction —
                    // four ways of noticing the same movement, three of noticing
                    // the same recovery. Ranked flat by surprise they interleave
                    // into what reads as the same card written out several times.
                    // Under a heading the same facts read as depth: four things
                    // known about sleep is a section, where four sleep cards
                    // scattered through a list is a stutter.
                    // Things you logged first, then what the watch read.
                    //
                    // Deliberately this order and not the reverse. A record fact
                    // exists because somebody did the logging, and putting the
                    // part they earned under four sections of Health history
                    // would bury it under the part they did not.
                    ForEach(HealthDigest.RecordTopic.allCases, id: \.self) { topic in
                        let inTopic = facts.filter {
                            if case .record(let t) = $0.subject { return t == topic }
                            return false
                        }
                        if !inTopic.isEmpty {
                            section(titled: topic.title, facts: inTopic)
                        }
                    }

                    ForEach(HealthGroup.allCases) { group in
                        let inGroup = facts.filter { $0.subject.healthGroup == group }
                        if !inGroup.isEmpty {
                            section(titled: group.title, facts: inGroup)
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .task(id: [store.healthByDay.count, store.sessions.count]) {
            let record = RecordFacts.pool(sessions: store.sessions,
                                          activityName: store.activityName)
            let pool = record + HealthDigest.pool(from: store.healthByDay)
            facts = pool
            // Asking the dispenser rather than storing the answer anywhere: it is
            // idempotent within a calendar day, so this returns the fact Today is
            // already showing and does not spend a second one.
            todaysKey = DailyFact()
                .fact(for: Calendar.current.startOfDay(for: Date()),
                      record: record,
                      from: HealthDigest.pool(from: store.healthByDay))
                .map(DailyFact.key(for:))
        }
    }

    /// One topic's facts, under the group's own name.
    ///
    /// The heading is the subject's own name — `HealthGroup.title` for the Health
    /// sections ("Sleep", "Recovery", "Movement", "Mind and light"), the same
    /// words the consent screen used, and `RecordTopic.title` for what somebody
    /// logged. Nothing here is a name invented for this list.
    private func section(titled title: String, facts inGroup: [HealthDigest.Fact]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(title)
                .padding(.top, Space.md)
                .padding(.bottom, Space.xs)

            ForEach(Array(inGroup.enumerated()), id: \.element.id) { index, fact in
                VStack(alignment: .leading, spacing: 0) {
                    if DailyFact.key(for: fact) == todaysKey {
                        Eyebrow("Today's")
                            .padding(.top, Space.sm)
                    }
                    HealthFactRow(
                        fact: fact,
                        // Capped, so the last row of a long group does not wait
                        // two seconds to draw itself in.
                        revealIndex: min(index, 3),
                        identifier: "all-facts-row"
                    )
                }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            DisplayHeadline([
                Text("Everything").styled(.sectionTitle),
                Text("we've ").styled(.sectionTitle).then(Text("found.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            // Counts what is here rather than promising what is coming. The pool
            // is finite and the last of it is not a failure state, so nothing on
            // this screen may imply that more is being held back.
            Text(summary)
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.md)
    }

    private var summary: String {
        let noun = facts.count == 1 ? "observation" : "observations"
        // No longer "most striking first" — that was true of the flat list and is
        // not true of the sections, which are ordered by topic. Within a section
        // the surprise ranking still holds, and saying so would be more precise
        // than a reader needs. "Health history" alone stopped being true once the
        // pool grew a half that comes from what somebody logged.
        return "\(facts.count) \(noun) from your own record and Health history, by topic."
    }

    /// Nothing read and nothing logged, so there is nothing to list. Both sources
    /// are named because both are now real: the empty state used to say logging
    /// would not change this, which was true when the pool came only from the
    /// watch and is not true any more.
    private var empty: some View {
        Text("Nothing here yet. These come from your Health history and what you log.")
            .textStyle(.body)
            .foregroundStyle(Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.sm)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text("←").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        Text("Today").textStyle(.action)
                    }
                    .frame(minHeight: Space.tapTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("back")
                Spacer()
            }
            .pageGutter()
            HRule()
        }
        .background(Color.canvas)
    }
}

/// The route to `AllFactsView`. A type rather than a bool so the destination is
/// declared once on Today and the link carries no state of its own.
struct AllFactsRoute: Hashable {}
