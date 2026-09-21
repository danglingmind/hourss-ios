import Foundation
import Observation
import AuthenticationServices

/// The one place the app asks who this is.
///
/// Hourss has no server, so there is nothing here that a session would normally
/// mean: no token, no expiry, no refresh. What Apple gives is an identifier and a
/// yes-or-no about whether it is still good, and the whole of this class is
/// keeping that answer honest — asking Apple on every launch rather than trusting
/// what was written to the Keychain, and listening for the revocation that can
/// arrive while the app is open.
///
/// That check is the reason this is not simply a boolean in the record. Somebody
/// who revokes Hourss in Settings ▸ Apple ID has said something, and an app that
/// keeps them signed in because it only ever read its own copy has not listened.
@Observable
@MainActor
final class AccountService {

    /// Signed in, signed out, or not yet known — and the third one is load-bearing.
    ///
    /// Asking Apple takes a moment. Without a state for "still asking", the gate
    /// has to guess during that moment, and guessing signed-out flashes a sign-in
    /// screen at somebody who is already signed in, every single launch.
    enum State: Equatable {
        case checking
        case signedOut
        case signedIn(Account)
    }

    private(set) var state: State = .checking

    /// Set while the Apple sheet is up, so the button can say so and refuse to
    /// raise a second one.
    private(set) var isSigningIn = false

    /// The last sign-in failure, phrased for the person who saw it. Nil after any
    /// success, and never set for a cancellation — deciding not to sign in is not
    /// an error and must not be reported as one.
    private(set) var failure: String?

    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    var isSignedIn: Bool { account != nil }
    var isChecking: Bool { state == .checking }

    private let store: AccountStore
    private let authorizer: AppleAuthorizing
    private let credentialState: AppleCredentialStateProviding

    /// Removed in `deinit`, which is not main-actor isolated — hence the explicit
    /// opt-out. `removeObserver` is safe from any thread.
    ///
    /// `@ObservationIgnored` is what makes that opt-out mean anything: without it
    /// the macro rewrites this into a computed property over hidden storage, and
    /// the isolation attribute lands on an accessor rather than on the box. It is
    /// also simply not observable state — no view redraws because a notification
    /// token changed.
    @ObservationIgnored
    private nonisolated(unsafe) var revocationObserver: NSObjectProtocol?

    init(store: AccountStore = KeychainAccountStore(),
         authorizer: AppleAuthorizing = AppleIDAuthorizer(),
         credentialState: AppleCredentialStateProviding = AppleIDCredentialState()) {
        self.store = store
        self.authorizer = authorizer
        self.credentialState = credentialState
    }

    deinit {
        if let revocationObserver {
            NotificationCenter.default.removeObserver(revocationObserver)
        }
    }

    // MARK: - Launch

    /// Work out where this person stands, and keep watching.
    ///
    /// Called once, from the app's root. Everything it does is idempotent, so a
    /// second call costs a Keychain read and another question to Apple rather
    /// than doing anything surprising.
    func start() async {
        observeRevocation()
        await restore()
    }

    /// Read the stored account back and check it is still good.
    private func restore() async {
        #if DEBUG
        if let forced = Self.launchArgumentAccount {
            // Deliberately not written to the store. A UI test that seeded an
            // account would otherwise leave it in the simulator's Keychain, where
            // it outlives the test and signs in every later run.
            state = .signedIn(forced)
            return
        }
        #endif

        // `try?` flattens the throw and the "nothing stored" into one nil, which
        // is right here: both mean there is nobody to check with Apple.
        guard let account = try? store.load() else {
            state = .signedOut
            return
        }

        switch await credentialState.credentialState(for: account.userIdentifier) {
        case .authorized:
            state = .signedIn(account)
        case .revoked, .notFound:
            // They withdrew it, or it was never Apple's to begin with. Either way
            // the stored copy is now a claim Apple will not stand behind.
            forget()
        case .transferred:
            // The app moved to another developer team, so the identifier is no
            // longer the one Apple would issue. Re-authorizing is the migration.
            forget()
        @unknown default:
            // A state this build has never heard of is not grounds for throwing
            // somebody out of an app that works offline.
            state = .signedIn(account)
        }
    }

