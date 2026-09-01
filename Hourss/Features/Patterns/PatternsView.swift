import SwiftUI

/// P1 and P2. The warm-up state is not a placeholder chart — the spec forbids
/// fake charts and premature observations, so before there is evidence the screen
/// says so plainly.
struct PatternsView: View {
    @Environment(HourssStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.isWarmingUp {
                    warmingUp
                } else {
                    ranked
                }
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            ScreenHeader(title: "Patterns")
        }
        .navigationDestination(for: Insight.self) { InsightDetailView(insight: $0) }
    }

    /// P1 — warming up.
    private var warmingUp: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            DisplayHeadline([
                Text("Still").styled(.sectionTitle),
                Text("listening.").styled(.emphasis(42)),
            ], style: .sectionTitle)
            .padding(.top, Space.md)

            Text("Hourss waits until a pattern repeats before saying anything. Nothing here yet is a good sign, not a broken screen.")
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .frame(maxWidth: 320, alignment: .leading)

            HRule()

            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow("Progress")
                Text("\(store.eligibleSessionCount) of \(HourssStore.sessionsNeededForPatterns) sessions")
                    .textStyle(.stepName)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.ink.opacity(0.08))
                        Rectangle().fill(Color.lime)
                            .frame(width: geo.size.width * store.warmUpProgress)
                    }
                }
                .frame(height: 8)
                .padding(.top, Space.xs)
            }

            HRule()

            VStack(alignment: .leading, spacing: Space.xs) {
                Eyebrow("What helps")
                ForEach([
                    "Log the same kind of work at different times of day.",
                    "Say how a session felt, even when it was unremarkable.",
                    "Keep going for a couple of weeks.",
                ], id: \.self) { line in
                    Text("— \(line)")
                        .textStyle(.body)
                        .foregroundStyle(Color.muted)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    /// P2 — one lead observation, then a sparse grouped feed.
    private var ranked: some View {
        let insights = store.visibleInsights

        return VStack(alignment: .leading, spacing: Space.lg) {
            if let lead = insights.first {
                NavigationLink(value: lead) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Eyebrow("Here's something we're noticing", color: .subtleOnDark)
                        Text(lead.statement)
                            .textStyle(.sectionLead)
                            .foregroundStyle(Color.paperOnDark)
                        Text(lead.evidence.summary)
                            .textStyle(.label)
                            .foregroundStyle(Color.mutedOnDark)
                        HStack(spacing: 6) {
                            Text("See the evidence").textStyle(.action)
                            Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        }
                        .foregroundStyle(Color.paperOnDark)
                        .padding(.top, Space.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
                    .background(Color.forest)
                    .environment(\.surface, .forest)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lead-insight")
                .padding(.top, Space.md)
            }

            ForEach(groups(insights.dropFirst().map { $0 }), id: \.0) { group, items in
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(group)
                        .padding(.bottom, Space.xs)
                    HRule()
                    ForEach(items) { insight in
                        NavigationLink(value: insight) {
                            InsightRow(insight: insight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insight-row")
                        HRule()
                    }
                }
            }

            Text("Observations, not rules. Hourss only speaks up when the same thing repeats.")
                .textStyle(.label)
                .foregroundStyle(Color.muted)
        }
    }

    private func groups(_ insights: [Insight]) -> [(String, [Insight])] {
        Dictionary(grouping: insights, by: { $0.type.group })
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

private struct InsightRow: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(insight.statement)
                .textStyle(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(insight.band.label)
                    .textStyle(.label)
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(insight.status == .saved ? "Saved" : "")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.sm)
        .contentShape(.rect)
    }
}

/// Shared top bar for the tabbed screens.
struct ScreenHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                Eyebrow(trailing ?? title)
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
            HRule()
        }
        .background(Color.canvas)
    }
}
