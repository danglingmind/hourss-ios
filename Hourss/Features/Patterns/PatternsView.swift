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
    ///
    /// This used to be a paragraph restating the progress bar beneath it, then
    /// three lines of generic advice. The marks are computed from real sessions,
    /// so they say what is actually thin rather than what usually is.
    private var warmingUp: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            DisplayHeadline([
                Text("Still").styled(.sectionTitle),
                Text("listening.").styled(.emphasis(42)),
            ], style: .sectionTitle)
            .padding(.top, Space.md)

            HRule()

            // Days, not sessions. The engine requires six distinct days on each
            // side of any comparison and never counts sessions at all, so a
            // session total told somebody they were two thirds of the way to
            // something that was not being measured. Six sessions on one Tuesday
            // are one day of evidence about Tuesdays.
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("\(store.ratedDayCount) of \(EvidenceFloor.days) days with a rating")
                    .textStyle(.stepName)
                DataBar(fraction: store.evidenceProgress, height: DataBar.progress)
                    .accessibilityLabel("\(store.ratedDayCount) of \(EvidenceFloor.days) days carrying a rated session")
            }

            HRule()

            VStack(alignment: .leading, spacing: Space.md) {
                coverageRow(
                    "Times of day",
                    detail: "\(store.timeBucketsCovered.filter { $0 }.count) of 4"
                ) {
                    CoverageMark(segments: store.timeBucketsCovered, height: DataBar.strip)
                }

                coverageRow(
                    "Sessions rated",
                    detail: "\(Int(store.ratedShare * 100))%"
                ) {
                    DataBar(fraction: store.ratedShare, height: DataBar.strip)
                }

                coverageRow(
                    "Weeks logged",
                    detail: String(format: "%.0f of 6", store.weeksOfHistory.rounded())
                ) {
                    DataBar(fraction: store.weeksOfHistory / 6, height: DataBar.strip)
                }
            }
        }
    }

    private func coverageRow<Mark: View>(
        _ title: String,
        detail: String,
        @ViewBuilder mark: () -> Mark
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).textStyle(.body)
                Spacer()
                Text(detail).textStyle(.label).foregroundStyle(Color.muted)
            }
            mark()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
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
                        Text(lead.evidence.summary)
                            .textStyle(.label)
                            .foregroundStyle(Color.mutedOnDark)
                        HStack(spacing: 6) {
                            Text("See the evidence").textStyle(.action)
                            Text("→").font(.custom("DMSans-Bold", fixedSize: 18)).foregroundStyle(Color.orange)
                        }
                        .padding(.top, Space.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
                    .background(Color.forest)
                    .surfaceContent(.forest)
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
