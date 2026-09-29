import Foundation
import Synchronization
@testable import NoeviaKit

/// One scripted reply. `.failure` makes URLSession fail with that URLError code.
enum StubReply: Sendable {
    case response(status: Int, headers: [String: String], body: Data)
    case failure(URLError.Code)

    /// A JSON reply carrying `X-Noevia-API: 1`, as every core `/api/*` response does
    /// (apps/web/server/index.cjs handleRequest). Pass `apiMajor: nil` to omit it.
    static func json(_ status: Int = 200, fixture: String, apiMajor: String? = "1", headers: [String: String] = [:]) -> StubReply {
        .response(status: status, headers: coreHeaders(apiMajor, headers), body: Fixture.data(fixture))
    }

    static func json(_ status: Int, body: String, apiMajor: String? = "1", headers: [String: String] = [:]) -> StubReply {
        .response(status: status, headers: coreHeaders(apiMajor, headers), body: Data(body.utf8))
    }

    /// A proxy error page: no core header, not JSON.
    static func gateway(_ status: Int) -> StubReply {
        .response(status: status, headers: ["Content-Type": "text/html"], body: Data("<html>Bad gateway</html>".utf8))
    }

    private static func coreHeaders(_ apiMajor: String?, _ extra: [String: String]) -> [String: String] {
        var h = ["Content-Type": "application/json"]
        if let apiMajor { h[APIContract.headerName] = apiMajor }
        return h.merging(extra) { _, new in new }
    }
}

struct RecordedRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A fake Noevia server behind one unique host. Each `METHOD /path` route has a queue of
/// replies; the last reply repeats. Tests run in parallel, so each gets its own host.
final class StubServer: Sendable {
    let origin: URL
    private let state = Mutex<(routes: [String: [StubReply]], log: [RecordedRequest])>(([:], []))

    init() {
        origin = URL(string: "https://\(UUID().uuidString.lowercased()).noevia.test")!
        StubURLProtocol.register(self)
    }

    init(origin: URL) {
        self.origin = origin
        StubURLProtocol.register(self)
    }

    var host: String { origin.host! }

    func on(_ method: String, _ path: String, _ replies: StubReply...) {
        state.withLock { $0.routes["\(method) \(path)"] = replies }
    }

    var requests: [RecordedRequest] { state.withLock { $0.log } }

    func requests(_ method: String, _ path: String) -> [RecordedRequest] {
        requests.filter { $0.method == method && $0.path == path }
    }

    fileprivate func reply(to request: RecordedRequest) -> StubReply {
        state.withLock { s in
            s.log.append(request)
            let key = "\(request.method) \(request.path)"
            guard var queue = s.routes[key], !queue.isEmpty else {
                return .json(404, body: #"{"error":"not found"}"#)
            }
            let next = queue.removeFirst()
            s.routes[key] = queue.isEmpty ? [next] : queue
            return next
        }
    }

    /// A client wired to this server with a recording, instant sleeper.
    func client(store: any CredentialStore = InMemoryCredentialStore(), policy: RetryPolicy = .default, sleeps: SleepRecorder = SleepRecorder(), random: Double = 0.5) throws -> NoeviaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let environment = ClientEnvironment(sleep: { await sleeps.record($0) }, random: { random })
        return try NoeviaClient(serverURL: origin, credentialStore: store, configuration: configuration, retryPolicy: policy, environment: environment)
    }
}

actor SleepRecorder {
    private(set) var delays: [Duration] = []
    func record(_ d: Duration) { delays.append(d) }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let servers = Mutex<[String: StubServer]>([:])

    static func register(_ server: StubServer) {
        servers.withLock { $0[server.host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let server = Self.servers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: url.path,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? Self.drain(request.httpBodyStream)
        )
        switch server.reply(to: recorded) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

enum Fixture {
    /// Loads Tests/NoeviaKitTests/Fixtures/<name>. Each file name cites the server file that
    /// produces the shape; scripts/generate-fixtures.cjs regenerates them from the real routes.
    static func data(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }
}

/// The `Set-Cookie` values auth.cjs issueSession() writes for an https origin (Secure) and
/// logout() writes to clear them. Foundation joins repeated headers with ", ".
enum CoreCookies {
    static func issued(session: String = "synthetic-session-token", csrf: String = "synthetic-csrf-token", secure: Bool = true) -> [String: String] {
        let s = secure ? "; Secure" : ""
        return ["Set-Cookie": "cowork_session=\(session); Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000\(s), cowork_csrf=\(csrf); Path=/; SameSite=Lax; Max-Age=2592000\(s)"]
    }

    static let cleared = ["Set-Cookie": "cowork_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0, cowork_csrf=; Path=/; SameSite=Lax; Max-Age=0"]
}
