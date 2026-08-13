import Foundation
import OhMyUsageApplication
import OhMyUsageProviders
import SQLite3

protocol CursorDashboardUsageFetching: Sendable {
    func fetchUsageEvents(since: Date, until: Date, auth: CursorLocalAuth) throws -> [LocalUsageEvent]
}

struct CursorLocalAuth: Equatable, Sendable {
    var databasePath: String
    var accessToken: String
    var userID: String
}

final class CursorDisabledDashboardFetcher: CursorDashboardUsageFetching, Sendable {
    func fetchUsageEvents(since: Date, until: Date, auth: CursorLocalAuth) throws -> [LocalUsageEvent] {
        _ = (since, until, auth)
        return []
    }
}

final class CursorDashboardUsageClient: CursorDashboardUsageFetching, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsageEvents(since: Date, until: Date, auth: CursorLocalAuth) throws -> [LocalUsageEvent] {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return []
        }

        var events: [LocalUsageEvent] = []
        let pageSize = 200
        let maxPages = 30
        for page in 1...maxPages {
            let pageEvents = try fetchPage(
                page: page,
                pageSize: pageSize,
                since: since,
                until: until,
                auth: auth
            )
            events.append(contentsOf: pageEvents)
            if pageEvents.count < pageSize {
                break
            }
        }
        return events
    }

    private func fetchPage(
        page: Int,
        pageSize: Int,
        since: Date,
        until: Date,
        auth: CursorLocalAuth
    ) throws -> [LocalUsageEvent] {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        let encodedToken = "\(auth.userID)::\(auth.accessToken)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? "\(auth.userID)::\(auth.accessToken)"
        request.setValue("WorkosCursorSessionToken=\(encodedToken)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "page": page,
            "pageSize": pageSize,
            "startDate": Int64((since.timeIntervalSince1970 * 1_000).rounded()),
            "endDate": Int64((until.timeIntervalSince1970 * 1_000).rounded())
        ])

        let data = try Self.send(request, session: session)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let rows = (root["usageEventsDisplay"] as? [[String: Any]])
            ?? (root["usageEvents"] as? [[String: Any]])
            ?? []
        return rows.compactMap(Self.event(from:))
    }

    private static func send(_ request: URLRequest, session: URLSession) throws -> Data {
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                box.result = .failure(error)
            } else if let http = response as? HTTPURLResponse,
                      !(200...299).contains(http.statusCode) {
                box.result = .failure(CursorLocalUsageServiceError.dashboardHTTP(http.statusCode))
            } else {
                box.result = .success(data ?? Data())
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try box.result.get()
    }

    private static func event(from row: [String: Any]) -> LocalUsageEvent? {
        let usage = (row["tokenUsage"] as? [String: Any]) ?? [:]
        let input = LocalUsageJSONParsing.firstInt(in: usage, keys: ["inputTokens", "input_tokens"]) ?? 0
        let output = LocalUsageJSONParsing.firstInt(in: usage, keys: ["outputTokens", "output_tokens"]) ?? 0
        let cacheRead = LocalUsageJSONParsing.firstInt(
            in: usage,
            keys: ["cacheReadTokens", "cache_read_tokens", "cachedInputTokens"]
        ) ?? 0
        let cacheWrite = LocalUsageJSONParsing.firstInt(
            in: usage,
            keys: ["cacheWriteTokens", "cache_write_tokens", "cacheCreationTokens"]
        ) ?? 0
        let total = input + output + cacheRead + cacheWrite
        guard total > 0 else { return nil }
        guard let eventAt = LocalUsageJSONParsing.parseTimestamp(row["timestamp"]) else {
            return nil
        }
        let modelID = LocalUsageJSONParsing.stringValue(row["model"]) ?? "cursor"
        let requestID = LocalUsageJSONParsing.stringValue(row["requestId"])
            ?? LocalUsageJSONParsing.stringValue(row["id"])
            ?? "cursor|\(Int(eventAt.timeIntervalSince1970))|\(modelID)|\(total)"
        return LocalUsageEvent(
            signature: "cursor|\(requestID)",
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: total,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    private final class ResultBox: @unchecked Sendable {
        var result: Result<Data, Error> = .failure(CursorLocalUsageServiceError.dashboardHTTP(0))
    }
}

enum CursorLocalUsageServiceError: LocalizedError {
    case dashboardHTTP(Int)

    var errorDescription: String? {
        switch self {
        case .dashboardHTTP(let code):
            return "Cursor dashboard http \(code)"
        }
    }
}

final class CursorLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let databasePath: String
    private let dashboardFetcher: any CursorDashboardUsageFetching

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        databasePath: String? = nil,
        dashboardFetcher: (any CursorDashboardUsageFetching)? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.databasePath = databasePath
            ?? "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        self.dashboardFetcher = dashboardFetcher ?? CursorDashboardUsageClient()
    }

    func fetchSummary() throws -> LocalUsageSummary {
        let now = nowProvider()
        let startOfLast30Days = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let events = try fetchEvents(since: startOfLast30Days, until: now)
        return LocalUsageSummaryBuilder.build(
            events: events,
            calendar: calendar,
            now: now,
            sourcePath: databasePath
        )
    }

    func fetchEvents(since: Date, until: Date? = nil) throws -> [LocalUsageEvent] {
        let end = until ?? nowProvider()
        let localEvents = readLocalEvents(since: since, until: end)
        let localWithTokens = localEvents.filter { $0.totalTokens > 0 }
        if let auth = loadAuth() {
            let remote = (try? dashboardFetcher.fetchUsageEvents(since: since, until: end, auth: auth)) ?? []
            if !remote.isEmpty {
                return remote.filter { $0.eventAt >= since && $0.eventAt < end }
            }
        }
        return localWithTokens
    }

    private func readLocalEvents(since: Date, until: Date) -> [LocalUsageEvent] {
        guard fileManager.fileExists(atPath: databasePath) else {
            return []
        }
        return queryJSONValues(
            query: "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%';"
        )
        .compactMap { key, json in
            event(fromBubbleKey: key, json: json, since: since, until: until)
        }
    }

    private func event(fromBubbleKey key: String, json: [String: Any], since: Date, until: Date) -> LocalUsageEvent? {
        let tokenCount = (json["tokenCount"] as? [String: Any]) ?? [:]
        let input = LocalUsageJSONParsing.firstInt(in: tokenCount, keys: ["inputTokens", "input_tokens"]) ?? 0
        let output = LocalUsageJSONParsing.firstInt(in: tokenCount, keys: ["outputTokens", "output_tokens"]) ?? 0
        let cacheRead = LocalUsageJSONParsing.firstInt(
            in: tokenCount,
            keys: ["cacheReadTokens", "cache_read_tokens"]
        ) ?? 0
        let cacheWrite = LocalUsageJSONParsing.firstInt(
            in: tokenCount,
            keys: ["cacheWriteTokens", "cache_write_tokens"]
        ) ?? 0
        let total = input + output + cacheRead + cacheWrite
        guard total > 0 else { return nil }
        guard let eventAt = LocalUsageJSONParsing.parseTimestamp(json["createdAt"] ?? json["timestamp"]),
              eventAt >= since,
              eventAt < until else {
            return nil
        }
        let modelID = LocalUsageJSONParsing.stringValue(json["modelName"])
            ?? LocalUsageJSONParsing.stringValue(json["model"])
            ?? "cursor"
        return LocalUsageEvent(
            signature: "cursor|\(key)",
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: total,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    private func loadAuth() -> CursorLocalAuth? {
        var values: [String: String] = [:]
        for (key, value) in queryRawRows(
            query: """
            SELECT key, value FROM ItemTable
            WHERE key IN ('cursorAuth/accessToken');
            """
        ) {
            values[key] = value
        }
        guard let accessToken = values["cursorAuth/accessToken"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            return nil
        }
        let subject = JWTInspector.subject(accessToken) ?? ""
        let userID = subject.components(separatedBy: "|").last ?? subject
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else { return nil }
        return CursorLocalAuth(
            databasePath: databasePath,
            accessToken: accessToken,
            userID: trimmedUserID
        )
    }

    private func queryJSONValues(query: String) -> [(key: String, json: [String: Any])] {
        queryRawRows(query: query).compactMap { key, value in
            guard let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return (key, json)
        }
    }

    private func queryRawRows(query: String) -> [(key: String, json: String)] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return []
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(statement, 0),
                  let valuePointer = sqlite3_column_text(statement, 1) else {
                continue
            }
            rows.append((String(cString: keyPointer), String(cString: valuePointer)))
        }
        return rows
    }
}
