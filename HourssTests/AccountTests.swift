import Testing
import Foundation
import AuthenticationServices
@testable import Hourss

/// Sign in with Apple, against no server.
///
/// Everything worth testing here is about a claim outliving the thing that
/// justified it. Hourss has no session to expire, so the only things standing
/// between a stale credential and somebody's record are the launch check, the
/// revocation notice, and the rule that Apple's silence about a name is not the
/// same as Apple saying there isn't one — and those are exactly what follows.
@Suite("The account")
@MainActor
struct AccountTests {

    // MARK: - Doubles

    /// One trip through the Apple sheet, decided in advance.
    private final class StubAuthorizer: AppleAuthorizing {
        var result: Result<AppleCredential, Error>
        private(set) var calls = 0

        init(_ result: Result<AppleCredential, Error>) { self.result = result }

        func authorize() async throws -> AppleCredential {
            calls += 1
            return try result.get()
        }
    }

    private struct StubCredentialState: AppleCredentialStateProviding {
        let state: ASAuthorizationAppleIDProvider.CredentialState
        func credentialState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
            state
        }
    }

    private func makeService(
        stored: Account? = nil,
        credential: Result<AppleCredential, Error> = .success(AppleCredential(
            userIdentifier: "apple.001", fullName: "Ada Lovelace", email: "ada@example.com"
        )),
        state: ASAuthorizationAppleIDProvider.CredentialState = .authorized
    ) -> (AccountService, InMemoryAccountStore) {
        let store = InMemoryAccountStore(stored)
        let service = AccountService(
            store: store,
            authorizer: StubAuthorizer(credential),
            credentialState: StubCredentialState(state: state)
        )
        return (service, store)
    }

    private static let ada = Account(
        userIdentifier: "apple.001", fullName: "Ada Lovelace", email: "ada@example.com"
    )

    // MARK: - The launch check

    @Test("Nothing stored means signed out")
    func emptyStoreSignsOut() async {
        let (service, _) = makeService()
        #expect(service.isChecking, "The state before the check has to be distinguishable from its answer")

        await service.start()

        #expect(service.state == .signedOut)
        #expect(service.account == nil)
    }

    @Test("A stored account Apple still recognises opens the app")
    func authorizedStoredAccountSignsIn() async {
        let (service, _) = makeService(stored: Self.ada, state: .authorized)

        await service.start()

        #expect(service.isSignedIn)
        #expect(service.account?.fullName == "Ada Lovelace")
    }

    /// The whole reason the check exists. Somebody who withdraws Hourss in
    /// Settings ▸ Apple ID has said something, and an app that reads only its own
    /// copy of the answer has not heard it.
    @Test("A revoked credential signs out and clears the stored account",
          arguments: [ASAuthorizationAppleIDProvider.CredentialState.revoked,
                      .notFound,
                      .transferred])
    func withdrawnCredentialSignsOut(_ state: ASAuthorizationAppleIDProvider.CredentialState) async {
        let (service, store) = makeService(stored: Self.ada, state: state)

        await service.start()

        #expect(service.state == .signedOut)
        #expect(try! store.load() == nil, "A credential Apple disowns must not survive on disk")
    }

    @Test("Revocation while the app is open signs out")
    func revocationNotificationSignsOut() async throws {
        let (service, store) = makeService(stored: Self.ada, state: .authorized)
        await service.start()
        #expect(service.isSignedIn)

        NotificationCenter.default.post(
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil
        )
        // The observer is delivered on the main queue, so the post has to be let
        // through a turn of the loop before it can be asserted on.
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.state == .signedOut)
        #expect(try store.load() == nil)
    }

    // MARK: - Signing in

    @Test("Signing in keeps what Apple sent")
    func signInStoresTheAccount() async throws {
        let (service, store) = makeService()

        let succeeded = await service.signIn()

        #expect(succeeded)
        #expect(service.account?.userIdentifier == "apple.001")
        #expect(try store.load()?.email == "ada@example.com")
        #expect(service.failure == nil)
    }

    /// Apple sends the name once per Apple ID, ever. Every later sign-in carries
    /// nil, so an overwrite erases it permanently — there is no second chance to
    /// be told.
    @Test("A later sign-in without a name does not erase the one Apple sent first")
    func nameSurvivesASecondSignIn() async throws {
        // The store already holds what the first sign-in captured, which is the
        // situation every sign-in after the first one is in.
        let (service, store) = makeService(
            stored: Self.ada,
            credential: .success(AppleCredential(
                userIdentifier: "apple.001", fullName: nil, email: nil
            ))
        )

        await service.signIn()

        #expect(service.account?.fullName == "Ada Lovelace")
        #expect(service.account?.email == "ada@example.com")
        #expect(try store.load()?.fullName == "Ada Lovelace")
    }

    /// The other half of that rule: filling in blanks is only ever allowed from
    /// the *same* person's stored account.
    @Test("A different Apple ID does not inherit the previous name")
    func aDifferentAccountStartsBlank() async throws {
        let store = InMemoryAccountStore(Self.ada)
        let service = AccountService(
            store: store,
            authorizer: StubAuthorizer(.success(
                AppleCredential(userIdentifier: "apple.002", fullName: nil, email: nil)
            )),
            credentialState: StubCredentialState(state: .authorized)
        )

        await service.signIn()

        #expect(service.account?.userIdentifier == "apple.002")
        #expect(service.account?.fullName == nil, "Ada's name must not follow somebody else's Apple ID")
    }

    @Test("Backing out of the sheet is not an error")
    func cancellationReportsNothing() async {
        let (service, store) = makeService(credential: .failure(ASAuthorizationError(.canceled)))
        // Through the launch check first: the sheet is only reachable from the
        // gate, and the gate is only on screen once the check has answered.
        await service.start()

        let succeeded = await service.signIn()

        #expect(succeeded == false)
        #expect(service.state == .signedOut)
        #expect(service.failure == nil, "Deciding not to sign in is an outcome, not a fault")
        #expect(try! store.load() == nil)
    }

    @Test("A real failure says so")
    func failureIsReported() async {
        let (service, _) = makeService(credential: .failure(ASAuthorizationError(.failed)))
        await service.start()

        let succeeded = await service.signIn()

        #expect(succeeded == false)
        #expect(service.failure != nil)
        #expect(service.isSigningIn == false, "The button has to come back")
    }

    // MARK: - Signing out

    @Test("Signing out forgets the account and nothing else")
    func signOutClearsTheAccount() async throws {
        let (service, store) = makeService(stored: Self.ada, state: .authorized)
        await service.start()

        service.signOut()

        #expect(service.state == .signedOut)
        #expect(try store.load() == nil)
    }
}

