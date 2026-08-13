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

    func testFetchEventsFallsBackToLocalTokensWhenDashboardIsEmpty() throws {
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
