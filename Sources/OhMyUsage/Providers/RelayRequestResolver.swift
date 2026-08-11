import Foundation
import OhMyUsageDomain

struct ResolvedRelayRequest {
    let method: String
    let path: String
    let bodyJSON: String?
    let staticHeaders: [String: String]
    let userID: String?
    let userIDHeader: String
    let authHeader: String?
    let authScheme: String?
    let successExpression: String?
    let remainingExpression: String
    let usedExpression: String?
    let limitExpression: String?
    let unitExpression: String?
    let accountLabelExpression: String?
}

enum RelayRequestResolver {
    static func resolveBalanceRequest(
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig
    ) -> ResolvedRelayRequest {
        let override = relayConfig.manualOverrides
        let request = manifest.balanceRequest
        let extract = manifest.extract
        return ResolvedRelayRequest(
            method: nonEmptyOrDefault(override?.requestMethod, fallback: request.method),
            path: applyRelayRequiredPlaceholders(
                to: nonEmptyOrDefault(override?.endpointPath, fallback: request.path),
                userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID)
            ),
            bodyJSON: applyRelayPlaceholders(
                to: trimmedOrNil(override?.requestBodyJSON) ?? trimmedOrNil(request.bodyJSON),
                userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID)
            ),
            staticHeaders: (request.headers ?? [:]).merging(override?.staticHeaders ?? [:], uniquingKeysWith: { _, rhs in rhs }),
            userID: trimmedOrNil(override?.userID) ?? trimmedOrNil(request.userID),
            userIDHeader: nonEmptyOrDefault(override?.userIDHeader, fallback: request.userIDHeader ?? "New-Api-User"),
            authHeader: nonEmptyOrDefault(override?.authHeader, fallback: request.authHeader ?? "Authorization"),
            authScheme: override?.authScheme ?? request.authScheme ?? "Bearer",
            successExpression: trimmedOrNil(override?.successExpression) ?? trimmedOrNil(extract.success),
            remainingExpression: nonEmptyOrDefault(override?.remainingExpression, fallback: extract.remaining),
            usedExpression: trimmedOrNil(override?.usedExpression) ?? trimmedOrNil(extract.used),
            limitExpression: trimmedOrNil(override?.limitExpression) ?? trimmedOrNil(extract.limit),
            unitExpression: trimmedOrNil(override?.unitExpression) ?? trimmedOrNil(extract.unit),
            accountLabelExpression: trimmedOrNil(override?.accountLabelExpression) ?? trimmedOrNil(extract.accountLabel)
        )
    }

    static func resolveBalanceRequests(
        manifest: RelayAdapterManifest,
        relayConfig: RelayProviderConfig
    ) -> [ResolvedRelayRequest] {
        let primary = resolveBalanceRequest(manifest: manifest, relayConfig: relayConfig)
        var requests: [ResolvedRelayRequest] = [primary]

        let manualPath = relayConfig.manualOverrides?.endpointPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if manualPath.isEmpty {
            switch manifest.id {
            case "hongmacc":
                requests.append(contentsOf: hongmaccProbeRequests(from: primary))
            case "xiaomimimo":
                requests.append(contentsOf: xiaomimimoProbeRequests(from: primary))
            case "moonshot":
                requests.append(contentsOf: moonshotProbeRequests(from: primary))
            case "minimax":
                requests.append(contentsOf: minimaxProbeRequests(from: primary))
            case "deepseek":
                requests.append(contentsOf: deepseekProbeRequests(from: primary))
            default:
                break
            }
        }

        var deduped: [ResolvedRelayRequest] = []
        var seen = Set<String>()
        for request in requests {
            let key = "\(normalizedPath(request.path))|\(request.remainingExpression)|\(request.usedExpression ?? "")|\(request.limitExpression ?? "")"
            if seen.insert(key).inserted {
                deduped.append(request)
            }
        }
        return deduped
    }

    static func relayURL(baseURL: URL, rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return baseURL.appending(path: "/")
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           let absolute = URL(string: trimmed) {
            return absolute
        }

        let normalized = normalizedPath(trimmed)
        guard let queryIndex = normalized.firstIndex(of: "?") else {
            return baseURL.appending(path: normalized)
        }

        let pathPart = String(normalized[..<queryIndex])
        let queryPart = String(normalized[normalized.index(after: queryIndex)...])
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = pathPart.isEmpty ? "/" : pathPart
        components?.percentEncodedQuery = queryPart.isEmpty ? nil : queryPart
        return components?.url ?? baseURL.appending(path: pathPart.isEmpty ? "/" : pathPart)
    }

    static func relayRootURL(from raw: String) -> URL? {
        let normalized = ProviderDescriptor.normalizeRelayBaseURL(raw)
        guard var components = URLComponents(string: normalized),
              let host = components.host,
              !host.isEmpty else {
            return URL(string: normalized)
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url ?? URL(string: normalized)
    }

    static func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
    }

    static func applyRelayPlaceholders(to value: String?, userID: String?) -> String? {
        guard var value else { return nil }
        if let userID {
            value = value.replacingOccurrences(of: "{{userID}}", with: userID)
        }
        return value
    }

    static func applyRelayRequiredPlaceholders(to value: String, userID: String?) -> String {
        applyRelayPlaceholders(to: value, userID: userID) ?? value
    }

    private static func hongmaccProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/user/key-balance",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(quota.remainingQuota,data.quota.remainingQuota,remainingQuota,data.remainingQuota)",
                usedExpression: "coalesce(quota.usedCost,data.quota.usedCost,usedCost,data.usedCost)",
                limitExpression: "coalesce(quota.totalCostLimit,data.quota.totalCostLimit,totalCostLimit,data.totalCostLimit)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            ),
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/user/api-keys",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(sum(data.*.remainingQuota),sum(data.items.*.remainingQuota),sum(apiKeys.*.remainingQuota),sum(keys.*.remainingQuota),data.remainingQuota,remainingQuota,data.balance,balance)",
                usedExpression: "coalesce(sum(data.*.usedQuota),sum(data.items.*.usedQuota),sum(apiKeys.*.usedQuota),sum(keys.*.usedQuota),data.usedQuota,usedQuota,data.used,used)",
                limitExpression: "coalesce(sum(data.*.totalQuota),sum(data.items.*.totalQuota),sum(apiKeys.*.totalQuota),sum(keys.*.totalQuota),data.totalQuota,totalQuota,data.limit,limit)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private static func xiaomimimoProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        let remainingExpression = "coalesce(data.balance,data.data.balance,data.result.balance,data.user.balance,data.data.user.balance,data.account.balance,data.data.account.balance,data.result.account.balance,data.wallet.balance,data.data.wallet.balance,data.result.wallet.balance,data.walletBalance,data.data.walletBalance,data.result.walletBalance,data.accountBalance,data.data.accountBalance,data.result.accountBalance,data.availableBalance,data.data.availableBalance,data.result.availableBalance,data.available_amount,data.data.available_amount,data.result.available_amount,data.availableAmount,data.data.availableAmount,data.result.availableAmount,data.currentBalance,data.data.currentBalance,data.result.currentBalance,data.remainBalance,data.data.remainBalance,data.result.remainBalance,data.remainingBalance,data.data.remainingBalance,data.result.remainingBalance,data.amount,data.data.amount,data.result.amount,balance,availableBalance,available_amount,availableAmount,currentBalance,walletBalance,accountBalance,remainBalance,remainingBalance,amount)"
        let usedExpression = "coalesce(data.monthlyUsage,data.data.monthlyUsage,data.result.monthlyUsage,data.monthlySpend,data.data.monthlySpend,data.result.monthlySpend,data.monthly_spend,data.data.monthly_spend,data.result.monthly_spend,data.used,data.data.used,data.result.used,data.consume,data.data.consume,data.result.consume,data.totalUsage,data.data.totalUsage,data.result.totalUsage,data.totalSpend,data.data.totalSpend,data.result.totalSpend,monthlyUsage,monthlySpend,monthly_spend,used,consume,totalUsage,totalSpend)"
        let limitExpression = "coalesce(data.totalLimit,data.data.totalLimit,data.result.totalLimit,data.limit,data.data.limit,data.result.limit,data.totalAmount,data.data.totalAmount,data.result.totalAmount,data.total_amount,data.data.total_amount,data.result.total_amount,data.quota,data.data.quota,data.result.quota,totalLimit,limit,totalAmount,total_amount,quota)"
        return [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api/v1/balance",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: remainingExpression,
                usedExpression: usedExpression,
                limitExpression: limitExpression,
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private static func moonshotProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "/api?endpoint=organizationAccountInfo",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)",
                usedExpression: "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)",
                limitExpression: "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)",
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private static func minimaxProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        let codingPlanRequest = ResolvedRelayRequest(
            method: "GET",
            path: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains",
            bodyJSON: nil,
            staticHeaders: ["Accept": "application/json", "Content-Type": "application/json"],
            userID: nil,
            userIDHeader: base.userIDHeader,
            authHeader: "Authorization",
            authScheme: "Bearer",
            successExpression: nil,
            remainingExpression: "model_remains.0.current_interval_remaining_percent",
            usedExpression: nil,
            limitExpression: "100",
            unitExpression: "\"%\"",
            accountLabelExpression: nil
        )
        guard let groupID = base.userID?.trimmingCharacters(in: .whitespacesAndNewlines), !groupID.isEmpty else {
            return [codingPlanRequest]
        }
        let expressions = (
            remaining: "coalesce(data.available_amount,data.balance,data.availableBalance,data.accountBalance,data.currentBalance,data.current_balance,data.group.balance,data.groupBalance,data.wallet.balance,data.walletBalance,data.remainBalance,data.remainingBalance,available_amount,balance,availableBalance,accountBalance,currentBalance,current_balance,groupBalance,walletBalance,remainBalance,remainingBalance)",
            used: "coalesce(data.used,data.monthlyUsage,data.monthlySpend,data.totalUsage,data.totalSpend,used,monthlyUsage,monthlySpend,totalUsage,totalSpend)",
            limit: "coalesce(data.limit,data.totalLimit,data.quota,data.totalQuota,limit,totalLimit,quota,totalQuota)"
        )
        let paths = [
            "https://www.minimaxi.com/account/query_balance?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/query_balance?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/query_balance/?GroupId=\(groupID)",
            "https://www.minimaxi.com/backend/account/query_balance?GroupId=\(groupID)",
            "https://platform.minimaxi.com/backend/query_balance?GroupId=\(groupID)"
        ]
        let cookieRequests = paths.map { path in
            ResolvedRelayRequest(
                method: "GET",
                path: path,
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: expressions.remaining,
                usedExpression: expressions.used,
                limitExpression: expressions.limit,
                unitExpression: "\"CNY\"",
                accountLabelExpression: base.accountLabelExpression
            )
        }
        return [codingPlanRequest] + cookieRequests
    }

    private static func deepseekProbeRequests(from base: ResolvedRelayRequest) -> [ResolvedRelayRequest] {
        // The platform session endpoint only accepts browser login tokens. Pasted
        // API keys (sk-...) are served by the official public balance endpoint.
        [
            ResolvedRelayRequest(
                method: "GET",
                path: "https://api.deepseek.com/user/balance",
                bodyJSON: nil,
                staticHeaders: base.staticHeaders,
                userID: base.userID,
                userIDHeader: base.userIDHeader,
                authHeader: base.authHeader,
                authScheme: base.authScheme,
                successExpression: nil,
                remainingExpression: "sum(balance_infos.*.total_balance)",
                usedExpression: nil,
                limitExpression: nil,
                unitExpression: "coalesce(balance_infos.0.currency,\"CNY\")",
                accountLabelExpression: base.accountLabelExpression
            )
        ]
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmptyOrDefault(_ value: String?, fallback: String) -> String {
        trimmedOrNil(value) ?? fallback
    }
}
