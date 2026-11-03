import XCTest
import OhMyUsageProviders
@testable import OhMyUsage

final class CodexAppServerRPCClientTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-rpc-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReturnsAsSoonAsBothResponsesArriveWhileServerKeepsRunning() async throws {
        // The server never exits on its own; the old fixed keep-alive would
        // have cost several seconds here.
        let path = try makeServer("""
        while IFS= read -r line; do
          case "$line" in
            *'"id":"2"'*) printf '%s\\n' '{"jsonrpc":"2.0","id":"2","result":{"account":{"email":"a@example.com"}}}' ;;
            *'"id":"3"'*) printf '%s\\n' '{"jsonrpc":"2.0","id":3,"result":{"rateLimits":{"credits":{}}}}' ;;
          esac
        done
        exec sleep 30
        """)
        let started = Date()
        let responses = try await client(path).readAccountAndRateLimits()

        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
        let account = try XCTUnwrap(responses["2"])
        XCTAssertTrue(String(decoding: account, as: UTF8.self).contains("a@example.com"))
        XCTAssertNotNil(responses["3"], "numeric IDs are normalized to strings")
    }

    func testJSONRPCErrorSurfacesAsInvalidResponse() async throws {
        let path = try makeServer("""
        read -r line
        printf '%s\\n' '{"jsonrpc":"2.0","id":"1","error":{"code":-1,"message":"not logged in"}}'
        exec sleep 30
        """)
        do {
            _ = try await client(path).readAccountAndRateLimits()
            XCTFail("expected an error")
        } catch let error as ProviderError {
            assertInvalidResponse(error, "not logged in")
        }
    }

    func testSilentServerHitsDeadline() async throws {
        let path = try makeServer("exec sleep 30")
        var rpc = client(path)
        rpc.deadline = 0.3
        let started = Date()
        do {
            _ = try await rpc.readAccountAndRateLimits()
            XCTFail("expected a timeout")
        } catch let error as ProviderError {
            guard case .timeout = error else { return XCTFail("unexpected error \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }

    func testNonZeroExitWithoutResponsesReportsStderr() async throws {
        let path = try makeServer("""
        echo "boom: no auth" >&2
        exit 3
        """)
        do {
            _ = try await client(path).readAccountAndRateLimits()
            XCTFail("expected a command failure")
        } catch let error as ProviderError {
            guard case .commandFailed(let stderr) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(stderr.contains("boom: no auth"))
        }
    }

    func testCleanExitWithPartialResponsesIsInvalid() async throws {
        let path = try makeServer("""
        printf '%s\\n' '{"jsonrpc":"2.0","id":"2","result":{"account":{}}}'
        exit 0
        """)
        do {
            _ = try await client(path).readAccountAndRateLimits()
            XCTFail("expected an invalid response")
        } catch let error as ProviderError {
            assertInvalidResponse(error, "missing account/read or account/rateLimits/read response")
        }
    }

    func testCancellationReturnsImmediately() async throws {
        let path = try makeServer("exec sleep 30")
        let rpc = client(path)
        let task = Task { try await rpc.readAccountAndRateLimits() }
        try await Task.sleep(nanoseconds: 200_000_000)
        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
        }
    }

    func testMissingExecutableThrowsLaunchError() async {
        do {
            _ = try await client(directory.appendingPathComponent("missing").path).readAccountAndRateLimits()
            XCTFail("expected a launch error")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testRequestLinesEscapeClientVersion() throws {
        let lines = CodexAppServerRPCClient.requestLines(clientVersion: #"2.6"7"#)
        let initialize = try XCTUnwrap(lines.first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(initialize.utf8)) as? [String: Any]
        )
        let params = try XCTUnwrap(json["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["version"] as? String, #"2.6"7"#)
        XCTAssertEqual(lines.count, 4)
    }

    func testParseLineIgnoresNoise() {
        XCTAssertNil(CodexAppServerRPCClient.parseLine("starting server"))
        XCTAssertNil(CodexAppServerRPCClient.parseLine(#"{"jsonrpc":"2.0","method":"notice"}"#))
    }

    private func assertInvalidResponse(_ error: ProviderError, _ expected: String, line: UInt = #line) {
        guard case .invalidResponse(let message) = error else {
            return XCTFail("unexpected error \(error)", line: line)
        }
        XCTAssertEqual(message, expected, line: line)
    }

    private func client(_ path: String) -> CodexAppServerRPCClient {
        CodexAppServerRPCClient(executablePath: path, clientVersion: "test", deadline: 5, exitGrace: 0.2)
    }

    private func makeServer(_ body: String) throws -> String {
        let url = directory.appendingPathComponent("codex-\(UUID().uuidString).sh")
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
}
