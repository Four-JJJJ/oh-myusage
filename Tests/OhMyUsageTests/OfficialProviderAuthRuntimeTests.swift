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
}
