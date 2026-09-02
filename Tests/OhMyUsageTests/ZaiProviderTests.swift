import Foundation
import OhMyUsageDomain
import OhMyUsageProviders
import XCTest
@testable import OhMyUsage

/// Request-count, mirror-retry, and partial-failure semantics of
/// `ZaiProvider` (optimization doc §8.4 Z.ai / §8.5): quota and subscription
/// are cached separately with distinct keys, a subscription failure must not
/// hide quota data, Coding Plan and API Balance use different cache keys, and
/// mirror retries stop after one attempt (429 stops immediately).
final class ZaiProviderTests: XCTestCase {
    private let quotaPath = "/api/monitor/usage/quota/limit"
    private let subscriptionPath = "/api/biz/subscription/list"
    private let balancePath = "/api/biz/account/query-customer-account-report"

    // MARK: - Separate quota / subscription caches

    func testRepeatedRefreshReusesSubscriptionMetadataWithoutReissuingSubscriptionRequest() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            if url.path == subscriptionPath {
                counter.increment("subscription")
                return (Self.httpOK(url), Data(Self.subscriptionBody(plan: "GLM Coding Max").utf8))
            }
            XCTAssertEqual(url.path, quotaPath)
            counter.increment("quota")
            return (Self.httpOK(url), Data(Self.quotaBody().utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)

        let first = try await provider.fetch()
        XCTAssertEqual(counter.value("quota"), 1)
        XCTAssertEqual(counter.value("subscription"), 1)
        XCTAssertEqual(first.extras["planType"], "GLM Coding Max")

        // Force refresh reloads the quota data but the subscription metadata
        // cache (separate key, longer TTL) is still fresh.
        let second = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(counter.value("quota"), 2, "quota data must be reloaded on force refresh")
        XCTAssertEqual(counter.value("subscription"), 1, "fresh subscription metadata must not be refetched")
        XCTAssertEqual(second.extras["planType"], "GLM Coding Max")

        // Non-forced fetch with the (zero) snapshot TTL reloads the quota data
        // but must still not touch the subscription endpoint.
        _ = try await provider.fetch()
        XCTAssertEqual(counter.value("quota"), 3)
        XCTAssertEqual(counter.value("subscription"), 1)
    }

    func testSubscriptionFailureDoesNotHideQuotaAndRecordsDiagnostic() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            if url.path == subscriptionPath {
                counter.increment("subscription")
                return (Self.httpResponse(url: url, statusCode: 500), Data())
            }
            XCTAssertEqual(url.path, quotaPath)
            counter.increment("quota")
            return (Self.httpOK(url), Data(Self.quotaBody().utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)
        let snapshot = try await provider.fetch()

        XCTAssertEqual(counter.value("quota"), 1)
        XCTAssertEqual(snapshot.quotaWindows.count, 2, "valid quota data must still be returned")
        XCTAssertEqual(snapshot.remaining ?? -1, 55, accuracy: 0.001)
        XCTAssertEqual(snapshot.extras["planType"], "unknown")
        XCTAssertEqual(
            snapshot.diagnosticCode,
            "endpoint-misconfigured",
            "partial subscription failure must be surfaced via the existing diagnosticCode vocabulary"
        )
    }

