import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

/// 千问AI平台（platform.qianwenai.com）：Coding Plan（Token Plan 个人版）与按量付费余额。
///
/// 平台没有开放 API Key 鉴权的额度查询接口，额度数据只能走控制台会话：
/// 前端统一 POST 网关 `platform-home.qianwenai.com/data/api.json?product=…&action=…`，
/// 表单体携带 `product / action / sec_token / region / params(JSON)`，Cookie 鉴权。
/// `sec_token` 由 `GET /tool/user/info.json` 下发，同时用于判定登录态与取账号名。
final class QwenProvider: UsageProvider, @unchecked Sendable {
    static let manualCookieAccount = "official/qwen/cookie-header"

    private static let webReadBackoff = WebOverlayRetryBackoff()
    private static let defaultConsoleOrigin = "https://platform.qianwenai.com"
    /// Token Plan 个人版 / 加油包在国内站的商品码（来自控制台前端常量）。
    private static let planCommodityCodeCN = "sfm_tokenplansolo_public_cn"
    private static let addonCommodityCodeCN = "sfm_tokenplansoloaddon_public_cn"

    private enum TokenPlanAPI {
        static let usage = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage"
        static let subscription = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/subscription"
        static let addonList = "zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/addon/list"
    }

    struct SessionContext: Sendable {
        let secToken: String
        let accountLabel: String?
    }

    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCookieService: any BrowserCookieDetecting
    private let webReadBackoff: WebOverlayRetryBackoff
    private let webRetryBackoffInterval: TimeInterval = 15 * 60

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCookieService: any BrowserCookieDetecting,
        webReadBackoff: WebOverlayRetryBackoff = QwenProvider.webReadBackoff
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.webReadBackoff = webReadBackoff
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: descriptor.type)
        guard official.sourceMode == .auto || official.sourceMode == .web else {
            throw ProviderError.unavailable("千问官方来源当前仅支持 Web 检测")
        }

        let cookie = try await resolveCookieHeader(forceRefresh: forceRefresh)
        let context = try await fetchSessionContext(cookieHeader: cookie.header)

        var snapshot: UsageSnapshot
        switch descriptor.type {
        case .qwenBalance:
            snapshot = try await fetchBalanceSnapshot(cookieHeader: cookie.header, context: context)
        default:
            snapshot = try await fetchCodingPlanSnapshot(cookieHeader: cookie.header, context: context)
        }
        snapshot.extras["webCookieSource"] = cookie.source
        return snapshot
    }

    // MARK: - Cookie

    private func resolveCookieHeader(forceRefresh: Bool) async throws -> BrowserCookieHeader {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: descriptor.type)
        return try await OfficialProviderWebOverlayRuntime.resolveCookieHeader(
            official: official,
            descriptorID: descriptor.id,
            keychain: keychain,
            browserCookieService: browserCookieService,
            webReadBackoff: webReadBackoff,
            webRetryBackoffInterval: webRetryBackoffInterval,
            forceRefresh: forceRefresh,
            strategy: OfficialBrowserCookieImportStrategy(
                providerKey: "qwen",
                hostContains: Self.cookieHostContains(consoleOrigin: consoleOrigin),
                namedCookie: nil,
                autoImportMissingCredential: "platform.qianwenai.com cookie",
                manualCredentialFallback: Self.manualCookieAccount,
                normalizeManualHeader: Self.normalizeCookieHeader,
                normalizeDetectedHeader: Self.normalizeCookieHeader
            )
        )
    }

    /// 控制台域名为 platform.qianwenai.com，Cookie 记在父域 qianwenai.com 上。
    internal static func cookieHostContains(consoleOrigin: String) -> String {
        guard let host = URL(string: consoleOrigin)?.host, !host.isEmpty else {
            return "qianwenai.com"
        }
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        return labels.suffix(2).joined(separator: ".")
    }

    /// 控制台页面在 platform.qianwenai.com，网关同源部署在 platform-home.qianwenai.com。
    internal static func gatewayOrigin(consoleOrigin: String) -> String {
        guard let host = URL(string: consoleOrigin)?.host, !host.isEmpty else {
            return "https://platform-home.qianwenai.com"
        }
        if host.hasPrefix("platform.") {
            return "https://platform-home." + host.dropFirst("platform.".count)
        }
        return "https://" + host
    }

    private var consoleOrigin: String {
        var base = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = Self.defaultConsoleOrigin
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    internal static func normalizeCookieHeader(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty, value.contains("=") else { return nil }
        return value
    }

    // MARK: - Session / sec_token

    private func fetchSessionContext(cookieHeader: String) async throws -> SessionContext {
        guard let url = URL(string: gatewayOrigin + "/tool/user/info.json") else {
            throw ProviderError.invalidResponse("invalid Qwen user info URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await perform(request: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Qwen user info decode failed")
        }
        guard Self.isEnvelopeSuccess(root),
              let payload = Self.envelopeData(root) else {
            // 未登录/会话过期：网关返回 successResponse=false。
            throw ProviderError.unauthorized
        }
        let secToken = OfficialValueParser.string(payload["secToken"]) ?? ""
        let account = OfficialValueParser.nonPlaceholderString(payload["nickName"])
            ?? OfficialValueParser.nonPlaceholderString(payload["displayName"])
            ?? OfficialValueParser.nonPlaceholderString(payload["loginId"])
            ?? OfficialValueParser.nonPlaceholderString(payload["email"])
        return SessionContext(secToken: secToken, accountLabel: account)
    }

    // MARK: - Gateway

    private var gatewayOrigin: String {
        Self.gatewayOrigin(consoleOrigin: consoleOrigin)
    }

    private func callGateway(
        product: String,
        action: String,
        params: [String: Any],
        cookieHeader: String,
        secToken: String
    ) async throws -> Any {
        guard var components = URLComponents(string: gatewayOrigin + "/data/api.json") else {
            throw ProviderError.invalidResponse("invalid Qwen gateway URL")
        }
        components.queryItems = [
            URLQueryItem(name: "product", value: product),
            URLQueryItem(name: "action", value: action)
        ]
        guard let url = components.url else {
            throw ProviderError.invalidResponse("invalid Qwen gateway URL")
        }

        let paramsJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: params),
           let text = String(data: data, encoding: .utf8) {
            paramsJSON = text
        } else {
            paramsJSON = "{}"
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "product", value: product),
            URLQueryItem(name: "action", value: action),
            URLQueryItem(name: "sec_token", value: secToken),
            // 控制台在未显式配置 REGION 时固定回落到 ap-southeast-1，跟随该行为。
            URLQueryItem(name: "region", value: "ap-southeast-1"),
            URLQueryItem(name: "params", value: paramsJSON)
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, _) = try await perform(request: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Qwen gateway decode failed")
        }
        guard Self.isEnvelopeSuccess(root) else {
            throw Self.envelopeError(root, fallback: "\(product).\(action)")
        }
        return Self.envelopeData(root) ?? [:]
    }

    private func perform(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Qwen non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Qwen http \(http.statusCode)")
        }
        return (data, http)
    }

    /// 网关信封成功判定：`successResponse == true` 或 `code == 200/"200"`。
    internal static func isEnvelopeSuccess(_ root: [String: Any]) -> Bool {
        if let success = root["successResponse"] as? Bool {
            return success
        }
        if let code = OfficialValueParser.int(root["code"]) {
            return code == 200
        }
        if let code = (root["code"] as? String), code == "200" {
            return true
        }
        return false
    }

    /// 载荷在 `data` 或 `Data` 下（BssOpenAPI 用大写 `Data`，sfm_bailian 用小写 `data`）。
    internal static func envelopeData(_ root: [String: Any]) -> [String: Any]? {
        (root["data"] as? [String: Any]) ?? (root["Data"] as? [String: Any])
    }

    private static func envelopeError(_ root: [String: Any], fallback: String) -> ProviderError {
        let message = OfficialValueParser.string(root["message"])
            ?? OfficialValueParser.string(root["msg"])
            ?? OfficialValueParser.string(root["errorMsg"])
            ?? OfficialValueParser.string(root["errorCode"])
            ?? "unknown error"
        let codeText = (OfficialValueParser.string(root["code"])
            ?? OfficialValueParser.string(root["errorCode"])
            ?? "").lowercased()
        if codeText.contains("login") || codeText.contains("auth") || codeText == "401" || codeText == "403" {
            return .unauthorizedDetail("\(fallback): \(message)")
        }
        return .invalidResponse("Qwen \(fallback): \(message)")
    }

    /// 由内向外逐层探测数据容器：内层 API 有时再包一层 `{code, data}`。
    internal static func dataContainers(_ root: [String: Any]) -> [[String: Any]] {
        var containers: [[String: Any]] = [root]
        var queue: [[String: Any]] = [root]
        var depth = 0
        while !queue.isEmpty, depth < 3 {
            var next: [[String: Any]] = []
            for container in queue {
                for key in ["data", "Data"] {
                    if let child = container[key] as? [String: Any] {
                        containers.append(child)
                        next.append(child)
                    }
                }
            }
            queue = next
            depth += 1
        }
        return containers
    }

    /// 金额字符串可能带千分位逗号（如 "1,234.56"），统一清洗后转 Double。
    internal static func numericValue(_ value: Any?) -> Double? {
        if let number = OfficialValueParser.double(value) {
            return number
        }
        if let string = OfficialValueParser.string(value) {
            let cleaned = string.replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(cleaned)
        }
        return nil
    }

    // MARK: - Coding Plan（Token Plan 个人版）

    private func fetchCodingPlanSnapshot(
        cookieHeader: String,
        context: SessionContext
    ) async throws -> UsageSnapshot {
        let usage = try await callGateway(
            product: "sfm_bailian",
            action: "BroadScopeAspnGateway",
            params: ["Api": TokenPlanAPI.usage, "Data": [String: Any]()],
            cookieHeader: cookieHeader,
            secToken: context.secToken
        )
        // 订阅信息与加油包只影响展示丰富度，失败不掩盖主额度窗口。
        let subscription = try? await callGateway(
            product: "sfm_bailian",
            action: "BroadScopeAspnGateway",
            params: ["Api": TokenPlanAPI.subscription, "Data": ["commodityCode": Self.planCommodityCodeCN]],
            cookieHeader: cookieHeader,
            secToken: context.secToken
        )
        let addons = try? await callGateway(
            product: "sfm_bailian",
            action: "BroadScopeAspnGateway",
            params: [
                "Api": TokenPlanAPI.addonList,
                "Data": [
                    "commodityCode": Self.addonCommodityCodeCN,
                    "status": ["ACTIVE"],
                    "pageNum": 1,
                    "pageSize": 10
                ]
            ],
            cookieHeader: cookieHeader,
            secToken: context.secToken
        )

        let usageRoot = (usage as? [String: Any]) ?? [:]
        let subscriptionRoot = (subscription as? [String: Any]) ?? [:]
        let addonRoot = (addons as? [String: Any]) ?? [:]
        var snapshot = try Self.parseCodingPlanSnapshot(
            usageRoot: usageRoot,
            subscriptionRoot: subscriptionRoot,
            addonRoot: addonRoot,
            descriptor: descriptor
        )
        snapshot.accountLabel = context.accountLabel
        return snapshot
    }

    internal static func parseCodingPlanSnapshot(
        usageRoot: [String: Any],
        subscriptionRoot: [String: Any],
        addonRoot: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        var windows: [UsageQuotaWindow] = []

        // 7 天滚动限额：per1WeekPercentage 为已用比例（0...1），per1WeekResetTime 为毫秒时间戳。
        let usageContainers = dataContainers(usageRoot)
        var usedFraction: Double?
        var weeklyReset: Date?
        for container in usageContainers {
            if usedFraction == nil {
                usedFraction = numericValue(container["per1WeekPercentage"])
            }
            if weeklyReset == nil {
                weeklyReset = millisecondDate(container["per1WeekResetTime"])
            }
        }
        if let fraction = usedFraction {
            // 兼容上游直接下发百分数的形态。
            let normalized = fraction > 1 ? fraction / 100 : fraction
            let usedPercent = max(0, min(100, normalized * 100))
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-weekly",
                    title: "7-day",
                    remainingPercent: max(0, 100 - usedPercent),
                    usedPercent: usedPercent,
                    resetAt: weeklyReset,
                    kind: .weekly
                )
            )
        }

        // 加油包：按 remainingCredits/totalCredits 汇总为一条 Credits 窗口。
        let addonContainers = dataContainers(addonRoot)
        var addonItems: [[String: Any]] = []
        for container in addonContainers where addonItems.isEmpty {
            for key in ["items", "list", "records", "data"] {
                if let items = container[key] as? [[String: Any]], !items.isEmpty {
                    addonItems = items
                    break
                }
            }
        }
        var addonRemaining = 0.0
        var addonTotal = 0.0
        var addonExpiry: Date?
        for item in addonItems {
            addonRemaining += numericValue(item["remainingCredits"]) ?? 0
            addonTotal += numericValue(item["totalCredits"]) ?? 0
            if let endTime = millisecondDate(item["endTime"]) {
                addonExpiry = max(addonExpiry ?? endTime, endTime)
            }
        }
        if addonTotal > 0 {
            let remainingPercent = max(0, min(100, addonRemaining / addonTotal * 100))
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-credits",
                    title: "加油包",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: addonExpiry,
                    kind: .credits
                )
            )
        }

        let subscriptionContainers = dataContainers(subscriptionRoot)
        let planType = planLabel(from: subscriptionContainers)
        let expiry = subscriptionContainers.lazy
            .compactMap { millisecondDate($0["endTime"]) }
            .first

        guard !windows.isEmpty else {
            throw ProviderError.unavailable("千问 Token Plan 未订阅或已失效")
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        var noteParts = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }
        if let planType {
            noteParts.insert("Plan \(planType)", at: 0)
        }

        var extras: [String: String] = [:]
        if let planType {
            extras["planType"] = planType
        }
        if addonTotal > 0 {
            extras["addonRemainingCredits"] = String(format: "%.0f", addonRemaining)
            extras["addonTotalCredits"] = String(format: "%.0f", addonTotal)
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: noteParts.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "Console",
            accountLabel: nil,
            extras: extras,
            rawMeta: [
                "qwen.endpoint.usage": TokenPlanAPI.usage,
                "qwen.planExpiry": expiry.map { String($0.timeIntervalSince1970) } ?? ""
            ]
        )
    }

    /// 订阅信息里的套餐档位：specType/specCode（lite/standard/pro），取第一个非空值并首字母大写。
    private static func planLabel(from containers: [[String: Any]]) -> String? {
        for container in containers {
            for key in ["specType", "specCode", "planType", "commodityName"] {
                if let raw = OfficialValueParser.nonPlaceholderString(container[key]) {
                    return raw.prefix(1).uppercased() + raw.dropFirst()
                }
            }
        }
        return nil
    }

    // MARK: - 按量付费余额

    private func fetchBalanceSnapshot(
        cookieHeader: String,
        context: SessionContext
    ) async throws -> UsageSnapshot {
        let payload = try await callGateway(
            product: "BssOpenAPI-V3",
            action: "GetBillingAccountAvailableAmount",
            params: [:],
            cookieHeader: cookieHeader,
            secToken: context.secToken
        )
        var snapshot = try Self.parseBalanceSnapshot(
            root: (payload as? [String: Any]) ?? [:],
            descriptor: descriptor
        )
        snapshot.accountLabel = context.accountLabel
        return snapshot
    }

    internal static func parseBalanceSnapshot(
        root: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        var remaining: Double?
        for container in dataContainers(root) where remaining == nil {
            remaining = numericValue(container["AvailableAmount"])
                ?? numericValue(container["availableAmount"])
        }
        guard let remaining else {
            throw ProviderError.invalidResponse("missing Qwen AvailableAmount")
        }

        let currency = "CNY"
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
            sourceLabel: "Console",
            accountLabel: nil,
            extras: ["balance": String(format: "%.2f", max(0, remaining)), "currency": currency],
            rawMeta: ["qwen.endpoint": "BssOpenAPI-V3/GetBillingAccountAvailableAmount"]
        )
    }

    private static func millisecondDate(_ value: Any?) -> Date? {
        guard let raw = numericValue(value), raw > 0 else { return nil }
        // 上游时间戳为毫秒；个别字段可能是秒，按数量级粗判。
        let seconds = raw > 1e12 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
