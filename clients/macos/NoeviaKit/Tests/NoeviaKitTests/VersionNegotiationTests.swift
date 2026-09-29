import Foundation
import Testing
@testable import NoeviaKit

@Suite("Connect and API version negotiation")
struct VersionNegotiationTests {
    @Test("A v1 core is accepted and its release version reported")
    func acceptsDeclaredV1() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        let client = try server.client()

        let info = try await client.connect()

        #expect(info.apiMajor == "1")
        #expect(info.apiMajorDeclared)
        #expect(info.releaseVersion == "0123abc")
        #expect(info.origin == server.origin)
        // Reachable, but no session yet.
        #expect(await client.state == .unauthorised)
        let ready = try #require(server.requests("GET", "/api/ready").first)
        #expect(ready.header("Cache-Control") == "no-store")
        #expect(ready.header("Cookie") == nil)
    }

    @Test("A pre-contract core without X-Noevia-API is treated as v1")
    func missingHeaderIsV1() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json", apiMajor: nil))
        let client = try server.client()

        let info = try await client.connect()

        #expect(info.apiMajor == "1")
        #expect(!info.apiMajorDeclared)
    }

    @Test("An unsupported major is refused with a clear error and blocks sign-in")
    func refusesUnsupportedMajor() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json", apiMajor: "2"))
        let client = try server.client()

        await #expect(throws: NoeviaError.unsupportedAPIMajor(served: "2", supported: ["1"])) {
            try await client.connect()
        }
        #expect(await client.state == .incompatible(servedMajor: "2"))
        let message = NoeviaError.unsupportedAPIMajor(served: "2", supported: ["1"]).localizedDescription
        #expect(message.contains("API version 2") && message.contains("supports version 1"))

        // No session work against an incompatible core.
        await #expect(throws: NoeviaError.unsupportedAPIMajor(served: "2", supported: ["1"])) {
            try await client.signIn(username: "synthetic", password: "synthetic-password")
        }
        #expect(server.requests("POST", "/api/auth/login/password").isEmpty)
        // Not retried: a different major is not a transient failure.
        #expect(server.requests("GET", "/api/ready").count == 1)
    }

    @Test("A later response declaring a different major stops the client")
    func laterMismatchStops() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready__routes-health.cjs.json"))
        server.on("GET", "/api/auth/session", .json(fixture: "auth-session__routes-auth.cjs.json", apiMajor: "2"))
        let store = InMemoryCredentialStore([TestCredentials.stored(for: server)])
        let client = try server.client(store: store)

        await #expect(throws: NoeviaError.unsupportedAPIMajor(served: "2", supported: ["1"])) {
            _ = try await client.restoreSession()
        }
        #expect(await client.state == .incompatible(servedMajor: "2"))
    }

    @Test("A gateway 502 without the core header is reachability, not a version mismatch")
    func gatewayErrorIsNotMismatch() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .gateway(502), .json(fixture: "api-ready__routes-health.cjs.json"))
        let client = try server.client()

        let info = try await client.connect()

        #expect(info.apiMajor == "1")
        #expect(server.requests("GET", "/api/ready").count == 2)
    }

    @Test("A starting core (ready: false) is waited for, then accepted")
    func waitsForReadiness() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready",
                  .json(fixture: "api-ready-starting__routes-health.cjs.json"),
                  .json(fixture: "api-ready__routes-health.cjs.json"))
        let sleeps = SleepRecorder()
        let client = try server.client(sleeps: sleeps)

        _ = try await client.connect()

        #expect(await sleeps.delays.count == 1)
        #expect(await client.state == .unauthorised)
    }

    @Test("A core that never finishes starting ends offline with serverNotReady")
    func neverReady() async throws {
        let server = StubServer()
        server.on("GET", "/api/ready", .json(fixture: "api-ready-starting__routes-health.cjs.json"))
        let client = try server.client(policy: RetryPolicy(maxAttempts: 3))

        await #expect(throws: NoeviaError.serverNotReady) { try await client.connect() }
        #expect(server.requests("GET", "/api/ready").count == 3)
        guard case .offline = await client.state else {
            Issue.record("expected offline, got \(await client.state)")
            return
        }
    }

    @Test("Server addresses follow the core's http/https rule", arguments: [
        ("https://noevia.example.com", true),
        ("https://noevia.example.com/", true),
        ("http://192.168.1.20:8021", true),
        ("http://10.0.0.5", true),
        ("http://172.20.1.1", true),
        ("http://localhost:8021", true),
        ("http://daserver", true),
        ("http://noevia.example.com", false),
        ("http://8.8.8.8", false),
        ("https://noevia.example.com/app", false),
        ("https://noevia.example.com/?x=1", false),
        ("https://user:pw@noevia.example.com", false),
        ("ftp://noevia.example.com", false),
    ])
    func serverURLValidation(address: String, accepted: Bool) throws {
        let url = try #require(URL(string: address))
        let result = Result { try NoeviaClient.validatedOrigin(url) }
        switch result {
        case .success(let origin):
            #expect(accepted, "\(address) should be refused")
            #expect(origin.path.isEmpty)
        case .failure(let error):
            #expect(!accepted, "\(address) should be accepted, got \(error)")
        }
    }
}
