import Foundation
import Testing
@testable import NoeviaKit

// Device sign-in (#555) against the shapes apps/web/server/device-auth.cjs really writes: every
// device fixture is produced by scripts/generate-fixtures.cjs running that module.

extension StubServer {
    /// A ready v1 core that offers device sign-in and answers the token endpoint with `polls`.
    func readyForDeviceSignIn(_ polls: StubReply...) {
        on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        on("POST", "/api/auth/device/code", .json(fixture: "device-code__device-auth.cjs-start.json"))
        on("GET", "/api/auth/session", .json(fixture: "auth-session-device__routes-device-auth.cjs.json"))
        if !polls.isEmpty { on("POST", "/api/auth/device/token", replies: polls) }
    }
}

enum DeviceFixtures {
    static let pending = StubReply.json(400, fixture: "device-pending__device-auth.cjs-token.json")
    static let slowDown = StubReply.json(400, fixture: "device-slow-down__device-auth.cjs-token.json")
    static let denied = StubReply.json(400, fixture: "device-denied__device-auth.cjs-token.json")
    static let expired = StubReply.json(400, fixture: "device-expired__device-auth.cjs-token.json")
    static let issued = StubReply.json(fixture: "device-token__device-auth.cjs-token.json")
    static let rotated = StubReply.json(fixture: "device-token-rotated__device-auth.cjs-token.json")
    static let reused = StubReply.json(400, fixture: "device-refresh-reuse__device-auth.cjs-token.json")

    static func stored(for server: StubServer, access: String = "nva_synthetic-access-1", refresh: String = "nvr_synthetic-refresh-1", expires: Date = .distantFuture) -> SessionCredential {
        SessionCredential(serverOrigin: server.origin.absoluteString, deviceTokens: DeviceTokens(accessToken: access, refreshToken: refresh, accessExpiresAt: expires))
    }
}

private func json(_ data: Data?) throws -> [String: String] {
    let body = try #require(data)
    let object = try JSONSerialization.jsonObject(with: body)
    return try #require(object as? [String: String])
}

