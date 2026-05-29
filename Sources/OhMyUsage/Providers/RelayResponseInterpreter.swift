import OhMyUsageDomain
import Foundation

struct RelayQuotaDisplayAmount {
    let remaining: Double
    let valueScale: Double
    let quotaPerUnit: Double
    let rate: Double
    let unit: String
    let displayType: String
    let displayInCurrency: Bool
}

struct AccountChannelResult {
    let remaining: Double?
    let used: Double?
    let limit: Double?
    let unit: String
    let accountLabel: String?
    let planType: String?
    let quotaWindows: [UsageQuotaWindow]
    let note: String
    var rawMeta: [String: String]
    var recoveryMeta: [String: String] = [:]
}

enum RelayResponseInterpreter {
    typealias JSONRequest = (_ url: URL, _ headers: [String: String], _ method: String?, _ bodyJSON: String?) async throws -> Any

    static func extractAccountValues(
        root: Any,
        baseURL: URL,
        request: ResolvedRelayRequest,
        manifest: RelayAdapterManifest,
        headers: [String: String],
        candidate: RelayCredentialCandidate,
        supplementalPlanType: String? = nil,
        requestJSON: @escaping JSONRequest
    ) async throws -> AccountChannelResult {
        if let successExpression = request.successExpression,
           let success = RelayJSONExpressionEvaluator.boolValue(for: successExpression, in: root),
           !success {
            throw ProviderError.invalidResponse("probe failed at \(successExpression)")
        }

        if manifest.id == "moonshot",
           let moonshotFallback = try? await extractMoonshotAccountValues(
            initialRoot: root,
            baseURL: baseURL,
            request: request,
            headers: headers,
            candidate: candidate,
            requestJSON: requestJSON
           ) {
            return moonshotFallback
        }

        if manifest.id == "xiaomimimo",
           let mimoFallback = extractXiaomimimoAccountValues(
            root: root,
            request: request,
            candidate: candidate,
            planType: supplementalPlanType ?? extractXiaomimimoPlanType(from: root)
           ) {
            return mimoFallback
        }

        guard var remaining = RelayJSONExpressionEvaluator.numericValue(for: request.remainingExpression, in: root) else {
            throw ProviderError.invalidResponse("missing remaining path \(request.remainingExpression)")
        }
        var used = request.usedExpression.flatMap { RelayJSONExpressionEvaluator.numericValue(for: $0, in: root) }
        var limit = request.limitExpression.flatMap { RelayJSONExpressionEvaluator.numericValue(for: $0, in: root) }
        if limit == nil, let used {
            limit = max(0, remaining + used)
        }

        var unit = request.unitExpression.flatMap { RelayJSONExpressionEvaluator.stringValue(for: $0, in: root) } ?? "quota"
        let accountLabel = request.accountLabelExpression.flatMap { RelayJSONExpressionEvaluator.stringValue(for: $0, in: root) }
        var extraMeta: [String: String] = [
            "endpointPath": RelayRequestResolver.normalizedPath(request.path),
            "requestMethod": request.method,
            "remainingPath": request.remainingExpression,
            "usedPath": request.usedExpression ?? "",
            "limitPath": request.limitExpression ?? "",
            "authSource": candidate.source
        ]
        if let userID = request.userID {
            extraMeta["userID"] = userID
        }
        let requestCount = RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.request_count,request_count)", in: root)
        if let requestCount {
            extraMeta["requestCount"] = String(Int(requestCount.rounded()))
        }
        if let rawUsedQuota = RelayJSONExpressionEvaluator.numericValue(for: "coalesce(data.used_quota,used_quota)", in: root) {
            extraMeta["rawUsedQuota"] = String(rawUsedQuota)
        }

