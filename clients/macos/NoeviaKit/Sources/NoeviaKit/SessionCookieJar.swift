import Foundation

/// An in-memory cookie jar for exactly one server origin.
///
/// The URLSession is configured with no system cookie storage, so cookies never reach the
/// shared on-disk jar. This jar honours the attributes the core sets
/// (apps/web/server/auth.cjs `issueSession`/`logout`): `Max-Age=0` removes a cookie, and a
/// `Secure` cookie is only sent over https.
struct SessionCookieJar: Sendable {
    static let sessionCookie = "cowork_session"
    static let csrfCookie = "cowork_csrf"

    struct Cookie: Sendable, Equatable {
        var value: String
        var secure: Bool
    }

    private(set) var cookies: [String: Cookie] = [:]

    var sessionToken: String? { cookies[Self.sessionCookie]?.value }
    var csrfToken: String? { cookies[Self.csrfCookie]?.value }
    var hasSession: Bool { sessionToken != nil && csrfToken != nil }
    var sessionIsSecure: Bool { cookies[Self.sessionCookie]?.secure ?? false }

    mutating func clear() { cookies.removeAll() }

    mutating func restore(_ credential: SessionCredential) {
        cookies[Self.sessionCookie] = Cookie(value: credential.sessionToken, secure: credential.secure)
        cookies[Self.csrfCookie] = Cookie(value: credential.csrfToken, secure: credential.secure)
    }

    func credential(serverOrigin: String) -> SessionCredential? {
        guard let session = cookies[Self.sessionCookie], let csrf = cookies[Self.csrfCookie] else { return nil }
        return SessionCredential(serverOrigin: serverOrigin, sessionToken: session.value, csrfToken: csrf.value, secure: session.secure || csrf.secure)
    }

    /// Applies every `Set-Cookie` in the response. Returns true when the jar changed.
    @discardableResult
    mutating func ingest(_ response: HTTPURLResponse, url: URL, now: Date = Date()) -> Bool {
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let k = key as? String, let v = value as? String { fields[k] = v }
        }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        var changed = false
        for cookie in parsed {
            let expired = cookie.expiresDate.map { $0 <= now } ?? false
            if expired || cookie.value.isEmpty {
                if cookies.removeValue(forKey: cookie.name) != nil { changed = true }
            } else {
                let next = Cookie(value: cookie.value, secure: cookie.isSecure)
                if cookies[cookie.name] != next { cookies[cookie.name] = next; changed = true }
            }
        }
        return changed
    }

    /// The `Cookie` request header for `url`, or nil when nothing may be sent.
    func header(for url: URL) -> String? {
        let https = url.scheme?.lowercased() == "https"
        let parts = cookies
            .filter { !$0.value.secure || https }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.value)" }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}
