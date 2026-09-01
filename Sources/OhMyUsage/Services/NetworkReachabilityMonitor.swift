//
//  NetworkReachabilityMonitor.swift
//  OhMyUsage
//
//  Tracks device network reachability on top of NWPathMonitor (Network
//  framework) for the refresh scheduling layer.
//
//  Intended scheduling behavior:
//    - While offline, pause ordinary background refresh instead of letting
//      every provider request run into long network timeouts.
//    - Manual refresh can consult `isOnline` to fail fast with a clear
//      offline state.
//    - When the network recovers, the scheduler refreshes only stale, visible
//      providers; this monitor never triggers a refresh fan-out by itself.
//
//  Implementation notes:
//    - No network requests are performed here; the monitor only observes
//      `NWPathMonitor` path updates.
//    - `NWPathMonitor` delivers updates on arbitrary system threads. All
//      mutable state is guarded by a lock, and `onPathChange` is always
//      dispatched asynchronously to the queue passed at init (main by
//      default), so observers never execute on NWPathMonitor's internal
//      thread.
//    - `onPathChange` fires only when the resolved online/offline value
//      changes, which keeps a network recovery from fanning out into
//      duplicate refresh work.
//

import Foundation
import Network

// MARK: - Value types

/// Coarse-grained interface kind behind the current online path.
enum NetworkPathInterface: Equatable, Sendable {
    case ethernet
    case wifi
    case cellular
    case other
}

/// Reachability state derived from the current network path.
enum NetworkPathStatus: Equatable, Sendable {
    case online(NetworkPathInterface)
    case offline
    case undetermined
}

// MARK: - Injection seam

/// Abstraction over the system path monitor so tests can inject fake paths.
///
/// Conforming implementations must invoke `onPathUpdate` with the current
/// path shortly after `start()` and then on every subsequent path change.
/// Updates may be delivered from any thread; `NetworkReachabilityMonitor`
/// re-dispatches them onto its callback queue.
protocol NetworkPathMonitoring: AnyObject, Sendable {
    var onPathUpdate: (@Sendable (NetworkPathStatus) -> Void)? { get set }
    func start()
    func cancel()
}

// MARK: - Monitor

/// Observes network reachability and exposes a thread-safe online/offline
/// snapshot plus a change callback on a caller-chosen queue.
///
/// `isOnline` is `false` until a path update resolves the initial
/// `.undetermined` state, which happens immediately after `start()` because
/// `NWPathMonitor` reports the current path right away.
final class NetworkReachabilityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let callbackQueue: DispatchQueue
    private let pathMonitorProvider: @Sendable () -> any NetworkPathMonitoring

    private var pathMonitor: (any NetworkPathMonitoring)?
    private var status: NetworkPathStatus = .undetermined
    private var online = false
    private var running = false
    private var changeHandler: (@Sendable (Bool) -> Void)?

    /// `false` until the first path update resolves the initial
    /// `.undetermined` state. Frozen at the last observed value after
    /// `stop()`.
    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    /// Latest resolved path status; `.undetermined` before the first update.
    var pathStatus: NetworkPathStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    /// Invoked on the queue passed at init (main by default) whenever the
    /// resolved online/offline value changes, including the transition out of
    /// the initial `.undetermined` state. Never invoked on the path monitor's
    /// internal thread. Safe to set before or after `start()`.
    var onPathChange: (@Sendable (Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return changeHandler
        }
        set {
            lock.lock()
            changeHandler = newValue
            lock.unlock()
        }
    }

    init(
        callbackQueue: DispatchQueue = .main,
        pathMonitorProvider: @escaping @Sendable () -> any NetworkPathMonitoring = { NWPathMonitorAdapter() }
    ) {
        self.callbackQueue = callbackQueue
        self.pathMonitorProvider = pathMonitorProvider
    }

    /// Begins observing path updates. Idempotent: repeated calls while
    /// running are ignored and never create additional path monitors. Can be
    /// called again after `stop()` to restart observation.
    func start() {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        let monitor = pathMonitorProvider()
        lock.lock()
        guard running else {
            // stop() raced with start(); tear the fresh monitor back down.
            lock.unlock()
            monitor.cancel()
            return
        }
        pathMonitor = monitor
        monitor.onPathUpdate = { [weak self] status in
            self?.handlePathUpdate(status)
        }
        lock.unlock()
        monitor.start()
    }

    /// Stops observing. Further path updates are ignored and no longer
    /// produce callbacks. Safe to call without a prior `start()` or multiple
    /// times in a row.
    func stop() {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        let seam = pathMonitor
        pathMonitor = nil
        lock.unlock()

        seam?.onPathUpdate = nil
        seam?.cancel()
    }

    /// Called on whatever thread the seam delivered the update from.
    private func handlePathUpdate(_ newStatus: NetworkPathStatus) {
        var notifyValue = false
        var handler: (@Sendable (Bool) -> Void)?

        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        status = newStatus
        let isNowOnline: Bool
        if case .online = newStatus {
            isNowOnline = true
        } else {
            isNowOnline = false
        }
        if isNowOnline != online {
            online = isNowOnline
            notifyValue = isNowOnline
            handler = changeHandler
        }
        lock.unlock()

        guard let handler else { return }
        callbackQueue.async {
            handler(notifyValue)
        }
    }
}

// MARK: - Production adapter

/// `NetworkPathMonitoring` backed by the real `NWPathMonitor`. A canceled
/// `NWPathMonitor` cannot restart, so `start()` recreates one when needed.
private final class NWPathMonitorAdapter: NetworkPathMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private let monitorQueue = DispatchQueue(label: "OhMyUsage.NWPathMonitorAdapter", qos: .utility)
    private var monitor: NWPathMonitor?
    private var deliveryHandler: (@Sendable (NetworkPathStatus) -> Void)?

    var onPathUpdate: (@Sendable (NetworkPathStatus) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return deliveryHandler
        }
        set {
            lock.lock()
            deliveryHandler = newValue
            lock.unlock()
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.emit(Self.resolveStatus(from: path))
        }
        self.monitor = monitor
        monitor.start(queue: monitorQueue)
    }

    func cancel() {
        lock.lock()
        let monitor = self.monitor
        self.monitor = nil
        lock.unlock()
        monitor?.cancel()
    }

    /// Invoked on `monitorQueue`; reads the handler under the lock and calls
    /// it outside the lock so the seam never holds its lock while the owner
    /// runs.
    private func emit(_ status: NetworkPathStatus) {
        lock.lock()
        let handler = deliveryHandler
        lock.unlock()
        handler?(status)
    }

    private static func resolveStatus(from path: NWPath) -> NetworkPathStatus {
        guard path.status == .satisfied else { return .offline }
        if path.usesInterfaceType(.wiredEthernet) { return .online(.ethernet) }
        if path.usesInterfaceType(.wifi) { return .online(.wifi) }
        if path.usesInterfaceType(.cellular) { return .online(.cellular) }
        return .online(.other)
    }
}
