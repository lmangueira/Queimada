import Foundation

/// Bracketed access to user-granted files for the duration of a burn
/// (KTD3/KTD4). Under App Sandbox the real implementation starts/stops
/// security-scoped resource access; in the non-sandboxed direct build it is
/// a no-op; in tests a mock asserts the bracketing discipline (U6 scenario).
public protocol FileAccessManaging: AnyObject, Sendable {
    /// Begin holding access to the given URLs. Returns a token that must be
    /// released when the operation finishes (success or failure).
    func beginAccess(to urls: [URL]) -> FileAccessToken
}

/// Opaque access token; release exactly once.
public protocol FileAccessToken: AnyObject, Sendable {
    func release()
}

/// No-op implementation for the non-sandboxed direct build (KTD4 fallback)
/// — plain paths, nothing to hold.
public final class UnrestrictedFileAccess: FileAccessManaging, @unchecked Sendable {
    public init() {}

    public func beginAccess(to urls: [URL]) -> FileAccessToken {
        NoopToken()
    }

    private final class NoopToken: FileAccessToken, @unchecked Sendable {
        func release() {}
    }
}
