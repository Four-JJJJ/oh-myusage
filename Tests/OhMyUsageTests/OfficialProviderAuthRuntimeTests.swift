import XCTest
@testable import OhMyUsage
import OhMyUsageProviders

final class OfficialProviderAuthRuntimeTests: XCTestCase {
    func testRequestWithExpiringCredentialRefreshRefreshesBeforeRequest() async throws {
        var events: [String] = []

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: 1,
            shouldRefresh: { value in
                events.append("shouldRefresh:\(value)")
                return true
            },
            request: { value in
                events.append("request:\(value)")
                return "ok-\(value)"
            },
            refresh: { value in
                events.append("refresh:\(value)")
                return value + 1
            }
        )

        XCTAssertEqual(events, ["shouldRefresh:1", "refresh:1", "request:2"])
        XCTAssertEqual(result.state, 2)
        XCTAssertEqual(result.response, "ok-2")
        XCTAssertTrue(result.didRefresh)
    }

    func testRequestWithExpiringCredentialRefreshRetriesUnauthorizedWithLatestState() async throws {
        var events: [String] = []

        let result = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
            initialState: 10,
            shouldRefresh: { value in
                events.append("shouldRefresh:\(value)")
                return false
            },
            request: { value in
                events.append("request:\(value)")
                if value == 10 {
                    throw ProviderError.unauthorized
                }
                return "ok-\(value)"
            },
            refresh: { value in
                events.append("refresh:\(value)")
                return value + 5
            }
        )

        XCTAssertEqual(events, ["shouldRefresh:10", "request:10", "refresh:10", "request:15"])
        XCTAssertEqual(result.state, 15)
        XCTAssertEqual(result.response, "ok-15")
        XCTAssertTrue(result.didRefresh)
    }

    func testRequestWithExpiringCredentialRefreshKeepsNonUnauthorizedErrors() async throws {
        do {
            _ = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
                initialState: 1,
                shouldRefresh: { _ in false },
                request: { _ in throw ProviderError.rateLimited },
                refresh: { value in value + 1 }
            ) as OfficialProviderAuthRequestResult<Int, String>
            XCTFail("Expected rateLimited")
        } catch let error as ProviderError {
            guard case .rateLimited = error else {
                return XCTFail("Unexpected provider error: \(error)")
            }
        }
    }

    func testRequestWithExpiringCredentialRefreshPropagatesRefreshFailure() async throws {
        var events: [String] = []

        do {
            _ = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
                initialState: 1,
                shouldRefresh: { _ in false },
                request: { value in
                    events.append("request:\(value)")
                    throw ProviderError.unauthorized
                },
                refresh: { value in
                    events.append("refresh:\(value)")
                    throw ProviderError.missingCredential("refresh-token")
                }
            ) as OfficialProviderAuthRequestResult<Int, String>
            XCTFail("Expected refresh failure")
        } catch let error as ProviderError {
            guard case let .missingCredential(path) = error else {
                return XCTFail("Unexpected provider error: \(error)")
            }
            XCTAssertEqual(path, "refresh-token")
        }

        XCTAssertEqual(events, ["request:1", "refresh:1"])
    }

    func testRequestWithExpiringCredentialRefreshPropagatesRetryUnauthorized() async throws {
        var events: [String] = []

        do {
            _ = try await OfficialProviderAuthRuntime.requestWithExpiringCredentialRefresh(
                initialState: 1,
                shouldRefresh: { _ in false },
                request: { value in
                    events.append("request:\(value)")
                    throw ProviderError.unauthorized
                },
                refresh: { value in
                    events.append("refresh:\(value)")
                    return value + 1
                }
            ) as OfficialProviderAuthRequestResult<Int, String>
            XCTFail("Expected retry unauthorized")
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                return XCTFail("Unexpected provider error: \(error)")
            }
        }

        XCTAssertEqual(events, ["request:1", "refresh:1", "request:2"])
    }

    func testRequestOAuthRefreshMaps429WithRetryAfterToProviderRateLimitError() async throws {
        let startedAt = Date()
        let session = makeMockSession(statusCode: 429, headers: ["Retry-After": "90"])

        do {
            _ = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
                session: session,
                request: URLRequest(url: URL(string: "https://auth.example.com/token")!),
                invalidResponseMessage: "refresh invalid response",
                missingAccessTokenMessage: "missing refresh access_token",
                httpErrorMessage: { "refresh http \($0)" }
            )
            XCTFail("Expected ProviderRateLimitError")
        } catch let error as ProviderRateLimitError {
            XCTAssertEqual(
                error.retryNotBefore.timeIntervalSince(startedAt),
                90,
                accuracy: 5
            )
        } catch {
            XCTFail("Expected ProviderRateLimitError, got \(error)")
        }
    }

    func testRequestOAuthRefreshKeepsUnauthorizedStatusCodesAndCustomMessage() async throws {
        let session = makeMockSession(statusCode: 400, headers: nil)

        do {
            _ = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
                session: session,
                request: URLRequest(url: URL(string: "https://auth.example.com/token")!),
                invalidResponseMessage: "refresh invalid response",
                missingAccessTokenMessage: "missing refresh access_token",
                httpErrorMessage: { "refresh http \($0)" }
            )
            XCTFail("Expected unauthorized")
        } catch let error as ProviderError {
            guard case .unauthorized = error else {
                return XCTFail("Expected unauthorized, got \(error)")
            }
        }

        let invalidSession = makeMockSession(statusCode: 404, headers: nil)
        do {
            _ = try await OfficialProviderAuthRuntime.requestOAuthRefresh(
                session: invalidSession,
                request: URLRequest(url: URL(string: "https://auth.example.com/token")!),
                invalidResponseMessage: "refresh invalid response",
                missingAccessTokenMessage: "missing refresh access_token",
                httpErrorMessage: { "refresh http \($0)" }
            )
            XCTFail("Expected invalidResponse")
        } catch let error as ProviderError {
            guard case .invalidResponse(let detail) = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
            XCTAssertEqual(detail, "refresh http 404")
        }
    }

    private func makeMockSession(statusCode: Int, headers: [String: String]?) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthRuntimeMockURLProtocol.self]
        AuthRuntimeMockURLProtocol.response = HTTPURLResponse(
            url: URL(string: "https://auth.example.com/token")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return URLSession(configuration: configuration)
    }
}

private final class AuthRuntimeMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: HTTPURLResponse?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
