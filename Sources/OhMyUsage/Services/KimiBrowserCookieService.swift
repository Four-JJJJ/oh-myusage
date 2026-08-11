import Foundation

struct KimiDetectedToken: Equatable {
    let token: String
    let source: String
}

final class KimiBrowserCookieService {
    private let cookieReader: BrowserCookieDatabaseReader
    private let storageReader: BrowserStorageCredentialReader
    private let browserOrderDefault: [KimiBrowserKind] = [.arc, .chrome, .safari, .edge, .brave, .firefox, .opera, .operaGX, .vivaldi, .chromium]

    init(fileManager: FileManager = .default) {
        self.cookieReader = BrowserCookieDatabaseReader(fileManager: fileManager, sqliteTimeout: nil)
        self.storageReader = BrowserStorageCredentialReader(fileManager: fileManager)
    }

    func detectKimiAuthToken(order: [KimiBrowserKind], refreshPaths: Bool = false) -> KimiDetectedToken? {
        for browser in order {
            if let token = tokenFromBrowser(
                browser,
                cookieName: "kimi-auth",
                hostContains: "kimi.com",
                refreshPaths: refreshPaths
            ), KimiJWT.payloadType(token) != "refresh" {
                // A refresh-typed value cannot authenticate API calls; keep it
                // for the refresh flow instead of returning it as access token.
                return KimiDetectedToken(token: token, source: browserLabel(browser))
            }
            let candidates = storageReader.bearerTokenCandidates(
                for: browser,
                hostCandidates: ["www.kimi.com", "kimi.com"],
                source: "\(browserLabel(browser)):localStorage",
                refreshPaths: refreshPaths
            )
            if let selected = Self.preferredAccessToken(in: candidates) {
                return KimiDetectedToken(token: selected.value, source: selected.source)
            }
        }
        return nil
    }

    /// Finds the long-lived web refresh token (kimi-auth cookie or localStorage),
    /// usable to mint a fresh access token via the AuthService RefreshToken RPC.
    func detectKimiRefreshToken(order: [KimiBrowserKind], refreshPaths: Bool = false) -> KimiDetectedToken? {
        for browser in order {
            if let token = tokenFromBrowser(
                browser,
                cookieName: "kimi-auth",
                hostContains: "kimi.com",
                refreshPaths: refreshPaths
            ), KimiJWT.payloadType(token) == "refresh" {
                return KimiDetectedToken(token: token, source: browserLabel(browser))
            }
            let candidates = storageReader.bearerTokenCandidates(
                for: browser,
                hostCandidates: ["www.kimi.com", "kimi.com"],
                source: "\(browserLabel(browser)):localStorage",
                refreshPaths: refreshPaths
            )
            if let refresh = candidates.first(where: { KimiJWT.payloadType($0.value) == "refresh" }) {
                return KimiDetectedToken(token: refresh.value, source: refresh.source)
            }
        }
        return nil
    }

    /// kimi.com localStorage holds both a short-lived access token and a
    /// long-lived refresh token, and expiry-sorted ordering puts the refresh
    /// token first even though the API rejects it ("token type mismatch").
    /// Prefer access-typed JWTs, then unknown shapes, then anything.
    static func preferredAccessToken(in candidates: [BrowserDetectedCredential]) -> BrowserDetectedCredential? {
        if let access = candidates.first(where: { KimiJWT.payloadType($0.value) == "access" }) {
            return access
        }
        return candidates.first(where: { KimiJWT.payloadType($0.value) != "refresh" }) ?? candidates.first
    }

    func detectCookieHeader(
        host: String,
        order: [KimiBrowserKind]? = nil,
        refreshPaths: Bool = false
    ) -> KimiDetectedToken? {
        let actualOrder = order ?? browserOrderDefault
        for browser in actualOrder {
            for path in cookieReader.candidateCookiePaths(for: browser, bypassCache: refreshPaths) {
                if let header = cookieReader.cookieHeader(fromDatabaseAt: path, browser: browser, hostContains: host),
                   !header.isEmpty {
                    return KimiDetectedToken(token: header, source: "\(browserLabel(browser)):cookie")
                }
            }
        }
        return nil
    }

    private func tokenFromBrowser(
        _ browser: KimiBrowserKind,
        cookieName: String,
        hostContains: String,
        refreshPaths: Bool
    ) -> String? {
        for path in cookieReader.candidateCookiePaths(for: browser, bypassCache: refreshPaths) {
            if let token = cookieReader.namedCookieValue(fromDatabaseAt: path, browser: browser, cookieName: cookieName, hostContains: hostContains) {
                return token
            }
        }
        return nil
    }

    private func browserLabel(_ browser: KimiBrowserKind) -> String {
        switch browser {
        case .arc:
            return "auto:Arc"
        case .chrome:
            return "auto:Chrome"
        case .safari:
            return "auto:Safari"
        case .edge:
            return "auto:Edge"
        case .brave:
            return "auto:Brave"
        case .chromium:
            return "auto:Chromium"
        case .firefox:
            return "auto:Firefox"
        case .opera:
            return "auto:Opera"
        case .operaGX:
            return "auto:OperaGX"
        case .vivaldi:
            return "auto:Vivaldi"
        }
    }
}
