import Foundation
import AuthenticationServices
import UIKit

/// Sign in with Apple, as one awaitable call.
///
/// `ASAuthorizationController` is a delegate API that must be kept alive by
/// somebody for the whole time the sheet is up, and whose two outcomes arrive at
/// two different methods. Everything in this file exists to turn that into one
/// `try await` — so the screens that sign somebody in read as what they do rather
/// than as callback bookkeeping.
@MainActor
final class AppleIDAuthorizer: AppleAuthorizing {

    /// The controller and its delegate are held here for the life of the request.
    ///
    /// Neither is retained by the system while the sheet is up: drop them and the
    /// delegate is deallocated mid-flight, the continuation is never resumed, and
    /// the task awaiting it hangs forever behind a sheet that has already closed.
    private var inFlight: (controller: ASAuthorizationController, session: AppleAuthorizationSession)?

    func authorize() async throws -> AppleCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Both are requests, not guarantees. A person can decline the name and
        // relay the email, and Hourss has to work when they do.
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])

        defer { inFlight = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = AppleAuthorizationSession(continuation: continuation)
            controller.delegate = session
            controller.presentationContextProvider = session
            inFlight = (controller, session)
            controller.performRequests()
        }
    }
}

/// The delegate, deliberately not actor-isolated.
///
/// It is a separate object from the authorizer rather than the authorizer itself
/// conforming, because `ASAuthorizationControllerDelegate` is an Objective-C
/// protocol whose isolation is the SDK's to declare, and a `@MainActor` class
/// trying to witness it is a compile error waiting on an SDK revision. A
/// non-isolated witness satisfies the requirement whichever way Apple annotates
/// it, and everything this object touches is either Sendable or reached through
/// an explicit hop.
private final class AppleAuthorizationSession: NSObject, @unchecked Sendable {
    /// Resumed exactly once, by whichever of the two delegate methods fires.
    private let continuation: CheckedContinuation<AppleCredential, Error>

    init(continuation: CheckedContinuation<AppleCredential, Error>) {
        self.continuation = continuation
    }
}

extension AppleAuthorizationSession: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            // Only an Apple ID request was made, so this cannot happen — and if
            // the SDK ever makes it happen, failing loudly beats signing somebody
            // in as nobody.
            continuation.resume(throwing: AccountError.unexpectedCredential)
            return
        }

        continuation.resume(returning: AppleCredential(
            userIdentifier: credential.user,
            fullName: credential.fullName.flatMap(Self.format),
            email: credential.email
        ))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }

    /// Apple hands over components, not a string, because name order is not
    /// universal. The formatter is what knows that; joining the fields by hand
    /// would put a surname in the wrong place in most of the world.
    private static func format(_ components: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let name = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty means they declined the name. That is a real answer and must stay
        // distinguishable from a name, rather than becoming one made of nothing.
        return name.isEmpty ? nil : name
    }
}

extension AppleAuthorizationSession: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Called on the main thread by AuthenticationServices. `assumeIsolated`
        // states that rather than hopping, because returning a window from an
        // async hop is not possible and a detached window would present nothing.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
        }
    }
}

/// What can go wrong that is Hourss's own fault rather than Apple's.
enum AccountError: Error, Equatable {
    case unexpectedCredential
}
