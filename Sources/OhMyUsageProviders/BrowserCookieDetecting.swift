import Foundation

public struct BrowserCookieHeader: Equatable, Sendable {
    public let header: String
    public let source: String
    /// True when resolving this header already performed a live browser read
    /// during this poll. A cookie resolved that way is already the browser's
    /// best answer, so re-reading it cannot rescue a rejected request.
    public let readBrowserDuringResolution: Bool
    /// A browser-detected header that replaced a stored cookie and is waiting
    /// for a successful request before it is persisted, so a stale browser
    /// login cannot silently destroy a working saved cookie.
    public let pendingPersistHeader: String?

    public init(
        header: String,
        source: String,
        readBrowserDuringResolution: Bool = false,
        pendingPersistHeader: String? = nil
    ) {
        self.header = header
        self.source = source
        self.readBrowserDuringResolution = readBrowserDuringResolution
        self.pendingPersistHeader = pendingPersistHeader
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