    func testSubscriptionFailureFallsBackToStaleCachedMetadata() async throws {
        let counter = ProviderRequestCounter()
        let subscriptionFails = MutableFlag(initialValue: false)
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            if url.path == subscriptionPath {
                counter.increment("subscription")
                if subscriptionFails.value {
                    return (Self.httpResponse(url: url, statusCode: 500), Data())
                }
                return (Self.httpOK(url), Data(Self.subscriptionBody(plan: "GLM Coding Max").utf8))
            }
            XCTAssertEqual(url.path, quotaPath)
            counter.increment("quota")
            return (Self.httpOK(url), Data(Self.quotaBody().utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        // Injectable clock so the subscription metadata is guaranteed stale on
        // fetch 2 and the (now failing) endpoint is actually consulted.
        let clock = MutableTestClock(now: Date())
        let provider = makeCodingPlanProvider(
            subscriptionCache: ZaiSubscriptionMetadataCache(ttl: 60, now: { clock.now() }),
            quotaCacheTTL: 0
        )
        let first = try await provider.fetch()
        XCTAssertEqual(first.extras["planType"], "GLM Coding Max")
        XCTAssertNil(first.diagnosticCode)

        clock.advance(by: 120)
        subscriptionFails.setValue(true)
        let second = try await provider.fetch(forceRefresh: true)

        XCTAssertEqual(counter.value("quota"), 2)
        XCTAssertEqual(counter.value("subscription"), 3, "fetch 2 attempts the primary host plus its mirror once")
        XCTAssertEqual(
            second.extras["planType"],
            "GLM Coding Max",
            "failed subscription refresh must reuse the cached plan metadata"
        )
        XCTAssertNotNil(second.diagnosticCode, "the partial failure must still be recorded")
    }

    // MARK: - Mirror retry policy

    func testRateLimitedQuotaDoesNotRetryOnMirror() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            counter.increment("total")
            XCTAssertTrue(url.absoluteString.hasPrefix("https://api.z.ai"))
            return (Self.httpResponse(url: url, statusCode: 429), Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)
        do {
            _ = try await provider.fetch()
            XCTFail("expected a rate limited error")
        } catch let error as ProviderError {
            guard case .rateLimited = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
        }

        XCTAssertEqual(
            counter.value("total"),
            1,
            "429 must stop immediately: no mirror request may be issued"
        )
    }

    func testGenericFailureRetriesMirrorAtMostOnce() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            counter.increment("total")
            return (Self.httpResponse(url: url, statusCode: 500), Data())
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)
        do {
            _ = try await provider.fetch()
            XCTFail("expected an invalid response error")
        } catch let error as ProviderError {
            guard case .invalidResponse = error else {
                return XCTFail("unexpected provider error: \(error)")
            }
        }

