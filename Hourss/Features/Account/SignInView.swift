import SwiftUI

/// The sign-in argument, wherever it is being made.
///
/// One view rather than two near-identical ones, because the onboarding beat and
/// the gate that appears when a credential is withdrawn are the same request with
/// a different reason in front of it. Sharing it is also what keeps the promise
/// on this screen in one place: it is the only screen in the app that says what
/// signing in does, and two copies would eventually say two things.
struct SignInPanel: View {
    @Environment(AccountService.self) private var account
    @Environment(HourssStore.self) private var store

    /// What the headline says. The body underneath does not change, because the
    /// facts do not.
    let headline: [Text]
    var lead: String
    var onSignedIn: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Eyebrow("Your account")

            DisplayHeadline(headline, style: .sectionTitle)

            Text(lead)
                .textStyle(.body)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.sm) {
                AppleSignInButton(action: signIn)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .opacity(account.isSigningIn ? 0.4 : 1)
                    .disabled(account.isSigningIn)
                    .accessibilityLabel("Sign in with Apple")
                    // Also on the SwiftUI side. `accessibilityLabel` on a
                    // `UIViewRepresentable` makes SwiftUI wrap it in an element of
                    // its own, which shadows the identifier set on the UIKit button
                    // underneath — so the control the gate exists for became
                    // invisible to the one test that checks the gate offers it.
                    .accessibilityIdentifier("sign-in-with-apple")

                // Sized and coloured as a real message rather than a caption: it
                // is the only thing on the screen explaining why nothing happened.
                if let failure = account.failure {
                    Text(failure)
                        .textStyle(.body)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sign-in-failure")
                }
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                HRule()
                Text("Apple shares your name and email, and lets you hide the email. Hourss never sees a password, and asks for nothing else.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .pageGutter()
        .padding(.top, Space.md)
    }

    /// The name is adopted here and nowhere else.
    ///
    /// Apple sends it once per Apple ID, ever, so the moment it arrives is the
    /// only moment it can be captured — and this is the single path a credential
    /// takes into the app, which is what makes "once" reliable rather than a
    /// thing three screens each half-remember to do.
    private func signIn() {
        Task {
            guard await account.signIn() else { return }
            if let name = account.account?.fullName {
                store.adoptDisplayName(name)
            }
            onSignedIn()
        }
    }
}

/// The gate a signed-out person meets after onboarding is behind them.
///
/// Reached two ways: they signed out in You, or they revoked Hourss in Settings ▸
/// Apple ID and the launch check noticed. The copy has to work for both, so it
/// says what is true in either case — nothing has been deleted.
struct AccountGateView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                // On the eyebrow rather than on the screen: an identifier on the
                // container would propagate down and overwrite the Apple button's.
                Eyebrow("Account")
                    .accessibilityIdentifier("account-gate")
            }
            .pageGutter()
            .padding(.vertical, Space.gutter)
            HRule()

            ScrollView {
                SignInPanel(
                    headline: [
                        Text("Sign back").styled(.sectionTitle),
                        Text("in to ").styled(.sectionTitle).then(Text("Hourss.").styled(.emphasis(42))),
                    ],
                    lead: "Hourss opens this record with your Apple ID. Nothing has been deleted — every session you have logged is still on this iPhone, waiting."
                )
                .padding(.bottom, Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .surface(.canvas)
    }
}

/// What the app shows while it is asking Apple whether the stored credential is
/// still good.
///
/// The wordmark on the canvas, and nothing else. The check is usually
/// imperceptible, but it is a call to another process and can take a moment on a
/// cold launch — and the two things that could stand in for it are both worse: the
/// gate flashes a sign-in screen at somebody who is signed in, and the app itself
/// flashes their record at somebody who may not be.
struct AccountCheckView: View {
    var body: some View {
        VStack {
            Spacer()
            Wordmark()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .surface(.canvas)
        .accessibilityIdentifier("account-checking")
    }
}

/// Y2 — the account, from You.
///
/// A short screen, because there is little to say: no password to change, no
/// devices to list, no server holding anything. What it does have is the one
/// control that matters and the one sentence that stops sign-out reading as a
/// threat to somebody's history.
struct AccountView: View {
    @Environment(AccountService.self) private var account
    @Environment(HourssStore.self) private var store
    @State private var isConfirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                DisplayHeadline([
                    Text("Signed in").styled(.sectionTitle),
                    Text("with ").styled(.sectionTitle).then(Text("Apple.").styled(.emphasis(42))),
                ], style: .sectionTitle)
                .padding(.top, Space.md)

                VStack(spacing: 0) {
                    HRule()
                    detail("Name", account.account?.fullName ?? "Not shared")
                    HRule()
                    detail("Email", account.account?.email ?? "Not shared")
                    HRule()
                }

                VStack(spacing: 0) {
                    Button {
                        isConfirmingSignOut = true
                    } label: {
                        SettingsRow(title: "Sign out", detail: "Your record stays on this iPhone.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sign-out")
                    HRule()
                }

                Text("Hourss keeps your record on this iPhone. Signing in names it and nothing more — no session, no sync, nothing sent anywhere.")
                    .textStyle(.label)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pageGutter()
            .padding(.bottom, Space.xl)
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .top, spacing: 0) { BackHeader(title: "You") }
        .navigationBarBackButtonHidden()
        .confirmationDialog("Sign out of Hourss?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { account.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sessions, ratings and notes stay on this iPhone. You will need your Apple ID to open them again.")
        }
    }

    /// Not a `SettingsRow`: these two rows are readings, not destinations, and the
    /// row style carries an arrow that would promise a screen behind them.
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).textStyle(.label).foregroundStyle(Color.muted)
            Spacer(minLength: Space.sm)
            Text(value)
                .textStyle(.body)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Space.sm)
        .frame(minHeight: Space.tapTarget)
        .accessibilityElement(children: .combine)
    }
}
