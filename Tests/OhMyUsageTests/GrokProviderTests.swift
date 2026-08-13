import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class GrokProviderTests: XCTestCase {
    // MARK: - Parsing

    func testParseSnapshotWeeklyWithUsageAndPayg() throws {
        let descriptor = ProviderDescriptor.defaultOfficialGrok()

        let snapshot = try GrokProvider.parseSnapshot(
            root: [
                "config": [
                    "creditUsagePercent": 37.5,
                    "currentPeriod": [
                        "type": "USAGE_PERIOD_TYPE_WEEKLY",
                        "start": "2026-08-13T03:47:03.411698+00:00",
                        "end": "2026-08-20T03:47:03.411698+00:00"
                    ],
                    "onDemandCap": ["val": 2500],
                    "onDemandUsed": ["val": 625],
                    "isUnifiedBillingUser": true
                ]
            ],
            descriptor: descriptor
        )

        XCTAssertEqual(snapshot.unit, "%")
        XCTAssertEqual(snapshot.used ?? -1, 37.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining ?? -1, 62.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.quotaWindows.count, 2)

        let weekly = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(weekly.title, "Weekly")
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.usedPercent, 37.5, accuracy: 0.001)
        let resetAt = try XCTUnwrap(weekly.resetAt)
        XCTAssertEqual(resetAt.timeIntervalSince1970, 1787197623.411, accuracy: 1)

        let payg = try XCTUnwrap(snapshot.quotaWindows.last)
        XCTAssertEqual(payg.title, "PAYG")
        XCTAssertEqual(payg.kind, .extraUsage)
        XCTAssertEqual(payg.usedPercent, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["payAsYouGoCap"], "2500")
        XCTAssertEqual(snapshot.extras["payAsYouGoUsed"], "625")
    }

    func testParseSnapshotTreatsMissingPercentAsZero() throws {
        // proto-JSON omits zero-valued fields; observed live from an unused account.
        let descriptor = ProviderDescriptor.defaultOfficialGrok()

        let snapshot = try GrokProvider.parseSnapshot(
            root: [
                "config": [
                    "currentPeriod": [
                        "type": "USAGE_PERIOD_TYPE_WEEKLY",
                        "start": "2026-08-13T03:47:03.411698+00:00",
                        "end": "2026-08-20T03:47:03.411698+00:00"
                    ],
                    "onDemandCap": ["val": 0],
                    "isUnifiedBillingUser": true
                ]
            ],
            descriptor: descriptor
        )

        XCTAssertEqual(snapshot.used ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.kind, .weekly)
    }

    func testParseSnapshotNonWeeklyPeriodUsesCustomKind() throws {
        let descriptor = ProviderDescriptor.defaultOfficialGrok()

        let snapshot = try GrokProvider.parseSnapshot(
            root: [
                "config": [
                    "creditUsagePercent": 12,
                    "currentPeriod": [
                        "type": "USAGE_PERIOD_TYPE_MONTHLY",
                        "start": "2026-08-01T00:00:00Z",
                        "end": "2026-09-01T00:00:00Z"
                    ]
                ]
            ],
            descriptor: descriptor
        )

        let window = try XCTUnwrap(snapshot.quotaWindows.first)
        XCTAssertEqual(window.kind, .custom)
        XCTAssertEqual(window.title, "Period")
    }

    func testParseSnapshotLowRemainingSetsWarning() throws {
        let descriptor = ProviderDescriptor.defaultOfficialGrok()

        let snapshot = try GrokProvider.parseSnapshot(
            root: [
                "config": [
                    "creditUsagePercent": 95,
                    "currentPeriod": [
                        "type": "USAGE_PERIOD_TYPE_WEEKLY",
                        "start": "2026-08-13T03:47:03Z",
                        "end": "2026-08-20T03:47:03Z"
                    ]
                ]
            ],
            descriptor: descriptor
        )

        XCTAssertEqual(snapshot.status, .warning)
    }

    func testParseSnapshotMissingConfigThrows() {
        let descriptor = ProviderDescriptor.defaultOfficialGrok()

        XCTAssertThrowsError(
            try GrokProvider.parseSnapshot(root: ["unexpected": true], descriptor: descriptor)
        ) { error in
            guard case .invalidResponse = error as? ProviderError else {
                XCTFail("Expected invalidResponse, got \(error)")
                return
            }
        }
    }

    // MARK: - Credentials

    func testParseCredentialsExtractsFieldsAndPrefersLatestExpiry() throws {
        let json: [String: Any] = [
            "https://auth.x.ai::client-old": [
                "key": "token-old",
                "refresh_token": "refresh-old",
                "expires_at": "2026-08-13T08:00:00Z",
                "email": "old@example.com"
            ],
            "https://auth.x.ai::client-new": [
                "key": "token-new",
                "refresh_token": "refresh-new",
                "expires_at": "2026-08-13T11:08:51.035329Z",
                "email": "new@example.com",
                "oidc_client_id": "explicit-client-id"
            ]
        ]

        let credentials = try XCTUnwrap(GrokProvider.parseCredentials(json: json, filePath: "/tmp/auth.json"))

        XCTAssertEqual(credentials.accessToken, "token-new")
        XCTAssertEqual(credentials.refreshToken, "refresh-new")
        XCTAssertEqual(credentials.email, "new@example.com")
        XCTAssertEqual(credentials.resolvedClientID, "explicit-client-id")
        let expiresAt = try XCTUnwrap(credentials.expiresAt)
        XCTAssertEqual(expiresAt.timeIntervalSince1970, 1786619331.035, accuracy: 1)
    }

    func testResolvedClientIDFallsBackToEntryKeySuffixThenDefault() {
        let fromEntryKey = GrokProvider.GrokCredentials(
            filePath: "/tmp/auth.json",
            entryKey: "https://auth.x.ai::suffix-client-id",
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            email: nil,
            oidcClientID: nil
        )
        XCTAssertEqual(fromEntryKey.resolvedClientID, "suffix-client-id")

        let fromDefault = GrokProvider.GrokCredentials(
            filePath: "/tmp/auth.json",
            entryKey: "no-separator",
            accessToken: "token",
            refreshToken: nil,
            expiresAt: nil,
            email: nil,
            oidcClientID: nil
        )
        XCTAssertEqual(fromDefault.resolvedClientID, GrokProvider.defaultOIDCClientID)
    }

    func testParseCredentialsReturnsNilWithoutUsableEntry() {
        XCTAssertNil(GrokProvider.parseCredentials(json: [:], filePath: "/tmp/auth.json"))
        XCTAssertNil(GrokProvider.parseCredentials(
            json: ["entry": ["refresh_token": "only-refresh"]],
            filePath: "/tmp/auth.json"
        ))
    }

    func testParseDateHandlesMicrosecondPrecision() throws {
        let microseconds = try XCTUnwrap(GrokProvider.parseDate("2026-08-13T03:47:03.411698+00:00"))
        XCTAssertEqual(microseconds.timeIntervalSince1970, 1786592823.411, accuracy: 0.01)

        let plain = try XCTUnwrap(GrokProvider.parseDate("2026-08-13T03:47:03Z"))
        XCTAssertEqual(plain.timeIntervalSince1970, 1786592823, accuracy: 0.01)

        XCTAssertNil(GrokProvider.parseDate(nil))
        XCTAssertNil(GrokProvider.parseDate("not a date"))
    }

    func testNeedsRefreshUsesFiveMinuteBuffer() {
        let now = Date()
        XCTAssertFalse(GrokProvider.needsRefresh(expiresAt: nil, now: now))
        XCTAssertFalse(GrokProvider.needsRefresh(expiresAt: now.addingTimeInterval(10 * 60), now: now))
        XCTAssertTrue(GrokProvider.needsRefresh(expiresAt: now.addingTimeInterval(2 * 60), now: now))
        XCTAssertTrue(GrokProvider.needsRefresh(expiresAt: now.addingTimeInterval(-1), now: now))
    }

    func testResolvedAuthFilePathPrefersGrokHome() {
        XCTAssertEqual(
            GrokProvider.resolvedAuthFilePath(homeDirectory: "/Users/tester", environment: [:]),
            "/Users/tester/.grok/auth.json"
        )
        XCTAssertEqual(
            GrokProvider.resolvedAuthFilePath(
                homeDirectory: "/Users/tester",
                environment: ["GROK_HOME": "/custom/grok/"]
            ),
            "/custom/grok/auth.json"
        )
    }

    // MARK: - Fetch (mocked HTTP)

    func testFetchReadsLocalAuthCallsBillingAndMergesPlan() async throws {
        let home = try makeTemporaryHome(authJSON: [
            "https://auth.x.ai::client-id": [
                "key": "access-token-123",
                "refresh_token": "refresh-token-123",
                "expires_at": iso8601(Date().addingTimeInterval(3600)),
                "email": "tester@example.com"
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: home) }

        let session = makeMockSession()
        GrokMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")

            switch request.url?.path {
            case "/v1/billing":
                XCTAssertEqual(request.url?.query, "format=credits")
                let body = #"""
                {"config":{"creditUsagePercent":25.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-13T03:47:03.411698+00:00","end":"2026-08-20T03:47:03.411698+00:00"},"onDemandCap":{"val":0},"isUnifiedBillingUser":true}}
                """#
                return (Self.okResponse(for: request), Data(body.utf8))
            case "/v1/settings":
                let body = #"{"subscription_tier_display":"SuperGrok"}"#
                return (Self.okResponse(for: request), Data(body.utf8))
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        defer { GrokMockURLProtocol.requestHandler = nil }

        let provider = GrokProvider(
            descriptor: .defaultOfficialGrok(),
            session: session,
            homeDirectory: { home },
            environment: { [:] }
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.used ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountLabel, "tester@example.com")
        XCTAssertEqual(snapshot.authSourceLabel, "Grok CLI")
        XCTAssertEqual(snapshot.extras["planType"], "SuperGrok")
        XCTAssertTrue(snapshot.note.hasPrefix("Plan SuperGrok | Weekly 75%"))
        XCTAssertEqual(snapshot.sourceLabel, "API")
    }

    func testFetchRefreshesTokenOn401AndPersistsRotatedCredentials() async throws {
        let home = try makeTemporaryHome(authJSON: [
            "https://auth.x.ai::client-id": [
                "key": "stale-token",
                "refresh_token": "refresh-token-123",
                "expires_at": iso8601(Date().addingTimeInterval(3600)),
                "email": "tester@example.com"
            ]
        ])
        defer { try? FileManager.default.removeItem(atPath: home) }

        let session = makeMockSession()
        GrokMockURLProtocol.requestHandler = { request in
            if request.url?.host == "auth.x.ai" {
                XCTAssertEqual(request.url?.path, "/oauth2/token")
                let body = #"{"access_token":"fresh-token","refresh_token":"rotated-refresh","expires_in":3600}"#
                return (Self.okResponse(for: request), Data(body.utf8))
            }

            switch request.url?.path {
            case "/v1/billing":
                let authorization = request.value(forHTTPHeaderField: "Authorization")
                if authorization == "Bearer stale-token" {
                    return (Self.response(for: request, statusCode: 401), Data())
                }
                XCTAssertEqual(authorization, "Bearer fresh-token")
                let body = #"""
                {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-13T03:47:03.411698+00:00","end":"2026-08-20T03:47:03.411698+00:00"}}}
                """#
                return (Self.okResponse(for: request), Data(body.utf8))
            case "/v1/settings":
                return (Self.response(for: request, statusCode: 404), Data())
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }
        defer { GrokMockURLProtocol.requestHandler = nil }

        let provider = GrokProvider(
            descriptor: .defaultOfficialGrok(),
            session: session,
            homeDirectory: { home },
            environment: { [:] }
        )

        let snapshot = try await provider.fetch()
        XCTAssertEqual(snapshot.remaining ?? -1, 100, accuracy: 0.001)
        XCTAssertNil(snapshot.extras["planType"])

        let persisted = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: home + "/.grok/auth.json"))
        ) as? [String: Any]
        let entry = try XCTUnwrap(persisted?["https://auth.x.ai::client-id"] as? [String: Any])
        XCTAssertEqual(entry["key"] as? String, "fresh-token")
        XCTAssertEqual(entry["refresh_token"] as? String, "rotated-refresh")
        XCTAssertEqual(entry["email"] as? String, "tester@example.com")
    }

    func testFetchThrowsMissingCredentialWithoutAuthFile() async throws {
        let home = NSTemporaryDirectory() + "grok-tests-missing-\(UUID().uuidString)"

        let provider = GrokProvider(
            descriptor: .defaultOfficialGrok(),
            session: makeMockSession(),
            homeDirectory: { home },
            environment: { [:] }
        )

        do {
            _ = try await provider.fetch()
            XCTFail("Expected ProviderError.missingCredential")
        } catch let error as ProviderError {
            guard case .missingCredential = error else {
                XCTFail("Expected missingCredential, got \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func makeTemporaryHome(authJSON: [String: Any]) throws -> String {
        let home = NSTemporaryDirectory() + "grok-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: home + "/.grok",
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: authJSON, options: [.prettyPrinted])
        try data.write(to: URL(fileURLWithPath: home + "/.grok/auth.json"))
        return home
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrokMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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

private final class GrokMockURLProtocol: URLProtocol {
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