        XCTAssertEqual(
            counter.value("total"),
            2,
            "primary host plus one mirror attempt; no further retries"
        )
    }

    func testGenericFailureFallsBackToMirrorOnceAndSucceeds() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            if url.path == quotaPath {
                counter.increment("quota")
                if url.absoluteString.hasPrefix("https://api.z.ai") {
                    return (Self.httpResponse(url: url, statusCode: 500), Data())
                }
                return (Self.httpOK(url), Data(Self.quotaBody().utf8))
            }
            XCTAssertEqual(url.path, subscriptionPath)
            counter.increment("subscription")
            return (Self.httpOK(url), Data(Self.subscriptionBody(plan: "GLM Coding Max").utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)
        let snapshot = try await provider.fetch()

        XCTAssertEqual(counter.value("quota"), 2, "one primary attempt plus one mirror attempt")
        XCTAssertEqual(snapshot.remaining ?? -1, 55, accuracy: 0.001)
    }

    func testAppLevelAuthFailureRetriesMirrorOnce() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            if url.path == quotaPath {
                counter.increment("quota")
                if url.absoluteString.hasPrefix("https://api.z.ai") {
                    // 这组端点对无效 key 返回 HTTP 200 + body code 401。
                    return (Self.httpOK(url), Data(#"{"success":false,"code":401}"#.utf8))
                }
                return (Self.httpOK(url), Data(Self.quotaBody().utf8))
            }
            XCTAssertEqual(url.path, subscriptionPath)
            counter.increment("subscription")
            return (Self.httpOK(url), Data(Self.subscriptionBody(plan: "GLM Coding Max").utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeCodingPlanProvider(quotaCacheTTL: 0)
        let snapshot = try await provider.fetch()

        XCTAssertEqual(counter.value("quota"), 2, "app-level auth failure retries the mirror exactly once")
        XCTAssertEqual(snapshot.remaining ?? -1, 55, accuracy: 0.001)
    }

    // MARK: - Distinct cache keys

    func testCodingPlanBalanceAndSubscriptionUseDistinctCacheKeys() {
        let descriptor = ProviderDescriptor.defaultOfficialZai()

        XCTAssertNotEqual(
            ZaiProvider.codingPlanSnapshotCacheKey(descriptor: descriptor, apiKey: "key-a"),
            ZaiProvider.balanceSnapshotCacheKey(descriptor: descriptor, apiKey: "key-a"),
            "Coding Plan and API Balance must use different cache keys"
        )
        XCTAssertNotEqual(
            ZaiProvider.codingPlanSnapshotCacheKey(descriptor: descriptor, apiKey: "key-a"),
            ZaiProvider.subscriptionCacheKey(descriptor: descriptor, apiKey: "key-a")
        )
        XCTAssertNotEqual(
            ZaiProvider.balanceSnapshotCacheKey(descriptor: descriptor, apiKey: "key-a"),
            ZaiProvider.subscriptionCacheKey(descriptor: descriptor, apiKey: "key-a")
        )
        XCTAssertNotEqual(
            ZaiProvider.codingPlanSnapshotCacheKey(descriptor: descriptor, apiKey: "key-a"),
            ZaiProvider.codingPlanSnapshotCacheKey(descriptor: descriptor, apiKey: "key-b"),
            "cache keys must not be reused across accounts"
        )
        XCTAssertGreaterThan(
            ZaiProvider.subscriptionMetadataTTL,
            15,
            "subscription metadata TTL must be longer than the quota snapshot TTL"
        )
    }

    func testBalanceSnapshotFetchSupportsForceRefreshAndSeparateCaching() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [balancePath] request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, balancePath)
            counter.increment("balance")
            return (Self.httpOK(url), Data(#"{"success":true,"data":{"balance":42.5,"currency":"CNY"}}"#.utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        let provider = makeBalanceProvider(quotaCacheTTL: 0)
        let first = try await provider.fetch()
        XCTAssertEqual(first.remaining ?? -1, 42.5, accuracy: 0.001)

        _ = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(counter.value("balance"), 2)
    }

    func testSnapshotCacheDoesNotCrossAccounts() async throws {
        let counter = ProviderRequestCounter()
        OfficialMockURLProtocol.requestHandler = { [quotaPath, subscriptionPath] request in
            let url = try XCTUnwrap(request.url)
            let apiKey = request.value(forHTTPHeaderField: "Authorization")
            if url.path == subscriptionPath {
                counter.increment("subscription")
                return (Self.httpOK(url), Data(Self.subscriptionBody(plan: "GLM Coding Max").utf8))
            }
            XCTAssertEqual(url.path, quotaPath)
            counter.increment("quota")
            let (percent, weeklyPercent) = apiKey == "key-b" ? (45.0, 75.0) : (15.0, 20.0)
            return (Self.httpOK(url), Data(Self.quotaBody(percent: percent, weeklyPercent: weeklyPercent).utf8))
        }
        defer { OfficialMockURLProtocol.requestHandler = nil }

        // Both providers share the same process-wide caches; only the
        // account-scoped cache keys may separate their data.
        let sharedSnapshotCache = SnapshotTimestampOfficialSnapshotCache()
        let sharedSubscriptionCache = ZaiSubscriptionMetadataCache()
        let providerA = makeCodingPlanProvider(
            cache: sharedSnapshotCache,
            subscriptionCache: sharedSubscriptionCache,
            apiKey: "key-a"
        )
        let providerB = makeCodingPlanProvider(
            cache: sharedSnapshotCache,
            subscriptionCache: sharedSubscriptionCache,
            apiKey: "key-b"
        )

        let firstA = try await providerA.fetch()
        XCTAssertEqual(firstA.remaining ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(counter.value("quota"), 1)

        let firstB = try await providerB.fetch()
        XCTAssertEqual(firstB.remaining ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(counter.value("quota"), 2, "account B must not reuse account A's cached snapshot")

        let secondA = try await providerA.fetch()
        XCTAssertEqual(secondA.remaining ?? -1, 80, accuracy: 0.001, "account A's cached entry must be untouched")
        XCTAssertEqual(counter.value("quota"), 2)
        XCTAssertEqual(
            counter.value("subscription"),
            2,
            "each account loaded its own subscription metadata once; neither refetched"
        )
    }

    // MARK: - Helpers

    private func makeCodingPlanProvider(
        cache: any OfficialSnapshotCaching = SnapshotTimestampOfficialSnapshotCache(),
        subscriptionCache: ZaiSubscriptionMetadataCache = ZaiSubscriptionMetadataCache(),
        apiKey: String = "coding-plan-key",
        quotaCacheTTL: TimeInterval = 15
    ) -> ZaiProvider {
        var descriptor = ProviderDescriptor.defaultOfficialZai()
        descriptor.id = "zai-official"
        return ZaiProvider(
            descriptor: descriptor,
            session: makeMockSession(),
            keychain: FixedTokenCredentialStore(token: apiKey),
            localJSONReader: NilLocalJSONFileReader(),
            cache: cache,
            gate: PassthroughOfficialFetchGate(),
            subscriptionCache: subscriptionCache,
            environment: [:],
            quotaCacheTTL: quotaCacheTTL
        )
    }

    private func makeBalanceProvider(quotaCacheTTL: TimeInterval) -> ZaiProvider {
        var descriptor = ProviderDescriptor.defaultOfficialZaiBalance()
        descriptor.id = "zai-balance-official"
        return ZaiProvider(
            descriptor: descriptor,
            session: makeMockSession(),
            keychain: FixedTokenCredentialStore(token: "balance-key"),
            localJSONReader: NilLocalJSONFileReader(),
            cache: SnapshotTimestampOfficialSnapshotCache(),
            gate: PassthroughOfficialFetchGate(),
            subscriptionCache: ZaiSubscriptionMetadataCache(),
            environment: [:],
            quotaCacheTTL: quotaCacheTTL
        )
    }

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfficialMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func httpOK(_ url: URL) -> HTTPURLResponse {
        httpResponse(url: url, statusCode: 200)
    }

    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private static func quotaBody(percent: Double = 15, weeklyPercent: Double = 45) -> String {
        """
        {
          "data": {
            "limits": [
              {"type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": \(percent), "nextResetTime": 1770648402389},
              {"type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": \(weeklyPercent), "nextResetTime": 1771200000000}
            ]
          }
        }
        """
    }

    private static func subscriptionBody(plan: String) -> String {
        """
        {"data": [{"productName": "\(plan)", "inCurrentPeriod": true, "nextRenewTime": "2026-05-12"}]}
        """
    }
}

/// Thread-safe boolean flag controllable from the mock handler.
private final class MutableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var valueStorage: Bool

    init(initialValue: Bool) {
        valueStorage = initialValue
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valueStorage
    }

    func setValue(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        valueStorage = newValue
    }
}

/// Injectable clock for TTL-controlled caches.
private final class MutableTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) {
        current = now
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

/// `LocalJSONFileReading` stub that never discovers credentials from local
/// files, keeping tests isolated from the machine's real `~/.claude` config.
private struct NilLocalJSONFileReader: LocalJSONFileReading {
    func dictionary(atPath path: String) -> [String: Any]? {
        nil
    }

    func text(atPath path: String) -> String? {
        nil
    }
}

/// `TokenCredentialStoring` stub serving a single fixed token for every
/// lookup (models a manually saved API key).
private final class FixedTokenCredentialStore: TokenCredentialStoring, @unchecked Sendable {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func readToken(service: String, account: String) -> String? {
        token
    }

    @discardableResult
    func saveToken(_ token: String, service: String, account: String) -> Bool {
        true
    }

    @discardableResult
    func deleteToken(service: String, account: String) -> Bool {
        true
    }
}

private final class OfficialMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = OfficialMockURLProtocol.requestHandler else {
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
