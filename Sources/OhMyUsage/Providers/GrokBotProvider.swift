import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

/// Cursor Grok Bot weekly Sand usage.
///
/// Authenticates with the same Cursor IDE session cookie as `CursorProvider` and calls
/// `POST /api/dashboard/get-sand-usage-status`. This is separate from xAI Grok CLI billing.
final class GrokBotProvider: UsageProvider, @unchecked Sendable {
    private let authStore: CursorSessionAuthStore
    private let session: URLSession
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        authStore: CursorSessionAuthStore? = nil
    ) {
        self.descriptor = descriptor
        self.session = session
        self.authStore = authStore ?? CursorSessionAuthStore(session: session)
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .grokBot)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Grok Bot 官方来源当前仅支持 API 检测")
        }

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: try authStore.loadAuth(),
            shouldRefresh: { authStore.shouldRefresh(accessToken: $0.accessToken) },
            request: { auth in
                try await self.requestSnapshot(auth: auth)
            },
            refresh: { auth in
                try await authStore.refresh(auth: auth)
            }
        )
        return result.response
    }

    private func requestSnapshot(auth: CursorSessionAuth) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(authStore.sessionCookieHeaderValue(accessToken: auth.accessToken), forHTTPHeaderField: "Cookie")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Grok Bot non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Grok Bot http \(http.statusCode)")
        }

        return try Self.parseSnapshot(
            data: data,
            descriptor: descriptor,
            accountLabel: auth.email
        )
    }

    internal static func parseSnapshot(
        data: Data,
        descriptor: ProviderDescriptor,
        accountLabel: String?
    ) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Grok Bot usage decode failed")
        }

        let hasWeeklyAllowance = (root["hasNonZeroIncludedLimit"] as? Bool) == true
        guard hasWeeklyAllowance else {
            throw ProviderError.unavailable("No Grok Bot weekly allowance")
        }

        guard let usedPercent = OfficialValueParser.double(root["usagePercent"]) else {
            throw ProviderError.invalidResponse("missing Grok Bot usagePercent")
        }

        let resetAt = OfficialValueParser.isoDate(OfficialValueParser.string(root["nextResetTimestampUtc"]))
        let clampedUsed = min(100, max(0, usedPercent))
        let remainingPercent = max(0, 100 - clampedUsed)

        let window = UsageQuotaWindow(
            id: "\(descriptor.id)-weekly",
            title: "Weekly",
            remainingPercent: remainingPercent,
            usedPercent: clampedUsed,
            resetAt: resetAt,
            kind: .weekly
        )

        var rawMeta: [String: String] = [:]
        if let periodStart = OfficialValueParser.string(root["currentPeriodStart"]) {
            rawMeta["grokBot.currentPeriodStart"] = periodStart
        }
        if let hasAvailableUsage = root["hasAvailableUsage"] as? Bool {
            rawMeta["grokBot.hasAvailableUsage"] = hasAvailableUsage ? "true" : "false"
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remainingPercent <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remainingPercent,
            used: clampedUsed,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Weekly \(Int(remainingPercent.rounded()))%",
            quotaWindows: [window],
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: [:],
            rawMeta: rawMeta
        )
    }
}
