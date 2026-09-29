import Foundation
import Testing
@testable import NoeviaKit

enum TestCredentials {
    static func stored(for server: StubServer, session: String = "synthetic-session-token", csrf: String = "synthetic-csrf-token") -> SessionCredential {
        SessionCredential(serverOrigin: server.origin.absoluteString, sessionToken: session, csrfToken: csrf, secure: true)
    }
}

extension StubServer {
    /// A ready v1 core whose password sign-in succeeds with auth.cjs's cookies.
    func readyWithLogin(secureCookies: Bool = true) {
        on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        on("POST", "/api/auth/login/password",
           .json(fixture: "auth-login-password__auth.cjs-passwordLogin.json", headers: CoreCookies.issued(secure: secureCookies)))
    }
}

@Suite("Session authentication and CSRF")
struct AuthTests {
    @Test("Password sign-in keeps the cookies in memory and the session in the store, never the password")
    func signInStoresSession() async throws {
        let server = StubServer()
        server.readyWithLogin()
        let store = InMemoryCredentialStore()
        let client = try server.client(store: store)

        let user = try await client.signIn(username: "synthetic", password: "synthetic-password-1")

        #expect(user.username == "synthetic")
        #expect(user.displayName == "Synthetic Owner")
        #expect(!user.isAdmin)
        guard case .connected(let info) = await client.state else {
            Issue.record("expected connected, got \(await client.state)")
            return
        }
        #expect(info.releaseVersion == "0123abc")

        let login = try #require(server.requests("POST", "/api/auth/login/password").first)
        let body = try #require(login.body)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(sent == ["username": "synthetic", "password": "synthetic-password-1"])
        #expect(login.header("Content-Type") == "application/json")
        // auth.cjs originValid() admits a request without Origin; the client never forges one.
        #expect(login.header("Origin") == nil)
        // Negotiation happened first.
        #expect(server.requests.first?.path == "/api/ready")

        let saved = try #require(try await store.load(serverOrigin: server.origin.absoluteString))
        #expect(saved.sessionToken == "synthetic-session-token")
        #expect(saved.csrfToken == "synthetic-csrf-token")
        #expect(saved.secure)
        let encoded = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        #expect(!encoded.contains("synthetic-password-1"))
    }

