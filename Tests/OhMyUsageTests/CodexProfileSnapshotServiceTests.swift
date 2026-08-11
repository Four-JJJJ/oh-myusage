import Foundation
import XCTest
@testable import OhMyUsage

final class CodexProfileSnapshotServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        CodexSnapshotMockURLProtocol.requestHandler = nil
    }

    func testFetchSnapshotSuccessAddsCodexMetadata() async throws {
        CodexSnapshotMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-success")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "team-a")
            let body: [String: Any] = [
                "plan_type": "plus",
                "rate_limit": [
                    "primary_window": ["used_percent": 25, "reset_at": 1_760_000_000],
                    "secondary_window": ["used_percent": 40, "reset_at": 1_760_500_000]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialCodex()
        let profile = makeProfile(
            slotID: .a,
            accountID: "team-a",
            email: "slot-a@example.com",
            subject: "sub-slot-a",
            accessToken: "access-success",
            refreshToken: "refresh-success"
        )

        let result = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)

        XCTAssertNil(result.refreshedAuthJSON)
        XCTAssertEqual(result.snapshot.accountLabel, "slot-a@example.com")
        XCTAssertEqual(result.snapshot.rawMeta["codex.accountLabel"], "slot-a@example.com")
        XCTAssertEqual(result.snapshot.rawMeta["codex.accountId"], "team-a")
        XCTAssertEqual(result.snapshot.rawMeta["codex.teamId"], "team-a")
        XCTAssertNotNil(result.snapshot.rawMeta["codex.credentialFingerprint"])
    }

    func testFetchSnapshotRefreshesAndRetriesOnUnauthorized() async throws {
        var usageRequestCount = 0
        let refreshedIDToken = makeIDToken(
            email: "refreshed@example.com",
            subject: "sub-refreshed"
        )
        CodexSnapshotMockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://chatgpt.com/backend-api/wham/usage" {
                usageRequestCount += 1
                if usageRequestCount == 1 {
                    return (
                        HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                        Data()
                    )
                }
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-refreshed")
                XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "team-refresh")
                let body: [String: Any] = [
                    "plan_type": "plus",
                    "rate_limit": [
                        "primary_window": ["used_percent": 15, "reset_at": 1_760_000_000],
                        "secondary_window": ["used_percent": 30, "reset_at": 1_760_500_000]
                    ]
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            if url == "https://auth.openai.com/oauth/token" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Content-Type"),
                    "application/x-www-form-urlencoded"
                )
                let body: [String: Any] = [
                    "access_token": "access-refreshed",
                    "refresh_token": "refresh-token-new",
                    "id_token": refreshedIDToken
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: body)
                )
            }
            throw URLError(.badURL)
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialCodex()
        let profile = makeProfile(
            slotID: .a,
            accountID: "team-refresh",
            email: "stale@example.com",
            subject: "sub-stale",
            accessToken: "access-stale",
            refreshToken: "refresh-token-old"
        )

        let result = try await service.fetchSnapshot(profile: profile, descriptor: descriptor)

        XCTAssertEqual(usageRequestCount, 2)
        XCTAssertEqual(result.snapshot.accountLabel, "refreshed@example.com")
        XCTAssertNotNil(result.refreshedAuthJSON)
        XCTAssertTrue(result.refreshedAuthJSON?.contains("access-refreshed") == true)
        XCTAssertTrue(result.refreshedAuthJSON?.contains("refresh-token-new") == true)
    }

    func testFetchSnapshotPercentEncodesRefreshTokenFormValue() async throws {
        var didAssertRefreshBody = false
        CodexSnapshotMockURLProtocol.requestHandler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://chatgpt.com/backend-api/wham/usage" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
            if url == "https://auth.openai.com/oauth/token" {
                let body = String(data: requestBodyData(request) ?? Data(), encoding: .utf8) ?? ""
                XCTAssertTrue(
                    body.contains("refresh_token=refresh%2Btoken%2Fwith%3Dchars%26space%20value"),
                    "refresh_token form value must be percent encoded; got \(body)"
                )
                didAssertRefreshBody = true
                let responseBody: [String: Any] = [
                    "access_token": "access-refreshed",
                    "refresh_token": "refresh-token-new",
                    "id_token": self.makeIDToken(email: "refreshed@example.com", subject: "sub-refreshed")
                ]
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    try JSONSerialization.data(withJSONObject: responseBody)
                )
            }
            throw URLError(.badURL)
        }

        let service = makeService()
        let descriptor = ProviderDescriptor.defaultOfficialCodex()
        let profile = makeProfile(
            slotID: .a,
            accountID: "team-refresh",
            email: "stale@example.com",
            subject: "sub-stale",
            accessToken: "access-stale",
            refreshToken: "refresh+token/with=chars&space value"
        )

        _ = try? await service.fetchSnapshot(profile: profile, descriptor: descriptor)

        XCTAssertTrue(didAssertRefreshBody)
    }

    private func makeService() -> CodexProfileSnapshotService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexSnapshotMockURLProtocol.self]
        return CodexProfileSnapshotService(session: URLSession(configuration: configuration))
    }

    private func makeProfile(
        slotID: CodexSlotID,
        accountID: String,
        email: String,
        subject: String,
        accessToken: String,
        refreshToken: String
    ) -> CodexAccountProfile {
        let authJSON = sampleAuthJSON(
            accountID: accountID,
            email: email,
            subject: subject,
            accessToken: accessToken,
            refreshToken: refreshToken
        )
        let payload = try! CodexAccountProfileStore.parseAuthJSON(authJSON)
        return CodexAccountProfile(
            slotID: slotID,
            displayName: "Codex \(slotID.rawValue)",
            authJSON: authJSON,
            accountId: accountID,
            accountEmail: email,
            accountSubject: subject,
            tenantKey: payload.tenantKey,
            identityKey: payload.identityKey,
            credentialFingerprint: payload.credentialFingerprint,
            lastImportedAt: Date(),
            isCurrentSystemAccount: false
        )
    }

    private func sampleAuthJSON(
        accountID: String,
        email: String,
        subject: String,
        accessToken: String,
        refreshToken: String
    ) -> String {
        let idToken = makeIDToken(email: email, subject: subject)
        return #"""
        {
          "tokens": {
            "access_token": "\#(accessToken)",
            "refresh_token": "\#(refreshToken)",
            "account_id": "\#(accountID)",
            "id_token": "\#(idToken)"
          }
        }
        """#
    }

    private func makeIDToken(email: String, subject: String) -> String {
        let payload = Data(#"{"email":"\#(email)","sub":"\#(subject)"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }
}

private final class CodexSnapshotMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = CodexSnapshotMockURLProtocol.requestHandler else {
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

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
}
