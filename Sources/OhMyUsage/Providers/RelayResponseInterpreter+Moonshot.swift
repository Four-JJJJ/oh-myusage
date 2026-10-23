import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

extension RelayResponseInterpreter {
    static func extractMoonshotAccountValues(
        initialRoot: Any,
        baseURL: URL,
        request: ResolvedRelayRequest,
        headers: [String: String],
        candidate: RelayCredentialCandidate,
        requestJSON: @escaping JSONRequest
    ) async throws -> AccountChannelResult? {
        if let remaining = RelayJSONExpressionEvaluator.numericValue(for: request.remainingExpression, in: initialRoot) {
            let used = request.usedExpression.flatMap { RelayJSONExpressionEvaluator.numericValue(for: $0, in: initialRoot) }
            var limit = request.limitExpression.flatMap { RelayJSONExpressionEvaluator.numericValue(for: $0, in: initialRoot) }
            if limit == nil, let used {
                limit = max(0, remaining + used)
            }
            var normalizedRemaining = remaining
            var normalizedUsed = used
            var normalizedLimit = limit
            var extraMeta: [String: String] = [
                "endpointPath": RelayRequestResolver.normalizedPath(request.path),
                "requestMethod": request.method,
                "remainingPath": request.remainingExpression,
                "usedPath": request.usedExpression ?? "",
                "limitPath": request.limitExpression ?? "",
                "authSource": candidate.source
            ]
            if moonshotUsesScaledCurrencyShape(root: initialRoot) {
                normalizedRemaining = remaining / 100_000
                normalizedUsed = used.map { $0 / 100_000 }
                normalizedLimit = limit.map { $0 / 100_000 }
                extraMeta["valueScale"] = "100000"
                extraMeta["rawRemaining"] = String(remaining)
                if let used { extraMeta["rawUsed"] = String(used) }
                if let limit { extraMeta["rawLimit"] = String(limit) }
            }
            let unit = request.unitExpression.flatMap { RelayJSONExpressionEvaluator.stringValue(for: $0, in: initialRoot) } ?? "quota"
            let accountLabel = request.accountLabelExpression.flatMap { RelayJSONExpressionEvaluator.stringValue(for: $0, in: initialRoot) }
            return AccountChannelResult(
                remaining: normalizedRemaining,
                used: normalizedUsed,
                limit: normalizedLimit,
                unit: unit,
                accountLabel: accountLabel,
                planType: nil,
                quotaWindows: [],
                note: "Account remaining \(String(format: "%.2f", normalizedRemaining))",
                rawMeta: extraMeta
            )
        }

        let trimmedPath = request.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let organizationIDs = extractMoonshotOrganizationIDs(from: initialRoot)
        if !trimmedPath.contains("endpoint=userInfo") &&
            !trimmedPath.contains("endpoint=organizationAccountInfo") {
            return nil
        }

        for oid in organizationIDs where !oid.isEmpty {
            let path = "/api?endpoint=organizationAccountInfo&oid=\(oid)"
            let root = try await requestJSON(
                RelayRequestResolver.relayURL(baseURL: baseURL, rawPath: path),
                headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                "GET",
                nil
            )
            if let extracted = extractMoonshotOrganizationAccountValues(root: root, oid: oid, candidate: candidate) {
                return extracted
            }
        }

        return nil
    }

    private static func extractMoonshotOrganizationIDs(from root: Any) -> [String] {
        let oidExpressions = [
            "data.organizations.0.organization.id", "data.organizations.0.id",
            "data.currentOrganizationId", "data.currentOrganization.id",
            "data.organizationId", "data.organization.id",
            "data.defaultOrganizationId", "data.defaultOrganization.id",
            "data.orgId", "data.org_id", "data.oid",
            "organizations.0.organization.id", "organizations.0.id",
            "currentOrganizationId", "organizationId", "orgId", "org_id", "oid"
        ]

        return oidExpressions.compactMap { expression -> String? in
            guard let raw = RelayJSONExpressionEvaluator.value(at: expression, in: root) else { return nil }
            if let string = raw as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let number = raw as? NSNumber {
                return number.stringValue
            }
            return nil
        }
    }

    private static func extractMoonshotOrganizationAccountValues(
        root: Any,
        oid: String,
        candidate: RelayCredentialCandidate
    ) -> AccountChannelResult? {
        if let remaining = RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)", in: root) {
            let used = RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)", in: root)
            var limit = RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)", in: root)
            if limit == nil, let used {
                limit = max(0, remaining + used)
            }
            var normalizedRemaining = remaining
            var normalizedUsed = used
            var normalizedLimit = limit
            var extraMeta: [String: String] = [
                "endpointPath": "/api?endpoint=organizationAccountInfo&oid=\(oid)",
                "requestMethod": "GET",
                "remainingPath": "coalesce(data.cur,data.balance,data.account.balance,data.wallet.balance,data.availableBalance,data.accountBalance,data.remaining,cur,balance,availableBalance,accountBalance,remaining)",
                "usedPath": "coalesce(data.use,data.used,data.monthlyUsage,data.monthlySpend,data.consume,use,used,monthlyUsage,monthlySpend,consume)",
                "limitPath": "coalesce(data.acc,data.limit,data.totalLimit,data.totalQuota,acc,limit,totalLimit,totalQuota)",
                "authSource": candidate.source,
                "organizationID": oid
            ]
            if moonshotUsesScaledCurrencyShape(root: root) {
                normalizedRemaining = remaining / 100_000
                normalizedUsed = used.map { $0 / 100_000 }
                normalizedLimit = limit.map { $0 / 100_000 }
                extraMeta["valueScale"] = "100000"
                extraMeta["rawRemaining"] = String(remaining)
                if let used { extraMeta["rawUsed"] = String(used) }
                if let limit { extraMeta["rawLimit"] = String(limit) }
            }
            let unit = RelayJSONExpressionEvaluator.stringValue(for: "\"CNY\"", in: root) ?? "CNY"
            let accountLabel = RelayJSONExpressionEvaluator.stringValue(for: "coalesce(data.user.nickname,data.user.nickName,data.user.name,data.nickName,data.nickname,data.userName,nickName,nickname,userName,name)", in: root)
            return AccountChannelResult(
                remaining: normalizedRemaining,
                used: normalizedUsed,
                limit: normalizedLimit,
                unit: unit,
                accountLabel: accountLabel,
                planType: nil,
                quotaWindows: [],
                note: "Account remaining \(String(format: "%.2f", normalizedRemaining))",
                rawMeta: extraMeta
            )
        }
        return nil
    }

    private static func moonshotUsesScaledCurrencyShape(root: Any) -> Bool {
        RelayJSONExpressionEvaluator.value(at: "data.cur", in: root) != nil ||
        RelayJSONExpressionEvaluator.value(at: "data.acc", in: root) != nil ||
        RelayJSONExpressionEvaluator.value(at: "data.use", in: root) != nil ||
        RelayJSONExpressionEvaluator.value(at: "cur", in: root) != nil ||
        RelayJSONExpressionEvaluator.value(at: "acc", in: root) != nil ||
        RelayJSONExpressionEvaluator.value(at: "use", in: root) != nil
    }
}
