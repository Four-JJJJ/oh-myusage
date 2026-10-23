import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

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
    var note: String
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

        if manifest.id == "deepseek",
           let deepseekError = deepseekBusinessError(root: root, candidate: candidate) {
            throw deepseekError
        }

        if manifest.id == "moonshot" {
            do {
                if let moonshotFallback = try await extractMoonshotAccountValues(
                    initialRoot: root, baseURL: baseURL, request: request,
                    headers: headers, candidate: candidate, requestJSON: requestJSON
                ) { return moonshotFallback }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if error is ProviderRateLimitError { throw error }
            }
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

        if manifest.id == "minimax",
           request.path.contains("/coding_plan/remains") {
            return try extractMiniMaxCodingPlanValues(
                root: root,
                request: request,
                candidate: candidate
            )
        }

        if manifest.postprocessID == .sub2apiUsage {
            return try extractSub2APIUsageValues(
                root: root,
                request: request,
                candidate: candidate
            )
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
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                if error is ProviderRateLimitError { throw error }
                extraMeta["quotaDisplayStatusError"] = "display conversion unavailable"
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

    static func extractMiniMaxCodingPlanValues(
        root: Any,
        request: ResolvedRelayRequest,
        candidate: RelayCredentialCandidate
    ) throws -> AccountChannelResult {
        try MiniMaxCodingPlanParser.parse(root: root, request: request, candidate: candidate)
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
