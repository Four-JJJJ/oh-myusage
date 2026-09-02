import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class CursorProviderTests: XCTestCase {
    func testFetchMaps401ToUnauthorizedWithSingleRefreshAttempt() async throws {
        let provider = makeProvider()

        var usageRequestCount = 0
        var refreshRequestCount = 0
        CursorMockURLProtocol.requestHandler = { request in
            let response: HTTPURLResponse
            if request.url?.path == "/api/usage-summary" {
                usageRequestCount += 1
                response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            } else {
                refreshRequestCount += 1
                response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            }
            return (response, Data(#"{"error":"unauthorized"}"#.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorized")
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                return XCTFail("Expected unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // 401 triggers at most one refresh + one retry of the usage request.
        XCTAssertEqual(usageRequestCount, 1)
        XCTAssertEqual(refreshRequestCount, 1)
    }

    func testFetchMaps429ToRateLimitedWithoutRetrying() async throws {
        let provider = makeProvider()

        var usageRequestCount = 0
        var refreshRequestCount = 0
        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/usage-summary" {
                usageRequestCount += 1
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error":"too many requests"}"#.utf8))
            }
            refreshRequestCount += 1
            XCTFail("429 must not trigger a credential refresh")
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected rateLimited")
        } catch let error as ProviderError {
            guard case .rateLimited = error else {
                return XCTFail("Expected rateLimited, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(usageRequestCount, 1)
        XCTAssertEqual(refreshRequestCount, 0)
    }

    func testFetchMissingStateDatabaseDoesNotTouchNetwork() async throws {
        let missingPath = NSTemporaryDirectory() + "cursor-missing-\(UUID().uuidString)/state.vscdb"
        let provider = makeProvider(stateDatabasePath: missingPath)
        CursorMockURLProtocol.requestHandler = { _ in
            XCTFail("network must not be reached without saved Cursor auth")
            let response = HTTPURLResponse(url: URL(string: "https://cursor.com/api/usage-summary")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeProvider(stateDatabasePath: String? = nil) -> CursorProvider {
        let resolvedPath: String
        if let stateDatabasePath {
            resolvedPath = stateDatabasePath
        } else {
            let directory = NSTemporaryDirectory() + "cursor-state-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            resolvedPath = directory + "/state.vscdb"
            FileManager.default.createFile(atPath: resolvedPath, contents: Data())
        }

        return CursorProvider(
            descriptor: ProviderDescriptor.defaultOfficialCursor(),
            session: makeMockSession(),
            sqlite: StubCursorSQLite(rows: [
                ["cursorAuth/accessToken", "fake.header.signature"],
                ["cursorAuth/refreshToken", "fake-refresh-token"],
                ["cursorAuth/cachedEmail", "user@example.com"]
            ]),
            stateDatabasePath: resolvedPath
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CursorMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class CursorMockURLProtocol: URLProtocol {
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

private struct StubCursorSQLite: SQLiteQuerying {
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
