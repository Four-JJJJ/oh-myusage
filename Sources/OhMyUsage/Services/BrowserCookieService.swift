import Foundation

final class BrowserCookieService: BrowserCookieDetecting {
    private static let defaultBrowserOrder: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]

    private let cookieReader: BrowserCookieDatabaseReader
    private let browserOrderDefault: [KimiBrowserKind]

    init(fileManager: FileManager = .default) {
        self.cookieReader = BrowserCookieDatabaseReader(fileManager: fileManager, sqliteTimeout: 5)
        self.browserOrderDefault = BrowserCookieService.defaultBrowserOrder
    }

    init(
        cookieReader: BrowserCookieDatabaseReader,
        browserOrder: [KimiBrowserKind] = BrowserCookieService.defaultBrowserOrder
    ) {
        self.cookieReader = cookieReader
        self.browserOrderDefault = browserOrder
    }

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]? = nil,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectCookieHeader(
            hostContains: hostContains,
            order: order,
            accessIntent: accessIntent,
            refreshPaths: false
        )
    }

    func detectCookieHeader(
        hostContains: String,
        order: [KimiBrowserKind]? = nil,
        accessIntent: BrowserCredentialAccessIntent,
        refreshPaths: Bool
    ) -> BrowserCookieHeader? {
        guard accessIntent.allowsLiveLookup else { return nil }
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in cookieReader.candidateCookiePaths(
                for: browser,
                includeSafariBinaryCookies: true,
                bypassCache: refreshPaths
            ) {
                if let header = cookieReader.cookieHeader(
                    fromDatabaseAt: path,
                    browser: browser,
                    hostContains: hostContains,
                    accessIntent: accessIntent
                ),
                   !header.isEmpty {
                    return BrowserCookieHeader(header: header, source: browserLabel(browser))
                }
            }
        }
        return nil
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]? = nil,
        accessIntent: BrowserCredentialAccessIntent
    ) -> BrowserCookieHeader? {
        detectNamedCookie(
            name: name,
            hostContains: hostContains,
            order: order,
            accessIntent: accessIntent,
            refreshPaths: false
        )
    }

    func detectNamedCookie(
        name: String,
        hostContains: String,
        order: [KimiBrowserKind]? = nil,
        accessIntent: BrowserCredentialAccessIntent,
        refreshPaths: Bool
    ) -> BrowserCookieHeader? {
        guard accessIntent.allowsLiveLookup else { return nil }
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in cookieReader.candidateCookiePaths(
                for: browser,
                includeSafariBinaryCookies: true,
                bypassCache: refreshPaths
            ) {
                if let value = cookieReader.namedCookieValue(
                    fromDatabaseAt: path,
                    browser: browser,
                    cookieName: name,
                    hostContains: hostContains,
                    accessIntent: accessIntent
                ),
                   !value.isEmpty {
                    return BrowserCookieHeader(header: "\(name)=\(value)", source: browserLabel(browser))
                }
            }
        }
        return nil
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "Auto:Arc"
        case .chrome:
            return "Auto:Chrome"
        case .safari:
            return "Auto:Safari"
        case .edge:
            return "Auto:Edge"
        case .brave:
            return "Auto:Brave"
        case .chromium:
            return "Auto:Chromium"
        case .firefox:
            return "Auto:Firefox"
        case .opera:
            return "Auto:Opera"
        case .operaGX:
            return "Auto:OperaGX"
        case .vivaldi:
            return "Auto:Vivaldi"
        }
    }
}
