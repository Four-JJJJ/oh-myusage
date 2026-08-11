import OhMyUsageDomain
import Foundation
import OhMyUsageProviders

final class OpenCodeGoProvider: UsageProvider, @unchecked Sendable {
    internal struct LocalUsageRow: Equatable {
        let createdMs: Double
        let cost: Double
    }

    private struct RemoteConfig {
        let workspaceID: String
        let endpointID: String
        let cookieHeader: String
    }

    private struct RemoteUsageMetric {
        let status: String
        let resetInSec: Double
        let usagePercent: Double
    }

    private enum RemoteWindowKey: String, CaseIterable {
        case rollingUsage
        case weeklyUsage
        case monthlyUsage

        var title: String {
            switch self {
            case .rollingUsage:
                return "Session"
            case .weeklyUsage:
                return "Weekly"
            case .monthlyUsage:
                return "Monthly"
            }
        }

        var suffix: String {
            switch self {
            case .rollingUsage:
                return "session"
            case .weeklyUsage:
                return "weekly"
            case .monthlyUsage:
                return "monthly"
            }
        }

        var kind: UsageQuotaKind {
            switch self {
            case .rollingUsage:
                return .session
            case .weeklyUsage:
                return .weekly
            case .monthlyUsage:
                return .custom
            }
        }
    }

    internal static let defaultEndpointID = "c7389bd0e731f80f49593e5ee53835475f4e28594dd6bd83eb229bab753498cd"

    private static let remotePath = "/_server"
    private static let remoteInstanceID = "server-fn:11"
    private static let remoteHashEnv = "OPENCODE_USAGE_ENDPOINT_ID"
    private static let localDatabaseDefaultPath = "\(NSHomeDirectory())/.local/share/opencode/opencode.db"

    private static let sessionWindowSec: TimeInterval = 5 * 60 * 60
    private static let weeklyWindowSec: TimeInterval = 7 * 24 * 60 * 60
    private static let monthlyDisplayWindowSec: TimeInterval = 30 * 24 * 60 * 60

    private static let sessionLimitUSD = 12.0
    private static let weeklyLimitUSD = 30.0
    private static let monthlyLimitUSD = 60.0

    private static let localHistoryRowsSQL = """
    SELECT
      CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs,
      CAST(json_extract(data, '$.cost') AS REAL) AS cost
    FROM message
    WHERE json_valid(data)
      AND json_extract(data, '$.providerID') = 'opencode-go'
      AND json_extract(data, '$.role') = 'assistant'
      AND json_type(data, '$.cost') IN ('integer', 'real');
    """

    private static let remoteUsageRegex = try! NSRegularExpression(
        pattern: #"(rollingUsage|weeklyUsage|monthlyUsage):\$R\[\d+\]=\{status:"([^"]+)",resetInSec:(\d+(?:\.\d+)?),usagePercent:(\d+(?:\.\d+)?)\}"#,
        options: []
    )

    private let session: URLSession
    private let keychain: any TokenCredentialStoring
    private let browserCookieService: any BrowserCookieDetecting
    private let localDatabasePath: String
    private let nowProvider: @Sendable () -> Date
    private let environment: [String: String]
    private let localRowsProvider: (@Sendable () -> [LocalUsageRow]?)?
    private let sqlite: any SQLiteQuerying

    let descriptor: ProviderDescriptor

    init(
        descriptor: ProviderDescriptor,
        session: URLSession = .shared,
        keychain: any TokenCredentialStoring,
        browserCookieService: any BrowserCookieDetecting,
        localDatabasePath: String = OpenCodeGoProvider.localDatabaseDefaultPath,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        environment: [String: String] = ProcessInfo.processInfo.environment,
        localRowsProvider: (@Sendable () -> [LocalUsageRow]?)? = nil,
        sqlite: any SQLiteQuerying = DefaultSQLiteShell()
    ) {
        self.descriptor = descriptor
        self.session = session
        self.keychain = keychain
        self.browserCookieService = browserCookieService
        self.localDatabasePath = localDatabasePath
        self.nowProvider = nowProvider
        self.environment = environment
        self.localRowsProvider = localRowsProvider
        self.sqlite = sqlite
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .opencodeGo)
        guard official.sourceMode == .auto || official.sourceMode == .web else {
            throw ProviderError.unavailable("OpenCode Go 官方来源当前仅支持 Web 检测")
        }

        let workspaceID = resolveWorkspaceID()
        let storedCookie = readStoredManualCookie(official: official)
        let localRows = loadLocalRows()
        let hasLocalHistory = !localRows.isEmpty

