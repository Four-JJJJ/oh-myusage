import Foundation
import OhMyUsageApplication
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum CCSwitchUsageSource: String, Equatable, Sendable {
    case proxy
    case session
    case dailyRollup

    var analyticsSource: UsageAnalyticsRecordSource {
        switch self {
        case .proxy: return .ccswitchProxy
        case .session: return .ccswitchSession
        case .dailyRollup: return .ccswitchDailyRollup
        }
    }
}

struct CCSwitchUsageRecord: Equatable, Sendable {
    var requestID: String
    var source: CCSwitchUsageSource
    var eventAt: Date
    var appType: String
    var providerID: String
    var providerName: String
    var modelID: String
    var requestCount: Int
    var successCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    var totals: UsageMetricTotals {
        UsageMetricTotals(
            requestCount: requestCount,
            successCount: successCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens
        )
    }

    var analyticsRecord: UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: source.analyticsSource,
            eventAt: eventAt,
            appType: appType,
            providerID: providerID,
            providerName: providerName,
            modelID: modelID,
            requestID: requestID,
            totals: totals
        )
    }
}

struct CCSwitchUsageReadResult: Equatable, Sendable {
    var records: [CCSwitchUsageRecord]
    var diagnostics: [String]
}

struct CCSwitchUsageLogReaderStreamEvent: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case proxyRequestLogs
        case dailyRollups
    }

    enum Phase: Equatable, Sendable {
        case rowRead
        case recordMapped
    }

    var source: Source
    var phase: Phase
    var ordinal: Int
}

final class CCSwitchUsageLogReader: @unchecked Sendable {
    private let databasePath: String
    private let fileManager: FileManager
    private let streamObserver: ((CCSwitchUsageLogReaderStreamEvent) -> Void)?

    init(
        databasePath: String = "\(NSHomeDirectory())/.cc-switch/cc-switch.db",
        fileManager: FileManager = .default,
        streamObserver: ((CCSwitchUsageLogReaderStreamEvent) -> Void)? = nil
    ) {
        self.databasePath = (databasePath as NSString).expandingTildeInPath
        self.fileManager = fileManager
        self.streamObserver = streamObserver
    }

    var sourceFingerprintCacheIdentity: String {
        (databasePath as NSString).standardizingPath
    }

    func readUsageLogs(since: Date, until: Date) -> CCSwitchUsageReadResult {
        guard fileManager.fileExists(atPath: databasePath) else {
            return CCSwitchUsageReadResult(
                records: [],
                diagnostics: ["未安装 cc-switch，已仅使用各官方应用的本地用量日志"]
            )
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return CCSwitchUsageReadResult(
                records: [],
                diagnostics: ["无法只读打开 cc-switch 请求日志：\(databasePath)"]
            )
        }
        defer { sqlite3_close(database) }

        var diagnostics: [String] = []
        var records: [CCSwitchUsageRecord] = []

        if tableExists("proxy_request_logs", database: database) {
            records.append(contentsOf: readProxyLogs(database: database, since: since, until: until))
        } else {
            diagnostics.append("cc-switch 数据库缺少 proxy_request_logs 表")
        }

        if tableExists("usage_daily_rollups", database: database) {
            let rollups = readDailyRollups(database: database, since: since, until: until)
            records.append(contentsOf: Self.rollupsWithoutCoveredDetailDays(rollups, details: records))
        }

        return CCSwitchUsageReadResult(records: records, diagnostics: diagnostics)
    }

    func sourceFingerprint() -> LocalUsageSourceFingerprint {
        LocalUsageSourceFingerprintBuilder.fingerprint(
            roots: [
                databasePath,
                "\(databasePath)-wal",
                "\(databasePath)-shm"
            ],
            fileManager: fileManager,
            includeFile: { _ in true }
        )
    }

