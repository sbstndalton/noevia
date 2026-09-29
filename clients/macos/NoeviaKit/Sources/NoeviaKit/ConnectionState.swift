import Foundation

/// The client's view of its link to the core, for a UI to render.
public enum ConnectionState: Sendable, Equatable {
    /// Nothing attempted yet.
    case idle
    /// The core is ready, the API major is supported and a session is held.
    case connected(ServerInfo)
    /// A transport error or 502/503 interrupted an idempotent request; the client is
    /// backing off and re-checking `/api/ready`. `attempt` counts failures so far.
    case reconnecting(attempt: Int)
    /// Retries were exhausted, or a request that must not be retried failed in transport.
    /// Call `NoeviaClient.reconnect()` to try again.
    case offline(reason: String)
    /// The core is reachable but there is no valid session (never signed in, signed out,
    /// or the server answered 401). Sign in again.
    case unauthorised
    /// The core declared an API major this client does not support. Terminal until the
    /// app or server is updated.
    case incompatible(servedMajor: String)
}