/// The two things the account asks of the record.
@Suite("The record's side of the account")
@MainActor
struct AccountRecordTests {

    @Test("Apple's name fills a blank and never overwrites a choice")
    func adoptingANameOnlyFillsABlank() {
        let store = HourssStore(repository: InMemoryRecordRepository())

        store.adoptDisplayName("Ada Lovelace")
        #expect(store.profile.displayName == "Ada Lovelace")

        store.adoptDisplayName("Someone Else")
        #expect(store.profile.displayName == "Ada Lovelace",
                "Apple's name is a starting value, not the authority on what somebody is called")
    }

    @Test("A name of nothing but spaces is not a name")
    func blankNamesAreRefused() {
        let store = HourssStore(repository: InMemoryRecordRepository())
        store.adoptDisplayName("   ")
        #expect(store.profile.displayName.isEmpty)
    }

    /// Hourss has no server, so this *is* the deletion — there is no copy
    /// elsewhere that a flag could be reconciled against later.
    @Test("Deleting everything leaves nothing on disk")
    func deletionClearsTheRecord() throws {
        let repository = InMemoryRecordRepository()
        let store = HourssStore(repository: repository)
        let activity = store.activities[0]
        let session = store.startSession(activityId: activity.id)
        store.stopSession(session.id)
        store.saveReflection(sessionId: session.id, feeling: 4, performance: 3, note: "kept")
        store.profile.displayName = "Ada"
        store.hasCompletedOnboarding = true
        store.persist()

        store.deleteEverything()

        #expect(store.sessions.isEmpty)
        #expect(store.reflections.isEmpty)
        #expect(store.profile.displayName.isEmpty)
        #expect(store.hasCompletedOnboarding == false,
                "Leaving onboarding done drops somebody into an app with no activities and no priorities")

        let written = try repository.load()
        #expect(written.sessions.isEmpty)
        #expect(written.reflections.isEmpty)
        #expect(written.profile.displayName.isEmpty)
    }
}
