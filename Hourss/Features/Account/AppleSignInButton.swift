import SwiftUI
import AuthenticationServices

/// Apple's own button, on the house corner radius.
///
/// Sign in with Apple is the one control in this app that may not be redrawn in
/// the house style — the mark, the wording and the proportions are Apple's, and
/// substituting a `DirectionalLink` for them would be both a guideline violation
/// and a worse button, because people recognise this one. `cornerRadius` is the
/// single property Apple does expose, so it is the only thing about this control
/// the system can state, and it states `Radius.block` like every other block.
///
/// It used to be forced to zero, back when nothing in Hourss had a rounded corner.
/// That made this file the one documented exception to the conformance sweep; now
/// it is an ordinary participant, and it is the reason `Radius.block` uses circular
/// corners rather than `.continuous` — `CALayer.cornerRadius` cannot do continuous,
/// and this button sits directly beside a `PrimaryAction` on the sign-in screen.
///
/// Wrapping `ASAuthorizationAppleIDButton` rather than using SwiftUI's
/// `SignInWithAppleButton` is what buys that radius at all. The SwiftUI wrapper
/// hides it, which would leave this button on Apple's default while its neighbour
/// followed the token.
struct AppleSignInButton: UIViewRepresentable {
    var label: ASAuthorizationAppleIDButton.ButtonType = .signIn
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: label,
            // The canvas is a warm paper, so the dark button is the one with
            // contrast. `.whiteOutline` disappears into it.
            authorizationButtonStyle: .black
        )
        button.cornerRadius = Radius.block
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.fire),
                         for: .touchUpInside)
        button.accessibilityIdentifier = "sign-in-with-apple"
        // The button reports its own intrinsic width, which in a SwiftUI layout
        // makes it refuse to fill the gutter.
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        // The closure is re-made on every redraw and captures fresh state, so the
        // coordinator has to be handed the current one or the button keeps firing
        // the action it was built with.
        context.coordinator.action = action
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}
