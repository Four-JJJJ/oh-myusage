import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

enum RelayBrowserRecoveryChannel: String {
    case balance
    case token
}

private actor BrowserRecoveryBackoff {
    private var blockedUntil: [String: Date] = [:]
    private var lastBrowserCookieReadAt: [String: Date] = [:]

    func shouldAttempt(for key: String, forceRefresh: Bool, now: Date = Date()) -> Bool {
        if forceRefresh {
            return true
        }
        guard let deadline = blockedUntil[key] else {
            return true
        }
        return now >= deadline
    }

    func markFailure(for key: String, interval: TimeInterval, now: Date = Date()) {
        blockedUntil[key] = now.addingTimeInterval(max(0, interval))
    }

    func clearFailure(for key: String) {
        blockedUntil.removeValue(forKey: key)
    }

    /// Session cookies such as XiaomiMIMO's have no refresh token, so browser
    /// modes re-read the live browser cookie on a fixed cadence and swap it in
    /// before the saved copy expires. The cadence is what keeps background
    /// polls from decrypting browser cookie stores on every fetch.
    func shouldProactivelyReadBrowserCookie(
        for key: String,
        minimumInterval: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let lastReadAt = lastBrowserCookieReadAt[key] else {
            return true
        }
        return now.timeIntervalSince(lastReadAt) >= max(0, minimumInterval)
    }

    func markBrowserCookieRead(for key: String, now: Date = Date()) {
        lastBrowserCookieReadAt[key] = now
    }
}

struct RelayRecoveryPolicy {
    private static let browserRecoveryBackoff = BrowserRecoveryBackoff()

    /// How often browser-first and browser-only modes re-read a live browser
    /// cookie while the saved one still works. Short enough to rotate a
    /// session cookie before it expires, long enough that background polling
    /// does not touch browser storage every cycle.
    static let proactiveBrowserCookieReadInterval: TimeInterval = 30 * 60

    let descriptor: ProviderDescriptor
    let credentialResolver: RelayCredentialResolver
    let browserRecoveryBackoffInterval: TimeInterval

    func recoveryTrigger(for error: ProviderError) -> String? {
        switch error {
        case .unauthorized:
            return "http401"
        case .unauthorizedDetail:
            return "credentialRejected"
        case .invalidResponse(let detail):
            let normalized = detail.lowercased()
            if normalized.contains("json decode failed") || normalized.contains("auth page") {
                return "nonJsonAuthPage"
            }
            return nil
        default:
            return nil
        }
    }

    func relaySupportsBrowserRecovery(
        manifest: RelayAdapterManifest,
        channel: RelayBrowserRecoveryChannel
    ) -> Bool {
        switch channel {
        case .balance:
            return manifest.authStrategies.contains(where: {
                switch $0.kind {
                case .browserBearer, .browserCookieHeader, .namedCookie:
                    return true
                default:
                    return false
                }
            })
        case .token:
            return manifest.authStrategies.contains(where: { $0.kind == .browserBearer })
        }
    }

    func canAttemptBrowserRecovery(
        host: String,
        channel: RelayBrowserRecoveryChannel,
        forceRefresh: Bool
    ) async -> Bool {
        await Self.browserRecoveryBackoff.shouldAttempt(
            for: browserRecoveryKey(host: host, channel: channel),
            forceRefresh: forceRefresh
        )
    }

    func clearBrowserRecoveryFailure(host: String, channel: RelayBrowserRecoveryChannel) async {
        await Self.browserRecoveryBackoff.clearFailure(
            for: browserRecoveryKey(host: host, channel: channel)
        )
    }

    func markBrowserRecoveryFailure(host: String, channel: RelayBrowserRecoveryChannel) async {
        await Self.browserRecoveryBackoff.markFailure(
            for: browserRecoveryKey(host: host, channel: channel),
            interval: browserRecoveryBackoffInterval
        )
    }

    /// Session cookies have no refresh token, so cookie-only adapters rotate
    /// the browser copy on the same cadence. Adapters that also accept a
    /// bearer are left out: their saved credential is usually an API key the
    /// user pasted, and a background poll must not replace it with whatever
    /// the browser happens to hold.
    func supportsProactiveBrowserCookieRotation(manifest: RelayAdapterManifest) -> Bool {
        let kinds = Set(manifest.authStrategies.map(\.kind))
        let readsBrowserCookie = kinds.contains(.browserCookieHeader) || kinds.contains(.namedCookie)
        return readsBrowserCookie && !kinds.contains(.savedBearer) && !kinds.contains(.browserBearer)
    }

