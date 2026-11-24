import Foundation
import OhMyUsageDomain
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

final class AntigravityUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("antigravity-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testAntigravityLocalUsageServiceParsesTranscriptJSONLAndRollingWindows() throws {
        let brainRoot = temporaryDirectory
            .appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        let logDir = brainRoot
            .appendingPathComponent("conv-1/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().date(from: "2026-11-24T10:00:00Z")!
        let lines = [
            #"{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-11-24T08:00:00Z","content":"hi"}"#,
            #"{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-24T08:00:05Z","model":"gemini-4-carbon-high","input_tokens":10000,"cache_read_tokens":5000,"output_tokens":500}"#,
            #"{"step_index":2,"source":"MODEL","type":"PLANNER_RESPONSE","status":"ACTIVE","created_at":"2026-11-24T08:01:00Z","model":"gemini-4-carbon-high","input_tokens":99999,"cache_read_tokens":0,"output_tokens":100}"#,
            #"{"step_index":3,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-11-21T12:00:00Z","model":"gemini-3.8-flash-high","input_tokens":2000,"cache_read_tokens":1000,"output_tokens":300}"#,
            #"{"event":"result","result":{"usage":{"input_tokens":99999,"output_tokens":999,"total_tokens":100998}}}"#
        ].joined(separator: "\n")
        try lines.write(to: logDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let service = AntigravityLocalUsageService(
            nowProvider: { now },
            brainRootPaths: [brainRoot.path],
            homeDirectory: temporaryDirectory.path,
            environment: [:]
        )

        let rolling = try service.fetchRollingWindowSummary(now: now)
        XCTAssertEqual(rolling.fiveHourTokens, 15_500)
        XCTAssertEqual(rolling.fiveHourRequests, 1)
        XCTAssertEqual(rolling.sevenDayTokens, 18_800)
        XCTAssertEqual(rolling.sevenDayRequests, 2)
        XCTAssertEqual(rolling.latestModelID, "gemini-4-carbon-high")

        let summary = try service.fetchSummary()
        XCTAssertEqual(summary.last30Days.totalTokens, 18_800)
        XCTAssertEqual(summary.last30Days.responses, 2)
    }

    func testAntigravityProviderParsesCommandDataGroupsSchemaFromGeminiAppHelper() async throws {
        let helperDir = temporaryDirectory
            .appendingPathComponent("Applications/Gemini.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helperDir, withIntermediateDirectories: true)
        let fakeAgy = helperDir.appendingPathComponent("agy")
        try "#!/bin/sh\nexit 0\n".write(to: fakeAgy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeAgy.path)

        let runner = RecordingShellRunner(stdout: Self.sampleAgy155UsageJSON)
        let descriptor = ProviderDescriptor.defaultOfficialAntigravity()

        let provider = AntigravityProvider(
            descriptor: descriptor,
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { self.temporaryDirectory.path },
            environment: { [:] },
            shell: runner,
            cacheTTL: 0
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(runner.lastEnvironment?["AGY_CLI_DISABLE_AUTO_UPDATE"], "true")
        XCTAssertEqual(runner.lastArguments, ["-p", "/usage", "--output-format", "json"])
        XCTAssertEqual(snapshot.sourceLabel, "Gemini.app")
        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.remaining ?? -1, 91.69058203697205, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.count, 4)
        XCTAssertEqual(snapshot.quotaWindows.map(\.title), [
            "Gemini 5h",
            "Gemini Weekly",
            "Claude/GPT 5h",
            "Claude/GPT Weekly"
        ])
        XCTAssertNotNil(snapshot.quotaWindows[0].resetAt)
        XCTAssertNotNil(snapshot.quotaWindows[1].resetAt)

        let localization = MenuQuotaLocalization(
            quotaFiveHour: "5h",
            quotaWeekly: "周",
            allModels: "全部模型",
            sonnetOnly: "Sonnet 专用",
            claudeDesign: "Claude Design",
            session: "会话",
            monthly: "月",
            currentPlan: "当前套餐",
            totalUsage: "总用量",
            autocomplete: "自动补全",
            dollarBalance: "美元额度"
        )
        let metrics = MenuQuotaPresenter.quotaMetrics(
            provider: descriptor,
            snapshot: snapshot,
            language: .zhHans,
            localization: localization
        )
        let visible = MenuQuotaPresenter.visibleMetrics(
            provider: descriptor,
            metrics: metrics,
            language: .zhHans,
            localization: localization
        )
        XCTAssertEqual(visible.map(\.title), [
            "Gemini 5h",
            "Gemini 周",
            "Claude/GPT 5h",
            "Claude/GPT 周"
        ])
    }

    func testGeminiProviderAutoModeFallsBackToBundledGeminiAppHelper() async throws {
        let helperDir = temporaryDirectory
            .appendingPathComponent("Applications/Gemini.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helperDir, withIntermediateDirectories: true)
        let fakeAgy = helperDir.appendingPathComponent("agy")
        try "#!/bin/sh\nexit 0\n".write(to: fakeAgy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeAgy.path)

        let runner = RecordingShellRunner(stdout: Self.sampleAgy155UsageJSON)
        let provider = GeminiProvider(
            descriptor: .defaultOfficialGemini(),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { self.temporaryDirectory.path },
            environment: { [:] },
            shell: runner,
            keychain: nil,
            browserCookieService: nil,
            externalKeychainReader: { _, _, _ in nil },
            cacheTTL: 0
        )

        let snapshot = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(snapshot.sourceLabel, "Gemini.app")
        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.quotaWindows[0].title, "5h")
        XCTAssertEqual(snapshot.quotaWindows[0].kind, .session)
        XCTAssertEqual(snapshot.quotaWindows[0].remainingPercent, 91.69058203697205, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows[1].title, "Weekly")
        XCTAssertEqual(snapshot.quotaWindows[1].kind, .weekly)
        XCTAssertEqual(snapshot.quotaWindows[1].remainingPercent, 96.91480398178101, accuracy: 0.001)
    }

    func testAntigravityProviderThrowsMissingCredentialInsteadOfTokenCountWhenCLIIsAbsent() async throws {
        let provider = AntigravityProvider(
            descriptor: .defaultOfficialAntigravity(),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            homeDirectory: { self.temporaryDirectory.path },
            environment: { [:] },
            shell: RecordingShellRunner(stdout: ""),
            cacheTTL: 0
        )

        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("Expected missingCredential when agy CLI is absent")
        } catch let error as ProviderError {
            if case .missingCredential = error {
                // Expected: percentage card never falls back to truncated raw token counts.
            } else {
                XCTFail("Unexpected ProviderError: \(error)")
            }
        }
    }

    private static let sampleAgy155UsageJSON = """
    {
      "conversation_id": "",
      "status": "SUCCESS",
      "response": "Gemini Models\\tWeekly Limit Remaining\\t97%\\t2026-12-01T01:22:05Z\\nGemini Models\\tFive Hour Limit Remaining\\t92%\\t2026-11-24T06:22:05Z\\nClaude and GPT models\\tWeekly Limit Remaining\\t100%\\t2026-12-01T02:40:14Z\\nClaude and GPT models\\tFive Hour Limit Remaining\\t100%\\t2026-11-24T07:40:14Z\\n",
      "duration_seconds": 0,
      "num_turns": 0,
      "command": {
        "name": "usage",
        "data": {
          "groups": [
            {
              "name": "Gemini Models",
              "buckets": [
                {
                  "id": "gemini-weekly",
                  "name": "Weekly Limit Remaining",
                  "window": "weekly",
                  "remaining_fraction": 0.9691480398178101,
                  "reset_time": "2026-12-01T01:22:05Z"
                },
                {
                  "id": "gemini-5h",
                  "name": "Five Hour Limit Remaining",
                  "window": "5h",
                  "remaining_fraction": 0.9169058203697205,
                  "reset_time": "2026-11-24T06:22:05Z"
                }
              ]
            },
            {
              "name": "Claude and GPT models",
              "buckets": [
                {
                  "id": "3p-weekly",
                  "name": "Weekly Limit Remaining",
                  "window": "weekly",
                  "remaining_fraction": 1,
                  "reset_time": "2026-12-01T02:40:14Z"
                },
                {
                  "id": "3p-5h",
                  "name": "Five Hour Limit Remaining",
                  "window": "5h",
                  "remaining_fraction": 1,
                  "reset_time": "2026-11-24T07:40:14Z"
                }
              ]
            }
          ]
        }
      }
    }
    """
}

private final class RecordingShellRunner: ShellCommandRunning, @unchecked Sendable {
    let stdout: String
    var lastArguments: [String] = []
    var lastEnvironment: [String: String]?

    init(stdout: String) {
        self.stdout = stdout
    }

    func run(
        executable: String,
        arguments: [String],
        input: String?,
        timeout: TimeInterval,
        environment: [String: String]?,
        currentDirectory: String?
    ) -> (status: Int32, stdout: String, stderr: String)? {
        if executable == "/usr/bin/which" {
            return (1, "", "")
        }
        lastArguments = arguments
        lastEnvironment = environment
        return (0, stdout, "")
    }
}
