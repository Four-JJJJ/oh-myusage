import Foundation
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class ClaudeProfileSnapshotServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ClaudeSnapshotMockURLProtocol.requestHandler = nil
    }

    func testFetchSnapshotSuccessAddsClaudeMetadata() async throws {
        ClaudeSnapshotMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-success")
            let body: [String: Any] = [
                "five_hour": ["utilization": 40, "resets_at": "2026-04-20T10:00:00Z"],
                "seven_day": ["utilization": 55, "resets_at": "2026-04-26T00:00:00Z"]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        let profile = makeProfile(
            slotID: .a,
            accountID: "acc-a",
            email: "a@example.com",
            accessToken: "access-success",
            refreshToken: "refresh-success",
            expiresAtMs: 4_102_444_800_000
        )

        let result = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)

        XCTAssertEqual(result.snapshot.accountLabel, "a@example.com")
        XCTAssertEqual(result.snapshot.rawMeta["claude.accountLabel"], "a@example.com")
        XCTAssertEqual(result.snapshot.rawMeta["claude.accountId"], "acc-a")
        XCTAssertEqual(result.snapshot.rawMeta["claude.configDir"], profile.configDir)
        XCTAssertNotNil(result.snapshot.rawMeta["claude.credentialFingerprint"])
        XCTAssertNil(result.refreshedCredentialsJSON)
    }

    func testFetchSnapshotRefreshesExpiredCredentials() async throws {
        ClaudeSnapshotMockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://platform.claude.com/v1/oauth/token" {
                let body: [String: Any] = [
                    "access_token": "access-refreshed",
                    "refresh_token": "refresh-refreshed",
                    "expires_in": 3600
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            if url == "https://api.anthropic.com/api/oauth/usage" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-refreshed")
                let body: [String: Any] = [
                    "five_hour": ["utilization": 20, "resets_at": "2026-04-20T10:00:00Z"],
                    "seven_day": ["utilization": 35, "resets_at": "2026-04-26T00:00:00Z"]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            throw URLError(.badURL)
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        let expired = Date(timeIntervalSince1970: 1_000).timeIntervalSince1970 * 1000
        let profile = makeProfile(
            slotID: .a,
            accountID: "acc-refresh",
            email: "refresh@example.com",
            accessToken: "access-expired",
            refreshToken: "refresh-expired",
            expiresAtMs: expired
        )

        let result = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)

        XCTAssertNotNil(result.refreshedCredentialsJSON)
        XCTAssertTrue(result.refreshedCredentialsJSON?.contains("access-refreshed") == true)
        XCTAssertEqual(result.snapshot.accountLabel, "refresh@example.com")
    }

    func testFetchSnapshotThrowsUnauthorizedOn401() async {
        ClaudeSnapshotMockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        let profile = makeProfile(
            slotID: .a,
            accountID: "acc-unauthorized",
            email: "unauthorized@example.com",
            accessToken: "access-unauthorized",
            refreshToken: nil,
            expiresAtMs: 4_102_444_800_000
        )

        do {
            _ = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)
            XCTFail("expected unauthorized error")
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchSnapshotRejectsInferenceOnlyCredentialsWithoutNetworkRequest() async {
        ClaudeSnapshotMockURLProtocol.requestHandler = { _ in
            XCTFail("network request should not happen for inference-only credentials")
            throw URLError(.badURL)
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialClaude()
        let profile = ClaudeAccountProfile(
            slotID: .a,
            displayName: "Claude A",
            source: .manualCredentials,
            configDir: "/tmp/claude-a",
            credentialsJSON: sampleInferenceOnlyCredentialsJSON(
                accountID: "acc-inference-only",
                email: "proxy@example.com",
                accessToken: "access-inference-only"
            ),
            accountId: "acc-inference-only",
            accountEmail: "proxy@example.com",
            credentialFingerprint: ClaudeAccountProfileStore.credentialFingerprint(for: "access-inference-only"),
            lastImportedAt: Date(),
            isCurrentSystemAccount: true
        )

        do {
            _ = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)
            XCTFail("expected unauthorizedDetail error")
        } catch let error as ProviderError {
            guard case .unauthorizedDetail(let detail) = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
            XCTAssertEqual(detail, "inference-only token cannot read Claude quota")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makeService() -> ClaudeProfileSnapshotService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaudeSnapshotMockURLProtocol.self]
        return ClaudeProfileSnapshotService(session: URLSession(configuration: configuration))
    }

    private func makeProfile(
        slotID: CodexSlotID,
        accountID: String,
        email: String,
        accessToken: String,
        refreshToken: String?,
        expiresAtMs: Double
    ) -> ClaudeAccountProfile {
        ClaudeAccountProfile(
            slotID: slotID,
            displayName: "Claude \(slotID.rawValue)",
            source: .manualCredentials,
            configDir: "/tmp/claude-\(slotID.rawValue.lowercased())",
            credentialsJSON: sampleCredentialsJSON(
                accountID: accountID,
                email: email,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAtMs: expiresAtMs
            ),
            accountId: accountID,
            accountEmail: email,
            credentialFingerprint: ClaudeAccountProfileStore.credentialFingerprint(for: accessToken),
            lastImportedAt: Date(),
            isCurrentSystemAccount: false
        )
    }

    private func sampleCredentialsJSON(
        accountID: String,
        email: String,
        accessToken: String,
        refreshToken: String?,
        expiresAtMs: Double
    ) -> String {
        var oauth: [String: Any] = [
            "accessToken": accessToken,
            "expiresAt": expiresAtMs,
            "subscriptionType": "pro",
            "scopes": ["user:profile"]
        ]
        if let refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        let root: [String: Any] = [
            "claudeAiOauth": oauth,
            "accountId": accountID,
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func sampleInferenceOnlyCredentialsJSON(
        accountID: String,
        email: String,
        accessToken: String
    ) -> String {
        let root: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": accessToken,
                "subscriptionType": "pro",
                "scopes": ["user:inference"]
            ],
            "accountId": accountID,
            "email": email
        ]
        let data = try! JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}

private final class ClaudeSnapshotMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = ClaudeSnapshotMockURLProtocol.requestHandler else {
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
