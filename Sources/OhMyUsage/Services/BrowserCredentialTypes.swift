struct BrowserCookieHeader: Equatable {
    let header: String
    let source: String
}

enum BrowserCredentialAccessIntent {
    case background
    case interactiveImport
    case authRecovery

    var allowsLiveLookup: Bool {
        switch self {
        case .background:
            return false
        case .interactiveImport, .authRecovery:
            return true
        }
    }

    var allowsKeychainInteraction: Bool {
        switch self {
        case .background:
            return false
        case .interactiveImport, .authRecovery:
            return true
        }
    }
}

protocol BrowserCookieDetecting {
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

extension BrowserCookieDetecting {
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
