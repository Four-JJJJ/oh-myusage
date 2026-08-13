import Foundation
import XCTest
@testable import OhMyUsage

final class GeminiLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gemini-local-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchEventsParsesJSONLTokensAndSplitsCachedInput() throws {
        let chats = temporaryDirectory
            .appendingPathComponent("project-a", isDirectory: true)
            .appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try writeLines(
            [
                jsonLine(["type": "session_metadata", "sessionId": "s1"]),
                jsonLine([
                    "type": "gemini",
                    "id": "m1",
                    "timestamp": "2026-05-16T10:00:00Z",
                    "model": "gemini-2.5-pro",
                    "tokens": [
                        "input": 120,
                        "output": 30,
                        "cached": 20,
                        "thoughts": 5
                    ]
                ]),
                jsonLine([
                    "type": "message_update",
                    "id": "m1",
                    "timestamp": "2026-05-16T10:00:05Z",
                    "model": "gemini-2.5-pro",
                    "tokens": [
                        "input": 120,
                        "output": 30,
                        "cached": 20,
                        "thoughts": 5
                    ]
                ])
            ],
            to: chats.appendingPathComponent("session-s1.jsonl")
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try fixedDate("2026-05-16T12:00:00Z")
        let service = GeminiLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            tmpRootPath: temporaryDirectory.path
        )

        let events = try service.fetchEvents(since: try fixedDate("2026-05-16T00:00:00Z"))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.modelID, "gemini-2.5-pro")
        XCTAssertEqual(events.first?.inputTokens, 100)
        XCTAssertEqual(events.first?.outputTokens, 35)
        XCTAssertEqual(events.first?.cacheReadTokens, 20)
        XCTAssertEqual(events.first?.totalTokens, 155)
    }

    private func writeLines(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "GeminiLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
