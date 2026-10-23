import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

extension RelayResponseInterpreter {
    static func extractSub2APIUsageValues(
        root: Any,
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate
    ) throws -> AccountChannelResult {
        if let error = sub2APIUsageError(from: root) {
            throw error
        }
        guard let body = root as? [String: Any] else {
            throw ProviderError.invalidResponse("Sub2API /v1/usage response is not an object")
        }

        let extraMeta: [String: String] = [
            "endpointPath": RelayRequestResolver.normalizedPath(request.path),
            "requestMethod": request.method,
            "remainingPath": request.remainingExpression,
            "usedPath": request.usedExpression ?? "",
            "limitPath": request.limitExpression ?? "",
            "authSource": candidate.source
        ]

        if let subscription = body["subscription"] as? [String: Any] {
            return try extractSub2APISubscriptionValues(
                body: body,
                subscription: subscription,
                extraMeta: extraMeta
            )
        }
        if let quota = body["quota"] as? [String: Any] {
            return try extractSub2APIQuotaValues(
                body: body,
                quota: quota,
                extraMeta: extraMeta
            )
        }
        if let rateLimits = body["rate_limits"] as? [Any], !rateLimits.isEmpty {
            return try extractSub2APIRateLimitValues(
                body: body,
                rateLimits: rateLimits,
                extraMeta: extraMeta
            )
        }
        return try extractSub2APIWalletValues(body: body, extraMeta: extraMeta)
    }

