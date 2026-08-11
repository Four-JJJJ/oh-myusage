import Foundation
import OhMyUsageDomain
import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class OpenRouterProviderTests: XCTestCase {
    func testParseCreditsSnapshot() throws {
        var descriptor = ProviderDescriptor.defaultOfficialOpenRouterCredits()
        descriptor.threshold = AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        let snapshot = try OpenRouterProvider.parseSnapshot(
            root: [
                "data": [
                    "total_credits": 100.5,
                    "total_usage": 25.25
                ]
            ],
            descriptor: descriptor
        )

        XCTAssertEqual(snapshot.unit, "USD")
        XCTAssertEqual(snapshot.remaining ?? -1, 75.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 25.25, accuracy: 0.001)
        XCTAssertEqual(snapshot.limit ?? -1, 100.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.count, 1)
        XCTAssertEqual(snapshot.quotaWindows.first?.title, "Credits")
        XCTAssertEqual(snapshot.quotaWindows.first?.kind, .credits)
        XCTAssertEqual(snapshot.sourceLabel, "API")
    }

    func testParseAPISnapshotBackfillsLimitFromRemainingAndUsage() throws {
        var descriptor = ProviderDescriptor.defaultOfficialOpenRouterAPI()
        descriptor.threshold = AlertRule(lowRemaining: 20, maxConsecutiveFailures: 2, notifyOnAuthError: true)

        let snapshot = try OpenRouterProvider.parseSnapshot(
            root: [
                "data": [
                    "limit": NSNull(),
                    "limit_remaining": 40,
                    "usage": 10
                ]
            ],
            descriptor: descriptor
        )

        XCTAssertEqual(snapshot.limit ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.remaining ?? -1, 40, accuracy: 0.001)
        XCTAssertEqual(snapshot.used ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(snapshot.quotaWindows.first?.title, "Limit")
    }

    func testParseAPISnapshotFailsWhenLimitCannotBeInferred() {
        let descriptor = ProviderDescriptor.defaultOfficialOpenRouterAPI()

        XCTAssertThrowsError(
            try OpenRouterProvider.parseSnapshot(
                root: ["data": ["usage": 10]],
                descriptor: descriptor
            )
        ) { error in
            guard case let .invalidResponse(detail) = error as? ProviderError else {
                XCTFail("Expected invalidResponse, got \(error)")
                return
            }
            XCTAssertTrue(detail.contains("limit"))
        }
    }

    func testFetchCreditsMaps403ToConfigError() async throws {
        let service = "OhMyUsageTests-OpenRouter-\(UUID().uuidString)"
        let account = "official/openrouter/credits-api-key-\(UUID().uuidString)"
        let keychain = makeTestKeychain()
        XCTAssertTrue(keychain.saveToken("sk-or-v1-test", service: service, account: account))

        var descriptor = ProviderDescriptor.defaultOfficialOpenRouterCredits()
        descriptor.auth = AuthConfig(kind: .bearer, keychainService: service, keychainAccount: account)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenRouterMockURLProtocol.self]
        let session = URLSession(configuration: config)

        OpenRouterMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/credits")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-or-v1-test")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = #"{"error":{"message":"Only management keys can perform this operation"}}"#
            return (response, Data(body.utf8))
        }
        defer { OpenRouterMockURLProtocol.requestHandler = nil }

        let provider = OpenRouterProvider(descriptor: descriptor, session: session, keychain: keychain)

        do {
            _ = try await provider.fetch()
            XCTFail("Expected ProviderError.invalidResponse")
        } catch let error as ProviderError {
            guard case let .invalidResponse(detail) = error else {
                XCTFail("Expected invalidResponse, got \(error)")
                return
            }
            XCTAssertTrue(detail.contains("management key required"))
        }
    }
}

private final class OpenRouterMockURLProtocol: URLProtocol {
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
