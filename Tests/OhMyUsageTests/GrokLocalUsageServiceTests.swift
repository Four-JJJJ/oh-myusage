import Foundation
import XCTest
@testable import OhMyUsage

final class GrokLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grok-local-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchEventsEstimatesTurnTokensFromUpdatesJSONL() throws {
        let sessionURL = temporaryDirectory
            .appendingPathComponent("encoded-cwd", isDirectory: true)
            .appendingPathComponent("session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        try writeJSON(
            [
                "current_model_id": "grok-4",
                "updated_at": "2026-05-16T11:00:00Z"
            ],
            to: sessionURL.appendingPathComponent("summary.json")
        )
        try writeLines(
            [
                jsonLine([
                    "timestamp": "2026-05-16T10:00:00Z",
                    "params": ["_meta": ["promptId": "p1", "totalTokens": 100]]
                ]),
                jsonLine([
                    "timestamp": "2026-05-16T10:01:00Z",
                    "params": ["_meta": ["promptId": "p1", "totalTokens": 140]]
                ]),
                jsonLine([
                    "timestamp": "2026-05-16T10:05:00Z",
                    "params": ["_meta": ["promptId": "p2", "totalTokens": 140]]
                ]),
                jsonLine([
                    "timestamp": "2026-05-16T10:06:00Z",
                    "params": ["_meta": ["promptId": "p2", "totalTokens": 155]]
                ])
            ],
            to: sessionURL.appendingPathComponent("updates.jsonl")
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try fixedDate("2026-05-16T12:00:00Z")
        let service = GrokLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            sessionsRootPath: temporaryDirectory.path
        )

        let events = try service.fetchEvents(since: try fixedDate("2026-05-16T00:00:00Z"))
            .sorted { $0.eventAt < $1.eventAt }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].inputTokens, 100)
        XCTAssertEqual(events[0].outputTokens, 40)
        XCTAssertEqual(events[1].inputTokens, 140)
        XCTAssertEqual(events[1].outputTokens, 15)
        XCTAssertEqual(events.map(\.modelID), ["grok-4", "grok-4"])
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try data.write(to: url)
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
            throw NSError(domain: "GrokLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