    private func readProxyLogs(database: OpaquePointer, since: Date, until: Date) -> [CCSwitchUsageRecord] {
        let hasProviders = tableExists("providers", database: database)
        let providerNameExpression = hasProviders ? "p.name" : "NULL"
        let joinExpression = hasProviders ? "LEFT JOIN providers p ON p.id = l.provider_id" : ""
        let createdAtRangePredicate = Self.createdAtRawEpochRangePredicate("l.created_at")
        let query = """
        SELECT l.request_id, l.provider_id, l.app_type, l.model, l.input_tokens, l.output_tokens,
               l.cache_read_tokens, l.cache_creation_tokens, l.status_code, l.created_at,
               l.data_source, \(providerNameExpression)
        FROM proxy_request_logs l
        \(joinExpression)
        WHERE \(createdAtRangePredicate)
        """

        var output: [CCSwitchUsageRecord] = []
        forEachRow(
            database: database,
            query: query,
            source: .proxyRequestLogs,
            bind: { statement in
                Self.bindCreatedAtRawEpochRanges(statement, since: since, until: until)
            },
            body: { row, rowOrdinal in
                guard let eventAt = Self.dateFromEpoch(row.int64(9)),
                      eventAt >= since,
                      eventAt < until else {
                    return
                }
                let providerID = row.string(1) ?? "unknown"
                let appType = row.string(2) ?? "unknown"
                let dataSource = row.string(10)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let source: CCSwitchUsageSource = (dataSource == "session" || Self.isSessionPlaceholder(providerID))
                    ? .session
                    : .proxy
                let cacheRead = row.int(6)
                let input = Self.freshInputTokens(
                    appType: appType,
                    rawInputTokens: row.int(4),
                    cacheReadTokens: cacheRead
                )
                let statusCode = row.int(8)
                output.append(
                    CCSwitchUsageRecord(
                        requestID: row.string(0) ?? UUID().uuidString,
                        source: source,
                        eventAt: eventAt,
                        appType: appType,
                        providerID: providerID,
                        providerName: Self.providerName(
                            providerID: providerID,
                            configuredName: row.string(11)
                        ),
                        modelID: row.string(3) ?? "unknown",
                        requestCount: 1,
                        successCount: (200..<400).contains(statusCode) ? 1 : 0,
                        inputTokens: input,
                        outputTokens: row.int(5),
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: row.int(7)
                    )
                )
                notifyStreamEvent(source: .proxyRequestLogs, phase: .recordMapped, ordinal: rowOrdinal)
            }
        )
        return output
    }

    private func readDailyRollups(database: OpaquePointer, since: Date, until: Date) -> [CCSwitchUsageRecord] {
        let hasProviders = tableExists("providers", database: database)
        let providerNameExpression = hasProviders ? "p.name" : "NULL"
        let joinExpression = hasProviders ? "LEFT JOIN providers p ON p.id = r.provider_id" : ""
        let startDay = Self.rollupDayString(for: since)
        let endDay = Self.rollupDayString(for: until)
        let query = """
        SELECT r.date, r.app_type, r.provider_id, r.model, r.request_count, r.success_count,
               r.input_tokens, r.output_tokens, r.cache_read_tokens, r.cache_creation_tokens,
               \(providerNameExpression)
        FROM usage_daily_rollups r
        \(joinExpression)
        WHERE r.date >= ?
          AND r.date <= ?
        """

        var output: [CCSwitchUsageRecord] = []
        forEachRow(
            database: database,
            query: query,
            source: .dailyRollups,
            bind: { statement in
                sqlite3_bind_text(statement, 1, startDay, -1, sqliteTransient)
                sqlite3_bind_text(statement, 2, endDay, -1, sqliteTransient)
            },
            body: { row, rowOrdinal in
                guard let eventAt = Self.dateFromRollupDay(row.string(0)),
                      eventAt >= since,
                      eventAt < until else {
                    return
                }
                let appType = row.string(1) ?? "unknown"
                let providerID = row.string(2) ?? "unknown"
                let cacheRead = row.int(8)
                output.append(
                    CCSwitchUsageRecord(
                        requestID: "rollup|\(row.string(0) ?? "")|\(appType)|\(providerID)|\(row.string(3) ?? "unknown")",
                        source: .dailyRollup,
                        eventAt: eventAt,
                        appType: appType,
                        providerID: providerID,
                        providerName: Self.providerName(
                            providerID: providerID,
                            configuredName: row.string(10)
                        ),
                        modelID: row.string(3) ?? "unknown",
                        requestCount: row.int(4),
                        successCount: row.int(5),
                        inputTokens: Self.freshInputTokens(
                            appType: appType,
                            rawInputTokens: row.int(6),
                            cacheReadTokens: cacheRead
                        ),
                        outputTokens: row.int(7),
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: row.int(9)
                    )
                )
                notifyStreamEvent(source: .dailyRollups, phase: .recordMapped, ordinal: rowOrdinal)
            }
        )
        return output
    }

