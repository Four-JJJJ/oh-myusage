import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

/// Grok (xAI) usage provider.
///
/// Reads the Grok CLI login from `~/.grok/auth.json` (or `$GROK_HOME/auth.json`) and calls the
/// same billing endpoint the CLI itself uses: `GET /v1/billing?format=credits` on
/// `cli-chat-proxy.grok.com`. The response is a proto3 message serialized as JSON, so zero-valued
/// fields (for example `creditUsagePercent`) are omitted entirely and must be treated as 0.
final class GrokProvider: UsageProvider, @unchecked Sendable {
    static let defaultOIDCClientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let weeklyPeriodType = "USAGE_PERIOD_TYPE_WEEKLY"
    private static let tokenAuthHeaderValue = "xai-grok-cli"
    private static let refreshURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private static let refreshBuffer: TimeInterval = 5 * 60

    let descriptor: ProviderDescriptor
    private let session: URLSession
    private let homeDirectory: () -> String
    private let environment: () -> [String: String]

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        homeDirectory: @escaping () -> String = { NSHomeDirectory() },
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.descriptor = descriptor
        self.session = session
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        _ = forceRefresh
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .grok)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Grok 官方来源当前仅支持 API 检测")
        }

        let credentials = try loadCredentials()
        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: credentials,
            shouldRefresh: { Self.needsRefresh(expiresAt: $0.expiresAt) },
            request: { [self] state in try await requestBilling(accessToken: state.accessToken) },
            refresh: { [self] state in try await refresh(credentials: state) }
        )

        var snapshot = try Self.parseSnapshot(root: result.response, descriptor: descriptor)
        if let email = result.state.email {
            snapshot.accountLabel = email
            snapshot.authSourceLabel = "Grok CLI"
            snapshot.rawMeta["grok.accountLabel"] = email
        }

        if let plan = try? await requestPlanName(accessToken: result.state.accessToken) {
            snapshot.extras["planType"] = plan
            snapshot.rawMeta["planType"] = plan
            snapshot.note = "Plan \(plan) | \(snapshot.note)"
        }

        return snapshot
    }

    // MARK: - Credentials

    struct GrokCredentials {
        var filePath: String
        var entryKey: String
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var email: String?
        var oidcClientID: String?

        var resolvedClientID: String {
            if let oidcClientID, !oidcClientID.isEmpty {
                return oidcClientID
            }
            let parts = entryKey.components(separatedBy: "::")
            if parts.count > 1, let last = parts.last {
                let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return GrokProvider.defaultOIDCClientID
        }
    }

    internal func authFilePath() -> String {
        Self.resolvedAuthFilePath(homeDirectory: homeDirectory(), environment: environment())
    }

    internal static func resolvedAuthFilePath(homeDirectory: String, environment: [String: String]) -> String {
        if let grokHome = environment["GROK_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grokHome.isEmpty {
            var base = grokHome
            while base.hasSuffix("/") {
                base.removeLast()
            }
            return base + "/auth.json"
        }
        return homeDirectory + "/.grok/auth.json"
    }

    private func loadCredentials() throws -> GrokCredentials {
        let path = authFilePath()
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.missingCredential("~/.grok/auth.json")
        }
        guard let credentials = Self.parseCredentials(json: json, filePath: path) else {
            throw ProviderError.missingCredential("~/.grok/auth.json (no usable entry)")
        }
        return credentials
    }

    internal static func parseCredentials(json: [String: Any], filePath: String) -> GrokCredentials? {
        let candidates: [GrokCredentials] = json.compactMap { entryKey, rawEntry in
            guard let entry = rawEntry as? [String: Any],
                  let accessToken = OfficialValueParser.string(entry["key"]) else {
                return nil
            }
            return GrokCredentials(
                filePath: filePath,
                entryKey: entryKey,
                accessToken: accessToken,
                refreshToken: OfficialValueParser.string(entry["refresh_token"] ?? entry["refresh"]),
                expiresAt: parseDate(OfficialValueParser.string(entry["expires_at"] ?? entry["expires"])),
                email: OfficialValueParser.string(entry["email"]),
                oidcClientID: OfficialValueParser.string(entry["oidc_client_id"])
            )
        }

        // Prefer the entry with the latest expiry so multi-account files pick the freshest login.
        return candidates.max { lhs, rhs in
            (lhs.expiresAt ?? .distantPast) < (rhs.expiresAt ?? .distantPast)
        }
    }

    internal static func needsRefresh(expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= refreshBuffer
    }

    private func refresh(credentials: GrokCredentials) async throws -> GrokCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw ProviderError.unauthorized
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OfficialProviderAuthRuntime.urlEncodedFormData([
            "grant_type": "refresh_token",
            "client_id": credentials.resolvedClientID,
            "refresh_token": refreshToken,
        ])

        let refresh = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
            session: session,
            request: request,
            invalidResponseMessage: "Grok refresh invalid response",
            missingAccessTokenMessage: "missing Grok refresh access_token",
            httpErrorMessage: { "Grok refresh http \($0)" }
        )

        var updated = credentials
        updated.accessToken = refresh.accessToken
        updated.refreshToken = OfficialValueParser.string(refresh.json["refresh_token"]) ?? credentials.refreshToken
        if let expiresIn = OfficialValueParser.double(refresh.json["expires_in"]) {
            updated.expiresAt = Date().addingTimeInterval(expiresIn)
        }

        persist(credentials: updated)
        return updated
    }

    private func persist(credentials: GrokCredentials) {
        OfficialProviderAuthRuntime.updateJSONObjectFile(path: credentials.filePath) { json in
            var entry = (json[credentials.entryKey] as? [String: Any]) ?? [:]
            entry["key"] = credentials.accessToken
            if let refreshToken = credentials.refreshToken {
                entry["refresh_token"] = refreshToken
            }
            if let expiresAt = credentials.expiresAt {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                entry["expires_at"] = formatter.string(from: expiresAt)
            }
            json[credentials.entryKey] = entry
        }
    }

    // MARK: - Requests

    private func normalizedBaseURL() -> String {
        var base = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = "https://cli-chat-proxy.grok.com"
        }
        if !base.contains("://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    private func requestBilling(accessToken: String) async throws -> [String: Any] {
        guard let url = URL(string: normalizedBaseURL() + "/v1/billing?format=credits") else {
            throw ProviderError.invalidResponse("invalid Grok billing URL")
        }
        let data = try await requestJSON(url: url, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Grok billing decode failed")
        }
        return root
    }

    private func requestPlanName(accessToken: String) async throws -> String? {
        guard let url = URL(string: normalizedBaseURL() + "/v1/settings") else {
            return nil
        }
        let data = try await requestJSON(url: url, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return OfficialValueParser.nonPlaceholderString(root["subscription_tier_display"])
    }

    private func requestJSON(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.tokenAuthHeaderValue, forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Grok non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Grok http \(http.statusCode)")
        }
        return data
    }

    // MARK: - Parsing

    internal static func parseSnapshot(root: [String: Any], descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let config = root["config"] as? [String: Any] else {
            throw ProviderError.invalidResponse("missing Grok billing config")
        }
        guard let period = config["currentPeriod"] as? [String: Any],
              let periodType = OfficialValueParser.string(period["type"]),
              let periodEnd = parseDate(OfficialValueParser.string(period["end"])) else {
            throw ProviderError.invalidResponse("missing Grok billing period")
        }

        // proto-JSON omits zero-valued fields, so an absent percent means a genuine 0%.
        let usedPercent = min(100, max(0, OfficialValueParser.double(config["creditUsagePercent"]) ?? 0))
        let remainingPercent = max(0, 100 - usedPercent)

        let isWeekly = periodType == weeklyPeriodType
        var windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-\(isWeekly ? "weekly" : "period")",
                title: isWeekly ? "Weekly" : "Period",
                remainingPercent: remainingPercent,
                usedPercent: usedPercent,
                resetAt: periodEnd,
                kind: isWeekly ? .weekly : .custom
            )
        ]

        let onDemandCap = OfficialValueParser.double((config["onDemandCap"] as? [String: Any])?["val"]) ?? 0
        let onDemandUsed = OfficialValueParser.double((config["onDemandUsed"] as? [String: Any])?["val"]) ?? 0
        if onDemandCap > 0 {
            let paygUsedPercent = min(100, max(0, onDemandUsed / onDemandCap * 100))
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-payg",
                    title: "PAYG",
                    remainingPercent: max(0, 100 - paygUsedPercent),
                    usedPercent: paygUsedPercent,
                    resetAt: periodEnd,
                    kind: .extraUsage
                )
            )
        }

        var extras: [String: String] = [:]
        if onDemandCap > 0 {
            extras["payAsYouGoCap"] = formatUnits(onDemandCap)
            extras["payAsYouGoUsed"] = formatUnits(onDemandUsed)
        }

        let note = windows
            .map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
            .joined(separator: " | ")

        return UsageSnapshot(
            source: descriptor.id,
            status: remainingPercent <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remainingPercent,
            used: usedPercent,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: extras,
            rawMeta: ["grok.periodType": periodType]
        )
    }

    /// xAI timestamps carry microsecond precision (`2026-08-13T03:47:03.411698+00:00`), which
    /// `ISO8601DateFormatter` rejects. Trim the fractional part to milliseconds before parsing.
    internal static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = OfficialValueParser.isoDate(raw) {
            return date
        }
        let trimmed = raw.replacingOccurrences(
            of: #"\.(\d{3})\d+"#,
            with: ".$1",
            options: .regularExpression
        )
        return OfficialValueParser.isoDate(trimmed)
    }

    private static func formatUnits(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
