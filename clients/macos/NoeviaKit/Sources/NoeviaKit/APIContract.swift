import Foundation

/// The browser/core API contract this client speaks (docs/api-browser-core-v1.md).
///
/// Every core response under `/api/*` carries `X-Noevia-API: <major>`
/// (apps/web/server/index.cjs `handleRequest`). The header is a protocol major, not a
/// release number. The rules mirror the SPA's `apps/web/src/api-contract.ts`:
/// - a missing header is the pre-contract v1 core and is accepted as v1;
/// - an explicit major this client does not support stops the client;
/// - a 5xx without the header is a reachability failure, not evidence of a different major.
public enum APIContract {
    public static let headerName = "X-Noevia-API"

    /// Majors this build of NoeviaKit can talk to. A new major means a new NoeviaKit release.
    public static let supportedMajors: [String] = ["1"]

    /// The major assumed when a pre-contract core omits the header.
    public static let assumedMajorWhenMissing = "1"

    /// Returns the served major when it is an explicit, unsupported one, else `nil`.
    /// `status >= 500` never counts as a mismatch (same as `hasApiMajorMismatchHeader`).
    public static func unsupportedMajor(served: String?, status: Int) -> String? {
        guard status < 500, let served else { return nil }
        let trimmed = served.trimmingCharacters(in: .whitespaces)
        return supportedMajors.contains(trimmed) ? nil : trimmed
    }
}

/// What `GET /api/ready` negotiated.
public struct ServerInfo: Sendable, Equatable {
    /// The server origin every request is sent to (scheme, host and port only).
    public let origin: URL
    /// The protocol major the core declared, or the assumed v1 for a pre-contract core.
    public let apiMajor: String
    /// False when the core omitted `X-Noevia-API` and v1 was assumed.
    public let apiMajorDeclared: Bool
    /// The release identifier from `/api/ready` (`version`). It is documented to equal the
    /// served `/version.json`; it is a release SHA or package version, never an API major.
    public let releaseVersion: String
}

/// `GET /api/ready` body, from apps/web/server/routes/health.cjs `createReadyRoutes`:
/// `{ ready: boolean, version: string }`.
struct ReadyResponse: Decodable, Sendable {
    let ready: Bool
    let version: String
}
