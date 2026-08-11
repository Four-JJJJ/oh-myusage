import Foundation

public struct BrowserCookieHeader: Equatable, Sendable {
    public let header: String
    public let source: String

    public init(header: String, source: String) {
        self.header = header
        self.source = source
    }
}

public enum BrowserCredentialAccessIntent: Sendable {
    case background
    case interactiveImport
    case authRecovery

    public var allowsLiveLookup: Bool {
        switch self {
        case .background:
            return false
        case .interactiveImport, .authRecovery:
            return true
        }
    }

    public var allowsKeychainInteraction: Bool {
        switch self {
        case .background:
            return false
        case .interactiveImport, .authRecovery:
            return true
        }
    }
}

/// Browser kinds used when probing cookie stores for provider auth.
public enum KimiBrowserKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case arc
    case chrome
    case safari
    case edge
    case brave
    case chromium
    case firefox
    case opera
    case operaGX
    case vivaldi

    public var id: String { rawValue }
}

/// Provider-side port for detecting browser session cookies.
public protocol BrowserCookieDetecting {
    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader?

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]?,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader?
}

public extension BrowserCookieDetecting {
    func detectCookieHeader(hostContains: String, order: [KimiBrowserKind]? = nil) -> BrowserCookieHeader? {
        detectCookieHeader(
            hostContains: hostContains,
            order: order,
            accessIntent: .interactiveImport
        )
    }

    func detectNamedCookie(name: String, hostContains: String, order: [KimiBrowserKind]? = nil) -> BrowserCookieHeader? {
        detectNamedCookie(
            name: name,
            hostContains: hostContains,
            order: order,
            accessIntent: .interactiveImport
        )
    }
}
