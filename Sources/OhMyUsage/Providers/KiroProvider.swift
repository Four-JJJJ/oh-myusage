import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class KiroProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor
    private static let stateKey = "kiro.kiroAgent"

    private let shell: any ShellCommandRunning
    private let sqlite: any SQLiteQuerying
    private let localJSONReader: any LocalJSONFileReading

    init(
        descriptor: ProviderDescriptor,
        shell: any ShellCommandRunning = DefaultShellCommandRunner(),
        sqlite: any SQLiteQuerying = DefaultSQLiteShell(),
        localJSONReader: any LocalJSONFileReading = DefaultLocalJSONFileReader()
    ) {
        self.descriptor = descriptor
        self.shell = shell
        self.sqlite = sqlite
        self.localJSONReader = localJSONReader
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .kiro)
        guard official.sourceMode == .auto || official.sourceMode == .cli else {
            throw ProviderError.unavailable("Kiro 官方来源当前仅支持 CLI 或 IDE 本地检测")
        }

        if official.sourceMode == .cli {
            return enrichAccountLabel(snapshot: try loadFromCLI())
        }

        do {
            return enrichAccountLabel(snapshot: try loadFromCLI())
        } catch {
            return try loadFromIDE()
        }
    }

    private func loadFromCLI() throws -> UsageSnapshot {
        guard shell.run(executable: "/usr/bin/env", arguments: ["which", "kiro-cli"], timeout: 5)?.status == 0 else {
            throw ProviderError.unavailable("未检测到 kiro-cli")
        }
        guard let result = shell.run(
            executable: "/usr/bin/env",
            arguments: ["kiro-cli"],
            input: "/usage\n/quit\n",
            timeout: 20,
            environment: nil,
            currentDirectory: nil
        ), result.status == 0 || !result.stdout.isEmpty else {
            throw ProviderError.commandFailed("kiro-cli /usage 执行失败")
        }
        return try Self.parseSnapshot(text: result.stdout, descriptor: descriptor)
    }

    private func loadFromIDE() throws -> UsageSnapshot {
        var sawStateDatabase = false
        var lastReadError: ProviderError?
        for stateDatabasePath in Self.ideStateDatabasePaths() {
            guard FileManager.default.fileExists(atPath: stateDatabasePath) else { continue }
            sawStateDatabase = true

            let result = sqlite.snapshotQuery(
                databasePath: stateDatabasePath,
                query: "SELECT value FROM ItemTable WHERE key = '\(Self.stateKey.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"
            )
            guard result.succeeded else {
                lastReadError = .commandFailed(
                    "Failed to read Kiro state database at \(stateDatabasePath): \(result.errorMessage)"
                )
                continue
            }

            guard let stateRaw = result.singleValue, !stateRaw.isEmpty else {
                continue
            }

            let accountLabel = Self.extractIDEAccountLabel(
                token: localJSONReader.dictionary(atPath: Self.ideTokenPath),
                profile: loadIDEProfile(stateDatabasePath: stateDatabasePath)
            )
            return try Self.parseIDESnapshot(
                stateJSON: stateRaw,
                descriptor: descriptor,
                accountLabel: accountLabel
            )
        }

        if let lastReadError {
            throw lastReadError
        }
        if sawStateDatabase {
            throw ProviderError.missingCredential(Self.stateKey)
        }
        throw ProviderError.missingCredential(Self.defaultIDEStateDatabasePath)
    }

    private func enrichAccountLabel(snapshot: UsageSnapshot) -> UsageSnapshot {
        guard snapshot.accountLabel == nil else { return snapshot }
        guard let accountLabel = Self.extractIDEAccountLabel(
            token: localJSONReader.dictionary(atPath: Self.ideTokenPath),
            profile: loadIDEProfile(stateDatabasePath: nil)
        ) else {
            return snapshot
        }

        var updated = snapshot
        updated.accountLabel = accountLabel
        updated.authSourceLabel = "Kiro IDE"
        updated.rawMeta["kiro.accountLabel"] = accountLabel
        return updated
    }

    internal static func parseSnapshot(text: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let clean = text.replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
        var windows: [UsageQuotaWindow] = []

        let bonus = clean.regexCaptures(pattern: #"Bonus credits:\s*([\d.,]+)/([\d.,]+)"#)
        if bonus.count >= 3,
           let used = parseNumeric(bonus[1]), let total = parseNumeric(bonus[2]), total > 0 {
            let remainingPercent = max(0, (total - used) / total * 100)
            let days = clean.regexCaptures(pattern: #"expires in (\d+) days"#)
            let resetAt = days.count >= 2 ? Date().addingTimeInterval((Double(days[1]) ?? 0) * 24 * 3600) : nil
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-bonus",
                    title: "Bonus",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }

        if let creditsUsage = parseFirstUsagePair(
            in: clean,
            patterns: [
                #"Credits \(([\d.,]+)\s+of\s+([\d.,]+)"#,
                #"Credits\s+([\d.,]+)\s+used\s*/\s*([\d.,]+)(?:\s+(?:covered\s+in\s+plan|credits?))?"#
            ]
        ) {
            let used = creditsUsage.used
            let total = creditsUsage.total
            let remainingPercent = max(0, (total - used) / total * 100)
            var resetAt: Date?
            let reset = clean.regexCaptures(pattern: #"resets on (\d{2}/\d{2})"#)
            if reset.count >= 2 {
                let comps = reset[1].split(separator: "/").compactMap { Int($0) }
                if comps.count == 2 {
                    var parts = Calendar.current.dateComponents([.year], from: Date())
                    parts.month = comps[0]
                    parts.day = comps[1]
                    resetAt = Calendar.current.date(from: parts)
                }
            }
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-credits",
                    title: "Credits",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("No quota data found in Kiro CLI output")
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
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: [:],
            rawMeta: [:]
        )
    }

    internal static func parseIDESnapshot(
        stateJSON: String,
        descriptor: ProviderDescriptor,
        accountLabel: String?
    ) throws -> UsageSnapshot {
        guard let data = stateJSON.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usageState = payload["kiro.resourceNotifications.usageState"] as? [String: Any],
              let usageBreakdowns = usageState["usageBreakdowns"] as? [[String: Any]] else {
            throw ProviderError.invalidResponse("No Kiro IDE usage state found")
        }

        let normalizedBreakdowns = usageBreakdowns.compactMap(normalizeUsageBreakdown)
        guard let primary = pickPrimaryBreakdown(from: normalizedBreakdowns) else {
            throw ProviderError.invalidResponse("No quota data found in Kiro IDE state")
        }

        var windows: [UsageQuotaWindow] = []
        let mainTitle = normalizedWindowTitle(primary.displayName, fallback: "Credits")
        windows.append(
            makeWindow(
                descriptor: descriptor,
                suffix: "credits",
                title: mainTitle,
                currentUsage: primary.currentUsage,
                usageLimit: primary.usageLimit,
                resetAt: primary.resetDate
            )
        )

        if let bonus = pickBonusUsage(from: primary) {
            let bonusTitle = normalizedWindowTitle(bonus.displayName, fallback: "Bonus")
            windows.append(
                makeWindow(
                    descriptor: descriptor,
                    suffix: "bonus",
                    title: bonusTitle,
                    currentUsage: bonus.currentUsage,
                    usageLimit: bonus.usageLimit,
                    resetAt: bonus.expiryDate
                )
            )
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("No quota windows parsed from Kiro IDE state")
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        let updatedAt = parseStateTimestamp(usageState["timestamp"]) ?? Date()
        var rawMeta: [String: String] = [:]
        if let accountLabel {
            rawMeta["kiro.accountLabel"] = accountLabel
        }

        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: updatedAt,
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "IDE",
            accountLabel: accountLabel,
            authSourceLabel: accountLabel == nil ? nil : "Kiro IDE",
            extras: [:],
            rawMeta: rawMeta
        )
    }

    internal static func extractIDEAccountLabel(
        token: [String: Any]?,
        profile: [String: Any]?
    ) -> String? {
        if let token {
            if let directEmail = firstEmail(in: token) {
                return directEmail
            }
            if let jwtEmail = firstJWTEmail(in: token) {
                return jwtEmail
            }
        }
        if let profile, let profileEmail = firstEmail(in: profile) {
            return profileEmail
        }

        // Fallback to non-email but human-readable labels if available.
        if let token, let label = firstReadableLabel(in: token) {
            return label
        }
        if let profile, let label = firstReadableLabel(in: profile) {
            return label
        }
        return nil
    }

    private static func makeWindow(
        descriptor: ProviderDescriptor,
        suffix: String,
        title: String,
        currentUsage: Double,
        usageLimit: Double,
        resetAt: Date?
    ) -> UsageQuotaWindow {
        let remainingPercent = max(0, min(100, (usageLimit - currentUsage) / usageLimit * 100))
        return UsageQuotaWindow(
            id: "\(descriptor.id)-\(suffix)",
            title: title,
            remainingPercent: remainingPercent,
            usedPercent: max(0, 100 - remainingPercent),
            resetAt: resetAt,
            kind: .custom
        )
    }

    private static func normalizeUsageBreakdown(_ raw: [String: Any]) -> KiroUsageBreakdown? {
        guard let currentUsage = firstDouble(in: raw, keys: ["currentUsageWithPrecision", "currentUsage"]),
              let usageLimit = firstDouble(in: raw, keys: ["usageLimitWithPrecision", "usageLimit"]),
              usageLimit > 0 else {
            return nil
        }

        let freeTrialPayload = dictionaryValue(raw["freeTrialInfo"]) ?? dictionaryValue(raw["freeTrialUsage"])
        let freeTrialUsage = normalizeUsagePool(
            freeTrialPayload,
            currentKeys: ["currentUsageWithPrecision", "currentUsage"],
            limitKeys: ["usageLimitWithPrecision", "usageLimit"],
            expiryKeys: ["freeTrialExpiry", "expiryDate"],
            statusKey: "freeTrialStatus",
            allowedStatuses: ["ACTIVE"]
        )

        let bonuses = (raw["bonuses"] as? [[String: Any]] ?? []).compactMap { bonus in
            normalizeUsagePool(
                bonus,
                currentKeys: ["currentUsageWithPrecision", "currentUsage"],
                limitKeys: ["usageLimitWithPrecision", "usageLimit"],
                expiryKeys: ["expiresAt", "expiryDate"],
                statusKey: "status",
                allowedStatuses: ["ACTIVE", "EXHAUSTED"]
            )
        }

        return KiroUsageBreakdown(
            type: OfficialValueParser.string(raw["resourceType"] ?? raw["type"])?.uppercased(),
            displayName: OfficialValueParser.nonPlaceholderString(raw["displayName"]),
            currentUsage: currentUsage,
            usageLimit: usageLimit,
            resetDate: parseISODate(in: raw, keys: ["nextDateReset", "resetDate"]),
            freeTrialUsage: freeTrialUsage,
            bonuses: bonuses
        )
    }

    private static func normalizeUsagePool(
        _ raw: [String: Any]?,
        currentKeys: [String],
        limitKeys: [String],
        expiryKeys: [String],
        statusKey: String? = nil,
        allowedStatuses: Set<String>? = nil
    ) -> KiroUsagePool? {
        guard let raw else { return nil }
        if let statusKey, let allowedStatuses,
           let status = OfficialValueParser.string(raw[statusKey])?.uppercased(),
           !allowedStatuses.contains(status) {
            return nil
        }
        guard let currentUsage = firstDouble(in: raw, keys: currentKeys),
              let usageLimit = firstDouble(in: raw, keys: limitKeys),
              usageLimit > 0 else {
            return nil
        }
        return KiroUsagePool(
            displayName: OfficialValueParser.nonPlaceholderString(raw["displayName"]),
            currentUsage: currentUsage,
            usageLimit: usageLimit,
            expiryDate: parseISODate(in: raw, keys: expiryKeys)
        )
    }

    private static func pickPrimaryBreakdown(from breakdowns: [KiroUsageBreakdown]) -> KiroUsageBreakdown? {
        breakdowns.first(where: { $0.type == "CREDIT" }) ?? breakdowns.first
    }

    private static func pickBonusUsage(from breakdown: KiroUsageBreakdown) -> KiroUsagePool? {
        if let freeTrial = breakdown.freeTrialUsage, freeTrial.usageLimit > 0 {
            return freeTrial
        }
        return breakdown.bonuses.first(where: { $0.usageLimit > 0 })
    }

    private static func parseStateTimestamp(_ value: Any?) -> Date? {
        guard let raw = OfficialValueParser.double(value) else { return nil }
        let seconds = raw > 100_000_000_000 ? raw / 1000 : raw
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseISODate(in dictionary: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let date = OfficialValueParser.isoDate(OfficialValueParser.string(dictionary[key])) {
                return date
            }
        }
        return nil
    }

    private static func firstDouble(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = OfficialValueParser.double(dictionary[key]) {
                return value
            }
        }
        return nil
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func normalizedWindowTitle(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func parseFirstUsagePair(in text: String, patterns: [String]) -> (used: Double, total: Double)? {
        for pattern in patterns {
            let captures = text.regexCaptures(pattern: pattern)
            guard captures.count >= 3,
                  let used = parseNumeric(captures[1]),
                  let total = parseNumeric(captures[2]),
                  total > 0 else {
                continue
            }
            return (used: used, total: total)
        }
        return nil
    }

    private static func parseNumeric(_ raw: String) -> Double? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private static func firstEmail(in dictionary: [String: Any]) -> String? {
        let candidates = stringCandidates(
            in: dictionary,
            keys: [
                "email", "userEmail", "accountEmail", "primaryEmail", "username", "userName",
                "login", "displayName", "name"
            ]
        )
        return candidates.first(where: isLikelyEmail)
    }

    private static func firstJWTEmail(in dictionary: [String: Any]) -> String? {
        for key in ["idToken", "accessToken", "token", "jwt"] {
            guard let token = OfficialValueParser.string(dictionary[key]),
                  token.split(separator: ".").count >= 2,
                  let email = JWTInspector.email(token),
                  isLikelyEmail(email) else {
                continue
            }
            return email
        }
        return nil
    }

    private static func firstReadableLabel(in dictionary: [String: Any]) -> String? {
        let candidates = stringCandidates(
            in: dictionary,
            keys: [
                "displayName", "name", "userName", "username", "accountName",
                "provider", "authMethod", "profileArn", "arn"
            ]
        )
        for candidate in candidates {
            if !candidate.contains("."),
               candidate.count <= 80 {
                return candidate
            }
        }
        return nil
    }

    private static func stringCandidates(in dictionary: [String: Any], keys: [String]) -> [String] {
        keys.compactMap { key in
            OfficialValueParser.nonPlaceholderString(dictionary[key])
        }
    }

    private static func isLikelyEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@"), at > trimmed.startIndex else { return false }
        let dot = trimmed[at...].contains(".")
        return dot
    }

    private func loadIDEProfile(stateDatabasePath: String?) -> [String: Any]? {
        for path in Self.ideProfilePaths(stateDatabasePath: stateDatabasePath) {
            if let profile = localJSONReader.dictionary(atPath: path) {
                return profile
            }
        }
        return nil
    }

    private static var defaultIDEStateDatabasePath: String {
        "\(NSHomeDirectory())/Library/Application Support/Kiro/User/globalStorage/state.vscdb"
    }

    private static var ideTokenPath: String {
        "\(NSHomeDirectory())/.aws/sso/cache/kiro-auth-token.json"
    }

    private static func ideStateDatabasePaths() -> [String] {
        let home = NSHomeDirectory()
        let appSupportPath = "\(home)/Library/Application Support"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: appSupportPath)) ?? []
        return ideStateDatabasePaths(homeDirectory: home, appSupportEntries: entries)
    }

    internal static func ideStateDatabasePaths(homeDirectory: String, appSupportEntries: [String]) -> [String] {
        let base = "\(homeDirectory)/Library/Application Support"
        var candidates = [
            "\(base)/Kiro/User/globalStorage/state.vscdb",
            "\(base)/Kiro - Insiders/User/globalStorage/state.vscdb",
            "\(base)/Kiro Insiders/User/globalStorage/state.vscdb",
            "\(base)/Kiro - Next/User/globalStorage/state.vscdb",
            "\(base)/Kiro Next/User/globalStorage/state.vscdb",
            "\(base)/Kiro - Beta/User/globalStorage/state.vscdb",
            "\(base)/Kiro Beta/User/globalStorage/state.vscdb",
            "\(base)/Kiro - Preview/User/globalStorage/state.vscdb",
            "\(base)/Kiro Preview/User/globalStorage/state.vscdb",
        ]

        let dynamicVariants = appSupportEntries.filter { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.lowercased().hasPrefix("kiro")
        }
        candidates.append(contentsOf: dynamicVariants.map { "\(base)/\($0)/User/globalStorage/state.vscdb" })
        return uniquePaths(candidates)
    }

    private static func ideProfilePaths(stateDatabasePath: String?) -> [String] {
        var globalStorageRoots: [String] = []
        if let stateDatabasePath {
            let stateURL = URL(fileURLWithPath: stateDatabasePath)
            globalStorageRoots.append(stateURL.deletingLastPathComponent().path)
        }
        globalStorageRoots.append(
            contentsOf: ideStateDatabasePaths().map { path in
                URL(fileURLWithPath: path).deletingLastPathComponent().path
            }
        )
        globalStorageRoots = uniquePaths(globalStorageRoots)

        var candidates: [String] = []
        for root in globalStorageRoots {
            candidates.append("\(root)/kiro.kiroagent/profile.json")
            candidates.append("\(root)/kiro.kiroAgent/profile.json")
            candidates.append("\(root)/kiro.kiro-agent/profile.json")
        }
        return uniquePaths(candidates)
    }

    private static func uniquePaths(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

private extension String {
    func regexCaptures(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return [] }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}

private struct KiroUsageBreakdown {
    var type: String?
    var displayName: String?
    var currentUsage: Double
    var usageLimit: Double
    var resetDate: Date?
    var freeTrialUsage: KiroUsagePool?
    var bonuses: [KiroUsagePool]
}

private struct KiroUsagePool {
    var displayName: String?
    var currentUsage: Double
    var usageLimit: Double
    var expiryDate: Date?
}
