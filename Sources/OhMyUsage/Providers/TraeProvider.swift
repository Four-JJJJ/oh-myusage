import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class TraeProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    let browserCredentialService: any BrowserCredentialProviding

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCredentialService: any BrowserCredentialProviding = BrowserCredentialService()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCredentialService = browserCredentialService
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .trae)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Trae SOLO 官方来源当前仅支持 API 检测")
        }

        let allowsBrowserFallback = official.sourceMode == .auto
        var attempted = Set<String>()

        do {
            let jwt = try resolveJWT()
            attempted.insert(jwt)
            return try await requestSnapshot(jwt: jwt)
        } catch let error as ProviderError {
            guard allowsBrowserFallback, Self.isCredentialRefreshable(error) else {
                throw error
            }
        }

        for candidate in browserJWTCandidates(excluding: attempted) {
            attempted.insert(candidate.jwt)
            do {
                var snapshot = try await requestSnapshot(jwt: candidate.jwt)
                snapshot.authSourceLabel = candidate.source
                persistJWT(candidate.jwt)
                return snapshot
            } catch let error as ProviderError {
                guard Self.isCredentialRefreshable(error) else {
                    throw error
                }
            }
        }

        throw ProviderError.unauthorizedDetail(
            "Trae SOLO Authorization 已失效，且未在浏览器中找到可用登录态。请登录 trae.ai 后重试，或重新粘贴最新 Cloud-IDE-JWT。"
        )
    }

    private func resolveJWT() throws -> String {
        let location = credentialLocation()
        let service = location.service
        let account = location.account
        guard let token = keychain.readToken(service: service, account: account) else {
            throw ProviderError.missingCredential(account)
        }

        let normalized = Self.normalizeToken(token)
        guard !normalized.isEmpty else {
            throw ProviderError.missingCredential(account)
        }
        return normalized
    }

    private func credentialLocation() -> (service: String, account: String) {
        (
            descriptor.auth.keychainService ?? TokenCredentialStoreServiceNames.defaultServiceName,
            descriptor.auth.keychainAccount ?? "official/trae/cloud-ide-jwt"
        )
    }

    private func persistJWT(_ jwt: String) {
        let normalized = Self.normalizeToken(jwt)
        guard !normalized.isEmpty else { return }
        let location = credentialLocation()
        _ = keychain.saveToken(normalized, service: location.service, account: location.account)
    }

    private func browserJWTCandidates(excluding attempted: Set<String>) -> [(jwt: String, source: String)] {
        let hosts = ["trae.ai", "api-sg-central.trae.ai"]
        var seen = attempted
        var output: [(jwt: String, source: String)] = []

        for host in hosts {
            for candidate in browserCredentialService.detectBearerTokenCandidates(
                host: host,
                accessIntent: .authRecovery
            ) {
                let jwt = Self.normalizeToken(candidate.value)
                guard Self.looksLikeJWT(jwt), seen.insert(jwt).inserted else { continue }
                output.append((jwt: jwt, source: "\(candidate.source):\(host)"))
            }
        }

        return output
    }

    private func requestSnapshot(jwt: String) async throws -> UsageSnapshot {
        let baseURL = (descriptor.baseURL?.isEmpty == false ? descriptor.baseURL : nil) ?? "https://api-sg-central.trae.ai"
        guard let url = URL(string: baseURL + "/trae/api/v1/pay/ide_user_ent_usage") else {
            throw ProviderError.invalidResponse("invalid Trae endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("Cloud-IDE-JWT \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["require_usage": true])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Trae non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            let message = Self.extractMessage(from: data)
            let suffix = message.map { ": \($0)" } ?? ""
            throw ProviderError.invalidResponse("Trae http \(http.statusCode)\(suffix)")
        }

        return try Self.parseSnapshot(data: data, descriptor: descriptor)
    }

    internal static func parseSnapshot(data: Data, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Trae response decode failed")
        }
        return try parseSnapshot(root: root, descriptor: descriptor)
    }

    private static func parseSnapshot(root: [String: Any], descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let payload = (root["data"] as? [String: Any]) ?? root
        let entries = ((payload["user_entitlement_pack_list"] as? [Any]) ?? [])
            .compactMap { $0 as? [String: Any] }
        guard let pack = entries.first else {
            throw ProviderError.invalidResponse("missing Trae entitlement pack")
        }

        let usage = (pack["usage"] as? [String: Any]) ?? [:]
        let entitlementBase = (pack["entitlement_base_info"] as? [String: Any]) ?? [:]
        let quota = (entitlementBase["quota"] as? [String: Any]) ?? [:]

        guard let dollarUsed = OfficialValueParser.double(usage["basic_usage_amount"]),
              let dollarLimit = OfficialValueParser.double(quota["basic_usage_limit"]),
              let autocompleteUsed = OfficialValueParser.double(usage["auto_completion_usage"]),
              let autocompleteLimit = OfficialValueParser.double(quota["auto_completion_limit"]) else {
            throw ProviderError.invalidResponse("missing Trae quota fields")
        }

        let dollar = usageWindow(used: dollarUsed, limit: dollarLimit)
        let autocomplete = usageWindow(used: autocompleteUsed, limit: autocompleteLimit)
        let resetAt = OfficialValueParser.epochDate(seconds: entitlementBase["end_time"])
        let planType = PlanTypeDisplayFormatter.normalizedPlanType(
            OfficialValueParser.string(pack["display_desc"]),
            providerType: .trae
        )

        let windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-dollar",
                title: "美元余额",
                remainingPercent: dollar.remainingPercent,
                usedPercent: dollar.usedPercent,
                resetAt: resetAt,
                kind: .custom
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-autocomplete",
                title: "自动补全",
                remainingPercent: autocomplete.remainingPercent,
                usedPercent: autocomplete.usedPercent,
                resetAt: resetAt,
                kind: .custom
            )
        ]

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let status: SnapshotStatus = remaining <= descriptor.threshold.lowRemaining ? .warning : .ok
        let usageNote = "美元余额 \(Int(dollar.remainingPercent.rounded()))% | 自动补全 \(Int(autocomplete.remainingPercent.rounded()))%"
        let note: String
        if let planType {
            note = "Plan \(planType) | \(usageNote)"
        } else {
            note = usageNote
        }

        var extras: [String: String] = [
            "dollarUsed": formatAmount(dollarUsed),
            "dollarLimit": formatAmount(dollarLimit),
            "dollarRemaining": formatAmount(max(0, dollarLimit - dollarUsed)),
            "autocompleteUsed": formatAmount(autocompleteUsed),
            "autocompleteLimit": formatAmount(autocompleteLimit),
            "autocompleteRemaining": formatAmount(max(0, autocompleteLimit - autocompleteUsed)),
        ]
        if let planType {
            extras["planType"] = planType
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: status,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: extras,
            rawMeta: [
                "trae.entitlement.end_time": OfficialValueParser.int(entitlementBase["end_time"]).map(String.init) ?? ""
            ]
        )
    }

    internal static func normalizeToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        token = trimWrappingQuotes(token)

        let prefixes = ["cloud-ide-jwt ", "bearer "]
        var changed = true
        while changed {
            changed = false
            let lower = token.lowercased()
            for prefix in prefixes where lower.hasPrefix(prefix) {
                token = String(token.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }

        token = trimWrappingQuotes(token)
        if let decoded = token.removingPercentEncoding, decoded.contains(".") {
            token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func looksLikeJWT(_ token: String) -> Bool {
        token.split(separator: ".").count >= 3
    }

    private static func isCredentialRefreshable(_ error: ProviderError) -> Bool {
        switch error {
        case .missingCredential, .unauthorized, .unauthorizedDetail:
            return true
        case .rateLimited, .invalidResponse, .commandFailed, .timeout, .unavailable:
            return false
        }
    }

    private static func usageWindow(used: Double, limit: Double) -> (remainingPercent: Double, usedPercent: Double) {
        guard limit > 0 else {
            let usedPercent = used > 0 ? 100.0 : 0
            return (remainingPercent: max(0, 100 - usedPercent), usedPercent: usedPercent)
        }
        let cappedUsed = min(limit, max(0, used))
        let usedPercent = min(100, max(0, (cappedUsed / limit) * 100))
        let remainingPercent = max(0, min(100, ((max(0, limit - cappedUsed)) / limit) * 100))
        return (remainingPercent, usedPercent)
    }

    private static func extractMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return OfficialValueParser.string(root["msg"] ?? root["message"])
    }

    private static func formatAmount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func trimWrappingQuotes(_ value: String) -> String {
        var output = value
        while output.hasPrefix("\""), output.hasSuffix("\""), output.count >= 2 {
            output = String(output.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
    }
}