    func shouldProactivelyReadBrowserCookie(
        host: String,
        channel: RelayBrowserRecoveryChannel,
        minimumInterval: TimeInterval = proactiveBrowserCookieReadInterval
    ) async -> Bool {
        await Self.browserRecoveryBackoff.shouldProactivelyReadBrowserCookie(
            for: browserRecoveryKey(host: host, channel: channel),
            minimumInterval: minimumInterval
        )
    }

    func markProactiveBrowserCookieRead(host: String, channel: RelayBrowserRecoveryChannel) async {
        await Self.browserRecoveryBackoff.markBrowserCookieRead(
            for: browserRecoveryKey(host: host, channel: channel)
        )
    }

    func makeRecoveryMetadata(trigger: String, source: String) -> [String: String] {
        [
            "succeeded": "true",
            "trigger": trigger,
            "source": source,
            "at": ISO8601DateFormatter().string(from: Date())
        ]
    }

    func relayRequiredInputError(
        manifest: RelayAdapterManifest,
        request: ResolvedRelayRequest
    ) -> ProviderError? {
        if request.userID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
           manifest.setup?.requiredInputs.contains(.userID) == true {
            if manifest.id == "minimax" {
                return .unauthorizedDetail("MiniMax needs GroupId before it can query balance. Fill User ID with the GroupId from the account request URL, for example /account/query_balance?GroupId=...")
            }
            let fieldName = request.userIDHeader.caseInsensitiveCompare("New-Api-User") == .orderedSame ? "User ID" : request.userIDHeader
            return .unauthorizedDetail("\(manifest.displayName) needs \(fieldName) before it can query balance. Fill the User ID field in site settings and try again.")
        }
        return nil
    }

    func relayBalancePreflightError(
        baseURL: URL,
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig,
        request: ResolvedRelayRequest,
        credentialMode: RelayCredentialMode,
        primaryCandidates: [RelayCredentialCandidate],
        fallbackCandidates: [RelayCredentialCandidate]
    ) -> ProviderError? {
        let allCandidates = primaryCandidates + fallbackCandidates
        let savedRaw = credentialResolver.readSavedCredential(auth: relayConfig.balanceAuth)

        if let inputError = relayRequiredInputError(manifest: manifest, request: request) {
            return inputError
        }

        guard allCandidates.isEmpty else {
            return nil
        }

        switch manifest.id {
        case "moonshot":
            if let savedRaw,
               credentialResolver.looksLikeCookieHeader(savedRaw),
               credentialResolver.looksLikeMoonshotNonAuthCookieHeader(savedRaw) {
                return .unauthorizedDetail("Moonshot cookie looks incomplete. Paste the full Cookie header from an authenticated platform request, or paste Authorization: Bearer ... instead.")
            }
            if credentialMode != .manualPreferred {
                return .unauthorizedDetail("No live Moonshot login was found in the browser. Log in to platform.moonshot.cn first, or switch back to Manual First and paste a bearer token.")
            }
            return .unauthorizedDetail("No usable Moonshot credential was found. Paste an Authorization bearer token, or switch to Browser First and make sure platform.moonshot.cn is logged in.")
        case "xiaomimimo":
            if let savedRaw, !savedRaw.lowercased().contains("api-platform_servicetoken") {
                return .unauthorizedDetail("XiaomiMIMO cookie looks incomplete. Paste the full Cookie header, or just the api-platform_serviceToken value.")
            }
            if credentialMode != .manualPreferred {
                return .unauthorizedDetail("No live XiaomiMIMO login was found in the browser. Log in to platform.xiaomimimo.com first; if it is already logged in, grant Full Disk Access and approve Arc/Chrome Safe Storage keychain access, then test again.")
            }
            return .unauthorizedDetail("No usable XiaomiMIMO cookie was found. Paste the full Cookie header, or switch to Browser First and make sure platform.xiaomimimo.com is logged in.")
        case "xiaomimimo-token-plan":
            if let savedRaw, !savedRaw.lowercased().contains("api-platform_servicetoken") {
                return .unauthorizedDetail("XiaomiMIMO Token Plan cookie looks incomplete. Paste the full Cookie header, or just the api-platform_serviceToken value.")
            }
            if credentialMode != .manualPreferred {
                return .unauthorizedDetail("No live XiaomiMIMO Token Plan login was found in the browser. Log in to platform.xiaomimimo.com first; if it is already logged in, grant Full Disk Access and approve Arc/Chrome Safe Storage keychain access, then test again.")
            }
            return .unauthorizedDetail("No usable XiaomiMIMO Token Plan cookie was found. Paste the full Cookie header, or switch to Browser First and make sure platform.xiaomimimo.com is logged in.")
        case "minimax":
            if credentialMode != .manualPreferred {
                return .unauthorizedDetail("No live MiniMax login was found in the browser. Log in to platform.minimaxi.com first, or switch back to Manual First and paste the full Cookie header.")
            }
            return .unauthorizedDetail("No usable MiniMax cookie was found. Paste the full Cookie header, and make sure GroupId is filled in User ID.")
        case "ailinyu":
            return .unauthorizedDetail("No usable open.ailinyu.de cookie was found. Paste the full Cookie header, and check that User ID matches your site account.")
        case "deepseek":
            if credentialMode != .manualPreferred {
                return .unauthorizedDetail("No platform.deepseek.com login was found in the browser. Log in to platform.deepseek.com (note: chat.deepseek.com is a different site) in Chrome, Arc, Edge or another Chromium browser — Safari and Firefox logins cannot be read — then test again. You can also paste your userToken or an API key (sk-...) directly.")
            }
            return .unauthorizedDetail("No usable DeepSeek credential was found. Paste your platform.deepseek.com userToken (DevTools → Application → Local Storage → userToken) or an API key (sk-...) from the API Keys page, or switch to Browser First after logging in.")
        default:
            let host = baseURL.host?.lowercased() ?? descriptor.name
            if credentialMode == .manualPreferred {
                return .unauthorizedDetail("No usable credential was found for \(manifest.displayName). Paste the required cookie/token, or switch to Browser First if \(host) supports browser login.")
            }
            return .unauthorizedDetail("No usable credential was found for \(manifest.displayName). Paste the required cookie/token, or switch to Browser First and make sure the site is logged in.")
        }
    }

