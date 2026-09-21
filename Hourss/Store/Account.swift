import Foundation
import AuthenticationServices

/// Who this record belongs to.
///
/// Three fields, and only the first one is Apple's answer to a question. The
/// identifier is stable for this Apple ID against this team and is the only thing
/// that identifies anybody; the name and the email are a courtesy Apple extends
/// exactly once and never again, which is why they are stored beside it rather
/// than re-read.
///
/// There is no token here and no session, because there is nothing to hold a
/// session against. Hourss keeps its record on the phone, so signing in names the
/// record and says who it is for — it does not fetch it.
struct Account: Codable, Equatable, Sendable {
    /// Apple's stable user identifier. Scoped to the developer team, so it is not
    /// an Apple ID and cannot be used to find this person anywhere else.
    let userIdentifier: String

    /// As Apple formatted it at first authorization, if they chose to share it.
    var fullName: String?

    /// Real or relayed — `@privaterelay.appleid.com` — and Hourss cannot tell the
    /// difference, which is the point of the feature and fine, since nothing here
    /// ever sends mail.
    var email: String?

    /// What You puts at the top of the screen. Empty rather than a placeholder:
    /// the caller decides what to show for somebody who shared no name.
    var displayName: String { fullName ?? "" }
}

/// What comes back from one trip through the Apple sheet.
///
/// Distinct from `Account` because it is the raw answer rather than the stored
/// one, and the difference matters: `fullName` here is nil on every sign-in after
/// the first, and treating that nil as the truth is how an app forgets somebody's
/// name. `AccountService` is where the two are reconciled.
struct AppleCredential: Sendable, Equatable {
    let userIdentifier: String
    let fullName: String?
    let email: String?
}

/// Where the account is kept between launches.
///
/// Not in `Record`. The record is the person's own history — exportable, and
/// deletable by them at any time — and an identity that lives inside the thing it
/// identifies disappears the moment they clear it. The Keychain also survives a
/// reinstall, which is the only way to keep a name Apple will never send twice.
protocol AccountStore: Sendable {
    func load() throws -> Account?
    func save(_ account: Account) throws
    func clear() throws
}

/// The account as one Keychain item.
///
/// `ThisDeviceOnly` on purpose. A synced item would restore onto a second phone
/// signed in as somebody else and assert that Hourss's local record belonged to
/// them — and since the credential check below would then fail, the only effect
/// available to it is being wrong for one launch.
struct KeychainAccountStore: AccountStore {
    /// Distinct from the bundle identifier so that renaming the app does not
    /// orphan the item, and legible in a Keychain dump, where an opaque key would
    /// be indistinguishable from a leak.
    let service: String
    let key: String

    init(service: String = "com.hourss.app.account", key: String = "apple") {
        self.service = service
        self.key = key
    }

    enum Failure: Error, Equatable {
        /// Carries the raw `OSStatus`, because "saving failed" is not something
        /// anybody can act on and the code is what a bug report needs.
        case keychain(OSStatus)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func load() throws -> Account? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Failure.keychain(status)
        }
        // A stored item that will not decode is a shape change, not a signed-in
        // person. Treating it as absent asks them to sign in again, which costs
        // one tap; treating it as an error would wedge the gate with no way past.
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    func save(_ account: Account) throws {
        let data = try JSONEncoder().encode(account)

        // Update first, because adding over an existing item fails rather than
        // replacing it, and the second sign-in is the common case.
        let updated = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Failure.keychain(updated) }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        // Deleting what is not there is the state the caller wanted.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }
}

/// An account store held in memory, for tests and for the debug override.
///
/// The Keychain is process-wide and outlives the simulator run that wrote to it,
/// so a test written against the real one would pass or fail on what the last one
/// left behind — and would leave a signed-in account on the machine afterwards.
final class InMemoryAccountStore: AccountStore, @unchecked Sendable {
    private let lock = NSLock()
    private var account: Account?

    init(_ account: Account? = nil) { self.account = account }

    func load() throws -> Account? { lock.withLock { account } }
    func save(_ account: Account) throws { lock.withLock { self.account = account } }
    func clear() throws { lock.withLock { account = nil } }
}

/// One trip through the Apple sheet.
///
/// A protocol because `ASAuthorizationController` cannot run without a window and
/// a human, so everything this app does *with* a credential — merging a name,
/// storing it, deciding what the gate shows — would otherwise be untestable. The
/// one implementation that talks to Apple lives in `AppleIDAuthorizer`.
@MainActor
protocol AppleAuthorizing {
    func authorize() async throws -> AppleCredential
}

/// Whether Apple still recognises a stored identifier.
///
/// Separated from authorizing for the same reason and a sharper one: this is the
/// check that runs on every launch, so it is the check most likely to be wrong in
/// a way nobody notices — a person who revoked Hourss in Settings staying signed
/// in forever.
@MainActor
protocol AppleCredentialStateProviding {
    func credentialState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState
}

/// The real check.
struct AppleIDCredentialState: AppleCredentialStateProviding {
    func credentialState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        // A failed check is not a revocation. The call reaches a daemon that can
        // be busy or unreachable, and answering "revoked" to a network problem
        // would sign somebody out of an app that works entirely offline.
        (try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userIdentifier)) ?? .authorized
    }
}
