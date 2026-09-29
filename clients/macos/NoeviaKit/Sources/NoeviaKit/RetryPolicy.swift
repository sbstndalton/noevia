import Foundation

/// Bounded exponential backoff with jitter for idempotent requests only.
///
/// `maxAttempts` counts every send of the request, including the first. Between attempts the
/// client sleeps `delay(afterFailure:)` and re-checks `/api/ready` before resending.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// Statuses treated like a transport failure: the reverse proxy or core is (re)starting.
    public var retryableStatuses: Set<Int>

    public init(maxAttempts: Int = 5, baseDelay: Duration = .milliseconds(500), maxDelay: Duration = .seconds(8), retryableStatuses: Set<Int> = [502, 503]) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.retryableStatuses = retryableStatuses
    }

    public static let `default` = RetryPolicy()

    /// "Equal jitter": the cap doubles per failure up to `maxDelay`; the delay is half the cap
    /// plus a random share of the other half, so it stays within `[cap/2, cap]`.
    /// `failure` is 1 for the first failure. `random` must be in `0...1`.
    public func delay(afterFailure failure: Int, random: Double) -> Duration {
        let exponent = min(max(failure - 1, 0), 30)
        let uncapped = baseDelay * (1 << exponent)
        let cap = min(uncapped, maxDelay)
        let r = min(max(random, 0), 1)
        return cap / 2 + (cap / 2) * r
    }

    static func isIdempotent(_ method: String) -> Bool {
        ["GET", "HEAD"].contains(method.uppercased())
    }
}

/// Seams for time and randomness so tests never sleep or depend on chance.
public struct ClientEnvironment: Sendable {
    public var sleep: @Sendable (Duration) async throws -> Void
    public var random: @Sendable () -> Double
    /// The wall clock, for device-token expiry (#555).
    public var now: @Sendable () -> Date

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void, random: @escaping @Sendable () -> Double, now: @escaping @Sendable () -> Date = { Date() }) {
        self.sleep = sleep
        self.random = random
        self.now = now
    }

    public static let live = ClientEnvironment(
        sleep: { try await Task.sleep(for: $0) },
        random: { Double.random(in: 0...1) }
    )
}