        let isDetected = Self.isDetected(
            workspaceID: workspaceID,
            cookieHeader: storedCookie,
            hasLocalHistory: hasLocalHistory
        )

        var remoteConfig: RemoteConfig?
        var remotePreparationError: Error?
        if official.webMode != .disabled {
            do {
                remoteConfig = try resolveRemoteConfig(
                    official: official,
                    workspaceID: workspaceID,
                    storedCookie: storedCookie,
                    forceRefresh: forceRefresh
                )
            } catch {
                remotePreparationError = error
            }
        }

        if let remoteConfig {
            do {
                return try await fetchRemoteSnapshot(config: remoteConfig)
            } catch {
                guard hasLocalHistory else { throw error }
                var local = try Self.makeLocalSnapshot(
                    rows: localRows,
                    descriptor: descriptor,
                    now: nowProvider(),
                    sourceLabel: "Local Fallback"
                )
                local.valueFreshness = .cachedFallback
                local.extras["truthSource"] = "local-fallback"
                local.extras["fallbackReason"] = Self.fallbackReason(for: error)
                return local
            }
        }

        if hasLocalHistory {
            return try Self.makeLocalSnapshot(
                rows: localRows,
                descriptor: descriptor,
                now: nowProvider(),
                sourceLabel: "Local"
            )
        }

        if !isDetected {
            throw ProviderError.unavailable("OpenCode Go not detected. Configure Workspace ID/Cookie or use OpenCode Go locally first.")
        }

        if let remotePreparationError {
            throw remotePreparationError
        }