        if manifest.postprocessID == .quotaDisplayStatus {
            do {
                let converted = try await convertQuotaToDisplayAmount(
                    baseURL: baseURL,
                    headers: headers.merging(request.staticHeaders, uniquingKeysWith: { _, rhs in rhs }),
                    quota: remaining,
                    requestJSON: requestJSON
                )
                remaining = converted.remaining
                used = used.map { $0 * converted.valueScale }
                limit = limit.map { $0 * converted.valueScale }
                unit = converted.unit
                extraMeta["displayType"] = converted.displayType
                extraMeta["displayInCurrency"] = String(converted.displayInCurrency)
                extraMeta["quotaPerUnit"] = String(converted.quotaPerUnit)
                extraMeta["displayRate"] = String(converted.rate)
                extraMeta["valueScale"] = String(converted.valueScale)
            } catch {
                extraMeta["quotaDisplayStatusError"] = String(describing: error)
            }
        }

        var noteParts = ["Account remaining \(String(format: "%.2f", remaining))"]
        if let requestCount {
            noteParts.append("Requests \(Int(requestCount.rounded()))")
        }
        let note = noteParts.joined(separator: " | ")
        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: unit,
            accountLabel: accountLabel,
            planType: nil,
            quotaWindows: [],
            note: note,
            rawMeta: extraMeta
        )
    }

    static func extractXiaomimimoTokenPlanValues(
        detailRoot: Any,
        usageRoot: Any,
        candidate: RelayCredentialCandidate
    ) throws -> AccountChannelResult {
        guard let usageAggregate = extractXiaomimimoTokenPlanUsageAggregate(from: usageRoot) else {
            throw ProviderError.invalidResponse("missing xiaomimimo token plan usage item")
        }

        let usedTokens = usageAggregate.used
        let limitTokens = usageAggregate.limit
        let remainingTokens = max(0, limitTokens - usedTokens)
        let rawItemPercent = usageAggregate.rawPercent
        let rawRootPercent = RelayJSONExpressionEvaluator.numericValue(
            for: "coalesce(data.usage.percent,usage.percent,data.monthUsage.percent,monthUsage.percent)",
            in: usageRoot
        )
        let rawPercent = rawItemPercent ?? rawRootPercent
        let derivedUsedPercent = limitTokens > 0 ? (usedTokens / limitTokens) * 100 : nil
        let fallbackUsedPercent = normalizedXiaomimimoTokenPlanPercent(rawPercent)
        let normalizedUsedPercent = min(100, max(0, derivedUsedPercent ?? fallbackUsedPercent ?? 0))
        let remainingPercent = max(0, 100 - normalizedUsedPercent)

        let planType = PlanTypeDisplayFormatter.normalizedPlanType(
            RelayJSONExpressionEvaluator.stringValue(for: "coalesce(data.planName,planName,data.planCode,planCode)", in: detailRoot)
        )
        let periodEndRaw = RelayJSONExpressionEvaluator.stringValue(for: "coalesce(data.currentPeriodEnd,currentPeriodEnd)", in: detailRoot)
        let periodEndDate = periodEndRaw.flatMap(parseXiaomimimoTokenPlanDate(_:))
        let autoRenew = RelayJSONExpressionEvaluator.boolValue(for: "coalesce(data.enableAutoRenew,enableAutoRenew)", in: detailRoot) ?? false
        let valueText = "\(formattedWholeNumber(usedTokens)) / \(formattedWholeNumber(limitTokens))"
        let windowID = "token-plan-total"
        let title = "Total Usage"

        var noteParts: [String] = []
        if let planType {
            noteParts.append("Plan \(planType)")
        }
        noteParts.append(valueText)
        noteParts.append("Used \(String(format: "%.1f", normalizedUsedPercent))%")
        if let periodEndRaw, !periodEndRaw.isEmpty {
            noteParts.append("Valid until \(periodEndRaw) UTC")
        }
        if autoRenew {
            noteParts.append("Auto renew")
        }

        var rawMeta: [String: String] = [
            "endpointPath": "/api/v1/tokenPlan/detail,/api/v1/tokenPlan/usage",
            "requestMethod": "GET",
            "remainingPath": "100 - usedPercent",
            "usedPath": "data.usage.items.*.used",
            "limitPath": "data.usage.items.*.limit",
            "authSource": candidate.source,
            "quotaValueText.\(windowID)": valueText,
            "tokenPlanUsageName": usageAggregate.names.joined(separator: ","),
            "tokenPlanUsageItemCount": String(usageAggregate.itemCount),
            "tokenPlanUsed": String(Int(usedTokens.rounded())),
            "tokenPlanRemaining": String(Int(remainingTokens.rounded())),
            "tokenPlanLimit": String(Int(limitTokens.rounded())),
            "tokenPlanUsedPercent": String(normalizedUsedPercent),
            "tokenPlanUsedPercentSource": derivedUsedPercent != nil ? "usedLimitDerived" : "percentFallback",
            "tokenPlanAutoRenew": String(autoRenew)
        ]
        if let rawItemPercent {
            rawMeta["tokenPlanUsageItemPercentRaw"] = String(rawItemPercent)
        }
        if let rawRootPercent {
            rawMeta["tokenPlanUsageRootPercentRaw"] = String(rawRootPercent)
        }
        if let rawPercent {
            rawMeta["tokenPlanUsedPercentRaw"] = String(rawPercent)
        }
        if let derivedUsedPercent {
            rawMeta["tokenPlanUsedPercentDerived"] = String(derivedUsedPercent)
        }
        if let planType {
            rawMeta["planType"] = planType
        }
        if let periodEndRaw, !periodEndRaw.isEmpty {
            rawMeta["tokenPlanCurrentPeriodEnd"] = periodEndRaw
        }

        let quotaWindow = UsageQuotaWindow(
            id: windowID,
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: normalizedUsedPercent,
            resetAt: periodEndDate,
            kind: .custom
        )

        return AccountChannelResult(
            remaining: remainingPercent,
            used: normalizedUsedPercent,
            limit: 100,
            unit: "%",
            accountLabel: periodEndRaw,
            planType: planType,
            quotaWindows: [quotaWindow],
            note: noteParts.joined(separator: " | "),
            rawMeta: rawMeta
        )
    }

    static func extractXiaomimimoPlanType(from root: Any) -> String? {
        let prioritizedKeys = [
            "tokenPlanName", "token_plan_name", "tokenPlanType", "token_plan_type",
            "tokenPlan", "token_plan", "currentTokenPlan", "current_token_plan",
            "planName", "plan_name", "planType", "plan_type",
            "currentPlan", "current_plan", "packageName", "package_name",
            "subscriptionName", "subscription_name", "subscriptionType", "subscription_type",
            "tierName", "tier_name", "membershipType", "membership_type", "plan"
        ]

        for key in prioritizedKeys {
            guard let rawValue = RelayJSONExpressionEvaluator.firstNestedValue(matchingKey: key, in: root),
                  let normalized = normalizedXiaomimimoPlanType(from: rawValue) else {
                continue
            }
            return normalized
        }
        return nil
    }

    private static func extractMoonshotAccountValues(
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

    private static func extractXiaomimimoAccountValues(
        root: Any,
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate,
        planType: String?
    ) -> AccountChannelResult? {
        let remainingKeys = [
            "available_amount", "availableAmount", "availableBalance", "currentBalance",
            "remainBalance", "remainingBalance", "walletBalance", "accountBalance",
            "balance", "amount"
        ]
        guard let remaining = RelayJSONExpressionEvaluator.firstNestedNumericValue(for: remainingKeys, in: root) else {
            return nil
        }

        let used = RelayJSONExpressionEvaluator.firstNestedNumericValue(
            for: ["monthly_spend", "monthlySpend", "monthlyUsage", "totalSpend", "totalUsage", "used", "consume"],
            in: root
        )
        var limit = RelayJSONExpressionEvaluator.firstNestedNumericValue(
            for: ["total_amount", "totalAmount", "totalLimit", "limit", "quota"],
            in: root
        )
        if limit == nil, let used {
            limit = max(0, remaining + used)
        }

        let accountLabel = RelayJSONExpressionEvaluator.firstNestedStringValue(
            for: ["nickName", "nickname", "userName", "name"],
            in: root
        )

        var rawMeta: [String: String] = [
            "endpointPath": RelayRequestResolver.normalizedPath(request.path),
            "requestMethod": request.method,
            "remainingPath": "xiaomimimoRecursiveFallback",
            "usedPath": request.usedExpression ?? "",
            "limitPath": request.limitExpression ?? "",
            "authSource": candidate.source
        ]
        if let planType {
            rawMeta["planType"] = planType
        }

        var noteParts: [String] = []
        if let planType { noteParts.append("Plan \(planType)") }
        noteParts.append("Account remaining \(String(format: "%.2f", remaining))")

        return AccountChannelResult(
            remaining: remaining,
            used: used,
            limit: limit,
            unit: "CNY",
            accountLabel: accountLabel,
            planType: planType,
            quotaWindows: [],
            note: noteParts.joined(separator: " | "),
            rawMeta: rawMeta
        )
    }

    private struct XiaomimimoTokenPlanUsageAggregate {
        let used: Double
        let limit: Double
        let rawPercent: Double?
        let names: [String]
        let itemCount: Int
    }

    private static func extractXiaomimimoTokenPlanUsageAggregate(from root: Any) -> XiaomimimoTokenPlanUsageAggregate? {
        let candidates = [
            RelayJSONExpressionEvaluator.value(at: "data.usage.items", in: root),
            RelayJSONExpressionEvaluator.value(at: "usage.items", in: root),
            RelayJSONExpressionEvaluator.value(at: "data.monthUsage.items", in: root),
            RelayJSONExpressionEvaluator.value(at: "monthUsage.items", in: root)
        ]

        for candidate in candidates {
            guard let items = candidate as? [Any], !items.isEmpty else { continue }
            let dictionaries = items.compactMap { $0 as? [String: Any] }
            let positiveLimitItems = dictionaries.compactMap { item -> (name: String, used: Double, limit: Double, rawPercent: Double?)? in
                let limit = RelayJSONExpressionEvaluator.coerceDouble(item["limit"] ?? 0) ?? 0
                guard limit > 0 else { return nil }
                let used = RelayJSONExpressionEvaluator.coerceDouble(item["used"] ?? 0) ?? 0
                let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (
                    name: name?.isEmpty == false ? name! : "token_plan_item",
                    used: max(0, used),
                    limit: limit,
                    rawPercent: RelayJSONExpressionEvaluator.coerceDouble(item["percent"] ?? 0)
                )
            }

            guard !positiveLimitItems.isEmpty else { continue }
            let totalUsed = positiveLimitItems.reduce(0) { $0 + $1.used }
            let totalLimit = positiveLimitItems.reduce(0) { $0 + $1.limit }
            guard totalLimit > 0 else { continue }
            return XiaomimimoTokenPlanUsageAggregate(
                used: totalUsed,
                limit: totalLimit,
                rawPercent: positiveLimitItems.count == 1 ? positiveLimitItems[0].rawPercent : nil,
                names: positiveLimitItems.map(\.name),
                itemCount: positiveLimitItems.count
            )
        }
        return nil
    }

    private static func normalizedXiaomimimoTokenPlanPercent(_ rawPercent: Double?) -> Double? {
        guard let rawPercent, rawPercent.isFinite else { return nil }
        if rawPercent > 0, rawPercent <= 1 {
            return rawPercent * 100
        }
        return rawPercent
    }

    private static func parseXiaomimimoTokenPlanDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: trimmed)
    }

    private static func formattedWholeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    private static func normalizedXiaomimimoPlanType(from value: Any) -> String? {
        if let string = value as? String {
            return normalizedXiaomimimoPlanType(string)
        }
        if let number = value as? NSNumber {
            return normalizedXiaomimimoPlanType(number.stringValue)
        }
        if let dict = value as? [String: Any] {
            let nestedKeys = [
                "displayName", "display_name", "name", "title", "type",
                "planName", "plan_name", "planType", "plan_type",
                "tierName", "tier_name", "levelName", "level_name", "label"
            ]
            for key in nestedKeys {
                guard let nestedValue = dict[key],
                      let normalized = normalizedXiaomimimoPlanType(from: nestedValue) else {
                    continue
                }
                return normalized
            }
            return nil
        }
        if let array = value as? [Any] {
            for item in array {
                if let normalized = normalizedXiaomimimoPlanType(from: item) {
                    return normalized
                }
            }
        }
        return nil
    }

    private static func normalizedXiaomimimoPlanType(_ raw: String) -> String? {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty,
              collapsed.count <= 48,
              collapsed.lowercased().contains("http") == false else {
            return nil
        }
        guard let normalized = PlanTypeDisplayFormatter.normalizedPlanType(collapsed) else {
            return nil
        }

        let lower = normalized.lowercased()
        let knownTiers: [String: String] = [
            "lite": "Lite",
            "standard": "Standard",
            "pro": "Pro",
            "max": "Max"
        ]
        for (token, display) in knownTiers {
            if lower == token ||
                lower.hasSuffix(" \(token)") ||
                lower.contains("token plan \(token)") ||
                lower.contains("plan \(token)") {
                return display
            }
        }

        return titleCaseASCIIWords(normalized)
    }

    private static func titleCaseASCIIWords(_ value: String) -> String {
        guard value.unicodeScalars.allSatisfy(\.isASCII) else {
            return value
        }

        var output = ""
        var shouldUppercase = true
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if shouldUppercase {
                    output += String(scalar).uppercased()
                    shouldUppercase = false
                } else {
                    output.append(Character(scalar))
                }
            } else {
                output.append(Character(scalar))
                shouldUppercase = scalar == " " || scalar == "-" || scalar == "_" || scalar == "/"
            }
        }
        return output
    }

    private static func convertQuotaToDisplayAmount(
        baseURL: URL,
        headers: [String: String],
        quota: Double,
        requestJSON: @escaping JSONRequest
    ) async throws -> RelayQuotaDisplayAmount {
        let root = try await requestJSON(
            baseURL.appending(path: "/api/status"),
            headers,
            "GET",
            nil
        )
        guard let quotaPerUnit = RelayJSONExpressionEvaluator.numericValue(for: "data.quota_per_unit", in: root), quotaPerUnit > 0 else {
            throw ProviderError.invalidResponse("missing data.quota_per_unit")
        }
        let displayType = RelayJSONExpressionEvaluator.stringValue(for: "data.quota_display_type", in: root)?.uppercased() ?? "USD"
        let displayInCurrency = RelayJSONExpressionEvaluator.boolValue(for: "data.display_in_currency", in: root) ?? true

        let displayRate: Double
        let unit: String
        let valueScale: Double
        if displayType == "TOKENS" || !displayInCurrency {
            displayRate = 1
            unit = displayType == "TOKENS" ? "tokens" : "quota"
            valueScale = 1
        } else {
            switch displayType {
            case "CNY":
                displayRate = RelayJSONExpressionEvaluator.numericValue(for: "data.usd_exchange_rate", in: root) ?? 1
                unit = "¥"
            case "CUSTOM":
                displayRate = RelayJSONExpressionEvaluator.numericValue(for: "data.custom_currency_exchange_rate", in: root) ?? 1
                unit = RelayJSONExpressionEvaluator.stringValue(for: "data.custom_currency_symbol", in: root) ?? "¤"
            default:
                displayRate = 1
                unit = "$"
            }
            valueScale = displayRate / quotaPerUnit
        }

        return RelayQuotaDisplayAmount(
            remaining: quota * valueScale,
            valueScale: valueScale,
            quotaPerUnit: quotaPerUnit,
            rate: displayRate,
            unit: unit,
            displayType: displayType,
            displayInCurrency: displayInCurrency
        )
    }
}