    @Test("Reads carry the session cookies but no CSRF header; writes carry X-CSRF-Token")
    func csrfOnlyOnMutations() async throws {
        let server = StubServer()
        server.readyWithLogin()
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        server.on("POST", "/api/auth/logout", .json(200, body: #"{"ok":true}"#, headers: CoreCookies.cleared))
        let store = InMemoryCredentialStore()
        let client = try server.client(store: store)
        try await client.signIn(username: "synthetic", password: "synthetic-password-1")

        _ = try await client.workspace()
        let read = try #require(server.requests("GET", "/api/workspace").first)
        #expect(read.header("Cookie") == "cowork_csrf=synthetic-csrf-token; cowork_session=synthetic-session-token")
        #expect(read.header("X-CSRF-Token") == nil)

        try await client.signOut()
        let write = try #require(server.requests("POST", "/api/auth/logout").first)
        // index.cjs csrfValid(): header == cowork_csrf cookie == the session's csrf hash.
        #expect(write.header("X-CSRF-Token") == "synthetic-csrf-token")
        #expect(write.header("Cookie")?.contains("cowork_csrf=synthetic-csrf-token") == true)
        #expect(write.header("Cookie")?.contains("cowork_session=synthetic-session-token") == true)

        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.state == .unauthorised)
        #expect(await client.user == nil)
        // Signed out locally: no request is made without a session.
        await #expect(throws: NoeviaError.unauthorised) { _ = try await client.workspace() }
        #expect(server.requests("GET", "/api/workspace").count == 1)
    }

    @Test("A rejected password is signInFailed, not retried, and stores nothing")
    func signInRejected() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("POST", "/api/auth/login/password", .json(401, fixture: "error-signin__auth.cjs-passwordLogin.json"))
        let store = InMemoryCredentialStore()
        let client = try server.client(store: store)

        await #expect(throws: NoeviaError.signInFailed) {
            try await client.signIn(username: "synthetic", password: "wrong-password-1")
        }
        #expect(server.requests("POST", "/api/auth/login/password").count == 1)
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.state == .unauthorised)
    }

    @Test("Rate-limited and Origin-refused sign-ins surface typed errors", arguments: [
        (429, #"{"error":"sign-in failed"}"#, NoeviaError.rateLimited),
        (403, #"{"error":"origin not allowed"}"#, NoeviaError.forbidden("origin not allowed")),
    ])
    func signInRefusals(status: Int, body: String, expected: NoeviaError) async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("POST", "/api/auth/login/password", .json(status, body: body))
        let client = try server.client()

        await #expect(throws: expected) {
            try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        }
    }

    @Test("A Secure session cookie over plain http is refused instead of silently failing later")
    func secureCookieOverHTTP() async throws {
        let server = StubServer(origin: URL(string: "http://noevia-lan-\(UUID().uuidString.prefix(8).lowercased())")!)
        server.readyWithLogin(secureCookies: true)
        let store = InMemoryCredentialStore()
        let client = try server.client(store: store)

        await #expect(throws: NoeviaError.insecureSessionCookie) {
            try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        }
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
    }

    @Test("A 200 sign-in without session cookies is an error, and an earlier session is kept")
    func signInWithoutCookies() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json"))
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        server.on("POST", "/api/auth/login/password", .json(fixture: "auth-login-password__auth.cjs-passwordLogin.json"))
        let client = try server.client(store: InMemoryCredentialStore([TestCredentials.stored(for: server, session: "earlier")]))
        _ = try await client.restoreSession()

        await #expect(throws: NoeviaError.missingSessionCookies) {
            try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        }
        _ = try await client.workspace()
        #expect(server.requests("GET", "/api/workspace").first?.header("Cookie")?.contains("cowork_session=earlier") == true)
    }

    @Test("Non-Secure cookies on a private http address work")
    func plainCookiesOnLAN() async throws {
        let server = StubServer(origin: URL(string: "http://noevia-lan-\(UUID().uuidString.prefix(8).lowercased())")!)
        server.readyWithLogin(secureCookies: false)
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        let client = try server.client()

        try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        _ = try await client.workspace()

        #expect(server.requests("GET", "/api/workspace").first?.header("Cookie")?.contains("cowork_session=") == true)
    }

    @Test("An existing session is restored from the store and checked with /api/auth/session")
    func restoresExistingSession() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json"))
        let client = try server.client(store: InMemoryCredentialStore([TestCredentials.stored(for: server)]))

        let user = try await client.restoreSession()

        #expect(user?.id == "7b0c2f6e-1111-4a4a-9c9c-000000000001")
        let check = try #require(server.requests("GET", "/api/auth/session").first)
        #expect(check.header("Cookie") == "cowork_csrf=synthetic-csrf-token; cowork_session=synthetic-session-token")
        guard case .connected = await client.state else {
            Issue.record("expected connected, got \(await client.state)")
            return
        }
    }

    @Test("With nothing stored, restore returns nil without asking the server")
    func restoreWithoutSession() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        let client = try server.client()

        #expect(try await client.restoreSession() == nil)
        #expect(server.requests("GET", "/api/auth/session").isEmpty)
        #expect(await client.state == .unauthorised)
    }

    @Test("401 moves to unauthorised and deletes the stored session")
    func unauthorisedDropsSession() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json"))
        server.on("GET", "/api/workspace", .json(401, fixture: "error-unauthorized__http.cjs.json", headers: ["WWW-Authenticate": #"Bearer realm="cowork""#]))
        let store = InMemoryCredentialStore([TestCredentials.stored(for: server)])
        let client = try server.client(store: store)
        _ = try await client.restoreSession()

        await #expect(throws: NoeviaError.unauthorised) { _ = try await client.workspace() }

        #expect(await client.state == .unauthorised)
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(server.requests("GET", "/api/workspace").count == 1, "401 is not retried")
        // A later restore finds nothing and does not replay the dead session.
        #expect(try await client.restoreSession() == nil)
    }

    @Test("A stored session the server no longer accepts restores to nil")
    func expiredStoredSession() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(401, fixture: "error-unauthorized__http.cjs.json"))
        let store = InMemoryCredentialStore([TestCredentials.stored(for: server)])
        let client = try server.client(store: store)

        #expect(try await client.restoreSession() == nil)
        #expect(await client.state == .unauthorised)
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
    }

    @Test("A CSRF refusal on sign-out is reported, and the local session is still removed")
    func csrfRefusalOnSignOut() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json"))
        server.on("POST", "/api/auth/logout", .json(403, fixture: "error-csrf__index.cjs.json"))
        let store = InMemoryCredentialStore([TestCredentials.stored(for: server)])
        let client = try server.client(store: store)
        _ = try await client.restoreSession()

        await #expect(throws: NoeviaError.forbidden("invalid CSRF token")) { try await client.signOut() }

        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.state == .unauthorised)
    }
}

@Suite("Cookie jar")
struct CookieJarTests {
    let url = URL(string: "https://noevia.example.com/api/auth/login/password")!

    func response(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test("auth.cjs issueSession cookies are parsed, and logout's Max-Age=0 clears them")
    func issueAndClear() {
        var jar = SessionCookieJar()
        let changed = jar.ingest(response(CoreCookies.issued()), url: url)
        #expect(changed)
        #expect(jar.sessionToken == "synthetic-session-token")
        #expect(jar.csrfToken == "synthetic-csrf-token")
        #expect(jar.sessionIsSecure)

        jar.ingest(response(CoreCookies.cleared), url: url)
        #expect(!jar.hasSession)
        #expect(jar.header(for: url) == nil)
    }

    @Test("Secure cookies are withheld from plain http")
    func secureWithheld() {
        var jar = SessionCookieJar()
        jar.ingest(response(CoreCookies.issued()), url: url)
        #expect(jar.header(for: URL(string: "http://noevia.example.com/api/workspace")!) == nil)
        #expect(jar.header(for: URL(string: "https://noevia.example.com/api/workspace")!) != nil)
    }
}
