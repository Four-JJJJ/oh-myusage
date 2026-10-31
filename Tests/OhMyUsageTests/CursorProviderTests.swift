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

    func testFetchMaps429WithRetryAfterToProviderRateLimitError() async throws {
        let provider = makeProvider()
        let startedAt = Date()

        var usageRequestCount = 0
        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/usage-summary" {
                usageRequestCount += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "120"]
                )!
                return (response, Data())
            }
            XCTFail("429 must not trigger a credential refresh")
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected ProviderRateLimitError")
        } catch let error as ProviderRateLimitError {
            XCTAssertEqual(
                error.retryNotBefore.timeIntervalSince(startedAt),
                120,
                accuracy: 5
            )
        } catch {
            XCTFail("Expected ProviderRateLimitError, got \(error)")
        }
        XCTAssertEqual(usageRequestCount, 1)
    }

    func testFetchMaps5xxToTimeout() async throws {
        let provider = makeProvider()

        CursorMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected timeout")
        } catch let error as ProviderError {
            guard case .timeout = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    func testEncryptedStateDatabaseTokenIsDecryptedBeforeUsageRequest() async throws {
        let jwt = Self.sessionJWT(expiration: 4_102_444_800)
        let encrypted = CursorSafeStorage.encryptedValuePrefix + "djEwY2lwaGVydGV4dA=="
        var capturedCookie: String?
        let provider = makeProvider(
            rows: [
                ["cursorAuth/accessToken", encrypted],
                ["cursorAuth/refreshToken", encrypted],
                ["cursorAuth/cachedEmail", "user@example.com"]
            ],
            safeStorage: CursorSafeStorage(
                readPassword: { "keychain-passphrase" },
                decrypt: { _, _ in jwt }
            )
        )
        CursorMockURLProtocol.requestHandler = { request in
            capturedCookie = request.value(forHTTPHeaderField: "Cookie")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.usageSummaryJSON.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        let cookie = try XCTUnwrap(capturedCookie)
        XCTAssertTrue(cookie.contains(jwt), "decrypted token must be sent, got \(cookie)")
        XCTAssertFalse(cookie.contains("cursor-safe-storage"), "ciphertext must never be sent")
    }

    func testEncryptedStateDatabaseTokenThatCannotBeDecryptedFailsWithoutNetwork() async throws {
        let provider = makeProvider(
            rows: [["cursorAuth/accessToken", CursorSafeStorage.encryptedValuePrefix + "djEwY2lwaGVydGV4dA=="]],
            safeStorage: CursorSafeStorage(
                readPassword: { "keychain-passphrase" },
                decrypt: { _, _ in nil }
            )
        )
        CursorMockURLProtocol.requestHandler = { _ in
            XCTFail("network must not be reached with an undecryptable credential")
            let response = HTTPURLResponse(url: URL(string: "https://cursor.com/api/usage-summary")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertEqual(message, CursorSessionAuth.encryptedTokenFailureMessage)
        }
    }

    func testRefreshShouldLogoutResponseMapsToReloginRequired() async throws {
        let provider = makeProvider()

        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/usage-summary" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error":"not_authenticated"}"#.utf8))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"access_token":"","id_token":"","shouldLogout":true}"#.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected unauthorizedDetail")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let message) = error else {
                return XCTFail("Expected unauthorizedDetail, got \(error)")
            }
            XCTAssertEqual(message, CursorSessionAuth.reloginRequiredMessage)
        }
    }

    func testEncryptedCredentialsAreNotWrittenBackAfterRefresh() async throws {
        let sqlite = RecordingCursorSQLite(rows: [
            ["cursorAuth/accessToken", CursorSafeStorage.encryptedValuePrefix + "djEwZXhwaXJlZA=="],
            ["cursorAuth/refreshToken", CursorSafeStorage.encryptedValuePrefix + "djEwcmVmcmVzaA=="]
        ])
        let expiredJWT = Self.sessionJWT(expiration: 1)
        let refreshedJWT = Self.sessionJWT(expiration: 4_102_444_800)
        let provider = makeProvider(
            sqlite: sqlite,
            safeStorage: CursorSafeStorage(
                readPassword: { "keychain-passphrase" },
                decrypt: { payload, _ in
                    payload == "djEwcmVmcmVzaA==" ? "keychain-passphrase" : expiredJWT
                }
            )
        )
        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/usage-summary" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.usageSummaryJSON.utf8))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"\#(refreshedJWT)"}"#
            return (response, Data(body.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        _ = try await provider.fetch()

        XCTAssertTrue(
            sqlite.executedSQLs.isEmpty,
            "writing a plaintext token into an encrypted store breaks Cursor itself"
        )
    }

    func testFetchUsesUnifiedWeeklyPoolInsteadOfStaleMonthlySummary() async throws {
        let provider = makeProvider()
        CursorMockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            switch request.url?.path {
            case "/api/usage-summary":
                let body = """
                {
                  "membershipType": "enterprise",
                  "billingCycleStart": "2026-10-01T00:00:00.000Z",
                  "billingCycleEnd": "2026-11-01T00:00:00.000Z",
                  "individualUsage": {
                    "plan": {
                      "enabled": true,
                      "autoPercentUsed": 62.86,
                      "apiPercentUsed": 0,
                      "totalPercentUsed": 100
                    },
                    "onDemand": { "enabled": true, "used": 447, "limit": null }
                  }
                }
                """
                return (response, Data(body.utf8))
            case "/api/dashboard/get-sand-usage-status":
                XCTAssertEqual(request.httpMethod, "POST")
                let body = """
                {
                  "usagePercent": 10.205850487540628,
                  "nextResetTimestampUtc": "2026-10-22T10:27:36Z",
                  "hasNonZeroIncludedLimit": true,
                  "grokPlanLabel": "Grok Bot Plan",
                  "cursorPlanName": "Premium",
                  "isUnified": true,
                  "billingBrand": "SAND_BILLING_BRAND_GROK"
                }
                """
                return (response, Data(body.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        let weekly = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(weekly.title, "Weekly")
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.usedPercent, 10.205850487540628, accuracy: 0.001)
        XCTAssertEqual(weekly.remainingPercent, 89.79414951245937, accuracy: 0.001)
        let expectedReset = try XCTUnwrap(XSubscriptionQuota.parseTimestamp("2026-10-22T10:27:36Z"))
        let resetAt = try XCTUnwrap(weekly.resetAt)
        XCTAssertEqual(resetAt.timeIntervalSince1970, expectedReset.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(snapshot.extras["planType"], "Premium")
        XCTAssertEqual(snapshot.extras["quotaScope"], "x-subscription")
        XCTAssertEqual(snapshot.note, "Plan Premium | Weekly 90%")
        XCTAssertFalse(snapshot.quotaWindows.contains { $0.title == "Cursor Models" || $0.title == "Other Models" })
    }

    func testFetchKeepsLegacyPoolsWhenSandStatusIsUnavailable() async throws {
        let provider = makeProvider()
        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/dashboard/get-sand-usage-status" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.usageSummaryJSON.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.quotaWindows.map(\.title), ["Cursor Models", "Other Models"])
        XCTAssertNil(snapshot.extras["quotaScope"])
    }

    func testPlaintextCredentialsAreStillWrittenBackAfterRefresh() async throws {
        let sqlite = RecordingCursorSQLite(rows: [
            ["cursorAuth/accessToken", Self.sessionJWT(expiration: 1)],
            ["cursorAuth/refreshToken", "keychain-passphrase"]
        ])
        let refreshedJWT = Self.sessionJWT(expiration: 4_102_444_800)
        let provider = makeProvider(sqlite: sqlite)
        CursorMockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/usage-summary" {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(Self.usageSummaryJSON.utf8))
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"\#(refreshedJWT)"}"#
            return (response, Data(body.utf8))
        }
        defer { CursorMockURLProtocol.requestHandler = nil }

        _ = try await provider.fetch()

        XCTAssertEqual(sqlite.executedSQLs.count, 1)
        XCTAssertTrue(try XCTUnwrap(sqlite.executedSQLs.first).contains(refreshedJWT))
    }

    private static let usageSummaryJSON = """
    {
      "membershipType": "pro",
      "billingCycleEnd": "2026-11-12T07:04:37.000Z",
      "individualUsage": {
        "plan": {
          "enabled": true,
          "autoPercentUsed": 14.822222222222223,
          "apiPercentUsed": 0
        }
      }
    }
    """

    private static func sessionJWT(expiration: Int, subject: String = "user|123") -> String {
        let header = base64URL(#"{"alg":"HS256","typ":"JWT"}"#)
        let payload = base64URL(#"{"sub":"\#(subject)","exp":\#(expiration)}"#)
        return "\(header).\(payload).signature"
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeProvider(
        stateDatabasePath: String? = nil,
        rows: [[String]]? = nil,
        sqlite: (any SQLiteQuerying)? = nil,
        safeStorage: CursorSafeStorage = .default
    ) -> CursorProvider {
        let resolvedPath: String
        if let stateDatabasePath {
            resolvedPath = stateDatabasePath
        } else {
            let directory = NSTemporaryDirectory() + "cursor-state-\(UUID().uuidString)"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            resolvedPath = directory + "/state.vscdb"
            FileManager.default.createFile(atPath: resolvedPath, contents: Data())
        }

        let resolvedRows = rows ?? [
            ["cursorAuth/accessToken", "fake.header.signature"],
            ["cursorAuth/refreshToken", "fake-refresh-token"],
            ["cursorAuth/cachedEmail", "user@example.com"]
        ]

        return CursorProvider(
            descriptor: ProviderDescriptor.defaultOfficialCursor(),
            session: makeMockSession(),
            sqlite: sqlite ?? StubCursorSQLite(rows: resolvedRows),
            stateDatabasePath: resolvedPath,
            safeStorage: safeStorage
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

/// SQLite 桩：记录 `execute` 写入，用来断言加密存储时不会把明文 token 写回。
private final class RecordingCursorSQLite: SQLiteQuerying, @unchecked Sendable {
    private let lock = NSLock()
    private let storedRows: [[String]]
    private var recordedSQLs: [String] = []

    init(rows: [[String]]) {
        self.storedRows = rows
    }

    var executedSQLs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSQLs
    }

    func rows(databasePath: String, query: String, separator: String) -> [[String]] {
        storedRows
    }

    func query(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        makeResult(databasePath: databasePath)
    }

    func snapshotQuery(databasePath: String, query: String, separator: String) -> SQLiteShell.QueryResult {
        makeResult(databasePath: databasePath)
    }

    func execute(databasePath: String, sql: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        recordedSQLs.append(sql)
        return true
    }

    private func makeResult(databasePath: String) -> SQLiteShell.QueryResult {
        SQLiteShell.QueryResult(
            databasePath: databasePath,
            executedPath: databasePath,
            mode: .readOnlySnapshot,
            status: 0,
            stdout: "",
            stderr: "",
            rows: storedRows
        )
    }
}
