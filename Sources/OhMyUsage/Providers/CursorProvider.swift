import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class CursorProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let auth: CursorSessionAuth
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell(),
        stateDatabasePath: String? = nil
    ) {
        self.descriptor = descriptor
        self.session = session
        self.auth = CursorSessionAuth(
            session: session,
            sqlite: sqlite,
            stateDatabasePath: stateDatabasePath ?? CursorSessionAuth.defaultIDEStateDatabasePath()
        )
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .cursor)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Cursor 官方来源当前仅支持 API 检测")
        }

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: try auth.loadIDE(),
            shouldRefresh: { credentials in
                CursorSessionAuth.needsRefresh(accessToken: credentials.accessToken)
            },
            request: { credentials in
                try await self.requestSnapshot(credentials: credentials)
            },
            refresh: { credentials in
                try await self.auth.refresh(credentials)
            }
        )
        return result.response
    }

    private func requestSnapshot(credentials: CursorSessionCredentials) async throws -> UsageSnapshot {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(CursorSessionAuth.workosCookieHeader(accessToken: credentials.accessToken), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Cursor non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Cursor http \(http.statusCode)")
        }

        return try Self.parseSnapshot(
            data: data,
            descriptor: descriptor,
            accountLabel: credentials.email
        )
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor, accountLabel: String?) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Cursor usage decode failed")
        }
        let membership = OfficialValueParser.string(root["membershipType"]) ?? "unknown"
        let resetAt = OfficialValueParser.isoDate(OfficialValueParser.string(root["billingCycleEnd"]))
        let individual = root["individualUsage"] as? [String: Any]

        var windows: [UsageQuotaWindow] = []
        if let plan = individual?["plan"] as? [String: Any],
           (plan["enabled"] as? Bool) == true {
            let autoPercentUsed = OfficialValueParser.double(plan["autoPercentUsed"])
            let apiPercentUsed = OfficialValueParser.double(plan["apiPercentUsed"])

            // Cursor dashboard now tracks two included pools:
            // autoPercentUsed → Cursor Models (Grok / Composer)
            // apiPercentUsed → Other Models (third-party API)
            if autoPercentUsed != nil || apiPercentUsed != nil {
                if let autoPercentUsed {
                    windows.append(
                        percentWindow(
                            id: "\(descriptor.id)-cursor-models",
                            title: "Cursor Models",
                            usedPercent: autoPercentUsed,
                            resetAt: resetAt
                        )
                    )
                }
                if let apiPercentUsed {
                    windows.append(
                        percentWindow(
                            id: "\(descriptor.id)-other-models",
                            title: "Other Models",
                            usedPercent: apiPercentUsed,
                            resetAt: resetAt
                        )
                    )
                }
            } else {
                let used = OfficialValueParser.double(plan["used"]) ?? 0
                let limit = OfficialValueParser.double(plan["limit"] ?? (plan["breakdown"] as? [String: Any])?["total"]) ?? 0
                if limit > 0 {
                    let remainingPercent = max(0, (limit - used) / limit * 100)
                    windows.append(
                        UsageQuotaWindow(
                            id: "\(descriptor.id)-monthly",
                            title: "Monthly",
                            remainingPercent: remainingPercent,
                            usedPercent: max(0, 100 - remainingPercent),
                            resetAt: resetAt,
                            kind: .custom
                        )
                    )
                }
            }
        }
        if let onDemand = individual?["onDemand"] as? [String: Any],
           (onDemand["enabled"] as? Bool) == true,
           let used = OfficialValueParser.double(onDemand["used"]),
           let limit = OfficialValueParser.double(onDemand["limit"]), limit > 0 {
            let remainingPercent = max(0, (limit - used) / limit * 100)
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-ondemand",
                    title: "On-Demand",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Cursor quota windows")
        }
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: "Plan \(membership) | " + windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: ["planType": membership],
            rawMeta: [:]
        )
    }

    private static func percentWindow(
        id: String,
        title: String,
        usedPercent: Double,
        resetAt: Date?
    ) -> UsageQuotaWindow {
        let clampedUsed = min(100, max(0, usedPercent))
        return UsageQuotaWindow(
            id: id,
            title: title,
            remainingPercent: max(0, 100 - clampedUsed),
            usedPercent: clampedUsed,
            resetAt: resetAt,
            kind: .custom
        )
    }
}
