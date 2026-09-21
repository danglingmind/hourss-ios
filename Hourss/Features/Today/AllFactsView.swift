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
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        VStack(alignment: .leading, spacing: 0) {
                            if DailyFact.key(for: fact) == todaysKey {
                                Eyebrow("Today's")
                                    .padding(.top, Space.sm)
                            }
                            HealthFactRow(
                                fact: fact,
                                revealIndex: min(index, 3),
                                identifier: "all-facts-row"
                            )
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
        .task(id: store.healthByDay.count) {
            let pool = HealthDigest.pool(from: store.healthByDay)
            facts = pool
            // Asking the dispenser rather than storing the answer anywhere: it is
            // idempotent within a calendar day, so this returns the fact Today is
            // already showing and does not spend a second one.
            todaysKey = DailyFact()
                .fact(for: Calendar.current.startOfDay(for: Date()), from: pool)
                .map(DailyFact.key(for:))
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
        return "\(facts.count) \(noun) from your own Health history, most striking first."
    }

    /// No Health history read yet, so there is nothing to list. Says that, rather
    /// than suggesting logging would change it — it would not; this pool comes
    /// from the watch, not from the record.
    private var empty: some View {
        Text("Nothing here yet. These come from your Health history.")
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
