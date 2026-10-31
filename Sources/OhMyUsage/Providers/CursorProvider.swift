import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class CursorProvider: UsageProvider, @unchecked Sendable {
    private static let sandUsageStatusURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!
    private let session: URLSession
    private let auth: CursorSessionAuth
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell(),
        stateDatabasePath: String? = nil,
        safeStorage: CursorSafeStorage = .default
    ) {
        self.descriptor = descriptor
        self.session = session
        self.auth = CursorSessionAuth(
            session: session,
            sqlite: sqlite,
            stateDatabasePath: stateDatabasePath ?? CursorSessionAuth.defaultIDEStateDatabasePath(),
            safeStorage: safeStorage
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
        let data = try await requestUsageSummary(accessToken: credentials.accessToken)
        let summary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let summary,
           let sand = await requestSandUsageStatus(accessToken: credentials.accessToken),
           XSubscriptionQuota.isUnified(sand) {
            return Self.parseUnifiedSnapshot(
                sand: sand,
                usageSummary: summary,
                descriptor: descriptor,
                accountLabel: credentials.email
            )
        }

        return try Self.parseSnapshot(
            data: data,
            descriptor: descriptor,
            accountLabel: credentials.email
        )
    }

    private func requestUsageSummary(accessToken: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(CursorSessionAuth.workosCookieHeader(accessToken: accessToken), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Cursor non-http response")
        }
        try HTTPResponseValidation.validate(http, urlDescription: "Cursor", body: data)
        return data
    }

    /// Best-effort. A failure here keeps the legacy usage-summary snapshot.
    private func requestSandUsageStatus(accessToken: String) async -> [String: Any]? {
        var request = URLRequest(url: Self.sandUsageStatusURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(CursorSessionAuth.workosCookieHeader(accessToken: accessToken), forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return root
        } catch {
            return nil
        }
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor, accountLabel: String?) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Cursor usage decode failed")
        }
        let membership = OfficialValueParser.firstPlanLabel([
            root["membershipType"],
            root["membership_type"],
            root["stripeMembershipType"],
            root["planType"],
            root["plan_type"],
            root["plan"],
            root["planName"],
            root["plan_name"]
        ])
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
        let usageNote = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | ")
        var extras: [String: String] = [:]
        if let membership {
            extras["planType"] = membership
        }
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: membership.map { "Plan \($0) | \(usageNote)" } ?? usageNote,
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: [:]
        )
    }

    /// X Subscription: one weekly pool shared with Grok and Grok Bot.
    /// `usage-summary` still reports the old monthly Cursor Models / Other Models split, so it is ignored here.
    internal static func parseUnifiedSnapshot(
        sand: [String: Any],
        usageSummary: [String: Any],
        descriptor: ProviderDescriptor,
        accountLabel: String?
    ) -> UsageSnapshot {
        let usedPercent = XSubscriptionQuota.includedUsedPercent(from: sand)
        let resetAt = XSubscriptionQuota.parseTimestamp(sand["nextResetTimestampUtc"])
            ?? XSubscriptionQuota.parseTimestamp(sand["currentPeriodEnd"])
        let membership = OfficialValueParser.firstPlanLabel([
            usageSummary["membershipType"],
            usageSummary["membership_type"],
            usageSummary["stripeMembershipType"]
        ])
        let planName = CursorSessionAuth.displayPlanName(
            grokPlanLabel: OfficialValueParser.planLabel(sand["grokPlanLabel"]),
            membershipType: membership,
            cursorPlanName: OfficialValueParser.planLabel(sand["cursorPlanName"]),
            isUnified: true
        )

        var windows: [UsageQuotaWindow] = [
            UsageQuotaWindow.percent(
                id: "\(descriptor.id)-weekly",
                title: "Weekly",
                usedPercent: usedPercent,
                resetAt: resetAt,
                kind: .weekly
            )
        ]
        if let onDemand = onDemandWindow(from: usageSummary, descriptor: descriptor, resetAt: resetAt) {
            windows.append(onDemand)
        }

        let remaining = windows.map(\.remainingPercent).min() ?? max(0, 100 - usedPercent)
        let usageNote = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | ")
        var extras: [String: String] = ["quotaScope": XSubscriptionQuota.scope]
        let resolvedPlan = OfficialValueParser.planLabel(planName)
        if let resolvedPlan {
            extras["planType"] = resolvedPlan
        }
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: usedPercent,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: resolvedPlan.map { "Plan \($0) | \(usageNote)" } ?? usageNote,
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: accountLabel,
            extras: extras,
            rawMeta: ["cursor.quotaScope": XSubscriptionQuota.scope]
        )
    }

    private static func onDemandWindow(
        from summary: [String: Any],
        descriptor: ProviderDescriptor,
        resetAt: Date?
    ) -> UsageQuotaWindow? {
        let individual = summary["individualUsage"] as? [String: Any]
        guard let onDemand = individual?["onDemand"] as? [String: Any],
              (onDemand["enabled"] as? Bool) == true,
              let used = OfficialValueParser.double(onDemand["used"]),
              let limit = OfficialValueParser.double(onDemand["limit"]),
              limit > 0 else {
            return nil
        }
        let remainingPercent = max(0, (limit - used) / limit * 100)
        return UsageQuotaWindow(
            id: "\(descriptor.id)-ondemand",
            title: "On-Demand",
            remainingPercent: remainingPercent,
            usedPercent: max(0, 100 - remainingPercent),
            resetAt: resetAt,
            kind: .extraUsage
        )
    }

    private static func percentWindow(
        id: String,
        title: String,
        usedPercent: Double,
        resetAt: Date?
    ) -> UsageQuotaWindow {
        UsageQuotaWindow.percent(
            id: id,
            title: title,
            usedPercent: usedPercent,
            resetAt: resetAt,
            kind: .custom
        )
    }
}