    private func tableExists(_ name: String, database: OpaquePointer) -> Bool {
        let query = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func forEachRow(
        database: OpaquePointer,
        query: String,
        source: CCSwitchUsageLogReaderStreamEvent.Source,
        bind: ((OpaquePointer?) -> Void)? = nil,
        body: (SQLiteRow, Int) -> Void
    ) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bind?(statement)

        var rowOrdinal = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            rowOrdinal += 1
            notifyStreamEvent(source: source, phase: .rowRead, ordinal: rowOrdinal)
            body(SQLiteRow(statement: statement), rowOrdinal)
        }
    }

    private func notifyStreamEvent(
        source: CCSwitchUsageLogReaderStreamEvent.Source,
        phase: CCSwitchUsageLogReaderStreamEvent.Phase,
        ordinal: Int
    ) {
        streamObserver?(
            CCSwitchUsageLogReaderStreamEvent(source: source, phase: phase, ordinal: ordinal)
        )
    }

    static func createdAtRawEpochRangePredicate(_ column: String) -> String {
        createdAtEpochScales
            .map { _ in "(\(column) >= ? AND \(column) < ?)" }
            .joined(separator: " OR ")
    }

    private static func bindCreatedAtRawEpochRanges(
        _ statement: OpaquePointer?,
        since: Date,
        until: Date,
        startingAt firstIndex: Int32 = 1
    ) {
        var bindIndex = firstIndex
        for scale in createdAtEpochScales {
            sqlite3_bind_int64(statement, bindIndex, epochBoundary(since, scale: scale))
            sqlite3_bind_int64(statement, bindIndex + 1, epochBoundary(until, scale: scale))
            bindIndex += 2
        }
    }

    private static let createdAtEpochScales: [Double] = [
        1,
        1_000,
        1_000_000,
        1_000_000_000
    ]

    private static func epochBoundary(_ date: Date, scale: Double) -> Int64 {
        let value = (date.timeIntervalSince1970 * scale).rounded(.up)
        guard value.isFinite else {
            return value.sign == .minus ? Int64.min : Int64.max
        }
        if value <= Double(Int64.min) {
            return Int64.min
        }
        if value >= Double(Int64.max) {
            return Int64.max
        }
        return Int64(value)
    }

    static func rollupsWithoutCoveredDetailDays(
        _ rollups: [CCSwitchUsageRecord],
        details: [CCSwitchUsageRecord]
    ) -> [CCSwitchUsageRecord] {
        let covered = Set(details.map(coverageKey(for:)))
        return rollups.filter { !covered.contains(coverageKey(for: $0)) }
    }

    private static func coverageKey(for record: CCSwitchUsageRecord) -> String {
        let day = rollupDayString(for: record.eventAt)
        let appType = record.appType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let providerID = record.providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modelID = record.modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(day)|\(appType)|\(providerID)|\(modelID)"
    }

    private static func freshInputTokens(appType: String, rawInputTokens: Int, cacheReadTokens: Int) -> Int {
        let normalized = appType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "codex" || normalized == "gemini" else {
            return max(0, rawInputTokens)
        }
        if rawInputTokens >= cacheReadTokens {
            return max(0, rawInputTokens - cacheReadTokens)
        }
        return max(0, rawInputTokens)
    }

    private static func providerName(providerID: String, configuredName: String?) -> String {
        if let placeholderName = placeholderProviderName(providerID) {
            return placeholderName
        }
        let trimmed = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return providerID
    }

    private static func placeholderProviderName(_ providerID: String) -> String? {
        switch providerID {
        case "_session": return "Claude (Session)"
        case "_codex_session": return "Codex (Session)"
        case "_gemini_session": return "Gemini (Session)"
        default: return nil
        }
    }

    private static func isSessionPlaceholder(_ providerID: String) -> Bool {
        placeholderProviderName(providerID) != nil
    }

    private static func dateFromEpoch(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        let doubleValue = Double(value)
        if value > 1_000_000_000_000_000_000 {
            return Date(timeIntervalSince1970: doubleValue / 1_000_000_000)
        }
        if value > 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: doubleValue / 1_000_000)
        }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: doubleValue / 1_000)
        }
        return Date(timeIntervalSince1970: doubleValue)
    }

    private static func dateFromRollupDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)?.addingTimeInterval(12 * 60 * 60)
    }

    private static func rollupDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct SQLiteRow {
    var statement: OpaquePointer?

    func string(_ index: Int) -> String? {
        guard let statement, containsColumn(at: index),
              let pointer = sqlite3_column_text(statement, Int32(index)) else {
            return nil
        }
        return String(cString: pointer)
    }

    func int(_ index: Int) -> Int {
        max(0, Int(int64(index)))
    }

    func int64(_ index: Int) -> Int64 {
        guard let statement, containsColumn(at: index) else { return 0 }
        return sqlite3_column_int64(statement, Int32(index))
    }

    private func containsColumn(at index: Int) -> Bool {
        guard let statement else { return false }
        return index >= 0 && index < Int(sqlite3_column_count(statement))
    }
}