    func relayFriendlyBalanceError(
        _ error: ProviderError,
        baseURL: URL,
        manifest: RelayAdapterManifest,
        request: ResolvedRelayRequest,
        credentialMode: RelayCredentialMode
    ) -> ProviderError {
        let _ = (baseURL, request, credentialMode)
        switch error {
        case .unauthorized:
            switch manifest.id {
            case "moonshot":
                if credentialMode == .manualPreferred {
                    return .unauthorizedDetail("Moonshot login expired. The saved credential cannot renew itself. Switch to Browser First to re-import it automatically while platform.moonshot.cn stays logged in, or paste a fresh token.")
                }
                return .unauthorizedDetail("Moonshot login expired and no newer login was found in the browser. Log in again at platform.moonshot.cn, or paste a fresh token.")
            case "xiaomimimo":
                return sessionCookieExpiredError(
                    siteName: "XiaomiMIMO",
                    loginURL: "platform.xiaomimimo.com",
                    credentialMode: credentialMode
                )
            case "xiaomimimo-token-plan":
                return sessionCookieExpiredError(
                    siteName: "XiaomiMIMO Token Plan",
                    loginURL: "platform.xiaomimimo.com",
                    credentialMode: credentialMode
                )
            case "minimax":
                return sessionCookieExpiredError(
                    siteName: "MiniMax",
                    loginURL: "platform.minimaxi.com",
                    credentialMode: credentialMode
                )
            case "deepseek":
                if credentialMode == .manualPreferred {
                    return .unauthorizedDetail("DeepSeek rejected the saved credential. It cannot renew itself. Switch to Browser First to re-import the browser login automatically, or paste a valid API key (sk-...) or a fresh platform.deepseek.com userToken.")
                }
                return .unauthorizedDetail("DeepSeek rejected the credential and no newer login was found in the browser. Log in again at platform.deepseek.com, or paste a valid API key (sk-...) or a fresh userToken.")
            default:
                if supportsProactiveBrowserCookieRotation(manifest: manifest) {
                    return sessionCookieExpiredError(
                        siteName: manifest.displayName,
                        loginURL: baseURL.host?.lowercased() ?? manifest.displayName,
                        credentialMode: credentialMode
                    )
                }
                if credentialMode == .manualPreferred {
                    return .unauthorizedDetail("The saved credential for \(manifest.displayName) is no longer valid and cannot renew itself. Switch to Browser First to re-import the browser login automatically, or paste a fresh credential.")
                }
                return .unauthorizedDetail("\(manifest.displayName) rejected the credential and no newer login was found in the browser. Log in again, or paste a fresh credential.")
            }
        case .invalidResponse(let detail):
            if manifest.id == "xiaomimimo-token-plan",
               detail.localizedCaseInsensitiveContains("no active subscription") {
                return .invalidResponse("XiaomiMIMO Token Plan has no active subscription. Subscribe or renew a Token Plan at platform.xiaomimimo.com, then test the connection again.")
            }
            if manifest.id == "xiaomimimo-token-plan",
               detail.contains("xiaomimimo token plan") {
                return .invalidResponse("XiaomiMIMO Token Plan connected, but the package detail or usage payload did not contain expected fields. Re-login in browser first; if it still fails, the site response likely changed. \(detail)")
            }
            if detail.contains("missing remaining path") {
                switch manifest.id {
                case "moonshot":
                    return .invalidResponse("Moonshot connected, but the returned payload still does not contain balance fields. Try Browser First and Test Connection again; if it still fails, the site response likely changed and the template needs an update.")
                case "xiaomimimo":
                    return .invalidResponse("XiaomiMIMO connected, but the balance payload did not contain balance fields. Re-login in browser first; if it still fails, the site response likely changed.")
                case "xiaomimimo-token-plan":
                    return .invalidResponse("XiaomiMIMO Token Plan connected, but the package usage payload did not contain expected fields. Re-login in browser first; if it still fails, the site response likely changed.")
                case "minimax":
                    return .invalidResponse("MiniMax connected, but the balance payload did not contain balance fields. Make sure GroupId is correct; if it is, the site response likely changed and the template needs an update.")
                default:
                    return .invalidResponse("\(manifest.displayName) connected, but the current response does not match the template. Test Connection can help re-check the site, or open Advanced settings if the site response changed.")
                }
            }
            if detail.contains("account balance JSON decode failed") || detail.contains("auth page html response") {
                return .invalidResponse("\(manifest.displayName) returned a non-JSON page. This usually means the credential is expired, the request was redirected to a login page, or the site is blocking the current auth method.")
            }
            return error
        default:
            return error
        }
    }

