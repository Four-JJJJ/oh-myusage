import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class CopilotProvider: UsageProvider, @unchecked Sendable {
    private struct ResolvedCredential {
        let token: String
        let sourceLabel: String
    }

    private let session: URLSession
    private let environment: () -> [String: String]
    private let keychainReader: (String, String?) -> String?
    private let shell: any ShellCommandRunning
    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        environment: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        keychainReader: @escaping (String, String?) -> String? = { service, account in
            SecurityCredentialReader.readGenericPassword(service: service, account: account)
        },
        shell: any ShellCommandRunning = DefaultShellCommandRunner()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.environment = environment
        self.keychainReader = keychainReader
        self.shell = shell
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .copilot)
        guard official.sourceMode == .auto || official.sourceMode == .api else {
            throw ProviderError.unavailable("GitHub Copilot 官方来源当前仅支持 API 检测")
        }

        let resolved = try resolveCredential()
        var request = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("token \(resolved.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Copilot non-http response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw Self.mapAuthorizationError(
                statusCode: http.statusCode,
                data: data,
                sourceLabel: resolved.sourceLabel
            )
        }
        if http.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("Copilot http \(http.statusCode)")
        }
        return try Self.parseSnapshot(
            data: data,
            descriptor: descriptor,
            authSourceLabel: resolved.sourceLabel
        )
    }

    private func resolveCredential() throws -> ResolvedCredential {
        let env = environment()
        for key in ["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"] {
            if let value = Self.normalizedCredential(env[key]) {
                return ResolvedCredential(token: value, sourceLabel: key)
            }
        }

        if let value = Self.normalizedCredential(keychainReader("copilot-cli", nil)) {
            return ResolvedCredential(token: value, sourceLabel: "Copilot CLI")
        }

        if let value = Self.normalizedCredential(keychainReader("gh:github.com", nil)) {
            return ResolvedCredential(token: value, sourceLabel: "GitHub CLI")
        }

        if let result = shell.run(executable: "/usr/bin/env", arguments: ["gh", "auth", "token"], timeout: 8),
           result.status == 0,
           let value = Self.normalizedCredential(result.stdout) {
            return ResolvedCredential(token: value, sourceLabel: "GitHub CLI")
        }

        throw ProviderError.missingCredential(
            "GitHub Copilot credential (COPILOT_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN, Copilot CLI, or GitHub CLI)"
        )
    }

    internal static func parseSnapshot(
        data: Data,
        descriptor: ProviderDescriptor,
        authSourceLabel: String? = nil,
        now: Date = Date()
    ) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("Copilot usage decode failed")
        }

        let plan = OfficialValueParser.nonPlaceholderString(root["copilot_plan"] ?? root["access_type_sku"])
        let accountLabel = resolveAccountLabel(root)
        let paidReset = OfficialValueParser.isoDate(
            OfficialValueParser.string(root["quota_reset_date"] ?? root["quota_reset_date_utc"])
        )
        let freeReset = parseDateOnly(OfficialValueParser.string(root["limited_user_reset_date"]))
        let limitedUser = root["limited_user_quotas"] as? [String: Any]
        let monthly = root["monthly_quotas"] as? [String: Any]

        var windowsByKind: [String: UsageQuotaWindow] = [:]
        var fallbackWindows: [UsageQuotaWindow] = []

        for candidate in quotaSnapshotCandidates(raw: root["quota_snapshots"]) {
            let quotaKey = quotaKeyHint(from: candidate.key)
            let percent = remainingPercent(
                from: candidate.value,
                quotaKeyHint: quotaKey,
                limitedUser: limitedUser,
                monthly: monthly
            )
            guard let percent,
                  !isPlaceholderSnapshot(candidate.value, remainingPercent: percent) else {
                continue
            }

            let title = quotaTitle(for: candidate.key)
            let id = "\(descriptor.id)-\(windowIdentifier(from: candidate.key))"
            let window = UsageQuotaWindow(
                id: id,
                title: title,
                remainingPercent: percent,
                usedPercent: max(0, 100 - percent),
                resetAt: paidReset,
                kind: .custom
            )

            if let canonical = canonicalSnapshotKind(for: candidate.key), windowsByKind[canonical] == nil {
                windowsByKind[canonical] = window
            } else {
                fallbackWindows.append(window)
            }
        }

        if windowsByKind["chat"] == nil,
           let percent = percentFromLimitedMonthly(quotaKey: "chat", limitedUser: limitedUser, monthly: monthly) {
            windowsByKind["chat"] = UsageQuotaWindow(
                id: "\(descriptor.id)-chat",
                title: "Chat",
                remainingPercent: percent,
                usedPercent: max(0, 100 - percent),
                resetAt: freeReset,
                kind: .custom
            )
        }

        if windowsByKind["completions"] == nil,
           let percent = percentFromLimitedMonthly(quotaKey: "completions", limitedUser: limitedUser, monthly: monthly) {
            windowsByKind["completions"] = UsageQuotaWindow(
                id: "\(descriptor.id)-completions",
                title: "Completions",
                remainingPercent: percent,
                usedPercent: max(0, 100 - percent),
                resetAt: freeReset,
                kind: .custom
            )
        }

        var windows: [UsageQuotaWindow] = []
        if let premium = windowsByKind["premium"] { windows.append(premium) }
        if let chat = windowsByKind["chat"], windows.contains(where: { $0.id == chat.id }) == false { windows.append(chat) }
        if let completions = windowsByKind["completions"], windows.count < 2,
           windows.contains(where: { $0.id == completions.id }) == false {
            windows.append(completions)
        }
        if windows.isEmpty, let firstFallback = fallbackWindows.first {
            windows.append(firstFallback)
        }
        if windows.count == 1,
           let second = fallbackWindows.first(where: { $0.id != windows[0].id }) {
            windows.append(second)
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("missing Copilot quota windows")
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let summary = windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | ")
        let notePrefix = plan.map { "Plan \($0)" } ?? "GitHub Copilot"

        var extras: [String: String] = [:]
        if let plan {
            extras["planType"] = plan
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: "\(notePrefix) | \(summary)",
            quotaWindows: windows,
            sourceLabel: "GitHub API",
            accountLabel: accountLabel,
            authSourceLabel: authSourceLabel,
            extras: extras,
            rawMeta: [:]
        )
    }

    private static func normalizedCredential(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private static func mapAuthorizationError(
        statusCode: Int,
        data: Data,
        sourceLabel: String
    ) -> ProviderError {
        let detail = extractErrorMessage(from: data)
        switch statusCode {
        case 401:
            var message = "GitHub Copilot rejected the \(sourceLabel) credential. Refresh that login or token and try again."
            if let detail, !detail.isEmpty {
                message += " Server: \(detail)"
            }
            return .unauthorizedDetail(message)
        case 403:
            var message = "GitHub Copilot accepted the \(sourceLabel) login, but this account cannot access Copilot usage. Check Copilot entitlement, org policy, and token scope."
            if let detail, !detail.isEmpty {
                message += " Server: \(detail)"
            }
            return .unauthorizedDetail(message)
        default:
            return .unauthorized
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error_description", "error", "detail"] {
                if let value = OfficialValueParser.nonPlaceholderString(root[key]) {
                    return value
                }
            }
            if let errors = root["errors"] as? [Any] {
                for item in errors {
                    guard let entry = item as? [String: Any] else { continue }
                    for key in ["message", "error", "detail"] {
                        if let value = OfficialValueParser.nonPlaceholderString(entry[key]) {
                            return value
                        }
                    }
                }
            }
        }

        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            raw.count <= 240 else {
            return nil
        }
        return raw
    }

    private static func resolveAccountLabel(_ root: [String: Any]) -> String? {
        let user = root["user"] as? [String: Any]
        return OfficialValueParser.nonPlaceholderString(root["login"])
            ?? OfficialValueParser.nonPlaceholderString(user?["login"])
            ?? OfficialValueParser.nonPlaceholderString(root["github_login"])
            ?? OfficialValueParser.nonPlaceholderString(user?["email"])
            ?? OfficialValueParser.nonPlaceholderString(root["email"])
    }

    private static func quotaSnapshotCandidates(raw: Any?) -> [(key: String, value: [String: Any])] {
        if let object = raw as? [String: Any] {
            return object.compactMap { key, value in
                guard let payload = value as? [String: Any] else { return nil }
                return (key: key, value: payload)
            }
        }

        if let array = raw as? [Any] {
            var output: [(key: String, value: [String: Any])] = []
            output.reserveCapacity(array.count)
            for (index, item) in array.enumerated() {
                guard let payload = item as? [String: Any] else { continue }
                let key = OfficialValueParser.string(payload["key"] ?? payload["name"] ?? payload["id"]) ?? "window_\(index)"
                output.append((key: key, value: payload))
            }
            return output
        }

        return []
    }

    private static func remainingPercent(
        from window: [String: Any],
        quotaKeyHint: String?,
        limitedUser: [String: Any]?,
        monthly: [String: Any]?
    ) -> Double? {
        if let percent = OfficialValueParser.double(window["percent_remaining"] ?? window["remaining_percent"] ?? window["percentRemaining"]) {
            return clampPercent(percent)
        }

        if let remaining = OfficialValueParser.double(window["remaining"] ?? window["remaining_quota"] ?? window["remainingQuota"]),
           let total = OfficialValueParser.double(window["entitlement"] ?? window["quota"] ?? window["total"]),
           total > 0 {
            return clampPercent(remaining / total * 100)
        }

        if let quotaKeyHint,
           let percent = percentFromLimitedMonthly(quotaKey: quotaKeyHint, limitedUser: limitedUser, monthly: monthly) {
            return percent
        }

        for key in ["chat", "completions"] {
            if let percent = percentFromLimitedMonthly(quotaKey: key, limitedUser: limitedUser, monthly: monthly) {
                return percent
            }
        }

        return nil
    }

    private static func percentFromLimitedMonthly(
        quotaKey: String,
        limitedUser: [String: Any]?,
        monthly: [String: Any]?
    ) -> Double? {
        guard let remaining = OfficialValueParser.double(limitedUser?[quotaKey]),
              let total = OfficialValueParser.double(monthly?[quotaKey]),
              total > 0 else {
            return nil
        }
        return clampPercent(remaining / total * 100)
    }

    private static func isPlaceholderSnapshot(_ window: [String: Any], remainingPercent: Double) -> Bool {
        let remaining = OfficialValueParser.double(window["remaining"] ?? window["remaining_quota"] ?? window["remainingQuota"])
        let entitlement = OfficialValueParser.double(window["entitlement"] ?? window["quota"] ?? window["total"])
        if let remaining, let entitlement, remaining == 0, entitlement == 0 {
            return true
        }

        if let name = OfficialValueParser.string(window["name"] ?? window["title"]),
           name.lowercased().contains("placeholder") {
            return true
        }

        return !remainingPercent.isFinite
    }

    private static func canonicalSnapshotKind(for key: String) -> String? {
        let normalized = normalizeKey(key)
        if normalized.contains("premium") || normalized.contains("interaction") {
            return "premium"
        }
        if normalized.contains("chat") || normalized.contains("message") {
            return "chat"
        }
        if normalized.contains("completion") || normalized.contains("code") {
            return "completions"
        }
        return nil
    }

    private static func quotaKeyHint(from key: String) -> String? {
        let normalized = normalizeKey(key)
        if normalized.contains("chat") || normalized.contains("message") {
            return "chat"
        }
        if normalized.contains("completion") || normalized.contains("code") {
            return "completions"
        }
        return nil
    }

    private static func quotaTitle(for key: String) -> String {
        if let canonical = canonicalSnapshotKind(for: key) {
            switch canonical {
            case "premium": return "Premium"
            case "chat": return "Chat"
            case "completions": return "Completions"
            default: break
            }
        }
        return humanizedKey(key)
    }

    private static func humanizedKey(_ key: String) -> String {
        let words = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { part -> String in
                let lower = part.lowercased()
                if lower == "d7" || lower == "d30" {
                    return lower.uppercased()
                }
                return lower.capitalized
            }
        let joined = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "Quota" : joined
    }

    private static func windowIdentifier(from key: String) -> String {
        key.lowercased().map { character in
            if character.isLetter || character.isNumber {
                return String(character)
            }
            return "-"
        }.joined()
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .ifEmpty("quota")
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func clampPercent(_ raw: Double) -> Double {
        max(0, min(100, raw))
    }

    private static func parseDateOnly(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
