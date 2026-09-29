import Foundation
import Security

/// The only thing NoeviaKit ever persists: the account's own sign-in for one server. That is
/// either a browser-equivalent session (`cowork_session` and `cowork_csrf`) or, after a device
/// sign-in (#555), this device's own access and refresh tokens. Never a password, and never a
/// service secret (Diary, tenant, provider or legacy `UI_AUTH_TOKEN` keys stay on the server).
public struct SessionCredential: Codable, Sendable, Equatable {
    /// Scheme, host and port of the server the session belongs to.
    public let serverOrigin: String
    public let sessionToken: String
    public let csrfToken: String
    /// The server marked the cookies `Secure`: they are only ever sent over https.
    public let secure: Bool
    /// Device-flow tokens. When present the client authenticates with `Authorization: Bearer`
    /// and sends no cookies, and the cookie fields are empty. Items saved before #555 have no
    /// such key and still decode.
    public let deviceTokens: DeviceTokens?

    public init(serverOrigin: String, sessionToken: String, csrfToken: String, secure: Bool) {
        self.serverOrigin = serverOrigin
        self.sessionToken = sessionToken
        self.csrfToken = csrfToken
        self.secure = secure
        self.deviceTokens = nil
    }

    /// A device sign-in's credential: tokens, no cookies.
    public init(serverOrigin: String, deviceTokens: DeviceTokens) {
        self.serverOrigin = serverOrigin
        self.sessionToken = ""
        self.csrfToken = ""
        self.secure = false
        self.deviceTokens = deviceTokens
    }
}

/// One device's tokens from `POST /api/auth/device/token` (apps/web/server/device-auth.cjs).
/// Both are opaque 256-bit values and the server keeps only their hashes. The access token lasts
/// an hour. The refresh token is single use: every refresh returns a new pair, and presenting a
/// spent refresh token again makes the server revoke this device entirely.
public struct DeviceTokens: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    /// When the access token stops working, by this device's clock.
    public let accessExpiresAt: Date

    public init(accessToken: String, refreshToken: String, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
    }
}

/// Where a session credential lives between launches. The app uses `KeychainCredentialStore`;
/// tests use `InMemoryCredentialStore`.
public protocol CredentialStore: Sendable {
    func load(serverOrigin: String) async throws -> SessionCredential?
    func save(_ credential: SessionCredential) async throws
    func delete(serverOrigin: String) async throws
}

/// Process-memory store for tests and for "don't remember me".
public actor InMemoryCredentialStore: CredentialStore {
    private var items: [String: SessionCredential] = [:]

    public init(_ initial: [SessionCredential] = []) {
        for credential in initial { items[credential.serverOrigin] = credential }
    }

    public func load(serverOrigin: String) async throws -> SessionCredential? { items[serverOrigin] }
    public func save(_ credential: SessionCredential) async throws { items[credential.serverOrigin] = credential }
    public func delete(serverOrigin: String) async throws { items[serverOrigin] = nil }
}

/// The Keychain, one generic-password item per server origin. Items are
/// `WhenUnlockedThisDeviceOnly` and never synchronised through iCloud Keychain.
///
/// By default this uses the data-protection Keychain, which needs a signed app with a
/// keychain access group; an unsigned command-line tool gets `errSecMissingEntitlement`
/// and should pass `useDataProtectionKeychain: false` (the login keychain).
public struct KeychainCredentialStore: CredentialStore {
    public let service: String
    public let useDataProtectionKeychain: Bool

    public init(service: String = "work.daserver.noevia.session", useDataProtectionKeychain: Bool = true) {
        self.service = service
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    private func query(_ origin: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: origin,
            kSecAttrSynchronizable as String: false,
        ]
        if useDataProtectionKeychain { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    public func load(serverOrigin: String) async throws -> SessionCredential? {
        var q = query(serverOrigin)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status) }
        do { return try JSONDecoder().decode(SessionCredential.self, from: data) }
        catch {
            // An unreadable item is useless; remove it rather than fail every launch.
            try await delete(serverOrigin: serverOrigin)
            return nil
        }
    }

    public func save(_ credential: SessionCredential) async throws {
        let data = try JSONEncoder().encode(credential)
        let q = query(credential.serverOrigin)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add.merge(update) { _, new in new }
            add[kSecAttrLabel as String] = "Noevia session (\(credential.serverOrigin))"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.failure(status) }
    }

    public func delete(serverOrigin: String) async throws {
        let status = SecItemDelete(query(serverOrigin) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.failure(status) }
    }

    private static func failure(_ status: OSStatus) -> NoeviaError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return .credentialStore(message)
    }
}
