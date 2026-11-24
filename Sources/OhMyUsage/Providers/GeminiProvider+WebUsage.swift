import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

extension GeminiProvider {
    static let manualCookieAccount = "official/gemini/cookie-header"
    static let webUsageQuerySignature = "2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g="
    static let webUsageQueryVariables = #"{"g1Request":{"entrypoints":["GEMINI_USAGE_SETTINGS_UPGRADE_BANNER"]},"workspaceRequest":{"recommendationsForSurfaceRequests":[]}}"#
    static let webCookieMatchingHosts = [
        "gemini.google.com",
        ".gemini.google.com",
        "google.com",
        ".google.com"
    ]

    private static let googleAuthCookieNames: Set<String> = [
        "__Secure-1PSID",
        "__Secure-3PSID",
        "SID",
        "__Host-1PLSID",
        "__Host-3PLSID",
        "SAPISID",
        "__Secure-1PAPISID",
        "__Secure-3PAPISID"
    ]

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    func loadFromWeb(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .gemini)
        guard official.webMode != .disabled else {
            throw ProviderError.unavailable(Localizer.systemText(.geminiWebDisabled))
        }
        guard let keychain else {
            throw ProviderError.missingCredential(official.manualCookieAccount ?? Self.manualCookieAccount)
        }

        if official.webMode == .manual {
            guard let stored = readStoredManualCookie(official: official, keychain: keychain) else {
                throw ProviderError.missingCredential(official.manualCookieAccount ?? Self.manualCookieAccount)
            }
            return try await fetchWebSnapshot(cookie: stored)
        }

        // Auto-import mode: use stored working cookie inside rotation window first,
        // then fall back to live multi-profile browser session traversal.
        let storedCookie = readStoredManualCookie(official: official, keychain: keychain)
        if let storedCookie, !forceRefresh {
            do {
                return try await fetchWebSnapshot(cookie: storedCookie)
            } catch let error as ProviderError where Self.isWebAuthFailure(error) {
                // Stored cookie expired: fall through to live browser recovery below.
            }
        }

        guard let browserCookieService else {
            if let storedCookie {
                return try await fetchWebSnapshot(cookie: storedCookie)
            }
            throw ProviderError.missingCredential("gemini.google.com session cookie")
        }

        let backoffKey = "gemini-web:\(official.manualCookieAccount ?? descriptor.id)"
        if !forceRefresh {
            let mayAttempt = await webReadBackoff.shouldAttempt(for: backoffKey, forceRefresh: false)
            if !mayAttempt {
                if let storedCookie {
                    return try await fetchWebSnapshot(cookie: storedCookie)
                }
                throw ProviderError.missingCredential("gemini.google.com session cookie")
            }
        }

        let accessIntent: BrowserCredentialAccessIntent = forceRefresh ? .interactiveImport : .authRecovery
        let rawCandidates = browserCookieService.detectCookieHeaders(
            matchingHosts: Self.webCookieMatchingHosts,
            fallbackHostContains: "google.com",
            order: nil,
            accessIntent: accessIntent
        )

        let sessionCandidates = rawCandidates.compactMap { candidate -> BrowserCookieHeader? in
            guard let normalized = Self.normalizeDetectedWebCookieHeader(candidate.header) else {
                return nil
            }
            return BrowserCookieHeader(
                header: normalized,
                source: candidate.source,
                readBrowserDuringResolution: true,
                pendingPersistHeader: normalized
            )
        }

        var sawRejectedCandidate = false
        var lastNonAuthError: Error?

        for candidate in sessionCandidates {
            do {
                let snapshot = try await fetchWebSnapshot(cookie: candidate)
                persistWebCookie(candidate, official: official, keychain: keychain)
                await webReadBackoff.clearFailure(for: backoffKey)
                return snapshot
            } catch let error as ProviderError where Self.isWebAuthFailure(error) {
                sawRejectedCandidate = true
                continue
            } catch {
                lastNonAuthError = error
                continue
            }
        }

        if let storedCookie, forceRefresh {
            // Browser had no newer signed-in session; keep serving a working pasted/saved cookie.
            if let snapshot = try? await fetchWebSnapshot(cookie: storedCookie) {
                return snapshot
            }
        }

        if let lastNonAuthError {
            throw lastNonAuthError
        }
        if sawRejectedCandidate {
            throw ProviderError.unauthorizedDetail(Localizer.systemText(.geminiWebSessionExpired))
        }