    /// Sign out whenever Apple says the credential has gone, including while the
    /// app is open and on screen.
    private func observeRevocation() {
        guard revocationObserver == nil else { return }
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
    }

    // MARK: - Signing in

    /// Raise the Apple sheet, and keep whatever comes back.
    @discardableResult
    func signIn() async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        failure = nil
        defer { isSigningIn = false }

        do {
            let credential = try await authorizer.authorize()
            let account = merged(credential)
            // Stored before the state changes, so a Keychain that refuses the
            // write cannot leave somebody signed in for one launch only.
            try store.save(account)
            state = .signedIn(account)
            return true
        } catch {
            failure = Self.message(for: error)
            return false
        }
    }

    /// Reconcile what Apple just said with what is already known.
    ///
    /// Apple sends the name and the email on the *first* authorization for an
    /// Apple ID and never again — every later sign-in carries nil for both. So a
    /// straight overwrite quietly erases somebody's name the second time they
    /// sign in, and the erasure is permanent, because there is no second chance
    /// to be told. Absent means "not sent this time", never "cleared".
    private func merged(_ credential: AppleCredential) -> Account {
        // Only the same person's stored account may fill in the blanks. Somebody
        // signing in with a second Apple ID must not inherit the first one's name.
        let stored = try? store.load()
        let existing = stored?.userIdentifier == credential.userIdentifier ? stored : nil

        return Account(
            userIdentifier: credential.userIdentifier,
            fullName: credential.fullName ?? existing?.fullName,
            email: credential.email ?? existing?.email
        )
    }

    // MARK: - Signing out

    /// Sign out at this person's request.
    ///
    /// Their record is untouched. Nothing in it is keyed to the account — it was
    /// on this phone before there was one — and deleting somebody's history
    /// because they signed out would be a data loss dressed up as a session.
    func signOut() {
        forget()
    }

    /// Drop the account, from memory and from the Keychain.
    private func forget() {
        try? store.clear()
        failure = nil
        state = .signedOut
    }

    // MARK: - Errors

    /// What to put on the screen.
    ///
    /// Cancellation returns nil: the person closed the sheet, which is an outcome
    /// rather than a fault, and an app that scolds them for it is describing its
    /// own disappointment.
    private static func message(for error: Error) -> String? {
        guard let authorization = error as? ASAuthorizationError else {
            return "Sign in didn't finish. Please try again."
        }
        switch authorization.code {
        case .canceled:
            return nil
        case .notHandled, .notInteractive:
            return "Sign in couldn't be shown. Please try again."
        case .invalidResponse, .failed:
            return "Apple couldn't complete that sign in. Please try again."
        default:
            // Overwhelmingly this is a simulator or device with no Apple ID
            // signed in, which is unguessable from the error itself and is the
            // first thing worth checking.
            return "Sign in didn't finish. Check that you're signed in to Apple on this iPhone."
        }
    }

    #if DEBUG
    /// `-hourss-debug-account "Ada Lovelace"`.
    ///
    /// The Apple sheet cannot be driven from a UI test — it is another process,
    /// and it wants a real Apple ID — so without this every test that walks
    /// onboarding would stop at the account beat forever. Read straight from
    /// `ProcessInfo` and compiled out of any build that is not DEBUG, so a
    /// shipped binary has no path that can arrive signed in without Apple.
    private static var launchArgumentAccount: Account? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: Self.debugLaunchArgument),
              index + 1 < arguments.count else { return nil }
        return Account(
            userIdentifier: "debug.\(arguments[index + 1])",
            fullName: arguments[index + 1],
            email: nil
        )
    }

    static let debugLaunchArgument = "-hourss-debug-account"
    #endif
}
