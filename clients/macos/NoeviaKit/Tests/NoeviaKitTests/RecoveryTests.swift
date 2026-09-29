import Foundation
import Testing
@testable import NoeviaKit

extension NoeviaClient {
    /// A signed-in client for recovery tests.
    static func signedIn(_ server: StubServer, policy: RetryPolicy = .default, sleeps: SleepRecorder = SleepRecorder()) async throws -> NoeviaClient {
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json"))
        let client = try server.client(store: InMemoryCredentialStore([TestCredentials.stored(for: server)]), policy: policy, sleeps: sleeps)
        _ = try #require(try await client.restoreSession())
        return client
    }
}

@Suite("Disconnect recovery")
struct RecoveryTests {
    @Test("503, 503, then 200: backs off with jitter, re-checks /api/ready, then succeeds")
    func retriesThenSucceeds() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, sleeps: sleeps)
        let states = await client.stateUpdates()
        server.on("GET", "/api/workspace",
                  .json(503, body: #"{"error":"busy"}"#),
                  .gateway(503),
                  .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        let readyBefore = server.requests("GET", "/api/ready").count

        let workspace = try await client.workspace()

        #expect(workspace.projects.count == 2)
        #expect(server.requests("GET", "/api/workspace").count == 3)
        #expect(server.requests("GET", "/api/ready").count - readyBefore == 2, "readiness re-checked before each resend")
        // Default policy, random 0.5: cap 0.5s → 0.375s, cap 1s → 0.75s.
        #expect(await sleeps.delays == [.milliseconds(375), .milliseconds(750)])

        var observed: [ConnectionState] = []
        for await state in states.prefix(5) { observed.append(state) }
        let info = try #require(await client.serverInfo)
        #expect(observed == [.connected(info), .reconnecting(attempt: 1), .connected(info), .reconnecting(attempt: 2), .connected(info)])
        #expect(await client.state == .connected(info))
    }

    @Test("A dropped connection on a read is retried once the core answers again")
    func transportErrorRetried() async throws {
        let server = StubServer()
        let client = try await NoeviaClient.signedIn(server)
        server.on("GET", "/api/workspace", .failure(.networkConnectionLost), .json(fixture: "workspace__routes-chat-lists.cjs.json"))

        _ = try await client.workspace()

        #expect(server.requests("GET", "/api/workspace").count == 2)
    }

    @Test("While the core is down, the readiness probe fails too, and the attempt budget still bounds it")
    func probeFailuresCount() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, policy: RetryPolicy(maxAttempts: 4), sleeps: sleeps)
        server.on("GET", "/api/workspace", .failure(.cannotConnectToHost), .json(fixture: "workspace__routes-chat-lists.cjs.json"))
        server.on("GET", "/api/ready", .failure(.cannotConnectToHost), .gateway(502), .json(fixture: "api-ready__routes-health.cjs.json"))

        _ = try await client.workspace()

        #expect(await sleeps.delays.count == 3)
        #expect(server.requests("GET", "/api/workspace").count == 2)
    }

    @Test("Exhausted retries end in .offline; reconnect() recovers")
    func exhaustsThenReconnects() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, policy: RetryPolicy(maxAttempts: 3), sleeps: sleeps)
        server.on("GET", "/api/workspace", .gateway(502))

        await #expect(throws: NoeviaError.offline(attempts: 3, lastError: "HTTP 502")) { _ = try await client.workspace() }
        #expect(server.requests("GET", "/api/workspace").count == 3)
        #expect(await sleeps.delays.count == 2)
        #expect(await client.state == .offline(reason: "HTTP 502"))

        let info = try await client.reconnect()
        #expect(await client.state == .connected(info))
    }

    @Test("A POST is never retried on 503")
    func noRetryOnPost503() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, sleeps: sleeps)
        server.on("POST", "/api/auth/logout", .json(503, body: #"{"error":"busy"}"#), .json(200, body: #"{"ok":true}"#))

        await #expect(throws: NoeviaError.http(status: 503, message: "busy")) { try await client.signOut() }

        #expect(server.requests("POST", "/api/auth/logout").count == 1)
        #expect(await sleeps.delays.isEmpty)
    }

    @Test("A POST that loses its connection is not resent and the client goes offline")
    func noRetryOnPostTransport() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, sleeps: sleeps)
        server.on("POST", "/api/auth/logout", .failure(.networkConnectionLost))

        do {
            try await client.signOut()
            Issue.record("expected a transport error")
        } catch let error as NoeviaError {
            guard case .transport = error else { Issue.record("expected transport, got \(error)"); return }
        }

        #expect(server.requests("POST", "/api/auth/logout").count == 1)
        #expect(await sleeps.delays.isEmpty)
        guard case .offline = await client.state else {
            Issue.record("expected offline, got \(await client.state)")
            return
        }
    }

    @Test("Password sign-in is not resent after a transport failure")
    func noRetryOnSignIn() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("POST", "/api/auth/login/password", .failure(.timedOut))
        let client = try server.client()

        await #expect(throws: NoeviaError.self) {
            try await client.signIn(username: "synthetic", password: "synthetic-password-1")
        }
        #expect(server.requests("POST", "/api/auth/login/password").count == 1)
    }

    @Test("A non-transient transport error (bad certificate) is not retried, even for a read")
    func certificateErrorNotRetried() async throws {
        let server = StubServer()
        let sleeps = SleepRecorder()
        let client = try await NoeviaClient.signedIn(server, sleeps: sleeps)
        server.on("GET", "/api/workspace", .failure(.serverCertificateUntrusted))

        await #expect(throws: NoeviaError.self) { _ = try await client.workspace() }
        #expect(server.requests("GET", "/api/workspace").count == 1)
        #expect(await sleeps.delays.isEmpty)
    }
}

@Suite("Backoff policy")
struct RetryPolicyTests {
    let policy = RetryPolicy(maxAttempts: 10, baseDelay: .milliseconds(500), maxDelay: .seconds(8))

    @Test("Delay doubles per failure and is capped", arguments: [
        (1, Duration.milliseconds(500)), (2, .seconds(1)), (3, .seconds(2)), (4, .seconds(4)), (5, .seconds(8)), (6, .seconds(8)), (40, .seconds(8)),
    ])
    func capDoubles(failure: Int, cap: Duration) {
        #expect(policy.delay(afterFailure: failure, random: 1) == cap)
        #expect(policy.delay(afterFailure: failure, random: 0) == cap / 2)
    }

    @Test("Jitter stays within [cap/2, cap] for any random input")
    func jitterBounds() {
        for r in stride(from: -0.5, through: 1.5, by: 0.125) {
            let d = policy.delay(afterFailure: 3, random: r)
            #expect(d >= .seconds(1) && d <= .seconds(2))
        }
    }

    @Test("Only GET and HEAD are idempotent")
    func idempotentMethods() {
        #expect(RetryPolicy.isIdempotent("GET"))
        #expect(RetryPolicy.isIdempotent("head"))
        for method in ["POST", "PUT", "PATCH", "DELETE"] { #expect(!RetryPolicy.isIdempotent(method)) }
    }
}
