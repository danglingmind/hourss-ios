import SwiftUI

/// How often Hourss should ask what you are doing.
///
/// Shared between the onboarding beat and Preferences for the same reason the
/// priority ranker is: it is a control that changes what the phone does, and two
/// implementations of it are two chances for the second one to offer a frequency
/// the scheduler has never heard of.
///
/// Every row states its own cost in notifications per day. A frequency nobody can
/// picture is a frequency nobody can consent to, and "every hour" sounds modest
/// right up until it is fifteen interruptions.
struct LogReminderPicker: View {
    @Binding var selection: LogReminderFrequency

    var body: some View {
        VStack(spacing: 0) {
            HRule()
            ForEach(LogReminderFrequency.offered) { frequency in
                row(frequency)
            }
        }
    }

    private func row(_ frequency: LogReminderFrequency) -> some View {
        let isSelected = selection == frequency

        return Button {
            selection = frequency
        } label: {
            HStack(alignment: .top, spacing: Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.xs) {
                        Text(frequency.title).textStyle(.stepName)
                        if frequency == .recommended {
                            Text("Recommended")
                                .textStyle(.label)
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Text(frequency.detail)
                        .textStyle(.label)
                        .foregroundStyle(Color.muted)
                }
                Spacer(minLength: Space.sm)
                SelectionDot(isSelected: isSelected)
                    .padding(.top, 6)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: Space.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminder-\(frequency.rawValue)")
        .accessibilityLabel("\(frequency.title), \(frequency.detail)\(frequency == .recommended ? ", recommended" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .overlay(alignment: .bottom) { HRule() }
    }
}