@Suite("Device sign-in (#555)")
struct DeviceAuthTests {
    @Test("Code, pending, slow_down, approval: the device then uses only its bearer token")
    func fullDeviceFlow() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.pending, DeviceFixtures.slowDown, DeviceFixtures.issued)
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        server.on("POST", "/api/auth/logout", .json(200, body: #"{"ok":true}"#))
        let store = InMemoryCredentialStore()
        let sleeps = SleepRecorder()
        let client = try server.client(store: store, sleeps: sleeps)

        let authorization = try await client.startDeviceSignIn(clientName: "Synthetic Mac")
        #expect(authorization.userCode == "BCDF-GHJK")
        #expect(authorization.verificationURL.absoluteString == "https://noevia.example.test/device")
        #expect(authorization.verificationURLComplete?.absoluteString == "https://noevia.example.test/device?code=BCDF-GHJK")
        #expect(authorization.interval == .seconds(5))
        #expect(authorization.expiresIn == .seconds(600))
        let start = try #require(server.requests("POST", "/api/auth/device/code").first)
        #expect(try json(start.body) == ["client_name": "Synthetic Mac"])
        #expect(start.header("Authorization") == nil && start.header("Cookie") == nil && start.header("Origin") == nil)

        let user = try await client.completeDeviceSignIn(authorization)
        #expect(user.id == "7b0c2f6e-1111-4a4a-9c9c-000000000001")
        #expect(!user.isAdmin, "a device token never acts as an administrator")
        // RFC 8628: wait the interval before each poll, and 5 s longer after slow_down.
        #expect(await sleeps.delays == [.seconds(5), .seconds(5), .seconds(10)])
        let polls = server.requests("POST", "/api/auth/device/token")
        #expect(polls.count == 3)
        #expect(try json(polls[0].body) == ["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": "synthetic-device-code"])
        #expect(polls.allSatisfy { $0.header("Authorization") == nil && $0.header("Cookie") == nil })

        #expect(await client.credential == .deviceToken)
        #expect(await client.deviceSession?.clientName == "Synthetic Mac")
        guard case .connected = await client.state else {
            Issue.record("expected connected, got \(await client.state)")
            return
        }
        let saved = try #require(try await store.load(serverOrigin: server.origin.absoluteString))
        #expect(saved.deviceTokens?.accessToken == "nva_synthetic-access-1")
        #expect(saved.deviceTokens?.refreshToken == "nvr_synthetic-refresh-1")
        #expect(saved.sessionToken.isEmpty && saved.csrfToken.isEmpty)

        _ = try await client.workspace()
        let read = try #require(server.requests("GET", "/api/workspace").first)
        #expect(read.header("Authorization") == "Bearer nva_synthetic-access-1")
        #expect(read.header("Cookie") == nil)

        try await client.signOut()
        let out = try #require(server.requests("POST", "/api/auth/logout").first)
        // Signing out with a device token revokes the device on the server. No CSRF: not a cookie.
        #expect(out.header("Authorization") == "Bearer nva_synthetic-access-1")
        #expect(out.header("X-CSRF-Token") == nil && out.header("Cookie") == nil)
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.credential == .none)
        #expect(await client.state == .unauthorised)
    }

    @Test("Deny in the browser ends the wait with deviceSignInDenied and stores nothing")
    func denied() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.pending, DeviceFixtures.denied)
        let store = InMemoryCredentialStore()
        let client = try server.client(store: store)
        let authorization = try await client.startDeviceSignIn(clientName: "Synthetic Mac")

        await #expect(throws: NoeviaError.deviceSignInDenied) { try await client.completeDeviceSignIn(authorization) }
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.credential == .none)
    }

    @Test("An expired code, from the server or by the client's own count, is deviceSignInExpired")
    func expired() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.expired)
        let client = try server.client()
        let authorization = try await client.startDeviceSignIn(clientName: "Synthetic Mac")
        await #expect(throws: NoeviaError.deviceSignInExpired) { try await client.completeDeviceSignIn(authorization) }

        // A code valid for 10 s with a 5 s interval gets exactly two polls, then gives up.
        let short = StubServer()
        short.readyForDeviceSignIn(DeviceFixtures.pending)
        short.on("POST", "/api/auth/device/code", .json(200, body: #"{"device_code":"synthetic-device-code","user_code":"BCDF-GHJK","verification_uri":"https://noevia.example.test/device","expires_in":10,"interval":5}"#))
        let shortClient = try short.client()
        let brief = try await shortClient.startDeviceSignIn(clientName: "Synthetic Mac")
        await #expect(throws: NoeviaError.deviceSignInExpired) { try await shortClient.completeDeviceSignIn(brief) }
        #expect(short.requests("POST", "/api/auth/device/token").count == 2)
    }

    @Test("A server without device sign-in (feature off) is deviceSignInUnavailable")
    func unavailable() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("POST", "/api/auth/device/code", .json(404, body: #"{"error":"not found"}"#))
        let client = try server.client()
        await #expect(throws: NoeviaError.deviceSignInUnavailable) { _ = try await client.startDeviceSignIn(clientName: "Synthetic Mac") }
    }

    @Test("A dropped poll is polled again, not treated as a failure")
    func droppedPoll() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(.failure(.networkConnectionLost), DeviceFixtures.issued)
        let client = try server.client()
        let authorization = try await client.startDeviceSignIn(clientName: "Synthetic Mac")
        _ = try await client.completeDeviceSignIn(authorization)
        #expect(server.requests("POST", "/api/auth/device/token").count == 2)
        #expect(await client.credential == .deviceToken)
    }

    @Test("A stored device credential is restored and checked with a bearer, no cookie")
    func restoresDeviceCredential() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn()
        let client = try server.client(store: InMemoryCredentialStore([DeviceFixtures.stored(for: server)]))

        let user = try await client.restoreSession()
        #expect(user?.username == "synthetic")
        let check = try #require(server.requests("GET", "/api/auth/session").first)
        #expect(check.header("Authorization") == "Bearer nva_synthetic-access-1")
        #expect(check.header("Cookie") == nil)
        #expect(await client.deviceSession?.id == "synthetic-device-id")
    }

    @Test("A 401 triggers one refresh with the single-use refresh token, then one resend")
    func refreshOn401() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.rotated)
        server.on("GET", "/api/workspace", .json(401, fixture: "error-unauthorized__http.cjs.json"), .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        let store = InMemoryCredentialStore([DeviceFixtures.stored(for: server)])
        let client = try server.client(store: store)
        _ = try await client.restoreSession()

        _ = try await client.workspace()

        let refresh = try #require(server.requests("POST", "/api/auth/device/token").first)
        #expect(try json(refresh.body) == ["grant_type": "refresh_token", "refresh_token": "nvr_synthetic-refresh-1"])
        #expect(refresh.header("Authorization") == nil)
        let reads = server.requests("GET", "/api/workspace")
        #expect(reads.map { $0.header("Authorization") } == ["Bearer nva_synthetic-access-1", "Bearer nva_synthetic-access-2"])
        let saved = try #require(try await store.load(serverOrigin: server.origin.absoluteString))
        #expect(saved.deviceTokens?.accessToken == "nva_synthetic-access-2")
        #expect(saved.deviceTokens?.refreshToken == "nvr_synthetic-refresh-2")
    }

    @Test("A refused refresh (revoked, or reuse detected) signs the device out locally")
    func refusedRefresh() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.reused)
        server.on("GET", "/api/workspace", .json(401, fixture: "error-unauthorized__http.cjs.json"))
        let store = InMemoryCredentialStore([DeviceFixtures.stored(for: server)])
        let client = try server.client(store: store)
        _ = try await client.restoreSession()

        await #expect(throws: NoeviaError.unauthorised) { _ = try await client.workspace() }
        #expect(server.requests("GET", "/api/workspace").count == 1, "no resend after a refused refresh")
        #expect(server.requests("POST", "/api/auth/device/token").count == 1, "a refresh is never retried")
        #expect(try await store.load(serverOrigin: server.origin.absoluteString) == nil)
        #expect(await client.state == .unauthorised)
        #expect(await client.credential == .none)
    }

    @Test("An access token about to expire is renewed first, once, however many requests need it")
    func proactiveSingleFlightRefresh() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn(DeviceFixtures.rotated)
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        let clock = TestClock()
        let store = InMemoryCredentialStore([DeviceFixtures.stored(for: server, expires: clock.now.addingTimeInterval(3600))])
        let client = try server.client(store: store, clock: clock)
        _ = try await client.restoreSession()
        clock.advance(3600 - 30) // inside the one-minute leeway

        async let first = client.workspace()
        async let second = client.workspace()
        async let third = client.workspace()
        _ = try await (first, second, third)

        // Two refreshes with one single-use token would make the server revoke the device.
        #expect(server.requests("POST", "/api/auth/device/token").count == 1)
        #expect(server.requests("GET", "/api/workspace").allSatisfy { $0.header("Authorization") == "Bearer nva_synthetic-access-2" })
    }

    @Test("Password sign-in replaces a device token; the two are never sent together")
    func passwordReplacesDeviceToken() async throws {
        let server = StubServer()
        server.readyForDeviceSignIn()
        server.readyWithLogin()
        server.on("GET", "/api/workspace", .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        let store = InMemoryCredentialStore([DeviceFixtures.stored(for: server)])
        let client = try server.client(store: store)
        _ = try await client.restoreSession()

        try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        let login = try #require(server.requests("POST", "/api/auth/login/password").first)
        #expect(login.header("Authorization") == nil)
        _ = try await client.workspace()
        let read = try #require(server.requests("GET", "/api/workspace").last)
        #expect(read.header("Authorization") == nil)
        #expect(read.header("Cookie")?.contains("cowork_session=") == true)
        #expect(await client.credential == .browserSession)
        #expect(try await store.load(serverOrigin: server.origin.absoluteString)?.deviceTokens == nil)
    }

    @Test("The core's browser-only refusal maps to browserSessionRequired; other 403s do not")
    func browserOnlyRefusal() {
        #expect(NoeviaClient.statusError(403, Fixture.data("error-browser-session__index.cjs.json")) == .browserSessionRequired)
        #expect(NoeviaClient.statusError(403, Fixture.data("error-csrf__index.cjs.json")) == .forbidden("invalid CSRF token"))
    }

    @Test("A credential saved before device sign-in still decodes; a device one round-trips")
    func credentialCompatibility() throws {
        let old = #"{"serverOrigin":"https://noevia.example.test","sessionToken":"s","csrfToken":"c","secure":true}"#
        let decoded = try JSONDecoder().decode(SessionCredential.self, from: Data(old.utf8))
        #expect(decoded.deviceTokens == nil)
        #expect(decoded.sessionToken == "s")
        let device = SessionCredential(serverOrigin: "https://noevia.example.test", deviceTokens: DeviceTokens(accessToken: "nva_a", refreshToken: "nvr_r", accessExpiresAt: Date(timeIntervalSince1970: 1_790_000_000)))
        #expect(try JSONDecoder().decode(SessionCredential.self, from: JSONEncoder().encode(device)) == device)
    }
}
