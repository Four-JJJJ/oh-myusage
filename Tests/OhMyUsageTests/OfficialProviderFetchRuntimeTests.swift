import Foundation
import XCTest
import OhMyUsageDomain
import OhMyUsageProviders

final class OfficialProviderFetchRuntimeTests: XCTestCase {
    private func snapshot(at date: Date) -> UsageSnapshot {
        UsageSnapshot(source: "test", status: .ok, remaining: 10, used: 0, limit: 10, unit: "%", updatedAt: date, note: "", sourceLabel: "test")
    }

    func testCapacityUsesRecentAccessAndKeepsStaleSeparateFromFresh() async {
        let now = Date(timeIntervalSince1970: 1000)
        let cache = SnapshotTimestampOfficialSnapshotCache(capacity: 2, maximumStaleAge: 100, now: { now })
        await cache.store(snapshot(at: now.addingTimeInterval(-50)), for: "a")
        await cache.store(snapshot(at: now), for: "b")
        let fresh = await cache.snapshotIfFresh(for: "a", ttl: 10)
        XCTAssertNil(fresh)
        let stale = await cache.snapshotAny(for: "a")
        XCTAssertNotNil(stale)
        await cache.store(snapshot(at: now), for: "c")
        let evicted = await cache.snapshotAny(for: "b")
        XCTAssertNil(evicted)
        await cache.store(snapshot(at: now.addingTimeInterval(-101)), for: "old")
        let expired = await cache.snapshotAny(for: "old")
        XCTAssertNil(expired)
    }

    func testCancellationDoesNotReturnOfflineFallback() async {
        let now = Date().addingTimeInterval(-1)
        let cache = SnapshotTimestampOfficialSnapshotCache()
        await cache.store(snapshot(at: now), for: "a")
        do {
            _ = try await OfficialProviderFetchRuntime.fetch(forceRefresh: false, cacheLookupKey: "a", ttl: 0, cache: cache, gate: PassthroughOfficialFetchGate()) {
                throw CancellationError()
            }
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testWaitingGateCancellationReturnsBeforeHolderCompletes() async throws {
        let gate = SerialOfficialFetchGate()
        let barrier = RuntimeBarrier()
        let holder = Task { try await gate.withPermit { await barrier.wait(); return 1 } }
        while !(await barrier.isWaiting) { await Task.yield() }
        let waiter = Task { try await gate.withPermit { XCTFail("Cancelled waiter executed"); return 2 } }
        for _ in 0..<10 { await Task.yield() }
        waiter.cancel()
        do { _ = try await waiter.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await barrier.release()
        _ = try await holder.value
        let next = try await gate.withPermit { 3 }
        XCTAssertEqual(next, 3)
    }

    func testInvalidationDuringFetchDoesNotRepopulateCache() async throws {
        let cache = FetchedAtOfficialSnapshotCache()
        let barrier = RuntimeBarrier()
        let value = snapshot(at: Date())
        let task = Task {
            try await OfficialProviderFetchRuntime.fetch(forceRefresh: true, cacheLookupKey: "a", ttl: 10, cache: cache, gate: PassthroughOfficialFetchGate()) {
                await barrier.wait()
                return value
            }
        }
        while !(await barrier.isWaiting) { await Task.yield() }
        OfficialProviderFetchRuntime.invalidateCaches()
        await barrier.release()
        _ = try await task.value
        let cached = await cache.snapshotAny(for: "a")
        XCTAssertNil(cached)
    }

    func testDelayedTaggedStoreRejectsInvalidatedLoadEpoch() async {
        let cache = FetchedAtOfficialSnapshotCache()
        let generation = OfficialProviderFetchRuntime.cacheGeneration
        OfficialProviderFetchRuntime.invalidateCaches()
        await cache.store(snapshot(at: Date()), for: "late", generation: generation)
        let value = await cache.snapshotAny(for: "late")
        XCTAssertNil(value)
    }

    func testFutureTimestampCannotBecomeFreshAfterClockReversal() async {
        let now = Date(timeIntervalSince1970: 1000)
        let cache = SnapshotTimestampOfficialSnapshotCache(now: { now })
        await cache.store(snapshot(at: now.addingTimeInterval(1)), for: "future")
        let fresh = await cache.snapshotIfFresh(for: "future", ttl: 60)
        XCTAssertNil(fresh)
        let fallback = await cache.snapshotAny(for: "future")
        XCTAssertNil(fallback)
    }

    func testRateLimitFallbackRetainsDeadline() async throws {
        let cache = SnapshotTimestampOfficialSnapshotCache()
        await cache.store(snapshot(at: Date().addingTimeInterval(-10)), for: "a")
        let deadline = Date().addingTimeInterval(3600)
        let result = try await OfficialProviderFetchRuntime.fetch(forceRefresh: false, cacheLookupKey: "a", ttl: 0, cache: cache, gate: PassthroughOfficialFetchGate()) {
            throw ProviderRateLimitError(retryNotBefore: deadline)
        }
        XCTAssertEqual(result.valueFreshness, .cachedFallback)
        XCTAssertEqual(result.fetchHealth, .rateLimited)
        XCTAssertEqual(result.rawMeta["provider.retryNotBefore"], String(deadline.timeIntervalSince1970))
    }

    func testAlreadyCancelledGateDoesNotExecuteOperation() async {
        let gate = SerialOfficialFetchGate()
        let task = Task {
            try await Task.sleep(for: .seconds(60))
            return try await gate.withPermit { XCTFail("Cancelled operation executed"); return 1 }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        do {
            let result = try await gate.withPermit { 2 }
            XCTAssertEqual(result, 2)
        } catch { XCTFail("Permit leaked") }
    }

    func testRetryAfterSecondsDateAndInvalidInput() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProviderRateLimitError.parseRetryAfter("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(ProviderRateLimitError.parseRetryAfter("Thu, 01 Jan 1970 00:02:00 GMT", now: now), now.addingTimeInterval(120))
        XCTAssertNil(ProviderRateLimitError.parseRetryAfter("-1", now: now))
        XCTAssertNil(ProviderRateLimitError.parseRetryAfter("nan", now: now))
        XCTAssertNil(ProviderRateLimitError.parseRetryAfter("1e308", now: now))
        XCTAssertNil(ProviderRateLimitError.parseRetryAfter("bad", now: now))
        XCTAssertNil(ProviderRateLimitError.parseRetryAfter("Thu, 01 Jan 1970 00:00:00 GMT", now: now.addingTimeInterval(1)))
        XCTAssertEqual(ProviderRateLimitError.parseRetryAfter("99999999", now: now), now.addingTimeInterval(99999999))
    }
}

private actor RuntimeBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
