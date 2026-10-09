import Foundation
import CryptoKit
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
    struct FetchResult: Sendable {
        var events: [LocalUsageEvent]
        var isPartial: Bool
        var failureDescription: String?
    }

    struct Page {
        var events: [LocalUsageEvent]
        var rawRowCount: Int
    }

    typealias RequestSender = @Sendable (URLRequest) throws -> Data
    typealias AsyncRequestSender = @Sendable (URLRequest) async throws -> Data
    private struct FlightKey: Hashable, Sendable {
        var since: Date
        var until: Date
        var identity: String
    }
    private actor Flights {
        struct Entry { var task: Task<FetchResult, Error>; var waiters: Set<UUID> }
        var entries: [FlightKey: Entry] = [:]
        func acquire(_ key: FlightKey, waiter: UUID, operation: @escaping @Sendable () async throws -> FetchResult) -> Task<FetchResult, Error> {
            if var entry = entries[key] {
                entry.waiters.insert(waiter); entries[key] = entry
                return entry.task
            }
            let task = Task { try await operation() }
            entries[key] = Entry(task: task, waiters: [waiter])
            return task
        }
        func release(_ key: FlightKey, waiter: UUID) {
            guard var entry = entries[key], entry.waiters.remove(waiter) != nil else { return }
            if entry.waiters.isEmpty { entries.removeValue(forKey: key); entry.task.cancel() }
            else { entries[key] = entry }
        }
    }
    private final class Waiter: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<FetchResult, Error>?
        private var result: Result<FetchResult, Error>?
        func install(_ continuation: CheckedContinuation<FetchResult, Error>) {
            lock.lock()
            if let result { lock.unlock(); continuation.resume(with: result) }
            else { self.continuation = continuation; lock.unlock() }
        }
        func finish(_ result: Result<FetchResult, Error>) {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return }
            self.result = result
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
    private let flights = Flights()

    private let session: URLSession
    private let requestSender: RequestSender?
    private let asyncRequestSender: AsyncRequestSender?
    private let maxPages: Int
    private let totalTimeout: TimeInterval

    init(session: URLSession = .shared, maxPages: Int = 30, totalTimeout: TimeInterval = 60,
         requestSender: RequestSender? = nil, asyncRequestSender: AsyncRequestSender? = nil) {
        self.session = session
        self.maxPages = max(1, maxPages)
        self.totalTimeout = max(0.01, totalTimeout)
        self.requestSender = requestSender
        self.asyncRequestSender = asyncRequestSender
    }

    func fetchUsageEvents(since: Date, until: Date, auth: CursorLocalAuth) throws -> [LocalUsageEvent] {
        try fetchResult(since: since, until: until, auth: auth).events
    }

    func fetchResult(since: Date, until: Date, auth: CursorLocalAuth) throws -> FetchResult {
        if requestSender == nil && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FetchResult(events: [], isPartial: false, failureDescription: nil)
        }
        let deadline = Date().addingTimeInterval(totalTimeout)
        var events: [LocalUsageEvent] = []
        var previousPage: Data?
        for page in 1...maxPages {
            try Task.checkCancellation()
            do {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw URLError(.timedOut) }
                let request = try makeRequest(page: page, since: since, until: until, auth: auth, timeout: remaining)
                let data = try requestSender?(request) ?? Self.send(request, session: session)
                guard data != previousPage else {
                    return FetchResult(events: events, isPartial: true, failureDescription: "repeated page")
                }
                previousPage = data
                let parsed = try Self.parsePage(data)
                events.append(contentsOf: parsed.events)
                if parsed.rawRowCount < 200 {
                    return FetchResult(events: events, isPartial: false, failureDescription: nil)
                }
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                if events.isEmpty { throw error }
                return FetchResult(events: events, isPartial: true, failureDescription: "dashboard request failed")
            }
        }
        return FetchResult(events: events, isPartial: true, failureDescription: "page limit reached")
    }

    func fetchResultAsync(since: Date, until: Date, auth: CursorLocalAuth) async throws -> FetchResult {
        try Task.checkCancellation()
        let digest = SHA256.hash(data: Data("\(auth.databasePath)|\(auth.userID)|\(auth.accessToken)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let key = FlightKey(since: since, until: until, identity: digest)
        let waiter = UUID()
        let task = await flights.acquire(key, waiter: waiter) { [self] in
            try await performFetchResultAsync(since: since, until: until, auth: auth)
        }
        let waiterResult = Waiter()
        do {
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    waiterResult.install(continuation)
                    Task { waiterResult.finish(await task.result) }
                }
            } onCancel: {
                waiterResult.finish(.failure(CancellationError()))
                Task { await self.flights.release(key, waiter: waiter) }
            }
            await flights.release(key, waiter: waiter)
            try Task.checkCancellation()
            return result
        } catch {
            await flights.release(key, waiter: waiter)
            throw error
        }
    }

    private func performFetchResultAsync(since: Date, until: Date, auth: CursorLocalAuth) async throws -> FetchResult {
        if asyncRequestSender == nil && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FetchResult(events: [], isPartial: false, failureDescription: nil)
        }
        // The deadline cancels URLSession's task and bounds the whole pagination operation.
        return try await withThrowingTaskGroup(of: FetchResult.self) { group in
            group.addTask { [self] in
                var events: [LocalUsageEvent] = []
                var previousPage: Data?
                for page in 1...maxPages {
                    try Task.checkCancellation()
                    do {
                        let request = try makeRequest(page: page, since: since, until: until, auth: auth, timeout: totalTimeout)
                        let data: Data
                        if let asyncRequestSender { data = try await asyncRequestSender(request) }
                        else {
                            let (responseData, response) = try await session.data(for: request)
                            try Self.validate(response)
                            data = responseData
                        }
                        guard data != previousPage else {
                            return FetchResult(events: events, isPartial: true, failureDescription: "repeated page")
                        }
                        previousPage = data
                        let parsed = try Self.parsePage(data)
                        events.append(contentsOf: parsed.events)
                        if parsed.rawRowCount < 200 {
                            return FetchResult(events: events, isPartial: false, failureDescription: nil)
                        }
                    } catch {
                        if Task.isCancelled || error is CancellationError { throw CancellationError() }
                        if events.isEmpty { throw error }
                        return FetchResult(events: events, isPartial: true, failureDescription: "dashboard request failed")
                    }
                }
                return FetchResult(events: events, isPartial: true, failureDescription: "page limit reached")
            }
            group.addTask { [totalTimeout] in
                try await Task.sleep(for: .seconds(totalTimeout))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func makeRequest(page: Int, since: Date, until: Date, auth: CursorLocalAuth, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!)
        request.httpMethod = "POST"
        request.timeoutInterval = min(20, timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        let encodedToken = "\(auth.userID)::\(auth.accessToken)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(auth.userID)::\(auth.accessToken)"
        request.setValue("WorkosCursorSessionToken=\(encodedToken)", forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "page": page, "pageSize": 200,
            "startDate": Int64((since.timeIntervalSince1970 * 1_000).rounded()),
            "endDate": Int64((until.timeIntervalSince1970 * 1_000).rounded())
        ])
        return request
    }

    static func parsePage(_ data: Data) throws -> Page {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = (root["usageEventsDisplay"] as? [Any]) ?? (root["usageEvents"] as? [Any]) else {
            throw CursorLocalUsageServiceError.invalidDashboardResponse
        }
        return Page(events: rows.compactMap { ($0 as? [String: Any]).flatMap(Self.event(from:)) }, rawRowCount: rows.count)
    }

    private static func validate(_ response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CursorLocalUsageServiceError.dashboardHTTP((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    private static func send(_ request: URLRequest, session: URLSession) throws -> Data {
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, error in
            do {
                if let error { throw error }
                try validate(response)
                box.result = .success(data ?? Data())
            } catch { box.result = .failure(error) }
            semaphore.signal()
        }
        task.resume()
        let deadline = Date().addingTimeInterval(request.timeoutInterval)
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            if Task.isCancelled { task.cancel(); throw CancellationError() }
            if Date() >= deadline { task.cancel(); throw URLError(.timedOut) }
        }
        try Task.checkCancellation()
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
    case invalidDashboardResponse

    var errorDescription: String? {
        switch self {
        case .invalidDashboardResponse:
            return "Cursor dashboard invalid response"
        case .dashboardHTTP(let code):
            return "Cursor dashboard http \(code)"
        }
    }
}

final class CursorLocalUsageService: @unchecked Sendable {
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
        let result = try fetchEventResult(since: startOfLast30Days, until: now)
        let summary = LocalUsageSummaryBuilder.build(
            events: result.events,
            calendar: calendar,
            now: now,
            sourcePath: databasePath
        )
        return result.isPartial ? summary.markedApproximateFallback(using: nil) : summary
    }

    func fetchSummaryAsync() async throws -> LocalUsageSummary {
        let now = nowProvider()
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let result = try await fetchEventResultAsync(since: start, until: now)
        let summary = LocalUsageSummaryBuilder.build(events: result.events, calendar: calendar, now: now, sourcePath: databasePath)
        return result.isPartial ? summary.markedApproximateFallback(using: nil) : summary
    }

    struct EventResult: Sendable {
        enum Source: Sendable { case dashboard, local }
        var events: [LocalUsageEvent]
        var source: Source
        var isPartial: Bool
        var diagnostics: [String]
    }

    func fetchEvents(since: Date, until: Date? = nil) throws -> [LocalUsageEvent] {
        try fetchEventResult(since: since, until: until).events
    }

    func fetchEventResult(since: Date, until: Date? = nil) throws -> EventResult {
        try Task.checkCancellation()
        let end = until ?? nowProvider()
        let local = readLocalEvents(since: since, until: end).filter { $0.totalTokens > 0 }
        if let auth = loadAuth() {
            do {
                let result: CursorDashboardUsageClient.FetchResult
                if let client = dashboardFetcher as? CursorDashboardUsageClient {
                    result = try client.fetchResult(since: since, until: end, auth: auth)
                } else {
                    result = .init(events: try dashboardFetcher.fetchUsageEvents(since: since, until: end, auth: auth), isPartial: false, failureDescription: nil)
                }
                if !result.events.isEmpty {
                    return EventResult(events: result.events.filter { $0.eventAt >= since && $0.eventAt < end },
                                       source: .dashboard, isPartial: result.isPartial,
                                       diagnostics: result.isPartial ? ["Cursor dashboard 结果不完整"] : [])
                }
                return EventResult(events: local, source: .local, isPartial: true,
                                   diagnostics: ["Cursor dashboard 无有效事件，使用本地日志（结果可能不完整）"])
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                return EventResult(events: local, source: .local, isPartial: true,
                                   diagnostics: ["Cursor dashboard 请求失败，使用本地日志"])
            }
        }
        return EventResult(events: local, source: .local, isPartial: true,
                           diagnostics: ["Cursor 仅使用本地事件，未验证 dashboard 完整性"])
    }

    func fetchEventResultAsync(since: Date, until: Date? = nil) async throws -> EventResult {
        try Task.checkCancellation()
        let end = until ?? nowProvider()
        let worker = Task.detached(priority: .utility) { [self] in
            (readLocalEvents(since: since, until: end), loadAuth())
        }
        let (local, auth) = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let auth else {
            return EventResult(events: local, source: .local, isPartial: true,
                               diagnostics: ["Cursor 仅使用本地事件，未验证 dashboard 完整性"])
        }
        do {
            let result: CursorDashboardUsageClient.FetchResult
            if let client = dashboardFetcher as? CursorDashboardUsageClient {
                result = try await client.fetchResultAsync(since: since, until: end, auth: auth)
            } else {
                result = .init(events: try dashboardFetcher.fetchUsageEvents(since: since, until: end, auth: auth), isPartial: false, failureDescription: nil)
            }
            guard !result.events.isEmpty else {
                return EventResult(events: local, source: .local, isPartial: true, diagnostics: ["Cursor dashboard 无有效事件，使用本地日志（结果可能不完整）"])
            }
            return EventResult(events: result.events.filter { $0.eventAt >= since && $0.eventAt < end },
                source: .dashboard, isPartial: result.isPartial, diagnostics: result.isPartial ? ["Cursor dashboard 结果不完整"] : [])
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return EventResult(events: local, source: .local, isPartial: true, diagnostics: ["Cursor dashboard 请求失败，使用本地日志"])
        }
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
        while !Task.isCancelled && sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(statement, 0),
                  let valuePointer = sqlite3_column_text(statement, 1) else {
                continue
            }
            rows.append((String(cString: keyPointer), String(cString: valuePointer)))
        }
        return rows
    }
}
