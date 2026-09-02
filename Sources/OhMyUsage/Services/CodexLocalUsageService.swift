import Foundation
import OhMyUsageApplication

enum CodexTrendScope: String, CaseIterable, Identifiable, Sendable {
    case currentAccount
    case allAccounts

    var id: String { rawValue }
}

struct CodexTrendIdentityContext: Equatable, Sendable {
    var accountID: String?
    var email: String?
    var identityKey: String?

    init(accountID: String?, email: String?, identityKey: String? = nil) {
        self.accountID = Self.normalizedAccountID(accountID)
        self.email = Self.trimmed(email)?.lowercased()
        self.identityKey = Self.trimmed(identityKey)?.lowercased()
    }

    var cacheIdentity: String {
        identityKey ?? accountID ?? email ?? "unknown"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedAccountID(_ value: String?) -> String? {
        guard var accountID = trimmed(value)?.lowercased() else { return nil }
        if accountID.hasPrefix("tenant:account:") {
            accountID = String(accountID.dropFirst("tenant:account:".count))
        }
        if accountID.hasPrefix("account:") {
            accountID = String(accountID.dropFirst("account:".count))
        }
        return trimmed(accountID)
    }
}

struct CodexLocalUsageTrendPoint: Equatable, Identifiable, Sendable {
    var id: String
    var startAt: Date
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
}

struct CodexLocalUsageModelBreakdown: Equatable, Identifiable, Sendable {
    var id: String { modelID }
    var modelID: String
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
}

struct CodexLocalUsagePeriodSummary: Equatable, Sendable {
    var totalTokens: Int
    var responses: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var byModel: [CodexLocalUsageModelBreakdown]

    static let empty = CodexLocalUsagePeriodSummary(totalTokens: 0, responses: 0, byModel: [])
}

enum CodexLocalUsageDiagnosticsSource: String, Sendable {
    case strict
    case sessions
    case approximate
}

struct CodexLocalUsageDiagnostics: Equatable, Sendable {
    var matchedRows: Int
    var parsedEvents: Int
    var attributableEvents: Int
    var recoveredByConversationResponses: Int
    var recoveredByConversationTokens: Int
    var unattributedResponses: Int
    var unattributedTokens: Int
    var latestEventAt: Date?
    var source: CodexLocalUsageDiagnosticsSource
}

struct CodexLocalUsageSummary: Equatable, Sendable {
    var today: CodexLocalUsagePeriodSummary
    var yesterday: CodexLocalUsagePeriodSummary
    var last30Days: CodexLocalUsagePeriodSummary
    var hourly24: [CodexLocalUsageTrendPoint]
    var daily7: [CodexLocalUsageTrendPoint]
    var databasePath: String
    var generatedAt: Date
    var diagnostics: CodexLocalUsageDiagnostics?
}

enum CodexLocalUsageServiceError: LocalizedError, Equatable {
    case databaseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "Codex logs database not found: \(path)"
        }
    }
}

