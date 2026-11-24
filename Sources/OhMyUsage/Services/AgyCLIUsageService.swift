import Foundation
import OhMyUsageDomain
import OhMyUsageProviders

struct AgyCLIQuotaBucket: Equatable, Sendable {
    enum Family: String, Equatable, Sendable {
        case gemini
        case claudeGPT
        case other
    }

    enum Cadence: String, Equatable, Sendable {
        case fiveHour
        case weekly
        case other
    }

    var id: String
    var family: Family
    var cadence: Cadence
    var groupName: String
    var bucketName: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetAt: Date?
    var sortOrder: Int
}

struct AgyCLIUsageReport: Equatable, Sendable {
    var buckets: [AgyCLIQuotaBucket]
    var planType: String?
    var accountLabel: String?
    var executableSource: String
    var outputFormat: String
    var fetchedAt: Date
}

actor AgyCLIUsageCoordinator {
    static let shared = AgyCLIUsageCoordinator()

    private struct CacheEntry {
        let report: AgyCLIUsageReport
        let storedAt: Date
    }

    private var cachedEntries: [String: CacheEntry] = [:]
    private var inFlightTasks: [String: Task<AgyCLIUsageReport, Error>] = [:]
    private let normalCacheTTL: TimeInterval = 45
    private let burstDeduplicationTTL: TimeInterval = 5

    func fetchReport(
        executablePath: String,
        forceRefresh: Bool,
        environment: [String: String],
        homeDirectory: String,
        shell: any ShellCommandRunning
    ) async throws -> AgyCLIUsageReport {
        let now = Date()
        if let cached = cachedEntries[executablePath] {
            let age = now.timeIntervalSince(cached.storedAt)
            if (!forceRefresh && age < normalCacheTTL) || (forceRefresh && age < burstDeduplicationTTL) {
                return cached.report
            }
        }

        if let existing = inFlightTasks[executablePath] {
            return try await existing.value
        }

        let task = Task.detached(priority: .userInitiated) {
            try AgyCLIUsageService.executeUsageCommand(
                executablePath: executablePath,
                environment: environment,
                homeDirectory: homeDirectory,
                shell: shell
            )
        }
        inFlightTasks[executablePath] = task

        do {
            let report = try await task.value
            inFlightTasks.removeValue(forKey: executablePath)
            cachedEntries[executablePath] = CacheEntry(report: report, storedAt: Date())
            return report
        } catch {
            inFlightTasks.removeValue(forKey: executablePath)
            throw error
        }
    }
}

