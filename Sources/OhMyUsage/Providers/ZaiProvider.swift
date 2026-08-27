import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class ZaiProvider: UsageProvider, @unchecked Sendable {
    static let balanceKeychainAccount = "official/zhipu/api-key"
    static let codingPlanKeychainAccount = "official/zhipu/coding-api-key"

    private let session: URLSession
    private let localJSONReader: any LocalJSONFileReading
    private let keychain: (any TokenCredentialStoring)?
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: (any TokenCredentialStoring)? = nil,
        localJSONReader: any LocalJSONFileReading = DefaultLocalJSONFileReader()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.localJSONReader = localJSONReader
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: descriptor.type)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Z.ai 官方来源当前仅支持 API 检测")
        }

        switch descriptor.type {
        case .zaiBalance:
            return try await fetchBalanceSnapshot()
        default:
            return try await fetchCodingPlanSnapshot()
        }
    }

    /// GLM Coding Plan 订阅额度：5h / Weekly 窗口。
    private func fetchCodingPlanSnapshot() async throws -> UsageSnapshot {
        let apiKey = try resolveAPIKey()
        let quotaRoot = try await codingPlanRequest(path: "/api/monitor/usage/quota/limit", apiKey: apiKey)
        // Plan metadata is optional. A temporary failure or upstream removal of
        // this endpoint must not hide otherwise valid quota data.
        let subscriptionRoot = (try? await codingPlanRequest(path: "/api/biz/subscription/list", apiKey: apiKey)) ?? [:]
        return try Self.parseSnapshot(subscriptionRoot: subscriptionRoot, quotaRoot: quotaRoot, descriptor: descriptor)
    }

    /// Coding Plan key 可能产自国内站（open.bigmodel.cn）或国际站（api.z.ai），
    /// 两站镜像了同一组查询端点，只有站点自己认得自家的 key。按主站点优先、
    /// 鉴权/路由类失败时切换镜像站重试一次。
    private func codingPlanRequest(path: String, apiKey: String) async throws -> [String: Any] {
        var lastError: ProviderError = .invalidResponse("Z.ai request failed")
        for host in Self.codingPlanHosts(primary: descriptor.baseURL ?? defaultBaseURL) {
            do {
                let root = try await request(path: path, apiKey: apiKey, baseURLOverride: host)
                if Self.isAppLevelAuthFailure(root) {
                    lastError = .unauthorized
                    continue
                }
                return root
            } catch let error as ProviderError {
                lastError = error
                guard case .rateLimited = error else { continue }
                throw error
            }
        }
        throw lastError
    }

    /// 与智谱两站部署一致：主站点失败时仅尝试另一个镜像。
    internal static func codingPlanHosts(primary: String) -> [String] {
        let mirror = primary.contains("bigmodel") ? "https://api.z.ai" : "https://open.bigmodel.cn"
        return [primary, mirror]
    }

    /// 这组端点对无效 key 返回 HTTP 200 + body `code: 401`，与正常响应同构，需归一化。
    private static func isAppLevelAuthFailure(_ root: [String: Any]) -> Bool {
        guard (root["success"] as? Bool) == false else { return false }
        let code = OfficialValueParser.int(root["code"])
        return code == 401 || code == 1001
    }

    /// 智谱开放平台按量付费余额（bigmodel.cn 与 api.z.ai 同构）。
    private func fetchBalanceSnapshot() async throws -> UsageSnapshot {
        let apiKey = try resolveAPIKey()
        // 原 `/api/paas/v4/user/balance` 已随控制台改版下线（两站均 404）。
        // 现网可用的是控制台账户报表接口，API Key 直接鉴权，字段见解析处注释。
        let root = try await codingPlanRequest(
            path: "/api/biz/account/query-customer-account-report",
            apiKey: apiKey
        )
        return try Self.parseBalanceSnapshot(root: root, descriptor: descriptor)
    }

    private func resolveAPIKey() throws -> String {
        if let discovered = Self.discoverLocalAPIKey(
            environment: ProcessInfo.processInfo.environment,
            localJSONReader: localJSONReader
        ) {
            return discovered
        }

        if let manuallySavedKey = readManuallySavedKey(), !manuallySavedKey.isEmpty {
            return manuallySavedKey
        }

        throw ProviderError.missingCredential(descriptor.type == .zaiBalance ? "智谱 API Key" : "ZAI_API_KEY")
    }

    /// 从本机环境发现智谱 API Key：环境变量优先，其次是 Claude Code 接入配置
    /// （~/.claude/settings.json 里的 ANTHROPIC_AUTH_TOKEN / providers.api_key）。
    /// 运行时兜底与设置页「从 Claude Code 导入」按钮共用同一份发现逻辑。
    internal static func discoverLocalAPIKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        localJSONReader: any LocalJSONFileReading = DefaultLocalJSONFileReader()
    ) -> String? {
        for key in ["ZAI_API_KEY", "GLM_API_KEY", "ZHIPU_API_KEY"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        let settingsPath = "\(NSHomeDirectory())/.claude/settings.json"
        if let text = localJSONReader.text(atPath: settingsPath),
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let env = json["env"] as? [String: Any],
               let baseURL = OfficialValueParser.string(env["ANTHROPIC_BASE_URL"]),
               (baseURL.contains("api.z.ai") || baseURL.contains("bigmodel.cn")),
               let auth = OfficialValueParser.string(env["ANTHROPIC_AUTH_TOKEN"]) {
                return auth
            }
            if let providers = json["providers"] as? [[String: Any]] {
                for provider in providers {
                    if let baseURL = OfficialValueParser.string(provider["base_url"]),
                       (baseURL.contains("api.z.ai") || baseURL.contains("bigmodel.cn")),
                       let apiKey = OfficialValueParser.string(provider["api_key"]) {
                        return apiKey
                    }
                }
            }
        }
        return nil
    }

    /// API Key 输入框保存在钥匙串，最后兜底读取。
    /// Coding Plan 与按量付费共用同一智谱账号体系，很多用户只有一把 key：
    /// 本描述符专属账号为空时回退到余额 key，避免重复填写。
    private func readManuallySavedKey() -> String? {
        guard let keychain else { return nil }
        let service = descriptor.auth.keychainService ?? TokenCredentialStoreServiceNames.defaultServiceName
        let account = descriptor.auth.keychainAccount ?? Self.balanceKeychainAccount
        if let token = keychain.readToken(service: service, account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        if account != Self.balanceKeychainAccount {
            return keychain.readToken(service: service, account: Self.balanceKeychainAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func request(
        path: String,
        apiKey: String,
        baseURLOverride: String? = nil
    ) async throws -> [String: Any] {
        let baseURL = baseURLOverride ?? descriptor.baseURL ?? defaultBaseURL
        guard let url = URL(string: baseURL + path) else {
            throw ProviderError.invalidResponse("invalid Z.ai url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        // The GLM quota/biz endpoints expect the API key verbatim. Adding a
        // Bearer prefix is accepted by some inference endpoints but rejected here.
        request.setValue(Self.authorizationHeaderValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Z.ai non-http response")
        }
        return try await perform(request: request, receivedData: data, httpResponse: http)
    }

    private func perform(
        request: URLRequest,
        receivedData: Data? = nil,
        httpResponse: HTTPURLResponse? = nil
    ) async throws -> [String: Any] {
        let (data, response): (Data, URLResponse)
        if let receivedData, let httpResponse, request.url == httpResponse.url {
            (data, response) = (receivedData, httpResponse)
        } else {
            (data, response) = try await session.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Z.ai non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            // 带上上游错误正文，404/403 这类账号形态差异才能现场定位。
            throw ProviderError.invalidResponse(Self.statusFailureDetail(status: http.statusCode, data: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Z.ai response decode failed")
        }
        return json
    }

    private var defaultBaseURL: String {
        descriptor.type == .zaiBalance ? "https://open.bigmodel.cn" : "https://api.z.ai"
    }

    /// 非 2xx 响应的报错文案：状态码 + 上游错误正文（截断），便于区分
    /// key 无效、账号形态不符、接口下线等场景。
    internal static func statusFailureDetail(status: Int, data: Data) -> String {
        var detail = "Z.ai http \(status)"
        if let json = (try? JSONSerialization.jsonObject(with: data)).flatMap({ $0 as? [String: Any] }) {
            let errorContainer = json["error"] as? [String: Any]
            let message = OfficialValueParser.string(errorContainer?["message"])
                ?? OfficialValueParser.string(json["message"])
                ?? OfficialValueParser.string(json["msg"])
            if let message, !message.isEmpty {
                detail += " · \(message.prefix(160))"
            }
        }
        return detail
    }

    internal static func authorizationHeaderValue(apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 智谱开放平台按量付费余额。
    ///
    /// 现网接口 `GET /api/biz/account/query-customer-account-report` 返回
    /// `{success, code, msg, data}`，data 内含
    /// `balance / availableBalance / frozenBalance / rechargeAmount ...`。
    /// 解析按常见形态逐级探测，兼容 `data.balance`、顶层 `balance`、
    /// `balance_infos` 及各类驼峰/下划线变体，并在控制台包裹层报错时透出原始 msg。
    internal static func parseBalanceSnapshot(
        root rootJson: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        if (rootJson["success"] as? Bool) == false {
            let message = OfficialValueParser.string(rootJson["msg"])
                ?? OfficialValueParser.string(rootJson["message"])
                ?? "unknown balance error"
            throw ProviderError.invalidResponse("Zhipu balance \(message)")
        }

        let balanceKeys = [
            "total_balance", "totalBalance",
            "available_balance", "availableBalance",
            "balance"
        ]
        let containers: [[String: Any]] = [
            rootJson,
            (rootJson["data"] as? [String: Any]) ?? [:]
        ]
        var remaining: Double?
        for container in containers where remaining == nil {
            remaining = Self.firstNumericValue(for: balanceKeys, in: container)
        }
        if remaining == nil {
            // DeepSeek 风格：balance_infos 数组可能出现在根级或 data 层。
            for container in containers where remaining == nil {
                if let infos = container["balance_infos"] as? [[String: Any]] {
                    for info in infos {
                        if let value = Self.firstNumericValue(for: balanceKeys, in: info) {
                            remaining = value
                            break
                        }
                    }
                }
            }
        }
        if remaining == nil {
            // 资源包形态：data 是列表，取第一个含余额字段的条目。
            let items = ((rootJson["data"] as? [Any]) ?? [])
                .compactMap { $0 as? [String: Any] }
            for item in items {
                if let value = Self.firstNumericValue(for: balanceKeys, in: item) {
                    remaining = value
                    break
                }
            }
        }

        guard let remaining else {
            throw ProviderError.invalidResponse("missing Zhipu balance fields")
        }

        let dataContainer = (rootJson["data"] as? [String: Any]) ?? [:]
        let currency = OfficialValueParser.string(dataContainer["currency"])
            ?? OfficialValueParser.string(rootJson["currency"])
            ?? "CNY"

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= 0 ? .warning : .ok,
            remaining: max(0, remaining),
            used: nil,
            limit: nil,
            unit: currency,
            updatedAt: Date(),
            note: "Balance \(String(format: "%.2f", max(0, remaining)))",
            quotaWindows: [],
            sourceLabel: "API",
            accountLabel: nil,
            extras: ["balance": String(format: "%.2f", max(0, remaining)), "currency": currency],
            rawMeta: ["zhipu.endpoint": "/api/biz/account/query-customer-account-report"]
        )
    }

    private static func firstNumericValue(for keys: [String], in container: [String: Any]) -> Double? {
        for key in keys {
            if let value = OfficialValueParser.double(container[key]), !key.isEmpty {
                return value
            }
        }
        return nil
    }

    internal static func parseSnapshot(
        subscriptionRoot: [String: Any],
        quotaRoot: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        let subscription = ((subscriptionRoot["data"] as? [Any]) ?? [])
            .compactMap { $0 as? [String: Any] }
            .first(where: { ($0["inCurrentPeriod"] as? Bool) == true })
            ?? ((subscriptionRoot["data"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.first

        let plan = OfficialValueParser.string(subscription?["productName"]) ?? "unknown"
        let monthlyReset = parseDateOnly(OfficialValueParser.string(subscription?["nextRenewTime"]))
        let limits = ((quotaRoot["data"] as? [String: Any])?["limits"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []

        var windows: [UsageQuotaWindow] = []
        for item in limits {
            let type = OfficialValueParser.string(item["type"]) ?? ""
            // 2026 年后新账号（如 GLM Coding Plan 体验卡 / lite）返回 CREDIT_LIMIT，
            // 老账号返回 TOKENS_LIMIT，字段结构一致，按同一规则解析。
            if type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT",
               let number = OfficialValueParser.int(item["number"]),
               let unit = OfficialValueParser.int(item["unit"]),
               let usedPercent = OfficialValueParser.double(item["percentage"]) {
                let kind: UsageQuotaKind
                let title: String
                if unit == 3 && number == 5 {
                    kind = .session
                    title = "5h"
                } else if unit == 6 {
                    kind = .weekly
                    title = "Weekly"
                } else {
                    kind = .custom
                    title = type == "CREDIT_LIMIT" ? "Credits" : "Tokens"
                }
                windows.append(
                    UsageQuotaWindow(
                        id: "\(descriptor.id)-\(kind.rawValue)-\(windows.count)",
                        title: title,
                        remainingPercent: max(0, 100 - usedPercent),
                        usedPercent: usedPercent,
                        resetAt: millisecondDate(item["nextResetTime"]),
                        kind: kind
                    )
                )
            }
            if type == "TIME_LIMIT",
               let remaining = OfficialValueParser.double(item["remaining"]),
               let total = OfficialValueParser.double(item["usage"]), total > 0 {
                let remainingPercent = remaining / total * 100
                windows.append(
                    UsageQuotaWindow(
                        id: "\(descriptor.id)-web",
                        title: "Web",
                        remainingPercent: remainingPercent,
                        usedPercent: max(0, 100 - remainingPercent),
                        resetAt: monthlyReset,
                        kind: .custom
                    )
                )
            }
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Z.ai quota windows")
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
            note: "Plan \(plan) | " + windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "API",
            accountLabel: nil,
            extras: ["planType": plan],
            rawMeta: [:]
        )
    }

    private static func parseDateOnly(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private static func millisecondDate(_ value: Any?) -> Date? {
        guard let raw = OfficialValueParser.double(value) else { return nil }
        return Date(timeIntervalSince1970: raw / 1000)
    }
}