final class CodexLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let maxRowCount: Int
    private let onSessionFileParsed: ((String) -> Void)?

    private static let sessionFileEnumerationCache = LocalUsageFileEnumerationCache()
    private static let parsedSessionFileCache = LocalUsageParsedFileCache<ParsedTokenEvent>(
        maxEntries: RuntimeDiagnosticsLimits.localUsageParsedFileCacheMaxEntries,
        maxCachedValues: RuntimeDiagnosticsLimits.localUsageParsedFileCacheMaxCachedValues
    )

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        maxRowCount: Int = 60_000,
        nowProvider: @escaping () -> Date = Date.init,
        onSessionFileParsed: ((String) -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.maxRowCount = max(100, maxRowCount)
        self.onSessionFileParsed = onSessionFileParsed
    }

    func fetchSummary(
        databasePath: String? = nil,
        sessionsRootPath: String? = nil,
        archivedSessionsRootPath: String? = nil,
        scope: CodexTrendScope = .allAccounts,
        currentIdentity: CodexTrendIdentityContext? = nil
    ) throws -> CodexLocalUsageSummary {
        let logsPath = resolvedDatabasePath(explicitPath: databasePath)

        let now = nowProvider()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfYesterday
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let startOf24Hours = calendar.date(byAdding: .hour, value: -23, to: startOfCurrentHour) ?? startOfCurrentHour

        let events: [ParsedTokenEvent]
        var diagnostics: CodexLocalUsageDiagnostics?
        switch scope {
        case .allAccounts:
            let sessionRoots = resolvedSessionRoots(
                explicitRoot: sessionsRootPath,
                explicitArchivedRoot: archivedSessionsRootPath
            )
            events = scanSessionTokenEvents(
                sessionRoots: sessionRoots,
                startOfLast30Days: startOfLast30Days
            )
            diagnostics = CodexLocalUsageDiagnostics(
                matchedRows: events.count,
                parsedEvents: events.count,
                attributableEvents: 0,
                recoveredByConversationResponses: 0,
                recoveredByConversationTokens: 0,
                unattributedResponses: 0,
                unattributedTokens: 0,
                latestEventAt: events.map(\.eventAt).max(),
                source: .sessions
            )
        case .currentAccount:
            guard fileManager.fileExists(atPath: logsPath) else {
                throw CodexLocalUsageServiceError.databaseNotFound(logsPath)
            }
            let scanResult = scanIdentityLogEvents(
                databasePath: logsPath,
                startOfLast30Days: startOfLast30Days
            )
            events = scanResult.events
            diagnostics = scanResult.diagnostics
        }

        var todayAccumulator = PeriodAccumulator()
        var yesterdayAccumulator = PeriodAccumulator()
        var last30Accumulator = PeriodAccumulator()
        var hourly24Buckets: [Date: PeriodAccumulator] = [:]
        var daily7Buckets: [Date: PeriodAccumulator] = [:]
        var attributableEvents = 0
        var latestAttributableEventAt: Date?

        for event in events {
            if event.eventAt < startOfLast30Days {
                continue
            }
            guard Self.shouldInclude(event: event, scope: scope, currentIdentity: currentIdentity) else {
                continue
            }

            attributableEvents += 1
            if latestAttributableEventAt == nil || event.eventAt > (latestAttributableEventAt ?? .distantPast) {
                latestAttributableEventAt = event.eventAt
            }

            last30Accumulator.consume(event: event)
            if event.eventAt >= startOfToday {
                todayAccumulator.consume(event: event)
            } else if event.eventAt >= startOfYesterday {
                yesterdayAccumulator.consume(event: event)
            }

            if event.eventAt >= startOf24Hours,
               let hourStart = calendar.dateInterval(of: .hour, for: event.eventAt)?.start {
                var accumulator = hourly24Buckets[hourStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                hourly24Buckets[hourStart] = accumulator
            }

            if event.eventAt >= startOf7Days {
                let dayStart = calendar.startOfDay(for: event.eventAt)
                var accumulator = daily7Buckets[dayStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                daily7Buckets[dayStart] = accumulator
            }
        }

        let hourly24 = buildHourlyTrendPoints(
            buckets: hourly24Buckets,
            startOfCurrentHour: startOfCurrentHour
        )
        let daily7 = buildDailyTrendPoints(
            buckets: daily7Buckets,
            startOfToday: startOfToday
        )

        if var value = diagnostics {
            value.attributableEvents = attributableEvents
            value.latestEventAt = latestAttributableEventAt ?? value.latestEventAt
            diagnostics = value
        }

        return CodexLocalUsageSummary(
            today: todayAccumulator.summary,
            yesterday: yesterdayAccumulator.summary,
            last30Days: last30Accumulator.summary,
            hourly24: hourly24,
            daily7: daily7,
            databasePath: logsPath,
            generatedAt: now,
            diagnostics: diagnostics
        )
    }

    func fetchEvents(
        databasePath: String? = nil,
        sessionsRootPath: String? = nil,
        archivedSessionsRootPath: String? = nil,
        scope: CodexTrendScope = .allAccounts,
        currentIdentity: CodexTrendIdentityContext? = nil,
        since: Date
    ) throws -> [LocalUsageEvent] {
        let parsedEvents: [ParsedTokenEvent]
        switch scope {
        case .allAccounts:
            parsedEvents = scanSessionTokenEvents(
                sessionRoots: resolvedSessionRoots(
                    explicitRoot: sessionsRootPath,
                    explicitArchivedRoot: archivedSessionsRootPath
                ),
                startOfLast30Days: since
            )
        case .currentAccount:
            let logsPath = resolvedDatabasePath(explicitPath: databasePath)
            guard fileManager.fileExists(atPath: logsPath) else {
                throw CodexLocalUsageServiceError.databaseNotFound(logsPath)
            }
            parsedEvents = scanIdentityLogEvents(
                databasePath: logsPath,
                startOfLast30Days: since
            ).events
        }

        return parsedEvents
            .filter { $0.eventAt >= since && Self.shouldInclude(event: $0, scope: scope, currentIdentity: currentIdentity) }
            .map(Self.localUsageEvent)
    }

    private func resolvedSessionRoots(explicitRoot: String?, explicitArchivedRoot: String?) -> [String] {
        if let explicitRoot {
            var roots = [explicitRoot]
            if let explicitArchivedRoot {
                roots.append(explicitArchivedRoot)
            }
            return roots
        }

        let codexRoot = "\(NSHomeDirectory())/.codex"
        return [
            "\(codexRoot)/sessions",
            "\(codexRoot)/archived_sessions"
        ]
    }

    private func scanSessionTokenEvents(
        sessionRoots: [String],
        startOfLast30Days: Date
    ) -> [ParsedTokenEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: startOfLast30Days) ?? startOfLast30Days
        let files = sessionJSONLFiles(roots: sessionRoots, cutoff: cutoff)
        if files.isEmpty {
            return []
        }

        var events: [ParsedTokenEvent] = []
        events.reserveCapacity(1024)
        for file in files {
            let parsed = Self.parsedSessionFileCache.values(for: file) {
                onSessionFileParsed?(file.path)
                return CodexSessionTokenEventScanner.parse(filePath: file.path)
            }
            events.append(contentsOf: parsed.lazy.filter { $0.eventAt >= startOfLast30Days })
        }
        return events
    }

    private func sessionJSONLFiles(roots: [String], cutoff: Date) -> [LocalUsageFileSnapshot] {
        Self.sessionFileEnumerationCache.files(
            identifier: "codex-session-jsonl",
            roots: roots,
            cutoff: cutoff,
            fileManager: fileManager,
            includeFile: { $0.pathExtension.lowercased() == "jsonl" }
        )
    }

    private func scanIdentityLogEvents(
        databasePath: String,
        startOfLast30Days: Date
    ) -> IdentityLogScanResult {
        CodexIdentityLogEventScanner(maxRowCount: maxRowCount).scan(
            databasePath: databasePath,
            startOfLast30Days: startOfLast30Days
        )
    }

    private static func shouldInclude(
        event: ParsedTokenEvent,
        scope: CodexTrendScope,
        currentIdentity: CodexTrendIdentityContext?
    ) -> Bool {
        guard scope == .currentAccount else { return true }
        guard let currentIdentity else { return false }

        if let expectedAccountID = currentIdentity.accountID {
            if let eventAccountID = event.accountID {
                if eventAccountID == expectedAccountID {
                    return true
                }
                // Some Codex logs emit a stable account_id that differs from the UI-selected identity,
                // but still carry a trustworthy email. Fall back to email in this case.
                if let expectedEmail = currentIdentity.email {
                    return event.email == expectedEmail
                }
                return false
            }
            if let expectedEmail = currentIdentity.email {
                return event.email == expectedEmail
            }
            return false
        }

        if let expectedEmail = currentIdentity.email {
            return event.email == expectedEmail
        }

        return false
    }

    private func resolvedDatabasePath(explicitPath: String?) -> String {
        if let explicitPath {
            return explicitPath
        }
        return "\(NSHomeDirectory())/.codex/logs_2.sqlite"
    }

    private static func localUsageEvent(from event: ParsedTokenEvent) -> LocalUsageEvent {
        LocalUsageEvent(
            signature: event.signature,
            eventAt: event.eventAt,
            modelID: event.modelID,
            totalTokens: event.totalTokens,
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cacheReadTokens: event.cacheReadTokens,
            cacheWriteTokens: event.cacheWriteTokens
        )
    }

    private func buildHourlyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        startOfCurrentHour: Date
    ) -> [CodexLocalUsageTrendPoint] {
        (0..<24).compactMap { offset -> CodexLocalUsageTrendPoint? in
            guard let hourStart = calendar.date(byAdding: .hour, value: -(23 - offset), to: startOfCurrentHour) else {
                return nil
            }
            let accumulator = buckets[hourStart] ?? PeriodAccumulator()
            return CodexLocalUsageTrendPoint(
                id: "h-\(Int(hourStart.timeIntervalSince1970))",
                startAt: hourStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses,
                inputTokens: accumulator.inputTokens,
                outputTokens: accumulator.outputTokens,
                cacheReadTokens: accumulator.cacheReadTokens,
                cacheWriteTokens: accumulator.cacheWriteTokens
            )
        }
    }

    private func buildDailyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        startOfToday: Date
    ) -> [CodexLocalUsageTrendPoint] {
        (0..<7).compactMap { offset -> CodexLocalUsageTrendPoint? in
            guard let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday) else {
                return nil
            }
            let accumulator = buckets[dayStart] ?? PeriodAccumulator()
            return CodexLocalUsageTrendPoint(
                id: "d-\(Int(dayStart.timeIntervalSince1970))",
                startAt: dayStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses,
                inputTokens: accumulator.inputTokens,
                outputTokens: accumulator.outputTokens,
                cacheReadTokens: accumulator.cacheReadTokens,
                cacheWriteTokens: accumulator.cacheWriteTokens
            )
        }
    }
}

