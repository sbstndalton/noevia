import Foundation

/// Every failure NoeviaKit surfaces. Messages are written for a person, not a log.
public enum NoeviaError: Error, Sendable, Equatable {
    /// The server address is not an absolute http(s) origin.
    case invalidServerURL(String)
    /// Plain http to a public host. The core accepts http only for private-network origins
    /// (apps/web/server/auth.cjs `isAcceptablePublicOrigin`); a password must not cross the
    /// internet unencrypted, so the client refuses too.
    case insecureServerURL(String)
    /// The core declared an API major this client does not support.
    case unsupportedAPIMajor(served: String, supported: [String])
    /// `/api/ready` answered `ready: false` (the core is still starting).
    case serverNotReady
    /// 401 on an authenticated route: no valid session. The stored session was removed.
    case unauthorised
    /// 401 from password sign-in (wrong username or password, or a disabled account;
    /// the server deliberately does not say which).
    case signInFailed
    /// 429: too many attempts.
    case rateLimited
    /// 403: not permitted, or a CSRF or Origin check failed. Carries the server's message.
    case forbidden(String)
    /// The server issued a `Secure` session cookie but the client talks plain http, so the
    /// cookie could never be sent back. Use the server's https address.
    case insecureSessionCookie
    /// Sign-in succeeded but the response lacked the `cowork_session`/`cowork_csrf` cookies.
    case missingSessionCookies
    /// Any other non-2xx answer. `message` is the `{ error }` body when present.
    case http(status: Int, message: String?)
    /// A transport failure on a request that was not retried (a non-idempotent request).
    case transport(String)
    /// Idempotent retries were exhausted; the connection state is now `.offline`.
    case offline(attempts: Int, lastError: String)
    /// The server answered something that is not the documented shape.
    case invalidResponse(String)
    /// The credential store (Keychain) failed.
    case credentialStore(String)
}

extension NoeviaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidServerURL(let s):
            return "“\(s)” is not a server address. Enter one like https://noevia.example.com."
        case .insecureServerURL(let s):
            return "“\(s)” uses plain http on a public address. Use https, or a private-network address."
        case .unsupportedAPIMajor(let served, let supported):
            return "This Noevia server uses API version \(served); this app supports version \(supported.joined(separator: ", ")). Update the app or the server so both use the same version."
        case .serverNotReady:
            return "The Noevia server is still starting."
        case .unauthorised:
            return "You are signed out. Sign in again."
        case .signInFailed:
            return "Sign-in failed. Check the username and password."
        case .rateLimited:
            return "Too many attempts. Wait a few minutes and try again."
        case .forbidden(let message):
            return "The server refused this request (\(message))."
        case .insecureSessionCookie:
            return "The server only allows its session over https. Connect with its https address."
        case .missingSessionCookies:
            return "The server did not start a session."
        case .http(let status, let message):
            return message.map { "The server answered \(status): \($0)" } ?? "The server answered \(status)."
        case .transport(let description):
            return "The request did not reach the server (\(description)). It was not retried."
        case .offline(let attempts, let lastError):
            return "The server could not be reached after \(attempts) attempts (\(lastError))."
        case .invalidResponse(let detail):
            return "The server answered in an unexpected format (\(detail))."
        case .credentialStore(let detail):
            return "The saved sign-in could not be read or written (\(detail))."
        }
    }
}
