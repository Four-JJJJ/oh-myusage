import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class CCSwitchUsageLogReaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ccswitch-usage-reader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testReadUsageLogsNormalizesProxySessionPlaceholderAndRollupRows() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let eventAt = try fixedDate("2026-05-16T10:30:00Z")
        let rollupDate = "2026-05-15"
        try runSQLite(
            databasePath: databaseURL.path,
            sql: """
            INSERT INTO providers (id, app_type, name) VALUES ('relay-a', 'codex', 'FourJ Relay');
            INSERT INTO providers (id, app_type, name) VALUES ('relay-b', 'claude', 'Claude Relay');
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES (
                'req-proxy', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 100, 50,
                20, 10, 200, \(Int(eventAt.timeIntervalSince1970)), NULL
            );
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES (
                'req-session', '_codex_session', 'codex', 'gpt-5.4', 'gpt-5.4', 30, 10,
                5, 0, 500, \(Int(eventAt.timeIntervalSince1970)), 'session'
            );
            INSERT INTO usage_daily_rollups (
                date, app_type, provider_id, model, request_count, success_count, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens
            ) VALUES (
                '\(rollupDate)', 'claude', 'relay-b', 'claude-sonnet-4-6', 3, 2, 9, 6, 5, 4
            );
            """
        )

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let result = reader.readUsageLogs(
            since: try fixedDate("2026-05-15T00:00:00Z"),
            until: try fixedDate("2026-05-17T00:00:00Z")
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.records.count, 3)

        let proxy = try XCTUnwrap(result.records.first { $0.requestID == "req-proxy" })
        XCTAssertEqual(proxy.source, .proxy)
        XCTAssertEqual(proxy.providerName, "FourJ Relay")
        XCTAssertEqual(proxy.inputTokens, 80)
        XCTAssertEqual(proxy.outputTokens, 50)
        XCTAssertEqual(proxy.cacheReadTokens, 20)
        XCTAssertEqual(proxy.cacheWriteTokens, 10)
        XCTAssertEqual(proxy.requestCount, 1)
        XCTAssertEqual(proxy.successCount, 1)

        let session = try XCTUnwrap(result.records.first { $0.requestID == "req-session" })
        XCTAssertEqual(session.source, .session)
        XCTAssertEqual(session.providerName, "Codex (Session)")
        XCTAssertEqual(session.inputTokens, 25)
        XCTAssertEqual(session.successCount, 0)

        let rollup = try XCTUnwrap(result.records.first { $0.source == .dailyRollup })
        XCTAssertEqual(rollup.providerName, "Claude Relay")
        XCTAssertEqual(rollup.requestCount, 3)
        XCTAssertEqual(rollup.successCount, 2)
        XCTAssertEqual(rollup.inputTokens, 9)
        XCTAssertEqual(rollup.cacheReadTokens, 5)
        XCTAssertEqual(rollup.cacheWriteTokens, 4)
    }

    func testReadUsageLogsReturnsEmptyDiagnosticWhenDatabaseIsMissing() throws {
        let reader = CCSwitchUsageLogReader(
            databasePath: temporaryDirectory.appendingPathComponent("missing.db").path
        )

        let result = reader.readUsageLogs(
            since: try fixedDate("2026-05-15T00:00:00Z"),
            until: try fixedDate("2026-05-17T00:00:00Z")
        )

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("未检测到 cc-switch 请求日志") })
    }

    func testReadUsageLogsKeepsEpochPrecisionAtRangeBoundaries() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-boundary.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let since = try fixedDate("2026-05-16T10:00:00Z")
        let until = try fixedDate("2026-05-16T11:00:00Z")
        let middle = try fixedDate("2026-05-16T10:30:00Z")
        let late = try fixedDate("2026-05-16T10:45:00Z")
        let nearEnd = try fixedDate("2026-05-16T10:59:59Z")
        let before = try fixedDate("2026-05-16T09:59:59Z")

        try runSQLite(
            databasePath: databaseURL.path,
            sql: """
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES
                ('req-sec', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(since.timeIntervalSince1970)), NULL),
                ('req-ms', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(middle.timeIntervalSince1970 * 1_000)), NULL),
                ('req-us', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(late.timeIntervalSince1970 * 1_000_000)), NULL),
                ('req-ns', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(nearEnd.timeIntervalSince1970 * 1_000_000_000)), NULL),
                ('req-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(before.timeIntervalSince1970)), NULL),
                ('req-ms-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(since.timeIntervalSince1970 * 1_000) - 1), NULL),
                ('req-ms-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(until.timeIntervalSince1970 * 1_000)), NULL),
                ('req-us-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(since.timeIntervalSince1970 * 1_000_000) - 1), NULL),
                ('req-us-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(until.timeIntervalSince1970 * 1_000_000)), NULL),
                ('req-ns-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(since.timeIntervalSince1970 * 1_000_000_000) - 1), NULL),
                ('req-ns-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(until.timeIntervalSince1970 * 1_000_000_000)), NULL),
                ('req-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(until.timeIntervalSince1970)), NULL);
            """
        )

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let result = reader.readUsageLogs(since: since, until: until)
        let requestIDs = result.records.map(\.requestID).sorted()

        XCTAssertEqual(requestIDs, ["req-ms", "req-ns", "req-sec", "req-us"])
    }

    func testProxyLogRangePredicateKeepsCreatedAtRawForIndexLookup() throws {
        let predicate = CCSwitchUsageLogReader.createdAtRawEpochRangePredicate("l.created_at")

        XCTAssertFalse(predicate.localizedCaseInsensitiveContains("CASE"))
        XCTAssertFalse(predicate.localizedCaseInsensitiveContains("CAST"))
        XCTAssertEqual(predicate.components(separatedBy: " OR ").count, 4)
        XCTAssertEqual(predicate.components(separatedBy: "l.created_at").count - 1, 8)
    }

    func testProxyLogRangePredicateUsesCreatedAtIndexInSQLitePlan() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-index-plan.db")
        try createCCSwitchSchema(at: databaseURL.path)
        try runSQLite(
            databasePath: databaseURL.path,
            sql: "CREATE INDEX idx_proxy_request_logs_created_at ON proxy_request_logs(created_at);"
        )

        let predicate = CCSwitchUsageLogReader.createdAtRawEpochRangePredicate("l.created_at")
        let plan = try runSQLiteOutput(
            databasePath: databaseURL.path,
            sql: """
            EXPLAIN QUERY PLAN
            SELECT request_id FROM proxy_request_logs l
            WHERE \(predicate);
            """
        )

        XCTAssertFalse(plan.contains("SCAN l"), plan)
        XCTAssertTrue(plan.contains("idx_proxy_request_logs_created_at"), plan)
    }

    func testReaderStreamsSQLiteRowsAsTheyAreMapped() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-streaming.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let firstEventAt = try fixedDate("2026-05-16T10:00:00Z")
        let secondEventAt = try fixedDate("2026-05-16T10:05:00Z")
        try runSQLite(
            databasePath: databaseURL.path,
            sql: """
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES
                ('stream-1', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int(firstEventAt.timeIntervalSince1970)), NULL),
                ('stream-2', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 20, 7, 0, 0, 200, \(Int(secondEventAt.timeIntervalSince1970)), NULL);
            INSERT INTO usage_daily_rollups (
                date, app_type, provider_id, model, request_count, success_count, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens
            ) VALUES (
                '2026-05-16', 'claude', 'relay-a', 'claude-sonnet-4-6', 2, 2, 30, 12, 0, 0
            );
            """
        )

        var events: [CCSwitchUsageLogReaderStreamEvent] = []
        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path) { event in
            events.append(event)
        }
        let result = reader.readUsageLogs(
            since: try fixedDate("2026-05-16T00:00:00Z"),
            until: try fixedDate("2026-05-17T00:00:00Z")
        )

        XCTAssertEqual(result.records.count, 3)
        XCTAssertEqual(
            events,
            [
                CCSwitchUsageLogReaderStreamEvent(source: .proxyRequestLogs, phase: .rowRead, ordinal: 1),
                CCSwitchUsageLogReaderStreamEvent(source: .proxyRequestLogs, phase: .recordMapped, ordinal: 1),
                CCSwitchUsageLogReaderStreamEvent(source: .proxyRequestLogs, phase: .rowRead, ordinal: 2),
                CCSwitchUsageLogReaderStreamEvent(source: .proxyRequestLogs, phase: .recordMapped, ordinal: 2),
                CCSwitchUsageLogReaderStreamEvent(source: .dailyRollups, phase: .rowRead, ordinal: 1),
                CCSwitchUsageLogReaderStreamEvent(source: .dailyRollups, phase: .recordMapped, ordinal: 1)
            ],
            "Rows should be mapped immediately after each SQLite step, not after collecting an intermediate batch."
        )
    }

    func testSourceFingerprintIncludesSQLiteWALSidecars() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-wal.db")
        try Data("main".utf8).write(to: databaseURL)
        try Data("wal-version-1".utf8).write(to: URL(fileURLWithPath: "\(databaseURL.path)-wal"))
        try Data("shm-version-1".utf8).write(to: URL(fileURLWithPath: "\(databaseURL.path)-shm"))

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let fingerprint = reader.sourceFingerprint()

        XCTAssertEqual(
            fingerprint.roots,
            [
                databaseURL.path,
                "\(databaseURL.path)-shm",
                "\(databaseURL.path)-wal"
            ].sorted()
        )
        XCTAssertEqual(fingerprint.fileCount, 3)

        Thread.sleep(forTimeInterval: 0.01)
        try Data("wal-version-2-with-more-bytes".utf8).write(to: URL(fileURLWithPath: "\(databaseURL.path)-wal"))
        let changedFingerprint = reader.sourceFingerprint()

        XCTAssertNotEqual(changedFingerprint, fingerprint)
        XCTAssertEqual(changedFingerprint.fileCount, 3)
    }

    func testReadUsageLogsHandlesLargeProxyAndRollupBatchWithinDateRange() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-large.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let since = try fixedDate("2026-05-16T00:00:00Z")
        let until = try fixedDate("2026-05-17T00:00:00Z")
        let proxyCount = 1_500
        var expectedInputTokens = 0
        var expectedOutputTokens = 0
        var expectedSuccessCount = 0
        var proxyRows: [String] = []

        for index in 0..<proxyCount {
            let eventAt = Int64(since.addingTimeInterval(Double(index % 3_600)).timeIntervalSince1970)
            let rawInput = 100 + (index % 17)
            let output = 20 + (index % 11)
            let cacheRead = index % 5
            let cacheWrite = index % 3
            let statusCode = index % 10 == 0 ? 500 : 200
            expectedInputTokens += rawInput - cacheRead
            expectedOutputTokens += output
            expectedSuccessCount += statusCode == 200 ? 1 : 0
            proxyRows.append("""
                ('bulk-\(index)', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', \(rawInput), \(output), \(cacheRead), \(cacheWrite), \(statusCode), \(eventAt), NULL)
            """)
        }

        let before = Int64(since.addingTimeInterval(-1).timeIntervalSince1970)
        let atEnd = Int64(until.timeIntervalSince1970)
        let sql = """
        BEGIN TRANSACTION;
        INSERT INTO providers (id, app_type, name) VALUES ('relay-a', 'codex', 'FourJ Relay');
        INSERT INTO proxy_request_logs (
            request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
            cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
        ) VALUES
            \(proxyRows.joined(separator: ",\n")),
            ('bulk-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 9999, 9999, 0, 0, 200, \(before), NULL),
            ('bulk-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 9999, 9999, 0, 0, 200, \(atEnd), NULL);
        INSERT INTO usage_daily_rollups (
            date, app_type, provider_id, model, request_count, success_count, input_tokens, output_tokens,
            cache_read_tokens, cache_creation_tokens
        ) VALUES
            ('2026-05-15', 'claude', 'relay-a', 'claude-sonnet-4-6', 99, 99, 9999, 9999, 0, 0),
            ('2026-05-16', 'claude', 'relay-a', 'claude-sonnet-4-6', 7, 6, 120, 45, 3, 2),
            ('2026-05-17', 'claude', 'relay-a', 'claude-sonnet-4-6', 88, 88, 8888, 8888, 0, 0);
        COMMIT;
        """
        try runSQLiteScript(databasePath: databaseURL.path, sql: sql)

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let result = reader.readUsageLogs(since: since, until: until)

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.records.count, proxyCount + 1)
        XCTAssertNil(result.records.first { $0.requestID == "bulk-before" })
        XCTAssertNil(result.records.first { $0.requestID == "bulk-end" })

        let proxyRecords = result.records.filter { $0.source == .proxy }
        XCTAssertEqual(proxyRecords.count, proxyCount)
        XCTAssertEqual(proxyRecords.reduce(0) { $0 + $1.requestCount }, proxyCount)
        XCTAssertEqual(proxyRecords.reduce(0) { $0 + $1.successCount }, expectedSuccessCount)
        XCTAssertEqual(proxyRecords.reduce(0) { $0 + $1.inputTokens }, expectedInputTokens)
        XCTAssertEqual(proxyRecords.reduce(0) { $0 + $1.outputTokens }, expectedOutputTokens)

        let rollup = try XCTUnwrap(result.records.first { $0.source == .dailyRollup })
        XCTAssertEqual(rollup.requestCount, 7)
        XCTAssertEqual(rollup.successCount, 6)
        XCTAssertEqual(rollup.inputTokens, 120)
        XCTAssertEqual(rollup.outputTokens, 45)
    }

    private func createCCSwitchSchema(at path: String) throws {
        try runSQLite(
            databasePath: path,
            sql: """
            CREATE TABLE providers (
                id TEXT PRIMARY KEY,
                app_type TEXT,
                name TEXT
            );
            CREATE TABLE proxy_request_logs (
                request_id TEXT PRIMARY KEY,
                provider_id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                model TEXT NOT NULL,
                request_model TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER,
                status_code INTEGER,
                created_at INTEGER,
                data_source TEXT
            );
            CREATE TABLE usage_daily_rollups (
                date TEXT,
                app_type TEXT,
                provider_id TEXT,
                model TEXT,
                request_count INTEGER,
                success_count INTEGER,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER
            );
            """
        )
    }

    private func runSQLite(databasePath: String, sql: String) throws {
        let result = try runSQLiteCommand(databasePath: databasePath, sql: sql)
        if result.status != 0 {
            XCTFail("sqlite3 command failed: \(result.stderr)")
        }
    }

    private func runSQLiteOutput(databasePath: String, sql: String) throws -> String {
        let result = try runSQLiteCommand(databasePath: databasePath, sql: sql)
        if result.status != 0 {
            XCTFail("sqlite3 command failed: \(result.stderr)")
        }
        return result.stdout
    }

    private func runSQLiteCommand(
        databasePath: String,
        sql: String
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        guard let result = ShellCommand.run(
            executable: "/usr/bin/sqlite3",
            arguments: [databasePath, sql],
            timeout: 10
        ) else {
            XCTFail("sqlite3 command failed to start")
            throw NSError(domain: "CCSwitchUsageLogReaderTests", code: 2)
        }
        return result
    }

    private func runSQLiteScript(databasePath: String, sql: String) throws {
        let scriptURL = temporaryDirectory.appendingPathComponent("script-\(UUID().uuidString).sql")
        try sql.write(to: scriptURL, atomically: true, encoding: .utf8)
        try runSQLite(databasePath: databasePath, sql: ".read \(scriptURL.path)")
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "CCSwitchUsageLogReaderTests", code: 1)
        }
        return date
    }
}
