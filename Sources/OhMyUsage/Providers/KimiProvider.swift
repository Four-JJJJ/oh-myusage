import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class KimiProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCookieService: any KimiBrowserCookieDetecting
    private let tokenResolverOverride: (() throws -> (token: String, source: String))?
    private let browserTokenResolverOverride: (([KimiBrowserKind], Bool) -> KimiDetectedToken?)?
    private let browserRefreshTokenResolverOverride: (([KimiBrowserKind], Bool) -> KimiDetectedToken?)?

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCookieService: any KimiBrowserCookieDetecting,
        tokenResolverOverride: (() throws -> (token: String, source: String))? = nil,
        browserTokenResolverOverride: (([KimiBrowserKind], Bool) -> KimiDetectedToken?)? = nil,
        browserRefreshTokenResolverOverride: (([KimiBrowserKind], Bool) -> KimiDetectedToken?)? = nil
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.tokenResolverOverride = tokenResolverOverride
        self.browserTokenResolverOverride = browserTokenResolverOverride
        self.browserRefreshTokenResolverOverride = browserRefreshTokenResolverOverride
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let baseURL = URL(string: descriptor.baseURL ?? "https://www.kimi.com")!
        let resolved: (token: String, source: String)
        if let tokenResolverOverride {
            resolved = try tokenResolverOverride()
        } else {
            resolved = try await resolveToken(forceRefresh: forceRefresh)
        }
        let authToken = Self.normalizeToken(resolved.token)
        let sessionInfo = Self.decodeSessionInfo(from: authToken)

        var request = URLRequest(url: baseURL.appending(path: "/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = #"{"scope":["FEATURE_CODING"]}"#.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(authToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue(Locale.preferredLanguages.first ?? "zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")
        if let deviceId = sessionInfo?.deviceId, !deviceId.isEmpty {
            request.setValue(deviceId, forHTTPHeaderField: "x-msh-device-id")
        }
        if let sessionId = sessionInfo?.sessionId, !sessionId.isEmpty {
            request.setValue(sessionId, forHTTPHeaderField: "x-msh-session-id")
        }
        if let trafficId = sessionInfo?.trafficId, !trafficId.isEmpty {
            request.setValue(trafficId, forHTTPHeaderField: "x-traffic-id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            if let message = Self.extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.unauthorizedDetail(message)
            }
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            if let message = Self.extractErrorMessage(from: data), !message.isEmpty {
                throw ProviderError.invalidResponse("http \(http.statusCode): \(message)")
            }
            throw ProviderError.invalidResponse("http \(http.statusCode)")
        }

        return try Self.parseSnapshot(data: data, descriptor: descriptor, authSource: resolved.source)
    }

    static func parseSnapshot(data: Data, descriptor: ProviderDescriptor, authSource: String, now: Date = Date()) throws -> UsageSnapshot {
        if let root = try? JSONSerialization.jsonObject(with: data),
           let parsed = parseSnapshotFromJSONObject(
               root,
               descriptor: descriptor,
               authSource: authSource,
               now: now
           ) {
            return parsed
        }

        let envelope: KimiUsageEnvelope
        do {
            envelope = try JSONDecoder().decode(KimiUsageEnvelope.self, from: data)
        } catch {
            throw ProviderError.invalidResponse("Kimi usage decode failed")
        }

        guard let codingUsage = envelope.usages.first(where: { $0.scope == "FEATURE_CODING" }) ?? envelope.usages.first else {
            throw ProviderError.invalidResponse("missing usages")
        }
        guard let weekly = codingUsage.detail else {
            throw ProviderError.invalidResponse("missing weekly detail")
        }
        guard let window = codingUsage.limits.first(where: { $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE" })?.detail
            ?? codingUsage.limits.first?.detail else {
            throw ProviderError.invalidResponse("missing 5-hour limit detail")
        }

        let weeklyPercent = ratioPercent(remaining: weekly.remaining, limit: weekly.limit)
        let windowPercent = ratioPercent(remaining: window.remaining, limit: window.limit)
        let minPercent = min(weeklyPercent, windowPercent)
        let status: SnapshotStatus = minPercent <= descriptor.threshold.lowRemaining ? .warning : .ok

        var rawMeta: [String: String] = [
            "kimi.authSource": authSource,
            "kimi.weekly.limit": formatNumber(weekly.limit),
            "kimi.weekly.used": formatNumber(weekly.used),
            "kimi.weekly.remaining": formatNumber(weekly.remaining),
            "kimi.weekly.remainingPercent": formatNumber(weeklyPercent),
            "kimi.window5h.limit": formatNumber(window.limit),
            "kimi.window5h.used": formatNumber(window.used),
            "kimi.window5h.remaining": formatNumber(window.remaining),
            "kimi.window5h.remainingPercent": formatNumber(windowPercent),
        ]
        if let epoch = parseISO8601ToEpoch(weekly.resetTime) {
            rawMeta["kimi.weekly.resetAt"] = String(epoch)
        }
        if let epoch = parseISO8601ToEpoch(window.resetTime) {
            rawMeta["kimi.window5h.resetAt"] = String(epoch)
        }

        let note = "Weekly \(Int(weekly.remaining))/\(Int(weekly.limit)) | 5h \(Int(window.remaining))/\(Int(window.limit))"
        let quotaWindows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: weeklyPercent,
                usedPercent: max(0, 100 - weeklyPercent),
                resetAt: Self.parseISO8601ToEpoch(weekly.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .weekly
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-5h",
                title: "5h",
                remainingPercent: windowPercent,
                usedPercent: max(0, 100 - windowPercent),
                resetAt: Self.parseISO8601ToEpoch(window.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .session
            )
        ]

        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: minPercent,
            used: 100 - minPercent,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: note,
            quotaWindows: quotaWindows,
            sourceLabel: authSource,
            accountLabel: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    private static func parseSnapshotFromJSONObject(
        _ root: Any,
        descriptor: ProviderDescriptor,
        authSource: String,
        now: Date
    ) -> UsageSnapshot? {
        guard let usageItems = usageArray(from: root), !usageItems.isEmpty else {
            return nil
        }
        let codingUsage = usageItems.first {
            let scope = stringValue($0["scope"])?.lowercased() ?? ""
            return scope.contains("coding")
        } ?? usageItems[0]

        guard let weekly = usageDetail(from: codingUsage["detail"] ?? codingUsage["usage"] ?? codingUsage["summary"]) else {
            return nil
        }

        let limitItems = dictionaryArray(from: codingUsage["limits"])
            ?? dictionaryArray(from: codingUsage["windows"])
            ?? dictionaryArray(from: codingUsage["window_limits"])
            ?? dictionaryArray(from: codingUsage["windowLimits"])
            ?? []
        let parsedWindows = limitItems.compactMap(parseWindowUsage(from:))
        guard let window = parsedWindows.first(where: isFiveHourWindow(_:)) ?? parsedWindows.first else {
            return nil
        }

        let weeklyPercent = ratioPercent(remaining: weekly.remaining, limit: weekly.limit)
        let windowPercent = ratioPercent(remaining: window.detail.remaining, limit: window.detail.limit)
        let minPercent = min(weeklyPercent, windowPercent)
        let status: SnapshotStatus = minPercent <= descriptor.threshold.lowRemaining ? .warning : .ok

        var rawMeta: [String: String] = [
            "kimi.authSource": authSource,
            "kimi.weekly.limit": formatNumber(weekly.limit),
            "kimi.weekly.used": formatNumber(weekly.used),
            "kimi.weekly.remaining": formatNumber(weekly.remaining),
            "kimi.weekly.remainingPercent": formatNumber(weeklyPercent),
            "kimi.window5h.limit": formatNumber(window.detail.limit),
            "kimi.window5h.used": formatNumber(window.detail.used),
            "kimi.window5h.remaining": formatNumber(window.detail.remaining),
            "kimi.window5h.remainingPercent": formatNumber(windowPercent),
        ]
        if let epoch = parseISO8601ToEpoch(weekly.resetTime) {
            rawMeta["kimi.weekly.resetAt"] = String(epoch)
        }
        if let epoch = parseISO8601ToEpoch(window.detail.resetTime) {
            rawMeta["kimi.window5h.resetAt"] = String(epoch)
        }

        let note = "Weekly \(Int(weekly.remaining))/\(Int(weekly.limit)) | 5h \(Int(window.detail.remaining))/\(Int(window.detail.limit))"
        let quotaWindows = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                remainingPercent: weeklyPercent,
                usedPercent: max(0, 100 - weeklyPercent),
                resetAt: Self.parseISO8601ToEpoch(weekly.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .weekly
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-5h",
                title: "5h",
                remainingPercent: windowPercent,
                usedPercent: max(0, 100 - windowPercent),
                resetAt: Self.parseISO8601ToEpoch(window.detail.resetTime).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                kind: .session
            )
        ]

        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: minPercent,
            used: 100 - minPercent,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: note,
            quotaWindows: quotaWindows,
            sourceLabel: authSource,
            accountLabel: nil,
            extras: [:],
            rawMeta: rawMeta
        )
    }

    private static func usageArray(from root: Any) -> [[String: Any]]? {
        if let map = root as? [String: Any] {
            if let direct = dictionaryArray(from: map["usages"]), !direct.isEmpty {
                return direct
            }
            let wrappedKeys = ["data", "result", "payload", "response", "json"]
            for key in wrappedKeys {
                if let nested = map[key], let found = usageArray(from: nested), !found.isEmpty {
                    return found
                }
            }
            if let firstArray = map.values.first(where: { $0 is [Any] }),
               let array = dictionaryArray(from: firstArray),
               array.contains(where: { $0["scope"] != nil }) {
                return array
            }
            return nil
        }
        if let list = root as? [Any] {
            let maps = list.compactMap { $0 as? [String: Any] }
            return maps.isEmpty ? nil : maps
        }
        return nil
    }

    private static func dictionaryArray(from any: Any?) -> [[String: Any]]? {
        guard let list = any as? [Any] else { return nil }
        let output = list.compactMap { $0 as? [String: Any] }
        return output.isEmpty ? nil : output
    }

    private static func usageDetail(from raw: Any?) -> ParsedUsageDetail? {
        guard let map = raw as? [String: Any] else { return nil }
        let limit = doubleValue(
            map["limit"],
            map["quota_amount"],
            map["quotaAmount"],
            map["total"],
            map["total_amount"],
            map["totalAmount"]
        )
        let remaining = doubleValue(
            map["remaining"],
            map["remaining_amount"],
            map["remainingAmount"],
            map["available"],
            map["available_amount"],
            map["availableAmount"]
        )
        let used = doubleValue(
            map["used"],
            map["used_amount"],
            map["usedAmount"],
            map["consumed"],
            map["consumed_amount"],
            map["consumedAmount"]
        )
        guard let resolvedLimit = limit else { return nil }
        let resolvedRemaining = remaining ?? max(0, resolvedLimit - (used ?? 0))
        let resolvedUsed = used ?? max(0, resolvedLimit - resolvedRemaining)
        return ParsedUsageDetail(
            limit: resolvedLimit,
            used: resolvedUsed,
            remaining: resolvedRemaining,
            resetTime: stringValue(
                map["resetTime"],
                map["reset_time"],
                map["resetAt"],
                map["reset_at"],
                map["next_reset_at"],
                map["nextResetAt"]
            )
        )
    }

    private static func parseWindowUsage(from raw: [String: Any]) -> ParsedWindowUsage? {
        guard let detail = usageDetail(from: raw["detail"] ?? raw["usage"] ?? raw) else {
            return nil
        }
        let window = (raw["window"] as? [String: Any]) ?? raw
        let duration = intValue(window["duration"] ?? window["window_duration"] ?? raw["duration"])
        let timeUnit = stringValue(window["timeUnit"], window["time_unit"], raw["timeUnit"], raw["time_unit"])
        let normalizedMinutes: Int?
        if let duration {
            let unit = (timeUnit ?? "TIME_UNIT_MINUTE").lowercased()
            if unit.contains("minute") {
                normalizedMinutes = duration
            } else if unit.contains("hour") {
                normalizedMinutes = duration * 60
            } else if unit.contains("day") {
                normalizedMinutes = duration * 24 * 60
            } else {
                normalizedMinutes = duration
            }
        } else {
            normalizedMinutes = nil
        }
        let title = stringValue(raw["name"], raw["title"], window["name"], window["title"])
        return ParsedWindowUsage(detail: detail, durationMinutes: normalizedMinutes, timeUnit: timeUnit, title: title)
    }

    private static func isFiveHourWindow(_ window: ParsedWindowUsage) -> Bool {
        if let minutes = window.durationMinutes, minutes == 300 {
            return true
        }
        let title = (window.title ?? "").lowercased()
        return title.contains("5h")
            || title.contains("5 h")
            || title.contains("300")
            || title.contains("session")
    }

    private static func doubleValue(_ values: Any?...) -> Double? {
        for value in values {
            if let value = value as? Double { return value }
            if let value = value as? Int { return Double(value) }
            if let value = value as? NSNumber { return value.doubleValue }
            if let value = value as? String,
               let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int(trimmed) { return parsed }
            if let parsedDouble = Double(trimmed) { return Int(parsedDouble.rounded()) }
        }
        return nil
    }

    private static func stringValue(_ values: Any?...) -> String? {
        for value in values {
            if let value = value as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let value = value as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func resolveToken(forceRefresh: Bool) async throws -> (token: String, source: String) {
        guard let kimiConfig = descriptor.kimiConfig else {
            throw ProviderError.invalidResponse("missing kimi config")
        }
        guard let service = descriptor.auth.keychainService else {
            throw ProviderError.missingCredential("OhMyUsage")
        }

        let manualAccount = kimiConfig.manualTokenAccount
        let autoAccount = "kimi.com/kimi-auth-auto"
        let refreshAccount = "kimi.com/kimi-refresh-auto"

        if let manual = keychain.readToken(service: service, account: manualAccount), !manual.isEmpty {
            let normalized = Self.normalizeToken(manual)
            if !normalized.isEmpty, !KimiJWT.isExpired(normalized) {
                if KimiJWT.payloadType(normalized) == "refresh" {
                    // Users sometimes paste the long-lived refresh token; the
                    // API only accepts access tokens, so exchange it instead.
                    if let exchanged = await refreshWebAccessToken(
                        service: service,
                        autoAccount: autoAccount,
                        refreshAccount: refreshAccount,
                        browserOrder: kimiConfig.browserOrder,
                        allowBrowserDetection: false,
                        explicitRefreshToken: normalized
                    ) {
                        return exchanged
                    }
                } else {
                    return (normalized, "manual")
                }
            }
            if kimiConfig.authMode == .manual {
                throw ProviderError.unauthorized
            }
        } else if kimiConfig.authMode == .manual {
            throw ProviderError.missingCredential(manualAccount)
        }

        guard kimiConfig.autoCookieEnabled else {
            throw ProviderError.missingCredential(manualAccount)
        }

        // Earlier versions could cache the long-lived refresh token in the
        // access slot (it sorted first by expiry). Move it to the refresh
        // slot so the exchange flow can use it instead of replaying it.
        if let cached = keychain.readToken(service: service, account: autoAccount) {
            let normalizedCached = Self.normalizeToken(cached)
            if !normalizedCached.isEmpty, KimiJWT.payloadType(normalizedCached) == "refresh" {
                _ = keychain.saveToken(normalizedCached, service: service, account: refreshAccount)
                _ = keychain.deleteToken(service: service, account: autoAccount)
            }
        }

        let cachedAuto = cachedAutoToken(service: service, account: autoAccount)
        if !forceRefresh, let cachedAuto {
            return cachedAuto
        }

        if forceRefresh {
            let detected = browserTokenResolverOverride?(kimiConfig.browserOrder, true)
                ?? browserCookieService.detectKimiAuthToken(order: kimiConfig.browserOrder, refreshPaths: true)
            if let detected,
               !KimiJWT.isExpired(Self.normalizeToken(detected.token)) {
                let normalized = Self.normalizeToken(detected.token)
                _ = keychain.saveToken(normalized, service: service, account: autoAccount)
                return (normalized, detected.source)
            }

            // The web access token expires about daily; the browser session is
            // usually still alive via its long-lived refresh token — exchange it.
            if let refreshed = await refreshWebAccessToken(
                service: service,
                autoAccount: autoAccount,
                refreshAccount: refreshAccount,
                browserOrder: kimiConfig.browserOrder,
                allowBrowserDetection: true
            ) {
                return refreshed
            }

            if let cachedAuto {
                return cachedAuto
            }
            throw ProviderError.missingCredential(autoAccount)
        }

        // Background path: silently renew with the stored refresh token (no
        // browser disk scan outside an explicit refresh).
        if let refreshed = await refreshWebAccessToken(
            service: service,
            autoAccount: autoAccount,
            refreshAccount: refreshAccount,
            browserOrder: kimiConfig.browserOrder,
            allowBrowserDetection: false
        ) {
            return refreshed
        }
        throw ProviderError.missingCredential(autoAccount)
    }

    private func refreshWebAccessToken(
        service: String,
        autoAccount: String,
        refreshAccount: String,
        browserOrder: [KimiBrowserKind],
        allowBrowserDetection: Bool,
        explicitRefreshToken: String? = nil
    ) async -> (token: String, source: String)? {
        var refreshToken: String?
        var refreshSource = "auto:refresh-cache"
        if let explicitRefreshToken {
            refreshToken = explicitRefreshToken
            refreshSource = "manual"
        } else if allowBrowserDetection {
            let detected = browserRefreshTokenResolverOverride?(browserOrder, true)
                ?? browserCookieService.detectKimiRefreshToken(order: browserOrder, refreshPaths: true)
            if let detected {
                let normalized = Self.normalizeToken(detected.token)
                if !normalized.isEmpty {
                    refreshToken = normalized
                    refreshSource = detected.source
                }
            }
        }
        if refreshToken == nil,
           let cached = keychain.readToken(service: service, account: refreshAccount) {
            let normalized = Self.normalizeToken(cached)
            if !normalized.isEmpty {
                refreshToken = normalized
            }
        }
        guard let refreshToken, !KimiJWT.isExpired(refreshToken) else { return nil }

        var request = URLRequest(url: URL(string: "https://auth.kimi.com/api/account.gateway.v1.AuthService/RefreshToken")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawAccess = (root["accessToken"] as? String) ?? (root["access_token"] as? String) else {
            return nil
        }

        let newAccess = Self.normalizeToken(rawAccess)
        guard !newAccess.isEmpty, !KimiJWT.isExpired(newAccess) else { return nil }

        if let rawRefresh = (root["refreshToken"] as? String) ?? (root["refresh_token"] as? String) {
            let newRefresh = Self.normalizeToken(rawRefresh)
            if !newRefresh.isEmpty {
                _ = keychain.saveToken(newRefresh, service: service, account: refreshAccount)
            }
        }
        _ = keychain.saveToken(newAccess, service: service, account: autoAccount)
        return (newAccess, "\(refreshSource)+refresh")
    }

    private func cachedAutoToken(service: String, account: String) -> (token: String, source: String)? {
        if let cached = keychain.readToken(service: service, account: account),
           !cached.isEmpty {
            let normalized = Self.normalizeToken(cached)
            if !normalized.isEmpty,
               KimiJWT.payloadType(normalized) != "refresh",
               !KimiJWT.isExpired(normalized) {
                return (normalized, "auto:cache")
            }
        }
        return nil
    }

    private static func ratioPercent(remaining: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(100, max(0, (remaining / limit) * 100))
    }

    private static func parseISO8601ToEpoch(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return Int(date.timeIntervalSince1970)
        }
        let fallback = ISO8601DateFormatter()
        if let date = fallback.date(from: raw) {
            return Int(date.timeIntervalSince1970)
        }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func normalizeToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("Bearer ") || token.hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 {
            token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let decoded = token.removingPercentEncoding, decoded.contains(".") {
            token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = root["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = root["error"] as? String {
            return error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let details = root["details"] as? String {
            return details.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let message = (root["error"] as? [String: Any])?["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func decodeSessionInfo(from token: String) -> KimiSessionInfo? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let payloadData = KimiJWT.decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return KimiSessionInfo(
            deviceId: payload["device_id"] as? String,
            sessionId: payload["ssid"] as? String,
            trafficId: payload["sub"] as? String
        )
    }
}

private struct KimiUsageEnvelope: Decodable {
    let usages: [KimiScopeUsage]
}

private struct KimiScopeUsage: Decodable {
    let scope: String
    let detail: KimiUsageDetail?
    let limits: [KimiWindowUsage]
}

private struct KimiWindowUsage: Decodable {
    let window: KimiWindow
    let detail: KimiUsageDetail
}

private struct KimiWindow: Decodable {
    let duration: Int
    let timeUnit: String
}

private struct KimiUsageDetail: Decodable {
    let limit: Double
    let used: Double
    let remaining: Double
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try Self.decodeDouble(container, key: .limit)
        remaining = try Self.decodeDouble(container, key: .remaining)
        if let directUsed = try? Self.decodeDouble(container, key: .used) {
            used = directUsed
        } else {
            used = max(0, limit - remaining)
        }
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
    }

    private static func decodeDouble(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let string = try? container.decode(String.self, forKey: key),
           let value = Double(string) {
            return value
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "invalid number")
    }
}

enum KimiJWT {
    static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return true }
        guard let payloadData = decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let expNumber = payload["exp"] as? NSNumber else {
            return true
        }
        let exp = expNumber.doubleValue
        return exp <= now.timeIntervalSince1970 + 5
    }

    /// The JWT `typ` claim ("access" / "refresh" on kimi.com tokens), lowercased.
    static func payloadType(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = decodeBase64URL(String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        return (payload["typ"] as? String)?.lowercased()
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

private struct KimiSessionInfo {
    let deviceId: String?
    let sessionId: String?
    let trafficId: String?
}

private struct ParsedUsageDetail {
    let limit: Double
    let used: Double
    let remaining: Double
    let resetTime: String?
}

private struct ParsedWindowUsage {
    let detail: ParsedUsageDetail
    let durationMinutes: Int?
    let timeUnit: String?
    let title: String?
}
