import Foundation
import XCTest
import OhMyUsageApplication
@testable import OhMyUsage

final class ClaudeLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaultProjectsRoot: URL!
    private var configADirectory: URL!
    private var configBDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-local-usage-tests-\(UUID().uuidString)", isDirectory: true)
        defaultProjectsRoot = temporaryDirectory.appendingPathComponent("default-projects", isDirectory: true)
        configADirectory = temporaryDirectory.appendingPathComponent("config-a", isDirectory: true)
        configBDirectory = temporaryDirectory.appendingPathComponent("config-b", isDirectory: true)

        try FileManager.default.createDirectory(at: defaultProjectsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configADirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configBDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchSummaryParsesUsageAndDedupesDuplicateAssistantMessage() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "workspace-a/session-a.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T10:00:00Z",
                    sessionID: "session-a",
                    uuid: "line-1",
                    messageID: "msg-1",
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 5,
                    cacheCreation: 3,
                    cacheRead: 2
                ),
                assistantLine(
                    timestamp: "2026-04-18T10:00:01Z",
                    sessionID: "session-a",
                    uuid: "line-2",
                    messageID: "msg-1", // duplicate assistant message id
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 7,
                    cacheCreation: 3,
                    cacheRead: 2
                ),
                assistantLine(
                    timestamp: "2026-04-17T11:00:00Z",
                    sessionID: "session-a",
                    uuid: "line-3",
                    messageID: "msg-2",
                    model: "claude-opus-4",
                    input: 12,
                    output: 8,
                    cacheCreation: 4,
                    cacheRead: 6
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(summary.today.totalTokens, 22)
        XCTAssertEqual(summary.today.responses, 1)
        XCTAssertEqual(summary.today.inputTokens, 10)
        XCTAssertEqual(summary.today.outputTokens, 7)
        XCTAssertEqual(summary.today.cacheWriteTokens, 3)
        XCTAssertEqual(summary.today.cacheReadTokens, 2)
        XCTAssertEqual(summary.yesterday.totalTokens, 30)
        XCTAssertEqual(summary.yesterday.responses, 1)
        XCTAssertEqual(summary.yesterday.inputTokens, 12)
        XCTAssertEqual(summary.yesterday.outputTokens, 8)
        XCTAssertEqual(summary.yesterday.cacheWriteTokens, 4)
        XCTAssertEqual(summary.yesterday.cacheReadTokens, 6)
        XCTAssertEqual(summary.last30Days.totalTokens, 52)
        XCTAssertEqual(summary.last30Days.responses, 2)
        XCTAssertEqual(summary.hourly24.count, 24)
        XCTAssertEqual(summary.daily7.count, 7)
    }

    func testFetchSummaryCurrentAndAllScopesUseExpectedRoots() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "default/default.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:00:00Z",
                    sessionID: "default-session",
                    uuid: "default-line",
                    messageID: "default-msg",
                    model: "claude-sonnet-4-6",
                    input: 4,
                    output: 4,
                    cacheCreation: 1,
                    cacheRead: 1
                )
            ]
        )
        try writeProjectFile(
            root: configADirectory.appendingPathComponent("projects", isDirectory: true),
            relativePath: "a/a.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:10:00Z",
                    sessionID: "a-session",
                    uuid: "a-line",
                    messageID: "a-msg",
                    model: "claude-sonnet-4-6",
                    input: 8,
                    output: 8,
                    cacheCreation: 4,
                    cacheRead: 5
                )
            ]
        )
        try writeProjectFile(
            root: configBDirectory.appendingPathComponent("projects", isDirectory: true),
            relativePath: "b/b.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:20:00Z",
                    sessionID: "b-session",
                    uuid: "b-line",
                    messageID: "b-msg",
                    model: "claude-opus-4",
                    input: 9,
                    output: 10,
                    cacheCreation: 3,
                    cacheRead: 4
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let currentSummary = try service.fetchSummary(
            scope: .currentAccount,
            currentConfigDir: configADirectory.path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(currentSummary.today.totalTokens, 25)
        XCTAssertEqual(currentSummary.today.responses, 1)

        let allSummary = try service.fetchSummary(
            scope: .allAccounts,
            currentConfigDir: configADirectory.path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(allSummary.today.totalTokens, 61)
        XCTAssertEqual(allSummary.today.responses, 3)

        let fallbackSummary = try service.fetchSummary(
            scope: .currentAccount,
            currentConfigDir: temporaryDirectory.appendingPathComponent("missing-config", isDirectory: true).path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(fallbackSummary.today.totalTokens, 10)
        XCTAssertEqual(fallbackSummary.today.responses, 1)
    }

    func testFetchSummarySkipsOversizedLineAndKeepsFollowingEvents() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let oversizedLine = String(repeating: "x", count: RuntimeDiagnosticsLimits.jsonlMaxLineBytes + 16_384)
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "workspace-oversized/session.jsonl",
            lines: [
                oversizedLine,
                assistantLine(
                    timestamp: "2026-04-18T10:30:00Z",
                    sessionID: "oversized-session",
                    uuid: "oversized-line-ok",
                    messageID: "oversized-msg-1",
                    model: "claude-sonnet-4-6",
                    input: 6,
                    output: 4,
                    cacheCreation: 1,
                    cacheRead: 1
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)
        XCTAssertEqual(summary.today.totalTokens, 12)
        XCTAssertEqual(summary.today.responses, 1)
    }

    func testFetchSummaryReusesUnchangedProjectFileCacheAndRefreshesAfterChange() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let relativePath = "workspace-cache/session-cache.jsonl"
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: relativePath,
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T10:00:00Z",
                    sessionID: "session-cache",
                    uuid: "line-1",
                    messageID: "msg-1",
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 5,
                    cacheCreation: 0,
                    cacheRead: 0
                )
            ]
        )

        var parseCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path,
            onProjectFileParsed: { _ in parseCount += 1 }
        )

        let first = try service.fetchSummary(scope: .allAccounts)
        let second = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(first.today.totalTokens, 15)
        XCTAssertEqual(second.today.totalTokens, 15)
        XCTAssertEqual(parseCount, 1)

        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: relativePath,
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T10:00:00Z",
                    sessionID: "session-cache",
                    uuid: "line-1",
                    messageID: "msg-1",
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 5,
                    cacheCreation: 0,
                    cacheRead: 0
                ),
                assistantLine(
                    timestamp: "2026-04-18T10:05:00Z",
                    sessionID: "session-cache",
                    uuid: "line-2",
                    messageID: "msg-2",
                    model: "claude-sonnet-4-6",
                    input: 3,
                    output: 2,
                    cacheCreation: 0,
                    cacheRead: 0
                )
            ]
        )

        let refreshed = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(refreshed.today.totalTokens, 20)
        XCTAssertEqual(parseCount, 2)
    }

    func testParsedClaudeUsageExcludesRawChatContent() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "workspace-privacy/session-privacy.jsonl",
            lines: [
                // Raw conversation lines that the usage scanner must ignore.
                jsonLine([
                    "timestamp": "2026-04-18T10:00:00Z",
                    "sessionId": "session-privacy",
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": "SECRET_CLAUDE_USER_CHAT_5K"
                    ]
                ]),
                jsonLine([
                    "timestamp": "2026-04-18T10:04:00Z",
                    "sessionId": "session-privacy",
                    "type": "assistant",
                    "message": [
                        "id": "msg-privacy-think",
                        "model": "claude-sonnet-4-6",
                        "content": [
                            ["type": "thinking", "thinking": "SECRET_CLAUDE_REASONING_NOTE_2M"]
                        ],
                        "usage": [
                            "input_tokens": 1,
                            "output_tokens": 1
                        ]
                    ]
                ]),
                jsonLine([
                    "timestamp": "2026-04-18T10:05:00Z",
                    "sessionId": "session-privacy",
                    "uuid": "line-privacy-1",
                    "type": "assistant",
                    "message": [
                        "id": "msg-privacy-1",
                        "model": "claude-sonnet-4-6",
                        "content": [
                            ["type": "text", "text": "SECRET_CLAUDE_REPLY_CHAT_8Z"]
                        ],
                        "usage": [
                            "input_tokens": 7,
                            "output_tokens": 4,
                            "cache_creation_input_tokens": 2,
                            "cache_read_input_tokens": 1
                        ]
                    ]
                ])
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)
        let events = try service.fetchEvents(
            scope: .allAccounts,
            since: try fixedDate("2026-04-11T00:00:00Z")
        )
        // Prove the usage pipeline actually parsed the assistant usage events.
        XCTAssertEqual(summary.today.totalTokens, 16)
        XCTAssertEqual(summary.today.responses, 2)
        XCTAssertEqual(events.count, 2)

        var summaryStrings: [String] = []
        Self.collectStrings(from: summary, into: &summaryStrings)
        var eventStrings: [String] = []
        Self.collectStrings(from: events, into: &eventStrings)

        for sentinel in ["SECRET_CLAUDE_USER_CHAT_5K", "SECRET_CLAUDE_REPLY_CHAT_8Z", "SECRET_CLAUDE_REASONING_NOTE_2M"] {
            XCTAssertFalse(
                summaryStrings.contains { $0.contains(sentinel) },
                "summary must not contain raw chat content (\(sentinel))"
            )
            XCTAssertFalse(
                eventStrings.contains { $0.contains(sentinel) },
                "parsed events must not contain raw chat content (\(sentinel))"
            )
        }

        // `LocalUsageSummary` is the Codable type persisted into the history cache;
        // its encoded payload must not contain raw chat content either.
        let persistedPayload = String(data: try JSONEncoder().encode(summary), encoding: .utf8)
        for sentinel in ["SECRET_CLAUDE_USER_CHAT_5K", "SECRET_CLAUDE_REPLY_CHAT_8Z", "SECRET_CLAUDE_REASONING_NOTE_2M"] {
            XCTAssertFalse(
                persistedPayload?.contains(sentinel) ?? true,
                "persisted summary payload must not contain raw chat content (\(sentinel))"
            )
        }
    }

    @MainActor
    func testPersistedLocalUsageHistoryCacheExcludesRawChatContent() async throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "workspace-cache-privacy/session-cache-privacy.jsonl",
            lines: [
                jsonLine([
                    "timestamp": "2026-04-18T10:00:00Z",
                    "sessionId": "session-cache-privacy",
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": "SECRET_CLAUDE_CACHE_PROMPT_6N"
                    ]
                ]),
                jsonLine([
                    "timestamp": "2026-04-18T10:05:00Z",
                    "sessionId": "session-cache-privacy",
                    "uuid": "line-cache-privacy-1",
                    "type": "assistant",
                    "message": [
                        "id": "msg-cache-privacy-1",
                        "model": "claude-sonnet-4-6",
                        "content": [
                            ["type": "text", "text": "SECRET_CLAUDE_CACHE_REPLY_3P"]
                        ],
                        "usage": [
                            "input_tokens": 7,
                            "output_tokens": 4
                        ]
                    ]
                ])
            ]
        )

        let cacheRoot = temporaryDirectory.appendingPathComponent("cache-root", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let fingerprint = LocalUsageSourceFingerprint(
            roots: [defaultProjectsRoot.path],
            fileCount: 1,
            totalSize: 128,
            latestModificationTime: now
        )
        var calendarBuilder = Calendar(identifier: .gregorian)
        calendarBuilder.timeZone = TimeZone(secondsFromGMT: 0)!
        let calendar = calendarBuilder
        let nowValue = now
        let projectsRootPath = defaultProjectsRoot.path
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: cacheRoot,
            nowProvider: { nowValue }
        )
        let query = LocalUsageHistoryQuery(
            providerType: .claude,
            providerID: "claude-official",
            scope: .allAccounts,
            identityKey: "cache-privacy"
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                let summary = try ClaudeLocalUsageService(
                    calendar: calendar,
                    nowProvider: { nowValue },
                    defaultClaudeRootPath: projectsRootPath
                ).fetchSummary(scope: .allAccounts)
                return LocalUsageHistoryLoadResult(summary: summary, sourceFingerprint: fingerprint)
            },
            onStateChange: {}
        )
        try await Self.waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 11 && !$0.isLoading
        }

        let cacheURL = cacheRoot
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
        let payload = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertTrue(payload.contains("totalTokens"), "history cache should persist aggregate token fields")
        XCTAssertFalse(payload.contains("SECRET_CLAUDE_CACHE_PROMPT_6N"), "history cache must not contain raw chat content")
        XCTAssertFalse(payload.contains("SECRET_CLAUDE_CACHE_REPLY_3P"), "history cache must not contain raw chat content")
    }

    private func writeProjectFile(root: URL, relativePath: String, lines: [String]) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func assistantLine(
        timestamp: String,
        sessionID: String,
        uuid: String,
        messageID: String,
        model: String,
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> String {
        jsonLine([
            "timestamp": timestamp,
            "sessionId": sessionID,
            "uuid": uuid,
            "type": "assistant",
            "message": [
                "id": messageID,
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreation,
                    "cache_read_input_tokens": cacheRead
                ]
            ]
        ])
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private static func collectStrings(from value: Any, into output: inout [String]) {
        if let string = value as? String {
            output.append(string)
            return
        }
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            collectStrings(from: child.value, into: &output)
        }
        if let superclassMirror = mirror.superclassMirror {
            collectStrings(from: superclassMirror, into: &output)
        }
    }

    @MainActor private static func waitUntil(
        repository: LocalUsageHistoryRepository,
        query: LocalUsageHistoryQuery,
        timeout: TimeInterval = 5,
        predicate: (LocalUsageHistoryState) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(repository.snapshot(for: query)) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for local usage history repository state")
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "ClaudeLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
