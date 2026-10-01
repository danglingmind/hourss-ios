import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The running session, on the lock screen and in the Dynamic Island.
///
/// One state: running. Stopping ends the activity and opens the app, where the
/// reflection belongs — so there is nothing here to keep in sync with the store,
/// and nothing that can be half-answered.
///
/// The Island is Apple's surface, not ours, so its shape and placement are not
/// negotiable — the container's curve is Apple's number and there is no API to put
/// `Radius.block` on it. Everything inside it is Hourss: the activity's own
/// rectangle glyph, DM Mono for the count, lime for the running state, no borrowed
/// symbols, and the stop control on the house radius like every other block.
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
                    StopButton()
                        // Inset well clear of the container's corner radius. A
                        // square element near the bottom edge loses its corners to
                        // the curve.
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .padding(.top, 4)
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
        }
    }
}

// MARK: - Pieces

/// Counts up while running, and freezes for the instant between stopping and the
/// activity ending.
///
/// `Text(timerInterval:)` is what keeps this ticking without the app running — the
/// system advances it, so no background execution is needed.
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

    /// The same shape as the running clock, so it freezes rather than switching
    /// units. Rounding to whole minutes rendered a short session as "0m", which
    /// read as a dead timer.
    private func elapsed(to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(context.attributes.startedAt)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

        if compact {
            return "\(hours * 60 + minutes):\(pad(seconds))"
        }
        return hours > 0
            ? "\(hours):\(pad(minutes)):\(pad(seconds))"
            : "\(minutes):\(pad(seconds))"
    }
}

/// Orange rather than lime: lime is the running state everywhere else in this
/// view, and an action in the same colour reads as more of the same.
///
/// The rounded corners used to be a scoped exception, back when `radius.default` was
/// 0 everywhere in Hourss and this was the one square block that could not be left
/// square — set into Apple's heavily rounded container it read as a mistake rather
/// than as a principle. It was 12pt, chosen by eye for that container alone.
///
/// It is not an exception any more. Blocks round throughout the app now, so this
/// takes `Radius.block` like the rest, and the Island stops being a special case.
/// The token is a touch tighter than the 12 this had; if the control looks mean
/// inside the container after a change, the fix is the token, not a number here.
private struct StopButton: View {
    var body: some View {
        Button(intent: StopSessionIntent()) {
            Text("Stop and reflect")
                .font(.custom("DMSans-Bold", size: 14))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .blockSurface(Color.orange)
        }
        .buttonStyle(.plain)
    }
}

/// The lock-screen presentation — the same information with room to breathe.
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

            StopButton()
        }
        .padding(16)
    }
}

private extension ActivityViewContext where Attributes == HourssActivityAttributes {
    var glyph: ActivityGlyph.Kind {
        ActivityGlyph.Kind(rawValue: attributes.glyphID) ?? .deepWork
    }
}