    /// One wording for every session-cookie site: Manual First can only be
    /// re-pasted, while browser modes renew themselves as long as the site
    /// stays logged in.
    private func sessionCookieExpiredError(
        siteName: String,
        loginURL: String,
        credentialMode: RelayCredentialMode
    ) -> ProviderError {
        if credentialMode == .manualPreferred {
            return .unauthorizedDetail("\(siteName) login expired. The saved Cookie cannot renew itself. Switch to Browser First to re-import it automatically while \(loginURL) stays logged in, or paste a fresh Cookie.")
        }
        return .unauthorizedDetail("\(siteName) login expired and no newer login was found in the browser. Log in again at \(loginURL); if it is already logged in, grant Full Disk Access and approve Arc/Chrome Safe Storage keychain access, then test again.")
    }

    func relayTokenPreflightError(
        baseURL: URL,
        credentialMode: RelayCredentialMode,
        manifest: RelayAdapterManifest
    ) -> ProviderError {
        guard credentialMode != .manualPreferred else {
            return .missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
        }
        let host = baseURL.host?.lowercased() ?? baseURL.absoluteString
        if relaySupportsBrowserRecovery(manifest: manifest, channel: .token) {
            return .unauthorizedDetail("No usable browser credential was found for \(host). Log in in the browser first, or switch back to Manual First and paste a token.")
        }
        return .missingCredential(descriptor.auth.keychainAccount ?? descriptor.id)
    }

    func relayFriendlyTokenError(_ error: ProviderError, baseURL: URL) -> ProviderError {
        switch error {
        case .unauthorized:
            return .unauthorizedDetail("The saved token for \(baseURL.host ?? descriptor.name) is no longer valid. Paste a fresh token or switch to Browser First if the site supports browser auth.")
        case .invalidResponse(let detail) where detail.contains("account balance JSON decode failed") || detail.contains("auth page html response"):
            return .invalidResponse("\(baseURL.host ?? descriptor.name) returned a non-JSON page. This usually means the credential is expired, the request was redirected to a login page, or the site is blocking the current auth method.")
        default:
            return error
        }
    }

    private func browserRecoveryKey(host: String, channel: RelayBrowserRecoveryChannel) -> String {
        "\(descriptor.id)|\(host)|\(channel.rawValue)"
    }
}
