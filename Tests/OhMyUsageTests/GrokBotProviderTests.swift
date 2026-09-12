import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class GrokBotProviderTests: XCTestCase {
    func testParseSnapshotMapsWeeklyUsage() throws {
        let descriptor = ProviderDescriptor.defaultOfficialGrokBot()
        let resetAt = "2026-08-20T03:47:03.411698+00:00"
        let data = Data(
            """
            {
              "hasNonZeroIncludedLimit": true,
              "usagePercent": 37.5,
              "nextResetTimestampUtc": "\(resetAt)",
              "currentPeriodStart": "2026-08-13T03:47:03.411698+00:00",
              "hasAvailableUsage": true
            }
            """.utf8
        )

        let snapshot = try GrokBotProvider.parseSnapshot(
            data: data,
            descriptor: descriptor,
            accountLabel: "user@example.com"
        )

        XCTAssertEqual(snapshot.used ?? -1, 37.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining ?? -1, 62.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountLabel, "user@example.com")
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let weekly = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.title, "Weekly")
        XCTAssertEqual(snapshot.rawMeta["grokBot.hasAvailableUsage"], "true")
    }

    func testParseSnapshotWithoutWeeklyAllowanceIsUnavailable() throws {
        let descriptor = ProviderDescriptor.defaultOfficialGrokBot()
        let data = Data(
            """
            {
              "hasNonZeroIncludedLimit": false,
              "usagePercent": 0,
              "hasAvailableUsage": false
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try GrokBotProvider.parseSnapshot(
                data: data,
                descriptor: descriptor,
                accountLabel: nil
            )
        ) { error in
            guard case .unavailable = error as? ProviderError else {
                XCTFail("Expected unavailable, got \(error)")
                return
            }
        }
    }

    func testFetchPostsSandUsageWithCursorSessionCookie() async throws {
        let directory = NSTemporaryDirectory() + "grokbot-state-\(UUID().uuidString)"
        let dbPath = directory + "/state.vscdb"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dbPath, contents: Data())

        let provider = GrokBotProvider(
            descriptor: .defaultOfficialGrokBot(),
            session: makeMockSession(),
            authStore: CursorSessionAuthStore(
                session: makeMockSession(),
                sqlite: StubGrokBotSQLite(rows: [
                    ["cursorAuth/accessToken", "fake.header.signature"],
                    ["cursorAuth/refreshToken", "fake-refresh-token"],
                    ["cursorAuth/cachedEmail", "user@example.com"]
                ]),
                stateDatabasePath: dbPath
            )
        )

        GrokBotMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/dashboard/get-sand-usage-status")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("WorkosCursorSessionToken=") == true)
            let body = """
            {
              "hasNonZeroIncludedLimit": true,
              "usagePercent": 12.5,
              "nextResetTimestampUtc": "2026-08-20T03:47:03.411698+00:00",
              "hasAvailableUsage": true
            }
            """
            return (Self.okResponse(for: request), Data(body.utf8))
        }
        defer { GrokBotMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.used ?? -1, 12.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountLabel, "user@example.com")
    }

    func testFetchMissingStateDatabaseDoesNotTouchNetwork() async throws {
        let missingPath = NSTemporaryDirectory() + "grokbot-missing-\(UUID().uuidString)/state.vscdb"
        let provider = GrokBotProvider(
            descriptor: .defaultOfficialGrokBot(),
            session: makeMockSession(),
            authStore: CursorSessionAuthStore(
                session: makeMockSession(),
                sqlite: StubGrokBotSQLite(rows: []),
                stateDatabasePath: missingPath
            )
        )

        GrokBotMockURLProtocol.requestHandler = { _ in
            XCTFail("network must not be reached without saved Cursor auth")
            let response = HTTPURLResponse(
                url: URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        defer { GrokBotMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                XCTFail("Expected missingCredential, got \(error)")
                return
            }
        }
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokBotMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func okResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

private final class GrokBotMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct StubGrokBotSQLite: SQLiteQuerying {
    let rows: [[String]]

    func rows(databasePath: String, query: String, separator: String) -> [[String]] {
        rows
    }

    func query(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        makeResult(databasePath: databasePath)
    }

    func snapshotQuery(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        makeResult(databasePath: databasePath)
    }

    func execute(databasePath: String, sql: String) -> Bool {
        true
    }

    private func makeResult(databasePath: String) -> SQLiteShell.QueryResult {
        SQLiteShell.QueryResult(
            databasePath: databasePath,
            executedPath: databasePath,
            mode: .readOnlySnapshot,
            status: 0,
            stdout: "",
            stderr: "",
            rows: rows
        )
    }
}
