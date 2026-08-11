import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class MicrosoftCopilotProvider: UsageProvider, @unchecked Sendable {
    private let session: URLSession
    private let shell: any ShellCommandRunning
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        shell: any ShellCommandRunning = DefaultShellCommandRunner()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.shell = shell
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .microsoftCopilot)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("Microsoft Copilot 官方来源当前仅支持 API 检测")
        }

        let token = try resolveToken()
        async let d7Root = requestSummary(period: "D7", accessToken: token)
        async let d30Root = requestSummary(period: "D30", accessToken: token)
        return try await Self.parseSnapshot(
            d7Root: d7Root,
            d30Root: d30Root,
            descriptor: descriptor
        )
    }

    private func resolveToken() throws -> String {
        let env = ProcessInfo.processInfo.environment
        for key in ["MS_GRAPH_TOKEN", "MICROSOFT_GRAPH_TOKEN"] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        if let value = SecurityCredentialReader.readGenericPassword(
            service: TokenCredentialStoreServiceNames.defaultServiceName,
            account: "official/microsoft-copilot/graph-token"
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        if let value = SecurityCredentialReader.readGenericPassword(
            service: "microsoft-graph-token"
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        if let token = tokenFromAzureCLI(arguments: [
            "account", "get-access-token",
            "--resource-type", "ms-graph",
            "--query", "accessToken",
            "-o", "tsv"
        ]) {
            return token
        }

        if let token = tokenFromAzureCLI(arguments: [
            "account", "get-access-token",
            "--resource", "https://graph.microsoft.com",
            "--query", "accessToken",
            "-o", "tsv"
        ]) {
            return token
        }

        throw ProviderError.missingCredential("MS_GRAPH_TOKEN")
    }

    private func tokenFromAzureCLI(arguments: [String]) -> String? {
        guard let result = shell.run(
            executable: "/usr/bin/env",
            arguments: ["az"] + arguments,
            timeout: 12
        ), result.status == 0 else {
            return nil
        }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private func requestSummary(period: String, accessToken: String) async throws -> [String: Any] {
        let baseURL = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? descriptor.baseURL!
            : "https://graph.microsoft.com"
        let path = "/v1.0/copilot/reports/getMicrosoft365CopilotUserCountSummary(period='\(period)')?$format=application/json"
        guard let url = URL(string: baseURL + path) else {
            throw ProviderError.invalidResponse("invalid Microsoft Copilot url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Microsoft Copilot non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.unauthorized
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Microsoft Copilot http \(http.statusCode)")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Microsoft Copilot response decode failed")
        }
        return root
    }

    internal static func parseSnapshot(
        d7Root: [String: Any],
        d30Root: [String: Any],
        descriptor: ProviderDescriptor
    ) throws -> UsageSnapshot {
        let d7 = try usageSummary(from: d7Root, expectedPeriod: 7, fallbackLabel: "D7")
        let d30 = try usageSummary(from: d30Root, expectedPeriod: 30, fallbackLabel: "D30")

        let windows: [UsageQuotaWindow] = [
            UsageQuotaWindow(
                id: "\(descriptor.id)-d7",
                title: "D7",
                remainingPercent: d7.adoptionPercent,
                usedPercent: max(0, 100 - d7.adoptionPercent),
                resetAt: nil,
                kind: .custom
            ),
            UsageQuotaWindow(
                id: "\(descriptor.id)-d30",
                title: "D30",
                remainingPercent: d30.adoptionPercent,
                usedPercent: max(0, 100 - d30.adoptionPercent),
                resetAt: nil,
                kind: .custom
            )
        ]
        let remaining = min(d7.adoptionPercent, d30.adoptionPercent)
        let note = "M365 | D7 \(d7.activeUsers)/\(d7.enabledUsers) | D30 \(d30.activeUsers)/\(d30.enabledUsers)"

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: note,
            quotaWindows: windows,
            sourceLabel: "Graph API",
            accountLabel: nil,
            extras: [
                "planType": "M365",
                "d7ActiveUsers": String(d7.activeUsers),
                "d7EnabledUsers": String(d7.enabledUsers),
                "d30ActiveUsers": String(d30.activeUsers),
                "d30EnabledUsers": String(d30.enabledUsers)
            ],
            rawMeta: [
                "microsoftCopilot.scope": "m365-reports"
            ]
        )
    }

    private static func usageSummary(
        from root: [String: Any],
        expectedPeriod: Int,
        fallbackLabel: String
    ) throws -> MicrosoftCopilotSummary {
        let values = (root["value"] as? [Any]) ?? []
        let objects = values.compactMap { $0 as? [String: Any] }
        for entry in objects {
            if let summary = summaryFromEntry(entry, expectedPeriod: expectedPeriod, fallbackLabel: fallbackLabel) {
                return summary
            }
        }
        throw ProviderError.invalidResponse("missing Microsoft Copilot \(fallbackLabel) summary")
    }

    private static func summaryFromEntry(
        _ entry: [String: Any],
        expectedPeriod: Int,
        fallbackLabel: String
    ) -> MicrosoftCopilotSummary? {
        if let summary = summaryFromNode(entry, expectedPeriod: expectedPeriod, fallbackLabel: fallbackLabel) {
            return summary
        }

        if let adoptionArray = entry["adoptionByProduct"] as? [Any] {
            for raw in adoptionArray {
                guard let node = raw as? [String: Any] else { continue }
                if let summary = summaryFromNode(node, expectedPeriod: expectedPeriod, fallbackLabel: fallbackLabel) {
                    return summary
                }
            }
        }

        if let adoptionObject = entry["adoptionByProduct"] as? [String: Any] {
            for raw in adoptionObject.values {
                guard let node = raw as? [String: Any] else { continue }
                if let summary = summaryFromNode(node, expectedPeriod: expectedPeriod, fallbackLabel: fallbackLabel) {
                    return summary
                }
            }
        }

        return nil
    }

    private static func summaryFromNode(
        _ node: [String: Any],
        expectedPeriod: Int,
        fallbackLabel: String
    ) -> MicrosoftCopilotSummary? {
        if let reportPeriod = OfficialValueParser.int(node["reportPeriod"] ?? node["period"]),
           reportPeriod != expectedPeriod {
            return nil
        }

        guard let activeUsers = OfficialValueParser.int(node["anyAppActiveUsers"] ?? node["activeUsers"]),
              let enabledUsers = OfficialValueParser.int(node["anyAppEnabledUsers"] ?? node["enabledUsers"]),
              enabledUsers > 0 else {
            return nil
        }

        let title = OfficialValueParser.string(node["reportPeriodLabel"]) ?? fallbackLabel
        let adoptionPercent = max(0, min(100, Double(activeUsers) / Double(enabledUsers) * 100))
        return MicrosoftCopilotSummary(
            title: title,
            activeUsers: activeUsers,
            enabledUsers: enabledUsers,
            adoptionPercent: adoptionPercent
        )
    }
}

private struct MicrosoftCopilotSummary {
    var title: String
    var activeUsers: Int
    var enabledUsers: Int
    var adoptionPercent: Double
}