enum AgyCLIUsageService {
    static func resolveExecutablePath(
        environment: [String: String],
        homeDirectory: String,
        shell: any ShellCommandRunning,
        fileManager: FileManager = .default
    ) -> String? {
        if let explicit = environment["ANTIGRAVITY_CLI_PATH"] {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let expanded = (trimmed as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded) ? expanded : nil
        }

        // Keep sandboxed/unit-test homeDirectory runs isolated from host-wide `/Applications` binaries.
        if homeDirectory != NSHomeDirectory() {
            let testCandidates = [
                "\(homeDirectory)/.local/bin/agy",
                "\(homeDirectory)/Applications/Gemini.app/Contents/Helpers/agy",
                "\(homeDirectory)/Applications/Antigravity.app/Contents/Helpers/agy",
            ]
            return testCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
        }

        var candidates: [String] = []
        if let pathValue = environment["PATH"] {
            for entry in pathValue.split(separator: ":") where !entry.isEmpty {
                candidates.append("\(entry)/agy")
            }
        }
        if let brewPrefix = environment["HOMEBREW_PREFIX"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !brewPrefix.isEmpty {
            candidates.append("\(brewPrefix)/bin/agy")
        }

        candidates.append(contentsOf: [
            "\(homeDirectory)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/Applications/Gemini.app/Contents/Helpers/agy",
            "\(homeDirectory)/Applications/Gemini.app/Contents/Helpers/agy",
            "/Applications/Antigravity.app/Contents/Helpers/agy",
            "\(homeDirectory)/Applications/Antigravity.app/Contents/Helpers/agy",
            "/Applications/Antigravity.app/Contents/Resources/app/bin/agy",
            "\(homeDirectory)/Applications/Antigravity.app/Contents/Resources/app/bin/agy",
        ])

        var seen: Set<String> = []
        for candidate in candidates where seen.insert(candidate).inserted {
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        if let discovered = shell.run(executable: "/usr/bin/which", arguments: ["agy"], timeout: 3)?
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines),
           !discovered.isEmpty,
           fileManager.isExecutableFile(atPath: discovered) {
            return discovered
        }

        return nil
    }

    static func executableSourceLabel(for executablePath: String) -> String {
        if executablePath.contains("/Gemini.app/") {
            return "Gemini.app"
        }
        if executablePath.contains("/Antigravity.app/") {
            return "Antigravity.app"
        }
        return "CLI"
    }

    static func executeUsageCommand(
        executablePath: String,
        environment: [String: String],
        homeDirectory: String,
        shell: any ShellCommandRunning
    ) throws -> AgyCLIUsageReport {
        let probeDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("omu-agy-probe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: probeDir) }

        var childEnv = environment
        // Documented official flag: literal lowercase "true" suppresses passive CLI auto-updates.
        childEnv["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
        // Prevent unauthenticated probes from launching a browser sign-in window.
        childEnv["BROWSER"] = "/usr/bin/false"

        guard let result = shell.run(
            executable: executablePath,
            arguments: ["-p", "/usage", "--output-format", "json"],
            input: nil,
            timeout: 30,
            environment: childEnv,
            currentDirectory: probeDir.path
        ) else {
            throw ProviderError.timeout(Localizer.systemText(.agyCLITimeout))
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.status != 0 && stdout.isEmpty {
            if containsAuthPrompt(stderr) {
                throw ProviderError.unauthorizedDetail(Localizer.systemText(.agyCLINotSignedIn))
            }
            throw ProviderError.unavailable(Localizer.agyExitFailureBody(status: result.status))
        }

        let fallbackAccount = readDesktopLastLoginUsername(homeDirectory: homeDirectory)
        return try parseUsageOutput(
            stdout: stdout,
            stderr: stderr,
            executableSource: executableSourceLabel(for: executablePath),
            fallbackAccountLabel: fallbackAccount
        )
    }

    static func parseUsageOutput(
        stdout: String,
        stderr: String = "",
        executableSource: String = "CLI",
        fallbackAccountLabel: String? = nil
    ) throws -> AgyCLIUsageReport {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if containsAuthPrompt(stderr) {
                throw ProviderError.unauthorizedDetail(Localizer.systemText(.agyCLINotSignedIn))
            }
            throw ProviderError.invalidResponse("empty agy /usage output")
        }

        if let data = trimmed.data(using: .utf8),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let status = OfficialValueParser.string(root["status"])?.uppercased(),
               status == "ERROR" {
                let errorMsg = OfficialValueParser.string(root["error"]) ?? ""
                if containsAuthPrompt(errorMsg) || containsAuthPrompt(stderr) {
                    throw ProviderError.unauthorizedDetail(Localizer.systemText(.agyCLINotSignedIn))
                }
                throw ProviderError.unavailable(
                    errorMsg.isEmpty ? Localizer.systemText(.agyCLIErrorStatus) : errorMsg
                )
            }

            // 1. Primary path: `command.data.groups` (actual `agy` 1.5+ schema) or `response.groups` / `groups`.
            if let structured = parseStructuredJSON(
                root: root,
                executableSource: executableSource,
                fallbackAccountLabel: fallbackAccountLabel
            ) {
                return structured
            }

            // 2. Envelope where `response` carries nested JSON or TSV lines.
            if let responseString = OfficialValueParser.string(root["response"]) {
                if let nestedData = responseString.data(using: .utf8),
                   let nestedJSON = (try? JSONSerialization.jsonObject(with: nestedData)) as? [String: Any],
                   let structured = parseStructuredJSON(
                    root: nestedJSON,
                    executableSource: executableSource,
                    fallbackAccountLabel: fallbackAccountLabel
                   ) {
                    return structured
                }
                if let textReport = parseTextReport(
                    responseString,
                    executableSource: executableSource,
                    fallbackAccountLabel: fallbackAccountLabel
                ) {
                    return textReport
                }
            }
        }

        if let textReport = parseTextReport(
            trimmed,
            executableSource: executableSource,
            fallbackAccountLabel: fallbackAccountLabel
        ) {
            return textReport
        }

        if containsAuthPrompt(trimmed) || containsAuthPrompt(stderr) {
            throw ProviderError.unauthorizedDetail(Localizer.systemText(.agyCLINotSignedIn))
        }

        throw ProviderError.invalidResponse("unable to parse agy /usage output")
    }

    private static func parseStructuredJSON(
        root: [String: Any],
        executableSource: String,
        fallbackAccountLabel: String?
    ) -> AgyCLIUsageReport? {
        let commandObj = root["command"] as? [String: Any]
        let commandDataObj = commandObj?["data"] as? [String: Any]
        let responseObj = root["response"] as? [String: Any]

        let rawGroups = (commandDataObj?["groups"] as? [Any])
            ?? (responseObj?["groups"] as? [Any])
            ?? (root["groups"] as? [Any])
            ?? []
        let groups = rawGroups.compactMap { $0 as? [String: Any] }
        guard !groups.isEmpty else { return nil }

        var buckets: [AgyCLIQuotaBucket] = []

        for group in groups {
            let groupName = OfficialValueParser.string(group["name"] ?? group["displayName"]) ?? "Quota"
            let rawBuckets = (group["buckets"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            for bucket in rawBuckets {
                let bucketID = OfficialValueParser.string(bucket["id"] ?? bucket["bucketId"]) ?? UUID().uuidString
                let bucketName = OfficialValueParser.string(bucket["name"] ?? bucket["displayName"]) ?? ""
                let windowHint = OfficialValueParser.string(bucket["window"]) ?? ""
                let remainingObj = bucket["remaining"] as? [String: Any]

                let rawRemainingFraction = OfficialValueParser.double(
                    bucket["remaining_fraction"]
                        ?? bucket["remainingFraction"]
                        ?? remainingObj?["remainingFraction"]
                        ?? remainingObj?["remaining_fraction"]
                )
                let rawUsedPercent = OfficialValueParser.double(
                    bucket["used_percent"]
                        ?? bucket["usedPercent"]
                        ?? bucket["percentageUsed"]
                        ?? bucket["percentage_used"]
                )

                let remainingPercent: Double
                let usedPercent: Double
                if let rawRemainingFraction, rawRemainingFraction.isFinite {
                    let pct = rawRemainingFraction <= 1.0 ? rawRemainingFraction * 100 : rawRemainingFraction
                    remainingPercent = min(100, max(0, pct))
                    usedPercent = max(0, 100 - remainingPercent)
                } else if let rawUsedPercent, rawUsedPercent.isFinite {
                    let pct = rawUsedPercent <= 1.0 ? rawUsedPercent * 100 : rawUsedPercent
                    usedPercent = min(100, max(0, pct))
                    remainingPercent = max(0, 100 - usedPercent)
                } else {
                    continue
                }

                let rawReset = OfficialValueParser.string(
                    bucket["reset_time"]
                        ?? bucket["resetTime"]
                        ?? bucket["resetsAt"]
                        ?? bucket["resetAt"]
                        ?? remainingObj?["reset_time"]
                        ?? remainingObj?["resetTime"]
                )
                let resetAt = rawReset.flatMap(parseDate(_:))

                let family = classifyFamily(groupName: groupName, bucketID: bucketID, bucketName: bucketName)
                let cadence = classifyCadence(windowHint: windowHint, bucketID: bucketID, bucketName: bucketName)
                let order = sortOrder(family: family, cadence: cadence)

                buckets.append(
                    AgyCLIQuotaBucket(
                        id: bucketID,
                        family: family,
                        cadence: cadence,
                        groupName: groupName,
                        bucketName: bucketName,
                        remainingPercent: remainingPercent,
                        usedPercent: usedPercent,
                        resetAt: resetAt,
                        sortOrder: order
                    )
                )
            }
        }

        guard !buckets.isEmpty else { return nil }
        buckets.sort {
            $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
        }

        let plan = OfficialValueParser.firstPlanLabel([
            commandDataObj?["plan"],
            commandDataObj?["plan_tier"],
            commandDataObj?["subscriptionTier"],
            responseObj?["plan"],
            responseObj?["plan_tier"],
            responseObj?["subscriptionTier"],
            root["plan"],
            root["plan_tier"],
        ])
        let email = OfficialValueParser.string(
            commandDataObj?["email"]
                ?? responseObj?["email"]
                ?? root["email"]
        ) ?? fallbackAccountLabel

        return AgyCLIUsageReport(
            buckets: buckets,
            planType: plan,
            accountLabel: email,
            executableSource: executableSource,
            outputFormat: "agy-cli-json",
            fetchedAt: Date()
        )
    }

    private static func parseTextReport(
        _ text: String,
        executableSource: String,
        fallbackAccountLabel: String?
    ) -> AgyCLIUsageReport? {
        var buckets: [AgyCLIQuotaBucket] = []

        // First try 3-or-4-column TSV emitted in `response`:
        // `Gemini Models\tWeekly Limit Remaining\t97%\t2026-12-01T01:22:05Z`
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let columns = line.components(separatedBy: "\t").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if columns.count >= 3,
               let percentValue = parsePercentString(columns[2]) {
                let groupName = columns[0]
                let bucketName = columns[1]
                let lowerBucket = bucketName.lowercased()
                let isUsed = lowerBucket.contains("used") && !lowerBucket.contains("remaining")
                let clamped = min(100, max(0, percentValue))
                let remaining = isUsed ? (100 - clamped) : clamped
                let resetAt = columns.count >= 4 ? parseDate(columns[3]) : nil
                let family = classifyFamily(groupName: groupName, bucketID: "", bucketName: bucketName)
                let cadence = classifyCadence(windowHint: "", bucketID: "", bucketName: bucketName)

                buckets.append(
                    AgyCLIQuotaBucket(
                        id: "tsv-\(index)",
                        family: family,
                        cadence: cadence,
                        groupName: groupName,
                        bucketName: bucketName,
                        remainingPercent: remaining,
                        usedPercent: 100 - remaining,
                        resetAt: resetAt,
                        sortOrder: sortOrder(family: family, cadence: cadence)
                    )
                )
            }
        }

        if buckets.isEmpty,
           let regex = try? NSRegularExpression(
            pattern: #"(?im)^\s*([A-Za-z0-9 +._/-]{2,48}?)[\s:|—–-]+([0-9]+(?:\.[0-9]+)?)\s*%\s*(remaining|left|used)?"#
           ) {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, range: nsRange)
            for (index, match) in matches.enumerated() where match.numberOfRanges >= 3 {
                guard let labelRange = Range(match.range(at: 1), in: text),
                      let numRange = Range(match.range(at: 2), in: text),
                      let rawValue = Double(text[numRange]) else {
                    continue
                }
                let rawLabel = String(text[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let qualifier: String
                if match.numberOfRanges >= 4, let qRange = Range(match.range(at: 3), in: text) {
                    qualifier = String(text[qRange]).lowercased()
                } else {
                    qualifier = rawLabel.lowercased().contains("used") ? "used" : "remaining"
                }
                let clamped = min(100, max(0, rawValue))
                let remaining = qualifier == "used" ? (100 - clamped) : clamped
                let family = classifyFamily(groupName: rawLabel, bucketID: "", bucketName: rawLabel)
                let cadence = classifyCadence(windowHint: "", bucketID: "", bucketName: rawLabel)

                buckets.append(
                    AgyCLIQuotaBucket(
                        id: "text-\(index)",
                        family: family,
                        cadence: cadence,
                        groupName: rawLabel,
                        bucketName: rawLabel,
                        remainingPercent: remaining,
                        usedPercent: 100 - remaining,
                        resetAt: nil,
                        sortOrder: sortOrder(family: family, cadence: cadence)
                    )
                )
            }
        }

        guard !buckets.isEmpty else { return nil }
        buckets.sort {
            $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
        }

        return AgyCLIUsageReport(
            buckets: buckets,
            planType: nil,
            accountLabel: fallbackAccountLabel,
            executableSource: executableSource,
            outputFormat: "agy-cli-text",
            fetchedAt: Date()
        )
    }

    private static func classifyFamily(
        groupName: String,
        bucketID: String,
        bucketName: String
    ) -> AgyCLIQuotaBucket.Family {
        let lower = "\(groupName) \(bucketID) \(bucketName)".lowercased()
        if lower.contains("gemini") {
            return .gemini
        }
        if lower.contains("claude") || lower.contains("gpt") || lower.hasPrefix("3p") || lower.contains(" 3p-") {
            return .claudeGPT
        }
        return .other
    }

    private static func classifyCadence(
        windowHint: String,
        bucketID: String,
        bucketName: String
    ) -> AgyCLIQuotaBucket.Cadence {
        let hint = windowHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hint == "5h" || hint == "five_hour" || hint == "session" {
            return .fiveHour
        }
        if hint == "weekly" || hint == "7d" || hint == "week" {
            return .weekly
        }

        let lower = "\(bucketID) \(bucketName)".lowercased()
        if lower.contains("5h") || lower.contains("5-hour") || lower.contains("five hour") || lower.contains("five-hour") || lower.contains("session") {
            return .fiveHour
        }
        if lower.contains("week") || lower.contains("7d") {
            return .weekly
        }
        return .other
    }

    private static func sortOrder(
        family: AgyCLIQuotaBucket.Family,
        cadence: AgyCLIQuotaBucket.Cadence
    ) -> Int {
        let familyBase: Int
        switch family {
        case .gemini:
            familyBase = 0
        case .claudeGPT:
            familyBase = 10
        case .other:
            familyBase = 20
        }

        let cadenceOffset: Int
        switch cadence {
        case .fiveHour:
            cadenceOffset = 0
        case .weekly:
            cadenceOffset = 1
        case .other:
            cadenceOffset = 2
        }

        return familyBase + cadenceOffset
    }

    private static func parsePercentString(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = OfficialValueParser.isoDate(trimmed) ?? OfficialValueParser.epochDate(seconds: trimmed) {
            return parsed
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: trimmed) {
            return parsed
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
    }

    private static func readDesktopLastLoginUsername(homeDirectory: String) -> String? {
        let path = "\(homeDirectory)/Library/Application Support/Antigravity/app_storage.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let username = OfficialValueParser.nonPlaceholderString(json["agy.onboarding.lastLoginUsername"]) else {
            return nil
        }
        return username
    }

    static func containsAuthPrompt(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("authentication required")
            || lower.contains("sign in")
            || lower.contains("not logged in")
            || lower.contains("login required")
            || lower.contains("unauthorized")
    }

    static func isRunningUnderXCTest(_ env: [String: String]) -> Bool {
        env["XCTestConfigurationFilePath"] != nil
            || env["XCTest_SESSION_IDENTIFIER"] != nil
            || ProcessInfo.processInfo.processName.lowercased().contains("xctest")
            || Bundle.main.bundlePath.lowercased().contains(".xctest")
    }
}
