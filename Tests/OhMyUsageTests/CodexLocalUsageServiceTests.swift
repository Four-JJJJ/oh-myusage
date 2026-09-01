import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class CodexLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var sessionsDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-local-usage-tests-\(UUID().uuidString)", isDirectory: true)
        sessionsDirectory = temporaryDirectory.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchSummaryAllAccountsUsesSessionTokenCountPipeline() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-a.jsonl",
            lines: [
                sessionMetaLine(id: "session-a", timestamp: "2026-04-18T07:50:00Z"),
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.4"),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 100),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 100), // duplicated snapshot
                tokenCountTotalLine(timestamp: "2026-04-18T09:00:00Z", total: 140),
                tokenCountLastLine(timestamp: "2026-04-18T10:00:00Z", last: 15)
            ]
        )

        try writeSessionFile(
            relativePath: "2026/04/17/rollout-b.jsonl",
            lines: [
                turnContextLine(timestamp: "2026-04-17T10:00:00Z", model: "gpt-5.4-mini"),
                tokenCountTotalLine(timestamp: "2026-04-17T11:00:00Z", total: 80),
                tokenCountTotalLine(timestamp: "2026-04-17T12:00:00Z", total: 100)
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(summary.today.totalTokens, 155)
        XCTAssertEqual(summary.today.responses, 3)
        XCTAssertEqual(summary.yesterday.totalTokens, 100)
        XCTAssertEqual(summary.yesterday.responses, 2)
        XCTAssertEqual(summary.last30Days.totalTokens, 255)
        XCTAssertEqual(summary.last30Days.responses, 5)
        XCTAssertEqual(summary.hourly24.count, 24)
        XCTAssertEqual(summary.daily7.count, 7)

        let todayByModel = Dictionary(uniqueKeysWithValues: summary.today.byModel.map { ($0.modelID, $0.totalTokens) })
        XCTAssertEqual(todayByModel["gpt-5.4"], 155)

        let yesterdayByModel = Dictionary(uniqueKeysWithValues: summary.yesterday.byModel.map { ($0.modelID, $0.totalTokens) })
        XCTAssertEqual(yesterdayByModel["gpt-5.4-mini"], 100)
    }

    func testFetchSummaryAllAccountsFallsBackToTurnContextModel() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-turn-context.jsonl",
            lines: [
                turnContextLine(timestamp: "2026-04-18T09:59:00Z", model: "gpt-5.4-mini"),
                tokenCountTotalLine(timestamp: "2026-04-18T10:00:00Z", total: 30, model: nil)
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(summary.today.totalTokens, 30)
        XCTAssertEqual(summary.today.responses, 1)
        XCTAssertEqual(summary.today.byModel.first?.modelID, "gpt-5.4-mini")
    }

    func testFetchSummaryAllAccountsFallsBackToUnknownModelWithoutTurnContext() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-unknown.jsonl",
            lines: [
                tokenCountLastLine(timestamp: "2026-04-18T10:00:00Z", last: 12, model: nil)
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(summary.today.totalTokens, 12)
        XCTAssertEqual(summary.today.responses, 1)

        let byModel = Dictionary(uniqueKeysWithValues: summary.today.byModel.map { ($0.modelID, $0.totalTokens) })
        XCTAssertEqual(byModel["unknown"], 12)
    }

    func testFetchSummaryAllAccountsSeparatesOpenAIStyleCachedInputComponents() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-components.jsonl",
            lines: [
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.5"),
                tokenCountUsageLine(
                    timestamp: "2026-04-18T08:05:00Z",
                    key: "total_token_usage",
                    input: 100,
                    output: 50,
                    cacheRead: 20,
                    cacheWrite: 10,
                    total: 160
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(summary.today.totalTokens, 160)
        XCTAssertEqual(summary.today.inputTokens, 80)
        XCTAssertEqual(summary.today.outputTokens, 50)
        XCTAssertEqual(summary.today.cacheReadTokens, 20)
        XCTAssertEqual(summary.today.cacheWriteTokens, 10)
    }

    func testFetchSummaryAllAccountsReusesUnchangedSessionFileCacheAndRefreshesAfterChange() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        let relativePath = "2026/04/18/cached-rollout.jsonl"
        try writeSessionFile(
            relativePath: relativePath,
            lines: [
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.4"),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 100)
            ]
        )

        var parseCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            onSessionFileParsed: { _ in parseCount += 1 }
        )

        let first = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )
        let second = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(first.today.totalTokens, 100)
        XCTAssertEqual(second.today.totalTokens, 100)
        XCTAssertEqual(parseCount, 1)

        try writeSessionFile(
            relativePath: relativePath,
            lines: [
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.4"),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 100),
                tokenCountTotalLine(timestamp: "2026-04-18T09:00:00Z", total: 160)
            ]
        )

        let refreshed = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )

        XCTAssertEqual(refreshed.today.totalTokens, 160)
        XCTAssertEqual(parseCount, 2)
    }

    func testParsedCodexUsageExcludesRawChatContent() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-chat-content.jsonl",
            lines: [
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.4"),
                // Raw conversation content lines that the usage scanner must ignore.
                jsonLine([
                    "timestamp": "2026-04-18T08:01:00Z",
                    "type": "response_item",
                    "payload": [
                        "type": "message",
                        "role": "user",
                        "content": [
                            ["type": "input_text", "text": "SECRET_CODEX_CHAT_PROMPT_3A"]
                        ]
                    ]
                ]),
                jsonLine([
                    "timestamp": "2026-04-18T08:02:00Z",
                    "type": "response_item",
                    "payload": [
                        "type": "reasoning",
                        "summary": [
                            ["type": "summary_text", "text": "SECRET_CODEX_CHAT_REASONING_6D"]
                        ]
                    ]
                ]),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 42),
                jsonLine([
                    "timestamp": "2026-04-18T08:06:00Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "agent_message",
                        "message": "SECRET_CODEX_CHAT_REPLY_9F"
                    ]
                ])
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )
        let events = try service.fetchEvents(
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts,
            since: try fixedDate("2026-04-11T00:00:00Z")
        )
        // Prove the usage pipeline actually parsed the token events.
        XCTAssertEqual(summary.today.totalTokens, 42)
        XCTAssertEqual(summary.today.responses, 1)
        XCTAssertEqual(events.count, 1)

        var summaryStrings: [String] = []
        Self.collectStrings(from: summary, into: &summaryStrings)
        var eventStrings: [String] = []
        Self.collectStrings(from: events, into: &eventStrings)

        for sentinel in ["SECRET_CODEX_CHAT_PROMPT_3A", "SECRET_CODEX_CHAT_REPLY_9F", "SECRET_CODEX_CHAT_REASONING_6D"] {
            XCTAssertFalse(
                summaryStrings.contains { $0.contains(sentinel) },
                "summary must not contain raw chat content (\(sentinel))"
            )
            XCTAssertFalse(
                eventStrings.contains { $0.contains(sentinel) },
                "parsed events must not contain raw chat content (\(sentinel))"
            )
        }

        // The history cache persists `LocalUsageSummary(codex:)`; its encoded payload
        // must not contain raw chat content either.
        let persistedPayload = String(data: try JSONEncoder().encode(LocalUsageSummary(codex: summary)), encoding: .utf8)
        for sentinel in ["SECRET_CODEX_CHAT_PROMPT_3A", "SECRET_CODEX_CHAT_REPLY_9F", "SECRET_CODEX_CHAT_REASONING_6D"] {
            XCTAssertFalse(
                persistedPayload?.contains(sentinel) ?? true,
                "persisted summary payload must not contain raw chat content (\(sentinel))"
            )
        }
    }

    @MainActor
    func testPersistedLocalUsageHistoryCacheExcludesRawChatContent() async throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeSessionFile(
            relativePath: "2026/04/18/rollout-cache-privacy.jsonl",
            lines: [
                turnContextLine(timestamp: "2026-04-18T08:00:00Z", model: "gpt-5.4"),
                jsonLine([
                    "timestamp": "2026-04-18T08:01:00Z",
                    "type": "response_item",
                    "payload": [
                        "type": "message",
                        "role": "user",
                        "content": [
                            ["type": "input_text", "text": "SECRET_CODEX_CACHE_PROMPT_4B"]
                        ]
                    ]
                ]),
                tokenCountTotalLine(timestamp: "2026-04-18T08:05:00Z", total: 37),
                jsonLine([
                    "timestamp": "2026-04-18T08:06:00Z",
                    "type": "event_msg",
                    "payload": [
                        "type": "agent_message",
                        "message": "SECRET_CODEX_CACHE_REPLY_7C"
                    ]
                ])
            ]
        )

        let cacheRoot = temporaryDirectory.appendingPathComponent("cache-root", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let fingerprint = LocalUsageSourceFingerprint(
            roots: [sessionsDirectory.path],
            fileCount: 1,
            totalSize: 128,
            latestModificationTime: now
        )
        var calendarBuilder = Calendar(identifier: .gregorian)
        calendarBuilder.timeZone = TimeZone(secondsFromGMT: 0)!
        let calendar = calendarBuilder
        let nowValue = now
        let sessionsRootPath = sessionsDirectory.path
        let repository = LocalUsageHistoryRepository(
            baseDirectoryURL: cacheRoot,
            nowProvider: { nowValue }
        )
        let query = LocalUsageHistoryQuery(
            providerType: .codex,
            providerID: "codex-official",
            scope: .allAccounts,
            identityKey: "cache-privacy"
        )

        repository.refreshIfNeeded(
            query: query,
            force: true,
            fingerprintProvider: { fingerprint },
            loader: { _ in
                let summary = try CodexLocalUsageService(
                    calendar: calendar,
                    nowProvider: { nowValue }
                ).fetchSummary(
                    sessionsRootPath: sessionsRootPath,
                    scope: .allAccounts
                )
                return LocalUsageHistoryLoadResult(
                    summary: LocalUsageSummary(codex: summary),
                    sourceFingerprint: fingerprint
                )
            },
            onStateChange: {}
        )
        try await Self.waitUntil(repository: repository, query: query) {
            $0.summary?.today.totalTokens == 37 && !$0.isLoading
        }

        let cacheURL = cacheRoot
            .appendingPathComponent("OhMyUsage", isDirectory: true)
            .appendingPathComponent("local_usage_history_cache.json")
        let payload = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertTrue(payload.contains("totalTokens"), "history cache should persist aggregate token fields")
        XCTAssertFalse(payload.contains("SECRET_CODEX_CACHE_PROMPT_4B"), "history cache must not contain raw chat content")
        XCTAssertFalse(payload.contains("SECRET_CODEX_CACHE_REPLY_7C"), "history cache must not contain raw chat content")
    }

    func testFetchSummaryCurrentAccountFiltersIdentityAndSupportsEscapedQuotes() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-a-1",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 10,
                output: 5,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-a",
                email: "A@Example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T09:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-a-2",
                eventTimestamp: "2026-04-18T09:00:00Z",
                model: "gpt-5.4-mini",
                input: 2,
                output: 3,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-a",
                email: "A@Example.com",
                escapeIdentityQuotes: true
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T08:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-b",
                eventTimestamp: "2026-04-18T08:00:00Z",
                model: "gpt-5.3-codex",
                input: 9,
                output: 1,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-b",
                email: "b@example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T07:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-no-identity",
                eventTimestamp: "2026-04-18T07:00:00Z",
                model: "gpt-5.4",
                input: 4,
                output: 1,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: nil,
                email: nil,
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let accountSummary = try service.fetchSummary(
            databasePath: databasePath,
            sessionsRootPath: sessionsDirectory.path,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(accountID: "acct-a", email: nil)
        )
        XCTAssertEqual(accountSummary.today.totalTokens, 20)
        XCTAssertEqual(accountSummary.today.responses, 2)

        let emailSummary = try service.fetchSummary(
            databasePath: databasePath,
            sessionsRootPath: sessionsDirectory.path,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(accountID: nil, email: "a@example.com")
        )
        XCTAssertEqual(emailSummary.today.totalTokens, 20)
        XCTAssertEqual(emailSummary.today.responses, 2)

        let emptyIdentitySummary = try service.fetchSummary(
            databasePath: databasePath,
            sessionsRootPath: sessionsDirectory.path,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(accountID: nil, email: nil)
        )
        XCTAssertEqual(emptyIdentitySummary.today.totalTokens, 0)
        XCTAssertEqual(emptyIdentitySummary.today.responses, 0)

        let allAccountsSummary = try service.fetchSummary(
            databasePath: databasePath,
            sessionsRootPath: sessionsDirectory.path,
            scope: .allAccounts
        )
        XCTAssertEqual(allAccountsSummary.today.totalTokens, 0)
        XCTAssertEqual(allAccountsSummary.today.responses, 0)
    }

    func testFetchSummaryCurrentAccountThrowsWhenDatabaseMissing() throws {
        let missingPath = temporaryDirectory.appendingPathComponent("missing.sqlite").path
        let service = CodexLocalUsageService()

        XCTAssertThrowsError(
            try service.fetchSummary(databasePath: missingPath, scope: .currentAccount)
        ) { error in
            guard case CodexLocalUsageServiceError.databaseNotFound(let path) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, missingPath)
        }
    }

    func testFetchSummaryCurrentAccountFallsBackToEmailWhenEventLacksAccountID() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-email-fallback",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 10,
                output: 6,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: nil,
                email: "match@example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-expected",
                email: "match@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 16)
        XCTAssertEqual(summary.today.responses, 1)
    }

    func testFetchSummaryCurrentAccountFallsBackToEmailWhenAccountIDMismatches() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:10:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-acct-mismatch-email",
                eventTimestamp: "2026-04-18T10:10:00Z",
                model: "gpt-5.4",
                input: 20,
                output: 5,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-runtime",
                email: "match@example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-selected",
                email: "match@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 25)
        XCTAssertEqual(summary.today.responses, 1)
    }

    func testFetchSummaryCurrentAccountRecoversMissingIdentityFromConversationHistory() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T09:50:00Z").timeIntervalSince1970),
            body: identityEventLogfmt(
                conversationID: "conv-recover",
                eventTimestamp: "2026-04-18T09:50:00Z",
                kind: "response.output_text.delta",
                accountID: "acct-recover",
                email: "recover@example.com"
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-recover",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 12,
                output: 8,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: nil,
                email: nil,
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-recover",
                email: "recover@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 20)
        XCTAssertEqual(summary.today.responses, 1)
        XCTAssertEqual(summary.diagnostics?.recoveredByConversationResponses, 1)
        XCTAssertEqual(summary.diagnostics?.recoveredByConversationTokens, 20)
        XCTAssertEqual(summary.diagnostics?.unattributedResponses, 0)
        XCTAssertEqual(summary.diagnostics?.unattributedTokens, 0)
    }

    func testFetchSummaryCurrentAccountUsesLatestConversationIdentityWhenConversationSwitches() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T09:30:00Z").timeIntervalSince1970),
            body: identityEventLogfmt(
                conversationID: "conv-switch",
                eventTimestamp: "2026-04-18T09:30:00Z",
                kind: "response.output_text.delta",
                accountID: "acct-old",
                email: "old@example.com"
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T09:45:00Z").timeIntervalSince1970),
            body: identityEventLogfmt(
                conversationID: "conv-switch",
                eventTimestamp: "2026-04-18T09:45:00Z",
                kind: "response.output_text.delta",
                accountID: "acct-new",
                email: "new@example.com"
            ),
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-switch",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 9,
                output: 1,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: nil,
                email: nil,
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let oldSummary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-old",
                email: "old@example.com"
            )
        )
        XCTAssertEqual(oldSummary.today.totalTokens, 0)
        XCTAssertEqual(oldSummary.today.responses, 0)

        let newSummary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-new",
                email: "new@example.com"
            )
        )
        XCTAssertEqual(newSummary.today.totalTokens, 10)
        XCTAssertEqual(newSummary.today.responses, 1)
        XCTAssertEqual(newSummary.diagnostics?.recoveredByConversationResponses, 1)
        XCTAssertEqual(newSummary.diagnostics?.recoveredByConversationTokens, 10)
    }

    func testFetchSummaryCurrentAccountKeepsUnrecoverableCompletedEventsAsUnattributed() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-unattributed",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 7,
                output: 3,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: nil,
                email: nil,
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-selected",
                email: "selected@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 0)
        XCTAssertEqual(summary.today.responses, 0)
        XCTAssertEqual(summary.diagnostics?.recoveredByConversationResponses, 0)
        XCTAssertEqual(summary.diagnostics?.recoveredByConversationTokens, 0)
        XCTAssertEqual(summary.diagnostics?.unattributedResponses, 1)
        XCTAssertEqual(summary.diagnostics?.unattributedTokens, 10)
    }

    func testFetchSummaryCurrentAccountPrefiltersResponseCompletedBeforeApplyingRowLimit() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        let nowTimestamp = Int(now.timeIntervalSince1970)

        for offset in 0..<180 {
            try insertLog(
                ts: nowTimestamp - offset,
                body: """
                event.name="codex.tool_result" event.kind=tool_call model=gpt-5.3-codex event.timestamp=2026-04-18T10:00:00Z
                """,
                at: databasePath
            )
        }

        try insertLog(
            ts: nowTimestamp - 1000,
            body: completedEventLogfmt(
                conversationID: "conv-limit-window",
                eventTimestamp: "2026-04-18T11:40:00Z",
                model: "gpt-5.4",
                input: 7,
                output: 5,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-limit",
                email: "limit@example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            maxRowCount: 100,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-limit",
                email: "limit@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 12)
        XCTAssertEqual(summary.today.responses, 1)
    }

    func testFetchSummaryCurrentAccountNormalizesAccountIDPrefixesAndCase() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-acct-normalize",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 6,
                output: 4,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "account:ACCT-MIXED",
                email: nil,
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "tenant:account:acct-mixed",
                email: nil
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 10)
        XCTAssertEqual(summary.today.responses, 1)
    }

    func testFetchSummaryCurrentAccountIgnoresEmbeddedEventKeysInsideArguments() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)

        let now = try fixedDate("2026-04-18T12:00:00Z")
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:30:00Z").timeIntervalSince1970),
            body: """
            arguments="query LIKE %event.name=codex.sse_event% and %event.kind=response.completed% and %input_token_count=999% and %output_token_count=1% and %user.account_id=acct-real%" event.name="codex.tool_result" event.kind=tool_call user.account_id="acct-real" user.email="real@example.com" model=gpt-5.3-codex event.timestamp=2026-04-18T10:30:00Z
            """,
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-18T10:00:00Z").timeIntervalSince1970),
            body: completedEventLogfmt(
                conversationID: "conv-real",
                eventTimestamp: "2026-04-18T10:00:00Z",
                model: "gpt-5.4",
                input: 5,
                output: 5,
                cached: 0,
                reasoning: 0,
                tool: 0,
                accountID: "acct-real",
                email: "real@example.com",
                escapeIdentityQuotes: false
            ),
            at: databasePath
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = CodexLocalUsageService(
            calendar: calendar,
            nowProvider: { now }
        )

        let summary = try service.fetchSummary(
            databasePath: databasePath,
            scope: .currentAccount,
            currentIdentity: CodexTrendIdentityContext(
                accountID: "acct-real",
                email: "real@example.com"
            )
        )

        XCTAssertEqual(summary.today.totalTokens, 10)
        XCTAssertEqual(summary.today.responses, 1)
    }

    private func createLogsTable(at path: String) throws {
        let sql = "CREATE TABLE IF NOT EXISTS logs (ts REAL, feedback_log_body TEXT);"
        try runSQLite(databasePath: path, sql: sql)
    }

    private func insertLog(ts: Int, body: String, at path: String) throws {
        let escaped = body.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO logs (ts, feedback_log_body) VALUES (\(ts), '\(escaped)');"
        try runSQLite(databasePath: path, sql: sql)
    }

    private func runSQLite(databasePath: String, sql: String) throws {
        guard let result = ShellCommand.run(
            executable: "/usr/bin/sqlite3",
            arguments: [databasePath, sql],
            timeout: 10
        ) else {
            XCTFail("sqlite3 command failed to start")
            return
        }
        if result.status != 0 {
            XCTFail("sqlite3 command failed: \(result.stderr)")
        }
    }

    private func writeSessionFile(relativePath: String, lines: [String]) throws {
        let fileURL = sessionsDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func sessionMetaLine(id: String, timestamp: String) -> String {
        jsonLine([
            "timestamp": timestamp,
            "type": "session_meta",
            "payload": [
                "id": id,
                "timestamp": timestamp
            ]
        ])
    }

    private func turnContextLine(timestamp: String, model: String) -> String {
        jsonLine([
            "timestamp": timestamp,
            "type": "turn_context",
            "payload": [
                "model": model
            ]
        ])
    }

    private func tokenCountTotalLine(timestamp: String, total: Int, model: String? = nil) -> String {
        var info: [String: Any] = [
            "total_token_usage": [
                "input_tokens": total,
                "cached_input_tokens": 0,
                "output_tokens": 0,
                "reasoning_output_tokens": 0,
                "total_tokens": total
            ]
        ]
        if let model {
            info["model"] = model
        }

        return jsonLine([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": info
            ]
        ])
    }

    private func tokenCountLastLine(timestamp: String, last: Int, model: String? = nil) -> String {
        var info: [String: Any] = [
            "last_token_usage": [
                "input_tokens": last,
                "cached_input_tokens": 0,
                "output_tokens": 0,
                "reasoning_output_tokens": 0,
                "total_tokens": last
            ]
        ]
        if let model {
            info["model"] = model
        }

        return jsonLine([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": info
            ]
        ])
    }

    private func tokenCountUsageLine(
        timestamp: String,
        key: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int,
        total: Int,
        model: String? = nil
    ) -> String {
        var info: [String: Any] = [
            key: [
                "input_tokens": input,
                "cached_input_tokens": cacheRead,
                "cache_creation_input_tokens": cacheWrite,
                "output_tokens": output,
                "total_tokens": total
            ]
        ]
        if let model {
            info["model"] = model
        }

        return jsonLine([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": info
            ]
        ])
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private func completedEventLogfmt(
        conversationID: String,
        eventTimestamp: String,
        model: String,
        input: Int,
        output: Int,
        cached: Int,
        reasoning: Int,
        tool: Int,
        accountID: String?,
        email: String?,
        escapeIdentityQuotes: Bool
    ) -> String {
        var parts = [
            "event.name=\"codex.sse_event\"",
            "event.kind=response.completed",
            "event.timestamp=\(eventTimestamp)",
            "conversation.id=\(conversationID)",
            "model=\(model)",
            "input_token_count=\(input)",
            "output_token_count=\(output)",
            "cached_token_count=\(cached)",
            "reasoning_token_count=\(reasoning)",
            "tool_token_count=\(tool)"
        ]

        if let accountID {
            if escapeIdentityQuotes {
                parts.append("user.account_id=\\\"\(accountID)\\\"")
            } else {
                parts.append("user.account_id=\"\(accountID)\"")
            }
        }
        if let email {
            if escapeIdentityQuotes {
                parts.append("user.email=\\\"\(email)\\\"")
            } else {
                parts.append("user.email=\"\(email)\"")
            }
        }

        return parts.joined(separator: " ")
    }

    private func identityEventLogfmt(
        conversationID: String,
        eventTimestamp: String,
        kind: String,
        accountID: String?,
        email: String?
    ) -> String {
        var parts = [
            "event.name=\"codex.sse_event\"",
            "event.kind=\(kind)",
            "event.timestamp=\(eventTimestamp)",
            "conversation.id=\(conversationID)",
            "model=gpt-5.4"
        ]

        if let accountID {
            parts.append("user.account_id=\"\(accountID)\"")
        }
        if let email {
            parts.append("user.email=\"\(email)\"")
        }

        return parts.joined(separator: " ")
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
            throw NSError(domain: "CodexLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
