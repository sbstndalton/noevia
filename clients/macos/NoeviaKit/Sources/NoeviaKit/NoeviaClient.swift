import Foundation

/// A typed client for the Noevia core's v1 browser API (docs/api-browser-core-v1.md), for the
/// native macOS client (#273). It holds one account's session for one server.
///
/// It authenticates exactly as the browser does, because that is all the core offers today:
/// password sign-in issues the `cowork_session` and `cowork_csrf` cookies, which live in an
/// in-memory jar (never the shared system cookie store) and, between launches, in a
/// `CredentialStore`. Mutating requests send `X-CSRF-Token`. No `Origin` header is sent: the
/// core's Origin check (auth.cjs `originValid`) admits a request without one, as it does curl.
///
/// Only GET and HEAD are ever retried. A transport error or 502/503 on one of those puts the
/// client in `.reconnecting`, backs off with jitter, re-checks `/api/ready`, then resends,
/// up to `RetryPolicy.maxAttempts` failures before `.offline`.
public actor NoeviaClient {
    /// Scheme, host and port of the server. Every request goes here.
    public nonisolated let origin: URL
    public nonisolated let originKey: String

    public private(set) var state: ConnectionState = .idle
    public private(set) var serverInfo: ServerInfo?
    public private(set) var user: User?

    private let session: URLSession
    private let store: any CredentialStore
    private let policy: RetryPolicy
    private let environment: ClientEnvironment
    private let requestTimeout: TimeInterval
    private var jar = SessionCookieJar()
    private var observers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    static let userAgent = "NoeviaKit/0.1 (macOS)"

    /// - Parameters:
    ///   - serverURL: the server address, e.g. `https://noevia.example.com`. A path, query or
    ///     credentials are refused. Plain http is accepted only for a private-network host.
    ///   - configuration: copied; cookie storage and caching are always switched off.
    public init(
        serverURL: URL,
        credentialStore: any CredentialStore,
        configuration: URLSessionConfiguration = .ephemeral,
        retryPolicy: RetryPolicy = .default,
        environment: ClientEnvironment = .live,
        requestTimeout: TimeInterval = 30
    ) throws {
        let origin = try Self.validatedOrigin(serverURL)
        self.origin = origin
        self.originKey = origin.absoluteString
        self.store = credentialStore
        self.policy = retryPolicy
        self.environment = environment
        self.requestTimeout = requestTimeout
        let config = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    deinit {
        for continuation in observers.values { continuation.finish() }
    }

    // MARK: - Connection state

    /// A stream of connection states, starting with the current one.
    public func stateUpdates() -> AsyncStream<ConnectionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .unbounded)
        let id = UUID()
        observers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func setState(_ next: ConnectionState) {
        guard next != state else { return }
        state = next
        for continuation in observers.values { continuation.yield(next) }
    }

    /// The state to show once the core has answered: signed in or not.
    private func reachableState(_ info: ServerInfo) -> ConnectionState {
        jar.hasSession ? .connected(info) : .unauthorised
    }

    // MARK: - Connect and version negotiation

    /// Checks `GET /api/ready` and the `X-Noevia-API` major, retrying with backoff while the
    /// core is unreachable, answering 502/503, or still starting. Throws
    /// `unsupportedAPIMajor` (state `.incompatible`) for a major this client does not speak.
    @discardableResult
    public func connect() async throws -> ServerInfo {
        try await withRecovery(idempotent: true, probeBeforeRetry: false) {
            try await probeReady()
        }
    }

    /// Recovery after `.offline`: the same bounded readiness loop as `connect()`.
    @discardableResult
    public func reconnect() async throws -> ServerInfo {
        try await connect()
    }

    private func ensureNegotiated() async throws {
        if case .incompatible(let served) = state {
            throw NoeviaError.unsupportedAPIMajor(served: served, supported: APIContract.supportedMajors)
        }
        if serverInfo == nil { try await connect() }
    }

    /// One readiness probe. Transient failures (including `ready: false`) are thrown as
    /// `Transient` so the caller's recovery loop handles them.
    private func probeReady() async throws -> ServerInfo {
        var request = makeRequest("/api/ready", method: "GET")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, http) = try await transmit(request)
        guard http.statusCode == 200 else {
            throw NoeviaError.http(status: http.statusCode, message: Self.errorMessage(data))
        }
        let ready: ReadyResponse
        do { ready = try JSONDecoder().decode(ReadyResponse.self, from: data) }
        catch { throw NoeviaError.invalidResponse("GET /api/ready: \(error)") }
        guard ready.ready else { throw Transient(reason: "server is starting", status: nil, message: nil, notReady: true) }
        let served = http.value(forHTTPHeaderField: APIContract.headerName)?.trimmingCharacters(in: .whitespaces)
        let info = ServerInfo(
            origin: origin,
            apiMajor: served ?? APIContract.assumedMajorWhenMissing,
            apiMajorDeclared: served != nil,
            releaseVersion: ready.version
        )
        serverInfo = info
        setState(reachableState(info))
        return info
    }

    // MARK: - Authentication

    /// `POST /api/auth/login/password`. Never retried. On success the session is kept in memory
    /// and saved to the credential store; the password is not kept anywhere.
    @discardableResult
    public func signIn(username: String, password: String) async throws -> User {
        try await ensureNegotiated()
        let body = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let previous = jar
        jar.clear()
        let data: Data, http: HTTPURLResponse
        do { (data, http) = try await send(makeRequest("/api/auth/login/password", method: "POST", body: body)) }
        catch { jar = previous; throw error }
        switch http.statusCode {
        case 200:
            guard let login = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                jar = previous
                throw NoeviaError.invalidResponse("POST /api/auth/login/password")
            }
            guard jar.hasSession, let credential = jar.credential(serverOrigin: originKey) else {
                jar = previous
                // Foundation (like browsers) refuses a Secure cookie set over http, so the jar
                // stays empty. auth.cjs issueSession() marks cookies Secure when the configured
                // origin is https and the request carried no Origin, as a native request does.
                if origin.scheme == "http", Self.setsSecureSessionCookie(http) {
                    setState(serverInfo.map(reachableState) ?? .unauthorised)
                    throw NoeviaError.insecureSessionCookie
                }
                throw NoeviaError.missingSessionCookies
            }
            if jar.sessionIsSecure && origin.scheme == "http" {
                // The cookie could never be sent back; don't keep a session we can't use.
                jar = previous
                setState(serverInfo.map(reachableState) ?? .unauthorised)
                throw NoeviaError.insecureSessionCookie
            }
            try await store.save(credential)
            user = login.user
            if let info = serverInfo { setState(.connected(info)) }
            return login.user
        default:
            jar = previous
            if http.statusCode == 401 {
                setState(.unauthorised)
                throw NoeviaError.signInFailed
            }
            throw Self.statusError(http.statusCode, data)
        }
    }

    /// Resumes a session saved by an earlier `signIn` (or created elsewhere and saved to the
    /// store), and checks it with `GET /api/auth/session`. Returns nil, with state
    /// `.unauthorised`, when there is no saved session or the server no longer accepts it.
    public func restoreSession() async throws -> User? {
        try await ensureNegotiated()
        guard let credential = try await store.load(serverOrigin: originKey) else {
            jar.clear()
            user = nil
            if let info = serverInfo { setState(reachableState(info)) }
            return nil
        }
        if credential.secure && origin.scheme == "http" {
            try? await store.delete(serverOrigin: originKey)
            setState(.unauthorised)
            return nil
        }
        jar.restore(credential)
        do { return try await currentUser() }
        catch NoeviaError.unauthorised { return nil }
    }

    /// `GET /api/auth/session`: the signed-in account.
    @discardableResult
    public func currentUser() async throws -> User {
        try await ensureNegotiated()
        try requireSession()
        let (data, http) = try await send(makeRequest("/api/auth/session", method: "GET"))
        let response = try await decode(SessionResponse.self, data, http)
        user = response.user
        if let info = serverInfo { setState(.connected(info)) }
        return response.user
    }

    /// `POST /api/auth/logout` with the CSRF header. Never retried. The local session is
    /// removed even when the server cannot be told; the error is then rethrown so the UI can
    /// say the server-side session was not revoked (it lapses after 7 idle days).
    public func signOut() async throws {
        var failure: (any Error)?
        if jar.hasSession {
            do {
                let (data, http) = try await send(makeRequest("/api/auth/logout", method: "POST", body: Data("{}".utf8)))
                if !(200..<300).contains(http.statusCode) && http.statusCode != 401 {
                    failure = Self.statusError(http.statusCode, data)
                }
            } catch {
                failure = error
            }
        }
        jar.clear()
        user = nil
        do { try await store.delete(serverOrigin: originKey) } catch { failure = failure ?? error }
        switch state {
        case .offline, .incompatible: break
        default: setState(.unauthorised)
        }
        if let failure { throw failure }
    }

    // MARK: - Owned state (read-only)

    /// `GET /api/workspace`: this account's projects and free chats.
    public func workspace() async throws -> Workspace {
        try await ensureNegotiated()
        try requireSession()
        let (data, http) = try await send(makeRequest("/api/workspace", method: "GET"))
        return try await decode(Workspace.self, data, http)
    }

    /// The account's projects (from `GET /api/workspace`; the core has no `GET /api/projects`).
    public func projects() async throws -> [Project] {
        try await workspace().projects
    }

    // MARK: - Transport

    struct Transient: Error {
        let reason: String
        let status: Int?
        let message: String?
        var notReady = false
    }

    private func requireSession() throws {
        guard jar.hasSession else {
            setState(.unauthorised)
            throw NoeviaError.unauthorised
        }
    }

    func makeRequest(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: origin.appending(path: path), timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Adds the jar's cookies and, for a mutating request, `X-CSRF-Token` (as the SPA's
    /// `apiFetch` does), at send time so a retry always carries the current session.
    private func authorise(_ request: URLRequest) -> URLRequest {
        var request = request
        guard let url = request.url else { return request }
        if let cookie = jar.header(for: url) { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let method = (request.httpMethod ?? "GET").uppercased()
        if !["GET", "HEAD", "OPTIONS"].contains(method), let csrf = jar.csrfToken {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        return request
    }

    /// Sends with recovery for idempotent methods only.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let idempotent = RetryPolicy.isIdempotent(request.httpMethod ?? "GET")
        return try await withRecovery(idempotent: idempotent, probeBeforeRetry: true) {
            try await transmit(request)
        }
    }

    private func withRecovery<T>(idempotent: Bool, probeBeforeRetry: Bool, _ operation: () async throws -> T) async throws -> T {
        var failures = 0
        var probe = false
        while true {
            try Task.checkCancellation()
            do {
                if probe { _ = try await probeReady() }
                return try await operation()
            } catch let transient as Transient {
                guard idempotent else {
                    // Never resend: the server may already have acted on it.
                    if let status = transient.status {
                        throw NoeviaError.http(status: status, message: transient.message)
                    }
                    setState(.offline(reason: transient.reason))
                    throw NoeviaError.transport(transient.reason)
                }
                failures += 1
                if failures >= policy.maxAttempts {
                    setState(.offline(reason: transient.reason))
                    if transient.notReady { throw NoeviaError.serverNotReady }
                    throw NoeviaError.offline(attempts: failures, lastError: transient.reason)
                }
                setState(.reconnecting(attempt: failures))
                try await environment.sleep(policy.delay(afterFailure: failures, random: environment.random()))
                probe = probeBeforeRetry
            }
        }
    }

    /// One send. Applies cookies, checks the API major on every response, and classifies
    /// transport errors and 502/503 as `Transient`.
    private func transmit(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let request = authorise(request)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            let reason = Self.describe(error)
            if Self.transientCodes.contains(error.code) {
                throw Transient(reason: reason, status: nil, message: nil)
            }
            throw NoeviaError.transport(reason)
        }
        guard let http = response as? HTTPURLResponse, let url = request.url else {
            throw NoeviaError.invalidResponse("not an HTTP response")
        }
        if let served = APIContract.unsupportedMajor(served: http.value(forHTTPHeaderField: APIContract.headerName), status: http.statusCode) {
            setState(.incompatible(servedMajor: served))
            throw NoeviaError.unsupportedAPIMajor(served: served, supported: APIContract.supportedMajors)
        }
        if jar.ingest(http, url: url), let credential = jar.credential(serverOrigin: originKey), url.path != "/api/auth/login/password" {
            // A session cookie changed outside sign-in; keep the store in step.
            try? await store.save(credential)
        }
        if policy.retryableStatuses.contains(http.statusCode) {
            throw Transient(reason: "HTTP \(http.statusCode)", status: http.statusCode, message: Self.errorMessage(data))
        }
        return (data, http)
    }

    /// Decodes a 2xx body; maps 401 (dropping the session), 403, 429 and others to errors.
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, _ http: HTTPURLResponse) async throws -> T {
        if http.statusCode == 401 {
            await dropSession()
            throw NoeviaError.unauthorised
        }
        guard (200..<300).contains(http.statusCode) else { throw Self.statusError(http.statusCode, data) }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw NoeviaError.invalidResponse("\(T.self): \(error)") }
    }

    private func dropSession() async {
        jar.clear()
        user = nil
        try? await store.delete(serverOrigin: originKey)
        setState(.unauthorised)
    }

    static let transientCodes: Set<URLError.Code> = [
        .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
        .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
        .internationalRoamingOff, .callIsActive, .dataNotAllowed,
    ]

    static func describe(_ error: URLError) -> String {
        "\(error.localizedDescription) [URLError \(error.code.rawValue)]"
    }

    static func setsSecureSessionCookie(_ response: HTTPURLResponse) -> Bool {
        guard let raw = response.value(forHTTPHeaderField: "Set-Cookie") else { return false }
        return raw.components(separatedBy: ", ").contains { cookie in
            let attributes = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            return attributes.first?.hasPrefix("\(SessionCookieJar.sessionCookie)=") == true && attributes.contains("secure")
        }
    }

    static func errorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }

    static func statusError(_ status: Int, _ data: Data) -> NoeviaError {
        let message = errorMessage(data)
        switch status {
        case 401: return .unauthorised
        case 403: return .forbidden(message ?? "forbidden")
        case 429: return .rateLimited
        default: return .http(status: status, message: message)
        }
    }

    // MARK: - Server address

    static func validatedOrigin(_ url: URL) throws -> URL {
        let text = url.absoluteString
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { throw NoeviaError.invalidServerURL(text) }
        if scheme == "http" && !isPrivateHost(host) { throw NoeviaError.insecureServerURL(text) }
        components.scheme = scheme
        components.path = ""
        guard let origin = components.url else { throw NoeviaError.invalidServerURL(text) }
        return origin
    }

    /// Mirrors apps/web/server/auth.cjs `isAcceptablePublicOrigin` for http.
    static func isPrivateHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        if octets.count == 4, octets.allSatisfy({ $0 != nil }) {
            let a = octets[0]!, b = octets[1]!
            if a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) { return true }
            return false
        }
        return !host.contains(".") && !host.contains(":")
    }
}
