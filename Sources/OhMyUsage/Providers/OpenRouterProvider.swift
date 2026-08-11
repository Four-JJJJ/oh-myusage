import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class OpenRouterProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let keychain: any TokenCredentialStoring

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        _ = forceRefresh
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: descriptor.type)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("OpenRouter 官方来源当前仅支持 API 检测")
        }

        let apiKey = try resolveAPIKey()
        let endpointPath = endpointPathForDescriptor()
        guard let url = endpointURL(path: endpointPath) else {
            throw ProviderError.invalidResponse("invalid OpenRouter endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("OpenRouter non-http response")
        }

        if http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        if http.statusCode == 403, descriptor.type == .openrouterCredits {
            throw ProviderError.invalidResponse("management key required")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = Self.extractMessage(from: data)
            let suffix = message.map { ": \($0)" } ?? ""
            throw ProviderError.invalidResponse("OpenRouter http \(http.statusCode)\(suffix)")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("OpenRouter decode failed")
        }

        return try Self.parseSnapshot(root: root, descriptor: descriptor)
    }

    private func endpointPathForDescriptor() -> String {
        switch descriptor.type {
        case .openrouterCredits:
            return "/credits"
        case .openrouterAPI:
            return "/key"
        default:
            return "/key"
        }
    }

    private func resolveAPIKey() throws -> String {
        let fallbackAccount: String
        switch descriptor.type {
        case .openrouterCredits:
            fallbackAccount = "official/openrouter/credits-api-key"
        case .openrouterAPI:
            fallbackAccount = "official/openrouter/api-key"
        default:
            fallbackAccount = "official/openrouter/api-key"
        }

        let service = descriptor.auth.keychainService ?? TokenCredentialStoreServiceNames.defaultServiceName
        let account = descriptor.auth.keychainAccount ?? fallbackAccount
        guard let token = keychain.readToken(service: service, account: account) else {
            throw ProviderError.missingCredential(account)
        }

        let normalized = Self.normalizeToken(token)
        guard !normalized.isEmpty else {
            throw ProviderError.missingCredential(account)
        }
        return normalized
    }

    private func endpointURL(path: String) -> URL? {
        var base = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = "https://openrouter.ai/api/v1"
        }
        if !base.contains("://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if let url = URL(string: base),
           let host = url.host?.lowercased(),
           host == "openrouter.ai",
           (url.path.isEmpty || url.path == "/") {
            base += "/api/v1"
        }
        return URL(string: base + path)
    }

    internal static func parseSnapshot(root: [String: Any], descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        switch descriptor.type {
        case .openrouterCredits:
            return try parseCreditsSnapshot(root: root, descriptor: descriptor)
        case .openrouterAPI:
            return try parseAPISnapshot(root: root, descriptor: descriptor)
        default:
            throw ProviderError.invalidResponse("unsupported OpenRouter provider type")
        }
    }

    internal static func parseCreditsSnapshot(root: [String: Any], descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let data = root["data"] as? [String: Any],
              let totalCredits = OfficialValueParser.double(data["total_credits"]),
              let totalUsage = OfficialValueParser.double(data["total_usage"]) else {
            throw ProviderError.invalidResponse("missing OpenRouter credits fields")
        }

        guard totalCredits > 0 else {
            throw ProviderError.invalidResponse("OpenRouter credits limit is not configured")
        }

        let remaining = max(0, totalCredits - totalUsage)
        let usedPercent = min(100, max(0, (max(0, totalUsage) / totalCredits) * 100))
        let remainingPercent = max(0, min(100, 100 - usedPercent))

        let window = UsageQuotaWindow(
            id: "\(descriptor.id)-credits",
            title: "Credits",
            remainingPercent: remainingPercent,
            usedPercent: usedPercent,
            resetAt: nil,
            kind: .credits
        )

        return UsageSnapshot(
            source: descriptor.id,
            status: remainingPercent <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: totalUsage,
            limit: totalCredits,
            unit: "USD",
            updatedAt: Date(),
            note: "Credits \(formatAmount(remaining))/\(formatAmount(totalCredits))",
            quotaWindows: [window],
            sourceLabel: "API",
            accountLabel: nil,
            extras: [
                "creditsTotal": formatAmount(totalCredits),
                "creditsUsed": formatAmount(totalUsage),
                "creditsRemaining": formatAmount(remaining)
            ],
            rawMeta: [
                "openrouter.endpoint": "/credits"
            ]
        )
    }

    internal static func parseAPISnapshot(root: [String: Any], descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let data = root["data"] as? [String: Any] else {
            throw ProviderError.invalidResponse("missing OpenRouter key data")
        }

        let rawLimit = OfficialValueParser.double(data["limit"])
        let rawRemaining = OfficialValueParser.double(data["limit_remaining"])
        let rawUsage = OfficialValueParser.double(data["usage"])

        let limit: Double
        if let rawLimit, rawLimit > 0 {
            limit = rawLimit
        } else if let rawRemaining, let rawUsage, (rawRemaining + rawUsage) > 0 {
            limit = rawRemaining + rawUsage
        } else {
            throw ProviderError.invalidResponse("OpenRouter API limit is not configured")
        }

        let remaining: Double
        if let rawRemaining {
            remaining = max(0, rawRemaining)
        } else if let rawUsage {
            remaining = max(0, limit - rawUsage)
        } else {
            throw ProviderError.invalidResponse("missing OpenRouter API remaining field")
        }

        let used: Double
        if let rawUsage {
            used = max(0, rawUsage)
        } else {
            used = max(0, limit - remaining)
        }

        let usedPercent = min(100, max(0, (used / limit) * 100))
        let remainingPercent = max(0, min(100, 100 - usedPercent))

        let window = UsageQuotaWindow(
            id: "\(descriptor.id)-limit",
            title: "Limit",
            remainingPercent: remainingPercent,
            usedPercent: usedPercent,
            resetAt: nil,
            kind: .credits
        )

        return UsageSnapshot(
            source: descriptor.id,
            status: remainingPercent <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: used,
            limit: limit,
            unit: "USD",
            updatedAt: Date(),
            note: "API Limit \(formatAmount(remaining))/\(formatAmount(limit))",
            quotaWindows: [window],
            sourceLabel: "API",
            accountLabel: nil,
            extras: [
                "apiLimit": formatAmount(limit),
                "apiUsed": formatAmount(used),
                "apiRemaining": formatAmount(remaining)
            ],
            rawMeta: [
                "openrouter.endpoint": "/key"
            ]
        )
    }

    private static func normalizeToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while token.hasPrefix("\"") && token.hasSuffix("\"") && token.count >= 2 {
            token = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func extractMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = root["error"] as? [String: Any] {
            return OfficialValueParser.string(error["message"])
        }
        return OfficialValueParser.string(root["message"] ?? root["msg"])
    }

    private static func formatAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
