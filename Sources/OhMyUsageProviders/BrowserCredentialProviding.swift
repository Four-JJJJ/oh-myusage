import Foundation

/// Browser-derived credential (bearer token or cookie header fragment).
public struct BrowserDetectedCredential: Equatable, Sendable {
    public let value: String
    public let source: String

    public init(value: String, source: String) {
        self.value = value
        self.source = source
    }
}

/// Provider-side port for resolving bearer tokens and cookie headers from browser storage.
/// Narrower than full cookie-store probing; matches Relay / Trae credential resolution.
public protocol BrowserCredentialProviding {
    func detectBearerTokenCandidates(
        host: String,
        accessIntent: BrowserCredentialAccessIntent
    ) -> [BrowserDetectedCredential]

    func detectCookieHeader(
        host: String,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserDetectedCredential?

    func detectNamedCookie(
        name: String,
        host: String,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserDetectedCredential?
}

public extension BrowserCredentialProviding {
    func detectBearerTokenCandidates(host: String) -> [BrowserDetectedCredential] {
        detectBearerTokenCandidates(host: host, accessIntent: .interactiveImport)
    }

    func detectCookieHeader(host: String) -> BrowserDetectedCredential? {
        detectCookieHeader(host: host, accessIntent: .interactiveImport)
    }

    func detectNamedCookie(name: String, host: String) -> BrowserDetectedCredential? {
        detectNamedCookie(name: name, host: host, accessIntent: .interactiveImport)
    }
}
