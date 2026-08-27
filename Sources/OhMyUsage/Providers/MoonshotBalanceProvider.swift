import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

/// Moonshot 开放平台（platform.moonshot.cn）按量付费余额，与 Kimi 订阅额度独立。
final class MoonshotBalanceProvider: UsageProvider, @unchecked Sendable {
    static let balanceKeychainAccount = "official/moonshot/api-key"

    private let session: URLSession
    private let keychain: (any TokenCredentialStoring)?
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: (any TokenCredentialStoring)? = nil
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: descriptor.type)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Kimi (API) 官方来源当前仅支持 API 检测")
        }
        let apiKey = try resolveAPIKey()
        let root = try await request(apiKey: apiKey)
        return try Self.parseBalanceSnapshot(root: root, descriptor: descriptor)
    }

    /// 环境变量 MOONSHOT_API_KEY 优先，其次是输入框保存在钥匙串的 key。
    private func resolveAPIKey() throws -> String {
        if let value = ProcessInfo.processInfo.environment["MOONSHOT_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        if let keychain {
            let service = descriptor.auth.keychainService ?? TokenCredentialStoreServiceNames.defaultServiceName
            let account = descriptor.auth.keychainAccount ?? Self.balanceKeychainAccount
            if let token = keychain.readToken(service: service, account: account)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                return token
            }
        }
        throw ProviderError.missingCredential("Moonshot API Key")
    }

    private func request(apiKey: String) async throws -> [String: Any] {
        let baseURL = descriptor.baseURL ?? "https://api.moonshot.cn"
        guard let url = URL(string: baseURL + "/v1/users/me/balance") else {
            throw ProviderError.invalidResponse("invalid Moonshot url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Moonshot non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Moonshot http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Moonshot response decode failed")
        }
        return json
    }

    /// Moonshot 开放平台余额：`GET /v1/users/me/balance` 返回
    /// `{code: 0, status: true, data: {available_balance, voucher_balance, cash_balance}}`。
    internal static func parseBalanceSnapshot(
        root: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        if let code = OfficialValueParser.int(root["code"]), code != 0 {
            let message = OfficialValueParser.string(root["message"])
                ?? OfficialValueParser.string(root["msg"])
                ?? "unknown Moonshot balance error"
            throw ProviderError.invalidResponse("Moonshot balance \(message)")
        }

        let data = (root["data"] as? [String: Any]) ?? [:]
        guard let remaining = OfficialValueParser.double(
            data["available_balance"] ?? data["availableBalance"]
        ) else {
            throw ProviderError.invalidResponse("missing Moonshot balance fields")
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= 0 ? .warning : .ok,
            remaining: max(0, remaining),
            used: nil,
            limit: nil,
            unit: "CNY",
            updatedAt: Date(),
            note: "Balance \(String(format: "%.2f", max(0, remaining)))",
            quotaWindows: [],
            sourceLabel: "API",
            accountLabel: nil,
            extras: ["balance": String(format: "%.2f", max(0, remaining)), "currency": "CNY"],
            rawMeta: ["moonshot.endpoint": "/v1/users/me/balance"]
        )
    }
}
