import Foundation

/// Detected Kimi auth/refresh token from browser cookie or localStorage.
public struct KimiDetectedToken: Equatable, Sendable {
    public let token: String
    public let source: String

    public init(token: String, source: String) {
        self.token = token
        self.source = source
    }
}

/// Provider-side port for Kimi-specific browser token detection
/// (access + refresh JWT selection beyond generic cookie headers).
public protocol KimiBrowserCookieDetecting {
    func detectKimiAuthToken(order: [KimiBrowserKind], refreshPaths: Bool) -> KimiDetectedToken?
    func detectKimiRefreshToken(order: [KimiBrowserKind], refreshPaths: Bool) -> KimiDetectedToken?
}
