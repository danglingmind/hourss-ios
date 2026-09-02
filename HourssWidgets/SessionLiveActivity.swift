import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The running session, on the lock screen and in the Dynamic Island.
///
/// The Island is Apple's surface, not ours, so its shape and placement are not
/// negotiable — but everything inside it is Hourss: the activity's own rectangle
/// glyph, DM Mono for the count, lime for the running state, and no borrowed
/// symbols. The one concession is the rounded container, which the system draws.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HourssActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.forest)
                .activitySystemActionForegroundColor(Color.lime)
                .widgetURL(URL(string: "hourss://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                // Glyph and name travel together on the leading side; splitting
                // them across leading/center made the pill claim the full width.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ActivityGlyph(kind: context.glyph, size: 17, color: .lime)
                            .padding(.vertical, 2)
                        Text(context.attributes.activityName)
                            .font(.custom("DMSans-Medium", size: 19))
                            .foregroundStyle(Color.paperOnDark)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Counter(context: context, size: 22, compact: false)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedControls(context: context)
                        // Inset well clear of the container's corner radius. A
                        // square element near the bottom edge loses its corners to
                        // the curve, and `radius.default` is 0 so it cannot be
                        // rounded to match — the margin is the only lever.
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            } compactLeading: {
                ActivityGlyph(kind: context.glyph, size: 14, color: .lime)
                    .padding(.leading, 2)
            } compactTrailing: {
                // The compact region has to stay narrow enough to sit beside the
                // camera. An hours-included timer reserves room for "0:00:00" and
                // stretches the pill edge to edge, so minutes and seconds only.
                Counter(context: context, size: 13, compact: true)
            } minimal: {
                ActivityGlyph(kind: context.glyph, size: 14, color: .lime)
            }
            .keylineTint(Color.lime)
            .widgetURL(URL(string: "hourss://today"))
        }
    }
}

// MARK: - Pieces

/// Counts up while running, and holds the final length once stopped.
///
/// `Text(timerInterval:)` is what keeps this ticking without the app running —
/// the system advances it, so no background execution is needed.
private struct Counter: View {
    let context: ActivityViewContext<HourssActivityAttributes>
    var size: CGFloat
    var compact: Bool

    var body: some View {
        Group {
            if let endedAt = context.state.endedAt {
                Text(elapsed(to: endedAt))
            } else {
                Text(
                    timerInterval: context.attributes.startedAt...distantFuture,
                    pauseTime: nil,
                    countsDown: false,
                    showsHours: !compact
                )
                .multilineTextAlignment(.trailing)
            }
        }
        .font(.custom("DMMono-Medium", size: size))
        .monospacedDigit()
        .foregroundStyle(Color.lime)
        .frame(maxWidth: compact ? 46 : nil)
    }

    private var distantFuture: Date {
        context.attributes.startedAt.addingTimeInterval(60 * 60 * 24)
    }

    /// The stopped value in the same shape as the running one, so the clock simply
    /// freezes rather than switching units. Rounding to whole minutes rendered
    /// anything under a minute as "0m", which read as a broken timer.
    private func elapsed(to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(context.attributes.startedAt)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

        if compact {
            // The compact pill has no room for hours; minutes carry over instead.
            return "\(hours * 60 + minutes):\(pad(seconds))"
        }
        return hours > 0
            ? "\(hours):\(pad(minutes)):\(pad(seconds))"
            : "\(minutes):\(pad(seconds))"
    }
}

/// What the bottom of the expanded Island shows: a stop control while running,
/// and both rating scales once stopped.
private struct ExpandedControls: View {
    let context: ActivityViewContext<HourssActivityAttributes>

    var body: some View {
        if context.state.isRunning {
            IslandButton(title: "Stop and reflect", intent: StopSessionIntent(), height: 36)
                .padding(.top, 4)
        } else {
            // No Save button. The spec is explicit that a tapped score saves
            // immediately, and a confirm step here would also have overflowed the
            // expanded region — the button was being clipped by the container.
            VStack(alignment: .leading, spacing: 5) {
                RatingRow(label: "FELT", scale: "feeling", value: context.state.feeling)
                RatingRow(label: "WENT", scale: "performance", value: context.state.performance)
                Text(context.state.feeling == nil ? "Saves as you tap" : "Saved")
                    .font(.custom("DMMono-Regular", size: 10))
                    .foregroundStyle(context.state.feeling == nil ? Color.subtleOnDark : Color.lime)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 42)
            }
            .padding(.top, 2)
        }
    }
}

/// A filled action.
///
/// Orange rather than lime: lime is the energy fill on every rating segment above
/// it, and an action in the same colour as the data reads as another segment.
///
/// **The rounded corners are a deliberate, scoped exception.** `radius.default` is
/// 0 everywhere in Hourss, and it stays 0 — but this control lives inside Apple's
/// container, not ours, and a square rectangle set into a heavily rounded pill
/// reads as a mistake rather than as a principle. The exception ends at the edge
/// of the Island; nothing in the app rounds.
private struct IslandButton<I: AppIntent>: View {
    let title: String
    let intent: I
    var enabled: Bool = true
    var height: CGFloat = 36

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.custom("DMSans-Bold", size: 14))
                .foregroundStyle(enabled ? Color.ink : Color.mutedOnDark)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    (enabled ? Color.orange : Color.forestRaised),
                    in: .rect(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// One scale, laid out inline: a short mono label, then five flat segments.
///
/// Both questions have to be answerable without leaving the Island, and stacking
/// label-above-segments twice over does not fit the expanded region's height. The
/// label moves beside the segments instead. VoiceOver still gets the full question.
private struct RatingRow: View {
    let label: String
    let scale: String
    let value: Int?

    private var question: String {
        scale == "feeling" ? "How did that feel?" : "How well did it go?"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.custom("DMMono-Medium", size: 10))
                .kerning(0.5)
                .foregroundStyle(Color.subtleOnDark)
                .frame(width: 34, alignment: .leading)
                .accessibilityLabel(question)

            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { score in
                    Button(intent: RateSessionIntent(scale: scale, score: score)) {
                        Text("\(score)")
                            .font(.custom("DMMono-Medium", size: 13))
                            .foregroundStyle(value == score ? Color.ink : Color.mutedOnDark)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(
                                value == score ? fill(score) : Color.forestRaised,
                                // Softer than the button so the action still leads,
                                // but square segments beside a rounded button would
                                // look unfinished.
                                in: .rect(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(question) \(score) out of 5")
                }
            }
        }
    }

    private func fill(_ score: Int) -> Color {
        switch score {
        case 1, 2: .drainingFill
        case 3: .restorativeFill
        default: .lime
        }
    }
}

/// The lock-screen presentation, which is the same information with room to breathe.
private struct LockScreenView: View {
    let context: ActivityViewContext<HourssActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ActivityGlyph(kind: context.glyph, size: 16, color: .lime)
                Text(context.attributes.activityName)
                    .font(.custom("DMSans-Medium", size: 20))
                    .foregroundStyle(Color.paperOnDark)
                Spacer()
                Counter(context: context, size: 24, compact: false)
            }

            Rectangle()
                .fill(Color.forestRule)
                .frame(height: 1)

            ExpandedControls(context: context)
        }
        .padding(16)
    }
}

private extension ActivityViewContext where Attributes == HourssActivityAttributes {
    var glyph: ActivityGlyph.Kind {
        ActivityGlyph.Kind(rawValue: attributes.glyphID) ?? .deepWork
    }
}
