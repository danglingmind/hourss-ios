import SwiftUI

/// Shown when Health access appears to have been withdrawn.
///
/// The app cannot work without it. Every observation Hourss makes rests on
/// readings from the phone, and with those gone the honest thing is to say so
/// rather than keep a feed on screen that has quietly stopped being true.
///
/// It is worth being precise about what is known here, because the copy has to
/// be. iOS never reports read authorization, so this is not a permission check —
/// it is an inference from a change: this phone read real data before and reads
/// none now. That is very likely a revocation and it is not certain, so nothing
/// here accuses anybody of anything, and the way out is a door rather than a
/// demand.
struct ReconnectHealthView: View {
    @Environment(HealthService.self) private var health
    @State private var rechecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Spacer(minLength: 0)

            Eyebrow("Health is disconnected", color: .subtleOnDark)

            DisplayHeadline([
                Text("Hourss can't read").styled(.sectionTitle),
                Text("your ").styled(.sectionTitle).then(Text("record.").styled(.emphasis(42))),
            ], style: .sectionTitle)

            Text("Everything Hourss shows you is built from what your phone already recorded. Without it there is nothing to read, and nothing honest to show.")
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                HRule()
                Text("Settings → Privacy & Security → Health → Hourss")
                    .textStyle(.label)
                    .padding(.vertical, Space.sm)
                    .fixedSize(horizontal: false, vertical: true)
                HRule()
            }

            // iOS will not present the permission sheet a second time once
            // somebody has answered it, so a button claiming to reconnect would
            // do nothing visible and read as broken. This one opens the place
            // where the switch actually is.
            DirectionalLink(title: "Open Settings", arrow: "→", color: .lime) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .accessibilityIdentifier("health-open-settings")

            DirectionalLink(title: rechecking ? "Checking…" : "I've turned it back on",
                            arrow: "↻", color: .subtleOnDark) {
                Task {
                    rechecking = true
                    await health.recheckAccess()
                    rechecking = false
                }
            }
            .disabled(rechecking)
            .accessibilityIdentifier("health-recheck")

            Text("Your sessions and notes are still here. Nothing was deleted.")
                .textStyle(.label)
                .foregroundStyle(Color.subtleOnDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)

            Spacer(minLength: 0)
        }
        .pageGutter()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .surface(.forest)
    }
}
