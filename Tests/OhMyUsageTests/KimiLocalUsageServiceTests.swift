import Foundation
import XCTest
@testable import OhMyUsage

final class KimiLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var sessionsRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Fail fast instead of hanging the full suite if filesystem/cache stalls.
        executionTimeAllowance = 15
        KimiLocalUsageService.clearCachesForTesting()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kimi-local-usage-tests-\(UUID().uuidString)", isDirectory: true)
        sessionsRoot = temporaryDirectory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        KimiLocalUsageService.clearCachesForTesting()
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchSummaryParsesStatusUpdateAndUsesPositiveDelta() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let todayBase = now.timeIntervalSince1970 - (2 * 60 * 60)
        let yesterdayBase = now.timeIntervalSince1970 - (26 * 60 * 60)
        try writeWireFile(
            relativePath: "tenant-1/session-a/wire.jsonl",
            lines: [
                statusUpdateLine(
                    timestamp: todayBase,
                    inputOther: 100,
                    output: 20,
                    cacheRead: 0,
                    messageID: "m1"
                ),
                statusUpdateLine( // duplicated snapshot: should be deduped
                    timestamp: todayBase,
                    inputOther: 100,
                    output: 20,
                    cacheRead: 0,
                    messageID: "m1"
                ),
                statusUpdateLine(
                    timestamp: todayBase + 100,
                    inputOther: 120,
                    output: 30,
                    cacheRead: 0,
                    messageID: "m2"
                ),
                statusUpdateLine( // decrease: ignored for delta, but baseline resets
                    timestamp: todayBase + 200,
                    inputOther: 80,
                    output: 20,
                    cacheRead: 0,
                    messageID: "m3"
                ),
                statusUpdateLine(
                    timestamp: todayBase + 300,
                    inputOther: 110,
                    output: 20,
                    cacheRead: 0,
                    messageID: "m4"
                )
            ]
        )
        try writeWireFile(
            relativePath: "tenant-1/session-b/wire.jsonl",
            lines: [
                statusUpdateLine(
                    timestamp: yesterdayBase,
                    inputOther: 70,
                    output: 20,
                    cacheRead: 0,
                    messageID: "m5"
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = KimiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultSessionsRootPath: sessionsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(summary.today.totalTokens, 180)
        XCTAssertEqual(summary.today.responses, 3)
        XCTAssertEqual(summary.today.inputTokens, 150)
        XCTAssertEqual(summary.today.outputTokens, 30)
        XCTAssertEqual(summary.today.cacheReadTokens, 0)
        XCTAssertEqual(summary.today.cacheWriteTokens, 0)
        XCTAssertEqual(summary.yesterday.totalTokens, 90)
        XCTAssertEqual(summary.yesterday.responses, 1)
        XCTAssertEqual(summary.yesterday.inputTokens, 70)
        XCTAssertEqual(summary.yesterday.outputTokens, 20)
        XCTAssertEqual(summary.last30Days.totalTokens, 270)
        XCTAssertEqual(summary.last30Days.responses, 4)
        XCTAssertEqual(summary.hourly24.count, 24)
        XCTAssertEqual(summary.daily7.count, 7)
    }

    func testFetchSummaryCurrentScopeFallsBackToAllAccounts() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeWireFile(
            relativePath: "tenant-2/session-c/wire.jsonl",
            lines: [
                statusUpdateLine(
                    timestamp: now.timeIntervalSince1970 - (1 * 60 * 60),
                    inputOther: 20,
                    output: 10,
                    cacheRead: 0,
                    messageID: "m6"
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = KimiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultSessionsRootPath: sessionsRoot.path
        )

        let allSummary = try service.fetchSummary(scope: .allAccounts)
        let currentSummary = try service.fetchSummary(scope: .currentAccount)

        XCTAssertEqual(currentSummary.today.totalTokens, allSummary.today.totalTokens)
        XCTAssertEqual(currentSummary.today.responses, allSummary.today.responses)
    }

    func testFetchEventsUsesPreWindowSnapshotAsDeltaBaseline() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let windowStart = now.addingTimeInterval(-2 * 60 * 60)
        try writeWireFile(
            relativePath: "tenant-window/session-window/wire.jsonl",
            lines: [
                statusUpdateLine(
                    timestamp: windowStart.timeIntervalSince1970 - 3_600,
                    inputOther: 1_000,
                    output: 200,
                    cacheRead: 0,
                    messageID: "old"
                ),
                statusUpdateLine(
                    timestamp: windowStart.timeIntervalSince1970 + 60,
                    inputOther: 1_050,
                    output: 220,
                    cacheRead: 0,
                    messageID: "new"
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = KimiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultSessionsRootPath: sessionsRoot.path
        )

        let events = try service.fetchEvents(scope: .allAccounts, since: windowStart)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.totalTokens, 70)
        XCTAssertEqual(events.first?.inputTokens, 50)
        XCTAssertEqual(events.first?.outputTokens, 20)
    }

    func testFetchSummaryReusesUnchangedWireFileCacheAndRefreshesAfterChange() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let timestamp = now.timeIntervalSince1970 - (60 * 60)
        let relativePath = "tenant-cache/session-cache/wire.jsonl"
        try writeWireFile(
            relativePath: relativePath,
            lines: [
                statusUpdateLine(
                    timestamp: timestamp,
                    inputOther: 20,
                    output: 10,
                    cacheRead: 0,
                    messageID: "m-cache-1"
                )
            ]
        )

        var parseCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = KimiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultSessionsRootPath: sessionsRoot.path,
            onWireFileParsed: { _ in parseCount += 1 }
        )

        let first = try service.fetchSummary(scope: .allAccounts)
        let second = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(first.today.totalTokens, 30)
        XCTAssertEqual(second.today.totalTokens, 30)
        XCTAssertEqual(parseCount, 1)

        try writeWireFile(
            relativePath: relativePath,
            lines: [
                statusUpdateLine(
                    timestamp: timestamp,
                    inputOther: 20,
                    output: 10,
                    cacheRead: 0,
                    messageID: "m-cache-1"
                ),
                statusUpdateLine(
                    timestamp: timestamp + 120,
                    inputOther: 40,
                    output: 10,
                    cacheRead: 0,
                    messageID: "m-cache-2"
                )
            ]
        )

        let refreshed = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(refreshed.today.totalTokens, 50)
        XCTAssertEqual(parseCount, 2)
    }

    func testFetchSummaryParsesV2UsageRecordWireFormat() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let todayMs = (now.timeIntervalSince1970 - (2 * 60 * 60)) * 1000
        let yesterdayMs = (now.timeIntervalSince1970 - (26 * 60 * 60)) * 1000

        try writeWireFile(
            relativePath: "session-v2/agents/main/wire.jsonl",
            lines: [
                jsonLine(["type": "metadata", "protocol_version": "1.5", "created_at": todayMs]),
                jsonLine([
                    "type": "usage.record",
                    "model": "kimi-k2",
                    "usage": ["inputOther": 100, "output": 20, "inputCacheRead": 30, "inputCacheCreation": 10],
                    "usageScope": "turn",
                    "time": todayMs
                ]),
                jsonLine([
                    "type": "usage.record",
                    "model": "kimi-k2",
                    "usage": ["inputOther": 50, "output": 10, "inputCacheRead": 0, "inputCacheCreation": 0],
                    "usageScope": "session",
                    "time": todayMs + 120_000
                ])
            ]
        )
        try writeWireFile(
            relativePath: "session-v2b/wire.jsonl",
            lines: [
                jsonLine([
                    "type": "usage.record",
                    "model": "kimi-k2",
                    "usage": ["inputOther": 70, "output": 20, "inputCacheRead": 0, "inputCacheCreation": 0],
                    "time": yesterdayMs
                ])
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = KimiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultSessionsRootPath: sessionsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)

        // v2 records are per-call deltas and must be summed as-is.
        XCTAssertEqual(summary.today.totalTokens, 220)
        XCTAssertEqual(summary.today.responses, 2)
        XCTAssertEqual(summary.today.inputTokens, 150)
        XCTAssertEqual(summary.today.outputTokens, 30)
        XCTAssertEqual(summary.today.cacheReadTokens, 30)
        XCTAssertEqual(summary.today.cacheWriteTokens, 10)
        XCTAssertEqual(summary.yesterday.totalTokens, 90)
        XCTAssertEqual(summary.yesterday.responses, 1)
        XCTAssertEqual(summary.last30Days.totalTokens, 310)
        XCTAssertEqual(summary.last30Days.responses, 3)
    }

    private func writeWireFile(relativePath: String, lines: [String]) throws {
        let fileURL = sessionsRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func statusUpdateLine(
        timestamp: Double,
        inputOther: Int,
        output: Int,
        cacheRead: Int,
        messageID: String
    ) -> String {
        jsonLine([
            "timestamp": timestamp,
            "message": [
                "type": "StatusUpdate",
                "payload": [
                    "token_usage": [
                        "input_other": inputOther,
                        "output": output,
                        "input_cache_read": cacheRead,
                        "input_cache_creation": 0
                    ],
                    "message_id": messageID
                ]
            ]
        ])
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "KimiLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
