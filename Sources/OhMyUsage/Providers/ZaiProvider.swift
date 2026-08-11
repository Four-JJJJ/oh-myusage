import OhMyUsageDomain
import Foundation

final class ZaiProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor, session: URLSession = .shared) {
        self.descriptor = descriptor
        self.session = session
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .zai)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Z.ai 官方来源当前仅支持 API 检测")
        }

        let apiKey = try resolveAPIKey()
        let quotaRoot = try await request(path: "/api/monitor/usage/quota/limit", apiKey: apiKey)
        // Plan metadata is optional. A temporary failure or upstream removal of
        // this endpoint must not hide otherwise valid quota data.
        let subscriptionRoot = (try? await request(path: "/api/biz/subscription/list", apiKey: apiKey)) ?? [:]
        return try Self.parseSnapshot(subscriptionRoot: subscriptionRoot, quotaRoot: quotaRoot, descriptor: descriptor)
    }

    private func resolveAPIKey() throws -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["ZAI_API_KEY", "GLM_API_KEY"] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        let settingsPath = "\(NSHomeDirectory())/.claude/settings.json"
        if let text = LocalJSONFileReader.text(atPath: settingsPath),
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

        throw ProviderError.missingCredential("ZAI_API_KEY")
    }

    private func request(path: String, apiKey: String) async throws -> [String: Any] {
        let baseURL = descriptor.baseURL ?? "https://api.z.ai"
        guard let url = URL(string: baseURL + path) else {
            throw ProviderError.invalidResponse("invalid Z.ai url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        // The GLM quota endpoint expects the API key verbatim. Adding a Bearer
        // prefix is accepted by some inference endpoints but rejected here.
        request.setValue(Self.authorizationHeaderValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
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
            throw ProviderError.invalidResponse("Z.ai http \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Z.ai response decode failed")
        }
        return json
    }

    internal static func authorizationHeaderValue(apiKey: String) -> String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if type == "TOKENS_LIMIT",
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
                    title = "Tokens"
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