        await webReadBackoff.markFailure(for: backoffKey, interval: 60)
        throw ProviderError.missingCredential("gemini.google.com session cookie")
    }

    func hasConfiguredWebCookieCandidate() -> Bool {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .gemini)
        guard official.webMode != .disabled else { return false }
        if let keychain, readStoredManualCookie(official: official, keychain: keychain) != nil {
            return true
        }
        return official.webMode == .autoImport && browserCookieService != nil
    }

    func webCookieCacheIdentity() -> String? {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .gemini)
        guard let keychain,
              let stored = readStoredManualCookie(official: official, keychain: keychain) else {
            return nil
        }
        return Self.credentialFingerprint(stored.header)
    }

    private func readStoredManualCookie(
        official: OfficialProviderConfig,
        keychain: any TokenCredentialStoring
    ) -> BrowserCookieHeader? {
        let account = official.manualCookieAccount ?? Self.manualCookieAccount
        guard let raw = keychain.readToken(service: Self.credentialServiceName, account: account),
              let normalized = Self.normalizeManualWebCookieHeader(raw) else {
            return nil
        }
        return BrowserCookieHeader(header: normalized, source: "Saved")
    }

    private func persistWebCookie(
        _ cookie: BrowserCookieHeader,
        official: OfficialProviderConfig,
        keychain: any TokenCredentialStoring
    ) {
        let account = official.manualCookieAccount ?? Self.manualCookieAccount
        _ = keychain.saveToken(cookie.header, service: Self.credentialServiceName, account: account)
    }

    private func fetchWebSnapshot(cookie: BrowserCookieHeader) async throws -> UsageSnapshot {
        let url = try webExecuteQueryURL()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(webConsoleOrigin() + "/usage", forHTTPHeaderField: "Referer")
        request.setValue(cookie.header, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Gemini Web non-http response")
        }

        if let finalHost = http.url?.host?.lowercased(),
           finalHost.contains("accounts.google.com") {
            throw ProviderError.unauthorized
        }
        if (300...399).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location")?.lowercased(),
           location.contains("accounts.google.com") || location.contains("servicelogin") {
            throw ProviderError.unauthorized
        }

        try HTTPResponseValidation.validate(
            http,
            urlDescription: "Gemini Web",
            body: data,
            expectingJSON: false
        )

        guard let rawBody = String(data: data, encoding: .utf8), !rawBody.isEmpty else {
            throw ProviderError.invalidResponse("empty Gemini Web response")
        }
        let trimmedLead = rawBody.drop(while: { $0.isWhitespace || $0.isNewline })
        if trimmedLead.first == "<" {
            throw ProviderError.unauthorized
        }

        return try Self.parseWebUsageSnapshot(
            rawBody: rawBody,
            descriptor: descriptor,
            cookieSource: cookie.source
        )
    }

    internal func webExecuteQueryURL() throws -> URL {
        let origin = webConsoleOrigin()
        let encodedSignature = Self.encodeURIComponent(Self.webUsageQuerySignature)
        let encodedVariables = Self.encodeURIComponent(Self.webUsageQueryVariables)
        let urlString =
            "\(origin)/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery" +
            "?query_signature=\(encodedSignature)&variables=\(encodedVariables)"
        guard let url = URL(string: urlString) else {
            throw ProviderError.invalidResponse("invalid Gemini Web GraphQL URL")
        }
        return url
    }

    private func webConsoleOrigin() -> String {
        guard let raw = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return "https://gemini.google.com"
        }
        var candidate = raw.contains("://") ? raw : "https://\(raw)"
        while candidate.hasSuffix("/") {
            candidate.removeLast()
        }
        if let host = URL(string: candidate)?.host?.lowercased(),
           host.contains("cloudcode-pa.googleapis.com") {
            return "https://gemini.google.com"
        }
        return candidate
    }

    internal static func parseWebUsageSnapshot(
        rawBody: String,
        descriptor: ProviderDescriptor,
        cookieSource: String? = nil
    ) throws -> UsageSnapshot {
        let cleaned = stripGoogleXSSIPrefix(rawBody)
        guard let jsonData = cleaned.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
            throw ProviderError.invalidResponse("Gemini Web GraphQL decode failed")
        }

        let dataObjects: [[String: Any]]
        if let array = jsonObject as? [Any] {
            dataObjects = array.compactMap { element in
                guard let envelope = element as? [String: Any] else { return nil }
                return (envelope["data"] as? [String: Any]) ?? envelope
            }
        } else if let dict = jsonObject as? [String: Any] {
            if let data = dict["data"] as? [String: Any] {
                dataObjects = [data]
            } else {
                dataObjects = [dict]
            }
        } else {
            throw ProviderError.invalidResponse("Gemini Web GraphQL unexpected root")
        }

        guard let viewerContainer = dataObjects.first(where: { $0.keys.contains("viewer") }) else {
            throw ProviderError.invalidResponse("Gemini Web GraphQL missing viewer field")
        }
        if viewerContainer["viewer"] is NSNull {
            throw ProviderError.unauthorized
        }
        guard let viewer = viewerContainer["viewer"] as? [String: Any] else {
            throw ProviderError.invalidResponse("Gemini Web GraphQL invalid viewer object")
        }

        let rpcs = viewer["rpcs"] as? [String: Any]
        guard let usageInfo = (rpcs?["getUsageInfo"] as? [String: Any])
            ?? (viewer["getUsageInfo"] as? [String: Any]),
              let poolsRaw = usageInfo["pools"] as? [Any] else {
            throw ProviderError.invalidResponse("Gemini Web GraphQL missing usage pools")
        }

        let pools = poolsRaw.compactMap { $0 as? [String: Any] }
        var windows: [UsageQuotaWindow] = []

        if let fiveHourly = parseWebPoolWindow(
            pools: pools,
            poolType: "GXU_FIVE_HOURLY",
            id: "\(descriptor.id)-session",
            title: "5h",
            kind: .session
        ) {
            windows.append(fiveHourly)
        }

        if let weekly = parseWebPoolWindow(
            pools: pools,
            poolType: "GXU_WEEKLY",
            id: "\(descriptor.id)-weekly",
            title: "Weekly",
            kind: .weekly
        ) {
            windows.append(weekly)
        }

        guard !windows.isEmpty else {
            throw ProviderError.unavailable(Localizer.systemText(.geminiWebPoolsUnavailable))
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let plan = parseWebSubscriptionTier(usageInfo: usageInfo, viewer: viewer)
        let accountEmail = OfficialValueParser.string(
            viewer["email"] ?? viewer["accountEmail"] ?? usageInfo["email"]
        )

        var extras: [String: String] = [:]
        if let plan, !plan.isEmpty {
            extras["planType"] = plan
        }
        if let cookieSource, !cookieSource.isEmpty {
            extras["webCookieSource"] = cookieSource
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: buildNote(plan: plan, windows: windows, projectLabel: nil),
            quotaWindows: windows,
            sourceLabel: "Web",
            accountLabel: accountEmail,
            extras: extras,
            rawMeta: ["gemini.source": "web-graphql"]
        )
    }

    private static func parseWebPoolWindow(
        pools: [[String: Any]],
        poolType: String,
        id: String,
        title: String,
        kind: UsageQuotaKind
    ) -> UsageQuotaWindow? {
        guard let pool = pools.first(where: {
            OfficialValueParser.string($0["poolType"] ?? $0["pool_type"]) == poolType
        }) else {
            return nil
        }

        guard let rawPercent = OfficialValueParser.double(
            pool["percentageUsed"] ?? pool["percentage_used"] ?? pool["usedFraction"]
        ),
              rawPercent.isFinite,
              rawPercent >= 0 else {
            return nil
        }

        let usedPercent: Double
        if rawPercent <= 1.0 {
            usedPercent = min(100, max(0, rawPercent * 100))
        } else {
            usedPercent = min(100, max(0, rawPercent))
        }
        let remainingPercent = max(0, min(100, 100 - usedPercent))

        let gxu = pool["gxu"] as? [String: Any]
        let rawReset = OfficialValueParser.string(
            gxu?["windowRefreshesAt"]
                ?? gxu?["window_refreshes_at"]
                ?? pool["windowRefreshesAt"]
                ?? pool["resetAt"]
                ?? pool["resetsAt"]
        )
        let resetAt = rawReset.flatMap(parseISO8601Date)

        return UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: usedPercent,
            resetAt: resetAt,
            kind: kind
        )
    }

    private static func parseWebSubscriptionTier(
        usageInfo: [String: Any],
        viewer: [String: Any]
    ) -> String? {
        let raw = OfficialValueParser.string(
            usageInfo["subscriptionTier"]
                ?? usageInfo["subscription_tier"]
                ?? usageInfo["planType"]
                ?? viewer["subscriptionTier"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let raw, !raw.isEmpty else { return nil }
        switch raw.uppercased() {
        case "TIER1", "PRO", "AI_PRO", "GOOGLE_ONE_AI_PREMIUM":
            return "pro"
        case "TIER2", "ULTRA", "AI_ULTRA":
            return "ultra"
        case "FREE", "TIER0", "UNSPECIFIED", "SUBSCRIPTION_TIER_UNSPECIFIED":
            return nil
        default:
            let lower = raw.lowercased()
            if lower.contains("ultra") { return "ultra" }
            if lower.contains("pro") || lower.contains("premium") { return "pro" }
            if lower.contains("plus") { return "plus" }
            return OfficialValueParser.nonPlaceholderString(raw)
        }
    }

    internal static func normalizeManualWebCookieHeader(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty else { return nil }
        if value.contains("=") {
            return value
        }
        return "__Secure-1PSID=\(value)"
    }

    internal static func normalizeDetectedWebCookieHeader(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, hasGoogleSessionCookies(trimmed) else {
            return nil
        }
        return trimmed
    }

    internal static func hasGoogleSessionCookies(_ header: String) -> Bool {
        for segment in header.split(separator: ";") {
            let pair = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && googleAuthCookieNames.contains(name) {
                return true
            }
        }
        return false
    }

    private static func stripGoogleXSSIPrefix(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(")]}'") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = OfficialValueParser.isoDate(trimmed) {
            return parsed
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: trimmed) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    private static func encodeURIComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func isWebAuthFailure(_ error: ProviderError) -> Bool {
        switch error {
        case .unauthorized, .unauthorizedDetail:
            return true
        default:
            return false
        }
    }
}
