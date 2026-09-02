//
//  NetworkReachabilityMonitorTests.swift
//  OhMyUsageTests
//
//  Covers the reachability contract used by the refresh scheduling layer:
//  offline -> online -> offline transitions, callback queue hop, start
//  idempotency, stop behavior, and the absence of retain cycles.
//

import Dispatch
import Foundation
import XCTest
@testable import OhMyUsage

private let testCallbackQueueLabel = "OhMyUsageTests.NetworkReachabilityMonitor.callback"
private let testDeliveryQueueLabel = "OhMyUsageTests.NetworkReachabilityMonitor.delivery"

/// Thread-safe path monitor fake: the test drives path updates manually from
/// whichever thread it wants, mimicking NWPathMonitor's arbitrary delivery
/// threads.
private final class FakeNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _startCount = 0
    private var _cancelCount = 0
    var onPathUpdate: (@Sendable (NetworkPathStatus) -> Void)?

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCount
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cancelCount
    }

    func start() {
        lock.lock()
        _startCount += 1
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        _cancelCount += 1
        lock.unlock()
    }

    func deliver(_ status: NetworkPathStatus) {
        onPathUpdate?(status)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class BoolRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var recorded: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class NetworkReachabilityMonitorTests: XCTestCase {
    private var callbackQueue: DispatchQueue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        callbackQueue = DispatchQueue(label: testCallbackQueueLabel)
    }

    override func tearDownWithError() throws {
        callbackQueue = nil
        try super.tearDownWithError()
    }

    func testInitialStateIsUndeterminedAndOffline() {
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { FakeNetworkPathMonitor() }
        )

        XCTAssertEqual(monitor.pathStatus, .undetermined)
        XCTAssertFalse(monitor.isOnline)
    }

    func testStartResolvesInitialUndeterminedStateFromFirstPathUpdate() {
        let fake = FakeNetworkPathMonitor()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        monitor.onPathChange = { recorder.append($0) }

        monitor.start()
        XCTAssertEqual(fake.startCount, 1)

        fake.deliver(.online(.wifi))
        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .online(.wifi))

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true])
    }

    func testOfflineOnlineOfflineSequenceUpdatesIsOnlineAndCallbackValues() {
        let fake = FakeNetworkPathMonitor()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        monitor.onPathChange = { recorder.append($0) }
        monitor.start()

        // Initial offline observation resolves .undetermined without a
        // callback because the resolved online value does not change.
        fake.deliver(.offline)
        XCTAssertFalse(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .offline)

        fake.deliver(.online(.ethernet))
        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .online(.ethernet))

        fake.deliver(.offline)
        XCTAssertFalse(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .offline)

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true, false])
    }

    func testCallbackFiresOnlyWhenOnlineValueChangesAcrossInterfaceChanges() {
        let fake = FakeNetworkPathMonitor()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        monitor.onPathChange = { recorder.append($0) }
        monitor.start()

        fake.deliver(.online(.wifi))
        fake.deliver(.online(.ethernet))
        fake.deliver(.online(.cellular))

        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .online(.cellular))

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true])
    }

    func testCallbackRunsOnConfiguredQueueNotDeliveryThread() {
        let fake = FakeNetworkPathMonitor()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        let expectedQueue = callbackQueue!
        let deliveryQueue = DispatchQueue(label: testDeliveryQueueLabel)
        let callbackFired = expectation(description: "callback delivered on configured queue")
        monitor.onPathChange = { _ in
            dispatchPrecondition(condition: .onQueue(expectedQueue))
            dispatchPrecondition(condition: .notOnQueue(deliveryQueue))
            XCTAssertFalse(Thread.isMainThread)
            callbackFired.fulfill()
        }
        monitor.start()

        // Deliver from an unrelated background thread, as NWPathMonitor does.
        deliveryQueue.async {
            fake.deliver(.online(.wifi))
        }

        wait(for: [callbackFired], timeout: 5)
    }

    func testDefaultCallbackQueueIsMain() {
        let fake = FakeNetworkPathMonitor()
        let monitor = NetworkReachabilityMonitor(pathMonitorProvider: { fake })
        let callbackFired = expectation(description: "callback delivered on main queue")
        monitor.onPathChange = { _ in
            XCTAssertTrue(Thread.isMainThread)
            callbackFired.fulfill()
        }
        monitor.start()

        fake.deliver(.online(.wifi))

        wait(for: [callbackFired], timeout: 5)
    }

    func testStartIsIdempotentAndDoesNotDuplicateCallbacks() {
        let fake = FakeNetworkPathMonitor()
        let providerCallCount = Counter()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: {
                providerCallCount.increment()
                return fake
            }
        )
        monitor.onPathChange = { recorder.append($0) }

        monitor.start()
        monitor.start()
        monitor.start()

        XCTAssertEqual(providerCallCount.current, 1)
        XCTAssertEqual(fake.startCount, 1)

        fake.deliver(.online(.wifi))
        XCTAssertTrue(monitor.isOnline)

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true])
    }

    func testStopPreventsFurtherCallbacksAndStateUpdates() {
        let fake = FakeNetworkPathMonitor()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        monitor.onPathChange = { recorder.append($0) }
        monitor.start()

        fake.deliver(.online(.wifi))
        XCTAssertTrue(monitor.isOnline)

        monitor.stop()
        XCTAssertEqual(fake.cancelCount, 1)

        fake.deliver(.offline)
        fake.deliver(.online(.cellular))

        // State is frozen at the last observed value once stopped.
        XCTAssertTrue(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .online(.wifi))

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true])
    }

    func testStopWithoutStartIsSafe() {
        let fake = FakeNetworkPathMonitor()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )

        monitor.stop()
        monitor.stop()

        XCTAssertEqual(fake.startCount, 0)
        XCTAssertEqual(fake.cancelCount, 0)
        XCTAssertFalse(monitor.isOnline)
        XCTAssertEqual(monitor.pathStatus, .undetermined)
    }

    func testMonitorRestartsAfterStop() {
        let fake = FakeNetworkPathMonitor()
        let recorder = BoolRecorder()
        let monitor = NetworkReachabilityMonitor(
            callbackQueue: callbackQueue,
            pathMonitorProvider: { fake }
        )
        monitor.onPathChange = { recorder.append($0) }

        monitor.start()
        fake.deliver(.offline)
        monitor.stop()
        XCTAssertEqual(fake.startCount, 1)
        XCTAssertEqual(fake.cancelCount, 1)

        monitor.start()
        XCTAssertEqual(fake.startCount, 2)

        fake.deliver(.online(.wifi))
        XCTAssertTrue(monitor.isOnline)

        drainCallbackQueue()
        XCTAssertEqual(recorder.recorded, [true])
    }

    func testMonitorDeallocatesWithoutRetainCycle() {
        weak var weakMonitor: NetworkReachabilityMonitor?
        weak var weakFake: FakeNetworkPathMonitor?

        do {
            let fake = FakeNetworkPathMonitor()
            let monitor = NetworkReachabilityMonitor(
                callbackQueue: callbackQueue,
                pathMonitorProvider: { fake }
            )
            monitor.start()
            monitor.onPathChange = { _ in }
            weakMonitor = monitor
            weakFake = fake
            XCTAssertNotNil(weakMonitor)
            XCTAssertNotNil(weakFake)
        }
        // The do-scope releases the strong locals: the path update closure
        // only holds a weak reference back to the monitor, so both objects
        // must deallocate even while started.
        XCTAssertNil(weakMonitor)
        XCTAssertNil(weakFake)
    }

    /// Serial queue FIFO guarantees this runs after any callbacks already
    /// dispatched, making the callback assertions deterministic.
    private func drainCallbackQueue(timeout: TimeInterval = 5) {
        let drained = expectation(description: "callback queue drained")
        callbackQueue.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: timeout)
    }
}
