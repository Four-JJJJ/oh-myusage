import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class GrokBotProviderTests: XCTestCase {
    private static let sampleJWT = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJhdXRoMHx1c2VyXzEyMyIsImVtYWlsIjoidGVzdGVyQGV4YW1wbGUuY29tIn0.sig"

    // MARK: - Parsing

    func testParseSnapshotSuperGrokWeeklyAndOnDemand() throws {
        let snapshot = try GrokBotProvider.parseSnapshot(
            sand: [
                "hasNonZeroIncludedLimit": true,
                "usagePercent": 42.0,
                "nextResetTimestampUtc": "2026-09-19T12:00:00Z",
                "grokPlanLabel": "SuperGrok Plus"
            ],
            period: [
                "billingCycleEnd": "1771077734000",
                "spendLimitUsage": [
                    "individualUsed": 25.0,
                    "individualLimit": 100.0
                ]
            ],
            descriptor: .defaultOfficialGrokBot(),
            credentials: makeCredentials(source: .grokBotApp, email: "tester@example.com"),
            planNameOverride: nil
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.extras["planType"], "SuperGrok Plus")
        XCTAssertEqual(snapshot.authSourceLabel, "Grok Bot")
        XCTAssertEqual(snapshot.accountLabel, "tester@example.com")
        XCTAssertTrue(snapshot.note.hasPrefix("Plan SuperGrok Plus | Weekly 58%"))

        let weekly = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(weekly.title, "Weekly")
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.usedPercent, 42, accuracy: 0.001)
        XCTAssertEqual(weekly.remainingPercent, 58, accuracy: 0.001)

        let onDemand = try XCTUnwrap(snapshot.quotaWindows.last)
        XCTAssertEqual(onDemand.title, "On-Demand")
        XCTAssertEqual(onDemand.kind, .extraUsage)
        XCTAssertEqual(onDemand.usedPercent, 25, accuracy: 0.001)
    }

    func testParseSnapshotCursorProWithoutOnDemandLimit() throws {
        let snapshot = try GrokBotProvider.parseSnapshot(
            sand: [
                "hasNonZeroIncludedLimit": true,
                "usagePercent": 18.5,
                "nextResetTimestampUtc": 1_790_000_000,
                "grokPlanLabel": "Cursor Pro"
            ],
            period: [
                "spendLimitUsage": [
                    "individualUsed": 12,
                    "individualLimit": 0
                ]
            ],
            descriptor: .defaultOfficialGrokBot(),
            credentials: makeCredentials(source: .cursorIDE, membershipType: "pro"),
            planNameOverride: nil
        )

        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.kind, .weekly)
        XCTAssertEqual(snapshot.extras["planType"], "Cursor Pro")
        XCTAssertEqual(snapshot.authSourceLabel, "Cursor")
        XCTAssertEqual(snapshot.note, "Plan Cursor Pro | Weekly 82%")
    }

    func testParseSnapshotFallsBackToMembershipTypeWhenPlanLabelMissing() throws {
        let snapshot = try GrokBotProvider.parseSnapshot(
            sand: [
                "usagePercent": 10
            ],
            period: nil,
            descriptor: .defaultOfficialGrokBot(),
            credentials: makeCredentials(source: .cursorIDE, membershipType: "ultra"),
            planNameOverride: nil
        )

        XCTAssertEqual(snapshot.extras["planType"], "Cursor Ultra")
    }

    func testParseSnapshotRejectsAccountsWithoutBotAllowance() {
        XCTAssertThrowsError(
            try GrokBotProvider.parseSnapshot(
                sand: [
                    "hasNonZeroIncludedLimit": false,
                    "usagePercent": 0
                ],
                period: nil,
                descriptor: .defaultOfficialGrokBot(),
                credentials: makeCredentials(source: .cursorIDE),
                planNameOverride: nil
            )
        ) { error in
            guard let providerError = error as? ProviderError,
                  case .unavailable(let message) = providerError else {
                return XCTFail("Expected unavailable, got \(error)")
            }
            XCTAssertTrue(message.contains("Grok Bot"))
        }
    }

    func testParseSnapshotRejectsMissingUsagePercent() {
        XCTAssertThrowsError(
            try GrokBotProvider.parseSnapshot(
                sand: ["hasNonZeroIncludedLimit": true],
                period: nil,
                descriptor: .defaultOfficialGrokBot(),
                credentials: makeCredentials(source: .cursorIDE),
                planNameOverride: nil
            )
        ) { error in
            guard let providerError = error as? ProviderError,
                  case .invalidResponse = providerError else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        }
    }

    func testParseTimestampAcceptsISOAndEpochMillis() throws {
        let iso = try XCTUnwrap(GrokBotProvider.parseTimestamp("2026-09-19T12:00:00Z"))
        let expectedISO = try XCTUnwrap(OfficialValueParser.isoDate("2026-09-19T12:00:00Z"))
        XCTAssertEqual(iso.timeIntervalSince1970, expectedISO.timeIntervalSince1970, accuracy: 1)

        let millis = GrokBotProvider.parseTimestamp("1771077734000")
        XCTAssertEqual(millis?.timeIntervalSince1970 ?? 0, 1_771_077_734, accuracy: 1)

        let seconds = GrokBotProvider.parseTimestamp(1_790_000_000)
        XCTAssertEqual(seconds?.timeIntervalSince1970 ?? 0, 1_790_000_000, accuracy: 0.001)

        XCTAssertNil(GrokBotProvider.parseTimestamp("not-a-date"))
        XCTAssertNil(GrokBotProvider.parseTimestamp(nil))
    }

    // MARK: - Desktop secrets

    func testParseActiveAccountFromEncodedCursorAccountsJSON() throws {
        let payload = """
        {
          "cursor-accounts": "{\\"active\\":\\"acct-1\\",\\"accounts\\":{\\"acct-1\\":{\\"cursor-access-token\\":\\"enc-access\\"}}}"
        }
        """
        let account = try GrokBotDesktopCredentialStore.parseActiveAccount(from: Data(payload.utf8))
        XCTAssertEqual(OfficialValueParser.string(account["cursor-access-token"]), "enc-access")
    }

    func testExtractJWTIgnoresChromiumPadding() {
        let padded = "xx" + Self.sampleJWT + "\u{0000}tail"
        XCTAssertEqual(GrokBotDesktopCredentialStore.extractJWT(from: padded), Self.sampleJWT)
        XCTAssertNil(GrokBotDesktopCredentialStore.extractJWT(from: "not-a-jwt"))
    }

    func testDesktopStoreDecryptsActiveAccountWithoutTouchingKeychain() throws {
        let secrets = """
        {
          "cursor-accounts": {
            "active": "acct-1",
            "accounts": {
              "acct-1": {
                "cursor-access-token": "enc-access",
                "cursor-refresh-token": "enc-refresh",
                "cursor-account-profile": "enc-profile"
              }
            }
          }
        }
        """
        let store = GrokBotDesktopCredentialStore(
            secretsFilePath: "/tmp/sand-secrets.json",
            readPassword: { "passphrase" },
            readFile: { _ in Data(secrets.utf8) },
            decrypt: { encoded, passphrase in
                XCTAssertEqual(passphrase, "passphrase")
                switch encoded {
                case "enc-access":
                    return "pad" + Self.sampleJWT
                case "enc-refresh":
                    return "refresh-token-value!"
                case "enc-profile":
                    return #"{"email":"bot@example.com"}"#
                default:
                    return nil
                }
            }
        )

        let credentials = try store.load()
        XCTAssertEqual(credentials.accessToken, Self.sampleJWT)
        XCTAssertEqual(credentials.refreshToken, "refresh-token-value")
        XCTAssertEqual(credentials.email, "bot@example.com")
        XCTAssertEqual(credentials.source, .grokBotApp)
    }

    func testLoadForGrokBotPrefersDesktopStoreOverIDE() throws {
        let auth = CursorSessionAuth(
            session: URLSession(configuration: .ephemeral),
            sqlite: StubGrokBotSQLite(rows: [
                ["cursorAuth/accessToken", "ide-token"],
                ["cursorAuth/cachedEmail", "ide@example.com"]
            ]),
            stateDatabasePath: makeTempStateDatabase(),
            grokBotStore: GrokBotDesktopCredentialStore(
                secretsFilePath: "/tmp/sand-secrets.json",
                readPassword: { "x" },
                readFile: { _ in Data(#"{"cursor-accounts":{"active":"a","accounts":{"a":{"cursor-access-token":"enc"}}}}"#.utf8) },
                decrypt: { _, _ in Self.sampleJWT }
            )
        )

        let credentials = try auth.loadForGrokBot()
        XCTAssertEqual(credentials.accessToken, Self.sampleJWT)
        XCTAssertEqual(credentials.source, .grokBotApp)
    }

    func testLoadForGrokBotFallsBackToIDEWhenDesktopStoreFails() throws {
        let auth = CursorSessionAuth(
            session: URLSession(configuration: .ephemeral),
            sqlite: StubGrokBotSQLite(rows: [
                ["cursorAuth/accessToken", "ide-token"],
                ["cursorAuth/cachedEmail", "ide@example.com"],
                ["cursorAuth/stripeMembershipType", "pro"]
            ]),
            stateDatabasePath: makeTempStateDatabase(),
            grokBotStore: GrokBotDesktopCredentialStore(
                secretsFilePath: "/missing/sand-secrets.json",
                readPassword: { throw ProviderError.missingCredential("Grok Bot Safe Storage") },
                readFile: { _ in throw NSError(domain: "test", code: 1) },
                decrypt: { _, _ in nil }
            )
        )

        let credentials = try auth.loadForGrokBot()
        XCTAssertEqual(credentials.accessToken, "ide-token")
        XCTAssertEqual(credentials.email, "ide@example.com")
        XCTAssertEqual(credentials.membershipType, "pro")
        XCTAssertEqual(credentials.source, .cursorIDE)
    }

    func testDisplayPlanNameMapsCursorMembership() {
        XCTAssertEqual(CursorSessionAuth.displayPlanName(grokPlanLabel: "SuperGrok", membershipType: "pro"), "SuperGrok")
        XCTAssertEqual(CursorSessionAuth.displayPlanName(grokPlanLabel: nil, membershipType: "pro"), "Cursor Pro")
        XCTAssertEqual(CursorSessionAuth.displayPlanName(grokPlanLabel: nil, membershipType: "pro_plus"), "Cursor Pro+")
        XCTAssertEqual(CursorSessionAuth.displayPlanName(grokPlanLabel: nil, membershipType: nil), "unknown")
    }

    // MARK: - Fetch

    func testFetchUsesConnectRPCAndMergesWeeklyPlan() async throws {
        let provider = makeProvider(store: makeDesktopStore())
        GrokBotMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-cursor-client-type"), "sand")
            switch request.url?.path {
            case "/aiserver.v1.DashboardService/GetSandUsageStatus":
                let body = #"{"hasNonZeroIncludedLimit":true,"usagePercent":25,"grokPlanLabel":"SuperGrok","nextResetTimestampUtc":"2026-09-19T12:00:00Z"}"#
                return (Self.okResponse(for: request), Data(body.utf8))
            case "/aiserver.v1.DashboardService/GetCurrentPeriodUsage":
                let body = #"{"spendLimitUsage":{"individualUsed":10,"individualLimit":40}}"#
                return (Self.okResponse(for: request), Data(body.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        defer { GrokBotMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.extras["planType"], "SuperGrok")
        XCTAssertEqual(snapshot.quotaWindows.count, 2)
        XCTAssertEqual(snapshot.authSourceLabel, "Grok Bot")
        XCTAssertEqual(snapshot.quotaWindows.last?.usedPercent ?? -1, 25, accuracy: 0.001)
    }

    func testFetchFallsBackToRESTWhenConnectRPCFails() async throws {
        let provider = makeProvider(store: makeDesktopStore())
        GrokBotMockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/aiserver.v1.DashboardService/GetSandUsageStatus",
                 "/aiserver.v1.DashboardService/GetCurrentPeriodUsage":
                return (Self.response(for: request, statusCode: 500), Data(#"{"error":"rpc down"}"#.utf8))
            case "/api/dashboard/get-sand-usage-status":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
                let body = #"{"hasNonZeroIncludedLimit":true,"usagePercent":33}"#
                return (Self.okResponse(for: request), Data(body.utf8))
            case "/api/usage-summary":
                return (Self.okResponse(for: request), Data(#"{"membershipType":"pro"}"#.utf8))
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        defer { GrokBotMockURLProtocol.requestHandler = nil }

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.extras["planType"], "Cursor Pro")
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.usedPercent ?? -1, 33, accuracy: 0.001)
    }

    func testFetchDoesNotTouchNetworkWithoutCredentials() async throws {
        let missingDB = NSTemporaryDirectory() + "grokbot-missing-\(UUID().uuidString)/state.vscdb"
        let provider = GrokBotProvider(
            descriptor: .defaultOfficialGrokBot(),
            session: makeMockSession(),
            sqlite: StubGrokBotSQLite(rows: []),
            stateDatabasePath: missingDB,
            grokBotStore: GrokBotDesktopCredentialStore(
                secretsFilePath: "/missing/sand-secrets.json",
                readPassword: { "x" },
                readFile: { _ in throw NSError(domain: "test", code: 1) },
                decrypt: { _, _ in nil }
            )
        )
        GrokBotMockURLProtocol.requestHandler = { _ in
            XCTFail("network must not be reached without credentials")
            throw URLError(.badURL)
        }
        defer { GrokBotMockURLProtocol.requestHandler = nil }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                return XCTFail("Expected missingCredential, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func makeCredentials(
        source: CursorSessionCredentials.Source,
        email: String? = nil,
        membershipType: String? = nil
    ) -> CursorSessionCredentials {
        CursorSessionCredentials(
            accessToken: Self.sampleJWT,
            refreshToken: "refresh",
            email: email,
            membershipType: membershipType,
            source: source,
            databasePath: nil
        )
    }

    private func makeDesktopStore() -> GrokBotDesktopCredentialStore {
        GrokBotDesktopCredentialStore(
            secretsFilePath: "/tmp/sand-secrets.json",
            readPassword: { "x" },
            readFile: { _ in Data(#"{"cursor-accounts":{"active":"a","accounts":{"a":{"cursor-access-token":"enc"}}}}"#.utf8) },
            decrypt: { _, _ in Self.sampleJWT }
        )
    }

    private func makeProvider(store: GrokBotDesktopCredentialStore) -> GrokBotProvider {
        GrokBotProvider(
            descriptor: .defaultOfficialGrokBot(),
            session: makeMockSession(),
            sqlite: StubGrokBotSQLite(rows: []),
            stateDatabasePath: makeTempStateDatabase(),
            grokBotStore: store
        )
    }

    private func makeTempStateDatabase() -> String {
        let directory = NSTemporaryDirectory() + "grokbot-state-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/state.vscdb"
        FileManager.default.createFile(atPath: path, contents: Data())
        return path
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GrokBotMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func okResponse(for request: URLRequest) -> HTTPURLResponse {
        response(for: request, statusCode: 200)
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
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