private struct PeriodAccumulator {
    var totalTokens = 0
    var responses = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var byModel: [String: CodexModelAccumulator] = [:]

    mutating func consume(event: ParsedTokenEvent) {
        totalTokens += event.totalTokens
        responses += 1
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cacheReadTokens += event.cacheReadTokens
        cacheWriteTokens += event.cacheWriteTokens
        var model = byModel[event.modelID, default: CodexModelAccumulator()]
        model.consume(event: event)
        byModel[event.modelID] = model
    }

    var summary: CodexLocalUsagePeriodSummary {
        let models = byModel.map { key, value in
            CodexLocalUsageModelBreakdown(
                modelID: key,
                totalTokens: value.totalTokens,
                responses: value.responses,
                inputTokens: value.inputTokens,
                outputTokens: value.outputTokens,
                cacheReadTokens: value.cacheReadTokens,
                cacheWriteTokens: value.cacheWriteTokens
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                if lhs.responses == rhs.responses {
                    return lhs.modelID < rhs.modelID
                }
                return lhs.responses > rhs.responses
            }
            return lhs.totalTokens > rhs.totalTokens
        }

        return CodexLocalUsagePeriodSummary(
            totalTokens: totalTokens,
            responses: responses,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            byModel: models
        )
    }
}

private struct CodexModelAccumulator {
    var totalTokens = 0
    var responses = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0

    mutating func consume(event: ParsedTokenEvent) {
        totalTokens += event.totalTokens
        responses += 1
        inputTokens += event.inputTokens
        outputTokens += event.outputTokens
        cacheReadTokens += event.cacheReadTokens
        cacheWriteTokens += event.cacheWriteTokens
    }
}