        throw ProviderError.unavailable("OpenCode Go usage is unavailable")
    }

    private func resolveRemoteConfig(
        official: OfficialProviderConfig,
        workspaceID: String?,
        storedCookie: String?,
        forceRefresh: Bool
    ) throws -> RemoteConfig {
        guard let workspaceID = Self.normalizedText(workspaceID) else {
            throw ProviderError.missingCredential(descriptor.auth.keychainAccount ?? "official/opencode-go/workspace-id")
        }

        let cookieHeader = try resolveAuthCookieHeader(
            official: official,
            storedCookie: storedCookie,
            forceRefresh: forceRefresh
        )
        return RemoteConfig(
            workspaceID: workspaceID,
            endpointID: resolveEndpointID(),
            cookieHeader: cookieHeader
        )
    }

    private func fetchRemoteSnapshot(config: RemoteConfig) async throws -> UsageSnapshot {
        guard let url = try usageURL(config: config) else {
            throw ProviderError.invalidResponse("invalid OpenCode Go usage URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(config.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(config.endpointID, forHTTPHeaderField: "x-server-id")
        request.setValue(Self.remoteInstanceID, forHTTPHeaderField: "x-server-instance")
        request.setValue("OhMyUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("OpenCode Go non-http response")
        }

        switch http.statusCode {
        case 302, 303, 401, 403:
            throw ProviderError.unauthorized
        case 429:
            throw ProviderError.rateLimited
        default:
            break
        }

        guard (200...299).contains(http.statusCode) else {
            throw ProviderError.invalidResponse("OpenCode Go http \(http.statusCode)")
        }

        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            throw ProviderError.invalidResponse("empty OpenCode Go usage response")
        }

        var snapshot = try Self.parseRemoteSnapshot(
            body: body,
            descriptor: descriptor,
            now: nowProvider()
        )
        snapshot.extras["truthSource"] = "remote"
        snapshot.rawMeta["opencode.workspaceID"] = config.workspaceID
        snapshot.rawMeta["opencode.endpointID"] = config.endpointID
        return snapshot
    }

    private func usageURL(config: RemoteConfig) throws -> URL? {
        var base = descriptor.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = "https://opencode.ai"
        }
        if !base.contains("://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }

        guard var components = URLComponents(string: base + Self.remotePath) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: config.endpointID),
            URLQueryItem(name: "args", value: try Self.remoteArgs(workspaceID: config.workspaceID))
        ]
        return components.url
    }

    private static func remoteArgs(workspaceID: String) throws -> String {
        let payload: [String: Any] = [
            "t": [
                "t": 9,
                "i": 0,
                "l": 1,
                "a": [
                    [
                        "t": 1,
                        "s": workspaceID
                    ]
                ],
                "o": 0
            ],
            "f": 31,
            "m": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw ProviderError.invalidResponse("failed to build OpenCode Go args")
        }
        return text
    }

    private func resolveEndpointID() -> String {
        if let override = Self.normalizedText(environment[Self.remoteHashEnv]) {
            return override
        }
        return Self.defaultEndpointID
    }

    private func resolveWorkspaceID() -> String? {
        guard let service = descriptor.auth.keychainService,
              let account = descriptor.auth.keychainAccount else {
            return nil
        }
        return Self.normalizedText(keychain.readToken(service: service, account: account))
    }

    private func readStoredManualCookie(official: OfficialProviderConfig) -> String? {
        guard let account = official.manualCookieAccount else { return nil }
        return keychain.readToken(service: TokenCredentialStoreServiceNames.defaultServiceName, account: account)
    }

    private func resolveAuthCookieHeader(
        official: OfficialProviderConfig,
        storedCookie: String?,
        forceRefresh: Bool
    ) throws -> String {
        if let rawManual = storedCookie,
           let manualHeader = Self.normalizedAuthCookieHeader(rawManual) {
            return manualHeader
        }

        let missingKey = official.manualCookieAccount ?? "official/opencode-go/auth-cookie"
        switch official.webMode {
        case .disabled:
            throw ProviderError.missingCredential(missingKey)
        case .manual:
            throw ProviderError.missingCredential(missingKey)
        case .autoImport:
            break
        }

        guard forceRefresh else {
            throw ProviderError.missingCredential("opencode.ai auth cookie")
        }

        if let named = browserCookieService.detectNamedCookie(
            name: "auth",
            hostContains: "opencode.ai",
            order: nil,
            accessIntent: .interactiveImport
        ),
           let header = Self.normalizedAuthCookieHeader(named.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(header, service: TokenCredentialStoreServiceNames.defaultServiceName, account: account)
            }
            return header
        }

        if let detected = browserCookieService.detectCookieHeader(
            hostContains: "opencode.ai",
            order: nil,
            accessIntent: .interactiveImport
        ),
           let header = Self.normalizedAuthCookieHeader(detected.header) {
            if let account = official.manualCookieAccount {
                _ = keychain.saveToken(header, service: TokenCredentialStoreServiceNames.defaultServiceName, account: account)
            }
            return header
        }

        throw ProviderError.missingCredential("opencode.ai auth cookie")
    }

    private func loadLocalRows() -> [LocalUsageRow] {
        if let localRowsProvider {
            return localRowsProvider() ?? []
        }
        guard FileManager.default.fileExists(atPath: localDatabasePath) else {
            return []
        }

        let rawRows = sqlite.rows(databasePath: localDatabasePath, query: Self.localHistoryRowsSQL)
        var rows: [LocalUsageRow] = []
        rows.reserveCapacity(rawRows.count)

        for raw in rawRows {
            guard raw.count >= 2 else { continue }
            guard let createdMs = Double(raw[0]), createdMs > 0 else { continue }
            guard let cost = Double(raw[1]), cost >= 0 else { continue }
            rows.append(LocalUsageRow(createdMs: createdMs, cost: cost))
        }
        return rows
    }

    internal static func isDetected(workspaceID: String?, cookieHeader: String?, hasLocalHistory: Bool) -> Bool {
        let hasWorkspace = normalizedText(workspaceID) != nil
        let hasCookie = normalizedAuthCookieHeader(cookieHeader) != nil
        return hasLocalHistory || hasWorkspace || hasCookie
    }

    internal static func parseRemoteSnapshot(
        body: String,
        descriptor: ProviderDescriptor,
        now: Date
    ) throws -> UsageSnapshot {
        if body.localizedCaseInsensitiveContains("not associated with a workspace") {
            throw ProviderError.invalidResponse("OpenCode Go workspace is not associated with current account")
        }

        let parsed = parseRemoteUsageMetrics(body)
        guard RemoteWindowKey.allCases.allSatisfy({ parsed[$0] != nil }) else {
            throw ProviderError.invalidResponse("missing OpenCode Go usage windows")
        }

        var windows: [UsageQuotaWindow] = []
        var extras: [String: String] = [:]
        for key in RemoteWindowKey.allCases {
            guard let metric = parsed[key] else { continue }
            let usedPercent = clampPercent(metric.usagePercent)
            let remainingPercent = max(0, min(100, 100 - usedPercent))
            let resetAt = now.addingTimeInterval(max(0, metric.resetInSec))
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-\(key.suffix)",
                    title: key.title,
                    remainingPercent: remainingPercent,
                    usedPercent: usedPercent,
                    resetAt: resetAt,
                    kind: key.kind
                )
            )
            extras["opencode.remote.status.\(key.suffix)"] = metric.status
        }

        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "Remote",
            accountLabel: nil,
            extras: extras,
            rawMeta: [:]
        )
    }

    internal static func makeLocalSnapshot(
        rows: [LocalUsageRow],
        descriptor: ProviderDescriptor,
        now: Date,
        sourceLabel: String
    ) throws -> UsageSnapshot {
        guard !rows.isEmpty else {
            throw ProviderError.unavailable("OpenCode Go local history is unavailable")
        }

        let windows = buildLocalWindows(rows: rows, descriptorID: descriptor.id, now: now)
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: now,
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: sourceLabel,
            accountLabel: nil,
            extras: [
                "truthSource": sourceLabel == "Local" ? "local" : "local-fallback"
            ],
            rawMeta: [:]
        )
    }

    internal static func buildLocalWindows(
        rows: [LocalUsageRow],
        descriptorID: String,
        now: Date
    ) -> [UsageQuotaWindow] {
        let nowMs = now.timeIntervalSince1970 * 1000
        let sessionStartMs = nowMs - sessionWindowSec * 1000

        let utc = utcCalendar()
        let weeklyStart = startOfUTCWeek(now: now, calendar: utc)
        let weeklyEnd = weeklyStart.addingTimeInterval(weeklyWindowSec)
        let weeklyStartMs = weeklyStart.timeIntervalSince1970 * 1000
        let weeklyEndMs = weeklyEnd.timeIntervalSince1970 * 1000

        var aggregation = LocalWindowAggregation()
        for row in rows {
            aggregation.record(
                row: row,
                sessionStartMs: sessionStartMs,
                nowMs: nowMs,
                weeklyStartMs: weeklyStartMs,
                weeklyEndMs: weeklyEndMs
            )
        }

        let monthBounds = anchoredMonthBounds(now: now, anchorMs: aggregation.earliestMs, calendar: utc)
        let monthStartMs = monthBounds.start.timeIntervalSince1970 * 1000
        let monthEndMs = monthBounds.end.timeIntervalSince1970 * 1000
        var monthlyCost = 0.0
        for row in rows where row.createdMs >= monthStartMs && row.createdMs < monthEndMs {
            monthlyCost += row.cost
        }

        let sessionUsedPercent = percent(used: aggregation.sessionCost, limit: sessionLimitUSD)
        let weeklyUsedPercent = percent(used: aggregation.weeklyCost, limit: weeklyLimitUSD)
        let monthlyUsedPercent = percent(used: monthlyCost, limit: monthlyLimitUSD)
        let sessionResetMs = (aggregation.oldestRollingMs ?? nowMs) + sessionWindowSec * 1000

        return [
            UsageQuotaWindow(
                id: "\(descriptorID)-session",
                title: "Session",
                remainingPercent: max(0, min(100, 100 - sessionUsedPercent)),
                usedPercent: sessionUsedPercent,
                resetAt: Date(timeIntervalSince1970: sessionResetMs / 1000),
                kind: .session
            ),
            UsageQuotaWindow(
                id: "\(descriptorID)-weekly",
                title: "Weekly",
                remainingPercent: max(0, min(100, 100 - weeklyUsedPercent)),
                usedPercent: weeklyUsedPercent,
                resetAt: weeklyEnd,
                kind: .weekly
            ),
            UsageQuotaWindow(
                id: "\(descriptorID)-monthly",
                title: "Monthly",
                remainingPercent: max(0, min(100, 100 - monthlyUsedPercent)),
                usedPercent: monthlyUsedPercent,
                resetAt: monthBounds.end,
                kind: .custom
            )
        ]
    }

    private struct LocalWindowAggregation {
        var earliestMs: Double?
        var oldestRollingMs: Double?
        var sessionCost = 0.0
        var weeklyCost = 0.0

        mutating func record(
            row: LocalUsageRow,
            sessionStartMs: Double,
            nowMs: Double,
            weeklyStartMs: Double,
            weeklyEndMs: Double
        ) {
            earliestMs = min(earliestMs ?? row.createdMs, row.createdMs)

            if row.createdMs >= sessionStartMs && row.createdMs < nowMs {
                sessionCost += row.cost
                oldestRollingMs = min(oldestRollingMs ?? row.createdMs, row.createdMs)
            }

            if row.createdMs >= weeklyStartMs && row.createdMs < weeklyEndMs {
                weeklyCost += row.cost
            }
        }
    }

    private static func parseRemoteUsageMetrics(_ body: String) -> [RemoteWindowKey: RemoteUsageMetric] {
        let nsBody = body as NSString
        let matches = remoteUsageRegex.matches(in: body, options: [], range: NSRange(location: 0, length: nsBody.length))
        var output: [RemoteWindowKey: RemoteUsageMetric] = [:]
        for match in matches where match.numberOfRanges >= 5 {
            let keyRaw = nsBody.substring(with: match.range(at: 1))
            guard let key = RemoteWindowKey(rawValue: keyRaw) else { continue }
            let status = nsBody.substring(with: match.range(at: 2))
            guard let resetInSec = Double(nsBody.substring(with: match.range(at: 3))),
                  let usagePercent = Double(nsBody.substring(with: match.range(at: 4))) else {
                continue
            }
            output[key] = RemoteUsageMetric(
                status: status,
                resetInSec: resetInSec,
                usagePercent: usagePercent
            )
        }
        return output
    }

    internal static func normalizedAuthCookieHeader(_ raw: String?) -> String? {
        guard var value = normalizedText(raw) else { return nil }
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let pattern = #"(?i)(?:^|;)\s*auth=([^;]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
            in: value,
            options: [],
            range: NSRange(location: 0, length: (value as NSString).length)
           ) {
            let nsValue = value as NSString
            let cookieValue = nsValue.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cookieValue.isEmpty {
                return "auth=\(cookieValue)"
            }
        }

        if !value.contains("=") {
            return "auth=\(value)"
        }
        return nil
    }

    private static func fallbackReason(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .missingCredential, .unauthorized, .unauthorizedDetail:
                return "cookie"
            case .rateLimited:
                return "rate-limited"
            case .invalidResponse(let detail):
                if detail.localizedCaseInsensitiveContains("workspace") {
                    return "workspace"
                }
                return "parse"
            case .timeout:
                return "network"
            case .commandFailed, .unavailable:
                return "remote"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }
        return "remote"
    }

    private static func normalizedText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    private static func percent(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return clampPercent((max(0, used) / limit) * 100)
    }

    private struct MonthBounds {
        let start: Date
        let end: Date
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func startOfUTCWeek(now: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: now)
        let offset = (weekday + 5) % 7 // Monday=0
        let dayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -offset, to: dayStart) ?? dayStart
    }

    private static func anchoredMonthBounds(now: Date, anchorMs: Double?, calendar: Calendar) -> MonthBounds {
        guard let anchorMs else {
            let start = startOfUTCMonth(now: now, calendar: calendar)
            return MonthBounds(start: start, end: startOfNextUTCMonth(now: now, calendar: calendar))
        }

        let anchor = Date(timeIntervalSince1970: anchorMs / 1000)
        var year = calendar.component(.year, from: now)
        var month = calendar.component(.month, from: now)
        var start = anchorMonth(year: year, month: month, anchor: anchor, calendar: calendar)

        if start > now {
            let previous = shiftMonth(year: year, month: month, delta: -1)
            year = previous.year
            month = previous.month
            start = anchorMonth(year: year, month: month, anchor: anchor, calendar: calendar)
        }

        let next = shiftMonth(year: year, month: month, delta: 1)
        let end = anchorMonth(year: next.year, month: next.month, anchor: anchor, calendar: calendar)
        return MonthBounds(start: start, end: end)
    }

    private static func shiftMonth(year: Int, month: Int, delta: Int) -> (year: Int, month: Int) {
        let total = year * 12 + (month - 1) + delta
        let shiftedYear = Int(floor(Double(total) / 12.0))
        let shiftedMonth = total - shiftedYear * 12 + 1
        return (shiftedYear, shiftedMonth)
    }

    private static func anchorMonth(year: Int, month: Int, anchor: Date, calendar: Calendar) -> Date {
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)

        var firstDayComponents = DateComponents()
        firstDayComponents.year = year
        firstDayComponents.month = month
        firstDayComponents.day = 1
        firstDayComponents.hour = 0
        firstDayComponents.minute = 0
        firstDayComponents.second = 0
        firstDayComponents.nanosecond = 0

        let firstDay = calendar.date(from: firstDayComponents)
            ?? Date(timeIntervalSince1970: 0)
        let maxDay = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 28

        var final = DateComponents()
        final.year = year
        final.month = month
        final.day = min(anchorComponents.day ?? 1, maxDay)
        final.hour = anchorComponents.hour ?? 0
        final.minute = anchorComponents.minute ?? 0
        final.second = anchorComponents.second ?? 0
        final.nanosecond = anchorComponents.nanosecond ?? 0
        return calendar.date(from: final) ?? firstDay
    }

    private static func startOfUTCMonth(now: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1))
            ?? now
    }

    private static func startOfNextUTCMonth(now: Date, calendar: Calendar) -> Date {
        let start = startOfUTCMonth(now: now, calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(monthlyDisplayWindowSec)
    }
}
