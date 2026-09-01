import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class WindsurfProviderTests: XCTestCase {
    func testFetchMaps401ToUnauthorizedWithoutRetryingSameCredential() async throws {
        var requestCount = 0
        WindsurfMockURLProtocol.requestHandler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.host, "server.self-serve.windsurf.com")
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":3,"message":"unauthorized"}"#.utf8))
        }
        defer { WindsurfMockURLProtocol.requestHandler = nil }

        let provider = makeProvider()

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
        XCTAssertEqual(requestCount, 1)
    }

    func testFetchMaps429ToRateLimitedWithoutRetrying() async throws {
        var requestCount = 0
        WindsurfMockURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"code":8,"message":"rate limited"}"#.utf8))
        }
        defer { WindsurfMockURLProtocol.requestHandler = nil }

        let provider = makeProvider()

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
        XCTAssertEqual(requestCount, 1)
    }

    private func makeProvider(
        stateVariants: [WindsurfProvider.StateVariant]? = nil
    ) -> WindsurfProvider {
        let stateDatabasePath = NSTemporaryDirectory() + "windsurf-state-\(UUID().uuidString)/state.vscdb"
        try? FileManager.default.createDirectory(
            atPath: (stateDatabasePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: stateDatabasePath, contents: Data())

        return WindsurfProvider(
            descriptor: ProviderDescriptor.defaultOfficialWindsurf(),
            session: makeMockSession(),
            stateVariants: stateVariants ?? [
                .init(ideName: "windsurf", dbPath: stateDatabasePath)
            ],
            sqlite: StubWindsurfSQLite(rows: [
                [#"{"apiKey":"windsurf-test-key"}"#]
            ])
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WindsurfMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class WindsurfMockURLProtocol: URLProtocol {
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

private struct StubWindsurfSQLite: SQLiteQuerying {
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