    private static func extractSub2APISubscriptionValues(
        body: [String: Any],
        subscription: [String: Any],
        extraMeta: [String: String]
    ) throws -> AccountChannelResult {
        let remaining = OfficialValueParser.double(body["remaining"])
        let isUnlimited = remaining.map { $0 < 0 } ?? false
        let windows = sub2APISubscriptionWindows(from: subscription)
        let monthlyLimit = OfficialValueParser.double(subscription["monthly_limit_usd"])
        let weeklyLimit = OfficialValueParser.double(subscription["weekly_limit_usd"])
        let dailyLimit = OfficialValueParser.double(subscription["daily_limit_usd"])
        let monthlyUsed = OfficialValueParser.double(subscription["monthly_usage_usd"])
        let weeklyUsed = OfficialValueParser.double(subscription["weekly_usage_usd"])
        let dailyUsed = OfficialValueParser.double(subscription["daily_usage_usd"])
        let limit = firstPositive([monthlyLimit, weeklyLimit, dailyLimit])
        let used = monthlyUsed ?? weeklyUsed ?? dailyUsed ?? 0
        let accountLabel = OfficialValueParser.string(body["planName"]) ?? "订阅"
        let unit = OfficialValueParser.string(body["unit"]) ?? "USD"
        var meta = extraMeta
        meta["sub2apiMode"] = "subscription"

        if isUnlimited {
            return AccountChannelResult(
                remaining: nil,
                used: nil,
                limit: nil,
                unit: unit,
                accountLabel: accountLabel,
                planType: accountLabel,
                quotaWindows: windows,
                note: "无限制",
                rawMeta: meta
            )
        }

        guard let remaining else {
            throw ProviderError.invalidResponse("missing remaining path remaining")
        }
        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit ?? remaining,
            unit: unit,
            accountLabel: accountLabel,
            planType: accountLabel,
            quotaWindows: windows,
            note: sub2APIRemainingNote(remaining: remaining, extra: sub2APIWindowSummary(windows)),
            rawMeta: meta
        )
    }

    private static func extractSub2APIQuotaValues(
        body: [String: Any],
        quota: [String: Any],
        extraMeta: [String: String]
    ) throws -> AccountChannelResult {
        guard let remaining = OfficialValueParser.double(quota["remaining"]) else {
            throw ProviderError.invalidResponse("missing remaining path quota.remaining")
        }
        let used = OfficialValueParser.double(quota["used"])
        let limit = OfficialValueParser.double(quota["limit"])
        let unit = OfficialValueParser.string(quota["unit"])
            ?? OfficialValueParser.string(body["unit"])
            ?? "USD"
        var meta = extraMeta
        meta["sub2apiMode"] = "quota"
        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            accountLabel: "API Key 配额",
            planType: "API Key 配额",
            quotaWindows: [],
            note: sub2APIRemainingNote(remaining: remaining),
            rawMeta: meta
        )
    }

    private static func extractSub2APIRateLimitValues(
        body: [String: Any],
        rateLimits: [Any],
        extraMeta: [String: String]
    ) throws -> AccountChannelResult {
        let entries = rateLimits.compactMap { $0 as? [String: Any] }
        guard !entries.isEmpty else {
            throw ProviderError.invalidResponse("missing remaining path remaining")
        }

        var windows: [UsageQuotaWindow] = []
        var binding = entries[0]
        var bindingOccupancy = occupancyPercent(
            used: OfficialValueParser.double(binding["used"]),
            limit: OfficialValueParser.double(binding["limit"])
        )
        for (index, entry) in entries.enumerated() {
            let used = OfficialValueParser.double(entry["used"])
            let limit = OfficialValueParser.double(entry["limit"])
            let remainingValue = OfficialValueParser.double(entry["remaining"])
            let occupancy = occupancyPercent(used: used, limit: limit)
            if let occupancy, occupancy >= (bindingOccupancy ?? -1) {
                binding = entry
                bindingOccupancy = occupancy
            }
            let windowName = OfficialValueParser.string(entry["window"]) ?? "window-\(index)"
            let usedPercent = occupancy ?? 0
            windows.append(
                UsageQuotaWindow(
                    id: "sub2api-rate-\(windowName)",
                    title: windowName,
                    remainingPercent: remainingPercent(remaining: remainingValue, usedPercent: usedPercent, limit: limit),
                    usedPercent: usedPercent,
                    kind: sub2APIWindowKind(windowName)
                )
            )
        }

        guard let remaining = OfficialValueParser.double(binding["remaining"]) else {
            throw ProviderError.invalidResponse("missing remaining path remaining")
        }
        var meta = extraMeta
        meta["sub2apiMode"] = "rate_limit"
        return AccountChannelResult(
            remaining: remaining,
            used: OfficialValueParser.double(binding["used"]),
            limit: OfficialValueParser.double(binding["limit"]),
            unit: OfficialValueParser.string(body["unit"]) ?? "USD",
            accountLabel: "速率限制",
            planType: "速率限制",
            quotaWindows: windows,
            note: sub2APIRemainingNote(remaining: remaining, extra: sub2APIWindowSummary(windows)),
            rawMeta: meta
        )
    }

    private static func extractSub2APIWalletValues(
        body: [String: Any],
        extraMeta: [String: String]
    ) throws -> AccountChannelResult {
        guard let remaining = OfficialValueParser.double(body["remaining"]) else {
            throw ProviderError.invalidResponse("missing remaining path remaining")
        }
        let unit = OfficialValueParser.string(body["unit"]) ?? "USD"
        let accountLabel = OfficialValueParser.string(body["planName"]) ?? "钱包余额"
        var meta = extraMeta
        meta["sub2apiMode"] = "wallet"
        return AccountChannelResult(
            remaining: remaining,
            used: 0,
            limit: remaining,
            unit: unit,
            accountLabel: accountLabel,
            planType: accountLabel,
            quotaWindows: [],
            note: sub2APIRemainingNote(remaining: remaining),
            rawMeta: meta
        )
    }

    private static func sub2APIUsageError(from root: Any) -> ProviderError? {
        guard let dict = root as? [String: Any] else { return nil }
        let invalidFlag = dict["isValid"] as? Bool == false
        let hasError = dict["error"] != nil
        guard invalidFlag || hasError else { return nil }
        return .unauthorizedDetail(sub2APIErrorMessage(from: dict) ?? "API Key 无效或查询失败")
    }

    private static func sub2APIErrorMessage(from dict: [String: Any]) -> String? {
        if let error = dict["error"] as? [String: Any],
           let message = OfficialValueParser.string(error["message"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        if let error = OfficialValueParser.string(dict["error"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty {
            return error
        }
        if let message = OfficialValueParser.string(dict["message"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        return nil
    }

    private static func sub2APISubscriptionWindows(from subscription: [String: Any]) -> [UsageQuotaWindow] {
        let specs: [(id: String, title: String, kind: UsageQuotaKind, usedKey: String, limitKey: String)] = [
            ("sub2api-daily", "Daily", .custom, "daily_usage_usd", "daily_limit_usd"),
            ("sub2api-weekly", "Weekly", .weekly, "weekly_usage_usd", "weekly_limit_usd"),
            ("sub2api-monthly", "Monthly", .custom, "monthly_usage_usd", "monthly_limit_usd")
        ]
        return specs.compactMap { spec in
            let used = OfficialValueParser.double(subscription[spec.usedKey])
            let limit = OfficialValueParser.double(subscription[spec.limitKey])
            guard let occupancy = occupancyPercent(used: used, limit: limit) else { return nil }
            return UsageQuotaWindow(
                id: spec.id,
                title: spec.title,
                remainingPercent: max(0, 100 - occupancy),
                usedPercent: occupancy,
                kind: spec.kind
            )
        }
    }

    private static func occupancyPercent(used: Double?, limit: Double?) -> Double? {
        guard let limit, limit > 0 else { return nil }
        return min(100, max(0, ((used ?? 0) / limit) * 100))
    }

    private static func remainingPercent(remaining: Double?, usedPercent: Double, limit: Double?) -> Double {
        if let remaining, let limit, limit > 0 {
            return min(100, max(0, (remaining / limit) * 100))
        }
        return max(0, 100 - usedPercent)
    }

    private static func firstPositive(_ values: [Double?]) -> Double? {
        values.compactMap { $0 }.first(where: { $0 > 0 })
    }

    private static func sub2APIWindowKind(_ window: String) -> UsageQuotaKind {
        let normalized = window.lowercased()
        if normalized.contains("week") || normalized == "7d" {
            return .weekly
        }
        if normalized.contains("5h") || normalized.contains("session") {
            return .session
        }
        return .custom
    }

    private static func sub2APIWindowSummary(_ windows: [UsageQuotaWindow]) -> String? {
        guard !windows.isEmpty else { return nil }
        return windows
            .map { "\($0.title) \(Int($0.usedPercent.rounded()))%" }
            .joined(separator: " · ")
    }

    private static func sub2APIRemainingNote(remaining: Double, extra: String? = nil) -> String {
        var parts = ["Account remaining \(String(format: "%.2f", remaining))"]
        if let extra, !extra.isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: " | ")
    }
}
