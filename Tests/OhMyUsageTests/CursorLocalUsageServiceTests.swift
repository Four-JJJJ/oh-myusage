import Foundation
import XCTest
@testable import OhMyUsage
import SQLite3

final class CursorLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cursor-local-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchEventsReadsNonZeroBubbleTokensAndPrefersDashboardFetcher() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("state.vscdb")
        try createCursorDatabase(at: databaseURL.path)
        let now = try fixedDate("2026-05-16T12:00:00Z")
        try insertBubble(
            key: "bubbleId:session-a:bubble-local",
            createdAt: "2026-05-16T10:00:00Z",
            input: 40,
            output: 10,
            at: databaseURL.path
        )
        try insertAccessToken("eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VyXzEyMyJ9.sig", at: databaseURL.path)

        let fetcher = StubCursorDashboardFetcher(events: [
            LocalUsageEvent(
                signature: "cursor|remote-1",
                eventAt: now.addingTimeInterval(-1_800),
                modelID: "composer-2",
                totalTokens: 90,
                inputTokens: 70,
                outputTokens: 20
            )
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CursorLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            databasePath: databaseURL.path,
            dashboardFetcher: fetcher
        )

        let events = try service.fetchEvents(since: now.addingTimeInterval(-3_600), until: now)
        XCTAssertEqual(events.map(\.signature), ["cursor|remote-1"])
        XCTAssertEqual(events.first?.totalTokens, 90)
    }

    func testFetchEventsFallsBackToLocalTokensWhenDashboardIsEmpty() async throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("state.vscdb")
        try createCursorDatabase(at: databaseURL.path)
        let now = try fixedDate("2026-05-16T12:00:00Z")
        try insertBubble(
            key: "bubbleId:session-a:bubble-local",
            createdAt: "2026-05-16T10:00:00Z",
            input: 40,
            output: 10,
            at: databaseURL.path
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CursorLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            databasePath: databaseURL.path,
            dashboardFetcher: StubCursorDashboardFetcher(events: [])
        )

        let events = try service.fetchEvents(since: now.addingTimeInterval(-8_000), until: now)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.inputTokens, 40)
        XCTAssertEqual(events.first?.outputTokens, 10)
        XCTAssertEqual(events.first?.modelID, "composer-2")
        XCTAssertTrue(try service.fetchSummary().isApproximateFallback)
        let asyncSummary = try await service.fetchSummaryAsync()
        XCTAssertTrue(asyncSummary.isApproximateFallback)
    }

    func testDashboardUsesRawRowCountAfterFiltering() throws {
        let valid: [String: Any] = ["id": "first", "timestamp": "2026-05-16T10:00:00Z", "tokenUsage": ["inputTokens": 1]]
        var rows = Array(repeating: valid, count: 199)
        rows.append(["tokenUsage": ["inputTokens": 0]])
        let first = try JSONSerialization.data(withJSONObject: ["usageEvents": rows])
        let last = try JSONSerialization.data(withJSONObject: ["usageEvents": [
            ["id": "second", "timestamp": "2026-05-16T11:00:00Z", "tokenUsage": ["inputTokens": 2]]
        ]])
        let client = CursorDashboardUsageClient(requestSender: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            return (body["page"] as? Int) == 1 ? first : last
        })
        let result = try client.fetchResult(since: .distantPast, until: .distantFuture,
                                            auth: .init(databasePath: "fixture", accessToken: "fixture", userID: "fixture"))
        XCTAssertEqual(result.events.count, 200)
        XCTAssertEqual(result.events.last?.signature, "cursor|second")
        XCTAssertFalse(result.isPartial)
    }

    func testDashboardFullInvalidRowsStillRequestNextPage() throws {
        let first = try JSONSerialization.data(withJSONObject: ["usageEvents": Array(repeating: ["tokenUsage": ["inputTokens": 0]], count: 200)])
        let last = try JSONSerialization.data(withJSONObject: ["usageEvents": [["id": "next", "timestamp": "2026-05-16T11:00:00Z", "tokenUsage": ["inputTokens": 1]]]])
        let client = CursorDashboardUsageClient(requestSender: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            return (body["page"] as? Int) == 1 ? first : last
        })
        let result = try client.fetchResult(since: .distantPast, until: .distantFuture,
                                            auth: .init(databasePath: "fixture", accessToken: "fixture", userID: "fixture"))
        XCTAssertEqual(result.events.count, 1)
        XCTAssertFalse(result.isPartial)
    }

    func testDashboardRepeatedPageAndLimitReportPartial() throws {
        let page = try JSONSerialization.data(withJSONObject: ["usageEvents": Array(repeating: ["id": "one", "timestamp": "2026-05-16T11:00:00Z", "tokenUsage": ["inputTokens": 1]], count: 200)])
        let auth = CursorLocalAuth(databasePath: "fixture", accessToken: "fixture", userID: "fixture")
        let repeated = try CursorDashboardUsageClient(requestSender: { _ in page })
            .fetchResult(since: .distantPast, until: .distantFuture, auth: auth)
        XCTAssertTrue(repeated.isPartial)
        XCTAssertEqual(repeated.events.count, 200)
        let limited = try CursorDashboardUsageClient(maxPages: 1, requestSender: { _ in page })
            .fetchResult(since: .distantPast, until: .distantFuture, auth: auth)
        XCTAssertTrue(limited.isPartial)
    }

    func testAsyncDashboardCancellationStopsRequests() async throws {
        let client = CursorDashboardUsageClient(asyncRequestSender: { _ in
            try await Task.sleep(for: .seconds(20))
            return Data()
        })
        let task = Task {
            try await client.fetchResultAsync(since: .distantPast, until: .distantFuture,
                auth: .init(databasePath: "fixture", accessToken: "fixture", userID: "fixture"))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private actor RequestProbe {
        var count = 0
        func increment() { count += 1 }
    }

    func testAsyncEquivalentRequestsShareFlightAndOneCancelledWaiterDoesNotCancelOther() async throws {
        let probe = RequestProbe()
        let data = try JSONSerialization.data(withJSONObject: ["usageEvents": [["id": "one", "timestamp": "2026-05-16T11:00:00Z", "tokenUsage": ["inputTokens": 1]]]])
        let client = CursorDashboardUsageClient(asyncRequestSender: { _ in
            await probe.increment()
            try await Task.sleep(for: .milliseconds(150))
            return data
        })
        let auth = CursorLocalAuth(databasePath: "fixture", accessToken: "fixture", userID: "fixture")
        let first = Task { try await client.fetchResultAsync(since: .distantPast, until: .distantFuture, auth: auth) }
        let second = Task { try await client.fetchResultAsync(since: .distantPast, until: .distantFuture, auth: auth) }
        try await Task.sleep(for: .milliseconds(50))
        let cancelledAt = Date()
        first.cancel()
        do { _ = try await first.value; XCTFail("expected cancelled waiter") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 0.08)
        let surviving = try await second.value
        XCTAssertEqual(surviving.events.count, 1)
        do { _ = try await first.value; XCTFail("expected cancelled waiter") } catch { XCTAssertTrue(error is CancellationError) }
        let count = await probe.count
        XCTAssertEqual(count, 1)
    }

    func testInvalidAndLaterFailureAreNotReportedAsComplete() throws {
        XCTAssertThrowsError(try CursorDashboardUsageClient.parsePage(Data("{}".utf8)))
        let data = try JSONSerialization.data(withJSONObject: ["usageEvents": Array(repeating: ["id": "one", "timestamp": "2026-05-16T11:00:00Z", "tokenUsage": ["inputTokens": 1]], count: 200)])
        let client = CursorDashboardUsageClient(requestSender: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            if (body["page"] as? Int) == 1 { return data }
            throw URLError(.notConnectedToInternet)
        })
        let result = try client.fetchResult(since: .distantPast, until: .distantFuture,
            auth: .init(databasePath: "fixture", accessToken: "fixture", userID: "fixture"))
        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.events.count, 200)
        let empty = try CursorDashboardUsageClient(requestSender: { _ in Data("{\"usageEvents\":[]}".utf8) })
            .fetchResult(since: .distantPast, until: .distantFuture,
                auth: .init(databasePath: "fixture", accessToken: "fixture", userID: "fixture"))
        XCTAssertTrue(empty.events.isEmpty)
        XCTAssertFalse(empty.isPartial)
    }

    private func createCursorDatabase(at path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 1)
        }
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE cursorDiskKV (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 2)
        }
    }

    private func insertBubble(
        key: String,
        createdAt: String,
        input: Int,
        output: Int,
        at path: String
    ) throws {
        let payload: [String: Any] = [
            "type": 2,
            "createdAt": createdAt,
            "modelName": "composer-2",
            "tokenCount": [
                "inputTokens": input,
                "outputTokens": output
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8)!
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 3)
        }
        defer { sqlite3_close(database) }
        let escapedJSON = json.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO cursorDiskKV(key, value) VALUES ('\(key)', '\(escapedJSON)');"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 4)
        }
    }

    private func insertAccessToken(_ token: String, at path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 6)
        }
        defer { sqlite3_close(database) }
        let escaped = token.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO ItemTable(key, value) VALUES ('cursorAuth/accessToken', '\(escaped)');"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 7)
        }
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "CursorLocalUsageServiceTests", code: 5)
        }
        return date
    }
}

private struct StubCursorDashboardFetcher: CursorDashboardUsageFetching {
    var events: [LocalUsageEvent]

    func fetchUsageEvents(since: Date, until: Date, auth: CursorLocalAuth) throws -> [LocalUsageEvent] {
        _ = (since, until, auth)
        return events
    }
}
